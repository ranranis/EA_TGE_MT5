"""合成文字、状态与协议测试；不含API Key，不发网络/券商请求。"""
import copy
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock
from app import config_load, export_teacher_levels
from deepseek_ai import AIError, initialize_ai, validate_output, resolve_token, process_ai_batch, ai_snapshot, member_follow_snapshot
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

    def test_local_price_completion_accepts_null_but_not_fabricated_price(self):
        for price in (None,'4168'):
            self.assertEqual(self.check_value(result(price=price))['0']['plans'][0]['price'],4168)
        for price in (True,'oops',4268):
            with self.assertRaises(AIError):self.check_value(result(price=price))

    def test_recap_cannot_be_entry_even_with_a_literal_arrow(self):
        with self.assertRaisesRegex(AIError,'复盘'):
            self.check_value(result(evidence='68↑'),[dict(id='0',text='方才68↑涨了一段',market_anchor=4170)])


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.origin=dict(message_id='om_direction',revision='r1',sender_id='teacher',source_role='teacher',
                         time='2026-10-13T14:00:00+08:00',text='现在90可⬆️',historical=False,
                         interpretation=result(token='90',price=4190,evidence='90可⬆️'))
        self.target=dict(id='0',message_id='om_reminder',revision='r2',sender_id='teacher',source_role='teacher',
                         time='2026-10-13T14:25:00+08:00',text='86了 注意。。',market_anchor=4186)
    def value(self):
        value=result(token='86',price=4186,evidence='86了 注意。。')
        value['plans'][0]['context_ref']='om_direction'
        return value
    def validate(self, history=None, value=None):
        return validate_output({'interpretations':[value or self.value()]},
                               [self.target],4186,[self.origin] if history is None else history)['0']
    def test_reference_update_inherits_only_direction_and_keeps_new_price_evidence(self):
        value=self.validate()
        self.assertEqual(value['plans'][0]['price'],4186)
        self.assertEqual(value['plans'][0]['mode'],'REACTION')
        self.assertEqual(value['source_refs'],[dict(message_id='om_direction',revision='r1')])
        self.assertIn('上下文承接',value['reason'])
        self.assertFalse(value['plans'][0]['near'])
    def test_no_basis_other_sender_future_historical_or_two_sided_basis_rejected(self):
        variants=[[],[dict(self.origin,sender_id='other')],[dict(self.origin,time='2026-10-13T14:26:00+08:00')],
                  [dict(self.origin,historical=True)]]
        two=copy.deepcopy(self.origin);two['interpretation']['plans'].append(
            dict(side='SELL',token='4200',price=4200,mode='REACTION',evidence='4200空'))
        variants.append([two])
        for history in variants:
            with self.subTest(history=history),self.assertRaises(AIError):self.validate(history)
    def test_cancel_and_ambiguous_instruction_break_context(self):
        for kind,text in [('CANCEL','取消前面计划'),('UNKNOWN','现在换方向'),
                          ('WATCH','先别做多'),('MODIFY','保护调一下'),('CLOSE','平仓')]:
            barrier=dict(self.origin,message_id='om_barrier',time='2026-10-13T14:10:00+08:00',
                         text=text,interpretation=result(kind=kind))
            with self.subTest(kind=kind),self.assertRaises(AIError):self.validate([self.origin,barrier])
    def test_pressure_watch_does_not_invent_sell_or_erase_prior_buy(self):
        watch=dict(self.origin,message_id='om_pressure',text='4200压力继续有效',interpretation=result(kind='WATCH'))
        self.assertEqual(self.validate([self.origin,watch])['plans'][0]['side'],'BUY')
        wrong=self.value();wrong['plans'][0]['side']='SELL'
        with self.assertRaises(AIError):self.validate(value=wrong)
    def test_context_cannot_upgrade_to_market_or_use_member_receipt(self):
        for key,val in [('mode','MARKET'),('context_ref','invented'),('price',4286)]:
            value=self.value();value['plans'][0][key]=val
            with self.subTest(key=key),self.assertRaises(AIError):self.validate(value=value)
        self.target['source_role']='member'
        with self.assertRaises(AIError):self.validate()
    def test_exit_negation_and_receipts_cannot_be_context_entry(self):
        for text in ['86了 不要进场','止损改到86注意','86上了注意','昨天86了注意','如果86了注意','86压力注意']:
            self.target['text']=text;v=self.value();v['plans'][0]['evidence']=text
            with self.subTest(text=text),self.assertRaises(AIError):self.validate(value=v)
    def test_same_batch_uses_earlier_target_even_when_model_output_order_is_reversed(self):
        first=dict(self.origin,id='0',market_anchor=4190);first.pop('interpretation')
        second=dict(self.target,id='1')
        explicit=result(token='90',price=4190,evidence='90可⬆️')
        reminder=dict(self.value(),id='1')
        values=validate_output({'interpretations':[reminder,explicit]},[first,second],4190)
        self.assertEqual(values['1']['source_refs'][0]['message_id'],'om_direction')
    def test_member_after_target_cannot_supply_missing_direction(self):
        with self.assertRaises(AIError):self.validate([])

    def test_direction_fragment_can_join_later_price_across_batches(self):
        self.origin.update(text='↑。。',interpretation=result(kind='WATCH'))
        self.target.update(time='2026-10-13T14:01:00+08:00',text='注意，86了，可以加')
        value=self.value();value['plans'][0]['evidence']=self.target['text']
        self.assertEqual(self.validate(value=value)['plans'][0]['side'],'BUY')
        self.target['time']='2026-10-13T14:30:00+08:00'
        with self.assertRaises(AIError):self.validate(value=self.value())


    def test_follow_context_is_not_market_and_unapproved_member_has_no_plans(self):
        self.target.update(source_role='follow_member',sender_id='follower',direction_sender_id='teacher',text='我是86')
        value=self.value();value['kind']='MEMBER_TRADE';value['plans'][0]['evidence']='我是86'
        self.assertEqual(self.validate(value=value)['plans'][0]['side'],'BUY')
        value=self.value();value['kind']='MEMBER_TRADE';value['plans'][0]['evidence']='我是86';value['plans'][0]['mode']='MARKET'
        with self.assertRaises(AIError):self.validate(value=value)
        self.target['source_role']='member'
        with self.assertRaises(AIError):self.validate(value=value)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.home=Path(self.temp.name)
        self.c=config_load(self.home);self.c['teacher_only']=False;self.c.update(chat_id='oc_test',teacher_sender_id='ou_teacher',ai_enabled=True,
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
        self.assertIn('SETUP,BUY,4168.0000000000,REACTION,POINT,om_test,'+state(self.db,'deepseek_setup')['revision']+','+str(int(state(self.db,'deepseek_setup')['created']))+',0.0000000000,0.0000000000,0.0000000000,0.0000000000',lines);self.assertEqual(lines[-1],'END,1')
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
        self.assertTrue(ai_snapshot(self.db,self.c,self.now+31,False)['active'])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now+self.c['sync_max_age_seconds']+1,False)['active'])
        ingest(self.db,'oc_test',[dict(m,deleted=True)])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_persistent_plan_still_blocks_unread_cancel_and_explicit_worker_failure(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        self.seed(mid='cancel',text='取消全部参考',age=0)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now+31,False)['active'])
        with self.db:set_state(self.db,'deepseek_status',dict(online=False,backlog=1,at=self.now))
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

    def contextual_client(self):
        def fake(targets,context,*_):
            outputs=[]
            for t in targets:
                if t['text']=='现在90可⬆️':
                    value=result(token='90',price=4190,evidence='90可⬆️')
                else:
                    value=result(token='86',price=4186,evidence='86了 注意。。')
                    value['plans'][0]['context_ref']='om_direction'
                outputs.append(dict(value,id=t['id']))
            return {'interpretations':outputs}
        return Mock(interpret=Mock(side_effect=fake))
    def seed_context(self):
        origin=self.seed(mid='om_direction',text='现在90可⬆️',age=30)
        self.seed(mid='om_reminder',text='86了 注意。。',age=10)
        return origin
    def test_context_chain_publishes_reference_and_all_versions_then_withdrawal_disables(self):
        origin=self.seed_context();client=self.contextual_client()
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),2)
        setup=state(self.db,'deepseek_setup')
        self.assertEqual(setup['plans'][0]['price'],4186)
        self.assertEqual({r['message_id'] for r in setup['source_refs']},{'om_direction','om_reminder'})
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)
        ingest(self.db,'oc_test',[dict(origin,deleted=True)])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_cached_context_has_ids_and_versions_and_edit_during_request_does_not_publish(self):
        origin=self.seed(mid='om_direction',text='现在90可⬆️',age=30)
        process_ai_batch(self.db,self.c,self.contextual_client(),self.now)
        self.seed(mid='om_reminder',text='86了 注意。。',age=0)
        good=self.contextual_client()
        def changed(targets,context,*rest):
            self.assertEqual(context[-1]['message_id'],'om_direction')
            self.assertTrue(context[-1]['revision'])
            response=good.interpret(targets,context,*rest)
            ingest(self.db,'oc_test',[dict(origin,content='取消多单参考',update_time='changed')])
            return response
        process_ai_batch(self.db,self.c,Mock(interpret=changed),self.now)
        self.assertEqual(state(self.db,'deepseek_setup')['message_id'],'om_direction')
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
        self.assertIsNone(self.db.execute("SELECT 1 FROM ai_messages WHERE message_id='om_reminder'").fetchone())
    def test_same_timestamp_uses_receipt_order_not_lexical_message_id(self):
        self.seed(mid='om_direction',text='现在90可⬆️',age=10)
        self.seed(mid='om_aaa',text='86了 注意。。',age=10)
        process_ai_batch(self.db,self.c,self.contextual_client(),self.now)
        self.assertEqual(state(self.db,'deepseek_setup')['message_id'],'om_aaa')
        self.assertEqual(state(self.db,'deepseek_setup')['plans'][0]['price'],4186)
    def test_retry_batch_cannot_skip_cached_cancel_between_targets(self):
        self.seed(mid='om_direction',text='现在90可⬆️',age=30)
        process_ai_batch(self.db,self.c,self.contextual_client(),self.now)
        self.seed(mid='om_cancel',text='取消前面的参考',age=20)
        cancel=result(kind='CANCEL');cancel['cancel_side']='ALL'
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value={'interpretations':[cancel]})),self.now)
        self.db.execute("UPDATE ai_messages SET status='RETRY',retry_at=0 WHERE message_id='om_direction'")
        self.db.commit()
        self.seed(mid='om_reminder',text='86了 注意。。',age=10)
        client=self.contextual_client()
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),0)
        self.assertEqual(state(self.db,'deepseek_setup')['mode'],'WAIT')
        self.assertIn('om_cancel',[m['message_id'] for m in client.interpret.call_args.args[1]])
    def test_uncertain_numeric_reminder_is_visible_for_review(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        self.seed(mid='om_unknown',text='86了 注意。。',age=0)
        process_ai_batch(self.db,self.c,self.client('UNKNOWN'),self.now)
        self.assertTrue(state(self.db,'deepseek_review'))
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])

    def follow_client(self,kind='MEMBER_TRADE',plans=True):
        def fake(targets,*_):
            self.assertEqual(targets[0]['source_role'],'follow_member')
            value=result(kind='SETUP',token='68',price=4168,evidence='68多上了')
            value['kind']=kind
            if not plans:value['plans']=[]
            return {'interpretations':[dict(value,id=t['id']) for t in targets]}
        return Mock(interpret=Mock(side_effect=fake))
    def configure_follow(self):
        self.c['follow_sender_id']='ou_follower'
    def test_follow_source_is_separate_and_teacher_reference_survives(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        original=state(self.db,'deepseek_setup')
        self.configure_follow();self.seed(mid='om_member',sender='ou_follower',text='68多上了',age=1)
        process_ai_batch(self.db,self.c,self.follow_client(),self.now)
        self.assertEqual(state(self.db,'deepseek_setup'),original)
        follow=member_follow_snapshot(self.db,self.c,self.now,False)
        self.assertTrue(follow['active']);self.assertEqual(follow['plans'][0]['price'],4168)
        export_teacher_levels(self.db,self.c,False,self.now)
        lines=(self.home/'common/FeishuMT5SignalMonitor/tge_member_follow.csv').read_text(encoding='utf-8').splitlines()
        self.assertEqual(lines[-2],'FOLLOW,BUY,4168.0000000000');self.assertEqual(lines[-1],'END,1')
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)
    def test_follow_remains_active_beyond_five_minutes_with_fresh_heartbeats(self):
        self.configure_follow();self.seed(sender='ou_follower',text='68多上了',age=1)
        process_ai_batch(self.db,self.c,self.follow_client(),self.now)
        for age,active in [(298.9,True),(299,True),(300,True),(86400,True)]:
            later=self.now+age
            with self.db:
                set_state(self.db,'last_sync_at',later);set_state(self.db,'checkpoint',later)
                status=state(self.db,'deepseek_status');status['at']=later;set_state(self.db,'deepseek_status',status)
            self.assertEqual(member_follow_snapshot(self.db,self.c,later,False)['active'],active)
    def test_historical_follow_and_other_members_never_gain_follow_authority(self):
        self.configure_follow();self.seed(sender='ou_follower',text='68多上了',historical=True)
        process_ai_batch(self.db,self.c,self.follow_client(),self.now)
        self.assertFalse(member_follow_snapshot(self.db,self.c,self.now,False)['active'])
        self.seed(mid='om_other',sender='ou_random',text='68多上了',age=0)
        process_ai_batch(self.db,self.c,self.client('MEMBER_TRADE'),self.now)
        self.assertFalse(member_follow_snapshot(self.db,self.c,self.now,False)['active'])
    def test_follow_receipt_can_use_teacher_direction_without_modifying_it(self):
        self.seed(mid='om_direction',text='现在90可⬆️',age=20)
        process_ai_batch(self.db,self.c,self.contextual_client(),self.now)
        self.configure_follow();m=self.seed(mid='om_member',sender='ou_follower',text='我是85',age=0)
        value=result(token='85',price=4185,evidence='我是85');value['kind']='MEMBER_TRADE'
        value['plans'][0]['context_ref']='om_direction'
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value={'interpretations':[value]})),self.now)
        self.assertEqual(state(self.db,'deepseek_setup')['message_id'],'om_direction')
        self.assertTrue(member_follow_snapshot(self.db,self.c,self.now,False)['active'])
        origin=self.db.execute("SELECT raw FROM messages WHERE message_id='om_direction'").fetchone()
        raw=json.loads(origin['raw']);ingest(self.db,'oc_test',[dict(raw,deleted=True)])
        self.assertFalse(member_follow_snapshot(self.db,self.c,self.now,False)['active'])
    def test_follow_withdrawal_and_cancel_do_not_fall_back_to_an_older_receipt(self):
        self.configure_follow();self.seed(mid='old',sender='ou_follower',text='68多上了',age=30)
        process_ai_batch(self.db,self.c,self.follow_client(),self.now)
        m=self.seed(mid='new',sender='ou_follower',text='68多上了',age=10)
        process_ai_batch(self.db,self.c,self.follow_client(),self.now)
        ingest(self.db,'oc_test',[dict(m,deleted=True)])
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(side_effect=AssertionError('deleted message must be local'))),self.now)
        self.assertFalse(member_follow_snapshot(self.db,self.c,self.now,False)['active'])
        self.assertEqual(member_follow_snapshot(self.db,self.c,self.now,False)['message_id'],'new')
    def test_follow_unknown_new_receipt_blocks_old_reference_and_sync_loss_blocks_follow(self):
        self.configure_follow();self.seed(mid='old',sender='ou_follower',text='68多上了',age=30)
        process_ai_batch(self.db,self.c,self.follow_client(),self.now)
        self.assertFalse(member_follow_snapshot(self.db,self.c,self.now,True)['active'])
        with self.db:set_state(self.db,'last_sync_ok',False)
        self.assertFalse(member_follow_snapshot(self.db,self.c,self.now,False)['active'])
        with self.db:set_state(self.db,'last_sync_ok',True)
        self.seed(mid='new',sender='ou_follower',text='我是85',age=0)
        process_ai_batch(self.db,self.c,self.follow_client(plans=False),self.now)
        self.assertFalse(member_follow_snapshot(self.db,self.c,self.now,False)['active'])


if __name__=='__main__':unittest.main()
