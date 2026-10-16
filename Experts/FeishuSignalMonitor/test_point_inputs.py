import copy
import csv
import io
import json
import unittest
from datetime import datetime, timezone
from unittest.mock import Mock

import test_deepseek_ai as fixture
from test_deepseek_ai import result
from teacher_strategy import source_levels, refresh_levels
from deepseek_ai import process_ai_batch, pending_rows
from execution_feed import execution_csv
from point_inputs import manual_points
from store import state, set_state, ingest

SUMMARY = '''接下来半个月，没有超级重磅经济数据值得关注，黄金大概率走区间震荡。
大区间：4100-4200
小区间：4120-4180
接近4120↑，接近4180↓
万一低于4100，闭眼入。
若出现全球瞩目的重磅事件，另当别论
关键点位
4130--4145--4162--4170（小压力）--4190--4200--4222
【寄存部门】4130以下，寄存部门考虑上车。
接近4200为收单位置'''


class PointInputTests(unittest.TestCase):
    setUp=fixture.WorkerTests.setUp
    tearDown=fixture.WorkerTests.tearDown
    seed=fixture.WorkerTests.seed

    def feed(self, paused=False, now=None):
        context=state(self.db,'teacher_levels',{})
        text=execution_csv(self.db,self.c,now or self.now,paused,context,context.get('active',False),
                           context.get('levels',[]),{},protocol=8)
        return list(csv.reader(io.StringIO(text)))

    def summary(self):
        self.c['teacher_only']=True
        raw=self.seed(mid='summary',text=SUMMARY,sender='ou_summarizer',age=3600)
        refresh_levels(self.db,self.c,self.now)
        def respond(targets,*_):
            self.assertEqual(targets[0]['source_role'],'group_summary')
            proof=lambda p: dict(message_id='summary',token=str(p),price=p,evidence=str(p))
            plans=[dict(side=side,token=str(p),price=p,mode='REACTION',price_ref='summary',
                        price_evidence=evidence,direction_ref='summary',direction_evidence=evidence,
                        exits=None,basis=None) for side,p,evidence in [('BUY',4120,'接近4120↑'),('SELL',4180,'接近4180↓')]]
            scene=dict(as_of='summary',action='UPDATE',regime='RANGE',
                       regime_ref=dict(message_id='summary',evidence='黄金大概率走区间震荡'),
                       plans=plans,inner_range=dict(low=proof(4120),high=proof(4180)),
                       outer_range=dict(low=proof(4100),high=proof(4200)),summary='会议总结')
            return dict(interpretations=[dict(result(kind='WATCH'),id=targets[0]['id'])],scene=scene)
        self.assertEqual(process_ai_batch(self.db,self.c,Mock(interpret=respond),self.now),1)
        return raw

    def test_spoken_role_forms_and_non_entry_target(self):
        from point_inputs import spoken_roles
        for text,side,price in [('75都成了支撑点鸟','BUY',4175),
                                ('小区间压力位4180已经到了。。','SELL',4180),
                                ('4175由压力转为支撑','BUY',4175),
                                ('4175从支撑转为压力','SELL',4175),
                                ('4170（小压力）','SELL',4170)]:
            self.assertEqual([(p['side'],p['price']) for p in spoken_roles(text,4180)],[(side,price)],text)
        for text in ['冲击4200的意思，昨日直播讲过','过了便是4200','75不是支撑',
                     '75支撑无效','昨天75是支撑','如果突破4180，75成为支撑',
                     '75可能成为支撑','75是支撑吗？','止损放到4175支撑','EMA75是支撑']:
            self.assertEqual(spoken_roles(text,4180),[],text)
        self.assertEqual(spoken_roles('75是支撑',0),[])
        self.assertEqual(spoken_roles('50支撑',4200),[])

    def test_new_map_does_not_resurrect_role_from_before_map(self):
        self.seed(mid='old',text='4175支撑',age=4000)
        process_ai_batch(self.db,self.c,Mock(interpret=lambda targets,*_:dict(interpretations=[dict(result(kind='WATCH'),id=t['id']) for t in targets])),self.now)
        self.feed()
        self.summary()
        self.assertFalse(any(r[2]=='ROLE' and float(r[5])==4175 for r in self.feed()[1:-1]))

    def test_teacher_watch_role_is_exported_and_replaces_older_opposite(self):
        self.summary()
        self.seed(mid='role',text='70都成了支撑点鸟',age=5)
        with self.db:set_state(self.db,'deepseek_anchors',{'role':4180})
        rows=self.feed()[1:-1]
        match=[r for r in rows if float(r[5])==4170]
        self.assertEqual([(r[2],r[4],r[3]) for r in match],[('ROLE','BUY','60')])
        again=[r for r in self.feed(now=self.now+2)[1:-1] if float(r[5])==4170]
        self.assertEqual(match,again)
        self.assertTrue(any(float(r[5])==4180 and r[4]=='SELL' for r in rows))

    def test_role_source_withdrawal_or_edit_cannot_resurrect_older_role(self):
        self.summary()
        old=self.seed(mid='old-role',text='4170压力',age=10)
        new=self.seed(mid='new-role',text='4170支撑',age=5)
        self.feed()
        ingest(self.db,self.c['chat_id'],[dict(new,deleted=True)])
        self.assertFalse(any(float(r[5])==4170 for r in self.feed()[1:-1]))
        # 同价最新来源无价格的编辑同样不能退回旧消息。
        ingest(self.db,self.c['chat_id'],[dict(new,content='先等等')])
        self.assertFalse(any(float(r[5])==4170 for r in self.feed()[1:-1]))

    def test_new_role_retires_old_direct_without_changing_other_prices(self):
        self.summary()
        self.seed(mid='role',text='4180现在成为支撑',age=0)
        rows=self.feed()[1:-1]
        self.assertFalse(any(float(r[5])==4180 and r[4]=='SELL' for r in rows))
        self.assertTrue(any(float(r[5])==4180 and r[2]=='ROLE' and r[4]=='BUY' for r in rows))

    def test_untrusted_historical_cancelled_roles_and_pause(self):
        self.summary()
        self.seed(mid='member-role',text='4175支撑',sender='member',age=10)
        self.assertFalse(any(float(r[5])==4175 for r in self.feed()[1:-1]))
        raw=self.seed(mid='role',text='4175支撑',age=5)
        self.feed()
        self.seed(mid='cancel',text='4175多取消',age=0)
        rows=self.feed()[1:-1]
        self.assertTrue(all(r[2]=='WATCH' for r in rows if float(r[5])==4175))
        self.assertEqual(self.feed(paused=True)[0][3],'0')
        with self.db:self.db.execute("UPDATE messages SET historical=1 WHERE message_id='role'")
        self.assertFalse(any(r[2]=='ROLE' and float(r[5])==4175 for r in self.feed()[1:-1]))

    def test_summary_parses_annotated_map_in_teacher_only_mode(self):
        self.c['teacher_only']=True
        raw=dict(msg_type='text',content=SUMMARY)
        self.assertEqual(source_levels(raw,'ou_member',self.c),[4130,4145,4162,4170,4190,4200,4222])
        self.c['allow_group_summaries']=False
        self.assertIsNone(source_levels(raw,'ou_member',self.c))
        self.c['allow_group_summaries']=True;self.c['summary_source_senders']=['ou_allowed']
        self.assertIsNone(source_levels(raw,'ou_member',self.c))
        self.assertIsNotNone(source_levels(raw,'ou_allowed',self.c))

    def test_member_opinion_is_not_summary(self):
        self.c['teacher_only']=True
        for text in ['我觉得4130多4180空','关键点位4130--4145--4162','昨天会议总结大区间4100-4200，小区间4120-4180']:
            self.assertIsNone(source_levels(dict(msg_type='text',content=text),'ou_member',self.c))

    def test_summary_scene_does_not_overwrite_teacher_and_exports_role(self):
        with self.db:set_state(self.db,'deepseek_setup',dict(sender='ou_teacher',mode='WAIT',created=self.now,plans=[]))
        before=copy.deepcopy(state(self.db,'deepseek_setup'))
        self.summary()
        self.assertEqual(state(self.db,'deepseek_setup'),before)
        rows=self.feed();self.assertEqual(rows[0][:4],['TGA','8',str(int(self.now)),'1'])
        entries={(r[2],r[4],float(r[5]),int(r[3])) for r in rows[1:-1]}
        self.assertIn(('DIRECT','BUY',4120,90),entries)
        self.assertIn(('DIRECT','SELL',4180,90),entries)
        self.assertIn(('ROLE','SELL',4170,55),entries)
        self.assertNotIn(('MAP','AUTO',4170,40),entries)
        self.assertFalse(any(r[2]=='DIRECT' and float(r[5]) in (4100,4130,4200) for r in rows[1:-1]))
        self.assertTrue(all(r[2]=='WATCH' for r in rows[1:-1] if float(r[5]) in (4100,4130,4200)))

    def test_withdrawn_summary_removes_reference(self):
        raw=self.summary()
        ingest(self.db,self.c['chat_id'],[dict(raw,deleted=True)])
        refresh_levels(self.db,self.c,self.now)
        self.assertEqual(self.feed()[-1],['END','0'])

    def test_teacher_cancel_blocks_summary_and_map_fallback_at_same_price(self):
        self.summary()
        self.seed(mid='cancel',text='4180空取消',age=0)
        rows=self.feed()[1:-1]
        self.assertTrue(all(r[2]=='WATCH' for r in rows if float(r[5])==4180))
        self.assertTrue(any(r[2]=='DIRECT' and float(r[5])==4120 for r in rows))

    def test_previous_evening_summary_survives_midnight_queue(self):
        self.c['teacher_only']=True
        self.now=datetime(2026,10,15,16,5,tzinfo=timezone.utc).timestamp()
        self.seed(mid='summary',text=SUMMARY,sender='ou_summarizer',age=3600)
        self.assertEqual([r['message_id'] for r in pending_rows(self.db,self.c,self.now)],['summary'])

    def manual(self, **changes):
        value=dict(enabled=True,symbol='XAUUSD',confirmed_at=datetime.fromtimestamp(self.now-30,timezone.utc).isoformat(),
                   levels=[dict(price=4170,role='minor_resistance'),dict(price=4200,role='watch'),dict(price=4120,role='buy')],
                   outer_range=[4100,4200])
        value.update(changes)
        (self.home/'config/manual_points.json').write_text(json.dumps(value,ensure_ascii=False),encoding='utf-8')
        return value

    def test_manual_replace_survives_ai_error_but_respects_pause_and_health(self):
        self.manual()
        with self.db:set_state(self.db,'deepseek_review',dict(message_id='bad',created=self.now))
        before=self.feed();self.assertEqual(before[0][3],'1')
        self.assertTrue(all(r[6]=='MANUAL' for r in before[1:-1]))
        self.assertTrue(all(r[2]=='WATCH' for r in before[1:-1] if float(r[5])==4200))
        self.assertEqual(before[1:],self.feed(now=self.now+2)[1:])
        self.assertEqual(self.feed(paused=True)[0][3],'0')
        self.assertEqual(self.feed(now=self.now+500)[0][3],'0')

    def test_bad_manual_file_stops_instead_of_falling_back(self):
        for changes in [dict(levels=[dict(price=True)]),dict(levels=[dict(price=70)]),
                        dict(levels=[dict(price=4170,role='oops')]),dict(inner_range=[4000,4190]),
                        dict(confirmed_at='2026-01-01'),dict(symbol='EURUSD')]:
            with self.subTest(changes=changes):
                self.manual(**changes)
                self.assertEqual(self.feed()[0][3],'0')
                self.assertIn('手动点位错误',self.feed()[0][6])
        (self.home/'config/manual_points.json').write_text('{bad',encoding='utf-8')
        self.assertEqual(self.feed()[-1],['END','0'])

    def test_disabled_manual_is_ignored(self):
        self.manual(enabled=False)
        self.assertIsNone(manual_points(self.c,self.now))


if __name__=='__main__':unittest.main()
