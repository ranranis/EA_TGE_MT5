"""合成文字、状态与协议测试；不含API Key，不发网络/券商请求。"""
import copy
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock
from app import config_load, export_teacher_levels
from deepseek_ai import AIError, initialize_ai, validate_output, resolve_token, process_ai_batch, ai_snapshot
from store import connect, ingest, set_state, state


def result(kind='SETUP', side='BUY', token='68', price=4168, evidence='68↑'):
    return dict(id='0',kind=kind,plans=[] if kind!='SETUP' else [
        dict(side=side,token=token,price=price,mode='REACTION',evidence=evidence)],
        cancel_side='NONE',reason='合成解释')


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.targets=[dict(id='0',text='最新68↑ 80↓',market_anchor=4170)]
    def check_value(self,value,targets=None):
        return validate_output({'interpretations':[value]},targets or self.targets,4170)
    def test_tail_and_full_prices(self):
        self.assertEqual(resolve_token('68',4170),4168)
        self.assertEqual(resolve_token('50',4165),4150)
        self.assertEqual(resolve_token('72',4165),4172)
        self.assertEqual(resolve_token('4180',4170),4180)
        with self.assertRaises(AIError):resolve_token('50',4200)
    def test_actual_arrow_plan_shape(self):
        self.assertEqual(self.check_value(result())['0']['plans'][0]['price'],4168)
    def test_near_and_prefix_are_grounded_in_the_literal_qualifier(self):
        p=self.check_value(result(),[dict(id='0',text='接近68↑',market_anchor=4170)])['0']['plans'][0]
        self.assertTrue(p['near'])
        p=self.check_value(result(evidence='68开↑'),[dict(id='0',text='68开↑',market_anchor=4170)])['0']['plans'][0]
        self.assertTrue(p['near'])
        self.assertFalse(self.check_value(result())['0']['plans'][0]['near'])
    def test_direction_and_literal_price_cannot_be_invented(self):
        for field,value in [('side','SELL'),('price',4268),('token','67'),('evidence','在68做多')]:
            r=result();r['plans'][0][field]=value
            with self.assertRaises(AIError):self.check_value(r)
    def test_multiple_directions_need_separate_evidence(self):
        r=result(evidence='68↑ 80↓')
        with self.assertRaises(AIError):self.check_value(r)
    def test_missing_or_duplicate_messages_fail_batch(self):
        for rows in [[],[result(),result()]]:
            with self.assertRaises(AIError):validate_output({'interpretations':rows},self.targets,4170)
    def test_truncated_number_and_extra_order_fields_rejected(self):
        r=result();r['plans'][0]['lots']=2
        with self.assertRaises(AIError):self.check_value(r)
        with self.assertRaises(AIError):self.check_value(result(),[dict(id='0',text='4168↑')])
    def test_market_requires_explicit_current_price_instruction(self):
        r=result();r['plans'][0]['mode']='MARKET'
        with self.assertRaises(AIError):self.check_value(r)
        self.check_value(r,[dict(id='0',text='现价直接买68↑',market_anchor=4170)])
    def test_watch_hold_and_old_receipts_never_become_new_orders(self):
        for text,kind in [('74了观察','WATCH'),('415开头的单多拿拿','HOLD')]:
            self.check_value(result(kind=kind),[dict(id='0',text=text)])
        with self.assertRaises(AIError):self.check_value(result(),[dict(id='0',text='历史晒单68↑')])
    def test_group_map_cannot_issue_direction(self):
        with self.assertRaises(AIError):
            self.check_value(result(),[dict(id='0',text='68↑',source_role='group_map')])
    def test_invalid_types_are_errors_not_worker_crashes(self):
        for field,value in [('id',[]),('kind',[])]: 
            r=result();r[field]=value
            with self.assertRaises(AIError):self.check_value(r)
    def test_indicator_period_is_not_a_price(self):
        with self.assertRaises(AIError):
            self.check_value(result(),[dict(id='0',text='EMA68↑',market_anchor=4170)])
    def test_cancel_needs_a_scope_and_literal_cancel_instruction(self):
        with self.assertRaises(AIError):
            self.check_value(result(kind='CANCEL'),[dict(id='0',text='取消当前点位')])
    def test_map_requires_complete_original_price_list(self):
        with self.assertRaises(AIError):self.check_value(result(kind='MAP'))
        self.check_value(result(kind='MAP'),[dict(id='0',text='4175--4185--4200')])


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.home=Path(self.temp.name)
        self.c=config_load(self.home);self.c.update(chat_id='oc_test',teacher_sender_id='ou_teacher',ai_enabled=True,
            common_files=str(self.home/'common'))
        (self.home/'data').mkdir();self.db=connect(self.home/'data/test.sqlite');initialize_ai(self.db)
        self.now=time.time()
        with self.db:
            set_state(self.db,'live_since',self.now-86400)
            set_state(self.db,'last_sync_ok',True);set_state(self.db,'last_sync_at',self.now);set_state(self.db,'checkpoint',self.now)
            set_state(self.db,'teacher_analysis',{'quote':{'bid':4170,'ask':4170.2,'at':self.now},'bars':[]})
    def tearDown(self):
        self.db.close();self.temp.cleanup()
    def seed(self,mid='om_test',text='最新68↑',age=10,historical=False,sender='ou_teacher',**kw):
        m=dict(message_id=mid,chat_id='oc_test',sender={'id':sender},create_time=self.now-age,
            msg_type='text',content=text,**kw)
        ingest(self.db,'oc_test',[m],historical=historical)
        return m
    def client(self,kind='SETUP'):
        def fake(targets,*_):
            return {'interpretations':[dict(result(kind=kind),id=t['id']) for t in targets]}
        return Mock(interpret=Mock(side_effect=fake))
    def test_success_cache_restart_and_atomic_snapshot(self):
        self.seed();client=self.client();process_ai_batch(self.db,self.c,client,self.now)
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
        process_ai_batch(self.db,self.c,client,self.now+2);self.assertEqual(client.interpret.call_count,1)
        export_teacher_levels(self.db,self.c,False,self.now)
        lines=(self.home/'common/FeishuMT5SignalMonitor/tge_ai_setups.csv').read_text(encoding='utf-8').splitlines()
        self.assertIn('SETUP,BUY,4168.0000000000,REACTION,POINT',lines);self.assertEqual(lines[-1],'END,1')
    def test_api_failure_retries_without_advancing_or_order(self):
        self.seed();client=Mock(interpret=Mock(side_effect=AIError('timeout')))
        process_ai_batch(self.db,self.c,client,self.now)
        self.assertEqual(self.db.execute("SELECT status FROM ai_messages").fetchone()[0],'RETRY')
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
        process_ai_batch(self.db,self.c,client,self.now+2);self.assertEqual(client.interpret.call_count,1)
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)
    def test_source_edit_during_request_does_not_publish_old_result(self):
        m=self.seed()
        def changed(targets,*args):
            ingest(self.db,'oc_test',[dict(m,content='取消',update_time='edit')])
            return {'interpretations':[result()]}
        process_ai_batch(self.db,self.c,Mock(interpret=changed),self.now)
        self.assertIsNone(state(self.db,'deepseek_setup'))
    def test_withdraw_pause_sync_and_worker_failure_block_old_plan(self):
        m=self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,True)['active'])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now+31,False)['active'])
        ingest(self.db,'oc_test',[dict(m,deleted=True)])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_historical_import_is_audit_only(self):
        self.seed(historical=True);process_ai_batch(self.db,self.c,self.client(),self.now)
        self.assertIsNone(state(self.db,'deepseek_setup'))
    def test_observation_does_not_replace_last_valid_direction(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        self.seed(mid='om_watch',text='74了观察',age=0)
        process_ai_batch(self.db,self.c,self.client('WATCH'),self.now)
        self.assertEqual(state(self.db,'deepseek_setup')['plans'][0]['price'],4168)
    def test_unknown_action_is_visible_and_blocks_instead_of_silently_using_old_plan(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        self.seed(mid='om_unknown',text='空单改一下',age=0)
        process_ai_batch(self.db,self.c,self.client('UNKNOWN'),self.now)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
        self.assertTrue(state(self.db,'deepseek_review'))
    def test_other_senders_do_not_get_trading_authority(self):
        self.seed(sender='ou_other');client=self.client('MEMBER_TRADE');process_ai_batch(self.db,self.c,client,self.now)
        client.interpret.assert_called_once();self.assertIsNone(state(self.db,'deepseek_setup'))
    def test_partial_cancel_retains_origin_and_withdrawal_blocks_the_retained_plan(self):
        m=self.seed(text='最新68↑ 80↓')
        a=result();a['plans'].append(dict(side='SELL',token='80',price=4180,mode='REACTION',evidence='80↓'))
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value={'interpretations':[a]})),self.now)
        self.seed(mid='om_cancel',text='取消多方向',age=0)
        cancel=result(kind='CANCEL');cancel['cancel_side']='BUY'
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value={'interpretations':[cancel]})),self.now)
        self.assertEqual(state(self.db,'deepseek_setup')['plans'][0]['side'],'SELL')
        ingest(self.db,'oc_test',[dict(m,deleted=True)])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_stale_retry_keeps_later_watch_from_enabling_an_older_setup(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        self.seed(mid='om_bad',age=1);process_ai_batch(self.db,self.c,Mock(interpret=Mock(side_effect=AIError('error'))),self.now)
        self.seed(mid='om_watch',text='74了观察',age=0)
        process_ai_batch(self.db,self.c,self.client('WATCH'),self.now+1)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now+1,False)['active'])


if __name__=='__main__':unittest.main()
