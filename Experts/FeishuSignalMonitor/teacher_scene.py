"""DeepSeek完整交易场景：语义由模型判断，本地只校验结构、原文与来源版本。"""
import hashlib
import json
import math
import re
from store import state, set_state, stamp

SCENE_PROMPT = """
除逐条interpretations外，根JSON必须增加scene。scene综合同一老师的连续发言和previous_scene，输出截至本批最后一条T哥消息的完整有效计划，不是只输出最后一句。
scene是独立的全文语义理解，不受旧interpretation标签约束；旧WATCH可能漏识别，不能沿袭误判。必须根据原文重新判断。
区间交易中的不同价格BUY和SELL是两个可同时等待的条件计划，不是方向冲突。“然后/另外/上去”不能据此取消另一侧；只有同价同条件矛盾或明确取消才视为冲突。
scene固定字段：
{"as_of":"最后一条teacher target的message_id，批内没有老师则为空","action":"KEEP|UPDATE|REVIEW",
"regime":"UNKNOWN|RANGE|TREND_UP|TREND_DOWN","regime_ref":null,
"plans":[],"inner_range":null,"outer_range":null,"summary":"中文理解、条件与不确定性"}
regime_ref有证据时为{"message_id":"真实来源ID","evidence":"原文连续片段"}。
每个plan固定字段：
{"side":"BUY|SELL","token":"价格原文数字","price":4175,"mode":"REACTION|MARKET",
"price_ref":"价格所在原消息ID","price_evidence":"含该token的原文连续片段",
"direction_ref":"方向依据所在原消息ID","direction_evidence":"表达买卖方向的原文连续片段"}
range对象固定为{"low":价格证据对象,"high":价格证据对象}；
价格证据对象固定为{"message_id":"来源","token":"数字","price":4175,"evidence":"原文连续片段"}。
interpretations的plan只允许side/token/price/mode/evidence（或context_ref），不能复制context中的near/source_refs/origin等本地内部字段。scene.plan使用自己定义的八个字段，与逐条plan字段不同。
处理原则：
1. 理解语义与数字角色。当前行情价、时间周期、入场价、目标价分开：例如“15分钟连绿，现在81了，多单等到75行动”明确表达等4175再做多，必须提取BUY4175（REACTION），81是行情位置、15是周期，不是入场价。
2. “然后上去93可↓”是补充SELL4193，应保留此前BUY4175；多空计划分别维护。明确“改到/不做/取消/最新取代”等才移除或替换对应旧计划，完整地图更新后不能复活此前作废方向。
3. “小区间4175-4200，大区间4150-4220”更新区间分析，不把区间两头自动生成为多空喊单；保留明确的双向入场计划。
4. “来回跑/区间震荡”可标记RANGE；“压力有效”只是关键位说明，不自动SELL。“多单等到/空单等到/可以行动/可上”不需要箭头，也属于有条件入场。
5. 含糊的“注意”可以承接唯一的前文方向，必须引用真实方向消息；没有唯一方向、方向冲突或真假含糊则REVIEW，禁止靠猜测填齐计划。
6. 优先T哥本人。成员晒单、引用、历史回顾、假设、玩笑不能更新scene。source_role=follow_member仍由独立五分钟通道处理。
7. 默认REACTION，持续有效条件计划由EA在目标上下2.00区内用实时tick检查逆向冲击，不等M1/M5收线。只有老师明确现价/市价/直接进且带数字，才能MARKET；前文的市价请求不能在新场景复活。
8. previous_scene只帮助记忆，引用必须在context/targets有原文并未撤回。不凭时间自动废掉T哥参考；明确作废、来源失效、新方案覆盖才变。
9. 普通闲聊且不改变场景用KEEP，plans=[]，regime=UNKNOWN，其他证据字段null。确有变更用UPDATE并返回完整仍有效场景；无法可靠确定新交易指令用REVIEW，不能静默继续旧方向。
10. summary可以解释突破后观察回踩等，但不能制造没有原文的交易价格、SL、TP、手数。不要把“15分钟连绿”的颜色直接判成趋势方向。
11. 所有引用只用截至as_of的真实消息ID；价格尾数用该消息的market_anchor/previous_scene已验证同token价格复核，不按未来行情重新补全。
12. previous_scene为空时，这是首次建立完整场景：必须结合context里的原文恢复截至as_of仍有效的计划，不能因为最后一句是补充说明就KEEP。没有可确认的计划返回UPDATE空计划；信息不足返回REVIEW。
"""


