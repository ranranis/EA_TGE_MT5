"""TGA9：同价唯一候选、独立来源期限和可追溯撤销；不发送交易。"""
import copy
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from store import state, set_state
from teacher_scene import cancels_plan

TZ=timezone(timedelta(hours=8))

def expiry(row, text, applied):
    # 每条依据独立计时；支撑重申不能延长旧明确指令。
    if row[2]=='WATCH': return 0
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
        chosen=max(live or items,key=lambda p:(p['row'][3],p['row'][14],p['sequence']))
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
        points.append(dict(price=price,side=r[4],state=status,reason=reason,expires=chosen['expires'],sources=evidence))
    if applied and applied['draft']['mode']!='auto':
        for price in applied['draft']['disabled']:
            if price in deleted: continue
            ident=hashlib.sha256(('DISABLED|'+str(price)).encode()).hexdigest()[:24]
            output.append(['PLAN',ident,'WATCH',0,'AUTO',f'{price:.10f}','MANUAL',ident,int(applied['at']),
                           'DISABLED|'+str(price),*['0.0000000000']*4,int(applied['at']),'REFERENCE',0,0,'DISABLED','人工停用：恢复自动后重新核验'])
            points.append(dict(price=price,side='AUTO',state='DISABLED',reason='人工停用',expires=0,sources=[]))
    if len(output)>64: raise ValueError('有效及停用点位合计超过64项，请减少点位')
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
