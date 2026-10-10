"""MT5 只读适配器：没有交易请求入口、账号切换或自动选品种操作。"""
import math
import multiprocessing
import time
from dataclasses import dataclass

class QuoteError(RuntimeError): pass

@dataclass(frozen=True)
class Quote:
    symbol:str
    bid:float
    ask:float
    at:float
    point:float
    tick_size:float
    digits:int
    volume_min:float
    volume_max:float
    volume_step:float
    stops:float

# 本机实测券商时钟快约5.02秒，留1秒边界余量；不动态对齐或改变旧报价有效期。
SERVER_CLOCK_TOLERANCE_SECONDS=6

class _NativeReader:
    def __init__(self,config):
        self.config=config
        import MetaTrader5 as mt5
        self.mt5=mt5; self.connected=False

    def ensure(self):
        m=self.mt5
        if not self.connected:
            path=self.config.get('mt5_terminal_path','')
            self.connected=m.initialize(path,timeout=5000) if path else m.initialize(timeout=5000)
        info=m.terminal_info() if self.connected else None
        if info is None or not info.connected:
            self.connected=False
            raise QuoteError('MT5未连接，停止新的模拟成交；'+str(m.last_error()))
        account=m.account_info()
        if account is None:
            raise QuoteError('无法读取MT5账户计价货币，拒绝混算盈亏')
        expected=self.config.get('currency','AUTO')
        if expected not in ('','AUTO') and account.currency!=expected:
            raise QuoteError('报价账户计价货币与模拟账户不一致，拒绝混算盈亏')
        # 这是只读安全闸：程序即使未来被误改，也不能在未启用终端保护时运行。
        if not bool(getattr(info,'tradeapi_disabled',False)):
            raise QuoteError('MT5未启用“禁止通过外部Python API自动交易”保护，拒绝读取并停止模拟')
        return info

    def account_currency(self):
        self.ensure()
        account=self.mt5.account_info()
        if account is None: raise QuoteError('无法读取MT5账户计价货币')
        return account.currency

    def quote(self,symbol,now):
        self.ensure()
        s=self.mt5.symbol_info(symbol); tick=self.mt5.symbol_info_tick(symbol)
        if s is None or tick is None or not s.visible:
            raise QuoteError('品种不可读/未在市场报价中显示：'+symbol)
        raw_at=tick.time_msc/1000
        # IPC首次连接会耗时；用读取完成时的本机时钟校验，避免新tick相对请求时刻显得超前。
        now=time.time()
        # 使用事先核对的固定偏移，不能将几小时前的旧报价重新对齐为当前报价。
        at=raw_at+self.config.get('mt5_time_offset_seconds',0)
        # 服务器时钟可能比本机快几秒；小幅未来值视为同一当前 tick，大幅未来值仍拒绝。
        if at>now and at-now<=SERVER_CLOCK_TOLERANCE_SECONDS: at=now
        q=Quote(symbol,tick.bid,tick.ask,at,s.point,s.trade_tick_size,s.digits,s.volume_min,s.volume_max,s.volume_step,s.trade_stops_level*s.point)
        validate_quote(q,now,self.config,spread=False)
        return q

    def bars(self,symbol,now):
        self.ensure()
        # 官方索引0是未收盘K线；从1开始读取，决不参与第0根的方向判断。
        raw=self.mt5.copy_rates_from_pos(symbol,self.mt5.TIMEFRAME_M5,1,120)
        if raw is None or len(raw)<60: raise QuoteError('M5历史不足60根，等待终端加载')
        offset=self.config.get('mt5_time_offset_seconds',0)
        bars=[dict(at=float(r['time'])+offset,open=float(r['open']),high=float(r['high']),low=float(r['low']),close=float(r['close'])) for r in raw]
        validate_bars(bars,now)
        return bars

    def profit(self,symbol,side,volume,entry,exit_price):
        self.ensure()
        # 官方只读估算函数按券商品种规格及账户货币换算，绝不发出委托。
        value=self.mt5.order_calc_profit(0 if side=='BUY' else 1,symbol,volume,entry,exit_price)
        if value is None or not math.isfinite(value): raise QuoteError('MT5无法计算该品种的账户货币盈亏')
        return float(value)

    def close(self):
        self.mt5.shutdown(); self.connected=False

