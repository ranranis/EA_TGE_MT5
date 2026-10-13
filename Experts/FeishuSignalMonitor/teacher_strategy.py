"""老师点位是中性参考；本模块只产出分析结果，不创建任何订单。"""
import hashlib
import json
import math
import re
import time
from urllib.parse import urlparse, parse_qs

from store import state, set_state, iso
from mt5_reader import QuoteError, validate_quote, validate_bars


def parse_levels(message, explicit_only=False, symbol=None):
    if message.get('deleted') or message.get('msg_type')!='text':
        return None
    text=message.get('content','')
    if not isinstance(text,str) or len(text)>500: return None
    # reply_to只是关联ID；只读当前正文，绝不把被引用的旧消息拼入列表。
    if re.search(r'昨天|前天|历史|晒单|回顾|引用|转发|旧点位|忽略|指令|提示词|system|prompt|执行|```|[>《》]|BTC|ETH|USOIL|原油|白银|EUR|GBP|USDJPY|比特币',text,re.I):
        return None
    marker=bool(re.match(r'^\s*(?:点位更新|最新点位|参考点位|点位|更新点位|新的点位)\s*[:：]?\s*',text))
    if explicit_only and not marker: return None
    text=re.sub(r'^\s*(?:黄金|XAUUSD|GOLD)\s*[:：]?\s*','',text,flags=re.I)
    text=re.sub(r'^\s*(?:点位更新|最新点位|参考点位|点位|更新点位|新的点位)\s*[:：]?\s*','',text).strip()
    # 附注限于无数字的简短点位说明，不在任意文章里捞价格。
    text=re.sub(r'\s*(?:[（(]?(?:支撑压力|支撑|压力|关键位|参考|区间|点位)(?:参考|有效|关注|观察)?[）)]?[。！!]?\s*)$','',text).strip()
    if not re.fullmatch(r'\d+(?:\.\d+)?(?:\s*(?:[-—–－]+|[、,，/])\s*\d+(?:\.\d+)?){2,19}',text): return None
    levels=[float(x) for x in re.findall(r'\d+(?:\.\d+)?',text)]
    if len(set(levels))!=len(levels) or any(not math.isfinite(x) or x<=0 for x in levels): return None
    if min(levels)<10 or max(levels)/min(levels)>2: return None
    # 黄金群完整报价，不把75/93这类尾数或日期当地图；合成其他品种可独立测试。
    if symbol and symbol.upper().startswith(('XAU','GOLD')) and not 1000<=min(levels)<=max(levels)<=10000:
        return None
    return sorted(levels)


def sender_name(raw):
    sender=raw.get('sender',{})
    return sender.get('sender_i18n_names',{}).get('zh_cn') or sender.get('name') or sender.get('id','未知')


def message_link(raw):
    link=raw.get('message_app_link','')
    p=urlparse(link)
    return link if p.scheme=='https' and p.hostname in ('applink.feishu.cn','applink.larksuite.com') else ''


def order_key(row):
    raw=json.loads(row['raw'])
    pos=parse_qs(urlparse(message_link(raw)).query).get('position',['0'])[0]
    return (row['created'],int(pos) if pos.isdigit() else 0,row['message_id'])


def source_levels(raw,sender,c):
    if sender==c['teacher_sender_id'] or sender in c.get('point_source_senders',[]):
        return parse_levels(raw,symbol=c.get('teacher_symbol'))
    return parse_levels(raw,symbol=c.get('teacher_symbol')) if c.get('allow_group_point_updates',False) else None


