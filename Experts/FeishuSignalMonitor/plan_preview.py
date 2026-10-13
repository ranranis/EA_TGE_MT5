"""本地人工预览：只在用户应用时更新场景，不直接写EA文件或发送订单。"""
import hashlib
import json
import sqlite3
import time
import uuid
from contextlib import closing

from store import state, set_state, stamp
from deepseek_ai import AIError, DeepSeek, process_ai_batch, refs_current, lane_readiness, SYSTEM
from teacher_scene import SCENE_PROMPT, publish_scene


def open_db(home, readonly=False):
    db=sqlite3.connect((home/'data/monitor.sqlite').as_uri()+('?mode=ro' if readonly else '?mode=rw'),uri=True,timeout=10)
    db.row_factory=sqlite3.Row
    return db


def fingerprint(db,c):
    # 仅比较会改变本次老师计划的输入；普通聊天与同步检查时间不使预览失效。
    rows=[tuple(r) for r in db.execute(
        'SELECT message_id,revision,deleted,historical,created FROM messages WHERE chat_id=? AND sender=? ORDER BY created,rowid',
        (c['chat_id'],c['teacher_sender_id']))]
    levels=state(db,'teacher_levels',{})
    values=[rows,{k:levels.get(k) for k in ('message_id','revision','active','levels')},
            state(db,'teacher_scene',{}),state(db,'deepseek_setup',{}),c['chat_id'],c['teacher_sender_id'],
            c.get('ai_model'),SYSTEM,SCENE_PROMPT]
    return hashlib.sha256(json.dumps(values,ensure_ascii=False,sort_keys=True).encode('utf-8')).hexdigest()


def public_preview(value):
    return {k:v for k,v in value.items() if k in ('id','status','created','completed','applied_at','error','scene')}


def begin_preview(home,c,now=None):
    now=now or time.time()
    if not c.get('ai_enabled'): raise AIError('请先启用DeepSeek')
    with closing(open_db(home)) as db, db:
        db.execute('BEGIN IMMEDIATE')
        previous=state(db,'plan_preview',{})
        if previous.get('status')=='RUNNING' and now-previous.get('created',0)<90:
            raise AIError('正在重新分析，请等待当前任务完成')
        draft=dict(id=uuid.uuid4().hex,status='RUNNING',created=now)
        set_state(db,'plan_preview',draft)
        return public_preview(draft)


def generate_preview(home,c,preview_id,client=None):
    try:
        with closing(open_db(home,True)) as db:
            db.execute('BEGIN')  # 本次读取使用一致快照；API等待期间不持有写锁。
            guard=fingerprint(db,c)
            scene=process_ai_batch(db,c,client or DeepSeek(home,c),time.time(),preview=True)
        with closing(open_db(home)) as db, db:
            db.execute('BEGIN IMMEDIATE')
            draft=state(db,'plan_preview',{})
            if draft.get('id')!=preview_id: return
            if fingerprint(db,c)!=guard: raise AIError('分析期间老师消息或实时计划已变化，请重新分析')
            draft.update(status='READY',completed=time.time(),scene=scene,guard=guard)
            set_state(db,'plan_preview',draft)
    except Exception as ex:
        # 不回传模型正文、凭证或请求头。
        error=str(ex) if isinstance(ex,AIError) else '重新分析失败：'+type(ex).__name__
        with closing(open_db(home)) as db, db:
            draft=state(db,'plan_preview',{})
            if draft.get('id')==preview_id:
                draft.update(status='FAILED',error=error,completed=time.time())
                set_state(db,'plan_preview',draft)


def apply_preview(home,c,preview_id,now=None):
    now=now or time.time()
    if (home/'control/pause').exists(): raise AIError('监控已暂停，请先恢复后重新核对')
    status=json.loads((home/'status.json').read_text(encoding='utf-8'))
    if status.get('stopped') or now-stamp(status.get('at',0))>20:
        raise AIError('监控不在线，不能应用计划')
    with closing(open_db(home)) as db, db:
        db.execute('BEGIN IMMEDIATE')
        draft=state(db,'plan_preview',{})
        if draft.get('id')!=preview_id: raise AIError('预览已被替换，请刷新页面')
        if draft.get('status')=='APPLIED': return public_preview(draft)
        if draft.get('status')!='READY': raise AIError('没有可应用的有效预览')
        # 此期限只限制人工审核草稿，不改变T哥条件计划的持续有效规则。
        if now-draft.get('completed',0)>600: raise AIError('预览已超过10分钟，请重新分析后核对')
        if not state(db,'last_sync_ok',False) or any(now-state(db,k,0)>c['sync_max_age_seconds'] for k in ('last_sync_at','checkpoint')):
            raise AIError('飞书同步未跟上，不能应用旧预览')
        market=state(db,'teacher_analysis',{})
        age=now-market.get('quote',{}).get('at',0)
        if not market.get('market_ok') or not -2<=age<=c['quote_max_age_seconds']:
            raise AIError('行情无效，待报价恢复再应用')
        if not lane_readiness(db,c,now)['teacher_ready']:
            raise AIError('有老师新消息尚未处理，请等待并重新分析')
        if fingerprint(db,c)!=draft.get('guard'):
            raise AIError('老师消息、点位或实时计划已经变化，请重新分析')
        scene=draft['scene']
        if scene.get('action')!='UPDATE' or any(p['mode']=='MARKET' for p in scene['plans']):
            raise AIError('预览不能重放历史市价单')
        if not refs_current(db,c['chat_id'],scene['source_refs']):
            raise AIError('原消息已编辑或撤回，请重新分析')
        publish_scene(db,c,scene)
        if state(db,'teacher_scene',{})!=scene: raise AIError('已有更新场景，不能覆盖')
        draft.update(status='APPLIED',applied_at=now)
        set_state(db,'plan_preview',draft)
        return public_preview(draft)
