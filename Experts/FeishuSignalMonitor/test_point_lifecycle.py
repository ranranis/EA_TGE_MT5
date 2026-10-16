"""隔离数据库验证TGA9点位生命周期；不写真实信号文件。"""
import copy
import unittest
from store import state,set_state,ingest
from point_lifecycle import lifecycle_rows,expiry
from point_editor import prepare_applied,empty_draft,merge_rows,validate_draft
import test_deepseek_ai as fixtures

class PointLifecycleTests(unittest.TestCase):
    setUp=fixtures.WorkerTests.setUp
    tearDown=fixtures.WorkerTests.tearDown
    seed=fixtures.WorkerTests.seed

    def row(self,mid='old',kind='DIRECT',side='SELL',price=4180,age=60,sender=None):
        raw=self.seed(mid=mid,text=str(price)+('支撑' if side=='BUY' else '压力'),age=age,**({'sender':sender} if sender else {}))
        dbrow=self.db.execute('SELECT * FROM messages WHERE message_id=?',(mid,)).fetchone()
        return ['PLAN',mid,kind,100 if kind=='DIRECT' else 60 if kind=='ROLE' else 40 if kind=='MAP' else 70,side,
                str(price),mid,dbrow['revision'],int(dbrow['created']),'group-'+mid,*['0']*4,int(dbrow['created']),'REACTION' if kind=='DIRECT' else 'REFERENCE']

    def feed(self,rows,now=None,**kwargs):
        return lifecycle_rows(self.db,self.c,rows,self.now if now is None else now,**kwargs)

    def test_same_side_one_candidate_with_two_independent_expiries(self):
        old=self.row(age=86000);new=self.row('new','ROLE',age=10)
        feed=self.feed([old,new]);self.assertEqual(len(feed),1)
        self.assertEqual(feed[0][2],'DIRECT');self.assertEqual(feed[0][17],2)
        after=self.feed([old,new],self.now+500)
        self.assertEqual(after[0][2],'ROLE')
        sources=state(self.db,'point_lifecycle')['points'][0]['sources']
        self.assertEqual([s['state'] for s in sources],['EXPIRED','READY'])

    def test_new_teacher_direction_beats_old_priority_and_does_not_revive(self):
        old=self.row();new=self.row('new','ROLE','BUY',age=1)
        self.assertEqual(self.feed([old,new])[0][4],'BUY')
        # 来源消失后旧反向计划仍已退役，不能从旧快照复活。
        result=self.feed([old])
        self.assertEqual(result[0][18],'REPLACED')
        self.assertEqual(result[0][2],'WATCH')

    def test_new_group_opinion_does_not_override_teacher(self):
        old=self.row();new=self.row('new','ROLE','BUY',age=1,sender='member')
        self.assertEqual(self.feed([old,new])[0][18],'CONFLICT')

    def test_simultaneous_opposite_source_conflict_is_watch(self):
        old=self.row()
        other=copy.deepcopy(old);other[1]='opposite';other[4]='BUY'
        self.assertEqual(self.feed([old,other])[0][18],'CONFLICT')

    def test_expired_direction_cannot_fall_back_to_neutral_map(self):
        old=self.row(age=90000);neutral=self.row('map','MAP','AUTO',age=10)
        self.assertEqual(self.feed([old,neutral])[0][2],'WATCH')

    def test_scoped_and_whole_cancel_preserved_after_withdrawal(self):
        a=self.row();b=self.row('b',price=4190)
        raw=self.seed(mid='cancel',text='4180空取消',age=0)
        feed=self.feed([a,b])
        self.assertEqual([(float(r[5]),r[18]) for r in feed],[(4180,'CANCELLED'),(4190,'READY')])
        ingest(self.db,self.c['chat_id'],[dict(raw,deleted=True)])
        self.assertEqual(self.feed([a,b])[0][18],'CANCELLED')
        self.seed(mid='all',text='之前的点位全部作废，今天以这组为准',age=0)
        self.assertTrue(all(r[18]=='CANCELLED' for r in self.feed([a,b])))

    def test_explicit_range_duration_not_shared_with_short_term_direction(self):
        r=self.row(kind='INNER')
        self.assertEqual(expiry(r,'接下来半个月，黄金区间震荡',None),r[14]+15*86400)
        r[2]='DIRECT'
        self.assertEqual(expiry(r,'接下来半个月，黄金区间震荡',None),r[14]+86400)

    def test_renewal_and_notes_do_not_change_execution_identity(self):
        d=empty_draft();d['levels']=[dict(id='a',price=4180,role='sell',note='',replaces=[],hours=8)]
        auto=dict(symbol='XAUUSD.c',revision='a',rows=[])
        a=prepare_applied(validate_draft(d,self.c),auto,None,self.now)
        first=merge_rows([],a)[0]
        d['levels'][0]['note']='仅改备注'
        b=prepare_applied(validate_draft(d,self.c),auto,a,self.now+10)
        self.assertEqual(first[14],merge_rows([],b)[0][14])
        d['levels'][0]['renew']=True
        c=prepare_applied(validate_draft(d,self.c),auto,b,self.now+20)
        renewed=merge_rows([],c)[0]
        self.assertEqual(first[1],renewed[1]);self.assertGreater(renewed[14],first[14])
        self.assertFalse(c['draft']['levels'][0]['renew'])
        self.assertEqual(expiry(renewed,'',c),renewed[14]+8*3600)

    def test_preview_is_read_only_and_heartbeat_does_not_duplicate_events(self):
        r=self.row()
        self.feed([r],persist=False)
        self.assertIsNone(state(self.db,'point_lifecycle'))
        self.feed([r]);before=state(self.db,'point_lifecycle')
        self.feed([r],self.now+1)
        self.assertEqual(before,state(self.db,'point_lifecycle'))
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

    def test_removal_logged_and_no_rows_recreated(self):
        r=self.row()
        self.feed([r]);self.assertEqual(self.feed([]),[])
        self.assertEqual(state(self.db,'point_lifecycle')['events'][-1]['state'],'REMOVED')

if __name__=='__main__':unittest.main()
