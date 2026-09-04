#ifndef SMA_JOURNAL_TRADE_SUMMARY_MQH
#define SMA_JOURNAL_TRADE_SUMMARY_MQH

string TradeSummaryKey(ulong positionIdentifier)
{
   return StringFormat("S55.SUMMARY.%I64d.%s.%I64u", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol, positionIdentifier);
}

bool TradeJournalSummaryWritten(ulong positionIdentifier)
{
   return positionIdentifier > 0 && GlobalVariableCheck(TradeSummaryKey(positionIdentifier));
}

// 仓位消失后才汇总历史Deal；成功写入一行Summary后才允许清理持久化状态。
bool FinalizeTradeLifecycle(int stateIdx)
{
   PerformanceScope perfScope(PERF_HISTORY_QUERY);
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return false;
   FinalizeFloatingPnlTiming(stateIdx);
   TicketState st = states[stateIdx];
   if(st.tradeFinalized || TradeJournalSummaryWritten(st.positionIdentifier))
   {
      st.tradeFinalized = true;
      st.lifecyclePhase = 生命周期_已结束;
      states[stateIdx] = st;
      return true;
   }
   if(st.positionIdentifier == 0 || !HistorySelectByPosition(st.positionIdentifier)) return false;
   double entryVolume=0.0, exitVolume=0.0, entryValue=0.0, exitValue=0.0;
   double gross=0.0, commission=0.0, swap=0.0, fee=0.0;
   double cumulativeDealNet=0.0, maxCumulativeDealNet=0.0, minCumulativeDealNet=0.0;
   datetime firstEntry=0, lastExit=0;
   ulong lastExitDeal=0;
   double lastExitPrice=0.0;
   long actualExitReason=0;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      double vol = HistoryDealGetDouble(deal, DEAL_VOLUME);
      double price = HistoryDealGetDouble(deal, DEAL_PRICE);
      datetime time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(st.lifecycleSegmentStartTime > 0 && time < st.lifecycleSegmentStartTime) continue;
      bool reversalEntry = (st.nettingReversalDetected && entry == DEAL_ENTRY_INOUT &&
                            st.lifecycleSegmentStartTime > 0 && MathAbs((long)(time-st.lifecycleSegmentStartTime)) <= 2);
      if(!reversalEntry)
      {
         double dealProfit = HistoryDealGetDouble(deal, DEAL_PROFIT);
         double dealCommission = HistoryDealGetDouble(deal, DEAL_COMMISSION);
         double dealSwap = HistoryDealGetDouble(deal, DEAL_SWAP);
         double dealFee = HistoryDealGetDouble(deal, DEAL_FEE);
         gross += dealProfit;
         commission += dealCommission;
         swap += dealSwap;
         fee += dealFee;
         cumulativeDealNet += dealProfit+dealCommission+dealSwap+dealFee;
         maxCumulativeDealNet = MathMax(maxCumulativeDealNet,cumulativeDealNet);
         minCumulativeDealNet = MathMin(minCumulativeDealNet,cumulativeDealNet);
      }
      if(entry == DEAL_ENTRY_IN || reversalEntry)
      {
         double effectiveEntryVolume = reversalEntry ? st.initialVolume : vol;
         entryVolume += effectiveEntryVolume;
         entryValue += effectiveEntryVolume*price;
         if(firstEntry == 0 || time < firstEntry) firstEntry = time;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
      {
         exitVolume += vol;
         exitValue += vol*price;
         if(time >= lastExit)
         {
            lastExit = time;
            lastExitDeal = deal;
            lastExitPrice = price;
            actualExitReason = HistoryDealGetInteger(deal, DEAL_REASON);
         }
      }
   }
   if(entryVolume <= 0.0 || exitVolume <= 0.0 || lastExit == 0) return false;
   if(states[stateIdx].pendingAction == 待确认动作_全部平仓)
   {
      TradeJournalWriteLifecycle(stateIdx, "FULL_CLOSE_FILL",
                                 StringFormat("history_confirmed;exit_volume=%.2f;last_deal=%I64u", exitVolume, lastExitDeal));
      ClearPendingTradeAction(stateIdx);
      states[stateIdx].lifecyclePhase = 生命周期_等待最终结算;
      st = states[stateIdx];
   }
   double entryPrice = entryValue/entryVolume, exitPrice = exitValue/exitVolume;
   double initialRMoney = 0.0;
   if(st.shortInitialRisk > _Point && st.initialVolume > 0.0)
   {
      ENUM_ORDER_TYPE orderType = st.positionDirection == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double riskClose = st.positionDirection == POSITION_TYPE_BUY ? entryPrice-st.shortInitialRisk : entryPrice+st.shortInitialRisk;
      if(!OrderCalcProfit(orderType, _Symbol, st.initialVolume, entryPrice, riskClose, initialRMoney))
         initialRMoney = 0.0;
      initialRMoney = MathAbs(initialRMoney);
   }
   double net = gross+commission+swap+fee;
   double cumulativeDealProfit = MathMax(maxCumulativeDealNet,0.0);
   double cumulativeDealLoss = minCumulativeDealNet < 0.0 ? -minCumulativeDealNet : 0.0;
   double finalProfit = net > 0.0 ? net : 0.0;
   double finalLoss = net < 0.0 ? -net : 0.0;
   st.maxLifecycleProfitMoney = MathMax(st.maxLifecycleProfitMoney,
                                        MathMax(cumulativeDealProfit,
                                                MathMax(st.maxProfitMoney,finalProfit)));
   st.maxLifecycleLossMoney = MathMax(st.maxLifecycleLossMoney,
                                      MathMax(cumulativeDealLoss,
                                              MathMax(st.maxLossMoney,finalLoss)));
   st.lifecycleRealizedNetMoney = net;
   st.lifecyclePnlEnvelopeInitialized = true;
   double mfeR = initialRMoney > 0.0 ? st.maxProfitMoney/initialRMoney : 0.0;
   double maeR = initialRMoney > 0.0 ? st.maxLossMoney/initialRMoney : 0.0;
   double realizedR = initialRMoney > 0.0 ? net/initialRMoney : 0.0;
   double capture = st.maxProfitMoney > 0.0 ? net/st.maxProfitMoney : 0.0;
   double floatingObservedSeconds = st.floatingProfitSeconds+st.floatingLossSeconds+st.floatingFlatSeconds;
   double totalHoldSeconds = lastExit > firstEntry ? (double)(lastExit-firstEntry) : 0.0;
   double floatingCoverageRatio = totalHoldSeconds > 0.0 ?
                                  MathMin(floatingObservedSeconds/totalHoldSeconds,1.0) : 0.0;
   string header[] = {"time_written","account","position_id","symbol","direction","template","trade_archetype",
                      "open_time","close_time","hold_seconds","initial_volume","entry_volume","exit_volume","entry_price","exit_price",
                      "initial_sl","initial_r_price","initial_r_money","max_profit_price","max_loss_price","max_profit_money","max_loss_money",
                      "mfe_r","mae_r","partial_stage_count","partial_fill_count","fast_protection","runner_mode","fixed_tp_removed",
                      "sl_modify_count","tp_modify_count","exit_intent","actual_exit_reason","last_exit_deal","last_exit_price",
                      "gross_profit","commission","swap","fee","net_profit","realized_r","profit_capture_ratio",
                      "floating_profit_seconds","floating_loss_seconds","floating_flat_seconds","longest_floating_loss_seconds",
                      "first_floating_profit_time","floating_timing_observation_start_time","floating_timing_observed_seconds",
                     "floating_timing_coverage_ratio","floating_timing_has_data",
                     "max_lifecycle_profit_money","max_lifecycle_loss_money"};
   int handle = TradeJournalOpen("TradeSummary", header);
   if(handle == INVALID_HANDLE) return false;
   FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), (string)AccountInfoInteger(ACCOUNT_LOGIN),
             (string)st.positionIdentifier, _Symbol, (string)st.positionDirection, (string)st.adoptedTemplate, (string)st.tradeArchetype,
             TimeToString(firstEntry, TIME_DATE|TIME_SECONDS), TimeToString(lastExit, TIME_DATE|TIME_SECONDS), (string)(lastExit-firstEntry),
             DoubleToString(st.initialVolume,2), DoubleToString(entryVolume,2), DoubleToString(exitVolume,2), DoubleToString(entryPrice,_Digits), DoubleToString(exitPrice,_Digits),
             DoubleToString(st.shortActualInitialSL,_Digits), DoubleToString(st.shortInitialRisk,_Digits), DoubleToString(initialRMoney,2),
             DoubleToString(st.maxProfitPrice,_Digits), DoubleToString(st.maxLossPrice,_Digits), DoubleToString(st.maxProfitMoney,2), DoubleToString(st.maxLossMoney,2),
             DoubleToString(mfeR,3), DoubleToString(maeR,3), (string)st.partialTPStage, (string)st.partialFillCount,
             st.fastProtectionActivated ? "1":"0", (string)st.runnerMode, st.fixedTPRemoved ? "1":"0", (string)st.slModifyCount, (string)st.tpModifyCount,
             (string)st.exitIntent, (string)actualExitReason, (string)lastExitDeal, DoubleToString(lastExitPrice,_Digits),
             DoubleToString(gross,2), DoubleToString(commission,2), DoubleToString(swap,2), DoubleToString(fee,2), DoubleToString(net,2),
             DoubleToString(realizedR,3), DoubleToString(capture,3),
             DoubleToString(st.floatingProfitSeconds,3),DoubleToString(st.floatingLossSeconds,3),
             DoubleToString(st.floatingFlatSeconds,3),DoubleToString(st.longestFloatingLossSeconds,3),
             (string)st.firstFloatingProfitTime,(string)st.floatingTimingObservationStartTime,
             DoubleToString(floatingObservedSeconds,3),DoubleToString(floatingCoverageRatio,6),
             st.floatingTimingHasData ? "1" : "0",
             DoubleToString(st.maxLifecycleProfitMoney,2),DoubleToString(st.maxLifecycleLossMoney,2));
   FileClose(handle);
   GlobalVariableSet(TradeSummaryKey(st.positionIdentifier), (double)TimeCurrent());
   InvalidateStatsCache();
   st.tradeFinalized = true;
   st.lifecyclePhase = 生命周期_已结束;
   states[stateIdx] = st;
   TradeJournalWriteLifecycle(stateIdx, "TRADE_FINALIZED",
                              StringFormat("position_id=%I64u;net_profit=%.2f;exit_deal=%I64u;exit_intent=%d;actual_exit_reason=%d",
                                           st.positionIdentifier, net, lastExitDeal, st.exitIntent, actualExitReason));
   return true;
}

#endif
