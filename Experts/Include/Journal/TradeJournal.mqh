#ifndef SMA_JOURNAL_TRADE_JOURNAL_MQH
#define SMA_JOURNAL_TRADE_JOURNAL_MQH

string TradeJournalFileName(string kind)
{
   return StringFormat("SMA_%s_%I64d.csv", kind, AccountInfoInteger(ACCOUNT_LOGIN));
}

int TradeJournalOpen(string kind, string &header[])
{
   int handle = FileOpen(TradeJournalFileName(kind), FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_COMMON|FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintRateLimited("journal_open:"+kind+":"+IntegerToString(err), 10,
                       StringFormat("[交易日志] 打开%s失败 err=%d", kind, err));
      return INVALID_HANDLE;
   }
   if(FileSize(handle) == 0)
   {
      string headerLine = "";
      for(int i=0; i<ArraySize(header); i++)
      {
         if(i > 0) headerLine += ",";
         headerLine += header[i];
      }
      FileWriteString(handle, headerLine+"\r\n");
   }
   FileSeek(handle, 0, SEEK_END);
   return handle;
}

bool TradeJournalDealSeen(ulong dealTicket)
{
   for(int i=0; i<processedJournalDealCount; i++)
      if(processedJournalDealTickets[i] == dealTicket) return true;
   return false;
}

void TradeJournalMarkDealSeen(ulong dealTicket)
{
   if(dealTicket == 0 || TradeJournalDealSeen(dealTicket)) return;
   if(processedJournalDealCount < ArraySize(processedJournalDealTickets))
      processedJournalDealTickets[processedJournalDealCount++] = dealTicket;
   else
   {
      for(int i=1; i<ArraySize(processedJournalDealTickets); i++)
         processedJournalDealTickets[i-1] = processedJournalDealTickets[i];
      processedJournalDealTickets[ArraySize(processedJournalDealTickets)-1] = dealTicket;
   }
}

bool TradeJournalDealInScope(ulong dealTicket)
{
   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) return false;
   ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   // 生命周期归属优先使用positionIdentifier，出场Deal的Magic可能与入场Magic不同。
   for(int i=0; i<ArraySize(states); i++)
      if(positionId > 0 && states[i].positionIdentifier == positionId) return true;
   long magic = (long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(只管理手动单) return magic == 0;
   return magic == 指定管理Magic;
}

void TradeJournalWriteDeal(ulong dealTicket, string source)
{
   PerformanceScope perfScope(PERF_TRADE_JOURNAL);
   if(!启用交易生命周期记录 || !交易生命周期记录原始Deal || dealTicket == 0) return;
   if(TradeJournalDealSeen(dealTicket) || !HistoryDealSelect(dealTicket) || !TradeJournalDealInScope(dealTicket)) return;
   string header[] = {"record_time","source","login","symbol","deal_ticket","position_id","order_ticket",
                      "entry","deal_type","reason","deal_time_msc","volume","price","profit","commission","swap","fee","magic"};
   int handle = TradeJournalOpen("TradeDeals", header);
   if(handle == INVALID_HANDLE) return;
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), source,
             (string)AccountInfoInteger(ACCOUNT_LOGIN), HistoryDealGetString(dealTicket, DEAL_SYMBOL),
             (string)dealTicket, (string)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID),
             (string)HistoryDealGetInteger(dealTicket, DEAL_ORDER),
             (string)HistoryDealGetInteger(dealTicket, DEAL_ENTRY), (string)HistoryDealGetInteger(dealTicket, DEAL_TYPE),
             (string)HistoryDealGetInteger(dealTicket, DEAL_REASON), (string)HistoryDealGetInteger(dealTicket, DEAL_TIME_MSC),
             DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 2),
             DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_PRICE), _Digits),
             DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_PROFIT), 2),
             DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_COMMISSION), 2),
             DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_SWAP), 2),
             DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_FEE), 2),
             (string)HistoryDealGetInteger(dealTicket, DEAL_MAGIC));
   FileClose(handle);
   TradeJournalMarkDealSeen(dealTicket);
}

