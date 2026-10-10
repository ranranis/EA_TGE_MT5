"""纯 SQLite 模拟交易。所有成交都只是本地假设，不是券商成交。"""
import json
import math
from datetime import datetime
from store import TZ, dumps, state, set_state, alert
from signals import validate_signal
from mt5_reader import QuoteError, validate_quote

def floor_step(value,step): return round(math.floor((value+1e-10)/step)*step,8)
def price_grid(value,q,up=False):
    n=math.ceil(value/q.tick_size-1e-9) if up else math.floor(value/q.tick_size+1e-9)
    return round(n*q.tick_size,q.digits)

class PaperEngine:
    def __init__(self,db,config,quotes): self.db=db; self.c=config; self.quotes=quotes

    def balance(self):
        return self.c['initial_equity']+self.db.execute('SELECT COALESCE(SUM(pnl-commission),0) FROM fills').fetchone()[0]

    def open_orders(self): return self.db.execute("SELECT * FROM orders WHERE status='OPEN' ORDER BY id").fetchall()

    def valuation(self,now):
        balance=self.balance(); equity=balance; total_risk=0
        for o in self.open_orders():
            q=self.quotes.quote(o['symbol'],now)
            validate_quote(q,now,self.c,spread=False)
            exit_price=q.bid if o['side']=='BUY' else q.ask
            equity+=self.quotes.profit(o['symbol'],o['side'],o['remaining'],o['entry_price'],exit_price)
            total_risk+=max(0,-self.quotes.profit(o['symbol'],o['side'],o['remaining'],exit_price,o['sl']))
        return balance,equity,total_risk

    def limits(self,now):
        balance,equity,open_risk=self.valuation(now)
        day=datetime.fromtimestamp(now,TZ).strftime('%Y-%m-%d'); key='day:'+day
        base=state(self.db,key)
        if base is None:
            base=equity; set_state(self.db,key,base)
        # 当日风控触发后锁到下一天；已持仓继续按保护规则管理。
        breached=base<=0 or equity<=base*(1-self.c['daily_loss_fraction'])
        if breached: set_state(self.db,'halt:'+day,True)
        if state(self.db,'halt:'+day,False): raise ValueError('当日模拟亏损触及限额，暂停新模拟成交')
        if equity<=0: raise ValueError('模拟权益不足')
        return equity,open_risk

    def levels(self,side,entry,sl,tps,q):
        if sl is None: raise ValueError('缺少止损，拒绝模拟开仓')
        if not tps: raise ValueError('缺少止盈，拒绝模拟开仓')
        for p in [entry,sl]+tps:
            if not math.isfinite(p) or p<=0 or abs(p/q.tick_size-round(p/q.tick_size))>1e-5:
                raise ValueError('价格不符合品种 tick size')
        direction=1 if side=='BUY' else -1
        if direction*(entry-sl)<=0 or abs(entry-sl)+1e-9<q.stops: raise ValueError('止损方向/最小距离错误')
        if any(direction*(tp-entry)<=0 or abs(tp-entry)+1e-9<q.stops for tp in tps): raise ValueError('止盈方向/最小距离错误')
        if tps!=sorted(set(tps),reverse=side=='SELL'): raise ValueError('多级止盈必须严格按有利方向排列')

    def process_signals(self,now,allow_new):
        if not allow_new: return
        rows=self.db.execute("SELECT * FROM signals WHERE status='ready' ORDER BY created,id").fetchall()
        for row in rows:
            with self.db:
                self.db.execute('BEGIN IMMEDIATE')
                current=self.db.execute('SELECT * FROM signals WHERE id=?',(row['id'],)).fetchone()
                if current['status']!='ready': continue
                try:
                    if row['sender'] not in self.c['trusted_senders']: raise ValueError('发送者不在可信名单，仅分析')
                    age=now-row['created']
                    if age<0 or age>self.c['signal_ttl_seconds']: raise ValueError('信号已过期/发送时间异常')
                    s=validate_signal(json.loads(row['payload']))
                    if s['kind']=='NEW_ORDER': self.new_order(row,s,now)
                    else: self.action(row,s,now)
                    self.db.execute("UPDATE signals SET status='processed',reason='已由本地模拟引擎处理' WHERE id=?",(row['id'],))
                except QuoteError as ex:
                    # 断线时保留待处理状态，仅在有效期内等报价恢复。
                    self.db.execute('UPDATE signals SET reason=? WHERE id=?',(str(ex),row['id']))
                except (ValueError,TypeError,KeyError) as ex:
                    self.db.execute("UPDATE signals SET status='rejected',reason=? WHERE id=?",(str(ex),row['id']))

    def new_order(self,row,s,now):
        existing=self.db.execute('SELECT id FROM orders WHERE chat_id=? AND source_id=?',(row['chat_id'],row['message_id'])).fetchone()
        if existing: raise ValueError('该消息已创建过模拟单')
        symbol=self.c['symbols'].get(s['symbol'])
        if not symbol: raise ValueError('品种没有显式配置映射')
        q=self.quotes.quote(symbol,now); validate_quote(q,now,self.c)
        self.limits(now)
        entry=s['entry']; low=min(entry) if entry else None; high=max(entry) if entry else None
        market=q.ask if s['side']=='BUY' else q.bid
        intended=(high if s['side']=='BUY' else low) if s['order_type']=='LIMIT' else price_grid(market+(1 if s['side']=='BUY' else -1)*self.c['slippage_points']*q.point,q,s['side']=='BUY')
        self.levels(s['side'],intended,s['sl'],s['tps'],q)
        if s['order_type']=='LIMIT' and ((s['side']=='BUY' and high>=q.ask) or (s['side']=='SELL' and low<=q.bid)): raise ValueError('限价单方向不合法或已越过入场区域')
        if s['order_type']=='MARKET' and entry and not low<=market<=high: raise ValueError('市价已离开明确入场区间')
        # 使用当前止损风险决定是否可成交，挂单真正触发时再次计算。
        if s['order_type']=='MARKET': volume=self.size(symbol,s['side'],intended,s['sl'],s['tps'],q,now)
        else: volume=0
        cursor=self.db.execute('INSERT INTO orders(chat_id,source_id,sender,symbol,side,kind,entry_low,entry_high,sl,tps,status,created,expires) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
            (row['chat_id'],row['message_id'],row['sender'],symbol,s['side'],s['order_type'],low,high,s['sl'],dumps(s['tps']),'PENDING',now,row['created']+(self.c['pending_ttl_seconds'] if s['order_type']=='LIMIT' else self.c['signal_ttl_seconds'])))
        if s['order_type']=='MARKET': self.fill_entry(cursor.lastrowid,intended,volume,q,market,now)

    def size(self,symbol,side,price,sl,tps,q,now):
        equity,open_risk=self.limits(now)
        unit=abs(self.quotes.profit(symbol,side,1,price,sl))+2*self.c['commission_per_lot_side']
        if unit<=0: raise ValueError('无法计算止损风险')
        budget=min(equity*self.c['risk_fraction'],equity*self.c['max_total_risk_fraction']-open_risk)
        volume=floor_step(min(q.volume_max,max(0,budget)/unit),q.volume_step)
        if volume<q.volume_min or floor_step(volume/len(tps),q.volume_step)<q.volume_min: raise ValueError('风险预算不足以满足最小手数/多级止盈分仓')
        return volume

    def fill_entry(self,oid,price,volume,q,raw_price,now):
        self.db.execute("UPDATE orders SET status='OPEN',opened=?,entry_price=?,volume=?,remaining=? WHERE id=?",(now,price,volume,volume,oid))
        self.db.execute('INSERT INTO fills(order_id,at,kind,volume,price,spread,slippage,pnl,commission,reason) VALUES(?,?,?,?,?,?,?,?,?,?)',
            (oid,now,'ENTRY',volume,price,q.ask-q.bid,abs(price-raw_price),0,volume*self.c['commission_per_lot_side'],'本地模拟开仓'))

    def action(self,row,s,now):
        if not s.get('target'): raise ValueError('缺少明确关联消息ID/回复关系，不猜测最近订单')
        o=self.db.execute('SELECT * FROM orders WHERE chat_id=? AND source_id=? AND sender=?',(row['chat_id'],s['target'],row['sender'])).fetchone()
        if not o: raise ValueError('找不到同一发送者的明确关联模拟单')
        if s['kind']=='CANCEL_ORDER':
            if o['status']!='PENDING': raise ValueError('只能撤销未成交模拟挂单')
            self.db.execute("UPDATE orders SET status='CANCELLED',reason='发送者明确撤单' WHERE id=?",(o['id'],)); return
        if o['status'] not in ('OPEN','PENDING'): raise ValueError('模拟单已结束')
        if s['kind']=='CLOSE_ORDER':
            if o['status']!='OPEN': raise ValueError('未成交模拟单应撤单')
            # 有效关联平仓意图持久化，报价恢复后再按可用价格模拟退出。
            self.db.execute('UPDATE orders SET close_requested=1 WHERE id=?',(o['id'],)); return
        if s['kind']!='MODIFY_ORDER': raise ValueError('不支持的动作')
        q=self.quotes.quote(o['symbol'],now)
        sl=s.get('sl') if s.get('sl') is not None else o['sl']
        tps=s.get('tps') or json.loads(o['tps'])[o['next_tp']:]
        reference=(q.bid if o['side']=='BUY' else q.ask) if o['status']=='OPEN' else (o['entry_high'] if o['side']=='BUY' else o['entry_low'])
        self.levels(o['side'],reference,sl,tps,q)
        # 默认不允许放大模拟止损风险，保本/收紧合法。
        if (o['side']=='BUY' and sl<o['sl']) or (o['side']=='SELL' and sl>o['sl']): raise ValueError('不允许扩大原止损风险')
        if o['remaining'] and floor_step(o['remaining']/len(tps),q.volume_step)<q.volume_min: raise ValueError('剩余手数不足以分配新止盈')
        self.db.execute('UPDATE orders SET sl=?,tps=?,next_tp=0,source_invalid=0,reason=? WHERE id=?',(sl,dumps(tps),'明确关联的模拟改单',o['id']))

    def tick(self,now,allow_new=True):
        # 一个事务内更新模拟仓位、模拟成交和权益，重启不会重放成交。
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            rows=self.db.execute("SELECT * FROM orders WHERE status IN ('OPEN','PENDING') ORDER BY id").fetchall()
            for o in rows:
                try:
                    if o['status']=='PENDING' and now>o['expires']:
                        self.db.execute("UPDATE orders SET status='EXPIRED',reason='挂单到期' WHERE id=?",(o['id'],)); continue
                    q=self.quotes.quote(o['symbol'],now)
                    validate_quote(q,now,self.c,spread=o['status']=='PENDING')
                    raw=q.ask if o['side']=='BUY' else q.bid
                    direction=1 if o['side']=='BUY' else -1
                    tps=json.loads(o['tps'])
                    if o['status']=='PENDING':
                        if not allow_new or o['source_invalid']: continue
                        single=o['entry_low']==o['entry_high']
                        reached=(raw<=o['entry_high'] if o['side']=='BUY' else raw>=o['entry_low']) if single else o['entry_low']<=raw<=o['entry_high']
                        if not reached: continue
                        requested=raw+direction*self.c['slippage_points']*q.point
                        requested=min(requested,o['entry_high']) if o['side']=='BUY' else max(requested,o['entry_low'])
                        price=price_grid(requested,q,o['side']=='BUY')
                        if single: price=o['entry_low']  # 保守按限价成交，不凭空给予跳空改善。
                        if not o['entry_low']<=price<=o['entry_high']: continue
                        self.levels(o['side'],price,o['sl'],tps,q)
                        volume=self.size(o['symbol'],o['side'],price,o['sl'],tps,q,now)
                        self.fill_entry(o['id'],price,volume,q,raw,now)
                        continue
                    exit_raw=q.bid if o['side']=='BUY' else q.ask
                    if direction*(exit_raw-o['sl'])<=0 or o['close_requested']:
                        price=price_grid(exit_raw-direction*self.c['slippage_points']*q.point,q,o['side']=='SELL')
                        self.exit(o,o['remaining'],price,q,exit_raw,now,'SL' if not o['close_requested'] else 'CLOSE'); continue
                    while o['next_tp']<len(tps) and direction*(exit_raw-tps[o['next_tp']])>=0:
                        left=len(tps)-o['next_tp']
                        volume=o['remaining'] if left==1 else floor_step(o['remaining']/left,q.volume_step)
                        if volume<q.volume_min: raise ValueError('分批手数低于最小值')
                        # 目标价跳空不给额外有利收益，扣除配置的模拟滑点。
                        price=price_grid(tps[o['next_tp']]-direction*self.c['slippage_points']*q.point,q,o['side']=='SELL')
                        self.exit(o,volume,price,q,tps[o['next_tp']],now,'TP')
                        self.db.execute('UPDATE orders SET next_tp=next_tp+1 WHERE id=?',(o['id'],))
                        o=self.db.execute('SELECT * FROM orders WHERE id=?',(o['id'],)).fetchone()
                except QuoteError:
                    continue
                except ValueError as ex:
                    if o['status']=='PENDING': self.db.execute("UPDATE orders SET status='REJECTED',reason=? WHERE id=?",(str(ex),o['id']))
                    else: alert(self.db,'PAPER_VALIDATION',str(ex),now)
            try:
                balance,equity,_=self.valuation(now)
                self.db.execute('INSERT OR REPLACE INTO equity VALUES(?,?,?)',(now,balance,equity))
                try: self.limits(now)
                except ValueError: pass
            except QuoteError: pass

    def exit(self,o,volume,price,q,raw,now,reason):
        pnl=self.quotes.profit(o['symbol'],o['side'],volume,o['entry_price'],price)
        self.db.execute('INSERT INTO fills(order_id,at,kind,volume,price,spread,slippage,pnl,commission,reason) VALUES(?,?,?,?,?,?,?,?,?,?)',
            (o['id'],now,'EXIT',volume,price,q.ask-q.bid,abs(raw-price),pnl,volume*self.c['commission_per_lot_side'],reason))
        remaining=round(o['remaining']-volume,8)
        self.db.execute("UPDATE orders SET remaining=?,status=?,reason=? WHERE id=?",(remaining,'CLOSED' if remaining<1e-8 else 'OPEN',reason,o['id']))
