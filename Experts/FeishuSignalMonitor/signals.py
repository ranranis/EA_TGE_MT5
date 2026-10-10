"""保守规则解析：字段不完整或语义有歧义时，只记录，不猜单。"""
import json
import math
import re

KINDS = {'NEW_ORDER', 'MODIFY_ORDER', 'CANCEL_ORDER', 'CLOSE_ORDER', 'DISCUSSION', 'UNKNOWN'}
NUM = r'\d+(?:\.\d+)?'
SYMBOL = re.compile(r'(?<![A-Z])(?:XAUUSD|(?:EUR|USD|GBP|JPY|CHF|AUD|NZD|CAD){2})(?![A-Z])', re.I)
TARGET = re.compile(r'(?:关联|信号ID|ref)\s*[:：=]?\s*(om_[A-Za-z0-9_]+)', re.I)
SL = re.compile(r'(?:\bSL\b|止损)\s*(?:改为|改到|调整到|设为|移到|[:：=@])?\s*('+NUM+r')', re.I)
TP = re.compile(r'(?:\bTP\d*\b|止盈\d*)\s*(?:改为|改到|调整到|设为|移到|[:：=@])?\s*('+NUM+r'(?:\s*[/、,，]\s*'+NUM+r')*)', re.I)

def unknown(reason, kind='UNKNOWN'):
    return {'kind':kind, 'reason':reason}

def parse_message(message):
    if message.get('deleted'):
        return unknown('原消息已撤回')
    if message.get('msg_type') != 'text':
        return unknown('图片待人工识别' if message.get('msg_type')=='image' else '非纯文字消息待人工识别')
    text=message.get('content','').strip()
    if not isinstance(text,str) or len(text)>10000:
        return unknown('正文长度或类型异常')
    # 转发/引用/复盘/玩笑/条件观点均不充当明确指令。
    if re.search(r'转发|引用|^>|晒单|复盘|昨天|昨日|刚才|之前|已平|已止盈|赚了|开玩笑|哈哈|[?？]|如果|假如|可能|预计|看好|我觉得|建议|考虑|关注|参考|支撑|阻力|压力|不要|禁止|不做|不买|不卖|别开|勿|例如|示例|测试|忽略.*指令',text):
        return unknown('讨论、条件观点、历史或引用，不能视为正式喊单','DISCUSSION')
    target=TARGET.search(text)
    target=target.group(1) if target else message.get('reply_to')
    sls=[float(x) for x in SL.findall(text)]
    tps=[float(x) for match in TP.findall(text) for x in re.findall(NUM,match)]
    if len(sls)>1 or len(tps)>8:
        return unknown('多组止损或过多止盈，含义不唯一')
    sl=sls[0] if sls else None
    if re.search(r'撤单|取消挂单|\bCANCEL\b',text,re.I):
        return {'kind':'CANCEL_ORDER','target':target,'reason':'明确撤单；关联仍需校验'}
    if re.search(r'平仓|全部平掉|\bCLOSE\b',text,re.I):
        return {'kind':'CLOSE_ORDER','target':target,'reason':'明确平仓；关联仍需校验'}
    if re.search(r'修改|调整|移到|改到|改为|\bMODIFY\b',text,re.I):
        if sl is None and not tps:
            return unknown('修改未提供明确价格')
        return {'kind':'MODIFY_ORDER','target':target,'sl':sl,'tps':tps,'reason':'明确修改；关联仍需校验'}
    symbols=set(x.upper() for x in SYMBOL.findall(text))
    if '黄金' in text: symbols.add('XAUUSD')
    if len(symbols)>1: return unknown('同一消息含多个品种')
    buys=bool(re.search(r'\bBUY\b|做多|买入|开多',text,re.I))
    sells=bool(re.search(r'\bSELL\b|做空|卖出|开空',text,re.I))
    if not buys and not sells: return unknown('没有明确开仓动作','DISCUSSION')
    if buys and sells: return unknown('同时出现多空方向')
    if not symbols: return unknown('缺少明确品种')
    order_type='MARKET' if re.search(r'市价|现价|\bMARKET\b',text,re.I) else 'LIMIT' if re.search(r'限价|挂单|\bLIMIT\b',text,re.I) else None
    if not order_type: return unknown('必须明确市价或限价')
    # 仅从入场标签读取价格，不把 SL/TP 数值当作入场价。
    entries=re.findall(r'(?:入场|进场|\bENTRY\b|@)\s*[:：=]?\s*('+NUM+r')(?:\s*(?:--|[-~～至到])\s*('+NUM+r'))?',text,re.I)
    if len(entries)>1: return unknown('存在多组入场价格')
    entry=sorted([float(x) for x in entries[0] if x]) if entries else []
    if order_type=='LIMIT' and not entry: return unknown('限价单缺少入场价格或区间')
    # 禁止忽略多余数字：常见“4105 做多”等未标注价格必须人工确认。
    rest=SL.sub('',text); rest=TP.sub('',rest); rest=TARGET.sub('',rest)
    rest=re.sub(r'(?:入场|进场|\bENTRY\b|@)\s*[:：=]?\s*'+NUM+r'(?:\s*(?:--|[-~～至到])\s*'+NUM+r')?', '',rest,flags=re.I)
    if re.search(NUM,rest): return unknown('存在未标注用途的数字，待人工确认')
    result={'kind':'NEW_ORDER','symbol':next(iter(symbols)), 'side':'BUY' if buys else 'SELL',
            'order_type':order_type,'entry':entry,'sl':sl,'tps':tps,'reason':'规则识别的明确候选信号'}
    validate_signal(result)
    return result

def validate_signal(s):
    """可供将来的本地 AI JSON 使用；本版本不调用 AI，也不上传群消息。"""
    if not isinstance(s,dict) or s.get('kind') not in KINDS: raise ValueError('信号类型无效')
    allowed={'kind','reason','symbol','side','order_type','entry','sl','tps','target'}
    if set(s)-allowed: raise ValueError('含未知字段')
    if 'reason' in s and not isinstance(s['reason'],str): raise ValueError('说明类型错误')
    if s.get('target') is not None and not re.fullmatch(r'om_[A-Za-z0-9_]+',s['target']): raise ValueError('关联ID无效')
    for key in ('sl',):
        value=s.get(key)
        if value is not None and (type(value) not in (int,float) or not math.isfinite(value) or value<=0): raise ValueError('价格无效')
    for key in ('entry','tps'):
        if key in s and (not isinstance(s[key],list) or any(type(v) not in (int,float) or not math.isfinite(v) or v<=0 for v in s[key])): raise ValueError('价格列表无效')
    if s['kind']=='NEW_ORDER':
        if not SYMBOL.fullmatch(s.get('symbol','')) or s.get('side') not in ('BUY','SELL') or s.get('order_type') not in ('MARKET','LIMIT'): raise ValueError('开仓字段不完整')
        if not isinstance(s.get('entry'),list) or len(s['entry'])>2 or not isinstance(s.get('tps'),list) or len(s['tps'])>8: raise ValueError('价格列表错误')
        if s['order_type']=='LIMIT' and not s['entry']: raise ValueError('限价缺少价格')
        if s['entry']!=sorted(s['entry']): raise ValueError('入场区间未排序')
    return s

def validate_ai_json(payload):
    # 即使人工引入 AI 结果，也不绕过字段校验和后续纸面风险控制。
    return validate_signal(json.loads(payload))
