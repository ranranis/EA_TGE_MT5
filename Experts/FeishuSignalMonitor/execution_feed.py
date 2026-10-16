"""v1.42执行快照：模型翻译原文，优先级和区间方向由已约定规则确定。"""
import csv
import hashlib
import io
import json
import re
from datetime import datetime
from store import state, set_state
from deepseek_ai import lane_readiness, refs_current, pending_window_start
from point_inputs import manual_points, annotated_roles, reference_only_prices, teacher_role_points, PRIORITIES
from teacher_strategy import summary_source
from teacher_scene import cancels_plan
from point_editor import remember_auto, merge_rows, cancel_manual_rows


def ai_status_note(db, c, now, fallback):
    status=state(db,'deepseek_status',{})
    pending=lane_readiness(db,c,now)['backlog']
    error=status.get('error','')
    if error.startswith('AI正在'):
        label='AI正在解析'
    elif fallback:
        label='AI解析异常' if error else 'AI等待解析'
        if 'AI场景' in error or '引用' in error or '校验' in error:
            label+='：语义校验'
        elif any(word in error for word in ('连接','凭证','timeout','超时','响应')):
            label+='：连接/响应'
    else:
        label='AI解析就绪'
    last=status.get('last_success',0)
    stamp=datetime.fromtimestamp(last).strftime('%m-%d %H:%M') if last else '暂无记录'
    note=f'{label} · 待{pending}条 · 最近成功 {stamp}'
    return note+(' · 沿用已确认点位' if fallback else '')


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
    if protocol >= 7 and not ready:
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
    active = bool(healthy and not reviewing and (not cancel_pending if protocol >= 7 else ready))
    fallback = bool(protocol >= 7 and c.get('ai_enabled') and
                    (not ready or state(db, 'deepseek_status', {}).get('online') is False))
    if not healthy:
        note = '暂停：监控已暂停或飞书同步异常'
    elif reviewing or cancel_pending:
        note = '暂停：老师撤销/语义待确认'
    elif active and fallback:
        note = ai_status_note(db,c,now,True)
    elif active and protocol >= 7 and c.get('ai_enabled'):
        note = ai_status_note(db,c,now,False)
    else:
        note = ('点位排序：明确指令 / 区间 / 支撑压力 / 中性地图' if protocol>=8 else '点位触价：明确方向8 / 区间6 / 地图5') if active else '暂停：等待AI解析'
    rows = []

    def add(kind, priority, side, price, source, revision, created, group, exits=None, confirmed=None, mode='REFERENCE'):
        exits = exits or {}
        # 身份不包含心跳/说明/退出价；只改目标不会把同一入场变成新机会。
        plan_id = hashlib.sha256(f'{kind}|{group}|{side}|{price:g}'.encode('utf-8')).hexdigest()[:24]
        rows.append(['PLAN', plan_id, kind, priority, side, f'{price:.10f}', source,
                     revision, int(created), group,
                     *[f'{(exits.get(key) or {}).get("price", 0):.10f}' for key in ('sl', 'tp1', 'tp2', 'breakeven')]])
        if protocol >= 7:
            rows[-1].extend([int(confirmed if confirmed is not None else created), mode])

    # 新协议保留已验证的旧计划供显示，失效计算由EA完成；心跳不能续期。
    direct = ai
    if protocol >= 7:
        valid = (c.get('ai_enabled') and setup.get('sender') == c['teacher_sender_id']
                 and setup.get('mode') == 'SETUP' and setup.get('source_refs')
                 and refs_current(db, c['chat_id'], setup['source_refs']))
        direct = dict(setup, active=bool(valid))
    # 新地图淘汰更早且范围外的明确方向；本地记住淘汰时间，重启/旧AI结果不复活。
    scope = dict(chat_id=c['chat_id'], teacher_id=c['teacher_sender_id'],
                 symbol=c['symbols'][c['teacher_symbol']])
    retired = state(db, 'map_retired_directions', {}) if protocol >= 7 else {}
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
            if protocol >= 7:
                key = hashlib.sha256(f"DIRECT|{origin}|{revision}|{p['side']}|{p['price']:g}".encode('utf-8')).hexdigest()[:24]
                if map_time > confirmed and not min(levels) <= p['price'] <= max(levels):
                    if map_time > retired['plans'].get(key, 0):
                        retired['plans'][key] = map_time
                        retired_changed = True
                if key in retired['plans'] and confirmed <= retired['plans'][key]:
                    continue
            add('DIRECT', PRIORITIES['teacher'] if protocol>=8 else 8, p['side'], p['price'], origin, revision,
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
                if protocol >= 7:
                    created = db.execute('SELECT created FROM messages WHERE chat_id=? AND message_id=?',
                                         (c['chat_id'], p['message_id'])).fetchone()[0]
                add(kind, PRIORITIES['inner' if kind=='INNER' else 'outer'] if protocol>=8 else 6, side, p['price'], p['message_id'], ref['revision'], created, group)
    if map_active:
        group = 'MAP|'+'|'.join(f'{v:g}' for v in levels)
        for price in levels:
            add('MAP', PRIORITIES['map'] if protocol>=8 else 5, 'AUTO', price, context['message_id'], context['revision'], context['created'], group)
    if protocol >= 8:
        meeting=state(db,'meeting_scene',{})
        source=db.execute('SELECT * FROM messages WHERE chat_id=? AND message_id=?',
                          (c['chat_id'],meeting.get('as_of',''))).fetchone()
        valid=bool(c.get('ai_enabled') and meeting.get('action')=='UPDATE' and source and not source['historical'] and not source['deleted'] and
                   summary_source(json.loads(source['raw']),source['sender'],c) and
                   refs_current(db,c['chat_id'],meeting.get('source_refs',[])))
        if valid:
            for p in meeting.get('plans',[]):
                if p.get('basis'): continue
                add('DIRECT',PRIORITIES['summary'],p['side'],p['price'],meeting['as_of'],meeting['revision'],
                    p['origin_created'],'SUMMARY|'+p['origin_id'],p.get('exits'),p['confirmed_at'],p['mode'])
            for name,kind in [('inner_range','INNER'),('outer_range','OUTER')]:
                band=meeting.get(name)
                # 新老师同类区间覆盖旧会议区间；会议本身不抹掉新老师即时指令。
                if not band or scene_valid and scene.get(name) and scene['created']>=meeting['created']: continue
                if scene_valid and scene.get(name): rows[:]=[r for r in rows if r[2]!=kind]
                for edge,side in [('low','BUY'),('high','SELL')]:
                    add(kind,PRIORITIES['inner' if kind=='INNER' else 'outer'],side,band[edge]['price'],
                        meeting['as_of'],meeting['revision'],meeting['created'],kind+'|SUMMARY|'+str(band['low']['price'])+'|'+str(band['high']['price']))
        if map_active:
            roles={p['price']:p for p in annotated_roles(context.get('text',''))}
            for price,p in roles.items():
                if price not in levels: continue
                rows[:]=[r for r in rows if not (r[2]=='MAP' and float(r[5])==price)]
                add('ROLE',p['priority'],p['side'],price,context['message_id'],context['revision'],context['created'],'ROLE|'+str(price))
        reference_sources={}
        if map_active:
            reference_sources[context['message_id']]=(context.get('text',''),context['revision'],context['created'])
        if valid:
            reference_sources[meeting['as_of']]=(json.loads(source['raw']).get('content',''),meeting['revision'],meeting['created'])
        for mid,(text,revision,created) in reference_sources.items():
            for price in reference_only_prices(text):
                matching=[r for r in rows if r[6]==mid and float(r[5])==price]
                if not matching: continue
                rows[:]=[r for r in rows if r not in matching]
                add('WATCH',0,'AUTO',price,mid,revision,created,'WATCH|'+mid+'|'+str(price))
        # 老师当前角色独立进入ROLE通道；较新的同价角色覆盖旧反向指令/区间/地图。
        # 手动覆盖仍在后面合并；已失效的新角色仅阻止旧自动方向复活，不生成入场。
        for point in teacher_role_points(db,c,now):
            price=point['price']; created=point['created']
            rows[:]=[r for r in rows if not (float(r[5])==price and r[14]<=created
                     and (r[2] in ('MAP','ROLE') or r[4] not in (point['side'],'AUTO')))]
            newer=any(float(r[5])==price and r[14]>created and r[2] in ('DIRECT','ROLE') for r in rows)
            if point['valid'] and not newer:
                add('ROLE',point['priority'],point['side'],price,point['message_id'],point['revision'],
                    created,'ROLE|'+str(price))
        if rows:
            # 撤销比排序更先执行：不能让较低层参考绕过老师后来的明确取消。
            cancellations=db.execute('''SELECT m.raw,m.created,a.payload FROM messages m LEFT JOIN ai_messages a
                ON a.chat_id=m.chat_id AND a.message_id=m.message_id AND a.revision=m.revision AND a.status='DONE'
                WHERE m.chat_id=? AND m.sender=? AND m.deleted=0 AND m.historical=0
                AND m.created>=? AND m.created<=?''',
                (c['chat_id'],c['teacher_sender_id'],min(r[8] for r in rows),now+5)).fetchall()
            for cancellation in cancellations:
                text=json.loads(cancellation['raw']).get('content','')
                if not isinstance(text,str): continue
                item=dict(text=text,interpretation=json.loads(cancellation['payload'] or '{}'))
                for row in rows:
                    if row[2]=='WATCH' or cancellation['created']<=row[14]: continue
                    sides=('BUY','SELL') if row[4]=='AUTO' else (row[4],)
                    if any(cancels_plan(item,dict(side=side,price=float(row[5]),token=format(float(row[5]),'g'))) for side in sides):
                        row[2]='WATCH';row[3]=0;row[4]='AUTO';row[10:14]=['0.0000000000']*4;row[15]='REFERENCE'
        try:
            remember_auto(db,c,rows)
            editor=state(db,'point_editor',{})
            applied=editor.get('applied')
            if applied:
                if applied['symbol']!=c['symbols'][c['teacher_symbol']]:
                    raise ValueError('网页手动点位品种不匹配，请重新编辑')
                if applied['draft']['mode']!='auto' and not c.get('manual_points_enabled'):
                    raise ValueError('配置已禁用手动点位入口')
                rows[:]=merge_rows(rows,applied)
                if applied['draft']['mode']!='auto':
                    # 语义待确认/明确撤销仍优先；人工编辑不绕过交易门禁。
                    note+='；网页'+('混合修正' if applied['draft']['mode']=='merge' else '全手动')
            manual=manual_points(c,now) if not applied else None
            if manual:
                rows.clear()
                for p in manual['plans']:
                    add(p['kind'],p['priority'],p['side'],p['price'],'MANUAL',manual['revision'],manual['created'],
                        'MANUAL|'+p['kind']+'|'+str(p['price']),mode='REACTION' if p['kind']=='DIRECT' else 'REFERENCE')
                # 手动watch是明确不交易，覆盖同价的区间派生候选。
                watch={r[5] for r in rows if r[2]=='WATCH'}
                rows[:]=[r for r in rows if r[2]=='WATCH' or r[5] not in watch]
                active=bool(healthy)
                note='手动替换模式：按文件点位执行；自动解析不覆盖'
            if applied: rows[:]=cancel_manual_rows(db,c,rows,now)
        except (OSError,ValueError,TypeError,KeyError) as ex:
            rows.clear(); active=False; note='手动点位错误：'+str(ex).replace(',','，').replace('\n',' ')[:100]
    if protocol >= 9:
        from point_lifecycle import lifecycle_rows
        try:
            rows=lifecycle_rows(db,c,rows,now)
        except ValueError as ex:
            rows=[];active=False;note=str(ex)
    if protocol >= 7 and active and not rows:
        active = False
        note = '等待已确认点位'
    rows.sort(key=lambda row: (-row[3], -row[8], row[5], row[4]))
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\r\n')
    writer.writerow(['TGA', str(protocol), int(now), int(active), c['symbols'][c['teacher_symbol']], len(rows), note])
    writer.writerows(rows)
    writer.writerow(['END', len(rows)])
    return output.getvalue()
