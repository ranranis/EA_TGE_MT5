import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from deepseek_ai import AIError, create_ai_client, DeepSeek
from workbuddy_ai import WorkBuddy


class WorkBuddyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.exe = self.root/'WorkBuddy.exe'
        self.exe.touch()
        folder = self.root/'resources/app.asar.unpacked/cli'
        (folder/'bin').mkdir(parents=True)
        (folder/'bin/codebuddy').touch()
        (folder/'product.json').write_text('{}', encoding='utf-8')
        self.config = dict(ai_provider='workbuddy', ai_model='glm-5.3',
                           workbuddy_executable=str(self.exe), teacher_only=True)
        self.client = create_ai_client(self.root, self.config)
        self.payload = dict(messages=[dict(content='系统约束'), dict(content='群消息')])

    def tearDown(self):
        self.temp.cleanup()

    def result(self, value='{"interpretations":[]}', **kwargs):
        obj=dict(type='result', subtype='success', is_error=False, result=value)
        obj.update(kwargs)
        return subprocess.CompletedProcess([], 0, json.dumps([dict(type='message'), obj]), '')

    def test_inference_has_no_tools_or_connections_and_no_shell(self):
        def run(command, **kwargs):
            self.assertEqual(command[command.index('--tools')+1], '')
            self.assertEqual(command[command.index('--setting-sources')+1], '')
            self.assertEqual(command[command.index('--mcp-config')+1], '{"mcpServers":{}}')
            self.assertIn('--strict-mcp-config', command)
            self.assertIn('--no-session-persistence', command)
            self.assertNotIn('shell', kwargs)
            self.assertEqual(kwargs['input'], '群消息')
            self.assertNotIn('群消息', command)
            prompt=Path(command[command.index('--system-prompt-file')+1])
            self.assertIn('系统约束', prompt.read_text(encoding='utf-8'))
            self.assertNotEqual(Path(kwargs['cwd']), Path.cwd())
            self.assertEqual(kwargs['env']['CODEBUDDY_CONFIG_DIR'], str(Path.home()/'.workbuddy'))
            return self.result()
        with patch('workbuddy_ai.subprocess.run', side_effect=run):
            self.assertEqual(self.client.request('/chat/completions', self.payload)['choices'][0]['finish_reason'], 'stop')

    def test_error_in_result_cannot_be_published_as_success(self):
        for value in [self.result(is_error=True), self.result(subtype='error_max_turns'),
                      self.result(value=chr(96)*3+'json {}'+chr(96)*3), self.result(value='[]'),
                      subprocess.CompletedProcess([], 1, 'private chat', 'secret')]:
            with self.subTest(value=value.returncode), patch('workbuddy_ai.subprocess.run', return_value=value):
                with self.assertRaises(AIError) as cm:
                    self.client.request('/chat/completions', self.payload)
                self.assertNotIn('secret', str(cm.exception))
                self.assertNotIn('private chat', str(cm.exception))

    def test_timeout_or_missing_install_keeps_failure_explicit(self):
        with patch('workbuddy_ai.subprocess.run', side_effect=subprocess.TimeoutExpired('cli',90)):
            with self.assertRaisesRegex(AIError,'超时'):
                self.client.request('/chat/completions', self.payload)
        self.exe.unlink()
        with self.assertRaisesRegex(AIError,'安装目录'):
            self.client.request('/chat/completions', self.payload)

    def test_shared_alias_mapping_and_direction_validation_are_preserved(self):
        target=dict(id='0', message_id='om_real_long_message_123',source_role='teacher',
                    sender_id='teacher',time='2026-10-17T10:00:00Z',text='4180空', historical=False)
        result=dict(interpretations=[dict(id='0',kind='SETUP',
                    plans=[dict(side='SELL',token='4180',price=4180,mode='REACTION',evidence='4180空')],
                    cancel_side='NONE',reason='明确空')],
                    scene=dict(as_of='r001'))
        with patch('workbuddy_ai.subprocess.run', return_value=self.result(json.dumps(result))):
            value=self.client.interpret([target], [], 4170, [])
        self.assertEqual(value['scene']['as_of'],target['message_id'])
        result['scene']['as_of']='made_up'
        with patch('workbuddy_ai.subprocess.run', return_value=self.result(json.dumps(result))):
            with self.assertRaisesRegex(AIError,'未知消息'):
                self.client.interpret([target], [], 4170, [])

    def test_market_snapshot_reaches_workbuddy_without_changing_message_anchor(self):
        self.client.current_market=dict(fresh=False,mid=None,quote=dict(bid=4164),bars=[])
        def run(command,**kwargs):
            data=json.loads(kwargs['input'])
            self.assertEqual(data['market_anchor'],4180)
            self.assertFalse(data['current_market']['fresh'])
            self.assertIsNone(data['current_market']['mid'])
            prompt=Path(command[command.index('--system-prompt-file')+1]).read_text(encoding='utf-8')
            self.assertIn('不能补造点位',prompt)
            return self.result()
        with patch('workbuddy_ai.subprocess.run',side_effect=run):
            self.client.interpret([],[],4180,[])

    def test_existing_deepseek_config_keeps_original_provider(self):
        self.assertIsInstance(create_ai_client(self.root, dict(ai_model='deepseek-flash')), DeepSeek)
        self.assertIsInstance(self.client, WorkBuddy)

    def test_batch_size_is_configurable_without_combining_source_lanes(self):
        from test_deepseek_ai import WorkerTests
        from deepseek_ai import pending_rows
        f=WorkerTests();f.setUp()
        try:
            f.c['ai_batch_messages']=16
            for i in range(20): f.seed(mid='t'+str(i),age=30-i)
            self.assertEqual(len(pending_rows(f.db,f.c,f.now)),16)
            f.c['ai_batch_messages']=8
            self.assertEqual(len(pending_rows(f.db,f.c,f.now)),8)
        finally: f.tearDown()

    def test_extended_context_includes_approved_summary_but_not_member_chat(self):
        from test_deepseek_ai import WorkerTests
        from deepseek_ai import process_ai_batch
        from unittest.mock import Mock
        f=WorkerTests();f.setUp()
        try:
            f.c['ai_context_messages']=96
            f.c['teacher_only']=True
            for i in range(70): f.seed(mid='old'+str(i),age=200-i,text='保持观察')
            f.seed(mid='summary',age=90,sender='ou_summary',
                   text='会议总结：小区间4120-4180，接近4120↑，接近4180↓')
            f.seed(mid='member',age=80,sender='ou_member',text='我自己觉得4180空')
            f.seed(mid='new',age=1,text='4170附近观察')
            seen={}
            def capture(targets,context,*args,**kw):
                seen['context']=context
                raise AIError('capture only')
            with self.assertRaisesRegex(AIError,'capture only'):
                process_ai_batch(f.db,f.c,Mock(interpret=capture),f.now,preview=True)
            rows=seen['context']
            self.assertGreater(len(rows),56)
            self.assertNotIn('member',[r['message_id'] for r in rows])
            summary=next(r for r in rows if r['message_id']=='summary')
            self.assertEqual(summary['source_role'],'group_summary')
        finally: f.tearDown()

    def test_provider_and_read_limits_are_checked_in_config(self):
        from app import config_load
        home=self.root/'monitor'
        config_load(home)
        p=home/'config/config.json'
        for values in [dict(ai_provider='invalid'),dict(ai_context_messages=10000),
                       dict(ai_batch_messages=True),dict(ai_provider='workbuddy',ai_model='glm-5.3',workbuddy_executable='missing')]:
            p.write_text(json.dumps(values),encoding='utf-8')
            with self.assertRaises(ValueError): config_load(home)
        p.write_text(json.dumps(self.config),encoding='utf-8')
        self.assertEqual(config_load(home)['ai_provider'],'workbuddy')


if __name__ == '__main__':
    unittest.main()
