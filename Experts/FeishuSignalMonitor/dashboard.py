"""仅监听127.0.0.1；同源令牌保护人工预览/应用，不暴露凭证或文件目录。"""
import csv
import json
import math
import os
import secrets
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sqlite3
import threading
import time
import webbrowser

from store import state, iso, stamp
from teacher_strategy import sender_name, message_link
from deepseek_ai import member_follow_snapshot, member_follow_snapshots
from teacher_scene import scene_view
from plan_preview import begin_preview, generate_preview, apply_preview, public_preview
from deepseek_ai import AIError
from point_editor import editor_view, editor_action, parse_text


def published_reference(c,now,status):
    """展示EA实际读取的原子导出文件，不把旧AI解释当作仍在执行的计划。"""
    folder=(Path(c['common_files']) if c.get('common_files') else
            Path(os.environ['APPDATA'])/'MetaQuotes/Terminal/Common/Files')/'FeishuMT5SignalMonitor'
    try:
        feed=folder/'tge_execution_v9.csv'
        if not feed.exists(): feed=folder/'tge_execution_v8.csv'
        if not feed.exists(): feed=folder/'tge_execution_v7.csv'
        with feed.open(encoding='utf-8-sig',newline='') as f:
            rows=list(csv.reader(f))
        head=rows[0];count=int(head[5]);generated=int(head[2])
        version=int(head[1]); kinds=('DIRECT','INNER','OUTER','MAP','ROLE','WATCH') if version>=8 else ('DIRECT','INNER','OUTER','MAP')
        if (len(head)!=7 or head[0]!='TGA' or version not in (7,8,9) or head[3] not in ('0','1') or
            head[4]!=c['symbols'][c['teacher_symbol']] or not 0<=count<=64 or
            len(rows)!=count+2 or rows[-1]!=['END',str(count)]):
            raise ValueError()
        plans=[]
        for row in rows[1:-1]:
            if len(row)!=(20 if version==9 else 16) or row[0]!='PLAN': raise ValueError()
            kind=row[2];priority=int(row[3]);price=float(row[5])
            priorities={'DIRECT':(100,95,90),'INNER':(70,),'OUTER':(75,),'ROLE':(60,55),'MAP':(40,),'WATCH':(0,)} if version>=8 else {'DIRECT':(8,),'INNER':(6,),'OUTER':(6,),'MAP':(5,)}
            if (kind not in kinds or priority not in priorities.get(kind,()) or
                row[4] not in (('AUTO',) if kind in ('MAP','WATCH') else ('BUY','SELL')) or
                not math.isfinite(price) or price<=0): raise ValueError()
            plans.append(dict(id=row[1],kind=kind,priority=priority,side=row[4],price=price,
                              source_id=row[6],created=int(row[8]),confirmed=int(row[14]),
                              expires=int(row[16]) if version==9 else 0, evidence_count=int(row[17]) if version==9 else 1,
                              life_state=row[18] if version==9 else 'READY',life_reason=row[19] if version==9 else ''))
        fresh=generated>0 and -5<=now-generated<=c['sync_max_age_seconds']
        active=bool(fresh and head[3]=='1' and status.get('online') and
                    status.get('sync_healthy') and not status.get('paused'))
        return dict(available=True,active=active,fresh=fresh,generated=generated,symbol=head[4],
                    plans=sorted(plans,key=lambda p:-p['priority']),
                    reason=head[6] if active else ('导出已过期，仅供查看' if not fresh else '同步暂停或未就绪，仅供查看'))
    except (OSError,ValueError,IndexError):
        return dict(available=False,active=False,fresh=False,plans=[],reason='执行文件尚不可读或不完整，等待重新导出')


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
        return dict(at=iso(now),chat_name=c['chat_name'],teacher_only=c.get('teacher_only',False),status=status,messages=messages,message_count=count,
                    follow=member_follow_snapshot(db,c,now,status.get('paused',False)),
                    follows=member_follow_snapshots(db,c,now,status.get('paused',False)),
                    execution_reference=published_reference(c,now,status),
                    point_editor=editor_view(db,c),
                    point_selection=state(db,'point_selection',{}),point_lifecycle=state(db,'point_lifecycle',{}),levels=state(db,'teacher_levels',{}),analysis=state(db,'teacher_analysis',{}),
                    preview=public_preview(state(db,'plan_preview',{})),scene=scene_view(db,c),ai=state(db,'deepseek_status',{}),ai_setup=state(db,'deepseek_setup',{}),
                    ai_recent=state(db,'deepseek_recent',[]),ai_review=state(db,'deepseek_review',{}),
                    events=state(db,'analysis_events',[]),last_sync=state(db,'last_sync_at',0),
                    poll_seconds=c['poll_seconds'],teacher_sender_id=c['teacher_sender_id'],
                    alert= dict(db.execute('SELECT at,code,detail FROM alerts ORDER BY id DESC LIMIT 1').fetchone() or {}))


