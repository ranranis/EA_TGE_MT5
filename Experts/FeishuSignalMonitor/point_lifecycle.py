"""TGA9：同价唯一候选、独立来源期限和可追溯撤销；不发送交易。"""
import copy
import hashlib
import json
import math
import re
from datetime import datetime, timedelta, timezone
from store import state, set_state
from teacher_scene import cancels_plan

TZ=timezone(timedelta(hours=8))

def expiry(row, text, applied):
    # 每条依据独立计时；支撑重申不能延长旧明确指令。
    hours=24
    if row[6]=='MANUAL' and applied:
        key=row[9].removeprefix('EDITOR|')
        draft=applied['draft']
        if key.startswith('level-'):
            item=next((p for p in draft['levels'] if 'level-'+p['id']==key),{})
        else:
            item=draft.get(key.rsplit('-',1)[0],{})
        hours=item.get('hours',24)
    elif row[2] in ('INNER','OUTER','MAP'):
        # 声明的跨日时间仅作用于区间/地图，不给所有短线指令续期。
        days=None
        match=re.search(r'(?:接下来|未来|今后|有效期(?:为)?)[\s：:]*(\d{1,2})\s*天',text)
        if match and 1<=int(match[1])<=30: days=int(match[1])
        elif re.search(r'(?:接下来|未来|今后)\s*半个月',text): days=15
        elif re.search(r'(?:接下来|未来|今后)\s*(?:两|二)天',text): days=2
        if days: hours=days*24
        elif re.search(r'本周(?:有效|区间|点位)|本周.*(?:区间|点位).*有效',text):
            date=datetime.fromtimestamp(row[14],TZ)
            return int((date.replace(hour=0,minute=0,second=0,microsecond=0)+timedelta(days=7-date.weekday())).timestamp())
        elif re.search(r'(?:仅限|有效期至|有效到)\s*(?:今天|今日)',text):
            date=datetime.fromtimestamp(row[14],TZ)
            return int((date.replace(hour=0,minute=0,second=0,microsecond=0)+timedelta(days=1)).timestamp())
    return int(row[14]+(180 if row[15]=='MARKET' else hours*3600))

