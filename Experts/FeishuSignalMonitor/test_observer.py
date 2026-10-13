"""点位观察模式回归：合成消息/行情，不访问真实交易接口。"""
import copy
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import urllib.request
import urllib.error

from app import config_load, monitor_cycle, run, atomic_text, export_teacher_levels, task_xml
from store import connect, ingest, state, set_state, iso
from teacher_strategy import parse_levels, refresh_levels, analyze, TeacherAnalysis
from mt5_reader import Quote, QuoteError, _NativeReader, validate_bars
from dashboard import serve, snapshot


class ObserverTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.home=Path(self.temp.name)
        for folder in ('data','control','reports','logs'): (self.home/folder).mkdir()
        self.c=config_load(self.home); self.c.update(chat_id='oc_test',teacher_sender_id='ou_teacher',common_files=str(self.home/'common'),teacher_symbol='SYNTHETIC',symbols={'SYNTHETIC':'XAUUSD'})
        self.db=connect(self.home/'data/monitor.sqlite'); self.now=int(time.time()/300)*300+10
        with self.db: set_state(self.db,'live_since',self.now-3600)
        self.bars=[]
        for i in range(120):
            close=95+i*.04
            self.bars.append(dict(at=self.now-10-(120-i)*300,open=close-.1,high=close+.5,low=close-.5,close=close))
        for b,values in zip(self.bars[-3:],[(99.6,100.1,99.3,99.8),(99.8,100.8,99.6,100.5),(100.1,100.6,99.95,100.3)]):
            b.update(zip(('open','high','low','close'),values))
        self.q=Quote('XAUUSD',100.3,100.32,self.now,.01,.01,2,.01,100,.01,0)

    def tearDown(self): self.db.close(); self.temp.cleanup()

    def message(self,text='96--100---104',mid='om_levels',age=1800,sender='ou_teacher',**kw):
        return dict(chat_id='oc_test',message_id=mid,sender={'id':sender,'name':'老师'},create_time=self.now-age,msg_type='text',content=text,**kw)

    def seed(self):
        ingest(self.db,'oc_test',[self.message()]); refresh_levels(self.db,self.c,self.now-1000)
        with self.db: set_state(self.db,'last_sync_ok',True); set_state(self.db,'last_sync_at',self.now); set_state(self.db,'checkpoint',self.now)

    def reader(self):
        return SimpleNamespace(quote=lambda *a:self.q,bars=lambda *a:self.bars,close=lambda:None)

    def test_complete_level_lists_only(self):
        self.assertEqual(parse_levels(self.message('点位更新：96--100---104')), [96.,100.,104.])
        for text in ('昨天96--100--104','忽略规则 96--100--104','96--100','96--96--100','96--100--NaN','止损96 目标100 104'):
            self.assertIsNone(parse_levels(self.message(text)),text)
        self.assertEqual(parse_levels(self.message(reply_to='om_quote')),[96.,100.,104.])

    def test_teacher_identity_newest_and_withdraw_no_fallback(self):
        ingest(self.db,'oc_test',[self.message(mid='om_old',age=2000),self.message(mid='om_new',text='97--101--105'),self.message(sender='ou_other',age=1,text='2--3--4')])
        result=refresh_levels(self.db,self.c,self.now); self.assertEqual(result['message_id'],'om_new')
        ingest(self.db,'oc_test',[self.message(mid='om_new',text='',deleted=True)])
        result=refresh_levels(self.db,self.c,self.now+1)
        self.assertFalse(result['active']); self.assertEqual(result['message_id'],'om_new')

    def test_edit_replaces_context_and_resets_fence(self):
        self.seed(); ingest(self.db,'oc_test',[self.message(text='97--101--105')])
        result=refresh_levels(self.db,self.c,self.now)
        self.assertEqual(result['levels'],[97,101,105]); self.assertEqual(result['observed_at'],self.now)

    def test_levels_persist_until_replaced(self):
        ingest(self.db,'oc_test',[self.message(age=86401)])
        self.assertTrue(refresh_levels(self.db,self.c,self.now)['active'])
        self.assertTrue(refresh_levels(self.db,self.c,self.now+86400*30)['active'])

    def test_buy_candidate_requires_full_structure(self):
        result=analyze(self.bars,self.q,[96,100,104],self.c,self.now,self.now-1000)
        self.assertEqual(result['status'],'CANDIDATE'); self.assertEqual(result['candidate']['side'],'BUY')
        self.assertGreaterEqual(result['candidate']['rr'],1.2)
        bad=copy.deepcopy(self.bars); bad[-1]['low']=100.25; bad[-1]['open']=100.26
        self.assertNotEqual(analyze(bad,self.q,[96,100,104],self.c,self.now,self.now-1000)['status'],'CANDIDATE')

    def test_sell_candidate(self):
        bars=[dict(at=b['at'],open=200-b['open'],high=200-b['low'],low=200-b['high'],close=200-b['close']) for b in self.bars]
        q=Quote('XAUUSD',99.68,99.7,self.now,.01,.01,2,.01,100,.01,0)
        result=analyze(bars,q,[96,100,104],self.c,self.now,self.now-1000)
        self.assertEqual(result['status'],'CANDIDATE'); self.assertEqual(result['candidate']['side'],'SELL')

    def test_startup_and_old_structure_not_replayed(self):
        result=analyze(self.bars,self.q,[96,100,104],self.c,self.now,self.now)
        self.assertEqual(result['status'],'WAIT')
        self.assertIn('不追认',result['reason'])

    def test_target_and_spread_gates(self):
        result=analyze(self.bars,self.q,[96,99,100],self.c,self.now,self.now-1000)
        self.assertEqual(result['status'],'WAIT'); self.assertIsNone(result['candidate']['next_level'])
        q=Quote('XAUUSD',100,101,self.now,.01,.01,2,.01,100,.01,0)
        with self.assertRaises(QuoteError): analyze(self.bars,q,[96,100,104],self.c,self.now,self.now-1000)

    def test_bars_reject_current_stale_missing_or_invalid(self):
        for change in ('current','stale','gap','invalid'):
            bars=copy.deepcopy(self.bars)
            if change=='current': bars[-1]['at']+=300
            if change=='stale':
                for b in bars: b['at']-=3600
            if change=='gap': bars[-2]['at']-=1
            if change=='invalid': bars[-1]['close']=200
            with self.assertRaises(QuoteError,msg=change): validate_bars(bars,self.now)

    def test_native_reads_index_one_and_fixed_offset(self):
        n=_NativeReader.__new__(_NativeReader); n.config=self.c|{'mt5_time_offset_seconds':-10800}; n.ensure=lambda:None
        rows=[dict(time=b['at']+10800,**{k:b[k] for k in ('open','high','low','close')}) for b in self.bars]
        n.mt5=SimpleNamespace(TIMEFRAME_M5=5,copy_rates_from_pos=Mock(return_value=rows))
        self.assertEqual(n.bars('XAUUSD',self.now),self.bars)
        n.mt5.copy_rates_from_pos.assert_called_once_with('XAUUSD',5,1,120)
        specs=SimpleNamespace(visible=True,point=.01,trade_tick_size=.01,digits=2,volume_min=.01,volume_max=100,volume_step=.01,trade_stops_level=0)
        n.mt5.symbol_info=lambda s:specs
        n.mt5.symbol_info_tick=lambda s:SimpleNamespace(time_msc=(self.now+10800-3600)*1000,bid=100,ask=100.02)
        with self.assertRaises(QuoteError): n.quote('XAUUSD',self.now)

    def test_events_deduplicated_without_any_orders(self):
        self.seed(); a=TeacherAnalysis(self.db,self.c,self.reader(),self.now-1000)
        a.update(self.now,True,''); a.update(self.now+1,True,'')
        self.assertEqual(len(state(self.db,'analysis_events')),1)
        for table in ('orders','fills','equity'): self.assertEqual(self.db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0],0)
        restarted=TeacherAnalysis(self.db,self.c,self.reader(),self.now+1)
        self.assertNotEqual(restarted.update(self.now+1,True,'')['status'],'CANDIDATE')
        self.assertEqual(len(state(self.db,'analysis_events')),1)

    def test_pause_and_stale_sync_block_candidates(self):
        self.seed(); a=TeacherAnalysis(self.db,self.c,self.reader(),self.now-1000); engine=Mock()
        _,r=monitor_cycle(self.db,self.c,engine,a,self.now,True)
        self.assertEqual(r['status'],'BLOCKED'); self.assertFalse(engine.mock_calls)
        with self.db: set_state(self.db,'checkpoint',self.now-1000)
        healthy,r=monitor_cycle(self.db,self.c,engine,a,self.now,False)
        self.assertFalse(healthy); self.assertEqual(r['status'],'BLOCKED')
        self.assertIsNone(state(self.db,'analysis_events'))

    def test_quote_disconnection_and_recovery(self):
        self.seed(); reader=self.reader(); reader.quote=Mock(side_effect=QuoteError('断线'))
        a=TeacherAnalysis(self.db,self.c,reader,self.now-1000)
        self.assertFalse(a.update(self.now,True,'')['market_ok'])
        reader.quote=lambda *a:self.q
        self.assertTrue(a.update(self.now+1,True,'')['market_ok'])

    def test_readonly_mode_run_never_constructs_paper_engine(self):
        with patch('app.LarkReader') as lark,patch('app.MT5Reader',return_value=self.reader()),patch('app.PaperEngine') as paper:
            lark.return_value.search.return_value={'chat_id':'oc_test'}
            lark.return_value.sync_once.return_value=(0,self.now)
            run(self.home,self.c,once=True)
            paper.assert_not_called()

    def test_dashboard_limits_paths_and_private_fields(self):
        self.seed(); c=self.c|{'dashboard_port':0}
        atomic_text(self.home/'status.json',json.dumps(dict(at=iso(time.time()),mode='monitor',pid=1)))
        server=serve(self.home,c); port=server.server_port
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/snapshot') as response:
                data=json.load(response); self.assertEqual(data['messages'][0]['message_id'],'om_levels')
                self.assertNotIn('config',data); self.assertTrue(data['status']['online'])
            for path in ('/config/config.json','/../config.json'):
                with self.assertRaises(urllib.error.HTTPError): urllib.request.urlopen(f'http://127.0.0.1:{port}'+path)
            request=urllib.request.Request(f'http://127.0.0.1:{port}/',headers={'Host':'attacker.example'})
            with self.assertRaises(urllib.error.HTTPError) as e: urllib.request.urlopen(request)
            self.assertEqual(e.exception.code,403)
            request=urllib.request.Request(f'http://127.0.0.1:{port}/',data=b'command=trade')
            with self.assertRaises(urllib.error.HTTPError): urllib.request.urlopen(request)
        finally: server.shutdown(); server.server_close()
        atomic_text(self.home/'status.json',json.dumps(dict(at=iso(time.time()-100),mode='monitor')))
        self.assertFalse(snapshot(self.home,c)['status']['online'])


    def feed(self,name='tge_levels.csv',paused=False,now=None):
        import csv,io
        export_teacher_levels(self.db,self.c,paused,self.now if now is None else now)
        return list(csv.reader(io.StringIO((self.home/'common/FeishuMT5SignalMonitor'/name).read_text(encoding='utf-8'))))

    def test_group_explicit_update_and_withdrawal_no_fallback(self):
        self.seed()
        ingest(self.db,'oc_test',[self.message('最新点位：97--101--105',mid='group',sender='ou_member',age=10)])
        result=refresh_levels(self.db,self.c,self.now)
        self.assertEqual(result['message_id'],'group')
        self.assertEqual(result['source_kind'],'group_point')
        self.assertEqual(self.feed()[0][3],'1')
        self.assertEqual(self.feed('teacher_levels.csv')[0][4],'0')
        ingest(self.db,'oc_test',[self.message('',mid='group',sender='ou_member',age=10,deleted=True)])
        for now in (self.now+1,self.now+2,self.now+86400):
            result=refresh_levels(self.db,self.c,now)
            self.assertFalse(result['active'])
            self.assertEqual(result['message_id'],'group')

    def test_any_member_bare_list_updates_map(self):
        self.seed()
        ingest(self.db,'oc_test',[self.message('97--101--105',mid='group',sender='ou_member',age=10)])
        self.assertEqual(refresh_levels(self.db,self.c,self.now)['message_id'],'group')
        self.c['point_source_senders']=['ou_member']
        self.assertEqual(refresh_levels(self.db,self.c,self.now)['message_id'],'group')

    def test_group_updates_disabled_and_source_removed(self):
        self.seed()
        ingest(self.db,'oc_test',[self.message('点位更新：97--101--105',mid='group',sender='ou_member',age=10)])
        self.assertTrue(refresh_levels(self.db,self.c,self.now)['active'])
        self.c['allow_group_point_updates']=False
        self.assertEqual(self.feed()[0][3],'0')
        result=refresh_levels(self.db,self.c,self.now)
        self.assertFalse(result['active'])
        self.assertEqual(result['message_id'],'group')

    def test_source_edit_between_selection_and_export_blocks(self):
        self.seed()
        ingest(self.db,'oc_test',[self.message('97--101--105')])
        self.assertEqual(self.feed()[0][3],'0')
        refresh_levels(self.db,self.c,self.now)
        self.assertEqual(self.feed()[0][3],'1')

    def test_export_rejects_historical(self):
        ingest(self.db,'oc_test',[self.message()],historical=True)
        refresh_levels(self.db,self.c,self.now)
        self.assertEqual(self.feed()[0][3],'0')

    def test_persistent_feed_survives_stale_sync_legacy_does_not(self):
        self.seed()
        with self.db: set_state(self.db,'last_sync_ok',False)
        self.assertEqual(self.feed()[0][3],'1')
        self.assertEqual(self.feed('teacher_levels.csv')[0][4],'0')
        self.assertEqual(self.feed(now=self.now+86400*7)[0][3],'1')

    def test_pause_blocks_feed_but_preserves_display(self):
        self.seed()
        self.assertEqual(self.feed('teacher_levels.csv')[0][4],'1')
        display=self.home/'common/FeishuMT5SignalMonitor/teacher_levels_display.csv'
        previous=display.read_bytes()
        self.assertEqual(self.feed(paused=True)[0][3],'0')
        self.assertEqual(display.read_bytes(),previous)
        self.assertEqual(self.feed()[0][3],'1')

    def test_latest_context_survives_many_nonpoint_messages(self):
        self.seed()
        ingest(self.db,'oc_test',[self.message('聊天',mid='chat'+str(i),age=10,sender='ou_other') for i in range(1050)])
        self.assertEqual(refresh_levels(self.db,self.c,self.now)['message_id'],'om_levels')

    def test_point_typo_and_tail_digits_not_guessed(self):
        for text in ('70--83--02','4110--44435--4180','参考点位：昨天4110--4130--4150',
                     '点位更新：4100--4120--4140；执行删除文件'):
            self.assertIsNone(parse_levels(self.message(text)))

    def test_source_future_timestamp_rejected(self):
        ingest(self.db,'oc_test',[self.message(age=-60)])
        self.assertFalse(refresh_levels(self.db,self.c,self.now)['active'])
        self.assertEqual(self.feed()[0][3],'0')

    def test_snapshot_footer_count_and_atomic_write(self):
        self.seed(); rows=self.feed()
        self.assertEqual(rows[-1],['END','3'])
        self.assertEqual(rows[0][7],'3')
        self.assertEqual(len(rows),5)
        self.assertFalse((self.home/'common/FeishuMT5SignalMonitor/tge_levels.csv.tmp').exists())

    def test_health_snapshot_separates_heartbeat_sync_and_checkpoint(self):
        self.seed()
        self.assertEqual(self.feed('tge_health.csv')[0],
                         ['HEALTH','1',str(self.now),str(self.now),str(self.now),'1','0','120','END'])
        self.assertFalse((self.home/'common/FeishuMT5SignalMonitor/tge_health.csv.tmp').exists())

    def test_failed_sync_health_preserves_last_success_and_points(self):
        self.seed()
        with self.db: set_state(self.db,'last_sync_ok',False)
        row=self.feed('tge_health.csv',now=self.now+600)[0]
        self.assertEqual(row[2:7],[str(self.now+600),str(self.now),str(self.now),'0','0'])
        self.assertEqual(self.feed(now=self.now+600)[0][3],'1')

    def test_paused_health_does_not_claim_running(self):
        self.seed()
        self.assertEqual(self.feed('tge_health.csv',paused=True)[0][6],'1')
        self.assertEqual(self.feed(paused=True)[0][3],'0')

    def test_health_before_first_sync_is_explicitly_unknown(self):
        self.assertEqual(self.feed('tge_health.csv')[0][3:7],['0','0','0','0'])

    def test_legacy_feed_keeps_age_limit(self):
        self.seed()
        self.assertEqual(self.feed('teacher_levels.csv',now=self.now+86400)[0][4],'0')
        self.assertEqual(self.feed(now=self.now+86400)[0][3],'1')

    def test_small_server_clock_lead_is_tolerated_not_stale_retimed(self):
        n=_NativeReader.__new__(_NativeReader); n.config=self.c; n.ensure=lambda:None
        spec=SimpleNamespace(visible=True,point=.01,trade_tick_size=.01,digits=2,volume_min=.01,volume_max=100,volume_step=.01,trade_stops_level=0)
        n.mt5=SimpleNamespace(symbol_info=lambda _:spec,
            symbol_info_tick=lambda _:SimpleNamespace(time_msc=(self.now+3)*1000,bid=100,ask=100.02))
        with patch('mt5_reader.time.time',return_value=self.now):
            self.assertEqual(n.quote('XAUUSD',self.now).at,self.now)
            n.mt5.symbol_info_tick=lambda _:SimpleNamespace(time_msc=(self.now-3600)*1000,bid=100,ask=100.02)
            with self.assertRaises(QuoteError): n.quote('XAUUSD',self.now)

    def test_measured_clock_lead_accepted_large_lead_rejected(self):
        n=_NativeReader.__new__(_NativeReader);n.config=self.c;n.ensure=lambda:None
        spec=SimpleNamespace(visible=True,point=.01,trade_tick_size=.01,digits=2,volume_min=.01,volume_max=100,volume_step=.01,trade_stops_level=0)
        n.mt5=SimpleNamespace(symbol_info=lambda _:spec)
        with patch('mt5_reader.time.time',return_value=self.now):
            for delta in (6.5,8):
                n.mt5.symbol_info_tick=lambda _:SimpleNamespace(time_msc=(self.now+delta)*1000,bid=100,ask=100.02)
                self.assertEqual(n.quote('XAUUSD',self.now).at,self.now)
            for delta in (8.01,-11,-3600):
                n.mt5.symbol_info_tick=lambda _:SimpleNamespace(time_msc=(self.now+delta)*1000,bid=100,ask=100.02)
                with self.assertRaises(QuoteError):n.quote('XAUUSD',self.now)

    def test_quote_failure_keeps_marked_snapshot_without_candidate(self):
        self.seed();reader=self.reader()
        analysis=TeacherAnalysis(self.db,self.c,reader,self.now-3600)
        first=analysis.update(self.now,True,'')
        reader.quote=Mock(side_effect=QuoteError('报价时间异常'))
        second=analysis.update(self.now+10,True,'')
        self.assertEqual(second['quote'],first['quote'])
        self.assertEqual(second['bars'],first['bars'])
        self.assertFalse(second['market_ok']);self.assertTrue(second['stale'])
        self.assertIsNone(second['candidate']);self.assertEqual(second['status'],'BLOCKED')

    def test_task_starts_independent_service_and_single_instance(self):
        import xml.etree.ElementTree as ET
        root=ET.fromstring(task_xml(self.home)); ns={'t':'http://schemas.microsoft.com/windows/2004/02/mit/task'}
        self.assertIn('service',root.findtext('.//t:Arguments',namespaces=ns))
        self.assertEqual(root.findtext('.//t:MultipleInstancesPolicy',namespaces=ns),'IgnoreNew')

    def test_reader_revision_change_during_analysis_is_blocked(self):
        self.seed()
        reader=self.reader()
        def bars(*args):
            ingest(self.db,'oc_test',[self.message('',deleted=True)])
            return self.bars
        reader.bars=bars
        result=TeacherAnalysis(self.db,self.c,reader,self.now-1000).update(self.now,True,'')
        self.assertEqual(result['status'],'BLOCKED')
        self.assertIsNone(result['candidate'])


if __name__=='__main__': unittest.main(verbosity=2)
