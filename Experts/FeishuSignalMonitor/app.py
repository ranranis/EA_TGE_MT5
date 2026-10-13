"""Windows 独立监控入口：python app.py --help。Python不调用真实交易接口；AI参考由独立EA读取。"""
import argparse
import csv
import io
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
from datetime import datetime
from xml.sax.saxutils import escape

from store import connect, state, set_state, ingest, alert, iso, stamp, dumps, TZ
from lark_reader import LarkReader, LarkError, AuthRequired
from mt5_reader import MT5Reader, QuoteError
from paper import PaperEngine
from teacher_strategy import TeacherAnalysis, source_levels
from dashboard import serve
from deepseek_ai import member_follow_snapshots, ai_worker, ai_snapshot, member_follow_snapshot

ROOT=Path(__file__).resolve().parent
DEFAULT_HOME=Path(os.environ.get('LOCALAPPDATA',str(Path.home())))/'FeishuMT5SignalMonitor'
TASK_NAME='FeishuMT5SignalMonitor'

def atomic_text(path,text):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+'.tmp')
    with temp.open('w',encoding='utf-8',newline='') as f:
        f.write(text); f.flush(); os.fsync(f.fileno())
    for attempt in range(5):
        try: os.replace(temp,path); return
        except PermissionError:
            if attempt==4: raise
            time.sleep(0.05*(attempt+1))

def config_load(home):
    home.mkdir(parents=True,exist_ok=True)
    path=home/'config'/'config.json'
    defaults=json.loads((ROOT/'config.example.json').read_text(encoding='utf-8'))
    if not path.exists(): atomic_text(path,json.dumps(defaults,ensure_ascii=False,indent=2))
    loaded=json.loads(path.read_text(encoding='utf-8'))
    if set(loaded)-set(defaults): raise ValueError('配置有未知字段：'+','.join(set(loaded)-set(defaults)))
    c=defaults|loaded
    if c['mode'] not in ('monitor','paper') or type(c['ai_enabled']) is not bool: raise ValueError('只允许 monitor / paper 模式，AI开关须为布尔值')
    if c['ai_model'] not in ('deepseek-flash','deepseek-v4-pro'): raise ValueError('DeepSeek模型不支持')
    for key in ('poll_seconds','quote_seconds','overlap_seconds','window_seconds','max_pages','reconcile_batch','thread_batch','signal_ttl_seconds','pending_ttl_seconds','quote_max_age_seconds','sync_max_age_seconds','initial_equity','max_spread_points'):
        if type(c[key]) not in (int,float) or c[key]<=0: raise ValueError('配置应为正数：'+key)
    if c['poll_seconds']<5 or c['quote_seconds']<0.5: raise ValueError('轮询周期过短')
    for key in ('max_pages','reconcile_batch','thread_batch'):
        if type(c[key]) is not int: raise ValueError('配置应为整数：'+key)
    if not 0<c['risk_fraction']<=0.0025 or not 0<c['daily_loss_fraction']<=0.01 or not 0<c['max_total_risk_fraction']<=0.01:
        raise ValueError('首版风险可下调，上限为单笔0.25%、当日1%、总敞口1%')
    if c['slippage_points']<0 or c['commission_per_lot_side']<0: raise ValueError('滑点/费用不可为负')
    if not isinstance(c['trusted_senders'],list) or any(not isinstance(x,str) or not x.startswith('ou_') for x in c['trusted_senders']): raise ValueError('可信发送者必须为 open_id 列表')
    if not isinstance(c['symbols'],dict) or any(not isinstance(k,str) or not isinstance(v,str) for k,v in c['symbols'].items()): raise ValueError('品种映射错误')
    if type(c['dashboard_port']) is not int or not 1024<=c['dashboard_port']<=65535: raise ValueError('看板端口必须在1024至65535之间')
    if type(c['levels_ttl_seconds']) not in (int,float) or c['levels_ttl_seconds']<0 or c['levels_ttl_seconds']>86400: raise ValueError('点位有效期须为0或不超过一天；0表示沿用到明确作废')
    if not isinstance(c['teacher_sender_id'],str) or c['teacher_sender_id'] and not c['teacher_sender_id'].startswith('ou_'): raise ValueError('老师身份须为open_id')
    if not isinstance(c['point_source_senders'],list) or any(not isinstance(x,str) or not x.startswith('ou_') for x in c['point_source_senders']): raise ValueError('点位来源必须为open_id列表')
    if type(c['allow_group_point_updates']) is not bool: raise ValueError('群友点位更新开关必须为布尔值')
    if not isinstance(c['follow_sender_id'],str) or c['follow_sender_id'] and not c['follow_sender_id'].startswith('ou_'): raise ValueError('跟随成员身份须为open_id')
    if c['follow_sender_id'] and c['follow_sender_id'] in [c['teacher_sender_id']]+c['point_source_senders']: raise ValueError('跟随成员须与老师点位来源分开配置')
    if not isinstance(c['follow_members'],list) or len(c['follow_members'])>8:
        raise ValueError('学生账号配置须为最多8项的列表')
    ids=set()
    for m in c['follow_members']:
        if not isinstance(m,dict) or set(m)!={'sender_id','name','enabled','ttl_seconds','max_adverse_price'}:
            raise ValueError('学生配置字段无效')
        mid=m['sender_id']
        if not isinstance(mid,str) or not mid.startswith('ou_') or mid==c['teacher_sender_id'] or mid in ids:
            raise ValueError('学生账号须为独立唯一open_id')
        if not isinstance(m['name'],str) or not m['name'] or len(m['name'])>40 or type(m['enabled']) is not bool:
            raise ValueError('学生名称/开关无效')
        if type(m['ttl_seconds']) is not int or not 1<=m['ttl_seconds']<=3600 or type(m['max_adverse_price']) not in (int,float) or not 0<m['max_adverse_price']<=100:
            raise ValueError('学生有效期/不利价差无效')
        ids.add(mid)
    if c['teacher_symbol'] not in c['symbols']: raise ValueError('老师点位品种缺少映射')
    if type(c['mt5_time_offset_seconds']) is not int or abs(c['mt5_time_offset_seconds'])>14*3600 or c['mt5_time_offset_seconds']%3600: raise ValueError('行情固定时间偏移须为整小时且不超过14小时')
    return c

