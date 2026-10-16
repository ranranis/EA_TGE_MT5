"""TGA6完整快照回归：隔离数据库、合成来源、不写真实Common文件。"""
import csv
import io
import json
import unittest
from unittest.mock import Mock
from store import state, set_state, ingest
import test_deepseek_ai as fixture
import test_teacher_scene as scenes
from deepseek_ai import process_ai_batch
from teacher_strategy import refresh_levels
from app import export_teacher_levels


class ExecutionTests(unittest.TestCase):
    setUp = fixture.WorkerTests.setUp
    tearDown = fixture.WorkerTests.tearDown
    seed = fixture.WorkerTests.seed
    client = fixture.WorkerTests.client

    def feed(self, paused=False, now=None, protocol=6):
        export_teacher_levels(self.db, self.c, paused, self.now if now is None else now)
        p = self.home/('common/FeishuMT5SignalMonitor/tge_execution_v7.csv' if protocol==7 else 'common/FeishuMT5SignalMonitor/tge_execution.csv')
        return list(csv.reader(io.StringIO(p.read_text(encoding='utf-8'))))

    def scene(self):
        response = scenes.SceneWorkerTests.scene_case(self)
        text='今日小区间4175-4200，大区间4150-4220'
        self.seed(mid='range',text=text,age=10)
        def reply(*args):
            value=response(*args)
            for key,prices in [('inner_range',(4175,4200)),('outer_range',(4150,4220))]:
                value['scene'][key]={edge:dict(message_id='range',token=str(price),price=price,evidence=text)
                                     for edge,price in zip(('low','high'),prices)}
            return value
        process_ai_batch(self.db, self.c, Mock(interpret=reply), self.now)

    def test_v9_display_survives_quote_loss_and_execution_recovers_only_with_fresh_quote(self):
        self.scene()
        symbol=self.c['symbols'][self.c['teacher_symbol']]
        def export(market_ok,at,paused=False):
            with self.db:
                set_state(self.db,'teacher_analysis',dict(market_ok=market_ok,
                    quote=dict(symbol=symbol,bid=4180,ask=4180.1,at=at)))
            export_teacher_levels(self.db,self.c,paused,self.now)
            p=self.home/'common/FeishuMT5SignalMonitor/tge_execution_v9.csv'
            return list(csv.reader(io.StringIO(p.read_text(encoding='utf-8'))))
        rows=export(False,self.now-3600)
        self.assertEqual(rows[0][3],'0')
        self.assertGreater(int(rows[0][5]),0)
        self.assertIn('报价失效',rows[0][6])
        self.assertLessEqual(int(rows[0][5]),6)
        self.assertEqual(rows[-1],['END',rows[0][5]])
        rows=export(True,self.now-3600)
        self.assertEqual(rows[0][3],'0')  # 旧报价不能只改market_ok就变新鲜。
        rows=export(True,self.now)
        self.assertEqual(rows[0][3],'1')
        rows=export(True,self.now,True)
        self.assertEqual(rows[0][3],'0')  # 暂停仍阻断，不能被新报价覆盖。

    def test_status_caption_distinguishes_processing_error_and_ready(self):
        from execution_feed import ai_status_note
        with self.db:
            set_state(self.db,'deepseek_status',dict(online=True,last_success=self.now))
        self.assertIn('AI解析就绪 · 待0条 · 最近成功',ai_status_note(self.db,self.c,self.now,False))
        self.scene()
        self.seed(mid='pending',text='4120↑',age=0)
        for error,label in [('AI正在解释新消息','AI正在解析'),
                            ('AI场景必须截至最新老师消息','AI解析异常：语义校验'),
                            ('DeepSeek连接/响应或本机凭证异常：RemoteDisconnected','AI解析异常：连接/响应')]:
            with self.db:
                set_state(self.db,'deepseek_status',dict(online=False,error=error,last_success=self.now-60))
            caption=self.feed(protocol=7)[0][6]
            self.assertIn(label,caption)
            self.assertIn('待1条',caption)
            self.assertIn('最近成功',caption)
            self.assertIn('沿用已确认点位',caption)
            self.assertNotIn('RemoteDisconnected',caption)
        self.seed(mid='cancel',text='取消全部计划',age=0)
        self.assertEqual(self.feed(protocol=7)[0][3],'0')
        self.assertIn('撤销',self.feed(protocol=7)[0][6])

    def test_complete_snapshot_contains_map_direct_and_ranges(self):
        self.scene()
        self.seed(mid='map', text='4150--4160--4175--4190--4200--4220', age=0)
        refresh_levels(self.db,self.c,self.now)
        process_ai_batch(self.db,self.c,Mock(),self.now)
        rows=self.feed()
        self.assertEqual(rows[0][:2],['TGA','6'])
        self.assertEqual(rows[0][3],'1')
        self.assertEqual(rows[-1],['END','12'])
        plans=rows[1:-1]
        self.assertEqual([p[3] for p in plans],['8']*2+['6']*4+['5']*6)
        self.assertTrue(all(len(p)==14 for p in plans))
        self.assertEqual({(p[2],p[4],float(p[5])) for p in plans if p[3]=='6'},
                         {('INNER','BUY',4175),('INNER','SELL',4200),('OUTER','BUY',4150),('OUTER','SELL',4220)})
        self.assertTrue(all(p[4]=='AUTO' for p in plans if p[2]=='MAP'))

    def test_range_only_does_not_need_ai_to_guess_buy_or_sell(self):
        self.scene()
        with self.db:
            scene=state(self.db,'teacher_scene');scene['plans']=[]
            set_state(self.db,'teacher_scene',scene)
            setup=state(self.db,'deepseek_setup');setup.update(mode='WAIT',plans=[])
            set_state(self.db,'deepseek_setup',setup)
        rows=self.feed()
        self.assertEqual(rows[0][3],'1')
        self.assertEqual([r[3] for r in rows[1:-1]],['6']*4)

    def test_pending_teacher_pause_and_recovery(self):
        self.scene()
        self.seed(mid='next',text='取消多单参考',age=0)
        self.assertEqual(self.feed()[0][3],'0')
        self.assertEqual(self.feed(paused=True)[0][3],'0')
        self.assertEqual(self.feed(now=self.now+500)[0][3],'0')

    def test_edit_or_withdrawal_removes_ranges_not_replays_older_source(self):
        self.scene()
        scene=state(self.db,'teacher_scene')
        mid=scene['inner_range']['low']['message_id']
        raw=json.loads(self.db.execute('SELECT raw FROM messages WHERE message_id=?',(mid,)).fetchone()[0])
        ingest(self.db,self.c['chat_id'],[dict(raw,deleted=True)])
        self.assertFalse(any(r[2] in ('INNER','OUTER') for r in self.feed()[1:-1]))

    def test_heartbeat_and_target_updates_preserve_entry_id(self):
        self.scene()
        before=[r for r in self.feed()[1:-1] if r[2]=='DIRECT']
        with self.db:
            setup=state(self.db,'deepseek_setup')
            setup['plans'][0].setdefault('exits',{})['tp2']={'price':4300}
            set_state(self.db,'deepseek_setup',setup)
        after=[r for r in self.feed(now=self.now+2)[1:-1] if r[2]=='DIRECT']
        self.assertEqual([r[1] for r in before],[r[1] for r in after])
        self.assertNotEqual([r[12] for r in before],[r[12] for r in after])

    def test_maps_do_not_expire_by_message_age_and_repost_keeps_id(self):
        self.seed(mid='map',text='4150--4160--4175',age=1000)
        refresh_levels(self.db,self.c,self.now)
        process_ai_batch(self.db,self.c,Mock(),self.now)
        a=self.feed()
        self.seed(mid='repost',text='4150--4160--4175',age=0)
        refresh_levels(self.db,self.c,self.now)
        process_ai_batch(self.db,self.c,Mock(),self.now)
        b=self.feed()
        self.assertEqual(a[0][3],'1')
        self.assertEqual([r[1] for r in a[1:-1]],[r[1] for r in b[1:-1]])

    def test_history_and_students_do_not_generate_new_direction(self):
        self.c['teacher_only']=True
        self.seed(mid='student',text='4150多单',sender='ou_other')
        self.seed(mid='history',text='4150--4160--4175',historical=True)
        refresh_levels(self.db,self.c,self.now)
        self.assertEqual(self.feed()[-1],['END','0'])

    def test_v7_keeps_reference_when_paused_and_uses_original_range_time(self):
        self.scene()
        before=self.feed(protocol=7)
        self.assertTrue(all(len(r)==16 for r in before[1:-1]))
        self.assertEqual(before[0][:2],['TGA','7'])
        with self.db:
            scene=state(self.db,'teacher_scene')
            scene['created']+=100
            set_state(self.db,'teacher_scene',scene)
        after=self.feed(paused=True,protocol=7)
        self.assertEqual(after[0][3],'0')
        self.assertEqual([r[8] for r in before[1:-1]],[r[8] for r in after[1:-1]])
        self.assertEqual([r[14] for r in before[1:-1]],[r[14] for r in after[1:-1]])

    def test_v7_idle_heartbeat_and_target_update_do_not_renew(self):
        self.scene()
        before=self.feed(protocol=7)
        with self.db:
            setup=state(self.db,'deepseek_setup')
            setup['created']=self.now+1
            setup['plans'][0].setdefault('exits',{})['tp2']={'price':4300}
            set_state(self.db,'deepseek_setup',setup)
        after=self.feed(now=self.now+2,protocol=7)
        self.assertEqual([(r[1],r[8],r[14]) for r in before[1:-1]],[(r[1],r[8],r[14]) for r in after[1:-1]])

    def test_v7_expired_market_plan_remains_visible_for_ea(self):
        self.scene()
        with self.db:
            setup=state(self.db,'deepseek_setup')
            setup['plans'][0]['mode']='MARKET'
            setup['plans'][0]['origin_created']=self.now-90000
            setup['plans'][0]['confirmed_at']=self.now-90000
            set_state(self.db,'deepseek_setup',setup)
        rows=self.feed(protocol=7)
        market=next(r for r in rows[1:-1] if r[15]=='MARKET')
        self.assertEqual(int(market[14]),int(self.now-90000))

    def test_v7_map_not_hidden_by_pause_or_age(self):
        with self.db:
            set_state(self.db,'live_since',self.now-200000)
        self.seed(mid='map',text='4150--4160--4175',age=90000)
        refresh_levels(self.db,self.c,self.now)
        rows=self.feed(paused=True,protocol=7)
        self.assertEqual(rows[0][3],'0')
        self.assertEqual(len([r for r in rows[1:-1] if r[2]=='MAP']),3)

    def test_keep_explicit_confirmation_is_saved_and_revocation_disables(self):
        from teacher_scene import publish_scene
        self.scene()
        before=state(self.db,'deepseek_setup')
        original=self.seed(mid='confirm',text='75继续有效',age=0)
        row=self.db.execute('SELECT rowid AS sequence,* FROM messages WHERE message_id=?',('confirm',)).fetchone()
        keep=dict(action='KEEP',as_of='confirm',created=row['created'],sequence=row['sequence'],revision=row['revision'],
                  sender=row['sender'],source_refs=[dict(message_id='confirm',revision=row['revision'])],summary='重申')
        with self.db:
            publish_scene(self.db,self.c,keep)
        after=state(self.db,'deepseek_setup')
        self.assertGreater(after['plans'][0]['confirmed_at'],before['plans'][0]['confirmed_at'])
        self.assertEqual(after['plans'][1]['confirmed_at'],before['plans'][1]['confirmed_at'])
        self.assertEqual(after['plans'][0]['origin_id'],before['plans'][0]['origin_id'])
        with self.db:
            publish_scene(self.db,self.c,keep)
        self.assertEqual(state(self.db,'deepseek_setup'),after)
        ingest(self.db,self.c['chat_id'],[dict(original,deleted=True)])
        self.assertFalse(any(r[2]=='DIRECT' for r in self.feed(protocol=7)[1:-1]))


    def test_v7_ai_outage_keeps_verified_plans_without_renewing(self):
        self.scene()
        before=self.feed(protocol=7)
        self.seed(mid='pending',text='上去93可空',age=0)
        with self.db:
            set_state(self.db,'deepseek_status',dict(online=False,error='HTTP 503'))
        after=self.feed(protocol=7)
        self.assertEqual(after[0][3],'1')
        self.assertIn('沿用已确认点位',after[0][6])
        self.assertEqual(before[1:],after[1:])
        self.assertEqual(self.feed(protocol=6)[0][3],'0')  # 旧协议保持旧行为。

    def test_v7_pending_cancel_blocks_even_during_ai_outage(self):
        self.scene()
        for text in ('取消多单参考','暂停交易','这些点位作废'):
            with self.subTest(text=text):
                self.seed(mid='cancel',text=text,age=0)
                rows=self.feed(protocol=7)
                self.assertEqual(rows[0][3],'0')
                self.assertIn('撤销',rows[0][6])

    def test_v7_outage_cannot_bypass_manual_pause_sync_or_review(self):
        self.scene()
        self.seed(mid='pending',text='上去93可空',age=0)
        self.assertEqual(self.feed(paused=True,protocol=7)[0][3],'0')
        self.assertEqual(self.feed(now=self.now+500,protocol=7)[0][3],'0')
        with self.db:
            set_state(self.db,'deepseek_review',dict(message_id='pending',created=self.now))
        self.assertEqual(self.feed(protocol=7)[0][3],'0')

    def test_v7_no_confirmed_data_cannot_become_an_active_plan(self):
        self.seed(mid='pending',text='上去93可空',age=0)
        rows=self.feed(protocol=7)
        self.assertEqual(rows[0][3],'0')
        self.assertEqual(rows[-1],['END','0'])

    def test_v7_ai_outage_still_removes_withdrawn_source(self):
        self.scene()
        self.seed(mid='pending',text='上去93可空',age=0)
        mid=state(self.db,'teacher_scene')['inner_range']['low']['message_id']
        raw=json.loads(self.db.execute('SELECT raw FROM messages WHERE message_id=?',(mid,)).fetchone()[0])
        ingest(self.db,self.c['chat_id'],[dict(raw,deleted=True)])
        rows=self.feed(protocol=7)
        self.assertFalse(any(r[2] in ('INNER','OUTER') for r in rows[1:-1]))

    def test_v7_map_survives_ai_outage_with_original_identity_and_time(self):
        self.seed(mid='map',text='4150--4160--4175',age=100)
        refresh_levels(self.db,self.c,self.now)
        before=self.feed(protocol=7)
        self.seed(mid='pending',text='上去93可空',age=0)
        with self.db:
            set_state(self.db,'deepseek_status',dict(online=False,error='TimeoutError'))
        after=self.feed(protocol=7)
        self.assertEqual(after[0][3],'1')
        self.assertEqual(before[1:],after[1:])


    def new_map(self, text='4135--4142--4152--4170', mid='new-map', age=0):
        raw=self.seed(mid=mid,text=text,age=age)
        refresh_levels(self.db,self.c,self.now)
        return raw

    def test_v7_new_map_removes_older_outside_directions_while_ai_is_down(self):
        self.scene()
        self.new_map()
        with self.db:
            set_state(self.db,'deepseek_status',dict(online=False,error='HTTP 503'))
        rows=self.feed(protocol=7)
        self.assertEqual(rows[0][3],'1')
        self.assertFalse(any(r[2]=='DIRECT' for r in rows[1:-1]))
        self.assertEqual([float(r[5]) for r in rows[1:-1] if r[2]=='MAP'],[4135,4142,4152,4170])
        self.assertEqual(len(state(self.db,'map_retired_directions')['plans']),2)
        self.assertEqual(rows,self.feed(protocol=7))  # 重复导出不产生额外状态/机会。

    def test_v7_new_map_keeps_inside_and_boundary_directions(self):
        self.scene()
        self.new_map('4175--4180--4193')
        self.assertEqual(len([r for r in self.feed(protocol=7)[1:-1] if r[2]=='DIRECT']),2)
        self.new_map('4160--4180--4200',mid='inside-map',age=-1)
        self.assertEqual(len([r for r in self.feed(protocol=7)[1:-1] if r[2]=='DIRECT']),2)

    def test_v7_older_or_same_time_map_cannot_remove_newer_direction(self):
        self.scene()
        self.new_map(age=50)
        self.assertEqual(len([r for r in self.feed(protocol=7)[1:-1] if r[2]=='DIRECT']),2)
        with self.db:
            setup=state(self.db,'deepseek_setup')
            for plan in setup['plans']:
                plan['confirmed_at']=self.now
            set_state(self.db,'deepseek_setup',setup)
        self.new_map(mid='equal-map')
        self.assertEqual(len([r for r in self.feed(protocol=7)[1:-1] if r[2]=='DIRECT']),2)

    def test_v7_removed_plan_stays_removed_after_reopen_and_wider_map(self):
        from store import connect
        self.scene()
        self.new_map()
        self.feed(protocol=7)
        path=self.db.execute('PRAGMA database_list').fetchone()[2]
        self.db.close()
        self.db=connect(path)
        self.new_map('4100--4175--4220',mid='wide-map',age=-1)
        rows=self.feed(protocol=7)
        self.assertFalse(any(r[2]=='DIRECT' for r in rows[1:-1]))
        # 更晚明确重申同一计划后可重新使用，原始消息时间不改。
        with self.db:
            setup=state(self.db,'deepseek_setup')
            setup['plans'][0]['confirmed_at']=self.now+2
            set_state(self.db,'deepseek_setup',setup)
        direct=[r for r in self.feed(now=self.now+2,protocol=7)[1:-1] if r[2]=='DIRECT']
        self.assertEqual(len(direct),1)
        self.assertEqual(float(direct[0][5]),4175)

    def test_v7_newer_outside_direction_can_be_added_after_map(self):
        self.scene()
        self.new_map()
        self.feed(protocol=7)
        with self.db:
            setup=state(self.db,'deepseek_setup')
            setup['plans'][0].update(origin_id='new-direction',origin_revision='new',
                                    origin_created=self.now+1,confirmed_at=self.now+1)
            set_state(self.db,'deepseek_setup',setup)
        self.assertEqual(len([r for r in self.feed(now=self.now+1,protocol=7)[1:-1] if r[2]=='DIRECT']),1)

    def test_v7_historical_or_withdrawn_map_cannot_retire_directions(self):
        self.scene()
        self.seed(mid='historical-map',text='4135--4142--4152--4170',historical=True,age=0)
        refresh_levels(self.db,self.c,self.now)
        self.assertEqual(len([r for r in self.feed(protocol=7)[1:-1] if r[2]=='DIRECT']),2)
        raw=self.new_map(mid='withdrawn',age=-1)
        ingest(self.db,self.c['chat_id'],[dict(raw,deleted=True)])
        refresh_levels(self.db,self.c,self.now)
        self.assertEqual(len([r for r in self.feed(protocol=7)[1:-1] if r[2]=='DIRECT']),2)


if __name__=='__main__':
    unittest.main()
