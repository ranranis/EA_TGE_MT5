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

    def feed(self, paused=False, now=None):
        export_teacher_levels(self.db, self.c, paused, self.now if now is None else now)
        p = self.home/'common/FeishuMT5SignalMonitor/tge_execution.csv'
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


if __name__=='__main__':
    unittest.main()
