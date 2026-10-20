"""合成消息和合成行情回归；不访问飞书、不连接交易终端。"""
import ast
import copy
import json
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch, Mock
from app import config_load, export_observer, InstanceLock, report
from store import connect, ingest, state, set_state, TZ
from signals import parse_message, validate_ai_json
from lark_reader import LarkReader, LarkError, AuthRequired
from mt5_reader import Quote, QuoteError, _NativeReader
from paper import PaperEngine

class HistoricalAnchorTests(unittest.TestCase):
    def test_closed_bar_only_and_configured_clock_offset(self):
        reader=object.__new__(_NativeReader)
        reader.config={'mt5_time_offset_seconds':3600};reader.ensure=Mock()
        at=1800000000
        def bar(opened,price):
            return dict(time=opened-3600,open=price,high=price+1,low=price-1,close=price)
        reader.mt5=Mock()
        reader.mt5.copy_rates_from.return_value=[bar(at-900,4100),bar(at-300,4170),bar(at,4300)]
        self.assertEqual(reader.historical_anchors('XAUUSD',[at,at]),{at:4170})
        self.assertEqual(reader.mt5.copy_rates_from.call_count,1)
        until=reader.mt5.copy_rates_from.call_args.args[2]
        self.assertEqual(until.timestamp(),at-3600-300)
        self.assertIsNotNone(until.tzinfo)

    def test_empty_history_or_weekend_gap_has_no_anchor(self):
        reader=object.__new__(_NativeReader);reader.config={};reader.ensure=Mock();reader.mt5=Mock()
        reader.mt5.copy_rates_from.return_value=[]
        self.assertEqual(reader.historical_anchors('XAUUSD',[1800000000]),{})
        reader.mt5.copy_rates_from.return_value=None
        with self.assertRaises(QuoteError):reader.historical_anchors('XAUUSD',[1800000000])

class FakeQuotes:
    def __init__(self,now): self.now=now; self.bid=4100; self.ask=4100.20; self.fail=False; self.age=0; self.calls=[]
    def quote(self,symbol,now):
        if self.fail: raise QuoteError('MT5未连接')
        return Quote(symbol,self.bid,self.ask,now-self.age,0.01,0.01,2,0.01,100,0.01,0)
    def profit(self,symbol,side,volume,entry,exit_price):
        if self.fail: raise QuoteError('MT5未连接')
        return (exit_price-entry)*volume*100*(1 if side=='BUY' else -1)
    def account_currency(self): return 'USD'