def setup(home,log_name='monitor.log'):
    for folder in ('data','logs','reports','control'): (home/folder).mkdir(parents=True,exist_ok=True)
    handler=RotatingFileHandler(home/'logs'/log_name,maxBytes=2_000_000,backupCount=5,encoding='utf-8')
    handlers=[handler]
    if sys.stdout is not None: handlers.append(logging.StreamHandler(sys.stdout))
    logging.basicConfig(level=logging.INFO,format='%(asctime)s %(levelname)s %(message)s',handlers=handlers,force=True)

class InstanceLock:
    def __init__(self,home,name='instance.lock'): self.path=home/'data'/name; self.file=None
    def __enter__(self):
        import msvcrt
        self.file=self.path.open('a+b'); self.file.seek(0); self.file.write(b'0'); self.file.flush(); self.file.seek(0)
        try: msvcrt.locking(self.file.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:
            self.file.close(); raise RuntimeError('已有监控/导入实例运行，拒绝重复启动')
        return self
    def __exit__(self,*args):
        import msvcrt
        self.file.seek(0); msvcrt.locking(self.file.fileno(),msvcrt.LK_UNLCK,1); self.file.close()

def warn(home,code,detail):
    logging.error('%s：%s',code,detail)
    atomic_text(home/'logs'/'alert.json',dumps({'at':iso(time.time()),'code':code,'detail':detail}))

def verify_chat(reader,c,home):
    found=reader.search(c['chat_name'])
    if c['chat_id'] and found['chat_id']!=c['chat_id']: raise LarkError('群名称搜索结果与配置chat_id不一致，请核对')
    c['chat_id']=found['chat_id']
    return found

def initialize_db(db,now):
    with db:
        if state(db,'live_since') is None:
            set_state(db,'live_since',now)
            set_state(db,'checkpoint',now-300)
        if state(db,'last_sync_ok') is None: set_state(db,'last_sync_ok',False)

def sync_worker(home,c,stop):
    db=connect(home/'data'/'monitor.sqlite'); reader=LarkReader(c,stop); delay=c['poll_seconds']
    try:
        while not stop.is_set():
            if (home/'control'/'pause').exists(): stop.wait(1); continue
            try:
                count,end=reader.sync_once(db,c['chat_id'],time.time())
                with db:
                    set_state(db,'last_sync_at',time.time()); set_state(db,'last_sync_ok',True)
                logging.info('飞书同步完成：新增/变更%d条；检查点%s',count,iso(end))
                delay=c['poll_seconds'] if time.time()-end<5 else 1
            except (LarkError,ValueError,KeyError) as ex:
                with db:
                    set_state(db,'last_sync_ok',False); alert(db,'AUTH_REQUIRED' if isinstance(ex,AuthRequired) else 'SYNC_ERROR',str(ex))
                warn(home,'AUTH_REQUIRED' if isinstance(ex,AuthRequired) else 'SYNC_ERROR',str(ex))
                delay=min(300,max(c['poll_seconds'],delay*2))
            except Exception as ex:
                with db: set_state(db,'last_sync_ok',False)
                warn(home,'SYNC_ERROR',type(ex).__name__+'：同步未完成，停止新模拟成交')
                delay=min(300,max(c['poll_seconds'],delay*2))
            stop.wait(delay)
    finally: db.close()

def export_observer(db,c,paused):
    folder=Path(c['common_files']) if c['common_files'] else Path(os.environ['APPDATA'])/'MetaQuotes/Terminal/Common/Files'
    rows=db.execute('SELECT * FROM orders ORDER BY id DESC LIMIT 100').fetchall()
    s=io.StringIO(newline=''); w=csv.writer(s,lineterminator='\r\n')
    w.writerow(['META','1',int(time.time()),len(rows),int(paused),c['currency']])
    for o in rows:
        w.writerow(['ORDER',o['id'],o['symbol'],o['side'],o['status'],o['entry_price'] or o['entry_high'] or 0,o['sl'],'|'.join(str(x) for x in json.loads(o['tps'])),o['remaining'],int(o['opened'] or o['created']),int(o['source_invalid']),o['source_id']])
    w.writerow(['END',len(rows)])
    atomic_text(folder/'FeishuMT5SignalMonitor'/'signals.csv',s.getvalue())

def export_teacher_levels(db,c,paused,now):
    """旧版继续使用短时授权快照；独立T哥版使用不按年龄到期的点位地图。"""
    context=state(db,'teacher_levels',{})
    row=db.execute('SELECT * FROM messages WHERE chat_id=? AND message_id=?',
                   (c['chat_id'],context.get('message_id',''))).fetchone()
    levels=source_levels(json.loads(row['raw']),row['sender'],c) if row else None
    source_ok=bool(context.get('active') and row and not row['deleted'] and not row['historical']
                   and row['revision']==context.get('revision')
                   and context.get('chat_id')==c['chat_id'] and levels==context.get('levels')
                   and context.get('created',now+10)<=now+5)
    folder=(Path(c['common_files']) if c['common_files'] else
            Path(os.environ['APPDATA'])/'MetaQuotes/Terminal/Common/Files')/'FeishuMT5SignalMonitor'
    # 独立文件，不使正在运行的v1.56因新版的永久点位策略而改变授权状态。
    active=bool(not paused and source_ok)
    out=io.StringIO(newline=''); w=csv.writer(out,lineterminator='\r\n')
    selected=levels if active else []
    w.writerow(['TGE','1',int(now),int(active),c['symbols'][c['teacher_symbol']],
                context.get('message_id',''),context.get('revision',''),len(selected),
                int(context.get('created',0)),context.get('source_kind',''),
                context.get('sender','')])
    for level in selected: w.writerow(['LEVEL',format(level,'.10f')])
    w.writerow(['END',len(selected)])
    atomic_text(folder/'tge_levels.csv',out.getvalue())
    # 独立健康快照只解释同步状态，不给长期点位新增过期条件。
    health=io.StringIO(newline=''); hw=csv.writer(health,lineterminator='\r\n')
    hw.writerow(['HEALTH','1',int(now),int(state(db,'last_sync_at',0)),
                 int(state(db,'checkpoint',0)),int(bool(state(db,'last_sync_ok',False))),
                 int(paused),int(c['sync_max_age_seconds']),'END'])
    atomic_text(folder/'tge_health.csv',health.getvalue())
    ai=ai_snapshot(db,c,now,paused) if c.get('ai_enabled') else dict(active=False,mode='WAIT',plans=[],reason='AI未启用')
    bridge=io.StringIO(newline=''); aw=csv.writer(bridge,lineterminator='\r\n')
    note=str(ai['reason']).replace(',','，').replace('\r',' ').replace('\n',' ')[:160]
    aw.writerow(['TGA','3',int(now),int(ai['active']),c['symbols'][c['teacher_symbol']],
                 ai.get('message_id',''),ai.get('revision',''),int(ai.get('created',0)),len(ai['plans']),ai['mode'],note])
    for plan in ai['plans']:
        aw.writerow(['SETUP',plan['side'],format(plan['price'],'.10f'),plan['mode'],'NEAR' if plan.get('near') else 'POINT',
                     plan.get('origin_id',ai.get('message_id','')),plan.get('origin_revision',ai.get('revision','')),
                     int(plan.get('origin_created',ai.get('created',0))),
                     *[format(((plan.get('exits') or {}).get(key) or {}).get('price',0),'.10f')
                       for key in ('sl','tp1','tp2','breakeven')]])
    aw.writerow(['END',len(ai['plans'])])
    atomic_text(folder/'tge_ai_setups.csv',bridge.getvalue())

    follow=member_follow_snapshot(db,c,now,paused)
    fb=io.StringIO(newline=''); fw=csv.writer(fb,lineterminator='\r\n')
    plans=follow.get('plans',[])
    note=str(follow['reason']).replace(',','，').replace('\r',' ').replace('\n',' ')[:160]
    fw.writerow(['TGF','1',int(now),int(follow['active']),c['symbols'][c['teacher_symbol']],
                 follow.get('message_id',''),follow.get('revision',''),int(follow.get('created',0)),
                 int(follow.get('created',0))+300,follow.get('sender',''),len(plans),note])
    for plan in plans: fw.writerow(['FOLLOW',plan['side'],format(plan['price'],'.10f')])
    fw.writerow(['END',len(plans)])
    atomic_text(folder/'tge_member_follow.csv',fb.getvalue())

    # 新EA读多账号快照；旧单成员文件仍独立保留，升级不改旧EA协议。
    members=member_follow_snapshots(db,c,now,paused)
    multi=io.StringIO(newline=''); mw=csv.writer(multi,lineterminator='\r\n')
    mw.writerow(['TGF','2',int(now),c['symbols'][c['teacher_symbol']],len(members)])
    for member in members:
        plan=member['plans'][0] if member.get('active') else {}
        safe=lambda v:str(v).replace(',','，').replace('\r',' ').replace('\n',' ')[:160]
        mw.writerow(['MEMBER',member['sender'],safe(member['name']),int(member['active']),
            member.get('message_id',''),member.get('revision',''),int(member.get('created',0)),
            int(member.get('expiry',0)),member['ttl_seconds'],format(member['max_adverse_price'],'.10f'),
            plan.get('side',''),format(plan.get('price',0),'.10f'),safe(member['reason'])])
    mw.writerow(['END',len(members)])
    atomic_text(folder/'tge_member_follows.csv',multi.getvalue())

    # 保留旧EA的24小时来源上限、90秒心跳及指定老师身份；新规则不绕过旧EA。
    healthy=bool(state(db,'last_sync_ok',False)) and now-state(db,'last_sync_at',0)<=c['sync_max_age_seconds'] and now-state(db,'checkpoint',0)<=c['sync_max_age_seconds']
    ttl=c['levels_ttl_seconds'] or 86400
    deadline=min(now+90,context.get('created',0)+ttl)
    legacy=bool(active and healthy and row['sender']==c['teacher_sender_id']
                and now-row['checked']<=c['sync_max_age_seconds'] and deadline>now)
    out=io.StringIO(newline=''); w=csv.writer(out,lineterminator='\r\n')
    selected=levels if legacy else []
    w.writerow(['LEVELS','1',int(now),int(deadline if legacy else 0),int(legacy),
                c['symbols'][c['teacher_symbol']],context.get('message_id',''),context.get('revision',''),len(selected)])
    for level in selected: w.writerow(['LEVEL',format(level,'.10f')])
    w.writerow(['END',len(selected)])
    atomic_text(folder/'teacher_levels.csv',out.getvalue())
    if legacy: atomic_text(folder/'teacher_levels_display.csv',out.getvalue())

def report(db,home,c):
    rows=db.execute('''SELECT o.*,COALESCE(SUM(f.pnl-f.commission),0) net FROM orders o
      LEFT JOIN fills f ON f.order_id=o.id GROUP BY o.id ORDER BY o.id''').fetchall()
    closed=[r for r in rows if r['status']=='CLOSED']; wins=sum(r['net']>0 for r in closed)
    curve=db.execute('SELECT * FROM equity ORDER BY at').fetchall()
    peak=c['initial_equity']; dd=0; dd_pct=0
    for point in curve:
        peak=max(peak,point['equity']); dd=max(dd,peak-point['equity']); dd_pct=max(dd_pct,(peak-point['equity'])/peak if peak>0 else 0)
    net=db.execute('SELECT COALESCE(SUM(pnl-commission),0) FROM fills').fetchone()[0]
    metrics={'generated':iso(time.time()),'label':'本地纸面模拟，非券商成交','currency':c['currency'],'orders':len(rows),'closed':len(closed),'wins':wins,'win_rate':wins/len(closed) if closed else None,'realized_net':net,'max_drawdown':dd,'max_drawdown_fraction':dd_pct,'equity_sample_count':len(curve)}
    atomic_text(home/'reports'/'summary.json',json.dumps(metrics,ensure_ascii=False,indent=2))
    lines=['# Feishu MT5 Signal Monitor 模拟报告','',f'生成时间：{metrics["generated"]}','', '**全部结果是本地模拟，不是券商成交记录。**','',f'- 模拟单：{len(rows)}；完整平仓：{len(closed)}；盈利单：{wins}',f'- 胜率：{wins/len(closed):.2%}' if closed else '- 胜率：暂无完整平仓样本',f'- 已实现净盈亏：{net:.2f} {c["currency"]}',f'- 采样权益最大回撤：{dd:.2f}（{dd_pct:.2%}）','', '盈亏按 MT5 只读估算换算到配置货币；点差与配置滑点计入，佣金默认0、隔夜费未建模。断线期间不补造报价或成交，采样间隔内的触价可能无法还原。','', '|单号|品种|方向|状态|模拟盈亏|来源消息|','|---|---|---|---|---:|---|']
    for o in rows: lines.append(f'|{o["id"]}|{o["symbol"]}|{o["side"]}|{o["status"]}|{o["net"]:.2f}|{o["source_id"]}|')
    lines+=['','## 消息处理状态','']
    for row in db.execute('SELECT status,COUNT(*) n FROM signals GROUP BY status'): lines.append(f'- {row["status"]}：{row["n"]}')
    lines+=['','## 最近告警','']
    for row in db.execute('SELECT * FROM alerts ORDER BY id DESC LIMIT 20'): lines.append(f'- {iso(row["at"])} {row["code"]}：{row["detail"]}')
    atomic_text(home/'reports'/'report.md','\n'.join(lines)+'\n')
    s=io.StringIO(newline=''); w=csv.writer(s); w.writerow(['id','symbol','side','status','entry_price','volume','remaining','net','source_id'])
    for r in rows: w.writerow([r[k] for k in ['id','symbol','side','status','entry_price','volume','remaining','net','source_id']])
    atomic_text(home/'reports'/'trades.csv','\ufeff'+s.getvalue())
    return metrics

def monitor_cycle(db,c,engine,analysis,now,paused):
    healthy=bool(state(db,'last_sync_ok',False)) and now-state(db,'last_sync_at',0)<=c['sync_max_age_seconds'] and now-state(db,'checkpoint',0)<=c['sync_max_age_seconds']
    allow=not paused and healthy
    # monitor模式不会构造或调用模拟引擎，连旧模拟订单也不会继续推进。
    if c['mode']=='paper':
        engine.process_signals(now,allow); engine.tick(now,allow)
    reason='已暂停监控' if paused else '飞书未同步到当前时间，等待恢复' if not healthy else ''
    result=analysis.update(now,allow,reason)
    return healthy,result


def run(home,c,once=False,with_dashboard=True):
    with InstanceLock(home):
        logging.info('监控启动，PID=%d，模式=%s',os.getpid(),c['mode'])
        stop=threading.Event(); db=connect(home/'data'/'monitor.sqlite'); initialize_db(db,time.time())
        reader=LarkReader(c,stop); verify_chat(reader,c,home)
        quotes=MT5Reader(c)
        if c['mode']=='paper': c['currency']=quotes.account_currency()
        engine=PaperEngine(db,c,quotes) if c['mode']=='paper' else None
        analysis=TeacherAnalysis(db,c,quotes,time.time())
        worker=None; ai_thread=None; dashboard=None
        def shutdown(*_): stop.set()
        signal.signal(signal.SIGINT,shutdown); signal.signal(signal.SIGTERM,shutdown)
        (home/'control'/'stop').unlink(missing_ok=True)
        try:
            if not once and with_dashboard:
                dashboard=serve(home,c)
                logging.info('本地看板 http://127.0.0.1:%s/；运行模式=%s',c['dashboard_port'],c['mode'])
            if once:
                count,end=reader.sync_once(db,c['chat_id'],time.time())
                with db: set_state(db,'last_sync_at',time.time()); set_state(db,'last_sync_ok',True)
                logging.info('单次同步：%d条新增/变更',count)
            else:
                worker=threading.Thread(target=sync_worker,args=(home,c,stop),name='lark-reader')
                worker.start()
            if c.get('ai_enabled'):
                ai_thread=threading.Thread(target=ai_worker,args=(home,c,stop),name='deepseek-reader')
                ai_thread.start()
            last_report=0; last_export=0; last_quote_warning=0; last_analysis=0
            healthy=False; result={}
            while not stop.is_set():
                if (home/'control'/'stop').exists(): break
                now=time.time(); paused=(home/'control'/'pause').exists()
                if c['mode']=='paper' or now-last_analysis>=5:
                    healthy,result=monitor_cycle(db,c,engine,analysis,now,paused); last_analysis=now
                allow=not paused and healthy
                if now-last_export>=2:
                    export_observer(db,c,c['mode']!='paper' or not allow); last_export=now
                    export_teacher_levels(db,c,paused,now)
                    mt5_ok=result.get('market_ok',False)
                    if not mt5_ok and now-last_quote_warning>=60:
                        warn(home,'QUOTE_UNAVAILABLE',result.get('reason','行情未就绪')); last_quote_warning=now
                    atomic_text(home/'status.json',dumps({'pid':os.getpid(),'at':iso(time.time()),'paused':paused,'sync_healthy':healthy,'quote_healthy':mt5_ok,'mode':c['mode'],'trusted_senders':len(c['trusted_senders']),'checkpoint':iso(state(db,'checkpoint',now))}))
                if c['mode']=='paper' and now-last_report>=60: report(db,home,c); last_report=now
                if once: break
                stop.wait(c['quote_seconds'])
        finally:
            stop.set()
            if worker: worker.join(timeout=40)
            if ai_thread: ai_thread.join(timeout=22)
            if dashboard: dashboard.shutdown(); dashboard.server_close()
            if c['mode']=='paper': report(db,home,c)
            export_observer(db,c,True); export_teacher_levels(db,c,True,time.time()); quotes.close(); db.close()
            atomic_text(home/'status.json',dumps({'at':iso(time.time()),'stopped':True,'mode':c['mode']}))
            logging.info('监控已优雅停止')

def service(home,c):
    """看板常驻；监控子进程退出后退避重启，不调用交易接口。"""
    with InstanceLock(home,'service.lock'):
        db=connect(home/'data'/'monitor.sqlite'); initialize_db(db,time.time()); db.close()
        (home/'control'/'stop').unlink(missing_ok=True)
        stop=threading.Event(); child=None; server=None; failures=0; restarts=0; started=0; retry_at=0; last_error=''
        signal.signal(signal.SIGINT,lambda *_:stop.set())
        signal.signal(signal.SIGTERM,lambda *_:stop.set())
        executable=ROOT/'.venv/Scripts/pythonw.exe'
        try:
            server=serve(home,c)
            logging.info('常驻看板已启动：http://127.0.0.1:%s/，PID=%d',c['dashboard_port'],os.getpid())
            while not stop.is_set() and not (home/'control'/'stop').exists():
                now=time.time()
                if child is not None and child.poll() is not None:
                    code=child.returncode
                    failures=0 if now-started>=120 else failures
                    failures+=1; restarts+=1
                    retry_at=now+min(60,5*2**min(failures-1,4))
                    last_error=f'监控退出（代码{code}），{int(retry_at-now)}秒后重试；详见 monitor.log / worker-stderr.log'
                    logging.error(last_error); child=None
                if child is None and now>=retry_at:
                    try:
                        error_log=home/'logs'/'worker-stderr.log'
                        if error_log.exists() and error_log.stat().st_size>2_000_000:
                            os.replace(error_log,error_log.with_suffix('.log.1'))
                        with error_log.open('ab') as errors:
                            child=subprocess.Popen([str(executable),'-X','utf8',str(ROOT/'app.py'),'--home',str(home),'worker'],
                                cwd=ROOT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),
                                stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors)
                        started=now; last_error=''
                        logging.info('监控子进程已启动，PID=%d',child.pid)
                    except OSError as ex:
                        last_error='监控启动失败：'+str(ex); retry_at=now+30
                        logging.exception(last_error)
                atomic_text(home/'service.json',dumps({'at':iso(now),'pid':os.getpid(),'worker_pid':child.pid if child else None,
                    'restarts':restarts,'error':last_error,'next_retry':iso(retry_at) if child is None else None}))
                stop.wait(1)
        finally:
            # 先发停止标记，让监控完成检查点与失效快照写入。
            atomic_text(home/'control'/'stop','1')
            if child is not None and child.poll() is None:
                try: child.wait(timeout=55)
                except subprocess.TimeoutExpired:
                    logging.error('监控未及时退出，结束监控子进程；已过期快照不会用于新开仓')
                    child.terminate(); child.wait(timeout=5)
            if server: server.shutdown(); server.server_close()
            atomic_text(home/'service.json',dumps({'at':iso(time.time()),'stopped':True,'pid':os.getpid()}))
            logging.info('常驻服务已停止')

