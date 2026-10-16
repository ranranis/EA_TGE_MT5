"""DeepSeek完整交易场景：语义由模型判断，本地只校验结构、原文与来源版本。"""
import hashlib
import copy
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
"direction_ref":"方向依据所在原消息ID","direction_evidence":"表达买卖方向的原文连续片段",
"exits":{"sl":null,"tp1":null,"tp2":null,"breakeven":null},"basis":null}
basis省略或null表示老师明确方向或唯一前文承接；AI区间推导必须为{"kind":"RANGE_EDGE","range":"inner_range|outer_range"}，不得冒充老师直接喊单。
range对象固定为{"low":价格证据对象,"high":价格证据对象}；
价格证据对象固定为{"message_id":"来源","token":"数字","price":4175,"evidence":"原文连续片段"}。
token必须逐字复制原文中的完整数字，不是价格尾数：原文4150--4220必须token="4150"、"4220"，绝对不能写"150"、"50"、"220"、"20"；只有原文真写“75”才用token="75"并补全price=4175。plans和range中引用同一端点时，token、price、price_ref/message_id必须一致。输出前逐项检查，否则整批拒绝。

interpretations的plan只允许side/token/price/mode/evidence（或context_ref），不能复制context中的near/source_refs/origin等本地内部字段。scene.plan另可带exits，与逐条plan字段不同。
exits各项为价格证据对象或null，sl是绝对止损价，tp1为首批减仓价，tp2为最终止盈价，breakeven为到达后推至开仓价的触发价。仅提取老师明确给出且与此入场计划唯一关联的价格，证据连续片段须包含对应价格及止损/止盈/保本角色；跨消息时须明确写出入场价和方向；唯一连续计划组的“目标统一”例外见第15条，必须由程序核验关联。缺失字段填null，不能把行情位置、点位列表或距离推算成退出价。只有一个明确止盈目标时填tp2；无tp1时由EA原有分批模板处理。退出信息更新用UPDATE保留完整计划。没有明确关联的“保本/出一半”只解释，不猜具体仓位。
处理原则：
1. 理解语义与数字角色。当前行情价、时间周期、入场价、目标价分开：例如“15分钟连绿，现在81了，多单等到75行动”明确表达等4175再做多，必须提取BUY4175（REACTION），81是行情位置、15是周期，不是入场价。
2. “然后上去93可↓”是补充SELL4193，应保留此前BUY4175；多空计划分别维护。明确“改到/不做/取消/最新取代”等才移除或替换对应旧计划，完整地图更新后不能复活此前作废方向。
3. 仅有“小区间4175-4200，大区间4150-4220”或“4520-4560区间来回跑”是中性区间，填区间对象用于展示；不能把下沿/上沿推断成老师明确说了BUY/SELL。没有方向原文时不得生成basis=null的plan。区间推导必须另有本次请求的明确授权规则。
4. “来回跑/区间震荡”可标记RANGE；孤立“压力有效”只是关键位说明；符合上述完整区间证据时，才可生成标注来源的AI条件计划。“多单等到/空单等到/可以行动/可上”不需要箭头，也属于有条件入场。
5. “现在90可⬆️”之后同一老师说“86了 注意”，若中间没有取消或相反方向且可唯一承接，应更新为BUY4186，price_ref引用86消息，direction_ref引用90做多消息；不要因新句没写多字就丢弃。若只是行情报数、持仓盈亏或无法唯一关联，则不生成。较晚明确改价替换对应旧入场，不能让旧价和新价一起重复占位。
6. 优先T哥本人。source_role=group_summary是已授权的会后总结，可从该总结本身提取区间和明确方向，as_of填写该总结ID，不能借用其他人的旧方向。普通成员晒单、历史回顾、假设、玩笑不能更新scene。source_role=follow_member仍由独立价格区间通道处理。数字后的“（小压力）/（支撑）”由本地点位角色通道维护，scene.plans仅输出明确入场方向。“收单位置”是退出参考，不是开空指令。“低于/突破/站稳”是额外条件，本协议不能表达，保留summary，不得缩成无条件碰价计划。
7. 默认REACTION，持续有效条件计划由EA在目标上下1.00区内用实时tick检查逆向冲击，不等M1/M5收线。只有老师明确现价/市价/直接进且带数字，才能MARKET；前文的市价请求不能在新场景复活。执行方式由EA决定，模型不控制挂单、市价或手数。
8. previous_scene只帮助记忆，引用必须在context/targets有原文并未撤回。不凭时间自动废掉T哥参考；明确作废、来源失效、新方案覆盖才变。
9. 普通闲聊且不改变场景用KEEP，plans=[]，regime=UNKNOWN，其他证据字段null。确有变更用UPDATE并返回完整仍有效场景；无法可靠确定新交易指令用REVIEW，不能静默继续旧方向。
10. interpretations不能把“多单等到75行动”写成无方向WATCH，应为SETUP；但EA只使用通过校验的scene.plans，不能只在summary写建议而plans为空。summary可以解释突破后观察回踩等，但不能制造没有原文的交易价格、SL、TP、手数。不要把“15分钟连绿”的颜色直接判成趋势方向。
11. 所有引用只用截至as_of的真实消息ID；价格尾数用该消息的market_anchor/previous_scene已验证同token价格复核，不按未来行情重新补全。
12. previous_scene为空时，这是首次建立完整场景：必须结合context里的原文恢复截至as_of仍有效的计划，不能因为最后一句是补充说明就KEEP。没有可确认的计划返回UPDATE空计划；信息不足返回REVIEW。
13. 先判断言语动作和时态，再分配数字角色。“方才最低68，反弹最高80”“方才5点到11点在4615—4625跑了十多个来回”是复盘，不能输出新地图、区间、入场或目标。summary说是复盘时，结构也必须没有由该复盘新增的活动价格。历史回顾不删除previous_scene中原有有效计划。
14. 不得用概率、一般做法或目标高低来猜BUY/SELL。“按照文章计划，4120动手”但文章未提供、也没有明确同组方向依据时必须REVIEW、plans=[]；不能一边说方向不明一边填BUY。只有“↑”“现在”时先WATCH，无数字不造plan，保留原文供后续同组消息承接。
15. 同一老师连续拆句可以组成一个计划：先给↑，随后给完整价格和入场/加仓提示，scene的price_ref引用后一句，direction_ref引用前一句；不要求单句同时含两者。仅缺数字的方向片段不取消原有效计划。下一批“目标统一XXXX”是当前唯一计划组的tp2更新，沿用原price_ref、direction_ref与入场价，不新增入场。不同方向/不同计划组并存又未指明对象则REVIEW。只能关联目标消息之前的计划，不能倒用后来的入场。
16. previous_scene返回的是完整快照，UPDATE时保留仍有效计划及已有exits；不能因新消息只补目标而清空其他已确认字段。改目标不换入场来源、不生成另一个机会；重复输入应得到同一组计划。计划identity由程序维护，不在JSON中新增内部字段。
17. 所有price必须是JSON number；尾数缺数量级时可填null由本地复核，不猜百位。每个新入场数字必须确实承担入场角色：压力75、70可空中的75不是入场，止损/目标/突破阈值也不能借其他句方向变成新入场。破位预测保留说明，不填进无条件目标。加仓间距只解释，推算的后续档位不是原文token，不得伪造价格证据生成scene.plans；后续执行映射另行开发。
18. “以后可以做空的位置”“以后再见可多”“等到/准备/可以/挂”只是在等待价格到达，只要价格和方向明确，就是当前发布的持续有效REACTION参考，不要求此刻已经开仓。多档明确位置各保留一条，不因尚未到价改成WATCH。复盘、假设分支和仅有压力支撑仍需区别。KEEP同样要填写最后老师target的as_of。
19. 当前支撑/压力和角色转换即使逐条标WATCH也会由本地ROLE通道同步到EA；不能把同价已转支撑的旧做空继续解释为有效，反之亦然。仅说冲击/过了便是某价是目标观察，不是该价入场。KEEP不要复制previous_scene字段；REVIEW同样plans为空、区间为空。\n20. 只翻译原文，不判断参考因时间/距离过期；EA负责这些判断。明确重申尽量引用新的点位与方向原文，普通闲聊、仅改目标不能刷新入场时间。取消只影响明确关联的计划；“86空取消”不代表所有空单取消，“挂的多取消”不代表整张地图取消。禁止因行情远离而自行从场景中删掉价格。
"""


RANGE_INFERENCE_PROMPT = """
本次另行授权的AI区间推导：同一老师明确当前区间震荡/来回跑，给出区间数值，并强调该区间两头重要，或明确该端支撑/压力重要时，生成下沿BUY、上沿SELL的REACTION计划，basis标记RANGE_EDGE并指定区间。direction_ref引用边界角色/重要性，regime_ref引用震荡原文，summary写明AI推导，不能冒充明确喊单。
例：“行情在区间来回跑”“大区间参考4150--4220”“大区间的两头为重要点位”，可生成BUY4150、SELL4220的RANGE_EDGE计划，同时保留明确的其他参考。完整地图首尾不能冒充已声明区间；假设震荡、趋势单边、突破后的旧边界不能推导。缺少证据不生成。最多4条，优先明确方向、其次被强调的边界；同价已有明确计划则不重复推导。
"""


def non_current_evidence(text, quote):
    """检查证据所在语段，不能靠截掉“方才”把复盘变成现行计划。"""
    if not isinstance(quote,str) or not quote or quote not in text:
        return True
    positions=[m.end() for m in re.finditer(re.escape(quote),text)]
    for end in positions:
        # 显式重新发布后的部分可成为新参考，早先的复盘不污染后半句。
        segment=re.split(r'现在|当前|今日|今天|最新|重新|接下来',text[:end])[-1]
        if re.search(r'方才|刚才|昨天|前天|历史|回顾|复盘|晒单|转发|引用|假设|开玩笑',segment):
            return True
    return False


def direction_side(text):
    buy=bool(re.search(r'↑|⬆|做多|买入|多单|(?<![太很许更])多(?!拿|少)',text))
    sell=bool(re.search(r'↓|⬇|做空|卖出|空单|空(?!间)',text))
    return ('BUY' if buy else 'SELL') if buy!=sell else None


def direction_fragment(text):
    """只接续尚无价格的方向短句，不把观点/保护/否定当缺价喊单。"""
    return direction_side(text) if re.fullmatch(r'[\s↑↓⬆⬇\ufe0f。.！!，,]*(?:(?:现在|准备|做多|做空|买入|卖出)[\s↑↓⬆⬇\ufe0f。.！!，,]*)*',text) else None


def same_plan_price(token, plan):
    # 仅匹配已验证计划的完整价/尾数，不用当前行情给旧消息重新补百位。
    if token in (plan['token'], format(plan['price'], 'g')):
        return True
    return token.isdigit() and len(token) in (2,3) and abs(plan['price'] % (10**len(token))-int(token))<0.001


def renew_confirmed_plans(plans, item):
    """只给能唯一对应原价的明确重申续期；不让模型填写时间或用闲聊续期。"""
    text = item.get('text', '')
    if (item.get('historical') or item.get('deleted') or
        not re.search(r'继续有效|依然有效|仍然有效|依旧有效|依然还是|仍然还是|还是刚才|再发一遍|重新确认', text) or
        re.search(r'取消|作废|撤销|不做|别做|无效|不再|是否|吗|？|\?|假设|复盘|晒单|转发', text)):
        return False
    changed = False
    for clause in re.split(r'[，,；;\n]', text):
        if (not re.search(r'继续有效|依然有效|仍然有效|依旧有效|依然还是|仍然还是|还是刚才|再发一遍|重新确认',clause)
            or re.search(r'止损|止盈|目标|保本|昨天|方才|曾经', clause)):
            continue
        numbers = re.findall(r'(?<![\d.])\d{1,5}(?:\.\d{1,2})?(?![\d.])', clause)
        for token in numbers:
            matches = [p for p in plans if not p.get('basis') and same_plan_price(token,p)]
            # 同价双向或仅尾数无法唯一对应时不猜续期对象。
            side = direction_side(clause)
            if side:
                matches = [p for p in matches if p['side'] == side]
            if len(matches) != 1:
                continue
            plan = matches[0]
            at = stamp(item['time'])
            if at > plan.get('confirmed_at', plan.get('origin_created', 0)):
                plan['confirmed_at'] = at
                plan['confirmed_ref'] = dict(message_id=item['message_id'], revision=item['revision'])
                changed = True
    return changed


def cancels_plan(item, plan):
    """取消数字有范围：86空取消不能把另一价格的空单也判为已取消。"""
    text=item.get('text','')
    if item.get('historical') or item.get('deleted') or not re.search(r'取消|作废|撤销|不做|别做|暂停',text):
        return False
    interpretation=item.get('interpretation') or {}
    all_sides=bool(re.search(r'^(?:取消|作废|撤销)(?:全部|所有|前面|之前|计划|参考)|^(?:全部|所有)(?:取消|作废|撤销)|^暂停(?:交易|计划|参考)',text.strip()))
    word='多' if plan['side']=='BUY' else '空'
    same_side=bool(re.search(r'(?:取消|作废|撤销|不做|别做)\s*(?:做)?'+word+r'|'+word+r'(?:单)?\s*(?:可以|先|都|全部)?\s*(?:取消|作废|撤销)',text))
    matched=all_sides or same_side or interpretation.get('kind')=='CANCEL' and interpretation.get('cancel_side') in ('ALL',plan['side'])
    if not matched:
        return False
    numbers=re.findall(r'(?<![\d.])\d{2,5}(?:\.\d{1,2})?(?![\d.])',text)
    return not numbers or any(same_plan_price(t,plan) for t in numbers)


def validate_scene(value, targets, context, anchor, previous=None):
    from deepseek_ai import AIError, resolve_token
    keys={'as_of','action','regime','regime_ref','plans','inner_range','outer_range','summary'}
    if not isinstance(value,dict) or set(value)!=keys:
        raise AIError('AI场景字段不完整')
    value=copy.deepcopy(value)
    if value['action'] not in ('KEEP','UPDATE','REVIEW') or value['regime'] not in ('UNKNOWN','RANGE','TREND_UP','TREND_DOWN'):
        raise AIError('AI场景状态无效')
    if not isinstance(value['summary'],str) or len(value['summary'])>400:
        raise AIError('AI场景说明无效')
    teacher=[t for t in targets if t.get('source_role') in ('teacher','group_summary') and not t.get('historical')]
    if not teacher:
        if value['as_of']!='' or value['action']!='KEEP':
            raise AIError('无老师新消息不能更新场景')
        return None
    latest=teacher[-1]
    # KEEP没有业务变更，处理到哪条消息由调用方确定，避免空as_of造成闲聊无限重试。
    if value['action']=='KEEP' and value['as_of']=='':
        value['as_of']=latest['message_id']
    if value['as_of']!=latest['message_id']:
        raise AIError('AI场景必须截至最新老师消息')
    if not isinstance(value['plans'],list) or len(value['plans'])>4:
        raise AIError('AI场景计划数量无效')
    if value['action']=='KEEP' and ((latest.get('interpretation') or {}).get('kind') in ('CANCEL','SETUP') or re.search(r'取消|作废|撤销|不做多|不做空|别做多|别做空|暂停',latest['text'])):
        raise AIError('明确新增/取消不能被KEEP忽略')
    if value['action']!='UPDATE':
        if value['plans'] or value['regime']!='UNKNOWN' or any(value[k] is not None for k in ('regime_ref','inner_range','outer_range')):
            # REVIEW永远不执行携带字段。KEEP仅容忍逐字段复述已验证旧场景，
            # 不能借格式修复接受新价格、新方向或让明确新增/取消失效。
            def plan_data(p):
                keys=('side','token','price','mode','price_ref','price_evidence','direction_ref','direction_evidence','exits','basis')
                if not isinstance(p,dict): return p
                data={k:p.get(k) for k in keys}
                data['exits']={k:(p.get('exits') or {}).get(k) for k in ('sl','tp1','tp2','breakeven')}
                return data
            echo=bool(previous)
            if value['plans']:
                remaining=[plan_data(p) for p in (previous or {}).get('plans',[])]
                for p in value['plans']:
                    data=plan_data(p)
                    if data not in remaining:
                        echo=False
                        break
                    remaining.remove(data)
                echo=echo and not remaining
            for key in ('regime','regime_ref','inner_range','outer_range'):
                if value[key] not in (None,'UNKNOWN'):
                    echo=echo and value[key]==(previous or {}).get(key)
            if value['action']=='KEEP' and not echo:
                raise AIError('KEEP夹带新增或变更计划，等待重新解释')
            value.update(plans=[],regime='UNKNOWN',regime_ref=None,inner_range=None,outer_range=None)
        return dict(value,source_role=latest.get('source_role','teacher'),created=stamp(latest['time']),sequence=latest['sequence'],
                    revision=latest['revision'],sender=latest['sender_id'],source_refs=[
                        dict(message_id=latest['message_id'],revision=latest['revision'])])
    items={m['message_id']:m for m in context+targets if m.get('message_id')}
    refs={}
    def evidence(mid, quote):
        item=items.get(mid) if isinstance(mid,str) else None
        if (not item or item.get('source_role') not in ('teacher','group_summary') or item.get('sender_id')!=latest['sender_id'] or
            item.get('historical') or item.get('deleted') or not item.get('revision') or
            (stamp(item['time']),item.get('sequence',0))>(stamp(latest['time']),latest['sequence']) or
            not isinstance(quote,str) or not quote or quote not in item['text']):
            raise AIError('AI场景引用缺少有效老师原文')
        if non_current_evidence(item['text'],quote):
            raise AIError('复盘/假设语段不能成为当前场景证据')
        refs[mid]=dict(message_id=mid,revision=item['revision'])
        return item
    def price(proof):
        if not isinstance(proof,dict) or set(proof)!={'message_id','token','price','evidence'}:
            raise AIError('AI场景价格证据字段无效')
        item=evidence(proof['message_id'],proof['evidence'])
        token=proof['token'];number=proof['price']
        if not isinstance(token,str) or not re.fullmatch(r'\d{1,5}(?:\.\d{1,2})?',token) or not re.search(r'(?<![\d.])'+re.escape(token)+r'(?![\d.])',proof['evidence']):
            raise AIError('AI场景价格不在原文或数字被截断')
        item_anchor=item.get('market_anchor',0)
        if not item_anchor:
            # 保留旧场景的价格必须保持原来核验的数量级，不拿实时行情补旧尾数。
            old_plans=(previous or {}).get('plans',[])
            match=next((p for p in old_plans if p['token']==token and p['price_ref']==proof['message_id']),None)
            item_anchor=match['price'] if match else (float(token) if len(token.split('.')[0])>=4 else 0)
        resolved=resolve_token(token,item_anchor)
        if number is None or isinstance(number,str) and re.fullmatch(r'\d+(?:\.\d+)?',number) and abs(float(number)-resolved)<=0.001:
            number=resolved
        if isinstance(number,bool) or not isinstance(number,(int,float)) or not math.isfinite(number):
            raise AIError('AI场景价格不是有限数')
        if abs(number-resolved)>0.001:
            raise AIError('AI场景价格补全未通过原时点复核')
        if re.search(r'(?:EMA|MA|ATR|RSI|ADX|MACD)\s*'+re.escape(token),proof['evidence'],re.I):
            raise AIError('指标周期不是入场价')
        proof['price']=resolved
        return resolved
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
    clean=[]
    for plan in value['plans']:
        required={'side','token','price','mode','price_ref','price_evidence','direction_ref','direction_evidence'}
        if not isinstance(plan,dict) or not required<=set(plan) or set(plan)-required-{'exits','basis'} or plan['side'] not in ('BUY','SELL') or plan['mode'] not in ('REACTION','MARKET'):
            raise AIError('AI场景计划字段无效')
        plan['price']=price(dict(message_id=plan['price_ref'],token=plan['token'],price=plan['price'],evidence=plan['price_evidence']))
        direction=evidence(plan['direction_ref'],plan['direction_evidence'])
        buy=bool(re.search(r'↑|⬆|做多|买入|多单|(?<![太很许更])多(?!拿|少)',plan['direction_evidence']))
        sell=bool(re.search(r'↓|⬇|做空|卖出|空单|空(?!间)',plan['direction_evidence']))
        basis=plan.get('basis')
        if basis is not None:
            if not isinstance(basis,dict) or set(basis)!={'kind','range'} or basis['kind']!='RANGE_EDGE' or basis['range'] not in ('inner_range','outer_range'):
                raise AIError('AI区间推导依据字段无效')
            band=value[basis['range']]
            if value['regime']!='RANGE' or not band or plan['mode']!='REACTION' or plan.get('exits') is not None and (not isinstance(plan['exits'],dict) or any(plan['exits'].values())):
                raise AIError('AI区间推导仅支持有依据的震荡条件计划，不推算退出价')
            rhythm=value['regime_ref']['evidence']
            if not re.search(r'震荡|来回|区间',rhythm) or re.search(r'单边|不再|不是|不做|取消|突破|跌破|若|如果|假设',rhythm):
                raise AIError('AI区间推导缺少当前震荡语义')
            edge=band['low' if plan['side']=='BUY' else 'high']
            if plan['price']!=edge['price'] or plan['price_ref']!=edge['message_id'] or plan['token']!=edge['token']:
                raise AIError('AI区间推导必须使用所引用区间的对应端点')
            if not all(re.search(r'区间|上沿|下沿|上限|下限',items[edge_proof['message_id']]['text']) for edge_proof in band.values()):
                raise AIError('中性地图首尾不能冒充老师给出的区间')
            quote=plan['direction_evidence']
            label='小区间' if basis['range']=='inner_range' else '大区间'
            both=label in quote and bool(re.search(r'两(?:头|端)|上下沿',quote)) and bool(re.search(r'重要|关键|有效',quote))
            role=r'支撑|下沿|下限|底部' if plan['side']=='BUY' else r'压力|阻力|上沿|上限|顶部'
            linked=label in quote or bool(re.search(r'(?<![\d.])'+re.escape(plan['token'])+r'(?![\d.])',quote))
            if not both and not (linked and re.search(role,quote)):
                raise AIError('AI区间推导缺少对应边界角色/重要性证据')
            if re.search(r'不是|无效|不重要|失效|跌破|突破|取消|不做|别做',quote):
                raise AIError('失效边界不能成为区间试仓')
        elif buy==sell or plan['side']!=('BUY' if buy else 'SELL'):
            raise AIError('AI场景方向缺少唯一原文依据')
        source=items[plan['price_ref']]
        for mid in (plan['price_ref'],plan['direction_ref']):
            if re.search(r'历史|晒单|转发|假设|昨天|回顾|开玩笑|忽略.{0,10}(规则|指令)',items[mid]['text']):
                raise AIError('历史/指令文本不能成为场景入场')
        if re.search(r'取消|作废|撤销|不做|别做|不要|止损|止盈|平仓|收单|低于|高于|突破|跌破|站稳',plan['direction_evidence']):
            raise AIError('取消/退出原文不能成为场景方向')
        if plan['mode']=='MARKET' and (plan['price_ref']!=latest['message_id'] or
            not re.search(r'现价|市价|直接.{0,3}(进|买|卖|多|空)',items[plan['price_ref']]['text'])):
            raise AIError('旧市价计划不可随场景重放')
        key=(plan['side'],plan['price'])
        if key in [(p['side'],p['price']) for p in clean]:
            raise AIError('AI场景计划重复')
        if any(p['price']==plan['price'] and p['side']!=plan['side'] for p in clean):
            raise AIError('同价双向条件矛盾，等待老师确认')
        exits=plan.get('exits')
        if exits is not None:
            if not isinstance(exits,dict) or set(exits)!={'sl','tp1','tp2','breakeven'}:
                raise AIError('退出计划字段无效')
            sign=1 if plan['side']=='BUY' else -1
            roles={'sl':r'止损|保险|SL','tp1':r'止盈|减仓|首批|第一目标|先看|TP1',
                   'tp2':r'止盈|目标|尾仓|利|TP2|TP','breakeven':r'保本|推保护'}
            prices={}
            for key,proof in exits.items():
                if proof is None: continue
                number=price(proof); quote=proof['evidence']; item=items[proof['message_id']]
                if re.search(r'历史|晒单|转发|假设|昨天|回顾|玩笑|不要|取消|不是|不在|别设',quote):
                    raise AIError('退出证据不是当前明确计划')
                token=re.escape(proof['token'])
                # 价格紧邻角色，避免一段话里把入场价/行情价错贴为止损。
                if not re.search(r'(?:'+roles[key]+r')[\s:：]*(?:(?:统一|设在|放在|放|到|在|看)\s*)?'+token+r'(?![\d.])|(?<![\d.])'+token+r'\s*(?:'+roles[key]+r')',quote,re.I):
                    raise AIError('退出价格缺少明确角色')
                same_source=proof['message_id']==plan['price_ref'] and sum(p['price_ref']==plan['price_ref'] for p in value['plans'])==1
                source_buy=bool(re.search(r'做多|多单|买入|↑',item['text']))
                source_sell=bool(re.search(r'做空|空单|卖出|↓',item['text']))
                same_source=same_source and source_buy!=source_sell and source_buy==(sign==1)
                entry_tokens=(plan['token'],format(plan['price'],'g'))
                has_entry=any(re.search(r'(?<![\d.])'+re.escape(t)+r'(?![\d.])',quote) for t in entry_tokens)
                has_buy=bool(re.search(r'做多|多单|买入|↑',quote));has_sell=bool(re.search(r'做空|空单|卖出|↓',quote))
                group={(p['side'],p['direction_ref']) for p in value['plans']}
                uniform=(key=='tp2' and bool(re.search(r'目标\s*统一|统一\s*(?:目标|止盈)',quote)) and
                         len(group)==1 and not any(p.get('basis') for p in value['plans']) and
                         (stamp(item['time']),item.get('sequence',0))>=
                         (stamp(source['time']),source.get('sequence',0)))
                # 不允许通过漏掉另一侧来“制造唯一组”；明确关联仍走原有入场价+方向路径。
                if uniform and previous:
                    uniform=all((p['side'],p['direction_ref']) in group for p in previous.get('plans',[]))
                if uniform:
                    group_sources={p[k] for p in value['plans'] for k in ('price_ref','direction_ref')}
                    for other in items.values():
                        if (other['message_id'] not in group_sources and other.get('sender_id')==latest['sender_id'] and
                            (stamp(source['time']),source.get('sequence',0))<
                            (stamp(other['time']),other.get('sequence',0))<
                            (stamp(item['time']),item.get('sequence',0)) and
                            not other.get('historical') and not other.get('deleted') and
                            direction_side(other['text']) and not non_current_evidence(other['text'],other['text']) and
                            not re.search(r'止损|止盈|目标|保险|保本',other['text'])):
                            uniform=False
                if not same_source and not uniform and not (has_entry and has_buy!=has_sell and has_buy==(sign==1)):
                    raise AIError('退出计划无法唯一关联入场')
                if sign*(number-plan['price'])*( -1 if key=='sl' else 1)<=0:
                    raise AIError('退出价格方向无效')
                prices[key]=number
            if prices.get('tp1') and prices.get('tp2') and sign*(prices['tp2']-prices['tp1'])<=0:
                raise AIError('首批与尾仓目标顺序无效')
        source=items[plan['price_ref']]
        # 价格只证明数值，不给方向续期：从方向证据开始核对其取消生命周期。
        # 取消后有新的明确方向时，以新方向来源重新建立；较早价格证据仍单独校验。
        start=(stamp(direction['time']),direction.get('sequence',0))
        for item in items.values():
            if item.get('sender_id')!=latest['sender_id'] or (stamp(item['time']),item.get('sequence',0))<=start:
                continue
            if cancels_plan(item,plan):
                raise AIError('AI场景不得复活取消前的旧方向')
        source=items[plan['price_ref']]
        if basis is None and plan['price_ref']!=plan['direction_ref']:
            if re.search(r'文章|图里|图中|会议|直播',source['text']) and not direction_side(plan['price_evidence']):
                raise AIError('引用材料未提供明确方向，不能借旧方向猜入场')
            if direction_fragment(direction['text']):
                gap=stamp(source['time'])-stamp(direction['time'])
                if not 0<=gap<=300:
                    raise AIError('缺价方向短句不属于同一段连续发言')
                for other in items.values():
                    if (other.get('sender_id')==latest['sender_id'] and
                        (stamp(direction['time']),direction.get('sequence',0))<
                        (stamp(other['time']),other.get('sequence',0))<
                        (stamp(source['time']),source.get('sequence',0)) and
                        not other.get('historical') and not other.get('deleted') and
                        direction_side(other['text']) not in (None,plan['side']) and
                        not non_current_evidence(other['text'],other['text'])):
                        raise AIError('连续短句出现相反方向，不能选择旧箭头')
            if direction_side(plan['price_evidence']) not in (None,plan['side']):
                raise AIError('当前入场方向与承接方向冲突')
            if not re.search(r'注意|关注|准备|行动|可|进|上车|加|上货|改到|换到|移到|动手',source['text']) and not direction_side(plan['price_evidence']):
                raise AIError('单纯行情报数不能借前文方向变成入场')
            if re.search(r'(?:止损|止盈|目标|保险|保本|压力|支撑)\s*(?:统一|改到|到|在|是|为)?\s*'+re.escape(plan['token']),plan['price_evidence']) and not direction_side(plan['price_evidence']):
                raise AIError('保护/目标/压力数字不能借方向变成入场')
        # 相同仍有效价位的形式编辑/重述继承机会身份，实际来源版本仍单独校验。
        prior=next((p for p in (previous or {}).get('plans',[]) if p['side']==plan['side'] and p['price']==plan['price'] and p['mode']==plan['mode']),None)
        origin_revision=hashlib.sha256(json.dumps([source['message_id'],direction['message_id'],plan['side'],plan['price'],plan['mode']],ensure_ascii=False).encode('utf-8')).hexdigest()
        plan=dict(plan,near=False,origin_id=prior.get('origin_id',source['message_id']) if prior else source['message_id'],
                  origin_revision=prior.get('origin_revision',origin_revision) if prior else origin_revision,
                  origin_created=prior.get('origin_created',stamp(source['time'])) if prior else stamp(source['time']))
        # 采用通过原文校验的入场/方向时间，退出价修改不属于入场重申。
        proof_at=max(stamp(source['time']),stamp(direction['time']))
        plan['confirmed_at']=max(proof_at,(prior or {}).get('confirmed_at',0))
        if prior and prior.get('confirmed_ref') and prior.get('confirmed_at',0)>proof_at:
            plan['confirmed_ref']=prior['confirmed_ref']
            refs[prior['confirmed_ref']['message_id']]=prior['confirmed_ref']
        clean.append(plan)
    for item in teacher:
        if renew_confirmed_plans(clean,item):
            refs[item['message_id']]=dict(message_id=item['message_id'],revision=item['revision'])
    refs[latest['message_id']]=dict(message_id=latest['message_id'],revision=latest['revision'])
    return dict(value,source_role=latest.get('source_role','teacher'),plans=clean,created=stamp(latest['time']),sequence=latest['sequence'],
                revision=latest['revision'],sender=latest['sender_id'],source_refs=list(refs.values()),
                map_only=not clean and (latest.get('interpretation') or {}).get('kind')=='MAP')


def validate_execution_scene(value, targets, context, anchor, previous=None):
    """无效的附加区间推导不能阻断独立、完整通过校验的明确计划。"""
    from deepseek_ai import AIError
    try:
        return validate_scene(value,targets,context,anchor,previous)
    except AIError as error:
        plans=value.get('plans') if isinstance(value,dict) else None
        if not isinstance(plans,list) or not plans or not all(isinstance(p,dict) for p in plans):
            raise
        if str(error)=='AI场景方向缺少唯一原文依据':
            # 模型把已声明区间的端点/破位预测误标为直接喊单时，仅纠正类型。
            # 引用、时态、上下沿及其他计划随后全部重验；文章缺方向等错误不能走此路径。
            edges=[proof for name in ('inner_range','outer_range')
                   for proof in (value.get(name) or {}).values() if isinstance(proof,dict)]
            unsupported=[p for p in plans if not p.get('basis') and
                         isinstance(p.get('direction_evidence'),str) and not direction_side(p['direction_evidence']) and
                         p.get('price_ref')==p.get('direction_ref') and
                         (any(p.get('price_ref')==edge.get('message_id') and p.get('token')==edge.get('token')
                              and p.get('price')==edge.get('price') for edge in edges) or
                          any(p.get('price_ref')==edge.get('message_id') for edge in edges) and
                          re.search(r'破|新高|新低',p['direction_evidence']) and
                          re.search(r'若|如果|则|有望',p['direction_evidence']))]
            if unsupported:
                direct=[p for p in plans if p not in unsupported]
                keys={'side','token','price','mode','price_ref','price_evidence','direction_ref','direction_evidence','exits','basis'}
                for old in (previous or {}).get('plans',[]):
                    if not any((p['side'],p['price'])==(old['side'],old['price']) for p in direct):
                        direct.append({k:v for k,v in old.items() if k in keys})
                clean=validate_scene(dict(value,plans=direct),targets,context,anchor,previous)
                clean['semantic_correction']='无明确方向的区间端点/破位预测只保留参考，不生成直接计划'
                clean['summary']=clean['semantic_correction']
                return clean
        direct=[p for p in plans if not p.get('basis')]
        if not direct or len(direct)==len(plans):
            raise
        # 只去掉新增推导；明确计划、区间、来源、取消生命周期仍完整重验。
        clean=validate_scene(dict(value,plans=direct),targets,context,anchor,previous)
        clean['inference_rejection']=str(error)
        clean['summary']='附加AI区间推导未通过校验，仅保留明确计划：'+', '.join(
            p['side']+' '+format(p['price'],'g') for p in clean['plans'])
        return clean


def publish_scene(db, c, scene):
    from deepseek_ai import refs_current
    if not scene:
        return
    if scene.get('source_role')=='group_summary':
        previous=state(db,'meeting_scene',{})
        if (scene['action'] in ('UPDATE','REVIEW') and refs_current(db,c['chat_id'],scene['source_refs']) and
            (scene['created'],scene['sequence']) >= (previous.get('created',0),previous.get('sequence',0))):
            set_state(db,'meeting_scene',scene)
        return
    previous=state(db,'teacher_scene',{})
    if (scene['created'],scene['sequence'])<(previous.get('created',0),previous.get('sequence',0)):
        return
    if not refs_current(db,c['chat_id'],scene['source_refs']):
        return
    if scene['action']=='KEEP':
        # KEEP可包含“75继续有效”，本地按唯一价格关联重申，不用AI编造续期。
        if not previous or not refs_current(db,c['chat_id'],previous.get('source_refs',[])):
            return
        row=db.execute('SELECT * FROM messages WHERE chat_id=? AND message_id=?',
                       (c['chat_id'],scene['as_of'])).fetchone()
        if not row or row['sender']!=c['teacher_sender_id'] or row['deleted'] or row['historical']:
            return
        raw=json.loads(row['raw']); text=raw.get('content','')
        if not isinstance(text,str):
            return
        retained=copy.deepcopy(previous)
        item=dict(text=text,time=row['created'],message_id=row['message_id'],revision=row['revision'])
        if not renew_confirmed_plans(retained.get('plans',[]),item):
            return
        refs={r['message_id']:r for r in previous['source_refs']+scene['source_refs']}
        retained.update(as_of=scene['as_of'],created=scene['created'],sequence=scene['sequence'],
                        revision=scene['revision'],source_refs=list(refs.values()),summary='老师明确重申对应点位')
        scene=retained
    if scene['action']=='REVIEW':
        set_state(db,'deepseek_review',dict(message_id=scene['as_of'],created=scene['created'],reason=scene['summary']))
        return
    set_state(db,'teacher_scene',scene)
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
