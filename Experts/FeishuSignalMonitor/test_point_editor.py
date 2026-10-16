"""临时数据库/合成消息，不调用真实DeepSeek、飞书或MT5交易。"""
import copy
import json
import re
import time
import unittest
import urllib.request
import urllib.error
from unittest.mock import Mock, patch

import test_plan_preview as preview_fixture
from point_editor import empty_draft, validate_draft, merge_rows, prepare_applied, editor_action, editor_view, parse_text, remember_auto
from app import export_teacher_levels
from dashboard import serve, snapshot
from store import state, set_state, ingest
from deepseek_ai import AIError


class EditorTests(unittest.TestCase):
    setUp=preview_fixture.PreviewTests.setUp
    tearDown=preview_fixture.PreviewTests.tearDown
    reply=preview_fixture.PreviewTests.reply

    def export(self, paused=False):
        export_teacher_levels(self.db,self.c,paused,self.now)
        return snapshot(self.home,self.c)['execution_reference']

    def save(self,draft):
        return editor_action(self.home,self.c,dict(action='save',revision=state(self.db,'point_editor',{}).get('revision',0),draft=draft),self.now)

    def apply(self,action='apply'):
        return editor_action(self.home,self.c,dict(action=action,revision=state(self.db,'point_editor')['revision'],
                            auto_revision=state(self.db,'point_editor_auto')['revision'],confirmed=True),self.now)

    def draft(self):
        d=empty_draft();d['levels']=[dict(id='one',price=4170,role='minor_resistance',note='小压力',replaces=[4175])];return d

    def test_save_is_draft_only_apply_replaces_source_and_undo_restores_auto(self):
        before=self.export();self.save(self.draft())
        self.assertEqual(self.export()['plans'],before['plans'])
        self.apply();plans=self.export()['plans']
        self.assertEqual([(p['price'],p['side'],p['kind']) for p in plans],[(4170,'SELL','ROLE')])
        self.assertEqual(plans[0]['source_id'],'MANUAL')
        self.apply('undo');self.assertEqual([p['price'] for p in self.export()['plans']],[4175])
        self.assertFalse(editor_view(self.db,self.c)['can_undo'])
        self.assertEqual(self.db.execute('SELECT count(*) FROM orders').fetchone()[0],0)

    def test_repeat_export_does_not_revive_disabled_price(self):
        self.export();d=empty_draft();d['disabled']=[4175];self.save(d);self.apply()
        self.assertTrue(all(p['kind']=='WATCH' and p['life_state']=='DISABLED' for p in self.export()['plans']))
        self.now+=2;self.assertTrue(all(p['kind']=='WATCH' and p['life_state']=='DISABLED' for p in self.export()['plans']))
        self.db.close()
        from store import connect
        self.db=connect(self.home/'data/monitor.sqlite')
        self.assertTrue(all(p['kind']=='WATCH' and p['life_state']=='DISABLED' for p in self.export()['plans']))

    def test_recover_one_auto_keeps_other_manual_additions(self):
        self.export();d=self.draft();d['levels'].append(dict(id='two',price=4190,role='neutral',note='',replaces=[]))
        self.save(d);self.apply();self.assertEqual({p['price'] for p in self.export()['plans']},{4170,4190})
        d['levels'].pop(0);self.save(d);self.apply();self.assertEqual({p['price'] for p in self.export()['plans']},{4175,4190})

    def test_unmodified_confirm_time_survives_save_and_undo(self):
        self.export();d=self.draft();self.save(d);self.apply();first=self.export()['plans'][0]
        self.now+=10;d['levels'][0]['note']='改备注';self.save(d);self.apply();second=self.export()['plans'][0]
        self.assertEqual(first['confirmed'],second['confirmed']);self.assertEqual(first['id'],second['id'])
        d['levels'][0]['price']=4171;self.save(d);self.apply();self.assertNotEqual(self.export()['plans'][0]['id'],first['id'])
        self.apply('undo');self.assertEqual(self.export()['plans'][0]['confirmed'],first['confirmed'])

    def test_cas_rejects_stale_browser_and_source_version(self):
        self.export();v=self.save(self.draft())
        with self.assertRaises(AIError):editor_action(self.home,self.c,dict(action='save',revision=0,draft=empty_draft()),self.now)
        old=v['auto']['revision'];auto=copy.deepcopy(v['auto']['rows']);auto[0][7]='new-source'
        remember_auto(self.db,self.c,auto)
        with self.assertRaises(AIError):editor_action(self.home,self.c,dict(action='apply',revision=v['revision'],auto_revision=old,confirmed=True),self.now)
        self.assertNotIn('applied',state(self.db,'point_editor'))

    def test_source_updates_keep_manual_and_flag_review(self):
        self.export();self.save(self.draft());self.apply()
        auto=state(self.db,'point_editor_auto')['rows'];auto[0][7]='updated'
        remember_auto(self.db,self.c,auto)
        v=editor_view(self.db,self.c);self.assertTrue(v['changed'])
        self.assertEqual(float(v['preview_rows'][0][5]),4170)

    def test_all_auto_and_all_manual_modes(self):
        self.export();d=self.draft();d['levels'][0]['replaces']=[];d['mode']='manual'
        self.save(d);self.apply();self.assertEqual([p['price'] for p in self.export()['plans']],[4170])
        d['mode']='auto';self.save(d);self.apply();self.assertEqual([p['price'] for p in self.export()['plans']],[4175])

    def test_invalid_draft_and_empty_manual_rejected(self):
        self.export()
        for change in [lambda d:d['levels'][0].update(price=True),lambda d:d['levels'][0].update(price=70),
                       lambda d:d['levels'][0].update(price=float('nan')),lambda d:d['levels'][0].update(role='oops'),
                       lambda d:d['levels'].append(copy.deepcopy(d['levels'][0])),lambda d:d.update(disabled=[4170]),
                       lambda d:d.update(inner_range=dict(action='replace',low=4180,high=4120))]:
            d=self.draft();change(d)
            with self.assertRaises((ValueError,TypeError)):self.save(d)
        with self.assertRaises(ValueError):self.save(dict(empty_draft(),mode='manual'))
        self.assertEqual(state(self.db,'point_editor',{}),{})

    def test_ranges_and_watch_override(self):
        self.export();d=empty_draft();d['inner_range']=dict(action='replace',low=4120,high=4180)
        d['outer_range']=dict(action='replace',low=4100,high=4200)
        d['levels']=[dict(id='watch',price=4180,role='watch',note='',replaces=[])]
        self.save(d);self.apply();plans=self.export()['plans']
        self.assertTrue(any(p['kind']=='INNER' and p['side']=='BUY' and p['price']==4120 for p in plans))
        self.assertTrue(all(p['kind']=='WATCH' for p in plans if p['price']==4180))
        self.assertTrue(any(p['kind']=='OUTER' and p['side']=='SELL' and p['price']==4200 for p in plans))

    def test_inherited_outer_range_checked_with_manual_inner(self):
        self.export();auto=state(self.db,'point_editor_auto');r=auto['rows'][0]
        auto['rows']=[list(r[:2])+['OUTER',75,'BUY','4100']+r[6:],list(r[:2])+['OUTER',75,'SELL','4200']+r[6:]]
        remember_auto(self.db,self.c,auto['rows']);d=empty_draft();d['inner_range']=dict(action='replace',low=4000,high=4180)
        v=self.save(d);self.assertIn('区间',v['preview_error'])
        with self.assertRaises(ValueError):self.apply()

    def test_manual_respects_pause_health_and_new_teacher_cancel(self):
        self.export();d=self.draft();d['levels'][0].update(price=4175,role='buy');self.save(d);self.apply()
        self.assertFalse(self.export(True)['active'])
        with self.db:set_state(self.db,'last_sync_ok',False)
        with self.assertRaises(AIError):self.apply()
        with self.db:set_state(self.db,'last_sync_ok',True)
        ingest(self.db,'test',[dict(self.message,message_id='cancel',content='4175多取消',create_time=self.now+2)])
        self.now+=3;plans=self.export()['plans'];self.assertTrue(plans)
        self.assertTrue(all(p['kind']=='WATCH' for p in plans if p['price']==4175))

    def test_disabled_manual_and_changed_symbol_block_apply(self):
        self.export();self.save(self.draft());self.c['manual_points_enabled']=False
        with self.assertRaises(AIError):self.apply()
        self.c['manual_points_enabled']=True;self.apply()
        self.c['symbols'][self.c['teacher_symbol']]='XAUUSD-other'
        self.assertFalse(self.export()['active'])

    def test_old_manual_file_is_untouched_and_web_auto_overrides_only_after_apply(self):
        self.export();path=self.home/'config/manual_points.json';original=path.read_bytes()
        self.save(dict(empty_draft(),mode='auto'));self.apply();self.export()
        self.assertEqual(path.read_bytes(),original)

    def test_merge_limit_prevents_silent_truncation(self):
        self.export();auto=state(self.db,'point_editor_auto');r=auto['rows'][0]
        auto['rows']=[list(r[:5])+[str(4100+i)]+r[6:] for i in range(64)]
        d=self.draft();d['levels'][0]['replaces']=[]
        with self.assertRaises(ValueError):merge_rows(auto['rows'],prepare_applied(d,auto,None,self.now))

    def test_parse_only_returns_editable_draft_and_rejects_invented_price(self):
        result=dict(levels=[dict(price=4170,role='minor_resistance',note='4170小压力')],inner_range=[4120,4180],outer_range=None)
        client=Mock(request=Mock(return_value={'choices':[dict(finish_reason='stop',message={'content':json.dumps(result)})]}))
        before=state(self.db,'point_editor',{});text='4170小压力，小区间4120—4180'
        parsed=parse_text(self.home,self.c,dict(text=text),client)
        self.assertEqual(parsed['draft']['levels'][0]['role'],'minor_resistance')
        self.assertEqual(state(self.db,'point_editor',{}),before)
        with self.assertRaises(AIError):parse_text(self.home,self.c,dict(text='4160小压力'),client)
        client.request.return_value['choices'][0]['finish_reason']='length'
        with self.assertRaises(AIError):parse_text(self.home,self.c,dict(text=text),client)

    def test_http_token_origin_limits_and_actual_apply(self):
        self.export();server=serve(self.home,dict(self.c,dashboard_port=0));base=f'http://127.0.0.1:{server.server_port}'
        try:
            html=urllib.request.urlopen(base).read().decode('utf-8')
            token=re.search("const actionToken='([^']+)'",html)[1]
            headers={'Origin':base,'Content-Type':'application/json','X-Local-Token':token}
            def request(path,body,head=headers):
                return urllib.request.urlopen(urllib.request.Request(base+path,data=json.dumps(body).encode('utf-8'),headers=head))
            payload=dict(action='save',revision=0,draft=self.draft())
            for bad in [headers|{'Origin':'https://example.org'},headers|{'X-Local-Token':'bad'}]:
                with self.assertRaises(urllib.error.HTTPError) as ex:request('/api/points',payload,bad)
                self.assertEqual(ex.exception.code,403)
            with request('/api/points',payload) as response:v=json.load(response)
            with request('/api/points',dict(action='apply',revision=v['revision'],auto_revision=v['auto']['revision'],confirmed=True)) as response:
                self.assertIsNotNone(json.load(response)['applied'])
            self.assertIn(b'renderPointEditor',urllib.request.urlopen(base+'/point-editor.js').read())
            self.assertEqual(self.export()['plans'][0]['price'],4170)
        finally:server.shutdown();server.server_close()


if __name__=='__main__':
    import sys
    if '--serve-preview' in sys.argv:
        fixture=EditorTests();fixture.setUp();fixture.export()
        server=serve(fixture.home,dict(fixture.c,dashboard_port=0))
        print(f'PREVIEW http://127.0.0.1:{server.server_port}/#point-editor',flush=True)
        try:
            while True:time.sleep(1)
        finally:server.shutdown();server.server_close();fixture.tearDown()
    else:unittest.main()
