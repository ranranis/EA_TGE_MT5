"""仅监听127.0.0.1的只读看板，不暴露配置、凭证或文件目录。"""
import json
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sqlite3
import threading
import time

from store import state, iso, stamp
from teacher_strategy import sender_name, message_link
from deepseek_ai import member_follow_snapshot
from teacher_scene import scene_view


def snapshot(home,c):
    now=time.time(); path=home/'status.json'
    status=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    status['online']=not status.get('stopped',False) and now-stamp(status.get('at',0))<20
    service_path=home/'service.json'
    status['service']=json.loads(service_path.read_text(encoding='utf-8')) if service_path.exists() else {}
    status['service']['online']=not status['service'].get('stopped',False) and now-stamp(status['service'].get('at',0))<5
    with closing(sqlite3.connect((home/'data'/'monitor.sqlite').as_uri()+'?mode=ro',uri=True)) as db:
        db.row_factory=sqlite3.Row
        messages=[]
        for r in db.execute('''SELECT m.*,s.status,s.payload,s.reason FROM messages m
          LEFT JOIN signals s ON s.chat_id=m.chat_id AND s.message_id=m.message_id AND s.revision=m.revision
          WHERE m.chat_id=? ORDER BY m.created DESC,m.rowid DESC LIMIT 50''',(c['chat_id'],)):
            raw=json.loads(r['raw'])
            messages.append(dict(message_id=r['message_id'],sender=sender_name(raw),sender_id=r['sender'],
                                 time=iso(r['created']),text='[已撤回]' if r['deleted'] else raw.get('content',''),
                                 type=raw.get('msg_type'),status=r['status'],reason=r['reason'],
                                 historical=bool(r['historical']),link=message_link(raw)))
        if c.get('ai_enabled') and db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='ai_messages'").fetchone():
            for message in messages:
                parsed=db.execute('''SELECT a.payload FROM ai_messages a JOIN messages m
                  ON a.chat_id=m.chat_id AND a.message_id=m.message_id AND a.revision=m.revision
                  WHERE a.chat_id=? AND a.message_id=? AND a.status='DONE' AND m.deleted=0''',
                  (c['chat_id'],message['message_id'])).fetchone()
                if parsed:
                    value=json.loads(parsed['payload'])
                    message['status']=value['kind'];message['reason']=value['reason']
        count=db.execute('SELECT COUNT(*) FROM messages WHERE chat_id=?',(c['chat_id'],)).fetchone()[0]
        return dict(at=iso(now),chat_name=c['chat_name'],status=status,messages=messages,message_count=count,
                    follow=member_follow_snapshot(db,c,now,status.get('paused',False)),
                    levels=state(db,'teacher_levels',{}),analysis=state(db,'teacher_analysis',{}),
                    scene=scene_view(db,c),ai=state(db,'deepseek_status',{}),ai_setup=state(db,'deepseek_setup',{}),
                    ai_recent=state(db,'deepseek_recent',[]),ai_review=state(db,'deepseek_review',{}),
                    events=state(db,'analysis_events',[]),last_sync=state(db,'last_sync_at',0),
                    poll_seconds=c['poll_seconds'],teacher_sender_id=c['teacher_sender_id'],
                    alert= dict(db.execute('SELECT at,code,detail FROM alerts ORDER BY id DESC LIMIT 1').fetchone() or {}))


def serve(home,c):
    html=Path(__file__).with_name('dashboard.html').read_bytes()
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args): pass
        def do_GET(self):
            # Host校验拒绝DNS rebinding；同源读，无CORS，无写接口。
            if self.headers.get('Host')!=f'127.0.0.1:{self.server.server_port}':
                self.send_error(403); return
            if self.path=='/': body=html; kind='text/html; charset=utf-8'
            elif self.path=='/api/snapshot':
                try: body=json.dumps(snapshot(home,c),ensure_ascii=False,allow_nan=False).encode('utf-8')
                except (OSError,ValueError,sqlite3.Error): self.send_error(503,'Snapshot unavailable'); return
                kind='application/json; charset=utf-8'
            else: self.send_error(404); return
            self.send_response(200); self.send_header('Content-Type',kind)
            self.send_header('Content-Length',str(len(body))); self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff'); self.send_header('Referrer-Policy','no-referrer')
            self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers(); self.wfile.write(body)
    server=ThreadingHTTPServer(('127.0.0.1',c['dashboard_port']),Handler)
    thread=threading.Thread(target=server.serve_forever,name='local-dashboard',daemon=True); thread.start()
    return server
