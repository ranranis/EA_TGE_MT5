"""预览/应用只在临时数据库测试，不连接真实MT5或群聊。"""
import copy
import json
from pathlib import Path
import re
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import urllib.request
import urllib.error

from app import config_load, export_teacher_levels
from dashboard import serve
from deepseek_ai import AIError, initialize_ai, process_ai_batch
from plan_preview import begin_preview, generate_preview, apply_preview
from store import connect, ingest, state, set_state, iso


class PreviewTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.home=Path(self.temp.name)
        self.c=config_load(self.home);self.c.update(chat_id='test',teacher_sender_id='teacher',ai_enabled=True,common_files=str(self.home/'common'))
        (self.home/'data').mkdir();(self.home/'control').mkdir(exist_ok=True)
        self.db=connect(self.home/'data/monitor.sqlite');initialize_ai(self.db);self.now=time.time()
        with self.db:
            for key,value in dict(live_since=self.now-10000,last_sync_ok=True,last_sync_at=self.now,checkpoint=self.now,
                                  teacher_analysis={'market_ok':True,'quote':{'at':self.now,'bid':4175,'ask':4175.2},'bars':[]}).items():
                set_state(self.db,key,value)
        (self.home/'status.json').write_text(json.dumps({'at':iso(self.now),'paused':False}),encoding='utf-8')
        self.message=dict(message_id='buy',chat_id='test',sender={'id':'teacher'},create_time=self.now-30,msg_type='text',content='4175做多')
        ingest(self.db,'test',[self.message])
        self.client=Mock(interpret=self.reply)
        process_ai_batch(self.db,self.c,self.client,self.now)
        self.original=copy.deepcopy(state(self.db,'deepseek_setup'))

    def tearDown(self):
        self.db.close();self.temp.cleanup()

    def reply(self,targets,*args,**kwargs):
        t=targets[-1];text=t['text']
        p=dict(side='BUY',token='4175',price=4175,mode='REACTION',price_ref='buy',price_evidence=text,
               direction_ref='buy',direction_evidence=text)
        scene=dict(as_of='buy',action='UPDATE',regime='UNKNOWN',regime_ref=None,plans=[p],
                   inner_range=None,outer_range=None,summary='明确做多4175')
        return dict(interpretations=[dict(id=t['id'],kind='SETUP',plans=[dict(side='BUY',token='4175',price=4175,mode='REACTION',evidence=text)],cancel_side='NONE',reason='明确做多')],scene=scene)

    def draft(self,client=None):
        draft=begin_preview(self.home,self.c)
        generate_preview(self.home,self.c,draft['id'],client or self.client)
        return state(self.db,'plan_preview')

    def test_preview_does_not_publish_or_requeue_or_create_order(self):
        rows=[tuple(r) for r in self.db.execute('SELECT * FROM ai_messages')]
        draft=self.draft()
        self.assertEqual(draft['status'],'READY')
        self.assertEqual(state(self.db,'deepseek_setup'),self.original)
        self.assertEqual(rows,[tuple(r) for r in self.db.execute('SELECT * FROM ai_messages')])
        self.assertFalse((self.home/'common').exists())
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

    def test_apply_once_preserves_identity_and_exports(self):
        draft=self.draft()
        first=apply_preview(self.home,self.c,draft['id'])
        self.assertEqual(first['status'],'APPLIED')
        second=apply_preview(self.home,self.c,draft['id'])
        self.assertEqual(first,second)
        self.assertEqual(state(self.db,'deepseek_setup')['plans'][0]['origin_revision'],self.original['plans'][0]['origin_revision'])
        export_teacher_levels(self.db,self.c,False,time.time())
        text=(self.home/'common/FeishuMT5SignalMonitor/tge_ai_setups.csv').read_text(encoding='utf-8')
        self.assertIn('SETUP,BUY,4175.',text)
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

    def test_failed_model_keeps_live_plan(self):
        draft=self.draft(Mock(interpret=Mock(side_effect=AIError('模型未通过'))))
        self.assertEqual(draft['status'],'FAILED')
        self.assertEqual(state(self.db,'deepseek_setup'),self.original)

    def test_edit_during_preview_invalidates(self):
        def reply(*args,**kwargs):
            ingest(self.db,'test',[dict(self.message,content='4175不做多',update_time='changed')])
            return self.reply(*args,**kwargs)
        draft=self.draft(Mock(interpret=reply))
        self.assertEqual(draft['status'],'FAILED')
        self.assertEqual(state(self.db,'deepseek_setup'),self.original)

    def test_new_cancel_after_preview_blocks_apply(self):
        draft=self.draft()
        ingest(self.db,'test',[dict(self.message,message_id='cancel',content='取消所有',create_time=self.now)])
        with self.assertRaises(AIError):apply_preview(self.home,self.c,draft['id'])
        self.assertEqual(state(self.db,'deepseek_setup'),self.original)

    def test_rejects_offline_quote_paused_expired_and_old_id(self):
        for case in ('quote','sync','paused','expired','id'):
            with self.subTest(case=case):
                draft=self.draft()
                with self.db:
                    set_state(self.db,'last_sync_ok',case!='sync')
                    market=state(self.db,'teacher_analysis');market['market_ok']=case!='quote';set_state(self.db,'teacher_analysis',market)
                    if case=='expired':draft['completed']=self.now-601;set_state(self.db,'plan_preview',draft)
                if case=='paused':(self.home/'control/pause').touch()
                with self.assertRaises(AIError):
                    apply_preview(self.home,self.c,'wrong' if case=='id' else draft['id'])
                (self.home/'control/pause').unlink(missing_ok=True)
                self.assertEqual(state(self.db,'deepseek_setup'),self.original)

    def test_duplicate_preview_request_is_rejected(self):
        begin_preview(self.home,self.c)
        with self.assertRaises(AIError):begin_preview(self.home,self.c)

    def test_market_plan_is_not_replayed(self):
        def reply(*args,**kwargs):
            raw=self.reply(*args,**kwargs);raw['scene']['plans'][0]['mode']='MARKET'
            return raw
        ingest(self.db,'test',[dict(self.message,content='现价4175做多')])
        draft=self.draft(Mock(interpret=reply))
        self.assertEqual(draft['status'],'READY')
        self.assertEqual(draft['scene']['plans'],[])

    def test_historical_only_never_replayed(self):
        with self.db:self.db.execute('UPDATE messages SET historical=1')
        draft=self.draft()
        self.assertEqual(draft['status'],'FAILED')

    def test_http_origin_token_confirmation_and_server_stored_plan(self):
        server=serve(self.home,self.c|{'dashboard_port':0});base=f'http://127.0.0.1:{server.server_port}'
        def request(path,body,headers):
            return urllib.request.urlopen(urllib.request.Request(base+path,data=json.dumps(body).encode(),headers=headers),timeout=3)
        try:
            with urllib.request.urlopen(base) as r:
                html=r.read().decode()
            token=re.search("const actionToken='([^']+)'",html)[1]
            headers={'Content-Type':'application/json','Origin':base,'X-Local-Token':token}
            with patch('dashboard.apply_preview',return_value={'status':'APPLIED'}) as apply:
                for bad in ({},headers|{'Origin':'https://evil.test'},headers|{'X-Local-Token':'bad'}):
                    with self.assertRaises(urllib.error.HTTPError) as error:request('/api/plan-apply',{'id':'draft','confirmed':True},bad)
                    self.assertEqual(error.exception.code,403)
                for body in ({'id':'draft'},{'id':'draft','confirmed':False},{'id':'draft','confirmed':True,'plans':[]}):
                    with self.assertRaises(urllib.error.HTTPError) as error:request('/api/plan-apply',body,headers)
                    self.assertEqual(error.exception.code,400)
                apply.assert_not_called()
                with request('/api/plan-apply',{'id':'draft','confirmed':True},headers) as r:self.assertEqual(r.status,200)
                apply.assert_called_once()
        finally:server.shutdown();server.server_close()


if __name__=='__main__':unittest.main()
