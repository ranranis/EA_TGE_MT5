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


class ExitPlanTests(unittest.TestCase):
    def case(self):
        text='4175做多，止损4168，首批4180，尾仓4190，保本4178'
        targets=[message('entry',text,1)]
        value=dict(as_of='entry',action='UPDATE',regime='UNKNOWN',regime_ref=None,
                   plans=[plan('BUY','4175',4175,'entry','4175做多')],
                   inner_range=None,outer_range=None,summary='有证据的退出计划')
        def proof(token,evidence=None):
            return dict(message_id='entry',token=token,price=float(token),evidence=evidence or text)
        value['plans'][0]['exits']={k:proof(t) for k,t in
            [('sl','4168'),('tp1','4180'),('tp2','4190'),('breakeven','4178')]}
        return targets,value

    def test_explicit_exit_prices_and_proof_survive_validation(self):
        targets,value=self.case()
        clean=validate_scene(value,targets,[],4181)
        self.assertEqual(clean['plans'][0]['exits']['sl']['price'],4168)
        self.assertEqual(clean['plans'][0]['exits']['breakeven']['price'],4178)

    def test_unknown_price_role_reversed_targets_and_missing_association_fail(self):
        for change in ('number','role','order','foreign','historical','direction'):
            with self.subTest(change=change),self.assertRaises(AIError):
                targets,value=self.case();exits=value['plans'][0]['exits']
                if change=='number':exits['sl']['price']=4268
                if change=='role':exits['sl'].update(token='4175',price=4175)
                if change=='order':
                    exits['tp1'],exits['tp2']=exits['tp2'],exits['tp1']
                    targets[0]['text']+='，止盈4180，止盈4190'
                    exits['tp1']['evidence']=exits['tp2']['evidence']=targets[0]['text']
                if change in ('foreign','historical'):
                    targets.append(message('exit','昨天止损4168' if change=='historical' else '止损4168',2))
                    value['as_of']='exit';exits['sl'].update(message_id='exit',evidence=targets[-1]['text'])
                if change=='direction':
                    targets[0]['text']=targets[0]['text'].replace('4168','4185')
                    exits['sl'].update(token='4185',price=4185,evidence=targets[0]['text'])
                    for k in ('tp1','tp2','breakeven'):exits[k]=None
                validate_scene(value,targets,[],4181)

    def test_cross_message_requires_stated_entry_direction_and_tracks_source(self):
        targets,value=self.case()
        targets.append(message('update','4175多单止损4169',2))
        value['as_of']='update'
        value['plans'][0]['exits']['sl']=dict(message_id='update',token='4169',price=4169,evidence=targets[-1]['text'])
        clean=validate_scene(value,targets,[],4181)
        self.assertIn('update',{r['message_id'] for r in clean['source_refs']})
        self.assertEqual(clean['plans'][0]['exits']['sl']['price'],4169)

    def test_one_clause_cannot_assign_other_plan_exit(self):
        targets,value=self.case()
        targets[0]['text']+='；4193做空，止损4200'
        value['plans'].append(plan('SELL','4193',4193,'entry','4193做空'))
        # 证据只有另一个计划的止损，不能仅凭同消息就套在多单上。
        value['plans'][0]['exits']['sl'].update(token='4200',price=4200,evidence='4193做空，止损4200')
        with self.assertRaises(AIError):validate_scene(value,targets,[],4181)


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

    def test_cancel_between_old_direction_and_new_price_rejects_both_sides(self):
        for side,scope in [('BUY','BUY'),('BUY','ALL'),('SELL','SELL'),('SELL','ALL')]:
            word='多单' if side=='BUY' else '空单'
            old=message('old','4170'+word,1)
            cancel=dict(message('cancel','取消'+(word if scope!='ALL' else '全部参考'),2),
                        interpretation=dict(kind='CANCEL',cancel_side=scope))
            new=message('new','到4175了',3)
            p=plan(side,'4175',4175,'new','到4175了');p.update(direction_ref='old',direction_evidence=old['text'])
            scene=dict(as_of='new',action='UPDATE',regime='UNKNOWN',regime_ref=None,plans=[p],
                       inner_range=None,outer_range=None,summary='新价格借用旧方向')
            with self.subTest(side=side,scope=scope),self.assertRaisesRegex(AIError,'取消前的旧方向'):
                validate_scene(scene,[new],[old,cancel],4181)

    def test_receipt_sequence_orders_cancel_between_same_time_evidence(self):
        old=message('old','4170多单',1)
        cancel=dict(message('cancel','取消多单',2),time=old['time'],interpretation=dict(kind='CANCEL',cancel_side='BUY'))
        new=dict(message('new','到4175了',3),time=old['time'])
        p=plan('BUY','4175',4175,'new',new['text']);p.update(direction_ref='old',direction_evidence=old['text'])
        scene=dict(as_of='new',action='UPDATE',regime='UNKNOWN',regime_ref=None,plans=[p],
                   inner_range=None,outer_range=None,summary='同时间按接收顺序核验')
        with self.assertRaisesRegex(AIError,'取消前的旧方向'):validate_scene(scene,[new],[old,cancel],4181)

    def test_new_explicit_direction_after_cancel_can_reestablish_plan(self):
        for side,scope in [('BUY','BUY'),('BUY','ALL'),('SELL','SELL'),('SELL','ALL')]:
            word='多单' if side=='BUY' else '空单'
            old=message('old','4170'+word,1)
            cancel=dict(message('cancel','取消'+(word if scope!='ALL' else '全部参考'),2),
                        interpretation=dict(kind='CANCEL',cancel_side=scope))
            new=message('new','4175'+word,3)
            scene=dict(as_of='new',action='UPDATE',regime='UNKNOWN',regime_ref=None,
                       plans=[plan(side,'4175',4175,'new',new['text'])],inner_range=None,outer_range=None,summary='新明确计划')
            with self.subTest(side=side,scope=scope):
                self.assertEqual(validate_scene(scene,[new],[old,cancel],4181)['plans'][0]['price'],4175)

    def test_new_explicit_direction_can_use_earlier_price_evidence(self):
        for side in ('BUY','SELL'):
            word='多单' if side=='BUY' else '空单'
            old=message('old','4170'+word,1)
            cancel=dict(message('cancel','取消'+word,2),interpretation=dict(kind='CANCEL',cancel_side=side))
            new=message('new','重新'+word,3)
            p=plan(side,'4170',4170,'old',old['text']);p.update(direction_ref='new',direction_evidence=new['text'])
            scene=dict(as_of='new',action='UPDATE',regime='UNKNOWN',regime_ref=None,plans=[p],
                       inner_range=None,outer_range=None,summary='价格证据不会续期旧方向，新明确方向可重新建立')
            with self.subTest(side=side):
                self.assertEqual(validate_scene(scene,[new],[old,cancel],4181)['plans'][0]['direction_ref'],'new')