void TradeJournalWriteLifecycle(int stateIdx, string eventName, string detail)
{
   PerformanceScope perfScope(PERF_TRADE_JOURNAL);
   if(!启用交易生命周期记录 || stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   TicketState st = states[stateIdx];
   bool live = PositionSelectByTicket(st.ticket);
   ENUM_POSITION_TYPE type = live ? (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) : (ENUM_POSITION_TYPE)st.positionDirection;
   double openPrice = live ? PositionGetDouble(POSITION_PRICE_OPEN) : 0.0;
   double volume = live ? PositionGetDouble(POSITION_VOLUME) : 0.0;
   double sl = live ? PositionGetDouble(POSITION_SL) : 0.0;
   double tp = live ? PositionGetDouble(POSITION_TP) : 0.0;
   double positionMoney = live ? PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP) : 0.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = type == POSITION_TYPE_BUY ? bid : ask;
   double profitPrice = (live && currentPrice > 0.0) ?
                        (type == POSITION_TYPE_BUY ? currentPrice-openPrice : openPrice-currentPrice) : 0.0;
   double floatingObservedSeconds = st.floatingProfitSeconds+st.floatingLossSeconds+st.floatingFlatSeconds;
   double floatingHoldSeconds = st.positionOpenTime > 0 && TimeCurrent() > st.positionOpenTime ?
                                (double)(TimeCurrent()-st.positionOpenTime) : 0.0;
   double floatingCoverageRatio = floatingHoldSeconds > 0.0 ?
                                  MathMin(floatingObservedSeconds/floatingHoldSeconds,1.0) : 0.0;
   double atr = 0.0;
   GetATRPrice(atr);
   string header[] = {"record_time","event","detail","login","symbol","template","ticket","position_id","direction",
                      "open_time","open_price","current_price","current_volume","initial_volume","sl","tp","profit_price","profit_money",
                      "initial_sl_request","initial_sl_actual","initial_r","risk_ready","risk_unknown","max_profit_price","max_loss_price",
                      "max_profit_money","max_loss_money","partial_stage","partial_pending","pending_stage","pending_volume","pending_filled",
                      "filled_stage1","filled_stage2","filled_stage3","runner_mode","fixed_tp_removed","fast_protection","market_regime",
                      "trade_archetype","spread_price","atr_m1","position_live",
                      "lifecycle_phase","protection_stage","pending_action","pending_requested_sl","pending_requested_tp",
                      "pending_requested_volume","pending_exit_intent","confirmed_sl_source","confirmed_tp_source","exit_intent",
                      "floating_profit_seconds","floating_loss_seconds","floating_flat_seconds","longest_floating_loss_seconds",
                      "first_floating_profit_time","floating_timing_observation_start_time","floating_timing_observed_seconds",
                      "floating_timing_coverage_ratio","floating_timing_has_data"};
   int handle = TradeJournalOpen("TradeLifecycle", header);
   if(handle == INVALID_HANDLE) return;
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), eventName, detail,
             (string)AccountInfoInteger(ACCOUNT_LOGIN), _Symbol, (string)st.adoptedTemplate,
             (string)st.ticket, (string)st.positionIdentifier, (string)((int)type),
             TimeToString(st.positionOpenTime, TIME_DATE|TIME_SECONDS),
             DoubleToString(openPrice, _Digits), DoubleToString(currentPrice, _Digits), DoubleToString(volume, 2), DoubleToString(st.initialVolume, 2),
             DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), DoubleToString(profitPrice, _Digits), DoubleToString(positionMoney, 2),
             DoubleToString(st.shortInitialSL, _Digits), DoubleToString(st.shortActualInitialSL, _Digits), DoubleToString(st.shortInitialRisk, _Digits),
             st.shortRiskReady ? "1" : "0", st.shortRiskUnknown ? "1" : "0",
             DoubleToString(st.maxProfitPrice, _Digits), DoubleToString(st.maxLossPrice, _Digits),
             DoubleToString(st.maxProfitMoney, 2), DoubleToString(st.maxLossMoney, 2),
             (string)st.partialTPStage, st.partialRequestPending ? "1" : "0", (string)st.pendingPartialStage,
             DoubleToString(st.pendingPartialVolume, 2), DoubleToString(st.pendingPartialFilledVolume, 2),
             DoubleToString(st.partialFilledVolumeStage1, 2), DoubleToString(st.partialFilledVolumeStage2, 2), DoubleToString(st.partialFilledVolumeStage3, 2),
             (string)st.runnerMode, st.fixedTPRemoved ? "1" : "0", st.fastProtectionActivated ? "1" : "0",
             (string)st.confirmedMarketRegime, (string)st.tradeArchetype,
             DoubleToString(MathMax(ask-bid, 0.0), _Digits), DoubleToString(atr, _Digits), live ? "1" : "0",
             (string)st.lifecyclePhase, (string)st.protectionStage, (string)st.pendingAction,
             DoubleToString(st.pendingRequestedSL, _Digits), DoubleToString(st.pendingRequestedTP, _Digits),
             DoubleToString(st.pendingRequestedVolume, 2), (string)st.pendingExitIntent,
             (string)st.lastConfirmedSLSource, (string)st.lastConfirmedTPSource, (string)st.exitIntent,
             DoubleToString(st.floatingProfitSeconds,3),DoubleToString(st.floatingLossSeconds,3),
             DoubleToString(st.floatingFlatSeconds,3),DoubleToString(st.longestFloatingLossSeconds,3),
             (string)st.firstFloatingProfitTime,(string)st.floatingTimingObservationStartTime,
             DoubleToString(floatingObservedSeconds,3),DoubleToString(floatingCoverageRatio,6),
             st.floatingTimingHasData ? "1" : "0");
   FileClose(handle);
}

void TradeJournalWriteSnapshots()
{
   PerformanceScope perfScope(PERF_TRADE_JOURNAL);
   if(!启用交易生命周期记录) return;
   int interval = MathMax(交易生命周期快照秒数, 10);
   datetime now = TimeCurrent();
   for(int i=0; i<ArraySize(states); i++)
   {
      if(now-states[i].lifecycleLastSnapshotTime < interval) continue;
      TradeJournalWriteLifecycle(i, "SNAPSHOT", "periodic_open_position_state");
      states[i].lifecycleLastSnapshotTime = now;
   }
}

string TradeJournalImportKey()
{
   return StringFormat("S55.JOURNAL.IMPORT.%I64d.%s", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol);
}

void TradeJournalImportAvailableHistory()
{
   if(!启用交易生命周期记录 || !交易生命周期记录原始Deal || !交易生命周期启动时导入终端历史) return;
   string key = TradeJournalImportKey();
   if(GlobalVariableCheck(key) || !HistorySelect(0, TimeCurrent())) return;
   int imported = 0;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || !TradeJournalDealInScope(deal)) continue;
      TradeJournalWriteDeal(deal, "startup_history_import");
      imported++;
   }
   GlobalVariableSet(key, (double)TimeCurrent());
   PrintFormat("[交易日志] 已补录当前品种/管理范围的终端历史Deal: %d", imported);
}

#endif
