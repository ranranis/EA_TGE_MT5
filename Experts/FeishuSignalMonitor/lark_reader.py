"""只调用官方 CLI 的固定只读命令，不解释或执行消息中的命令。"""
import json
import logging
import os
import shutil
import subprocess
import threading
from pathlib import Path
from store import iso, state, ingest

class LarkError(RuntimeError): pass
class AuthRequired(LarkError): pass

def locate_cli(configured=''):
    candidates=[configured,shutil.which('lark-cli.exe'),str(Path.home()/'.workbuddy/binaries/node/cli-connector-packages/node_modules/@larksuite/cli/bin/lark-cli.exe')]
    for p in candidates:
        if p and Path(p).is_file(): return str(Path(p).resolve())
    raise LarkError('找不到 lark-cli.exe，请在本地配置 lark_cli 绝对路径')

class LarkReader:
    def __init__(self,config,stop=None):
        self.config=config; self.cli=locate_cli(config.get('lark_cli','')); self.stop=stop or threading.Event()

    def call(self,args):
        env=dict(os.environ,LARKSUITE_CLI_NO_UPDATE_NOTIFIER='1',LARKSUITE_CLI_NO_SKILLS_NOTIFIER='1')
        # 不能让群消息、配置的自由文本成为 shell 命令。
        for attempt in range(4):
            if self.stop.is_set(): raise LarkError('已请求停止')
            try:
                result=subprocess.run([self.cli]+args+['--as','user','--format','json'],shell=False,env=env,capture_output=True,text=True,encoding='utf-8',timeout=30,
                    creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
                d=json.loads(result.stdout if result.stdout.strip() else result.stderr)
                if result.returncode==0 and d.get('ok'):
                    if result.stderr.strip(): logging.warning('飞书读取提示（详情已隐藏，避免泄露正文）：%s',result.stderr[:120].replace('\n',' '))
                    return d
                err=d.get('error',{}); code=str(err.get('code','')); category=err.get('type','')
                if category in ('authentication','authorization') or code in ('99991663','99991664','99991668','99991671','99991672','99991679'):
                    raise AuthRequired('飞书需要重新授权或权限不足；错误码='+code+'；缺失权限='+','.join(err.get('missing_scopes',[])))
                if category!='network' and code not in ('99991400','99991401'):
                    raise LarkError('飞书接口拒绝请求；错误码='+code+'；类型='+category)
            except (subprocess.TimeoutExpired,json.JSONDecodeError,OSError):
                pass
            if attempt<3:
                logging.warning('飞书网络/限速异常，%s秒后重试',2**attempt)
                self.stop.wait(2**attempt)
        raise LarkError('飞书读取连续失败；检查网络，检查点未推进')

    def pages(self,base):
        token=''; seen=set(); all_messages=[]
        for _ in range(self.config['max_pages']):
            data=self.call(base+(['--page-token',token] if token else []))
            payload=data['data']; all_messages.extend(payload.get('messages',[]))
            more=payload.get('has_more',data.get('meta',{}).get('pagination',{}).get('complete') is False)
            if not more: return all_messages
            token=payload.get('page_token') or data.get('meta',{}).get('pagination',{}).get('next_token')
            if not token or token in seen: raise LarkError('分页游标未前进，整批未提交')
            seen.add(token)
        raise LarkError('达到分页保护上限，整批未提交；提高 max_pages 或缩短 window_seconds')

    def search(self,name):
        d=self.call(['im','+chat-search','--query',name,'--disable-search-by-user','--page-size','100','--page-all','--page-limit','1000'])
        if d.get('data',{}).get('has_more') or d.get('meta',{}).get('pagination',{}).get('complete') is False: raise LarkError('群搜索未完成，不能确认唯一匹配')
        matches=[x for x in d['data']['chats'] if x['name']==name]
        if len(matches)!=1: raise LarkError('群名称不唯一或不可见：'+json.dumps([{'name':x['name'],'chat_id':x['chat_id']} for x in matches],ensure_ascii=False))
        return matches[0]

    def chat_messages(self,chat_id,start,end):
        return self.pages(['im','+chat-messages-list','--chat-id',chat_id,'--start',iso(start),'--end',iso(end),'--order','asc','--page-size','50','--no-reactions'])

    def collect(self,db,chat_id,start,end,reconcile=True):
        messages=self.chat_messages(chat_id,start,end); checked=[]
        if reconcile:
            active=[r[0] for r in db.execute("SELECT source_id FROM orders WHERE status IN ('OPEN','PENDING')")]
            teacher=state(db,'teacher_levels',{})
            if teacher.get('message_id'): active.append(teacher['message_id'])
            rotating=[r[0] for r in db.execute('SELECT message_id FROM messages WHERE chat_id=? ORDER BY checked LIMIT ?',(chat_id,self.config['reconcile_batch']))]
            checked=list(dict.fromkeys(active+rotating))
            for i in range(0,len(checked),50):
                ids=checked[i:i+50]
                data=self.call(['im','+messages-mget','--message-ids',','.join(ids),'--no-reactions'])
                got=data['data'].get('messages',[])
                missing=set(ids)-{m['message_id'] for m in got}
                if missing: raise LarkError('已知消息无法读取，可能撤回或权限变化；需核对：'+','.join(sorted(missing)))
                messages.extend(got)
        expanded=[]
        for m in messages: expanded.extend(m.get('thread_replies',[]))
        messages.extend(expanded)
        tids={m['thread_id'] for m in messages if m.get('thread_id')}
        if reconcile:
            tids.update(r[0] for r in db.execute('SELECT thread_id FROM threads ORDER BY checked LIMIT ?',(self.config['thread_batch'],)))
        for tid in sorted(tids):
            messages.extend(self.pages(['im','+threads-messages-list','--thread',tid,'--order','asc','--page-size','50','--no-reactions']))
        unique={m['message_id']:m for m in messages}
        return list(unique.values()),checked,sorted(tids)

    def sync_once(self,db,chat_id,now):
        checkpoint=state(db,'checkpoint',now-self.config['overlap_seconds'])
        end=min(now,checkpoint+self.config['window_seconds'])
        messages,ids,threads=self.collect(db,chat_id,max(0,checkpoint-self.config['overlap_seconds']),end)
        count=ingest(db,chat_id,messages,cutoff=end,checked_ids=ids,thread_ids=threads)
        return count,end