def validate_quote(q,now,config,spread=True):
    values=[q.bid,q.ask,q.at,q.point,q.tick_size,q.volume_min,q.volume_max,q.volume_step]
    if any(not math.isfinite(v) or v<=0 for v in values) or q.ask<q.bid or q.volume_min>q.volume_max: raise QuoteError('报价/品种规格不完整')
    if now-q.at>config['quote_max_age_seconds'] or q.at-now>2: raise QuoteError('报价过期或时间异常')
    if spread and (q.ask-q.bid)/q.point>config['max_spread_points']+1e-7: raise QuoteError('点差超过模拟成交上限')


def validate_bars(bars,now):
    if len(bars)<60: raise QuoteError('M5历史不足60根')
    for i,b in enumerate(bars):
        if any(not math.isfinite(b[k]) or b[k]<=0 for k in ('at','open','high','low','close')):
            raise QuoteError('M5价格/时间无效')
        if b['low']>min(b['open'],b['close']) or b['high']<max(b['open'],b['close']): raise QuoteError('M5高低价无效')
        if i and b['at']<=bars[i-1]['at']: raise QuoteError('M5时间顺序错误')
    if not -SERVER_CLOCK_TOLERANCE_SECONDS<=now-(bars[-1]['at']+300)<=310: raise QuoteError('最后已收盘M5过期或时间偏移配置不符')
    if any(bars[i]['at']-bars[i-1]['at']!=300 for i in (-1,-2)):
        raise QuoteError('最近三根M5不连续，等待新的完整结构')

def _worker(pipe,config):
    reader=None
    try:
        reader=_NativeReader(config)
        while True:
            method,args=pipe.recv()
            if method=='close': break
            try:
                # 固定允许列表，子进程也没有任意 MT5 方法分发。
                if method=='quote': result=reader.quote(*args)
                elif method=='bars': result=reader.bars(*args)
                elif method=='account_currency': result=reader.account_currency()
                elif method=='profit': result=reader.profit(*args)
                else: raise QuoteError('未知的只读请求')
                pipe.send((True,result))
            except Exception as ex: pipe.send((False,str(ex)))
    except (EOFError,BrokenPipeError): pass
    except Exception as ex:
        try: pipe.send((False,str(ex)))
        except (OSError,EOFError): pass
    finally:
        if reader is not None: reader.close()
        pipe.close()

class MT5Reader:
    """官方初始化实测会无视短 timeout 卡60秒；隔离后不阻塞监控/停止。"""
    def __init__(self,config):
        self.config=config; self.process=None; self.pipe=None; self.retry_at=0

    def _call(self,method,*args):
        if time.monotonic()<self.retry_at: raise QuoteError('MT5连接退避中，暂不模拟成交')
        if self.process is None:
            ctx=multiprocessing.get_context('spawn'); self.pipe,child=ctx.Pipe()
            self.process=ctx.Process(target=_worker,args=(child,self.config),daemon=True,name='MT5-readonly')
            self.process.start(); child.close()
        try:
            self.pipe.send((method,args))
            if not self.pipe.poll(6): raise QuoteError('MT5只读接口6秒未响应（IPC/集成设置），停止新模拟成交')
            ok,result=self.pipe.recv()
            if not ok: raise QuoteError(result)
            return result
        except (OSError,EOFError,QuoteError) as ex:
            self._terminate(); self.retry_at=time.monotonic()+30
            raise QuoteError(str(ex)) from ex

    def quote(self,symbol,now): return self._call('quote',symbol,now)
    def bars(self,symbol,now): return self._call('bars',symbol,now)
    def account_currency(self): return self._call('account_currency')
    def profit(self,symbol,side,volume,entry,exit_price): return self._call('profit',symbol,side,volume,entry,exit_price)
    def _terminate(self):
        if self.process is not None:
            if self.process.is_alive(): self.process.terminate()
            self.process.join(timeout=2); self.process.close(); self.process=None
        if self.pipe is not None: self.pipe.close(); self.pipe=None
    def close(self):
        if self.pipe is not None:
            try: self.pipe.send(('close',()))
            except (OSError,EOFError): pass
        if self.process is not None: self.process.join(timeout=1)
        self._terminate()