def validate_scene(value, targets, context, anchor, previous=None):
    from deepseek_ai import AIError, resolve_token
    keys={'as_of','action','regime','regime_ref','plans','inner_range','outer_range','summary'}
    if not isinstance(value,dict) or set(value)!=keys:
        raise AIError('AI场景字段不完整')
    if value['action'] not in ('KEEP','UPDATE','REVIEW') or value['regime'] not in ('UNKNOWN','RANGE','TREND_UP','TREND_DOWN'):
        raise AIError('AI场景状态无效')
    if not isinstance(value['summary'],str) or len(value['summary'])>400:
        raise AIError('AI场景说明无效')
    teacher=[t for t in targets if t.get('source_role')=='teacher' and not t.get('historical')]
    if not teacher:
        if value['as_of']!='' or value['action']!='KEEP':
            raise AIError('无老师新消息不能更新场景')
        return None
    latest=teacher[-1]
    if value['as_of']!=latest['message_id']:
        raise AIError('AI场景必须截至最新老师消息')
    if not isinstance(value['plans'],list) or len(value['plans'])>4:
        raise AIError('AI场景计划数量无效')
    if value['action']=='KEEP' and ((latest.get('interpretation') or {}).get('kind') in ('CANCEL','SETUP') or re.search(r'取消|作废|撤销|不做多|不做空|别做多|别做空|暂停',latest['text'])):
        raise AIError('明确新增/取消不能被KEEP忽略')
    if value['action']!='UPDATE':
        if value['plans'] or value['regime']!='UNKNOWN' or any(value[k] is not None for k in ('regime_ref','inner_range','outer_range')):
            raise AIError('KEEP/REVIEW不能夹带执行计划')
        return dict(value,created=stamp(latest['time']),sequence=latest['sequence'],
                    revision=latest['revision'],sender=latest['sender_id'],source_refs=[
                        dict(message_id=latest['message_id'],revision=latest['revision'])])
    items={m['message_id']:m for m in context+targets if m.get('message_id')}
    refs={}
    def evidence(mid, quote):
        item=items.get(mid) if isinstance(mid,str) else None
        if (not item or item.get('source_role')!='teacher' or item.get('sender_id')!=latest['sender_id'] or
            item.get('historical') or item.get('deleted') or not item.get('revision') or
            (stamp(item['time']),item.get('sequence',0))>(stamp(latest['time']),latest['sequence']) or
            not isinstance(quote,str) or not quote or quote not in item['text']):
            raise AIError('AI场景引用缺少有效老师原文')
        refs[mid]=dict(message_id=mid,revision=item['revision'])
        return item
    def price(proof):
        if not isinstance(proof,dict) or set(proof)!={'message_id','token','price','evidence'}:
            raise AIError('AI场景价格证据字段无效')
        item=evidence(proof['message_id'],proof['evidence'])
        token=proof['token'];number=proof['price']
        if not isinstance(token,str) or not re.search(r'(?<![\d.])'+re.escape(token)+r'(?![\d.])',proof['evidence']):
            raise AIError('AI场景价格不在原文或数字被截断')
        if isinstance(number,bool) or not isinstance(number,(int,float)) or not math.isfinite(number):
            raise AIError('AI场景价格不是有限数')
        item_anchor=item.get('market_anchor',0)
        if not item_anchor:
            # 保留旧场景的价格必须保持原来核验的数量级，不拿实时行情补旧尾数。
            old_plans=(previous or {}).get('plans',[])
            match=next((p for p in old_plans if p['token']==token and p['price_ref']==proof['message_id']),None)
            item_anchor=match['price'] if match else (float(token) if len(token.split('.')[0])>=4 else 0)
        if abs(number-resolve_token(token,item_anchor))>0.001:
            raise AIError('AI场景价格补全未通过原时点复核')
        if re.search(r'(?:EMA|MA|ATR|RSI|ADX|MACD)\s*'+re.escape(token),proof['evidence'],re.I):
            raise AIError('指标周期不是入场价')
        return number
    clean=[]
    for plan in value['plans']:
        required={'side','token','price','mode','price_ref','price_evidence','direction_ref','direction_evidence'}
        if not isinstance(plan,dict) or set(plan)!=required or plan['side'] not in ('BUY','SELL') or plan['mode'] not in ('REACTION','MARKET'):
            raise AIError('AI场景计划字段无效')
        price(dict(message_id=plan['price_ref'],token=plan['token'],price=plan['price'],evidence=plan['price_evidence']))
        direction=evidence(plan['direction_ref'],plan['direction_evidence'])
        buy=bool(re.search(r'↑|⬆|做多|买入|多单|(?<![太很许更])多(?!拿|少)',plan['direction_evidence']))
        sell=bool(re.search(r'↓|⬇|做空|卖出|空单|空(?!间)',plan['direction_evidence']))
        if buy==sell or plan['side']!=('BUY' if buy else 'SELL'):
            raise AIError('AI场景方向缺少唯一原文依据')
        for mid in (plan['price_ref'],plan['direction_ref']):
            if re.search(r'历史|晒单|转发|假设|昨天|回顾|开玩笑|忽略.{0,10}(规则|指令)',items[mid]['text']):
                raise AIError('历史/指令文本不能成为场景入场')
        if re.search(r'取消|作废|撤销|不做|别做|不要|止损|止盈|平仓',plan['direction_evidence']):
            raise AIError('取消/退出原文不能成为场景方向')
        if plan['mode']=='MARKET' and (plan['price_ref']!=latest['message_id'] or
            not re.search(r'现价|市价|直接.{0,3}(进|买|卖|多|空)',items[plan['price_ref']]['text'])):
            raise AIError('旧市价计划不可随场景重放')
        key=(plan['side'],plan['price'])
        if key in [(p['side'],p['price']) for p in clean]:
            raise AIError('AI场景计划重复')
        if any(p['price']==plan['price'] and p['side']!=plan['side'] for p in clean):
            raise AIError('同价双向条件矛盾，等待老师确认')
        source=items[plan['price_ref']]
        start=max((stamp(source['time']),source.get('sequence',0)),(stamp(direction['time']),direction.get('sequence',0)))
        for item in items.values():
            if item.get('sender_id')!=latest['sender_id'] or (stamp(item['time']),item.get('sequence',0))<=start:
                continue
            interpretation=item.get('interpretation') or {}
            kind=interpretation.get('kind')
            text=item.get('text','')
            raw_all=bool(re.search(r'^(?:取消|作废|撤销)(?:全部|所有|前面|之前|计划|参考)|^(?:全部|所有)(?:取消|作废|撤销)|^暂停(?:交易|计划|参考)',text.strip()))
            raw_side=bool(re.search(r'(?:取消|作废|撤销|不做|别做)\s*(?:多单|做多)|(?:多单|做多)\s*(?:取消|作废|撤销)',text)) if plan['side']=='BUY' else bool(re.search(r'(?:取消|作废|撤销|不做|别做)\s*(?:空单|做空)|(?:空单|做空)\s*(?:取消|作废|撤销)',text))
            if not item.get('deleted') and not item.get('historical') and (
                kind=='CANCEL' and interpretation.get('cancel_side') in ('ALL',plan['side']) or raw_all or raw_side):
                raise AIError('AI场景不得复活取消前的旧方向')
        # 相同仍有效价位的形式编辑/重述继承机会身份，实际来源版本仍单独校验。
        prior=next((p for p in (previous or {}).get('plans',[]) if p['side']==plan['side'] and p['price']==plan['price'] and p['mode']==plan['mode']),None)
        origin_revision=hashlib.sha256(json.dumps([source['message_id'],direction['message_id'],plan['side'],plan['price'],plan['mode']],ensure_ascii=False).encode('utf-8')).hexdigest()
        plan=dict(plan,near=False,origin_id=prior.get('origin_id',source['message_id']) if prior else source['message_id'],
                  origin_revision=prior.get('origin_revision',origin_revision) if prior else origin_revision,
                  origin_created=prior.get('origin_created',stamp(source['time'])) if prior else stamp(source['time']))
        clean.append(plan)
    for name in ('inner_range','outer_range'):
        band=value[name]
        if band is not None:
            if not isinstance(band,dict) or set(band)!={'low','high'} or price(band['low'])>=price(band['high']):
                raise AIError('AI场景区间无效')
    if value['inner_range'] and value['outer_range']:
        if not (value['outer_range']['low']['price']<=value['inner_range']['low']['price']<
                value['inner_range']['high']['price']<=value['outer_range']['high']['price']):
            raise AIError('AI场景大小区间顺序冲突')
    regime=value['regime_ref']
    if value['regime']!='UNKNOWN':
        if not isinstance(regime,dict) or set(regime)!={'message_id','evidence'}:
            raise AIError('AI场景节奏缺少原文')
        evidence(regime['message_id'],regime['evidence'])
    elif regime is not None:
        raise AIError('未知节奏不能带判断证据')
    refs[latest['message_id']]=dict(message_id=latest['message_id'],revision=latest['revision'])
    return dict(value,plans=clean,created=stamp(latest['time']),sequence=latest['sequence'],
                revision=latest['revision'],sender=latest['sender_id'],source_refs=list(refs.values()),
                map_only=not clean and (latest.get('interpretation') or {}).get('kind')=='MAP')


def publish_scene(db, c, scene):
    from deepseek_ai import refs_current
    if not scene or scene['action']=='KEEP':
        return
    previous=state(db,'teacher_scene',{})
    if (scene['created'],scene['sequence'])<(previous.get('created',0),previous.get('sequence',0)):
        return
    if not refs_current(db,c['chat_id'],scene['source_refs']):
        return
    set_state(db,'teacher_scene',scene)
    if scene['action']=='REVIEW':
        set_state(db,'deepseek_review',dict(message_id=scene['as_of'],created=scene['created'],reason=scene['summary']))
        return
    set_state(db,'deepseek_review',{})
    set_state(db,'deepseek_setup',dict(message_id=scene['as_of'],revision=scene['revision'],created=scene['created'],
        sender=scene['sender'],mode='SETUP' if scene['plans'] else 'MAP' if scene.get('map_only') else 'WAIT',
        plans=scene['plans'],source_refs=scene['source_refs'],reason=scene['summary'],scene=True))


def scene_view(db, c):
    from deepseek_ai import refs_current
    scene=state(db,'teacher_scene',{})
    if not scene:
        return {}
    return dict(scene,source_valid=refs_current(db,c['chat_id'],scene['source_refs']))