def refresh_levels(db,c,now):
    """单调选择最新点位；当前来源失效时不悄悄复活较老列表。"""
    previous=state(db,'teacher_levels',{})
    if previous.get('teacher_id',c['teacher_sender_id'])!=c['teacher_sender_id'] or previous.get('chat_id')!=c['chat_id']:
        previous={}
    rows=db.execute('SELECT * FROM messages WHERE chat_id=? ORDER BY created DESC LIMIT 1000',
                    (c['chat_id'],)).fetchall()
    def candidate(row):
        return source_levels(json.loads(row['raw']),row['sender'],c)
    selected=None
    if previous.get('message_id'):
        selected=db.execute('SELECT * FROM messages WHERE chat_id=? AND message_id=?',
                            (c['chat_id'],previous['message_id'])).fetchone()
    for row in sorted(rows,key=order_key,reverse=True):
        if selected is not None and order_key(row)<=order_key(selected): break
        if candidate(row):
            selected=row; break
    if selected is None:
        result={'active':False,'reason':'等待目标群完整文字点位列表','levels':[]}
    else:
        raw=json.loads(selected['raw']); levels=candidate(selected)
        same=previous.get('active') and levels==previous.get('levels')
        reason='当前参考点位' if levels else '当前点位已撤回或改成非点位内容，等待新列表'
        if selected['created']>now+5: reason='消息时间异常'; levels=None
        result=dict(chat_id=c['chat_id'],teacher_id=c['teacher_sender_id'],message_id=selected['message_id'],revision=selected['revision'],
                    sender=selected['sender'],sender_name=sender_name(raw),source_kind=('teacher' if selected['sender']==c['teacher_sender_id'] else 'group_point'),created=selected['created'],
                    time=iso(selected['created']),observed_at=previous['observed_at'] if same else now,
                    historical=bool(selected['historical']),checked=selected['checked'],
                    active=bool(levels),levels=levels or [],text=raw.get('content',''),
                    link=message_link(raw),reason=reason)
    with db: set_state(db,'teacher_levels',result)
    return result


def ema(values,period):
    result=[values[0]]; alpha=2/(period+1)
    for value in values[1:]: result.append(alpha*value+(1-alpha)*result[-1])
    return result


def analyze(bars,q,levels,c,now,live_after):
    """三根已收盘K线：穿越前、突破、回踩确认。固定首版规则仅供观察。"""
    validate_quote(q,now,c); validate_bars(bars,now)
    closes=[b['close'] for b in bars]; fast=ema(closes,20); slow=ema(closes,50)
    ranges=[max(bars[i]['high']-bars[i]['low'],abs(bars[i]['high']-bars[i-1]['close']),abs(bars[i]['low']-bars[i-1]['close'])) for i in range(1,len(bars))]
    atr=sum(ranges[-14:])/14
    if atr<=0: raise QuoteError('M5波动为零，无法判断')
    a,b,d=bars[-3:]; up=fast[-1]>slow[-1] and fast[-1]>fast[-2] and d['close']>fast[-1]
    down=fast[-1]<slow[-1] and fast[-1]<fast[-2] and d['close']<fast[-1]
    result=dict(status='WAIT',reason='等待突破后回踩确认',at=now,bar_at=d['at'],bar_time=iso(d['at']),
                closed_at=iso(d['at']+300),close=d['close'],ema20=round(fast[-1],4),ema50=round(slow[-1],4),
                atr14=round(atr,4),trend='偏多' if up else '偏空' if down else '震荡',checks=[],candidate=None)
    checks=result['checks']
    fresh=b['at']>=live_after
    checks.append(dict(label='突破K线在本次启动及点位确认之后形成',ok=fresh))
    checks.append(dict(label='EMA20 / EMA50 方向和斜率一致',ok=up or down))
    candidates=[]
    for level in levels:
        long=up and a['close']<=level and b['close']>level+0.1*atr
        short=down and a['close']>=level and b['close']<level-0.1*atr
        retest_long=long and level-0.2*atr<=d['low']<=level+0.2*atr and d['close']>level+0.1*atr and d['close']>d['open']
        retest_short=short and level-0.2*atr<=d['high']<=level+0.2*atr and d['close']<level-0.1*atr and d['close']<d['open']
        if retest_long or retest_short: candidates.append((level,'BUY' if retest_long else 'SELL'))
    checks.append(dict(label='已收盘M5突破 + 下一根回踩守住点位',ok=bool(candidates)))
    if not fresh: result['reason']='只观察启动/点位更新之后形成的结构，不追认旧信号'; return result
    if not up and not down: result['reason']='均线方向不一致，等待趋势清晰'; return result
    if not candidates: return result
    if len(candidates)!=1: result['reason']='同时满足多个点位，结构有歧义'; return result
    level,side=candidates[0]; sign=1 if side=='BUY' else -1; entry=q.ask if side=='BUY' else q.bid
    raw_stop=min(b['low'],d['low'],level)-0.25*atr if sign==1 else max(b['high'],d['high'],level)+0.25*atr
    stop=round((math.floor(raw_stop/q.tick_size) if sign==1 else math.ceil(raw_stop/q.tick_size))*q.tick_size,q.digits)
    targets=[x for x in levels if sign*(x-entry)>0]
    target=min(targets) if targets and sign==1 else max(targets) if targets else None
    risk=sign*(entry-stop); reward=sign*(target-entry) if target is not None else 0
    rr=reward/risk if risk>0 else 0
    checks.extend([dict(label='实时价格仍在点位方向，距离不超过0.75 ATR',ok=0<=sign*(entry-level)<=0.75*atr),
                   dict(label='结构保护距离有效且不超过2.5 ATR',ok=q.stops<=risk<=2.5*atr and risk>0),
                   dict(label='下一老师点位存在，收益/风险至少1.2',ok=target is not None and rr>=1.2)])
    result['candidate']=dict(side=side,level=level,reference_entry=entry,structure_sl=stop,next_level=target,rr=round(rr,2),
                             note='结构保护价由规则计算，不是老师原文；仅为观察提示，没有订单')
    failed=[x['label'] for x in checks if not x['ok']]
    if failed: result['reason']='未通过：'+'；'.join(failed)
    else: result['status']='CANDIDATE'; result['reason']='突破与回踩条件满足，等待你自行判断；未下单'
    return result


