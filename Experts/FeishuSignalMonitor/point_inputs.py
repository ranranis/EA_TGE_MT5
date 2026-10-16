"""手动点位与原文角色；分数用于排序，不是胜率或仓位建议。"""
import hashlib
import json
import math
import re
from pathlib import Path
from datetime import datetime

PRIORITIES = {'teacher': 100, 'summary': 90, 'manual': 95,
              'outer': 75, 'inner': 70, 'role': 60, 'minor': 55, 'map': 40}


def annotated_roles(text):
    result = []
    for match in re.finditer(r'(?<![\d.])(\d{4,5}(?:\.\d{1,2})?)\s*[（(]\s*((?:小|强|弱|重要)?(?:压力|阻力|支撑))\s*[）)]', text):
        role = match[2]
        result.append(dict(price=float(match[1]), side='BUY' if '支撑' in role else 'SELL',
                           priority=PRIORITIES['minor' if role.startswith(('小','弱')) else 'role']))
    return result



def spoken_roles(text, anchor=0):
    """明确当前支撑压力独立于开仓标签；尾数只用消息原时点的锚点。"""
    from deepseek_ai import resolve_token, AIError
    if not isinstance(text,str) or re.search(r'如果|假如|假设|万一|若|一旦|突破后|跌破后|站稳后|转发|引用|[“”「」？?]|是不是|可能|也许',text):
        return []
    number=r'(?<![\d.])(\d{2,5}(?:\.\d{1,2})?)(?![\d.])'
    role=r'((?:小|弱|强|重要)?(?:支撑|压力|阻力))'
    link=r'(?:这里|附近|位置|这个|都|已经|现在|是|为|成了|成为|变成|变为|转为|作为|的|了|：|:|\s|[（(])*'
    transition=r'(?:(?:由|从)?(?:支撑|压力|阻力)(?:位|点)?(?:变成|变为|转为|成了))?'
    patterns=[number+link+transition+role, role+r'(?:位|点)?'+link+number]
    result={}
    for clause in re.split(r'[，,；;\n。！!]',text):
        if re.search(r'昨天|昨日|之前|以前|曾经|刚才|方才',clause):
            clause=re.split(r'现在|当前|如今',clause)[-1]
        if re.search(r'昨天|昨日|之前|以前|曾经|刚才|方才|复盘|回顾|历史|不是|不再|不算|不做|取消|撤销|作废|无效|失效|不成立|没撑住|不住|未必|止损|止盈|目标|收单|收米|平仓|EMA|MA\d',clause,re.I):
            continue
        for index,pattern in enumerate(patterns):
            for match in re.finditer(pattern,clause):
                token,label=(match[1],match[2]) if index==0 else (match[2],match[1])
                try:
                    price=resolve_token(token,anchor or (float(token) if len(token.split('.')[0])>=4 else 0))
                except AIError:
                    continue
                side='BUY' if '支撑' in label else 'SELL'
                point=dict(price=price,side=side,priority=PRIORITIES['minor' if label.startswith(('小','弱')) else 'role'])
                if price in result and result[price]['side']!=side:
                    result[price]['conflict']=True
                else:
                    result[price]=point
    return [p for p in result.values() if not p.get('conflict')]


def teacher_role_points(db,c,now):
    """保存最新角色来源；撤回/编辑失效时不复活此前同价的反向参考。"""
    from store import state, set_state
    if not c.get('ai_enabled'):
        return []
    scope=[c['chat_id'],c['teacher_sender_id'],c['symbols'][c['teacher_symbol']]]
    saved=state(db,'teacher_point_roles',{})
    if saved.get('scope')!=scope:
        saved=dict(scope=scope,points={})
    before=json.dumps(saved,sort_keys=True)
    anchors=state(db,'deepseek_anchors',{})
    floor=state(db,'teacher_levels',{}).get('created',0)
    sources=db.execute("""SELECT *,rowid AS sequence FROM messages
        WHERE chat_id=? AND sender=? AND historical=0 AND created>=? AND created<=?
        AND (raw LIKE '%支撑%' OR raw LIKE '%压力%' OR raw LIKE '%阻力%')
        ORDER BY created,rowid""",(c['chat_id'],c['teacher_sender_id'],floor,now+5)).fetchall()
    for source in sources:
        if source['deleted']:
            continue
        raw=json.loads(source['raw'])
        if raw.get('msg_type')!='text':
            continue
        for p in spoken_roles(raw.get('content',''),anchors.get(source['message_id'],0)):
            key=format(p['price'],'g')
            old=saved['points'].get(key,{})
            if (source['created'],source['sequence']) < (old.get('created',0),old.get('sequence',0)):
                continue
            saved['points'][key]=dict(p,message_id=source['message_id'],revision=source['revision'],
                                     created=source['created'],sequence=source['sequence'])
    if before!=json.dumps(saved,sort_keys=True):
        with db:
            set_state(db,'teacher_point_roles',saved)
    result=[]
    for p in saved['points'].values():
        row=db.execute('SELECT revision,deleted,historical FROM messages WHERE chat_id=? AND message_id=?',
                       (c['chat_id'],p['message_id'])).fetchone()
        valid=bool(p['created']>=floor and row and not row['deleted'] and not row['historical'] and row['revision']==p['revision'])
        result.append(dict(p,valid=valid))
    return result

