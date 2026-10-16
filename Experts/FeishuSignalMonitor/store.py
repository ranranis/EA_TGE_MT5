"""SQLite 是同步检查点、消息版本和模拟成交的唯一持久化来源。"""
import hashlib
import json
import sqlite3
import time
from datetime import datetime, timezone, timedelta

TZ = timezone(timedelta(hours=8))

def stamp(value):
    if isinstance(value,(int,float)) or str(value).isdigit():
        n=float(value); return n/1000 if n>1e11 else n
    return datetime.fromisoformat(str(value).replace('Z','+00:00')).replace(tzinfo=TZ).timestamp() if datetime.fromisoformat(str(value).replace('Z','+00:00')).tzinfo is None else datetime.fromisoformat(str(value).replace('Z','+00:00')).timestamp()

def iso(t):
    return datetime.fromtimestamp(t,TZ).isoformat(timespec='seconds')

def dumps(value):
    return json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False)

def connect(path):
    db=sqlite3.connect(path,timeout=20)
    db.row_factory=sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('PRAGMA foreign_keys=ON')
    db.executescript('''
    CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS messages(
      chat_id TEXT, message_id TEXT, sender TEXT NOT NULL, created REAL NOT NULL,
      modified TEXT, revision TEXT NOT NULL, deleted INTEGER NOT NULL, historical INTEGER NOT NULL,
      thread_id TEXT, checked REAL NOT NULL DEFAULT 0, raw TEXT NOT NULL,
      PRIMARY KEY(chat_id,message_id));
    CREATE TABLE IF NOT EXISTS ai_messages(
      chat_id TEXT NOT NULL,message_id TEXT NOT NULL,revision TEXT NOT NULL,created REAL NOT NULL,
      status TEXT NOT NULL,payload TEXT NOT NULL,processed REAL NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,
      retry_at REAL NOT NULL DEFAULT 0,error TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(chat_id,message_id,revision));
    CREATE TABLE IF NOT EXISTS signals(
      id INTEGER PRIMARY KEY,chat_id TEXT NOT NULL,message_id TEXT NOT NULL,revision TEXT NOT NULL,
      sender TEXT NOT NULL,created REAL NOT NULL,payload TEXT NOT NULL,status TEXT NOT NULL,reason TEXT,
      UNIQUE(chat_id,message_id,revision));
    CREATE TABLE IF NOT EXISTS threads(thread_id TEXT PRIMARY KEY,checked REAL NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS orders(
      id INTEGER PRIMARY KEY,chat_id TEXT NOT NULL,source_id TEXT NOT NULL,sender TEXT NOT NULL,
      symbol TEXT NOT NULL,side TEXT NOT NULL,kind TEXT NOT NULL,entry_low REAL,entry_high REAL,
      sl REAL NOT NULL,tps TEXT NOT NULL,status TEXT NOT NULL,created REAL NOT NULL,expires REAL NOT NULL,
      opened REAL,entry_price REAL,volume REAL NOT NULL DEFAULT 0,remaining REAL NOT NULL DEFAULT 0,
      next_tp INTEGER NOT NULL DEFAULT 0,source_invalid INTEGER NOT NULL DEFAULT 0,
      close_requested INTEGER NOT NULL DEFAULT 0,reason TEXT NOT NULL DEFAULT '',
      UNIQUE(chat_id,source_id));
    CREATE TABLE IF NOT EXISTS fills(
      id INTEGER PRIMARY KEY,order_id INTEGER NOT NULL REFERENCES orders(id),at REAL NOT NULL,
      kind TEXT NOT NULL,volume REAL NOT NULL,price REAL NOT NULL,spread REAL NOT NULL,
      slippage REAL NOT NULL,pnl REAL NOT NULL,commission REAL NOT NULL,reason TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS equity(at REAL PRIMARY KEY,balance REAL NOT NULL,equity REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS alerts(id INTEGER PRIMARY KEY,at REAL NOT NULL,code TEXT NOT NULL,detail TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS message_versions(
      id INTEGER PRIMARY KEY, chat_id TEXT NOT NULL, message_id TEXT NOT NULL,
      revision TEXT NOT NULL, received_at REAL NOT NULL, source_created REAL NOT NULL,
      historical INTEGER NOT NULL, baseline INTEGER NOT NULL, raw TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS message_version_lookup ON message_versions(chat_id,message_id,id);
    CREATE TABLE IF NOT EXISTS point_state_versions(
      id INTEGER PRIMARY KEY, key TEXT NOT NULL, recorded_at REAL NOT NULL, value TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS point_state_lookup ON point_state_versions(key,id);
    CREATE TABLE IF NOT EXISTS execution_versions(
      id INTEGER PRIMARY KEY, scope TEXT NOT NULL, recorded_at REAL NOT NULL,
      generated_at REAL NOT NULL, signature TEXT NOT NULL, snapshot TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS execution_version_lookup ON execution_versions(scope,id);
    CREATE INDEX IF NOT EXISTS message_check ON messages(checked);
    CREATE INDEX IF NOT EXISTS signal_status ON signals(status);
    ''')
    return db