class TeacherAnalysis:
    def __init__(self,db,c,quotes,started):
        self.db=db; self.c=c; self.quotes=quotes; self.started=started

    def update(self,now,allowed,blocked_reason):
        context=refresh_levels(self.db,self.c,now)
        result=dict(at=now,status='BLOCKED',reason=blocked_reason or context['reason'],checks=[],candidate=None)
        quote=None
        read_started=time.monotonic()
        try:
            symbol=self.c['symbols'][self.c['teacher_symbol']]
            quote=self.quotes.quote(symbol,now)
            bars=self.quotes.bars(symbol,now)
            # IPC等待时间计入校验时钟，避免刚收到的tick被误判为未来报价。
            now+=time.monotonic()-read_started
            if context['active']:
                result=analyze(bars,quote,context['levels'],self.c,now,max(self.started,context['observed_at']))
                if not allowed: result.update(status='BLOCKED',reason=blocked_reason,candidate=None)
                elif now-context['checked']>self.c['sync_max_age_seconds']:
                    result.update(status='BLOCKED',reason='点位来源复查已过期，等待飞书同步',candidate=None)
            result['bars']=bars[-60:]
            result['quote']=quote.__dict__; result['market_ok']=True
        except QuoteError as ex:
            previous=state(self.db,'teacher_analysis',{})
            for key in ('quote','bars','ema20','ema50','atr14','trend','close','closed_at'):
                if key in previous: result[key]=previous[key]
            result.update(reason=str(ex),market_ok=False,stale=True,status='BLOCKED',candidate=None,checks=[])
            if quote: result['quote']=quote.__dict__
        # 网络读取在事务外；提交时重新检查来源版本，避免刚撤回的点位产生提示。
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            if context.get('message_id'):
                current=self.db.execute('SELECT revision,deleted FROM messages WHERE chat_id=? AND message_id=?',
                                        (self.c['chat_id'],context['message_id'])).fetchone()
                if not current or current['revision']!=context['revision'] or current['deleted']:
                    result.update(status='BLOCKED',reason='点位来源刚发生变更，等待重新分析',candidate=None)
            result['source_id']=context.get('message_id'); result['mode']='analysis_only'
            if result['status']=='CANDIDATE':
                key=hashlib.sha256(f"{context['message_id']}:{context['revision']}:{result['bar_at']}".encode()).hexdigest()
                events=state(self.db,'analysis_events',[])
                if not any(e['id']==key for e in events):
                    events.insert(0,dict(id=key,**{k:v for k,v in result.items() if k!='bars'})); set_state(self.db,'analysis_events',events[:20])
            set_state(self.db,'teacher_analysis',result)
        return result