class RangeInferenceTests(unittest.TestCase):
    def sample(self):
        targets,context,scene=example()
        targets.append(message('edges','大区间的两头，为重要点位',6))
        scene['as_of']='edges'
        for side,token in [('BUY','4150'),('SELL','4220')]:
            item=plan(side,token,int(token),'large','大区间参考4150--4220')
            item.update(direction_ref='edges',direction_evidence=targets[-1]['text'],
                        basis=dict(kind='RANGE_EDGE',range='outer_range'))
            scene['plans'].append(item)
        return targets,context,scene

    def test_emphasized_range_edges_add_typed_buy_and_sell(self):
        targets,context,scene=self.sample()
        clean=validate_scene(scene,targets,context,4181)
        self.assertEqual([(p['side'],p['price']) for p in clean['plans']],
                         [('BUY',4175),('SELL',4193),('BUY',4150),('SELL',4220)])
        self.assertEqual(clean['plans'][2]['basis']['kind'],'RANGE_EDGE')
        self.assertIn('edges',[r['message_id'] for r in clean['source_refs']])
        self.assertIn('rhythm',[r['message_id'] for r in clean['source_refs']])

    def test_range_inference_rejects_missing_or_false_evidence(self):
        for case in ['bare_range','wrong_side','wrong_price','trend','member','market','invalid_role','exits']:
            targets,context,scene=self.sample()
            p=scene['plans'][2]
            if case=='bare_range': p.update(direction_ref='large',direction_evidence=targets[-2]['text'])
            if case=='wrong_side': p['side']='SELL'
            if case=='wrong_price': p.update(token='4160',price=4160)
            if case=='trend': scene['regime']='TREND_DOWN'
            if case=='member': targets[-1]['source_role']='follow_member'
            if case=='market': p['mode']='MARKET'
            if case=='invalid_role':
                targets[-1]['text']='大区间两头不重要，支撑失效'
                p['direction_evidence']=targets[-1]['text']
            if case=='exits': p['exits']={'sl':dict(price=4140)}
            with self.subTest(case=case),self.assertRaises(AIError):
                validate_scene(scene,targets,context,4181)

    def test_invalid_added_inference_does_not_block_valid_explicit_plans(self):
        from teacher_scene import validate_execution_scene
        targets,context,scene=self.sample()
        scene['plans'][2]['direction_evidence']='区间好位置'
        clean=validate_execution_scene(scene,targets,context,4181)
        self.assertEqual([(p['side'],p['price']) for p in clean['plans']],[('BUY',4175),('SELL',4193)])
        self.assertIn('inference_rejection',clean)
        self.assertNotIn('4150',clean['summary'])
        scene['plans'][0]['price']=9999
        with self.assertRaises(AIError):validate_execution_scene(scene,targets,context,4181)

    def test_explicit_cancel_cannot_revive_range_buy(self):
        targets,context,scene=self.sample()
        targets.append(dict(message('cancel','取消多单',7),interpretation=dict(kind='CANCEL',cancel_side='BUY')))
        scene['as_of']='cancel'
        with self.assertRaises(AIError):validate_scene(scene,targets,context,4181)

    def test_contextual_price_update_replaces_prior_buy(self):
        old=message('old','现在90可⬆️',1)
        new=message('new','86了 注意。。',2)
        p=plan('BUY','86',4186,'new',new['text'])
        p.update(direction_ref='old',direction_evidence=old['text'])
        scene=dict(as_of='new',action='UPDATE',regime='UNKNOWN',regime_ref=None,
                   plans=[p],inner_range=None,outer_range=None,summary='承接原方向，更新入场价')
        self.assertEqual(validate_scene(scene,[new],[old],4188)['plans'][0]['price'],4186)


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
    def test_range_plans_export_tga4_type_without_creating_orders(self):
        from app import export_teacher_levels
        import csv
        self.seed(mid='rhythm',text='区间来回跑',age=30)
        self.seed(mid='range',text='大区间参考4150--4220',age=20)
        self.seed(mid='edges',text='大区间的两头，为重要点位',age=10)
        def response(targets,*args):
            p=plan('BUY','4150',4150,'range','大区间参考4150--4220')
            p.update(direction_ref='edges',direction_evidence='大区间的两头，为重要点位',
                     basis=dict(kind='RANGE_EDGE',range='outer_range'))
            band={role:dict(message_id='range',token=str(n),price=n,evidence='大区间参考4150--4220')
                  for role,n in [('low',4150),('high',4220)]}
            scene=dict(as_of='edges',action='UPDATE',regime='RANGE',
                       regime_ref=dict(message_id='rhythm',evidence='区间来回跑'),
                       plans=[p],inner_range=None,outer_range=band,summary='AI区间下沿BUY试仓')
            return dict(interpretations=[dict(result(kind='WATCH'),id=t['id']) for t in targets],scene=scene)
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=response),self.now),3)
        export_teacher_levels(self.db,self.c,False,self.now)
        with (self.home/'common/FeishuMT5SignalMonitor/tge_ai_setups.csv').open(encoding='utf-8',newline='') as f:
            rows=list(csv.reader(f))
        self.assertEqual(rows[0][1],'4')
        self.assertEqual(rows[1][1:3],['BUY','4150.0000000000'])
        self.assertEqual(rows[1][12],'RANGE_EDGE')
        self.assertEqual(len(rows[1]),13)
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

    def test_validated_exits_export_in_tga3(self):
        from app import export_teacher_levels
        import csv
        text='4175做多，止损4168，首批4180，尾仓4190，保本4178'
        self.seed(mid='entry-exit',text=text,age=0)
        def response(targets,*args):
            p=plan('BUY','4175',4175,'entry-exit','4175做多')
            p['exits']={k:dict(message_id='entry-exit',token=str(n),price=n,evidence=text)
                for k,n in [('sl',4168),('tp1',4180),('tp2',4190),('breakeven',4178)]}
            scene=dict(as_of='entry-exit',action='UPDATE',regime='UNKNOWN',regime_ref=None,
                plans=[p],inner_range=None,outer_range=None,summary='退出证据测试')
            return dict(interpretations=[dict(result(kind='WATCH'),id=t['id']) for t in targets],scene=scene)
        process_ai_batch(self.db,self.c,Mock(interpret=response),self.now)
        export_teacher_levels(self.db,self.c,False,self.now)
        with (self.home/'common/FeishuMT5SignalMonitor/tge_ai_setups.csv').open(encoding='utf-8',newline='') as file:
            rows=list(csv.reader(file))
        self.assertEqual(rows[0][1],'3')
        self.assertEqual(list(map(float,rows[1][8:])),[4168,4180,4190,4178])
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

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
        self.assertEqual(lines[0][:2],['TGA','3'])
        self.assertEqual([lines[1][5],lines[2][5]],['buy','sell'])
        self.assertEqual(len(lines[1]),12)
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


