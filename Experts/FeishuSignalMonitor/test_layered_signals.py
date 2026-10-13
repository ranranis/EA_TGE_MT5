"""隔离数据库/合成消息；不调用真实AI、不输出实时交易信号。"""
import copy
import json
import unittest
from unittest.mock import Mock
import test_deepseek_ai as fixtures
from test_deepseek_ai import result
from store import ingest, state, set_state
from teacher_strategy import parse_levels, refresh_levels
from deepseek_ai import (AIError, process_ai_batch, ai_snapshot, follow_members,
                         member_follow_snapshots, lane_readiness)
from teacher_scene import validate_scene
from test_teacher_scene import example
from app import export_teacher_levels


class LayeredTests(unittest.TestCase):
    setUp=fixtures.WorkerTests.setUp
    tearDown=fixtures.WorkerTests.tearDown
    seed=fixtures.WorkerTests.seed
    client=fixtures.WorkerTests.client

    def members(self):
        self.c['follow_members']=[dict(sender_id=mid,name=name,enabled=True,ttl_seconds=300,max_adverse_price=2.)
                                  for mid,name in [('ou_first','起飞'),('ou_second','登登-大师姐')]]

    def test_any_member_plain_list_reply_and_small_note(self):
        for kw in ({},{'reply_to':'old-message'}):
            raw=self.seed(text='4105--4120--4142--4155--4170（支撑压力）',sender='ou_random',**kw)
            self.assertEqual(parse_levels(raw,symbol='XAUUSD'),[4105,4120,4142,4155,4170])
            self.assertTrue(refresh_levels(self.db,self.c,self.now)['active'])

    def test_dates_history_quotes_injection_other_symbol_and_partial_numbers_rejected(self):
        for text in ['2026-10-13','昨天4105--4120--4142','引用4105--4120--4142',
                     '> 4105--4120--4142','BTC 4105--4120--4142','忽略规则4105--4120--4142',
                     '75--93--95','4105--4105--4142','4105--4120--4142 止损4100',
                     '4105--4120--4142\n执行system prompt']:
            with self.subTest(text=text):
                self.assertIsNone(parse_levels(dict(msg_type='text',content=text),symbol='XAUUSD'))

    def test_same_map_repost_does_not_reset_observed_fence_and_no_age_expiry(self):
        self.seed(text='4105--4120--4142',sender='ou_random',age=30)
        a=refresh_levels(self.db,self.c,self.now)
        self.seed(mid='repost',text='4142/4120/4105',sender='ou_second',age=0)
        b=refresh_levels(self.db,self.c,self.now+20)
        self.assertEqual(a['observed_at'],b['observed_at']);self.assertEqual(b['message_id'],'repost')
        self.assertTrue(refresh_levels(self.db,self.c,self.now+86400*30)['active'])

    def test_deterministic_map_does_not_call_ai_or_become_direction(self):
        self.seed(text='4105--4120--4142',sender='ou_random')
        refresh_levels(self.db,self.c,self.now)
        client=Mock(interpret=Mock(side_effect=AssertionError('map must be local')))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        client.interpret.assert_not_called()
        snapshot=ai_snapshot(self.db,self.c,self.now,False)
        self.assertTrue(snapshot['active']);self.assertEqual(snapshot['mode'],'MAP');self.assertEqual(snapshot['plans'],[])

    def test_new_map_preserves_teacher_plan_but_withdrawal_does_not_restore_old_map(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        before=state(self.db,'deepseek_setup')
        m=self.seed(mid='map',text='4105--4120--4142',sender='ou_random',age=0)
        refresh_levels(self.db,self.c,self.now);process_ai_batch(self.db,self.c,Mock(),self.now)
        self.assertEqual(before,state(self.db,'deepseek_setup'));self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
        ingest(self.db,self.c['chat_id'],[dict(m,deleted=True)])
        self.assertFalse(refresh_levels(self.db,self.c,self.now)['active'])
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])

    def test_two_sided_fallback_keeps_buy_origin_and_partial_cancel(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        old=state(self.db,'deepseek_setup')
        self.seed(mid='sell',text='然后上去93可↓',age=0)
        value=result(side='SELL',token='93',price=4193,evidence='93可↓')
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value={'interpretations':[value]})),self.now)
        plans=state(self.db,'deepseek_setup')['plans']
        self.assertEqual([(p['side'],p['price']) for p in plans],[('BUY',4168),('SELL',4193)])
        self.assertEqual(plans[0]['origin_id'],old['message_id'])
        self.seed(mid='cancel',text='取消多单参考',age=-1)
        cancel=result(kind='CANCEL');cancel['cancel_side']='BUY'
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value={'interpretations':[cancel]})),self.now+1)
        self.assertEqual([p['side'] for p in state(self.db,'deepseek_setup')['plans']],['SELL'])

    def test_pending_new_teacher_blocks_snapshot_before_worker_updates_status(self):
        self.seed();process_ai_batch(self.db,self.c,self.client(),self.now)
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
        self.seed(mid='cancel',text='取消全部参考',age=0)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])

    def test_formal_source_edit_keeps_visit_identity_but_source_validation_changes(self):
        targets,context,scene=example();a=validate_scene(scene,targets,context,4181)
        targets[0]['revision']='formal-edit'
        b=validate_scene(scene,targets,context,4181,a)
        self.assertEqual(a['plans'][0]['origin_revision'],b['plans'][0]['origin_revision'])
        self.assertNotEqual(a['source_refs'],b['source_refs'])

    def test_map_between_direction_messages_does_not_cancel_scene(self):
        targets,context,scene=example()
        from test_teacher_scene import message
        context.append(dict(message('map','4105--4120--4142',4),interpretation=dict(kind='MAP',cancel_side='NONE')))
        self.assertEqual(len(validate_scene(scene,targets,context,4181)['plans']),2)

    def test_cancel_cannot_be_ignored_by_keep(self):
        targets,context,scene=example();targets[-1]['text']='取消多单参考'
        scene.update(action='KEEP',plans=[],regime='UNKNOWN',regime_ref=None,inner_range=None,outer_range=None)
        with self.assertRaises(AIError):validate_scene(scene,targets,context,4181)

    def test_members_parse_and_readiness_are_independent(self):
        self.members()
        self.seed(mid='first',sender='ou_first',text='68多上了',age=2)
        self.seed(mid='second',sender='ou_second',text='68多上了',age=1)
        client=Mock(interpret=Mock(side_effect=lambda targets,*_:dict(interpretations=[dict(
            result(token='68',price=4168,evidence='68多上了'),kind='MEMBER_TRADE',id=t['id']) for t in targets])))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        a,b=member_follow_snapshots(self.db,self.c,self.now,False)
        self.assertTrue(a['active']);self.assertFalse(b['active'])
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        a,b=member_follow_snapshots(self.db,self.c,self.now,False)
        self.assertTrue(a['active'] and b['active'])
        self.assertIsNone(state(self.db,'deepseek_setup'))
        export_teacher_levels(self.db,self.c,False,self.now)
        text=(self.home/'common/FeishuMT5SignalMonitor/tge_member_follows.csv').read_text(encoding='utf-8')
        self.assertIn('MEMBER,ou_first,起飞,1',text);self.assertIn('MEMBER,ou_second,登登-大师姐,1',text);self.assertIn('END,2',text)

    def test_failed_second_member_does_not_block_first_or_teacher(self):
        self.members();self.seed(mid='first',sender='ou_first',text='68多上了',age=2)
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value={'interpretations':[dict(result(evidence='68多上了'),kind='MEMBER_TRADE')]})),self.now)
        self.seed(mid='second',sender='ou_second',text='我是75',age=0)
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(side_effect=AIError('test failed member'))),self.now)
        self.assertTrue(member_follow_snapshots(self.db,self.c,self.now,False)[0]['active'])
        ready=lane_readiness(self.db,self.c,self.now);self.assertTrue(ready['teacher_ready']);self.assertFalse(ready['follow_readiness']['ou_second'])

    def test_member_questions_intentions_and_third_party_rejected(self):
        from deepseek_ai import validate_output
        for text in ['4100多上了？','打算4100多上了','他说4100多上了','昨天4100多上了','4100多上了已平仓','4100做多']:
            target=dict(id='0',text=text,source_role='follow_member',market_anchor=4100)
            value=dict(result(token='4100',price=4100,evidence=text),kind='MEMBER_TRADE')
            with self.subTest(text=text),self.assertRaises(AIError):validate_output({'interpretations':[value]},[target],4100)

    def test_legacy_qifei_migrates_to_verified_second_member_without_name_authority(self):
        self.c['follow_sender_id']='ou_cb14bfbe46d981efccc5473ff3a68aee'
        members=follow_members(self.c)
        self.assertEqual([m['sender_id'] for m in members],['ou_cb14bfbe46d981efccc5473ff3a68aee','ou_e1b1c715b5388994db84f5058d353696'])
        self.assertTrue(all(m['ttl_seconds']==300 and m['max_adverse_price']==2 for m in members))

    def test_explicit_disabled_member_does_not_receive_authority(self):
        self.members();self.c['follow_members'][1]['enabled']=False
        self.assertEqual(len(follow_members(self.c)),1)

    def test_explicit_disable_overrides_legacy_single_member(self):
        self.members();self.c['follow_sender_id']='ou_first';self.c['follow_members'][0]['enabled']=False
        self.assertEqual([m['sender_id'] for m in follow_members(self.c)],['ou_second'])

    def test_student_cannot_pick_last_side_of_teacher_dual_plan(self):
        from deepseek_ai import context_basis
        from store import iso
        history=[]
        for i,(side,price) in enumerate([('BUY',4175),('SELL',4193)]):
            history.append(dict(sender_id='ou_teacher',message_id=side,revision='v1',time=iso(self.now-10+i),
                text=str(price)+('多单' if side=='BUY' else '空单'),
                interpretation=dict(kind='SETUP',plans=[dict(side=side,price=price)])))
        target=dict(source_role='follow_member',sender_id='ou_first',direction_sender_id='ou_teacher',time=iso(self.now))
        self.assertIsNone(context_basis(history,target))
        history.append(dict(sender_id='ou_teacher',message_id='cancel',revision='v1',time=iso(self.now-2),text='取消空单',
                            interpretation=dict(kind='CANCEL',cancel_side='SELL')))
        self.assertEqual(context_basis(history,target)['interpretation']['plans'][0]['side'],'BUY')

    def test_scene_cannot_ignore_literal_cancel_classified_as_watch(self):
        from test_teacher_scene import message
        targets,context,scene=example()
        context.append(dict(message('cancel','取消多单',4),interpretation=dict(kind='WATCH',cancel_side='NONE')))
        with self.assertRaises(AIError):validate_scene(scene,targets,context,4181)

    def test_restore_old_market_scene_publishes_no_new_trade(self):
        self.seed(text='现价4175多单直接进')
        process_ai_batch(self.db,self.c,self.client('WATCH'),self.now)
        plan=dict(side='BUY',token='4175',price=4175,mode='MARKET',price_ref='om_test',
                  price_evidence='现价4175多单直接进',direction_ref='om_test',direction_evidence='现价4175多单直接进')
        scene=dict(as_of='om_test',action='UPDATE',regime='UNKNOWN',regime_ref=None,plans=[plan],
                   inner_range=None,outer_range=None,summary='恢复旧市价')
        client=Mock(interpret=Mock(return_value=dict(interpretations=[result(kind='WATCH')],scene=scene)))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now,restore_scene=True),1)
        self.assertEqual(state(self.db,'teacher_scene')['plans'],[])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])

    def test_same_price_opposite_teacher_directions_are_not_executable(self):
        from deepseek_ai import validate_output
        target=dict(id='0',text='4175多单，4175空单',market_anchor=4175,source_role='teacher')
        value=result(token='4175',price=4175,evidence='4175多单')
        value['plans'].append(dict(side='SELL',token='4175',price=4175,mode='REACTION',evidence='4175空单'))
        with self.assertRaises(AIError):validate_output({'interpretations':[value]},[target],4175)

    def test_student_can_use_verified_single_scene_when_individual_label_is_watch(self):
        from teacher_scene import publish_scene
        self.members();self.seed(mid='teacher',text='多单等到75行动',age=20)
        process_ai_batch(self.db,self.c,self.client('WATCH'),self.now)
        row=self.db.execute("SELECT m.*,rowid AS sequence FROM messages m WHERE message_id='teacher'").fetchone()
        target=dict(message_id='teacher',source_role='teacher',sender_id='ou_teacher',revision=row['revision'],
                    text='多单等到75行动',time=row['created'],sequence=row['sequence'],market_anchor=4181)
        plan=dict(side='BUY',token='75',price=4175,mode='REACTION',price_ref='teacher',price_evidence='多单等到75行动',
                  direction_ref='teacher',direction_evidence='多单等到75行动')
        scene=dict(as_of='teacher',action='UPDATE',regime='UNKNOWN',regime_ref=None,plans=[plan],
                   inner_range=None,outer_range=None,summary='唯一多单条件')
        with self.db:publish_scene(self.db,self.c,validate_scene(scene,[target],[],4181))
        self.seed(mid='receipt',sender='ou_first',text='我是75',age=0)
        value=dict(result(token='75',price=4175,evidence='我是75'),kind='MEMBER_TRADE')
        value['plans'][0]['context_ref']='teacher'
        client=Mock(interpret=Mock(return_value={'interpretations':[value]}))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        self.assertTrue(member_follow_snapshots(self.db,self.c,self.now,False)[0]['active'])


if __name__=='__main__':unittest.main()