def lifecycle_rows(db,c,rows,now,applied_override=None,persist=True):
    """先撤销/替换再排序；同价旧反向依据永久退役，重发旧来源不能复活。"""
    scope=[c['chat_id'],c['teacher_sender_id'],c['symbols'][c['teacher_symbol']]]
    saved=copy.deepcopy(state(db,'point_lifecycle',{}))
    if saved.get('scope')!=scope: saved=dict(scope=scope,retired={},points=[],events=[])
    retired=saved['retired']
    applied=applied_override if applied_override is not None else state(db,'point_editor',{}).get('applied')
    messages={r['message_id']:dict(r) for r in db.execute(
        'SELECT *,rowid AS sequence FROM messages WHERE chat_id=? AND created<=?',
        (c['chat_id'],now+5))}
    teachers=[r for r in messages.values() if r['sender']==c['teacher_sender_id'] and not r['historical'] and not r['deleted']]
    teachers.sort(key=lambda r:(r['created'],r['sequence']))
    deleted=set(applied['draft'].get('deleted', [])) if applied and applied['draft']['mode']!='auto' else set()
    groups={}
    for original in rows:
        if float(original[5]) in deleted: continue
        r=copy.deepcopy(original)
        source=messages.get(r[6],{})
        text=json.loads(source['raw']).get('content','') if source else ''
        if not isinstance(text,str): text=''
        authority=3 if r[6]=='MANUAL' else 2 if source.get('sender')==c['teacher_sender_id'] else 1
        key=r[1]+'|'+str(r[14])  # 新明确确认可恢复；心跳/备注不能。
        item=dict(row=r,key=key,authority=authority,sequence=source.get('sequence',0),
                  expires=expiry(r,text,applied),text=text[:240],state='READY',reason='有效参考')
        if r[2]=='WATCH': item.update(state='WATCH',reason='仅展示：条件或退出参考')
        for message in teachers:
            if message['created']<=r[14]: continue
            raw=json.loads(message['raw']); body=raw.get('content','')
            if not isinstance(body,str): continue
            whole=bool(re.search(r'(?:旧|之前|此前|原来)(?:的)?(?:全部|所有|整组|整套)?(?:点位|计划|参考).*?(?:作废|取消|不用)|(?:全部|所有|整组)(?:点位|计划|参考).*?(?:作废|取消)',body))
            cancel=whole or any(cancels_plan(dict(text=body),dict(side=side,price=float(r[5]),token=format(float(r[5]),'g')))
                               for side in (('BUY','SELL') if r[4]=='AUTO' else (r[4],)))
            # 明确改价且新SETUP已核验：替换同方向旧直接计划，不能删除其他方向。
            changed=False
            if r[2]=='DIRECT' and re.search(r'改到|改为|换到|换成',body):
                parsed=db.execute("SELECT payload FROM ai_messages WHERE message_id=? AND revision=? AND chat_id=? AND status='DONE'",
                                  (message['message_id'],message['revision'],c['chat_id'])).fetchone()
                plans=json.loads(parsed[0]).get('plans',[]) if parsed else []
                destinations=[p.get('price') for p in plans if p.get('side')==r[4]]
                older=[old for old in rows if old[2]=='DIRECT' and old[4]==r[4] and old[14]<message['created'] and float(old[5]) not in destinations]
                tokens=re.findall(r'(?<![\\d.])\\d{2,5}(?:\\.\\d+)?(?![\\d.])',body)
                explicit=format(float(r[5]),'g') in tokens
                changed=bool(destinations and float(r[5]) not in destinations and (explicit or len(older)==1))
            if cancel or changed:
                retired[key]=dict(state='REPLACED' if changed else 'CANCELLED',at=message['created'],
                                  reason='老师改价：旧计划退出' if changed else '老师明确取消',source=message['message_id'])
        groups.setdefault(float(r[5]),[]).append(item)
    points=[];output=[]
    for price,items in sorted(groups.items()):
        directional=[p for p in items if p['row'][4]!='AUTO' and p['key'] not in retired]
        # 来源权威相当时按原消息时间/顺序判断，新老师角色可覆盖旧会议方向。
        for old in directional:
            for new in directional:
                if new['row'][4]==old['row'][4]: continue
                if (new['authority']>=old['authority'] and
                    (new['row'][14],new['sequence'])>(old['row'][14],old['sequence'])):
                    retired[old['key']]=dict(state='REPLACED',at=new['row'][14],
                        reason='被较新同价方向替换',source=new['row'][6])
        for p in items:
            if p['key'] in retired:
                p.update(state=retired[p['key']]['state'],reason=retired[p['key']]['reason'])
            elif p['expires'] and now>=p['expires']:
                p.update(state='EXPIRED',reason='确认期限已到：仅观察')
        live=[p for p in items if p['state']=='READY']
        directions={p['row'][4] for p in live if p['row'][4]!='AUTO'}
        conflict=len(directions)>1
        # 中性地图不能绕过同价方向的取消/到期重新触发。
        if not directions and any(p['row'][4]!='AUTO' for p in items):
            live=[p for p in live if p['row'][4]!='AUTO']
        chosen=max(live or items,key=lambda p:(p['authority'],p['row'][14],p['row'][3],p['sequence']))
        status,reason=chosen['state'],chosen['reason']
        if conflict: status,reason='CONFLICT','同价方向冲突：等待明确更新'
        r=copy.deepcopy(chosen['row'])
        # 一个价位只出一条执行候选；消费身份仍由EA按价位/方向共用。
        if not live and status=='READY': status,reason='WATCH','同价方向已停用：仅观察'
        if status!='READY':
            r[2:5]=['WATCH',0,'AUTO'];r[10:14]=['0.0000000000']*4;r[15]='REFERENCE'
        reason=reason.replace(',','，').replace('\n',' ').replace('\r',' ')
        r.extend([chosen['expires'],len(items),status,reason])
        output.append(r)
        evidence=[dict(kind=p['row'][2],side=p['row'][4],source=p['row'][6],confirmed=p['row'][14],
                       expires=p['expires'],state=p['state'],reason=p['reason'],text=p['text']) for p in items]
        points.append(dict(price=price,side=r[4],state=status,reason=reason,expires=chosen['expires'],
                           authority=chosen['authority'],sources=evidence))
    if applied and applied['draft']['mode']!='auto':
        for price in applied['draft']['disabled']:
            if price in deleted: continue
            ident=hashlib.sha256(('DISABLED|'+str(price)).encode()).hexdigest()[:24]
            output.append(['PLAN',ident,'WATCH',0,'AUTO',f'{price:.10f}','MANUAL',ident,int(applied['at']),
                           'DISABLED|'+str(price),*['0.0000000000']*4,int(applied['at']),'REFERENCE',0,0,'DISABLED','人工停用：恢复自动后重新核验'])
            points.append(dict(price=price,side='AUTO',state='DISABLED',reason='人工停用',expires=0,sources=[]))
    previous={p['price']:p for p in saved['points']}
    current={p['price']:p for p in points}
    events=saved['events']
    for price in sorted(previous.keys()|current.keys()):
        old,new=previous.get(price),current.get(price)
        if old==new: continue
        events.append(dict(at=int(now),price=price,state=new['state'] if new else 'REMOVED',
                           reason=new['reason'] if new else '来源撤回、改价或新地图替换',
                           before=old,after=new))
    value=dict(scope=scope,retired=retired,points=points,events=events[-300:])
    if persist and value!=saved:
        with db: set_state(db,'point_lifecycle',value)
    return output


# 统一候选出口；所有价格差均为报价单位（例如4180→4185），不是MT5 Point。
POINT_LIMIT=6
POINT_GAP=5.0


