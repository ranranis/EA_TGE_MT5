"""Use the installed WorkBuddy CLI and its own login; inference only, no agent tools."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

from deepseek_ai import AIError, DeepSeek


# 与消息档案分开：每轮仅使用本次传入的原文与来源，不使用Agent个人记忆。
WORKBUDDY_READING_RULES = """
【连续阅读与点位地图整理规则】
一、先按消息时间和sequence阅读context，再按顺序解释targets；每条target只能使用其之前的信息。先区分老师、合格会议总结、指定跟随成员和普通群友，再区分入场、区间、关键位角色、退出、行情报数、复盘和假设。
二、旧interpretation和previous_scene只是待核对的记录，不能当原文事实。逐个旧计划核对后续取消、改价、同价角色转换；较新老师原话可替换旧转述，同等权威较新明确说明优先。不得为凑计划继续保留已被取消或同价新角色否定的旧方向；支撑重申不能当旧做空重申，压力重申不能当旧做多重申。
三、维护一份截至as_of的完整场景。确有变更时UPDATE包含仍有依据的全部计划；补充另一侧不删除无关计划，明确改价不能同时保留旧价和新价。普通闲聊KEEP；新交易指令含糊或相互矛盾时REVIEW，不猜方向。原文“取消4180空”只取消相应计划，不扩大为取消所有空。
四、已撤回、改版或已被替换的来源不得复活；再次读到同一消息不等于重新确认。没有新明确证据，不刷新旧入场依据。只保留原文价格，不按均值合并、补造邻近点；不把时间周期、当前报价、止盈位置当入场。
五、当前协议不能表达“站稳后才多、跌破后再空”等额外条件，不得缩成碰价就下单，写入summary说明待确认。明确多/空是条件参考，不等于已经成交；支撑/压力先按角色记录，不强造直接喊单。入场、大小区间、目标分别按既有schema填写，不新增JSON字段。
六、你负责语义解释，程序负责有效期、人工删除/停用、6个点位上限和至少5.00间距。不能为了凑六个、距离现价太远或自己估计过期就删掉原文仍有效的场景依据。不要自己填到期时间；过期与落选由程序核对原确认时点并记录原因。完整语义场景不是最终可执行地图。
七、最后检查每条计划的价格、方向、来源、时序和取消情况。summary用简短中文说明本次变化、当前区间和歧义；摘要中的消息引用也使用本次短编号。仍只输出规定的interpretations与scene完整JSON，不输出Markdown、交易请求或程序指令。
"""


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
                system.write_text(payload['messages'][0]['content']+WORKBUDDY_READING_RULES,
                                  encoding='utf-8')
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