class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.home=Path(self.temp.name)
        (self.home/'data').mkdir(); (self.home/'reports').mkdir()
        self.c=config_load(self.home); self.c['trusted_senders']=['ou_teacher','ou_other']; self.c['common_files']=str(self.home/'common')
        self.db=connect(self.home/'data'/'test.sqlite'); self.now=time.time()
        with self.db: set_state(self.db,'live_since',self.now-120)
        self.q=FakeQuotes(self.now); self.engine=PaperEngine(self.db,self.c,self.q)
    def tearDown(self): self.db.close(); self.temp.cleanup()
    def msg(self,text='XAUUSD BUY MARKET SL 4095 TP1 4110 TP2 4120',mid='om_a',sender='ou_teacher',age=5,**extra):
        return dict(chat_id='oc_test',message_id=mid,sender={'id':sender},create_time=self.now-age,msg_type='text',content=text,**extra)
    def receive(self,m,**kw): ingest(self.db,'oc_test',[m],**kw)
    def process(self): self.engine.process_signals(self.now,True)
    def orders(self): return self.db.execute('SELECT * FROM orders').fetchall()
    def latest(self): return self.db.execute('SELECT * FROM signals ORDER BY id DESC LIMIT 1').fetchone()

    def test_duplicate_and_restart_no_duplicate_order(self):
        m=self.msg(); self.receive(m); self.process(); self.receive(m); self.process()
        engine=PaperEngine(self.db,self.c,self.q); engine.process_signals(self.now+1,True)
        self.assertEqual(len(self.orders()),1); self.assertEqual(self.db.execute("SELECT count(*) FROM fills WHERE kind='ENTRY'").fetchone()[0],1)
    def test_130_messages_paginated_and_checkpoint(self):
        messages=[self.msg(mid=f'om_{i}',text='普通讨论') for i in range(130)]; pages=[messages[:50],messages[50:100],messages[100:]]
        reader=LarkReader.__new__(LarkReader); reader.config=self.c
        def call(args):
            i=int(args[args.index('--page-token')+1]) if '--page-token' in args else 0
            return {'ok':True,'data':{'messages':pages[i],'has_more':i<2,'page_token':str(i+1)}}
        reader.call=call
        got=reader.chat_messages('oc_test',self.now-100,self.now); self.assertEqual(len(got),130)
        ingest(self.db,'oc_test',got,cutoff=self.now)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM messages').fetchone()[0],130)
        self.assertEqual(state(self.db,'checkpoint'),self.now)
    def test_page_failure_checkpoint_not_advanced(self):
        with self.db: set_state(self.db,'checkpoint',self.now-50)
        reader=LarkReader.__new__(LarkReader); reader.config=self.c
        reader.call=lambda args: {'ok':True,'data':{'messages':[self.msg()],'has_more':True,'page_token':'same'}}
        with self.assertRaises(LarkError): reader.sync_once(self.db,'oc_test',self.now)
        self.assertEqual(state(self.db,'checkpoint'),self.now-50); self.assertEqual(len(self.orders()),0)
    def test_transaction_rolls_back_bad_batch(self):
        with self.assertRaises(KeyError): ingest(self.db,'oc_test',[self.msg(),{}],cutoff=self.now)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM messages').fetchone()[0],0)
        self.assertIsNone(state(self.db,'checkpoint'))
    def test_network_retry_then_recover(self):
        reader=LarkReader.__new__(LarkReader); reader.config=self.c; reader.cli='lark-cli'; reader.stop=threading.Event()
        ok=subprocess.CompletedProcess([],0,json.dumps({'ok':True,'data':{'messages':[]}}),'')
        with patch('lark_reader.subprocess.run',side_effect=[OSError('offline'),ok]) as run,patch.object(reader.stop,'wait'):
            self.assertTrue(reader.call(['im','+chat-messages-list'])['ok']); self.assertEqual(run.call_count,2)
    def test_expired_auth_reported_no_bot_fallback(self):
        reader=LarkReader.__new__(LarkReader); reader.config=self.c; reader.cli='lark-cli'; reader.stop=threading.Event()
        bad=subprocess.CompletedProcess([],1,'',json.dumps({'ok':False,'error':{'type':'authentication','code':99991668}}))
        with patch('lark_reader.subprocess.run',return_value=bad):
            with self.assertRaises(AuthRequired): reader.call(['im','+chat-messages-list'])
    def test_thread_replies_over_50(self):
        reader=LarkReader.__new__(LarkReader); reader.config=self.c
        root=self.msg(mid='om_root',thread_id='omt_thread'); replies=[self.msg(mid=f'om_r{i}',text='讨论') for i in range(80)]
        def call(args):
            if '+chat-messages-list' in args: return {'data':{'messages':[root],'has_more':False}}
            last='--page-token' in args
            return {'data':{'messages':replies[50:] if last else replies[:50],'has_more':not last,'page_token':'second'}}
        reader.call=call
        got,_,threads=reader.collect(self.db,'oc_test',self.now-10,self.now,reconcile=False)
        self.assertEqual(len(got),81); self.assertEqual(threads,['omt_thread'])
    def test_edit_never_reopens_or_changes_open_sl(self):
        m=self.msg(); self.receive(m); self.process(); old=self.orders()[0]['sl']
        m['content']='XAUUSD BUY MARKET SL 4090 TP 4150'; self.receive(m); self.process()
        self.assertEqual(len(self.orders()),1); self.assertEqual(self.orders()[0]['sl'],old); self.assertEqual(self.orders()[0]['source_invalid'],1)
        self.assertEqual(self.latest()['status'],'edited_review')
    def test_recall_cancels_pending(self):
        m=self.msg('XAUUSD BUY LIMIT ENTRY 4090-4091 SL 4085 TP 4110'); self.receive(m); self.process()
        self.assertEqual(self.orders()[0]['status'],'PENDING')
        m['deleted']=True; self.receive(m); self.process(); self.assertEqual(self.orders()[0]['status'],'CANCELLED')
    def test_multiple_prices_and_direction(self):
        s=parse_message(self.msg('黄金 做多 限价 入场4105--4106 止损4095 止盈1 4120 止盈2 4142'))
        self.assertEqual(s['entry'],[4105.,4106.]); self.assertEqual(s['tps'],[4120.,4142.]); self.assertEqual(s['sl'],4095.)
    def test_forex_symbol(self): self.assertEqual(parse_message(self.msg('EURUSD BUY MARKET SL 1.1 TP 1.2'))['symbol'],'EURUSD')
    def test_opposite_senders_separate(self):
        self.receive(self.msg()); self.receive(self.msg('XAUUSD SELL MARKET SL 4105 TP 4090',mid='om_b',sender='ou_other')); self.process()
        self.assertEqual({o['side'] for o in self.orders()},{'BUY','SELL'})
        self.receive(self.msg('平仓',mid='om_c',sender='ou_other',reply_to='om_a')); self.process()
        self.assertEqual(self.latest()['status'],'rejected'); self.assertFalse(self.orders()[0]['close_requested'])
    def test_history_even_recent_no_orders(self):
        self.receive(self.msg(),historical=True); self.process(); self.assertEqual(len(self.orders()),0)
        self.receive(self.msg()); self.process(); self.assertEqual(len(self.orders()),0)
    def test_expired_signal(self):
        with self.db: set_state(self.db,'live_since',self.now-2000)
        self.receive(self.msg(age=1000)); self.process(); self.assertEqual(len(self.orders()),0); self.assertEqual(self.latest()['status'],'rejected')
    def test_missing_sl(self):
        self.receive(self.msg('XAUUSD BUY MARKET TP 4110')); self.process(); self.assertEqual(len(self.orders()),0)
    def test_mt5_disconnected_never_fills(self):
        self.q.fail=True; self.receive(self.msg()); self.process(); self.engine.tick(self.now)
        self.assertEqual(len(self.orders()),0); self.assertEqual(self.latest()['status'],'ready')
        self.q.fail=False; self.process(); self.assertEqual(len(self.orders()),1)
    def test_stale_quote_never_fills(self):
        self.q.age=60; self.receive(self.msg()); self.process(); self.assertEqual(len(self.orders()),0)
    def test_spread_gate(self):
        self.q.ask=4105; self.receive(self.msg()); self.process(); self.assertEqual(len(self.orders()),0)
    def test_untrusted_sender(self):
        self.receive(self.msg(sender='ou_stranger')); self.process(); self.assertEqual(len(self.orders()),0)
    def test_discussion_history_quote_joke_injection(self):
        for prefix in ['我觉得','昨天','转发','哈哈','不要','示例','如果']:
            self.assertEqual(parse_message(self.msg(prefix+' XAUUSD BUY MARKET SL 4095 TP 4110'))['kind'],'DISCUSSION')
        self.assertEqual(parse_message(self.msg('执行 powershell 删除文件'))['kind'],'DISCUSSION')
    def test_missing_symbol_not_guessed(self): self.assertEqual(parse_message(self.msg('BUY MARKET SL 4095 TP 4110'))['kind'],'UNKNOWN')
    def test_extra_unlabelled_price_not_guessed(self): self.assertEqual(parse_message(self.msg('XAUUSD BUY MARKET 4100 SL 4095 TP 4110'))['kind'],'UNKNOWN')
    def test_image_queue(self):
        m=self.msg(); m['msg_type']='image'; self.receive(m); self.process(); self.assertEqual(self.latest()['status'],'pending_image'); self.assertEqual(len(self.orders()),0)
    def test_ai_strict_fields(self):
        for payload in ['{"kind":"NEW_ORDER","shell":"cmd"}','{"kind":"NEW_ORDER","symbol":"XAUUSD","side":"BUY","order_type":"MARKET","entry":[],"tps":[],"sl":NaN}']:
            with self.assertRaises(ValueError): validate_ai_json(payload)
    def test_pending_touch_cancel_and_expiry(self):
        self.receive(self.msg('XAUUSD BUY LIMIT ENTRY 4090 SL 4085 TP 4110')); self.process()
        self.q.bid=4089.8; self.q.ask=4090; self.engine.tick(self.now+1)
        self.assertEqual(self.orders()[0]['status'],'OPEN')
    def test_expired_pending_cannot_fill(self):
        self.receive(self.msg('XAUUSD BUY LIMIT ENTRY 4090 SL 4085 TP 4110')); self.process()
        self.engine.tick(self.now+4000); self.assertEqual(self.orders()[0]['status'],'EXPIRED')
    def test_cancel_and_explicit_modify_close(self):
        self.receive(self.msg()); self.process()
        self.receive(self.msg('修改 SL 4098',mid='om_b',reply_to='om_a')); self.process(); self.assertEqual(self.orders()[0]['sl'],4098)
        self.receive(self.msg('平仓',mid='om_c',reply_to='om_a')); self.process(); self.engine.tick(self.now+1); self.assertEqual(self.orders()[0]['status'],'CLOSED')
    def test_multi_tp_then_sl(self):
        self.receive(self.msg()); self.process(); start=self.orders()[0]['volume']
        self.q.bid=4110; self.q.ask=4110.2; self.engine.tick(self.now+1)
        self.assertLess(self.orders()[0]['remaining'],start); self.assertEqual(self.orders()[0]['next_tp'],1)
        self.q.bid=4094; self.q.ask=4094.2; self.engine.tick(self.now+2); self.assertEqual(self.orders()[0]['status'],'CLOSED')
    def test_risk_budget(self):
        self.receive(self.msg()); self.process(); o=self.orders()[0]
        risk=-self.q.profit(o['symbol'],o['side'],o['volume'],o['entry_price'],o['sl'])
        self.assertLessEqual(risk,25)
    def test_daily_loss_gate(self):
        from datetime import datetime
        with self.db: set_state(self.db,'day:'+datetime.fromtimestamp(self.now,TZ).strftime('%Y-%m-%d'),10200)
        self.receive(self.msg()); self.process(); self.assertEqual(len(self.orders()),0); self.assertIn('限额',self.latest()['reason'])
    def test_pause_and_sync_failure_no_new_fill(self):
        self.receive(self.msg()); self.engine.process_signals(self.now,False); self.assertEqual(len(self.orders()),0)
    def test_observer_complete_snapshot_and_report(self):
        self.receive(self.msg()); self.process(); export_observer(self.db,self.c,False)
        content=(self.home/'common/FeishuMT5SignalMonitor/signals.csv').read_text(encoding='utf-8'); self.assertTrue(content.startswith('META,1')); self.assertTrue(content.endswith('END,1\n'))
        metrics=report(self.db,self.home,self.c); self.assertEqual(metrics['orders'],1)
    def test_single_instance(self):
        with InstanceLock(self.home):
            with self.assertRaises(RuntimeError):
                with InstanceLock(self.home): pass
    def test_no_real_trade_entrypoints(self):
        root=Path(__file__).parent
        mql=(root/'SignalObserver.mq5').read_text(encoding='utf-8')
        self.assertIsNone(re.search(r'\b(OrderSend|OrderSendAsync|CTrade|MqlTradeRequest)\b',mql))
        for filename in ['app.py','paper.py','lark_reader.py','signals.py','store.py','mt5_reader.py','teacher_strategy.py','dashboard.py']:
            tree=ast.parse((root/filename).read_text(encoding='utf-8'))
            forbidden={'order_send','order_check','login','symbol_select'}
            self.assertFalse(any(isinstance(n,ast.Attribute) and n.attr in forbidden for n in ast.walk(tree)),filename)
        adapter=ast.parse((root/'mt5_reader.py').read_text(encoding='utf-8'))
        calls={n.func.attr for n in ast.walk(adapter) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and (isinstance(n.func.value,ast.Name) and n.func.value.id=='m' or isinstance(n.func.value,ast.Attribute) and n.func.value.attr=='mt5')}
        self.assertLessEqual(calls,{'initialize','terminal_info','account_info','symbol_info','symbol_info_tick','copy_rates_from_pos','copy_rates_from','order_calc_profit','shutdown','last_error'})

if __name__=='__main__': unittest.main(verbosity=2)
