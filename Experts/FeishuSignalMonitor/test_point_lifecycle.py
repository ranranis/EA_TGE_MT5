"""隔离数据库验证TGA9点位生命周期；不写真实信号文件。"""
import copy
import unittest
from store import state,set_state,ingest
from point_lifecycle import lifecycle_rows,expiry,select_rows
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
        self.assertEqual(feed[0][2],'ROLE');self.assertEqual(feed[0][17],2)
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

class PointSelectionTests(unittest.TestCase):
    setUp=PointLifecycleTests.setUp
    tearDown=PointLifecycleTests.tearDown
    seed=PointLifecycleTests.seed
    row=PointLifecycleTests.row
    feed=PointLifecycleTests.feed
    def select(self,rows,mid=4176,now=None,bar=100,market=True,persist=True):
        now=self.now if now is None else now
        with self.db:
            set_state(self.db,'teacher_analysis',dict(market_ok=market,
                quote=dict(symbol=self.c['symbols'][self.c['teacher_symbol']],bid=mid-.1,ask=mid+.1,at=now),
                bars=[dict(at=bar)]))
        return select_rows(self.db,self.c,self.feed(rows,now,persist=persist),now,persist)

    def test_new_near_price_wins_without_chain_merge(self):
        rows=[self.row(str(p),kind='MAP',side='AUTO',price=p,age=60) for p in (4170,4175,4180,4190)]
        rows.append(self.row('new',kind='ROLE',price=4182,age=1))
        selected,value=self.select(rows)
        self.assertEqual([float(r[5]) for r in selected],[4170,4175,4182,4190])
        self.assertIn('不足5点',next(p for p in value['items'] if p['price']==4180)['reason'])

    def test_total_limit_two_sides_and_overflow(self):
        rows=[self.row(str(p),'MAP','AUTO',p) for p in range(4130,4231,10)]
        picked,_=self.select(rows,4181)
        self.assertEqual([float(r[5]) for r in picked],[4160,4170,4180,4190,4200,4210])
        picked,_=self.select(rows,mid=4300,bar=200)
        self.assertEqual(len(picked),6)
        self.assertTrue(all(float(b[5])-float(a[5])>=5 for a,b in zip(picked,picked[1:])))

    def test_authority_manual_and_equal_time_conflict(self):
        teacher=self.row('teacher','ROLE','BUY',4180,age=100)
        group=self.row('group','DIRECT','SELL',4182,age=1,sender='member')
        self.assertEqual([float(r[5]) for r in self.select([teacher,group])[0]],[4180])
        manual=list(group);manual[1]='manual';manual[6]='MANUAL'
        self.assertEqual([float(r[5]) for r in self.select([teacher,manual])[0]],[4182])
        other=self.row('other','ROLE','SELL',4182,age=100)
        picked,value=self.select([teacher,other])
        self.assertEqual(picked,[])
        self.assertTrue(all('冲突' in p['reason'] for p in value['items']))

    def test_heartbeat_restart_and_m5_hysteresis(self):
        rows=[self.row(str(p),'MAP','AUTO',p) for p in range(4130,4231,10)]
        first,value=self.select(rows,4181,bar=100)
        saved=state(self.db,'point_selection')
        second,_=self.select(rows,4182,now=self.now+1,bar=100)
        self.assertEqual(first,second);self.assertEqual(saved,state(self.db,'point_selection'))
        # 跨到下一价位附近，但新点仅近2点：不在新M5立即来回换。
        third,_=self.select(rows,4191,now=self.now+2,bar=200)
        self.assertEqual(first,third)
        fourth,_=self.select(rows,4194,now=self.now+3,bar=300)
        self.assertEqual([float(r[5]) for r in fourth],[4170,4180,4190,4200,4210,4220])
        self.assertTrue(state(self.db,'point_selection')['events'])

    def test_expiry_watch_and_no_quote(self):
        watch=self.row('watch','WATCH','AUTO',4175,age=90000);watch[3]=0
        fresh=self.row('fresh','ROLE','BUY',4180,age=1)
        picked,value=self.select([watch,fresh],market=False)
        self.assertEqual([float(r[5]) for r in picked],[4180])
        self.assertFalse(value['quote_ready'])
        self.assertIn('暂停新单',value['items'][1]['reason'])
        picked,_=self.select([watch,fresh])
        self.assertEqual([float(r[5]) for r in picked],[4180])
        self.assertEqual(expiry(watch,'',None),watch[14]+86400)
        picked,_=self.select([watch,fresh],now=self.now+86401,market=False)
        self.assertEqual(picked,[])

    def test_new_message_during_quote_loss_selects_on_first_return_same_bar(self):
        old=self.row('old',price=4180,age=60)
        new=self.row('new',price=4182,age=1)
        self.select([old],bar=100)
        picked,value=self.select([old,new],bar=100,market=False)
        self.assertEqual([float(r[5]) for r in picked],[4182])
        self.assertFalse(value['quote_ready'])
        picked,_=self.select([old,new],bar=100)
        self.assertEqual([float(r[5]) for r in picked],[4182])
        self.assertFalse(state(self.db,'point_selection')['pending'])

    def test_manual_correction_resolves_older_near_conflict(self):
        a=self.row('a','ROLE','BUY',4180,age=60)
        b=self.row('b','ROLE','SELL',4182,age=60)
        override=self.row('manual','ROLE','BUY',4181,age=1);override[6]='MANUAL'
        picked,_=self.select([a,b,override])
        self.assertEqual([float(r[5]) for r in picked],[4181])

    def test_large_candidate_pool_retires_to_six_not_whole_feed_error(self):
        rows=[self.row(str(p),'MAP','AUTO',p) for p in range(4000,4400,5)]
        picked,_=self.select(rows,mid=4180)
        self.assertEqual(len(picked),6)

    def test_quote_loss_without_new_sources_keeps_display_stable(self):
        rows=[self.row(str(p),'MAP','AUTO',p) for p in range(4130,4231,5)]
        original,_=self.select(rows,mid=4150)
        for i in range(3):
            shown,value=self.select(rows,mid=4300,now=self.now+i+1,market=False)
            self.assertEqual(original,shown)
            self.assertFalse(value['quote_ready'])

    def test_no_quote_first_start_still_displays_six_spaced_current_points(self):
        rows=[self.row(str(p),'MAP','AUTO',p,age=4400-p) for p in range(4130,4231,5)]
        picked,value=self.select(rows,mid=1,market=False)
        prices=[float(r[5]) for r in picked]
        self.assertEqual(len(prices),6)
        self.assertEqual(prices,[4205,4210,4215,4220,4225,4230])
        self.assertTrue(all(b-a>=5 for a,b in zip(prices,prices[1:])))
        self.assertTrue(value['pending']);self.assertFalse(value['quote_ready'])
        restored,_=select_rows(self.db,self.c,self.feed(rows),self.now)
        self.assertEqual(picked,restored)
        # 恢复报价不必等待下一M5，即按现价重新筛选。
        after,value=self.select(rows,mid=4150,bar=100)
        self.assertTrue(value['quote_ready']);self.assertFalse(value['pending'])
        self.assertNotEqual(prices,[float(r[5]) for r in after])

    def test_preview_does_not_change_selection_or_log(self):
        row=self.row();self.select([row])
        before=state(self.db,'point_selection')
        self.select([row,self.row('new',price=4182,age=1)],persist=False)
        self.assertEqual(state(self.db,'point_selection'),before)

if __name__=='__main__':unittest.main()