def select_rows(db,c,rows,now,persist=True):
    scope=[c['chat_id'],c['teacher_sender_id'],c['symbols'][c['teacher_symbol']]]
    saved=state(db,'point_selection',{})
    if saved.get('scope')!=scope: saved={}
    ids=sorted({r[6] for r in rows if r[6]!='MANUAL'})
    messages={r['message_id']:r['sender'] for r in db.execute(
        'SELECT message_id,sender FROM messages WHERE chat_id=? AND message_id IN ('+','.join('?' for _ in ids)+')',
        (c['chat_id'],*ids))} if ids else {}
    candidates=[r for r in rows if r[18] in ('READY','WATCH') and (not r[16] or now<r[16])]
    def authority(r):
        return 3 if r[6]=='MANUAL' else 2 if messages.get(r[6])==c['teacher_sender_id'] else 1
    def rank(r):
        return (-authority(r),-r[14],-r[3],r[1])
    signature=hashlib.sha256(json.dumps(rows,ensure_ascii=False,separators=(',',':')).encode('utf-8')).hexdigest()
    reasons={float(r[5]):r[19] for r in rows if r not in candidates}
    # 高权威/新确认先处理；旧冲突不能反过来挡住已明确的手动修正。
    ordered=sorted(candidates,key=rank)
    conflicts=set(); accepted=[]
    for i,r in enumerate(ordered):
        price=float(r[5])
        neighbor=next((a for a in accepted if abs(float(a[5])-price)<POINT_GAP-1e-8),None)
        if neighbor:
            reasons[price]=f'距{float(neighbor[5]):.2f}不足5点：暂不采用'; continue
        if any(abs(price-p)<POINT_GAP-1e-8 for p in conflicts):
            reasons[price]='邻近点位多空冲突：待明确更新'; continue
        peers=[b for b in ordered[i+1:] if abs(float(b[5])-price)<POINT_GAP-1e-8 and
               r[4] in ('BUY','SELL') and b[4] in ('BUY','SELL') and r[4]!=b[4] and
               authority(r)==authority(b) and r[14]==b[14] and
               not any(abs(float(a[5])-float(b[5]))<POINT_GAP-1e-8 for a in accepted)]
        if peers:
            conflicts.update([price,*[float(b[5]) for b in peers]])
            reasons[price]='邻近点位多空冲突：待明确更新'; continue
        accepted.append(r)
    market=state(db,'teacher_analysis',{})
    quote=market.get('quote',{})
    bid,ask=quote.get('bid',0),quote.get('ask',0)
    fresh=(quote.get('symbol')==scope[2] and market.get('market_ok',False) and
           isinstance(bid,(int,float)) and isinstance(ask,(int,float)) and
           math.isfinite(bid) and math.isfinite(ask) and 0<bid<=ask and
           -2<=now-quote.get('at',0)<=c.get('quote_max_age_seconds',10))
    mid=(bid+ask)/2 if fresh else saved.get('mid',0)
    bars=market.get('bars',[])
    bar=bars[-1]['at'] if fresh and bars else (int(quote.get('at',0)//300)*300-300 if fresh else saved.get('bar',0))
    by_price={float(r[5]):r for r in accepted}
    previous=[p for p in saved.get('selected',[]) if p in by_price]
    changed=signature!=saved.get('signature') or saved.get('pending',False)
    if not fresh:
        selected=previous
    elif not changed and bar==saved.get('bar'):
        selected=previous
    else:
        near=sorted(by_price,key=lambda p:(abs(p-mid),rank(by_price[p])))
        lower=[p for p in near if p<=mid][:3]
        upper=[p for p in near if p>mid][:3]
        desired=lower+upper
        desired += [p for p in near if p not in desired][:POINT_LIMIT-len(desired)]
        selected=desired
        if not changed:
            # 仅行情换位时使用5点优势门槛；消息/撤销/到期变化立即生效。
            selected=previous[:]
            for price in desired:
                if price in selected: continue
                if len(selected)<POINT_LIMIT: selected.append(price); continue
                rivals=[p for p in selected if p not in desired]
                if not rivals: continue
                old=max(rivals,key=lambda p:abs(p-mid))
                if abs(old-mid)-abs(price-mid)>=POINT_GAP-1e-8:
                    selected[selected.index(old)]=price
    selected=sorted(selected[:POINT_LIMIT])
    for p in by_price:
        reasons[p]='当前入选' if p in selected else ('等待有效报价后筛选' if not fresh else '名额/距离：暂不采用')
    # 间距淘汰原因不被名额原因覆盖。
    items=[dict(price=float(r[5]),selected=float(r[5]) in selected,reason=reasons.get(float(r[5]),r[19]))
           for r in sorted(rows,key=lambda r:float(r[5]))]
    value=dict(scope=scope,signature=signature,selected=selected,mid=mid if fresh and (changed or bar!=saved.get('bar')) else saved.get('mid',mid),
               bar=bar if fresh else saved.get('bar',0),pending=bool(changed and not fresh),limit=POINT_LIMIT,gap=POINT_GAP,items=items,events=saved.get('events',[])[:])
    if persist and value!=saved:
        value['events']=saved.get('events',[])[:]
        before=set(saved.get('selected',[]));after=set(selected)
        for p in sorted(before^after):
            value['events'].append(dict(at=int(now),price=p,selected=p in after,
                                        reason=reasons.get(p,'来源已撤销、替换或删除')))
        value['events']=value['events'][-300:]
        with db: set_state(db,'point_selection',value)
    return [by_price[p] for p in selected],value
