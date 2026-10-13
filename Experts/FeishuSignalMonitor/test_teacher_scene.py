"""场景语义桥回归；全部使用隔离合成消息，不写真实EA信号。"""
import copy
import json
import unittest
from unittest.mock import Mock
from deepseek_ai import AIError, DeepSeek, process_ai_batch, ai_snapshot
from teacher_scene import validate_scene, publish_scene
from store import state, set_state, ingest
from test_deepseek_ai import WorkerTests as DatabaseFixture, result


def message(mid,text,n,role='teacher',historical=False):
    return dict(id=str(n),message_id=mid,revision='rev-'+mid,sender_id='teacher' if role=='teacher' else 'member',
                sequence=n,time=f'2026-10-13T17:{30+n:02d}:00+08:00',market_anchor=4181,
                source_role=role,historical=historical,text=text)


def plan(side,token,price,mid,evidence):
    return dict(side=side,token=token,price=price,mode='REACTION',
                price_ref=mid,price_evidence=evidence,direction_ref=mid,direction_evidence=evidence)


def example():
    targets=[message('buy','15分钟连绿。。现在81了多单等到75行动。。。',2),
             message('sell','然后。。上去93可↓',3),
             message('small','今日，小区间参考，4175-4200',4),
             message('large','大区间参考4150--4220',5)]
    context=[message('rhythm','这种行情在可控区间来回跑',1)]
    def proof(mid,token):
        return dict(message_id=mid,token=token,price=int(token),evidence=next(t['text'] for t in targets if t['message_id']==mid))
    scene=dict(as_of='large',action='UPDATE',regime='RANGE',
               regime_ref=dict(message_id='rhythm',evidence=context[0]['text']),
               plans=[plan('BUY','75',4175,'buy','多单等到75行动'),plan('SELL','93',4193,'sell','上去93可↓')],
               inner_range=dict(low=proof('small','4175'),high=proof('small','4200')),
               outer_range=dict(low=proof('large','4150'),high=proof('large','4220')),summary='区间内等待4175多、4193空的收线反应')
    return targets,context,scene


class ReferenceTransportTests(unittest.TestCase):
    def client(self, respond):
        client=DeepSeek('.',{'ai_model':'deepseek-flash'})
        def request(endpoint,payload):
            body=json.loads(payload['messages'][1]['content'])
            return {'choices':[{'finish_reason':'stop','message':{'content':json.dumps(respond(body),ensure_ascii=False)}}]}
        client.request=Mock(side_effect=request)
        return client

    def test_all_scene_references_round_trip_and_inputs_stay_unchanged(self):
        targets,context,scene=example()
        previous=validate_scene(scene,targets,context,4181)
        before=copy.deepcopy((targets,context,previous))
        def respond(body):
            self.assertEqual([m['message_id'] for m in body['context']+body['targets']],['r001','r002','r003','r004','r005'])
            self.assertEqual(body['targets'][0]['id'],'2')
            old=body['previous_scene']
            self.assertEqual(old['as_of'],'r005')
            self.assertEqual(old['plans'][0]['price_ref'],'r002')
            self.assertEqual(old['plans'][0]['origin_id'],'r002')
            self.assertEqual(old['regime_ref']['message_id'],'r001')
            self.assertEqual(old['inner_range']['low']['message_id'],'r004')
            # 回包只保留外部场景字段，内部来源元数据不能越过既有校验。
            value={key:old[key] for key in scene}
            value['plans']=[{key:p[key] for key in scene['plans'][0]} for p in old['plans']]
            return dict(interpretations=[],scene=value)
        output=self.client(respond).interpret(targets,context,4181,[],previous)
        self.assertEqual(output['scene'],scene)
        self.assertEqual((targets,context,previous),before)
        self.assertEqual(len(validate_scene(output['scene'],targets,context,4181)['plans']),2)

    def test_unknown_reference_is_rejected_without_fuzzy_matching(self):
        targets,context,scene=example()
        for wrong in ('r999','buy','om_x100b63ebe38f70a4c32078cea8cb53f'):
            with self.subTest(wrong=wrong),self.assertRaisesRegex(AIError,'未知消息编号'):
                self.client(lambda body:dict(interpretations=[],scene=dict(as_of=wrong))).interpret(targets,context,4181,[])

    def test_follow_context_ref_round_trip_and_unrequested_scene_is_ignored(self):
        context=[message('original-direction','4175做多',1)]
        targets=[message('member-receipt','我是75',2,role='follow_member')]
        def respond(body):
            return dict(interpretations=[dict(id='2',plans=[dict(context_ref='r001')])],scene=dict(as_of='invented'))
        output=self.client(respond).interpret(targets,context,4181,[])
        self.assertEqual(output,dict(interpretations=[dict(id='2',plans=[dict(context_ref='original-direction')])]))

    def test_known_member_alias_does_not_gain_teacher_authority(self):
        targets,context,scene=example()
        context.append(message('outsider','小区间4175-4200',0,role='member'))
        def respond(body):
            aliases={old['message_id']:new['message_id'] for old,new in zip(context+targets,body['context']+body['targets'])}
            value=copy.deepcopy(scene)
            value['as_of']=aliases['large']
            for p in value['plans']:
                p['price_ref']=aliases[p['price_ref']];p['direction_ref']=aliases[p['direction_ref']]
            value['regime_ref']['message_id']=aliases['rhythm']
            for band in ('inner_range','outer_range'):
                for proof in value[band].values():proof['message_id']=aliases[proof['message_id']]
            value['inner_range']['low']['message_id']=aliases['outsider']
            return dict(interpretations=[],scene=value)
        output=self.client(respond).interpret(targets,context,4181,[])
        with self.assertRaisesRegex(AIError,'有效老师原文'):
            validate_scene(output['scene'],targets,context,4181)