def serve(home,c):
    action_token=secrets.token_urlsafe(32)
    html=Path(__file__).with_name('dashboard.html').read_text(encoding='utf-8').replace('__LOCAL_ACTION_TOKEN__',action_token).encode('utf-8')
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args): pass
        def do_POST(self):
            origin=f'http://127.0.0.1:{self.server.server_port}'
            if (self.headers.get('Host')!=origin.removeprefix('http://') or
                self.headers.get('Origin')!=origin or
                not secrets.compare_digest(self.headers.get('X-Local-Token',''),action_token)):
                self.send_error(403); return
            if self.path not in ('/api/plan-preview','/api/plan-apply','/api/points','/api/points-parse'):
                self.send_error(404); return
            try:
                size=int(self.headers.get('Content-Length','0'))
                if not 0<size<=(65536 if self.path.startswith('/api/points') else 1024) or self.headers.get('Content-Type')!='application/json':
                    self.send_error(400); return
                body=json.loads(self.rfile.read(size))
                if self.path=='/api/points':
                    result=editor_action(home,c,body)
                elif self.path=='/api/points-parse':
                    if not parse_lock.acquire(blocking=False): raise AIError('正在整理粘贴消息，请稍候')
                    try: result=parse_text(home,c,body)
                    finally: parse_lock.release()
                elif self.path=='/api/plan-preview':
                    if body!={}: raise ValueError()
                    result=begin_preview(home,c)
                    threading.Thread(target=generate_preview,args=(home,c,result['id']),daemon=True,name='plan-preview').start()
                else:
                    if not isinstance(body,dict) or set(body)!={'id','confirmed'} or body['confirmed'] is not True or not isinstance(body['id'],str):
                        raise ValueError()
                    result=apply_preview(home,c,body['id'])
                code=200
            except AIError as ex: code=409; result={'error':str(ex)}
            except (ValueError,TypeError) as ex: code=400; result={'error':str(ex) if self.path=='/api/points' else '请求格式无效'}
            except (OSError,sqlite3.Error): code=503; result={'error':'本地状态不可用，请稍后重试'}
            data=json.dumps(result,ensure_ascii=False,allow_nan=False).encode('utf-8')
            self.send_response(code); self.send_header('Content-Type','application/json; charset=utf-8')
            self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store')
            self.end_headers();self.wfile.write(data)

        def do_GET(self):
            # Host校验拒绝DNS rebinding；无CORS。
            if self.headers.get('Host')!=f'127.0.0.1:{self.server.server_port}':
                self.send_error(403); return
            if self.path=='/': body=html; kind='text/html; charset=utf-8'
            elif self.path=='/point-editor.js':
                body=Path(__file__).with_name('point-editor.js').read_bytes(); kind='text/javascript; charset=utf-8'
            elif self.path=='/api/snapshot':
                try: body=json.dumps(snapshot(home,c),ensure_ascii=False,allow_nan=False).encode('utf-8')
                except (OSError,ValueError,sqlite3.Error): self.send_error(503,'Snapshot unavailable'); return
                kind='application/json; charset=utf-8'
            else: self.send_error(404); return
            self.send_response(200); self.send_header('Content-Type',kind)
            self.send_header('Content-Length',str(len(body))); self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff'); self.send_header('Referrer-Policy','no-referrer')
            self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers(); self.wfile.write(body)
    parse_lock=threading.Lock()
    server=ThreadingHTTPServer(('127.0.0.1',c['dashboard_port']),Handler)
    thread=threading.Thread(target=server.serve_forever,name='local-dashboard',daemon=True); thread.start()
    def watch_editor_request():
        folder=(Path(c['common_files']) if c.get('common_files') else
                Path(os.environ['APPDATA'])/'MetaQuotes/Terminal/Common/Files')/'FeishuMT5SignalMonitor'
        request=folder/'open_point_editor.txt'
        while thread.is_alive():
            try:
                if request.exists():
                    value=request.read_text(encoding='utf-8-sig').strip() if request.stat().st_size<64 else ''
                    request.unlink()
                    if value.isdigit() and -5<=time.time()-int(value)<=30:
                        webbrowser.open(f'http://127.0.0.1:{server.server_port}/#point-editor')
            except (OSError,ValueError): pass
            time.sleep(1)
    threading.Thread(target=watch_editor_request,name='point-editor-shortcut',daemon=True).start()
    return server