def install_task(home):
    """只创建/更新本项目自己的任务，启动不再依赖启动器进程存活。"""
    existing=subprocess.run(['schtasks.exe','/Query','/TN',TASK_NAME,'/XML'],capture_output=True)
    if existing.returncode==0:
        raw=existing.stdout
        xml=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'oem')
        task=ET.fromstring(xml); ns={'t':'http://schemas.microsoft.com/windows/2004/02/mit/task'}
        arguments=task.findtext('.//t:Exec/t:Arguments',default='',namespaces=ns)
        if str(ROOT/'app.py') not in arguments or str(home) not in arguments:
            raise RuntimeError('同名任务不属于当前项目，拒绝覆盖：'+TASK_NAME)
    target=home/'config'/'scheduled-task.xml'; target.write_text(task_xml(home),encoding='utf-16')
    command=['schtasks.exe','/Create','/TN',TASK_NAME,'/XML',str(target)]
    if existing.returncode==0: command.append('/F')
    result=subprocess.run(command,capture_output=True)
    if result.returncode: raise RuntimeError('任务计划安装失败：'+result.stderr.decode('oem',errors='replace'))

def task_xml(home):
    python=str(ROOT/'.venv/Scripts/pythonw.exe'); args=subprocess.list2cmdline(['-X','utf8',str(ROOT/'app.py'),'--home',str(home),'service'])
    user=os.environ.get('USERDOMAIN','')+'\\'+os.environ['USERNAME']
    return f'''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
 <RegistrationInfo><Description>Feishu read-only monitor and local analysis dashboard</Description></RegistrationInfo>
 <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>{escape(user)}</UserId><Delay>PT30S</Delay></LogonTrigger></Triggers>
 <Principals><Principal id="Author"><UserId>{escape(user)}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
 <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure></Settings>
 <Actions Context="Author"><Exec><Command>{escape(python)}</Command><Arguments>{escape(args)}</Arguments><WorkingDirectory>{escape(str(ROOT))}</WorkingDirectory></Exec></Actions>
</Task>'''

