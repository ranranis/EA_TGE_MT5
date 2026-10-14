"""v1.42执行快照：模型翻译原文，优先级和区间方向由已约定规则确定。"""
import csv
import hashlib
import io
from store import state
from deepseek_ai import lane_readiness, refs_current


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
    active = bool(healthy and ready and not reviewing)
    note = '点位触价：明确方向8 / 区间6 / 地图5' if active else '暂停：同步、待解析或语义待确认'
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
    if direct.get('active'):
        for p in direct.get('plans', []):
            if p.get('basis'):  # AI的旧区间推导不用作直接喊单，区间在下方确定性映射。
                continue
            origin = p.get('origin_id', direct.get('message_id', ''))
            revision = p.get('origin_revision', direct.get('revision', ''))
            created = p.get('origin_created', direct.get('created', 0))
            add('DIRECT', 8, p['side'], p['price'], origin, revision,
                created, origin+'|'+revision, p.get('exits'), p.get('confirmed_at', created), p['mode'])

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
    rows.sort(key=lambda row: (-row[3], -row[8], row[5], row[4]))
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\r\n')
    writer.writerow(['TGA', str(protocol), int(now), int(active), c['symbols'][c['teacher_symbol']], len(rows), note])
    writer.writerows(rows)
    writer.writerow(['END', len(rows)])
    return output.getvalue()
