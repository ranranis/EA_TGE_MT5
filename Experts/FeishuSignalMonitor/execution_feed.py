"""v1.42执行快照：模型翻译原文，优先级和区间方向由已约定规则确定。"""
import csv
import hashlib
import io
import json
import re
from store import state, set_state
from deepseek_ai import lane_readiness, refs_current, pending_window_start


def execution_csv(db, c, now, paused, context, map_active, levels, ai, protocol=6):
    # 单个完整快照同时替换三类参考；删去的行即撤销，不依赖事件补发。
    healthy = (not paused and state(db, 'last_sync_ok', False)
               and 0 <= now-state(db, 'last_sync_at', 0) <= c['sync_max_age_seconds']
               and 0 <= now-state(db, 'checkpoint', 0) <= c['sync_max_age_seconds'])
    review = state(db, 'deepseek_review', {})
    scene = state(db, 'teacher_scene', {})
    setup = state(db, 'deepseek_setup', {})
    ready = not c.get('ai_enabled') or lane_readiness(db, c, now)['teacher_ready']
    reviewing = bool(review.get('message_id') and review.get('created', 0) >= setup.get('created', 0))
    # TGA7只让AI提供已校验数据，不让请求超时/排队冻结已有参考。
    # 待解析的明确取消/暂停先阻断，不能在AI故障期间忽略老师撤销意图。
    cancel_pending = False
    if protocol == 7 and not ready:
        pending = db.execute('''SELECT m.raw FROM messages m LEFT JOIN ai_messages a
            ON a.chat_id=m.chat_id AND a.message_id=m.message_id AND a.revision=m.revision
            WHERE m.chat_id=? AND m.sender=? AND m.historical=0 AND m.deleted=0
            AND m.created>=? AND m.created<=? AND (a.status IS NULL OR a.status='RETRY')''',
            (c['chat_id'], c['teacher_sender_id'], pending_window_start(db, now), now+5))
        for row in pending:
            text = json.loads(row['raw']).get('content', '')
            if isinstance(text, str) and re.search(r'取消|作废|撤销|不做了|不做多|不做空|别做多|别做空|暂停|失效|无效', text):
                cancel_pending = True
                break
    active = bool(healthy and not reviewing and (not cancel_pending if protocol == 7 else ready))
    fallback = bool(protocol == 7 and c.get('ai_enabled') and
                    (not ready or state(db, 'deepseek_status', {}).get('online') is False))
    if not healthy:
        note = '暂停：监控已暂停或飞书同步异常'
    elif reviewing or cancel_pending:
        note = '暂停：老师撤销/语义待确认'
    elif active and fallback:
        note = 'AI待解析或暂不可用；沿用已确认点位'
    else:
        note = '点位触价：明确方向8 / 区间6 / 地图5' if active else '暂停：等待AI解析'
    rows = []

    def add(kind, priority, side, price, source, revision, created, group, exits=None, confirmed=None, mode='REFERENCE'):
        exits = exits or {}
        # 身份不包含心跳/说明/退出价；只改目标不会把同一入场变成新机会。
        plan_id = hashlib.sha256(f'{kind}|{group}|{side}|{price:g}'.encode('utf-8')).hexdigest()[:24]
        rows.append(['PLAN', plan_id, kind, priority, side, f'{price:.10f}', source,
                     revision, int(created), group,
                     *[f'{(exits.get(key) or {}).get("price", 0):.10f}' for key in ('sl', 'tp1', 'tp2', 'breakeven')]])
        if protocol == 7:
            rows[-1].extend([int(confirmed if confirmed is not None else created), mode])

    # 新协议保留已验证的旧计划供显示，失效计算由EA完成；心跳不能续期。
    direct = ai
    if protocol == 7:
        valid = (c.get('ai_enabled') and setup.get('sender') == c['teacher_sender_id']
                 and setup.get('mode') == 'SETUP' and setup.get('source_refs')
                 and refs_current(db, c['chat_id'], setup['source_refs']))
        direct = dict(setup, active=bool(valid))
    # 新地图淘汰更早且范围外的明确方向；本地记住淘汰时间，重启/旧AI结果不复活。
    scope = dict(chat_id=c['chat_id'], teacher_id=c['teacher_sender_id'],
                 symbol=c['symbols'][c['teacher_symbol']])
    retired = state(db, 'map_retired_directions', {}) if protocol == 7 else {}
    if any(retired.get(k) != v for k, v in scope.items()):
        retired = dict(scope, plans={})
    retired_changed = False
    map_time = context.get('created', 0) if map_active and len(levels) >= 3 else 0
    if direct.get('active'):
        for p in direct.get('plans', []):
            if p.get('basis'):  # AI的旧区间推导不用作直接喊单，区间在下方确定性映射。
                continue
            origin = p.get('origin_id', direct.get('message_id', ''))
            revision = p.get('origin_revision', direct.get('revision', ''))
            created = p.get('origin_created', direct.get('created', 0))
            confirmed = p.get('confirmed_at', created)
            if protocol == 7:
                key = hashlib.sha256(f"DIRECT|{origin}|{revision}|{p['side']}|{p['price']:g}".encode('utf-8')).hexdigest()[:24]
                if map_time > confirmed and not min(levels) <= p['price'] <= max(levels):
                    if map_time > retired['plans'].get(key, 0):
                        retired['plans'][key] = map_time
                        retired_changed = True
                if key in retired['plans'] and confirmed <= retired['plans'][key]:
                    continue
            add('DIRECT', 8, p['side'], p['price'], origin, revision,
                created, origin+'|'+revision, p.get('exits'), confirmed, p['mode'])
    if retired_changed:
        with db:
            set_state(db, 'map_retired_directions', retired)

    # 明确给出的大小区间无需AI臆造方向：下沿BUY、上沿SELL标成规则推导。
    # 即使scene无直接计划、旧ai_snapshot为WAIT，合法的区间仍可独立使用。
    scene_valid = (c.get('ai_enabled') and scene.get('sender') == c['teacher_sender_id'] and scene.get('source_refs')
                   and refs_current(db, c['chat_id'], scene['source_refs']))
    if scene_valid:
        for name, kind in [('inner_range', 'INNER'), ('outer_range', 'OUTER')]:
            band = scene.get(name)
            if not band:
                continue
            group = kind+'|'+str(band['low']['price'])+'|'+str(band['high']['price'])
            for edge, side in [('low', 'BUY'), ('high', 'SELL')]:
                p = band[edge]
                ref = next(r for r in scene['source_refs'] if r['message_id'] == p['message_id'])
                created = scene['created']
                if protocol == 7:
                    created = db.execute('SELECT created FROM messages WHERE chat_id=? AND message_id=?',
                                         (c['chat_id'], p['message_id'])).fetchone()[0]
                add(kind, 6, side, p['price'], p['message_id'], ref['revision'], created, group)
    if map_active:
        group = 'MAP|'+'|'.join(f'{v:g}' for v in levels)
        for price in levels:
            add('MAP', 5, 'AUTO', price, context['message_id'], context['revision'], context['created'], group)
    if protocol == 7 and active and not rows:
        active = False
        note = '等待已确认点位'
    rows.sort(key=lambda row: (-row[3], -row[8], row[5], row[4]))
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\r\n')
    writer.writerow(['TGA', str(protocol), int(now), int(active), c['symbols'][c['teacher_symbol']], len(rows), note])
    writer.writerows(rows)
    writer.writerow(['END', len(rows)])
    return output.getvalue()