def main(argv=None):
    parser=argparse.ArgumentParser(description='飞书监控与 MT5 本地模拟；不存在实盘模式')
    parser.add_argument('--home',type=Path,default=DEFAULT_HOME,help='配置/运行数据目录，默认 LocalAppData')
    sub=parser.add_subparsers(dest='command',required=True)
    for name in ('run','worker','service','once','doctor','status','report','pause','resume','stop','start','dashboard','install-task','uninstall-task','ai-key'): sub.add_parser(name)
    imp=sub.add_parser('import-history'); imp.add_argument('--start',required=True); imp.add_argument('--end',required=True)
    args=parser.parse_args(argv); home=args.home.resolve(); c=config_load(home); setup(home,'service.log' if args.command=='service' else 'monitor.log')
    if args.command=='ai-key':
        import getpass
        from deepseek_ai import protect_secret
        key=getpass.getpass('DeepSeek API Key: ').strip()
        if not key.startswith('sk-') or len(key)<20: raise ValueError('API Key格式不正确')
        protect_secret(home/'credentials/deepseek.dpapi',key)
        print('凭证已用当前Windows用户加密保存'); return
    if args.command in ('pause','resume','stop'):
        if args.command=='resume': (home/'control'/'pause').unlink(missing_ok=True)
        else: atomic_text(home/'control'/args.command,'1')
        print('控制指令已保存：'+args.command); return
    if args.command=='status':
        path=home/'status.json'; print(path.read_text(encoding='utf-8') if path.exists() else '监控尚未启动'); return
    if args.command=='service': service(home,c); return
    if args.command=='dashboard':
        import webbrowser
        webbrowser.open(f'http://127.0.0.1:{c["dashboard_port"]}/'); return
    if args.command=='start':
        executable=ROOT/'.venv/Scripts/pythonw.exe'
        if not executable.exists(): raise RuntimeError('请先运行 Setup.cmd')
        install_task(home)
        result=subprocess.run(['schtasks.exe','/Run','/TN',TASK_NAME],capture_output=True)
        if result.returncode: raise RuntimeError('后台启动失败：'+result.stderr.decode('oem',errors='replace'))
        print('已通过任务计划启动常驻服务；用 Status.cmd 查看同步状态'); return
    if args.command in ('install-task','uninstall-task'):
        if args.command=='install-task':
            install_task(home); print('本项目登录启动任务已安装/更新'); return
        else: command=['schtasks.exe','/Delete','/TN',TASK_NAME,'/F']
        r=subprocess.run(command,capture_output=True)
        print(r.stdout.decode('oem',errors='replace')); print(r.stderr.decode('oem',errors='replace'))
        if r.returncode: raise RuntimeError('任务计划操作失败，代码'+str(r.returncode))
        return
    if args.command=='doctor':
        reader=LarkReader(c); found=verify_chat(reader,c,home)
        recent=reader.call(['im','+chat-messages-list','--chat-id',found['chat_id'],'--page-size','5','--no-reactions'])
        data=recent['data']; pagination=False
        if data.get('has_more'):
            nxt=reader.call(['im','+chat-messages-list','--chat-id',found['chat_id'],'--page-size','5','--no-reactions','--page-token',data['page_token']])
            pagination=bool(nxt.get('ok'))
        result={'at':iso(time.time()),'chat_id':found['chat_id'],'external':found.get('external'),'read_count':len(data.get('messages',[])),'pagination_verified':pagination}
        quotes=MT5Reader(c)
        try:
            result['currency']=quotes.account_currency()
            qs=[quotes.quote(s,time.time()).__dict__ for s in set(c['symbols'].values())]
            result['quotes']=qs; result['mt5_readonly_verified']=True
        except QuoteError as ex: result['mt5_error']=str(ex)
        finally: quotes.close()
        atomic_text(home/'reports'/'doctor.json',json.dumps(result,ensure_ascii=False,indent=2)); print(json.dumps(result,ensure_ascii=False,indent=2)); return
    if args.command=='report':
        db=connect(home/'data'/'monitor.sqlite'); print(json.dumps(report(db,home,c),ensure_ascii=False,indent=2)); db.close(); return
    if args.command=='import-history':
        start,end=stamp(args.start),stamp(args.end)
        if end<=start or end>time.time(): raise ValueError('历史导入时间范围不正确')
        with InstanceLock(home):
            db=connect(home/'data'/'monitor.sqlite'); reader=LarkReader(c); verify_chat(reader,c,home)
            while start<end:
                until=min(end,start+c['window_seconds'])
                messages,_,_=reader.collect(db,c['chat_id'],start,until,reconcile=False)
                n=ingest(db,c['chat_id'],messages,historical=True)
                logging.info('历史分析导入%d条，截至%s；不会生成订单',n,iso(until)); start=until
            report(db,home,c); db.close()
        return
    run(home,c,once=args.command=='once',with_dashboard=args.command!='worker')

if __name__=='__main__':
    try: main()
    except Exception as ex:
        logging.exception('运行失败：%s',ex)
        if sys.stderr is not None: print('运行失败：'+str(ex),file=sys.stderr)
        sys.exit(1)