def state(db,key,default=None):
    row=db.execute('SELECT value FROM state WHERE key=?',(key,)).fetchone()
    return json.loads(row[0]) if row else default

def set_state(db,key,value):
    encoded=dumps(value)
    # 与当前状态同事务保存；历史表不反向参与交易，不用原消息时间伪造首次获知时间。
    if key in ('teacher_levels','teacher_scene','deepseek_setup','deepseek_review','point_editor'):
        latest=db.execute('SELECT value FROM point_state_versions WHERE key=? ORDER BY id DESC LIMIT 1',(key,)).fetchone()
        if not latest or latest[0]!=encoded:
            db.execute('INSERT INTO point_state_versions(key,recorded_at,value) VALUES(?,?,?)',(key,time.time(),encoded))
    db.execute('INSERT INTO state VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',(key,encoded))

def archive_execution(db,c,generated,snapshot):
    import csv,io
    rows=list(csv.reader(io.StringIO(snapshot)))
    if len(rows)<2 or rows[0][:2]!=['TGA','9'] or rows[-1][0]!='END':
        raise ValueError('只能归档完整TGA9执行快照')
    # 仅剔除心跳和展示说明；启停、点位行、手动来源、期限和撤销状态参与版本比较。
    semantic=[rows[0][0:2]+rows[0][3:6],*rows[1:]]
    signature=hashlib.sha256(dumps(semantic).encode('utf-8')).hexdigest()
    scope=dumps([c['chat_id'],c['symbols'][c['teacher_symbol']]])
    with db:
        previous=db.execute('SELECT signature FROM execution_versions WHERE scope=? ORDER BY id DESC LIMIT 1',(scope,)).fetchone()
        if not previous or previous[0]!=signature:
            db.execute('INSERT INTO execution_versions(scope,recorded_at,generated_at,signature,snapshot) VALUES(?,?,?,?,?)',
                       (scope,time.time(),generated,signature,snapshot))


def alert(db,code,detail,now=None):
    db.execute('INSERT INTO alerts(at,code,detail) VALUES(?,?,?)',(now or time.time(),code,detail))