def reference_only_prices(text):
    """条件阈值和收单价不能从同一总结再绕回中性/区间碰价入口。"""
    number=r'(\d{4,5}(?:\.\d{1,2})?)'
    patterns=[r'(?:低于|高于|突破|跌破)\s*'+number,
              number+r'\s*(?:以下|以上)',
              number+r'\s*(?:为|是|作为)?\s*(?:收单|平仓|止盈|离场)(?:位置|价位|位)?']
    return {float(m[1]) for pattern in patterns for m in re.finditer(pattern,text)}


def manual_points(c, now):
    """每次导出读取；无效的已启用文件阻断输出，不能悄悄回到自动计划。"""
    if not c.get('manual_points_enabled') or not c.get('_home'):
        return None
    path = Path(c.get('manual_points_file', 'config/manual_points.json'))
    if not path.is_absolute(): path = Path(c['_home']) / path
    if not path.exists(): return None
    if path.stat().st_size > 32768: raise ValueError('手动点位文件超过32KB')
    value = json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(value, dict) or type(value.get('enabled')) is not bool:
        raise ValueError('手动文件必须有enabled布尔开关')
    if not value['enabled']: return None
    if set(value) - {'enabled','symbol','confirmed_at','note','levels','inner_range','outer_range'}:
        raise ValueError('手动点位包含未知字段')
    if value.get('symbol') not in (c['teacher_symbol'], c['symbols'][c['teacher_symbol']]):
        raise ValueError('手动点位品种不匹配')
    at = datetime.fromisoformat(value.get('confirmed_at', ''))
    if at.tzinfo is None: raise ValueError('confirmed_at必须包含时区，如+08:00')
    created = int(at.timestamp())
    if not 0 < created <= now+5: raise ValueError('手动确认时间无效或在未来')
    def price(number):
        if type(number) not in (float,int) or not math.isfinite(number) or not 0 < number < 1000000:
            raise ValueError('价格必须是有效正数')
        if c['teacher_symbol'].upper().startswith(('XAU','GOLD')) and not 1000 <= number <= 10000:
            raise ValueError('黄金点位必须填写完整价格，不能填尾数')
        return float(number)
    entries = value.get('levels', [])
    if not isinstance(entries,list) or len(entries)>20: raise ValueError('手动点位最多20项')
    plans=[]; seen=set()
    for entry in entries:
        if not isinstance(entry,dict) or set(entry)-{'price','role','note'}:
            raise ValueError('点位字段只允许price、role、note')
        number=price(entry.get('price')); role=entry.get('role','neutral')
        if number in seen: raise ValueError('手动点位价格重复，请合并角色')
        seen.add(number)
        if role not in ('buy','sell','support','resistance','minor_support','minor_resistance','neutral','watch'):
            raise ValueError('点位role无效')
        kind='DIRECT' if role in ('buy','sell') else 'MAP' if role=='neutral' else 'WATCH' if role=='watch' else 'ROLE'
        side='BUY' if role in ('buy','support','minor_support') else 'SELL' if role in ('sell','resistance','minor_resistance') else 'AUTO'
        score=PRIORITIES['manual'] if kind=='DIRECT' else PRIORITIES['minor' if role.startswith('minor_') else 'role'] if kind=='ROLE' else PRIORITIES['map'] if kind=='MAP' else 0
        plans.append(dict(kind=kind,side=side,price=number,priority=score))
    bands={}
    for name,kind in [('inner_range','INNER'),('outer_range','OUTER')]:
        band=value.get(name)
        if band is None: continue
        if not isinstance(band,list) or len(band)!=2: raise ValueError(name+'必须是两个完整价格')
        low,high=map(price,band)
        if low>=high: raise ValueError(name+'下沿必须小于上沿')
        bands[name]=(low,high)
        for side,number in [('BUY',low),('SELL',high)]:
            plans.append(dict(kind=kind,side=side,price=number,priority=PRIORITIES['inner' if kind=='INNER' else 'outer']))
    if len(bands)==2 and not bands['outer_range'][0]<=bands['inner_range'][0]<bands['inner_range'][1]<=bands['outer_range'][1]:
        raise ValueError('小区间必须包含在大区间内')
    if not plans: raise ValueError('启用手动模式时至少填写一个点位或区间')
    revision=hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False).encode('utf-8')).hexdigest()
    return dict(plans=plans,created=created,revision=revision)