class TeacherOnlyQueueTests(unittest.TestCase):
    setUp=SceneWorkerTests.setUp
    tearDown=SceneWorkerTests.tearDown
    seed=SceneWorkerTests.seed

    def baseline(self):
        response=SceneWorkerTests.scene_case(self)
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=response),self.now),3)
        return copy.deepcopy(state(self.db,'deepseek_setup'))

    def test_old_discussion_with_malformed_scene_cannot_block_newer_valid_plan(self):
        before=self.baseline()
        self.seed(mid='old-chat',text='都还在睡？',age=3600)
        raw=dict(interpretations=[result(kind='DISCUSSION')],scene=dict(
            as_of='old-chat',action='KEEP',regime='RANGE',regime_ref=None,
            plans=[{'price':9999}],inner_range=None,outer_range=None,summary='格式错误'))
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value=raw)),self.now),1)
        self.assertEqual(state(self.db,'deepseek_setup'),before)
        self.assertEqual(self.db.execute("SELECT status FROM ai_messages WHERE message_id='old-chat'").fetchone()[0],'DONE')
        self.assertTrue(ai_snapshot(self.db,self.c,self.now,False)['active'])
        from app import export_teacher_levels
        export_teacher_levels(self.db,self.c,False,self.now)
        output=(self.home/'common/FeishuMT5SignalMonitor/tge_ai_setups.csv').read_text(encoding='utf-8')
        self.assertIn(',1,XAUUSD',output)
        self.assertNotIn('9999',output)
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

    def test_cancel_reprice_and_ambiguous_instruction_cannot_use_chatter_shortcut(self):
        before=self.baseline()
        for n,text in enumerate(('取消全部','55可以上','改到55','先别做','算了','暂停')):
            mid='instruction'+str(n)
            self.seed(mid=mid,text=text,age=0)
            raw=dict(interpretations=[result(kind='DISCUSSION')],scene=dict(
                as_of=mid,action='KEEP',regime='UNKNOWN',regime_ref=None,
                plans=[{'price':9999}],inner_range=None,outer_range=None,summary='错误'))
            self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value=raw)),self.now),0)
            self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
        self.assertEqual(state(self.db,'deepseek_setup'),before)

    def test_review_still_blocks_and_source_edit_still_blocks(self):
        self.baseline()
        self.seed(mid='unclear',text='多单先等等',age=0)
        raw=dict(interpretations=[result(kind='UNKNOWN')],scene=dict(
            as_of='unclear',action='REVIEW',regime='UNKNOWN',regime_ref=None,
            plans=[],inner_range=None,outer_range=None,summary='是否取消不清楚'))
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=Mock(return_value=raw)),self.now),1)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])
        r=self.db.execute("SELECT raw FROM messages WHERE message_id='buy'").fetchone()
        ingest(self.db,'oc_test',[dict(json.loads(r['raw']),deleted=True)])
        with self.db:set_state(self.db,'deepseek_review',{})
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])

    def test_teacher_only_never_analyzes_members_or_uses_member_map(self):
        from deepseek_ai import follow_ids,lane_readiness
        from teacher_strategy import source_levels
        self.c.update(teacher_only=True,follow_sender_id='ou_student',
                      follow_members=[dict(sender_id='ou_student',enabled=True,ttl_seconds=300)])
        self.seed(mid='student',text='4155多上了',sender='ou_student')
        other=self.seed(mid='other-map',text='4150--4160--4175',sender='ou_other')
        client=Mock()
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),0)
        client.interpret.assert_not_called()
        self.assertEqual(follow_ids(self.c),[])
        self.assertEqual(lane_readiness(self.db,self.c,self.now)['backlog'],0)
        self.assertIsNone(source_levels(other,'ou_other',self.c))

    def test_teacher_only_exports_explicit_tga5_without_member_channel(self):
        from app import export_teacher_levels
        import csv
        self.baseline()
        self.c['teacher_only']=True
        export_teacher_levels(self.db,self.c,False,self.now)
        with (self.home/'common/FeishuMT5SignalMonitor/tge_ai_setups.csv').open(encoding='utf-8',newline='') as f:
            rows=list(csv.reader(f))
        self.assertEqual(rows[0][1],'5')
        self.assertTrue(all(len(r)==13 and r[12]=='DIRECT' for r in rows[1:-1]))

    def test_teacher_only_strips_inference_but_keeps_direct_teacher_plan(self):
        self.c['teacher_only']=True
        base=SceneWorkerTests.scene_case(self)
        def response(*args):
            value=base(*args)
            value['scene']['plans'][0]['basis']={'kind':'RANGE_EDGE','range':'outer_range'}
            return value
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=response),self.now),3)
        plans=state(self.db,'deepseek_setup')['plans']
        self.assertEqual([(p['side'],p['price']) for p in plans],[('SELL',4193)])

