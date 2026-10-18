"""停止控制在临时目录测试；不关闭真实MT5或运行真实任务计划。"""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import app


class StopAllTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.home=Path(self.temp.name)
        for folder in ('control','data'): (self.home/folder).mkdir()

    def tearDown(self): self.temp.cleanup()

    def test_waits_for_both_locks_before_closing(self):
        events=[]
        class Lock:
            def __init__(self,home,name='instance.lock'): self.name=name
            def __enter__(self): events.append('lock '+self.name); return self
            def __exit__(self,*args): events.append('unlock '+self.name)
        def close(path):
            self.assertTrue((self.home/'control/off').exists())
            self.assertTrue((self.home/'control/stop').exists())
            events.append('close')
        with patch('app.InstanceLock',Lock),patch('app.close_mt5',side_effect=close):
            app.stop_all(self.home,{'mt5_terminal_path':'target'})
        self.assertEqual(events,['lock service.lock','lock instance.lock','close',
                                 'unlock instance.lock','unlock service.lock'])

    def test_busy_monitor_does_not_close_mt5(self):
        with patch('app.InstanceLock',side_effect=RuntimeError('busy')),patch('app.close_mt5') as close:
            with self.assertRaisesRegex(RuntimeError,'监控尚未完全退出'):
                app.stop_all(self.home,{},timeout=0)
        close.assert_not_called()
        self.assertTrue((self.home/'control/off').exists())

    def test_off_blocks_login_and_readers(self):
        (self.home/'control/off').touch()
        with patch('app.config_load',return_value={}),patch('app.setup'),patch('app.service') as service,patch('app.run') as run:
            for command in ('service','worker','run','once','doctor'):
                app.main(['--home',str(self.home),command])
        service.assert_not_called();run.assert_not_called()

    def test_start_clears_persistent_off(self):
        (self.home/'control/off').touch()
        with patch('app.config_load',return_value={}),patch('app.setup'),patch('app.install_task'),patch('app.subprocess.run',return_value=Mock(returncode=0)):
            app.main(['--home',str(self.home),'start'])
        self.assertFalse((self.home/'control/off').exists())

    def test_close_uses_configured_path_and_normal_window_close(self):
        target=self.home/'terminal64.exe';target.touch()
        with patch('app.subprocess.run',return_value=Mock(returncode=0)) as run:
            app.close_mt5(str(target))
        args,kwargs=run.call_args
        self.assertEqual(kwargs['env']['FEISHU_STOP_MT5_PATH'],str(target.resolve()))
        command=args[0][-1]
        self.assertIn('$_.Path -eq $env:FEISHU_STOP_MT5_PATH',command)
        self.assertIn('CloseMainWindow',command)
        self.assertNotIn('Stop-Process',command)

    def test_failed_close_is_reported_and_invalid_path_is_not_run(self):
        with patch('app.subprocess.run') as run:
            with self.assertRaises(RuntimeError): app.close_mt5('')
            run.assert_not_called()
        target=self.home/'terminal64.exe';target.touch()
        with patch('app.subprocess.run',return_value=Mock(returncode=1)):
            with self.assertRaisesRegex(RuntimeError,'未正常退出'): app.close_mt5(str(target))


if __name__=='__main__': unittest.main()