class SceneTests(unittest.TestCase):
    def test_full_conversation_has_both_directions_and_ranges(self):
        targets,context,scene=example();clean=validate_scene(scene,targets,context,4181)
        self.assertEqual([(p['side'],p['price']) for p in clean['plans']],[('BUY',4175),('SELL',4193)])
        self.assertEqual(clean['inner_range']['high']['price'],4200)
        self.assertEqual({r['message_id'] for r in clean['source_refs']},{'buy','sell','small','large','rhythm'})
    def test_provenance_stays_stable_for_retained_plan_when_range_message_changes(self):
        targets,context,scene=example();a=validate_scene(scene,targets,context,4181)
        targets[-1]['revision']='new-range-version';b=validate_scene(scene,targets,context,4181)
        self.assertEqual(a['plans'][0]['origin_revision'],b['plans'][0]['origin_revision'])
        targets[0]['revision']='new-direction-version';c=validate_scene(scene,targets,context,4181)
        self.assertEqual(a['plans'][0]['origin_revision'],c['plans'][0]['origin_revision'])
        self.assertNotEqual(a['source_refs'],c['source_refs'])
    def test_fabricated_price_direction_future_member_and_historical_sources_fail(self):
        for change in ['price','direction','future','member','historical']:
            targets,context,scene=example()
            if change=='price':scene['plans'][0]['price']=4275
            if change=='direction':scene['plans'][0]['side']='SELL'
            if change=='future':targets[0]['time']='2026-10-13T18:00:00+08:00'
            if change=='member':targets[0]['source_role']='member'
            if change=='historical':targets[0]['historical']=True
            with self.subTest(change=change),self.assertRaises(AIError):validate_scene(scene,targets,context,4181)
    def test_extra_ai_order_fields_unknown_actions_and_reversed_ranges_fail(self):
        for change in ['lots','action','range','duplicate']:
            targets,context,scene=example()
            if change=='lots':scene['plans'][0]['lots']=1
            if change=='action':scene['action']='SEND_ORDER'
            if change=='range':scene['inner_range']['low'],scene['inner_range']['high']=scene['inner_range']['high'],scene['inner_range']['low']
            if change=='duplicate':scene['plans'].append(copy.deepcopy(scene['plans'][0]))
            with self.subTest(change=change),self.assertRaises(AIError):validate_scene(scene,targets,context,4181)
    def test_prior_cancel_and_new_map_cannot_be_ignored(self):
        for kind,side in [('CANCEL','ALL'),('CANCEL','BUY')]:
            targets,context,scene=example()
            context.append(dict(message('stop','取消多单参考',4),interpretation=dict(kind=kind,cancel_side=side)))
            with self.subTest(kind=kind),self.assertRaises(AIError):validate_scene(scene,targets,context,4181)
    def test_keep_and_review_cannot_smuggle_plans_or_ranges(self):
        targets,context,scene=example()
        scene['action']='KEEP'
        with self.assertRaises(AIError):validate_scene(scene,targets,context,4181)
        scene.update(plans=[],regime='UNKNOWN',regime_ref=None,inner_range=None,outer_range=None,action='REVIEW')
        self.assertEqual(validate_scene(scene,targets,context,4181)['action'],'REVIEW')
    def test_old_market_instruction_is_not_replayed_by_new_scene(self):
        targets,context,scene=example();scene['plans'][0]['mode']='MARKET'
        with self.assertRaises(AIError):validate_scene(scene,targets,context,4181)
    def test_price_token_cannot_be_cut_out_of_larger_number_or_indicator_period(self):
        for evidence,token in [('多单等到4175行动','75'),('多单MA 75','75')]:
            targets,context,scene=example()
            targets[0]['text']=evidence
            scene['plans'][0].update(token=token,price_evidence=evidence,direction_evidence=evidence)
            with self.subTest(evidence=evidence),self.assertRaises(AIError):
                validate_scene(scene,targets,context,4181)
    def test_retained_tail_price_keeps_original_magnitude(self):
        targets,context,scene=example();old=validate_scene(scene,targets,context,4181)
        targets[0]['market_anchor']=0;targets[1]['market_anchor']=0
        self.assertEqual(validate_scene(scene,targets,context,4290,old)['plans'][0]['price'],4175)


