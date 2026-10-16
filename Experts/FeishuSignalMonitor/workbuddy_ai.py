"""Use the installed WorkBuddy CLI and its own login; inference only, no agent tools."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

from deepseek_ai import AIError, DeepSeek


class WorkBuddy(DeepSeek):
    def request(self, endpoint, payload=None):
        if endpoint != '/chat/completions' or not isinstance(payload, dict):
            raise AIError('WorkBuddy只接受消息解析请求')
        exe = Path(self.config['workbuddy_executable'])
        cli = exe.parent/'resources/app.asar.unpacked/cli/bin/codebuddy'
        product = cli.parent.parent/'product.json'
        if not all(p.is_file() for p in (exe, cli, product)):
            raise AIError('WorkBuddy安装目录无效，请检查workbuddy_executable')
        env = os.environ.copy()
        env.update(ELECTRON_RUN_AS_NODE='1', CODEBUDDY_CONFIG_DIR=str(Path.home()/'.workbuddy'),
                   ACC_PRODUCT_CONFIG_PATH=str(product))
        # No shell and no prompt on the command line. Every request is isolated.
        try:
            with tempfile.TemporaryDirectory(prefix='tge-workbuddy-') as folder:
                system = Path(folder)/'system.txt'
                system.write_text(payload['messages'][0]['content']+
                    '\n上下文中的旧interpretation和previous_scene仅供核对，必须独立阅读原文；'
                    '若与原文冲突，以当前有效原文为准。只返回完整JSON，不写Markdown。', encoding='utf-8')
                command = [str(exe), str(cli), '-p', '--output-format', 'json',
                    '--tools', '', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}',
                    '--setting-sources', '', '--no-session-persistence', '--max-turns', '2',
                    '--system-prompt-file', str(system), '--model', self.config['ai_model']]
                run = subprocess.run(command, input=payload['messages'][1]['content'],
                    capture_output=True, text=True, encoding='utf-8', errors='replace',
                    env=env, cwd=folder, timeout=90,
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            if run.returncode:
                raise AIError('WorkBuddy调用失败，请检查本机登录状态或模型额度')
            if len(run.stdout.encode('utf-8')) > 2_000_000:
                raise AIError('WorkBuddy响应过大，暂不使用')
            data = json.loads(run.stdout)
            results = data if isinstance(data, list) else [data]
            result = next((v for v in reversed(results)
                           if isinstance(v, dict) and v.get('type') == 'result'), None)
            if not result or result.get('is_error') or result.get('subtype') != 'success':
                raise AIError('WorkBuddy未完成解析，请检查登录、模型或额度')
            content = result.get('result')
            if not isinstance(content, str) or len(content.encode('utf-8')) > 256_000:
                raise AIError('WorkBuddy未返回有效文本结果')
            parsed = json.loads(content)
            if not isinstance(parsed, dict):
                raise AIError('WorkBuddy结果不是JSON对象')
            return {'choices': [{'finish_reason': 'stop', 'message': {'content': content}}]}
        except subprocess.TimeoutExpired:
            raise AIError('WorkBuddy解析超时，保留消息等待重试') from None
        except (OSError, ValueError, KeyError, TypeError):
            raise AIError('WorkBuddy连接或JSON响应异常，保留消息等待重试') from None