def ingest(db,chat_id,messages,cutoff=None,historical=False,checked_ids=(),thread_ids=()):
    from signals import parse_message
    now=time.time(); live_since=state(db,'live_since',now); count=0
    # 整批成功后才推进检查点；中断时全部回滚，下次按消息ID/版本重试。
    with db:
        db.execute('BEGIN IMMEDIATE')
        for message in messages:
            if message.get('chat_id',chat_id)!=chat_id: raise ValueError('消息来自其他群，拒绝混入')
            mid=message['message_id']; sender=message.get('sender',{}).get('id','')
            created=stamp(message['create_time']); modified=message.get('update_time','')
            signature={k:message.get(k) for k in ('content','deleted','msg_type','reply_to','thread_id','update_time')}
            revision=hashlib.sha256(dumps(signature).encode('utf-8')).hexdigest()
            old=db.execute('SELECT * FROM messages WHERE chat_id=? AND message_id=?',(chat_id,mid)).fetchone()
            is_history=bool(historical or created<live_since or (old and old['historical']))
            # 升级前没有版本历史的旧行只能标为“升级基线”，不能宣称当年已归档。
            archived=db.execute('SELECT 1 FROM message_versions WHERE chat_id=? AND message_id=? LIMIT 1',(chat_id,mid)).fetchone()
            if old and not archived:
                db.execute('INSERT INTO message_versions(chat_id,message_id,revision,received_at,source_created,historical,baseline,raw) VALUES(?,?,?,?,?,?,1,?)',
                           (chat_id,mid,old['revision'],now,old['created'],old['historical'],old['raw']))
            if not old or old['revision']!=revision:
                db.execute('INSERT INTO message_versions(chat_id,message_id,revision,received_at,source_created,historical,baseline,raw) VALUES(?,?,?,?,?,?,0,?)',
                           (chat_id,mid,revision,now,created,int(is_history),dumps(message)))
            thread=message.get('thread_id')
            if thread: db.execute('INSERT OR IGNORE INTO threads(thread_id) VALUES(?)',(thread,))
            if old and old['revision']==revision:
                db.execute('UPDATE messages SET checked=? WHERE chat_id=? AND message_id=?',(now,chat_id,mid))
                continue
            count+=1
            deleted=bool(message.get('deleted'))
            try: signal=parse_message(message)
            except (ValueError,TypeError): signal={'kind':'UNKNOWN','reason':'字段校验失败，待人工识别'}
            kind=signal['kind']
            status='ready' if kind in ('NEW_ORDER','MODIFY_ORDER','CANCEL_ORDER','CLOSE_ORDER') else kind.lower()
            if is_history: status='historical'
            if message.get('msg_type')=='image': status='pending_image'
            if old:
                db.execute("UPDATE signals SET status='superseded' WHERE chat_id=? AND message_id=? AND status='ready'",(chat_id,mid))
                db.execute("UPDATE orders SET source_invalid=1,status=CASE WHEN status='PENDING' THEN 'CANCELLED' ELSE status END,reason='来源消息编辑或撤回：保留原保护，待人工核对' WHERE chat_id=? AND source_id=? AND status IN ('PENDING','OPEN')",(chat_id,mid))
                # 编辑不是新的交易意图，不再次触发开/平/改单。
                status='edited_review'
                alert(db,'MESSAGE_CHANGED','消息编辑/撤回：'+mid,now)
            if deleted: status='withdrawn'
            db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(chat_id,message_id) DO UPDATE SET sender=excluded.sender,modified=excluded.modified,revision=excluded.revision,deleted=excluded.deleted,historical=excluded.historical,thread_id=excluded.thread_id,checked=excluded.checked,raw=excluded.raw',
                (chat_id,mid,sender,created,modified,revision,int(deleted),int(is_history),thread,now,dumps(message)))
            db.execute('INSERT OR IGNORE INTO signals(chat_id,message_id,revision,sender,created,payload,status,reason) VALUES(?,?,?,?,?,?,?,?)',
                (chat_id,mid,revision,sender,created,dumps(signal),status,signal.get('reason','')))
        for mid in checked_ids:
            db.execute('UPDATE messages SET checked=? WHERE chat_id=? AND message_id=?',(now,chat_id,mid))
        for tid in thread_ids: db.execute('UPDATE threads SET checked=? WHERE thread_id=?',(now,tid))
        if cutoff is not None: set_state(db,'checkpoint',cutoff)
    return count