class SceneWorkerTests(DatabaseFixture):
    # 继承既有隔离数据库夹具；只执行这里定义的场景集成用例。
    def scene_case(self):
        self.seed(mid='buy',text='多单等到75行动',age=30)
        self.seed(mid='sell',text='然后上去93可↓',age=20)
        self.seed(mid='range',text='小区间4175-4200',age=10)
        def response(targets,context,anchor,levels,previous):
            self.assertEqual([t['message_id'] for t in targets],['buy','sell','range'])
            scene=dict(as_of='range',action='UPDATE',regime='UNKNOWN',regime_ref=None,
                       plans=[plan('BUY','75',4175,'buy','多单等到75行动'),plan('SELL','93',4193,'sell','上去93可↓')],
                       inner_range=None,outer_range=None,summary='完整双向计划')
            # 逐条分类故意都是WATCH，完整场景仍必须作为执行参考发布。
            return dict(interpretations=[dict(result(kind='WATCH'),id=t['id']) for t in targets],scene=scene)
        with self.db:set_state(self.db,'teacher_analysis',{'quote':{'bid':4181,'ask':4181.2,'at':self.now},'bars':[]})
        return response
    def test_scene_is_execution_source_even_when_individual_classifications_are_watch(self):
        client=Mock(interpret=self.scene_case())
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),3)
        self.assertEqual(len(state(self.db,'deepseek_setup')['plans']),2)
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
        from app import export_teacher_levels
        export_teacher_levels(self.db,self.c,False,self.now)
        import csv
        with (self.home/'common/FeishuMT5SignalMonitor/tge_ai_setups.csv').open(encoding='utf-8',newline='') as file:
            lines=list(csv.reader(file))
        self.assertEqual(lines[0][:2],['TGA','2'])
        self.assertEqual([lines[1][5],lines[2][5]],['buy','sell'])
        self.assertEqual(len(lines[1]),8)
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)
        self.seed(mid='smalltalk',text='慢慢来',age=0)
        keep=dict(as_of='smalltalk',action='KEEP',regime='UNKNOWN',regime_ref=None,plans=[],inner_range=None,outer_range=None,summary='沿用')
        response=dict(interpretations=[result(kind='DISCUSSION')],scene=keep)
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value=response)),self.now)
        self.assertEqual(len(state(self.db,'deepseek_setup')['plans']),2)
    def test_legacy_classifier_map_failure_does_not_veto_valid_full_scene(self):
        original=self.scene_case()
        def response(*args):
            value=original(*args)
            value['interpretations'][-1]['kind']='MAP'  # 两点区间不符合旧三点列表解析器。
            return value
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=response),self.now),3)
        self.assertEqual(len(state(self.db,'teacher_scene')['plans']),2)
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_invalid_scene_never_falls_back_to_individual_trade_result(self):
        original=self.scene_case()
        def response(*args):
            value=original(*args);value['scene']['plans'][0]['price']=9999
            return value
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=response),self.now),0)
        self.assertIsNone(state(self.db,'teacher_scene'))
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_cancelled_full_scene_is_wait_not_neutral_map_permission(self):
        process_ai_batch(self.db,self.c,Mock(interpret=self.scene_case()),self.now)
        self.seed(mid='cancel',text='取消全部计划',age=0)
        value=dict(as_of='cancel',action='UPDATE',regime='UNKNOWN',regime_ref=None,
                   plans=[],inner_range=None,outer_range=None,summary='明确取消')
        cancel=result(kind='CANCEL');cancel['cancel_side']='ALL'
        process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value=dict(interpretations=[cancel],scene=value))),self.now)
        self.assertEqual(state(self.db,'deepseek_setup')['mode'],'WAIT')
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_scene_source_edit_disables_all_dependent_execution(self):
        process_ai_batch(self.db,self.c,Mock(interpret=self.scene_case()),self.now)
        r=self.db.execute("SELECT raw FROM messages WHERE message_id='buy'").fetchone()
        import json
        ingest(self.db,'oc_test',[dict(json.loads(r['raw']),deleted=True)])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
    def test_scene_source_change_during_api_does_not_commit_partial_results(self):
        original=self.scene_case()
        def changed(*args):
            response=original(*args)
            r=self.db.execute("SELECT raw FROM messages WHERE message_id='buy'").fetchone()
            import json
            ingest(self.db,'oc_test',[dict(json.loads(r['raw']),deleted=True)])
            return response
        process_ai_batch(self.db,self.c,Mock(interpret=changed),self.now)
        self.assertIsNone(state(self.db,'teacher_scene'))
        self.assertEqual(self.db.execute("SELECT count(*) FROM ai_messages WHERE status='DONE'").fetchone()[0],0)

    def test_member_scene_is_ignored_and_does_not_interrupt_teacher_during_request(self):
        process_ai_batch(self.db,self.c,Mock(interpret=self.scene_case()),self.now)
        before=state(self.db,'teacher_scene')
        self.seed(mid='member',text='赞',sender='ou_other',age=0)
        def response(targets,*args):
            self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
            return dict(interpretations=[result(kind='DISCUSSION')],scene={'action':'UPDATE','as_of':'invented'})
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=response),self.now),1)
        self.assertEqual(state(self.db,'teacher_scene'),before)
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])

    def test_member_failure_backoff_and_follow_failure_do_not_block_teacher(self):
        process_ai_batch(self.db,self.c,Mock(interpret=self.scene_case()),self.now)
        self.c['follow_sender_id']='ou_follower'
        self.seed(mid='member',text='赞',sender='ou_other',age=0)
        self.seed(mid='follow',text='整整75',sender='ou_follower',age=0)
        failed=Mock(interpret=Mock(side_effect=AIError('成员解析失败')))
        process_ai_batch(self.db,self.c,failed,self.now)
        process_ai_batch(self.db,self.c,failed,self.now)
        process_ai_batch(self.db,self.c,failed,self.now+2)
        self.assertEqual(failed.interpret.call_count,2)
        self.assertTrue(ai_snapshot(self.db,self.c,self.now+2,False)['active'])
        status=state(self.db,'deepseek_status')
        self.assertFalse(status['follow_ready'])
        self.assertEqual(status['backlog'],2)
        self.assertEqual(status['error'],'成员解析失败')

    def test_teacher_and_member_are_never_in_same_batch_and_teacher_goes_first(self):
        self.seed(mid='member',text='赞',sender='ou_other',age=40)
        response=self.scene_case()
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=response),self.now),3)
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
        self.assertIsNone(self.db.execute("SELECT status FROM ai_messages WHERE message_id='member'").fetchone())

    def test_new_teacher_failure_still_blocks_existing_plan_during_backoff(self):
        process_ai_batch(self.db,self.c,Mock(interpret=self.scene_case()),self.now)
        self.seed(mid='change',text='取消多单',age=0)
        failed=Mock(interpret=Mock(side_effect=AIError('老师新指令解析失败')))
        process_ai_batch(self.db,self.c,failed,self.now)
        process_ai_batch(self.db,self.c,failed,self.now+2)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now+2,False)['active'])
        self.assertEqual(state(self.db,'deepseek_status')['backlog'],1)

    def test_restore_done_teacher_messages_once_without_replaying_follow_or_orders(self):
        self.scene_case()
        # 模拟旧版已逐条解析、只有空单但没有完整场景的数据库。
        process_ai_batch(self.db,self.c,self.client('WATCH'),self.now)
        with self.db:
            set_state(self.db,'teacher_analysis',{'quote':{'bid':4300,'ask':4301,'at':self.now+3600},'bars':[]})
        def restored(targets,context,*args):
            self.assertEqual([t['message_id'] for t in targets],['range'])
            by_id={m['message_id']:m for m in context}
            self.assertAlmostEqual(by_id['buy']['market_anchor'],4181.1)
            scene=dict(as_of='range',action='UPDATE',regime='UNKNOWN',regime_ref=None,
                plans=[plan('BUY','75',4175,'buy','多单等到75行动'),plan('SELL','93',4193,'sell','上去93可↓')],
                inner_range=None,outer_range=None,summary='恢复已有双向计划')
            return dict(interpretations=[result(kind='WATCH')],scene=scene)
        client=Mock(interpret=restored)
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now+3600,restore_scene=True),1)
        scene=state(self.db,'teacher_scene')
        self.assertEqual([p['price'] for p in scene['plans']],[4175,4193])
        self.assertLess(scene['plans'][0]['origin_created'],self.now)
        self.assertTrue(state(self.db,'teacher_scene_initialized'))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now+3602,restore_scene=True),0)
        self.assertIsNone(state(self.db,'member_follow_setups'))
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

    def test_restore_keep_is_retried_with_backoff_instead_of_silently_initialized(self):
        self.seed();process_ai_batch(self.db,self.c,self.client('WATCH'),self.now)
        keep=dict(as_of='om_test',action='KEEP',regime='UNKNOWN',regime_ref=None,plans=[],inner_range=None,outer_range=None,summary='沿用')
        client=Mock(interpret=Mock(return_value=dict(interpretations=[result(kind='WATCH')],scene=keep)))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now,restore_scene=True),0)
        process_ai_batch(self.db,self.c,client,self.now+2,restore_scene=True)
        self.assertEqual(client.interpret.call_count,1)
        self.assertFalse(state(self.db,'teacher_scene_initialized',False))
        self.assertFalse(ai_snapshot(self.db,self.c,self.now+2,False)['active'])

    def test_restore_does_not_promote_historical_imports(self):
        self.seed(historical=True)
        process_ai_batch(self.db,self.c,self.client('WATCH'),self.now)
        client=Mock(interpret=Mock(side_effect=AssertionError('不能重放历史导入')))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now,restore_scene=True),0)
        client.interpret.assert_not_called()

    def test_old_unprocessed_chat_does_not_block_but_cross_midnight_source_edit_does(self):
        from deepseek_ai import pending_rows,lane_readiness
        self.seed(mid='old-chat',text='旧的聊天',age=3*86400)
        process_ai_batch(self.db,self.c,Mock(interpret=self.scene_case()),self.now)
        self.assertTrue(lane_readiness(self.db,self.c,self.now)['teacher_ready'])
        import json
        raw=json.loads(self.db.execute("SELECT raw FROM messages WHERE message_id='buy'").fetchone()[0])
        ingest(self.db,'oc_test',[dict(raw,content='取消多单',update_time='edited-next-day')])
        tomorrow=self.now+86400
        self.assertEqual([r['message_id'] for r in pending_rows(self.db,self.c,tomorrow)],['buy'])
        self.assertFalse(lane_readiness(self.db,self.c,tomorrow)['teacher_ready'])


# 复用夹具而不重复执行从父类继承的已有测试。
for name in list(vars(DatabaseFixture)):
    if name.startswith('test_'):
        setattr(SceneWorkerTests,name,None)

del DatabaseFixture

if __name__=='__main__':unittest.main()