class SemanticRepairTests(unittest.TestCase):
    def scene(self,mid,plans):
        return dict(as_of=mid,action='UPDATE',regime='UNKNOWN',regime_ref=None,
                    plans=plans,inner_range=None,outer_range=None,summary='合成语义场景')

    def split_case(self):
        direction=message('direction','↑。。',1)
        entry=message('entry','注意，4200了，每距离20点可以加',2)
        target=message('target','目标统一4250',3)
        p=plan('BUY','4200',4200,'entry',entry['text'])
        p.update(direction_ref='direction',direction_evidence=direction['text'])
        before=validate_scene(self.scene('entry',[p]),[entry],[direction],4200)
        p['exits']=dict(sl=None,tp1=None,tp2=dict(message_id='target',token='4250',price=4250,evidence=target['text']),breakeven=None)
        return direction,entry,target,before,self.scene('target',[p])

    def test_late_uniform_target_updates_same_identity_and_tracks_all_sources(self):
        direction,entry,target,before,value=self.split_case()
        clean=validate_scene(value,[target],[direction,entry],4200,before)
        self.assertEqual(clean['plans'][0]['exits']['tp2']['price'],4250)
        for key in ('origin_id','origin_revision','origin_created'):
            self.assertEqual(clean['plans'][0][key],before['plans'][0][key])
        self.assertEqual({r['message_id'] for r in clean['source_refs']},{'direction','entry','target'})
        self.assertEqual(validate_scene(value,[target],[direction,entry],4300,clean)['plans'],clean['plans'])

    def test_uniform_target_cannot_drop_another_group_to_claim_unique_association(self):
        direction,entry,target,before,value=self.split_case()
        before['plans'].append(dict(plan('SELL','4270',4270,'other','4270可空')))
        with self.assertRaisesRegex(AIError,'唯一关联'):
            validate_scene(value,[target],[direction,entry],4200,before)

    def test_target_before_entry_cannot_be_applied_retroactively(self):
        direction,entry,target,before,value=self.split_case()
        target['time']=direction['time'];target['sequence']=0
        value['as_of']='entry'
        with self.assertRaisesRegex(AIError,'唯一关联'):
            validate_scene(value,[entry],[direction,target],4200)

    def test_recap_cannot_supply_range_entry_or_exit_even_when_quote_omits_recap_word(self):
        for mode in ('range','entry','exit'):
            with self.subTest(mode=mode),self.assertRaisesRegex(AIError,'复盘'):
                old=message('old','方才4200多，目标4250，在4200--4260跑了几个来回',1)
                value=self.scene('old',[])
                proof=lambda token:dict(message_id='old',token=token,price=int(token),evidence=token)
                if mode=='range':value['inner_range']=dict(low=proof('4200'),high=proof('4260'))
                if mode=='entry':value['plans']=[plan('BUY','4200',4200,'old','4200多')]
                if mode=='exit':
                    new=message('new','4190多',0)
                    p=plan('BUY','4190',4190,'new',new['text'])
                    p['exits']=dict(sl=None,tp1=None,tp2=dict(proof('4250'),evidence='目标4250'),breakeven=None)
                    value['plans']=[p]
                    validate_scene(value,[old],[new],4200)
                else:validate_scene(value,[old],[],4200)

    def test_explicit_republication_after_recap_is_allowed(self):
        new=message('new','方才4180做多赚了。现在4200可多',1)
        value=self.scene('new',[plan('BUY','4200',4200,'new','现在4200可多')])
        self.assertEqual(validate_scene(value,[new],[],4200)['plans'][0]['price'],4200)

    def test_missing_article_and_bare_quote_cannot_borrow_a_direction(self):
        for text in ('按照文章计划，4200开始动手','4200了','目标统一4200'):
            old=message('old','4190做多',1);new=message('new',text,2)
            p=plan('BUY','4200',4200,'new',text)
            p.update(direction_ref='old',direction_evidence=old['text'])
            with self.subTest(text=text),self.assertRaises(AIError):
                validate_scene(self.scene('new',[p]),[new],[old],4200)

    def test_no_direction_cannot_be_invented_and_no_price_cannot_be_invented(self):
        for text,token in [('4200开始动手','4200'),('↑现在','现在')]:
            new=message('new',text,1)
            with self.subTest(text=text),self.assertRaises(AIError):
                validate_scene(self.scene('new',[plan('BUY',token,4200,'new',text)]),[new],[],4200)

    def test_null_and_numeric_string_prices_are_locally_resolved_without_input_mutation(self):
        for number in (None,'4175'):
            new=message('new','75多',1)
            value=self.scene('new',[plan('BUY','75',number,'new',new['text'])])
            clean=validate_scene(value,[new],[],4181)
            self.assertEqual(clean['plans'][0]['price'],4175)
            self.assertEqual(value['plans'][0]['price'],number)

    def test_empty_keep_cursor_is_bound_but_wrong_cursor_and_payload_still_fail(self):
        new=message('new','方才4200到4210来回震荡',1)
        value=self.scene('',[]);value['action']='KEEP'
        self.assertEqual(validate_scene(value,[new],[],4200)['as_of'],'new')
        value['as_of']='other'
        with self.assertRaises(AIError):validate_scene(value,[new],[],4200)
        value['as_of']='';value['plans']=[plan('BUY','4200',4200,'new',new['text'])]
        with self.assertRaises(AIError):validate_scene(value,[new],[],4200)

    def test_teacher_only_request_does_not_include_range_inference_examples(self):
        client=DeepSeek('.',dict(ai_model='deepseek-flash',teacher_only=True))
        client.request=Mock(return_value={'choices':[{'finish_reason':'stop','message':{'content':'{"interpretations":[]}'}}]})
        client.interpret([message('new','小区间4200--4250',1)],[],4200,[])
        prompt=client.request.call_args.args[1]['messages'][0]['content']
        self.assertNotIn('本次另行授权的AI区间推导',prompt)
        self.assertIn('不得生成basis=null',prompt)

    def test_mislabeled_range_edges_remain_display_only_and_retain_prior_plan(self):
        from teacher_scene import validate_execution_scene
        direction,entry,target,before,value=self.split_case()
        band=message('range','区间4200--4260来回跑',4)
        value=self.scene('range',[
            plan('BUY','4200',4200,'range',band['text']),plan('SELL','4260',4260,'range',band['text'])])
        value['inner_range']={key:dict(message_id='range',token=token,price=int(token),evidence=band['text'])
                              for key,token in [('low','4200'),('high','4260')]}
        clean=validate_execution_scene(value,[band],[direction,entry],4200,before)
        self.assertEqual([(p['side'],p['price'],p['price_ref']) for p in clean['plans']],[('BUY',4200,'entry')])
        self.assertEqual(clean['inner_range']['high']['price'],4260)
        self.assertIn('semantic_correction',clean)
        band['text']+='，往上破4270则有望去4300'
        value['plans']=[plan('BUY','4270',4270,'range','往上破4270则有望去4300')]
        clean=validate_execution_scene(value,[band],[direction,entry],4200,before)
        self.assertEqual([(p['side'],p['price']) for p in clean['plans']],[('BUY',4200)])
        band['text']='方才区间4200--4260来回跑'
        with self.assertRaises(AIError):validate_execution_scene(value,[band],[direction,entry],4200,before)

    def test_intervening_opposite_direction_prevents_fragment_link_and_uniform_target(self):
        direction,entry,target,before,value=self.split_case()
        other=message('other','↓。。',1);other['time']=entry['time'];other['sequence']=1
        with self.assertRaisesRegex(AIError,'相反方向'):
            validate_scene(value,[target],[direction,other,entry],4200,before)
        other['time']=target['time'];other['sequence']=2
        with self.assertRaisesRegex(AIError,'唯一关联'):
            validate_scene(value,[target],[direction,entry,other],4200,before)


class SplitMessageWorkerTests(unittest.TestCase):
    setUp=SceneWorkerTests.setUp
    tearDown=SceneWorkerTests.tearDown
    seed=SceneWorkerTests.seed

    def respond(self,targets,context,anchor,levels,previous):
        all_items={m['message_id']:m for m in context+targets}
        last=targets[-1]['message_id']
        plans=[]
        if 'entry' in all_items:
            p=plan('BUY','4200',4200,'entry',all_items['entry']['text'])
            p.update(direction_ref='direction',direction_evidence='↑。。')
            if 'target' in all_items:
                p['exits']=dict(sl=None,tp1=None,tp2=dict(message_id='target',token='4250',price=4250,evidence='目标统一4250'),breakeven=None)
            plans=[p]
        value=SemanticRepairTests().scene(last,plans)
        return dict(interpretations=[dict(result(kind='WATCH'),id=t['id']) for t in targets],scene=value)

    def test_split_messages_restart_dedupe_and_withdrawn_target(self):
        from store import connect
        self.seed(mid='direction',text='↑。。',age=30)
        client=Mock(interpret=Mock(side_effect=self.respond))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        self.assertEqual(state(self.db,'deepseek_setup')['plans'],[])
        self.seed(mid='entry',text='注意，4200了，每距离20点可以加',age=20)
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        origin=state(self.db,'deepseek_setup')['plans'][0]['origin_revision']
        self.db.close();self.db=connect(self.home/'data/test.sqlite')
        target=self.seed(mid='target',text='目标统一4250',age=10)
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        setup=state(self.db,'deepseek_setup');self.assertEqual(len(setup['plans']),1)
        self.assertEqual(setup['plans'][0]['origin_revision'],origin)
        self.assertEqual(setup['plans'][0]['exits']['tp2']['price'],4250)
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),0)
        self.assertEqual(client.interpret.call_count,3)
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)
        ingest(self.db,'oc_test',[dict(target,deleted=True)])
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])

    def test_review_preserves_last_valid_scene_for_next_message(self):
        self.seed(mid='direction',text='↑。。',age=30)
        self.seed(mid='entry',text='注意4200了，可以加',age=20)
        process_ai_batch(self.db,self.c,Mock(interpret=self.respond),self.now)
        before=copy.deepcopy(state(self.db,'teacher_scene'))
        self.seed(mid='unclear',text='文章计划怎么说的',age=10)
        review=SemanticRepairTests().scene('unclear',[]);review['action']='REVIEW'
        client=Mock(interpret=Mock(return_value=dict(interpretations=[result(kind='UNKNOWN')],scene=review)))
        self.assertEqual(process_ai_batch(self.db,self.c,client,self.now),1)
        self.assertEqual(state(self.db,'teacher_scene'),before)
        self.assertFalse(ai_snapshot(self.db,self.c,self.now,False)['active'])


if __name__=='__main__':unittest.main()
