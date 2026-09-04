#ifndef SMA_PERSISTENCE_STATE_STORE_MQH
#define SMA_PERSISTENCE_STATE_STORE_MQH

string ShortStateKey(ulong positionIdentifier, string field)
{
   return StringFormat("S55.%I64d.%s.%I64u.%s", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol,
                       positionIdentifier, field);
}

double ShortStateRead(ulong positionIdentifier, string field)
{
   string key = ShortStateKey(positionIdentifier, field);
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : 0.0;
}

void ShortStateWrite(ulong positionIdentifier, string field, double value)
{
   if(positionIdentifier > 0) GlobalVariableSet(ShortStateKey(positionIdentifier, field), value);
}

void ShortStateSave(int stateIdx)
{
   PerformanceScope perfScope(PERF_SHORT_STATE_SAVE);
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   TicketState st = states[stateIdx];
   if(!st.shortStateManaged || st.positionIdentifier == 0) return;
   ulong id = st.positionIdentifier;
   ShortStateWrite(id, "V", 6.0);
   ShortStateWrite(id, "TK", (double)st.ticket);
   ShortStateWrite(id, "OT", (double)st.positionOpenTime);
   ShortStateWrite(id, "DR", (double)st.positionDirection);
   ShortStateWrite(id, "ATM", (double)st.adoptedTemplate);
   ShortStateWrite(id, "IV", st.initialVolume);
   ShortStateWrite(id, "IR", st.shortInitialRisk);
   ShortStateWrite(id, "ISL", st.shortInitialSL);
   ShortStateWrite(id, "ASL", st.shortActualInitialSL);
   ShortStateWrite(id, "RR", st.shortRiskReady ? 1.0 : 0.0);
   ShortStateWrite(id, "SC", st.shortInitialSLConfirmed ? 1.0 : 0.0);
   ShortStateWrite(id, "RU", st.shortRiskUnknown ? 1.0 : 0.0);
   ShortStateWrite(id, "MP", st.maxProfitPrice);
   ShortStateWrite(id, "ML", st.maxLossPrice);
   ShortStateWrite(id, "MPM", st.maxProfitMoney);
   ShortStateWrite(id, "MLM", st.maxLossMoney);
   ShortStateWrite(id, "LRN", st.lifecycleRealizedNetMoney);
   ShortStateWrite(id, "MLP", st.maxLifecycleProfitMoney);
   ShortStateWrite(id, "MLL", st.maxLifecycleLossMoney);
   ShortStateWrite(id, "LPE", st.lifecyclePnlEnvelopeInitialized ? 1.0 : 0.0);
   ShortStateWrite(id, "PS", (double)st.partialTPStage);
   ShortStateWrite(id, "PT", (double)st.lastPartialTPTime);
   ShortStateWrite(id, "PP", st.lastPartialTPProfit);
   ShortStateWrite(id, "PD", st.partialTPDone ? 1.0 : 0.0);
   ShortStateWrite(id, "PEN", st.partialRequestPending ? 1.0 : 0.0);
   ShortStateWrite(id, "PST", (double)st.pendingPartialStage);
   ShortStateWrite(id, "PV", st.pendingPartialVolume);
   ShortStateWrite(id, "PF", st.pendingPartialFilledVolume);
   ShortStateWrite(id, "PSV", st.pendingPartialStartVolume);
   ShortStateWrite(id, "PQT", (double)st.pendingPartialRequestTime);
   ShortStateWrite(id, "F1", st.partialFilledVolumeStage1);
   ShortStateWrite(id, "F2", st.partialFilledVolumeStage2);
   ShortStateWrite(id, "F3", st.partialFilledVolumeStage3);
   ShortStateWrite(id, "LD", (double)st.lastShortDeal);
   ShortStateWrite(id, "RM", (double)st.runnerMode);
   ShortStateWrite(id, "FR", st.fixedTPRemoved ? 1.0 : 0.0);
   ShortStateWrite(id, "FP", st.fastProtectionActivated ? 1.0 : 0.0);
   ShortStateWrite(id, "FT", (double)st.fastProtectionTime);
   ShortStateWrite(id, "MR", (double)st.confirmedMarketRegime);
   ShortStateWrite(id, "CR", (double)st.candidateMarketRegime);
   ShortStateWrite(id, "RC", (double)st.candidateRegimeCount);
   ShortStateWrite(id, "RT", (double)st.regimeChangedTime);
   ShortStateWrite(id, "TA", (double)st.tradeArchetype);
   ShortStateWrite(id, "LP", (double)st.lifecyclePhase);
   ShortStateWrite(id, "PG", (double)st.protectionStage);
   ShortStateWrite(id, "PA", (double)st.pendingAction);
   ShortStateWrite(id, "PAT", (double)st.pendingActionTime);
   ShortStateWrite(id, "PRQ", (double)st.pendingRequestId);
   ShortStateWrite(id, "POR", (double)st.pendingOrder);
   ShortStateWrite(id, "PDE", (double)st.pendingDeal);
   ShortStateWrite(id, "PSL", st.pendingRequestedSL);
   ShortStateWrite(id, "PTP", st.pendingRequestedTP);
   ShortStateWrite(id, "PVO", st.pendingRequestedVolume);
   ShortStateWrite(id, "PSV2", st.pendingStartVolume);
   ShortStateWrite(id, "PSS", (double)st.pendingSLSource);
   ShortStateWrite(id, "PTS", (double)st.pendingTPSource);
   ShortStateWrite(id, "PEI", (double)st.pendingExitIntent);
   ShortStateWrite(id, "PFP", st.pendingFastProtection ? 1.0 : 0.0);
   ShortStateWrite(id, "PFSL", st.pendingFastProtectionSL);
   ShortStateWrite(id, "PFR", st.pendingFixedTPRemoval ? 1.0 : 0.0);
   ShortStateWrite(id, "CDT", (double)st.closeDetectedTime);
   ShortStateWrite(id, "FRC", (double)st.finalizeRetryCount);
   ShortStateWrite(id, "FIN", st.tradeFinalized ? 1.0 : 0.0);
   ShortStateWrite(id, "SMC", (double)st.slModifyCount);
   ShortStateWrite(id, "TMC", (double)st.tpModifyCount);
   ShortStateWrite(id, "PFC", (double)st.partialFillCount);
   ShortStateWrite(id, "LSS", (double)st.lastConfirmedSLSource);
   ShortStateWrite(id, "LTS", (double)st.lastConfirmedTPSource);
   ShortStateWrite(id, "EXI", (double)st.exitIntent);
   ShortStateWrite(id, "LMT", (double)st.lastManagedModifyTime);
   ShortStateWrite(id, "LKV", st.lastKnownVolume);
   ShortStateWrite(id, "LKP", st.lastKnownOpenPrice);
   ShortStateWrite(id, "EVC", st.externalVolumeChangeDetected ? 1.0 : 0.0);
   ShortStateWrite(id, "EVT", (double)st.externalVolumeChangeTime);
   ShortStateWrite(id, "PEF", st.pendingExitFilledVolume);
   ShortStateWrite(id, "PRC", (double)st.pendingRetryCount);
   ShortStateWrite(id, "LED", (double)st.lastLifecycleExitDeal);
   ShortStateWrite(id, "RBT", (double)st.lastRegimeClosedBarTime);
   ShortStateWrite(id, "NRV", st.nettingReversalDetected ? 1.0 : 0.0);
   ShortStateWrite(id, "LST", (double)st.lifecycleSegmentStartTime);
   ShortStateWrite(id, "FTPS", st.floatingProfitSeconds);
   ShortStateWrite(id, "FTLS", st.floatingLossSeconds);
   ShortStateWrite(id, "FTFS", st.floatingFlatSeconds);
   ShortStateWrite(id, "FTLL", st.longestFloatingLossSeconds);
   ShortStateWrite(id, "FTFP", (double)st.firstFloatingProfitTime);
   ShortStateWrite(id, "FTOS", (double)st.floatingTimingObservationStartTime);
   ShortStateWrite(id, "FTHD", st.floatingTimingHasData ? 1.0 : 0.0);
   ShortStateWrite(id, "FTFN", st.floatingTimingFinalized ? 1.0 : 0.0);
   states[stateIdx].lastStateSaveTime = TimeCurrent();
   states[stateIdx].lastSavedVersion = st.stateVersion;
   states[stateIdx].stateDirty = (states[stateIdx].stateVersion != st.stateVersion);
}

void MarkShortStateDirty(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   states[stateIdx].stateDirty = true;
   states[stateIdx].stateVersion++;
}

bool FlushShortStateIfNeeded(int stateIdx, bool force)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return false;
   if(!states[stateIdx].shortStateManaged || states[stateIdx].positionIdentifier == 0) return false;
   if(!force && !states[stateIdx].stateDirty && states[stateIdx].stateVersion == states[stateIdx].lastSavedVersion)
      return false;

   datetime now = TimeCurrent();
   if(!force && states[stateIdx].lastStateSaveTime > 0 && now >= states[stateIdx].lastStateSaveTime &&
      now-states[stateIdx].lastStateSaveTime < 5)
      return false;

   ShortStateSave(stateIdx);
   return (!states[stateIdx].stateDirty && states[stateIdx].lastSavedVersion == states[stateIdx].stateVersion);
}

void FlushAllDirtyShortStates(bool force)
{
   for(int i=0; i<ArraySize(states); i++)
      FlushShortStateIfNeeded(i, force);
}

bool ShortStateLoad(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return false;
   TicketState st = states[stateIdx];
   if(st.positionIdentifier == 0 || ShortStateRead(st.positionIdentifier, "V") < 1.0) return false;
   datetime savedOpenTime = (datetime)ShortStateRead(st.positionIdentifier, "OT");
   int savedDirection = (int)ShortStateRead(st.positionIdentifier, "DR");
   if(savedOpenTime != st.positionOpenTime || savedDirection != st.positionDirection)
   {
      PrintFormat("[短线状态] 拒绝恢复 id=%I64u：开仓时间或方向不一致", st.positionIdentifier);
      return false;
   }
   st.shortStateManaged = true;
   string adoptedTemplateKey = ShortStateKey(st.positionIdentifier, "ATM");
   if(GlobalVariableCheck(adoptedTemplateKey))
      st.adoptedTemplate = (int)GlobalVariableGet(adoptedTemplateKey);
   st.initialVolume = ShortStateRead(st.positionIdentifier, "IV");
   st.shortInitialRisk = ShortStateRead(st.positionIdentifier, "IR");
   st.shortInitialSL = ShortStateRead(st.positionIdentifier, "ISL");
   st.shortActualInitialSL = ShortStateRead(st.positionIdentifier, "ASL");
   st.shortRiskReady = (ShortStateRead(st.positionIdentifier, "RR") > 0.5 && st.shortInitialRisk > 0.0);
   st.shortInitialSLConfirmed = (ShortStateRead(st.positionIdentifier, "SC") > 0.5);
   st.shortRiskUnknown = (ShortStateRead(st.positionIdentifier, "RU") > 0.5);
   st.maxProfitPrice = ShortStateRead(st.positionIdentifier, "MP");
   st.maxLossPrice = ShortStateRead(st.positionIdentifier, "ML");
   st.maxProfitMoney = ShortStateRead(st.positionIdentifier, "MPM");
   st.maxLossMoney = ShortStateRead(st.positionIdentifier, "MLM");
   st.lifecycleRealizedNetMoney = ShortStateRead(st.positionIdentifier, "LRN");
   st.maxLifecycleProfitMoney = MathMax(ShortStateRead(st.positionIdentifier, "MLP"),0.0);
   st.maxLifecycleLossMoney = MathMax(ShortStateRead(st.positionIdentifier, "MLL"),0.0);
   st.lifecyclePnlEnvelopeInitialized = (ShortStateRead(st.positionIdentifier, "LPE") > 0.5);
   st.partialTPStage = (int)ShortStateRead(st.positionIdentifier, "PS");
   st.lastPartialTPTime = (datetime)ShortStateRead(st.positionIdentifier, "PT");
   st.lastPartialTPProfit = ShortStateRead(st.positionIdentifier, "PP");
   st.partialTPDone = (ShortStateRead(st.positionIdentifier, "PD") > 0.5);
   st.partialRequestPending = (ShortStateRead(st.positionIdentifier, "PEN") > 0.5);
   st.pendingPartialStage = (int)ShortStateRead(st.positionIdentifier, "PST");
   st.pendingPartialVolume = ShortStateRead(st.positionIdentifier, "PV");
   st.pendingPartialFilledVolume = ShortStateRead(st.positionIdentifier, "PF");
   st.pendingPartialStartVolume = ShortStateRead(st.positionIdentifier, "PSV");
   st.pendingPartialRequestTime = (datetime)ShortStateRead(st.positionIdentifier, "PQT");
   st.partialFilledVolumeStage1 = ShortStateRead(st.positionIdentifier, "F1");
   st.partialFilledVolumeStage2 = ShortStateRead(st.positionIdentifier, "F2");
   st.partialFilledVolumeStage3 = ShortStateRead(st.positionIdentifier, "F3");
   st.lastShortDeal = (ulong)ShortStateRead(st.positionIdentifier, "LD");
   st.runnerMode = (int)ShortStateRead(st.positionIdentifier, "RM");
   st.fixedTPRemoved = (ShortStateRead(st.positionIdentifier, "FR") > 0.5);
   st.fastProtectionActivated = (ShortStateRead(st.positionIdentifier, "FP") > 0.5);
   st.fastProtectionTime = (datetime)ShortStateRead(st.positionIdentifier, "FT");
   st.confirmedMarketRegime = (int)ShortStateRead(st.positionIdentifier, "MR");
   st.candidateMarketRegime = (int)ShortStateRead(st.positionIdentifier, "CR");
   st.candidateRegimeCount = (int)ShortStateRead(st.positionIdentifier, "RC");
   st.regimeChangedTime = (datetime)ShortStateRead(st.positionIdentifier, "RT");
   st.tradeArchetype = (int)ShortStateRead(st.positionIdentifier, "TA");
   st.lifecyclePhase = (int)ShortStateRead(st.positionIdentifier, "LP");
   st.protectionStage = (int)ShortStateRead(st.positionIdentifier, "PG");
   st.pendingAction = (int)ShortStateRead(st.positionIdentifier, "PA");
   st.pendingActionTime = (datetime)ShortStateRead(st.positionIdentifier, "PAT");
   st.pendingRequestId = (ulong)ShortStateRead(st.positionIdentifier, "PRQ");
   st.pendingOrder = (ulong)ShortStateRead(st.positionIdentifier, "POR");
   st.pendingDeal = (ulong)ShortStateRead(st.positionIdentifier, "PDE");
   st.pendingRequestedSL = ShortStateRead(st.positionIdentifier, "PSL");
   st.pendingRequestedTP = ShortStateRead(st.positionIdentifier, "PTP");
   st.pendingRequestedVolume = ShortStateRead(st.positionIdentifier, "PVO");
   st.pendingStartVolume = ShortStateRead(st.positionIdentifier, "PSV2");
   st.pendingSLSource = (int)ShortStateRead(st.positionIdentifier, "PSS");
   st.pendingTPSource = (int)ShortStateRead(st.positionIdentifier, "PTS");
   st.pendingExitIntent = (int)ShortStateRead(st.positionIdentifier, "PEI");
   st.pendingFastProtection = (ShortStateRead(st.positionIdentifier, "PFP") > 0.5);
   st.pendingFastProtectionSL = ShortStateRead(st.positionIdentifier, "PFSL");
   st.pendingFixedTPRemoval = (ShortStateRead(st.positionIdentifier, "PFR") > 0.5);
   st.closeDetectedTime = (datetime)ShortStateRead(st.positionIdentifier, "CDT");
   st.finalizeRetryCount = (int)ShortStateRead(st.positionIdentifier, "FRC");
   st.tradeFinalized = (ShortStateRead(st.positionIdentifier, "FIN") > 0.5);
   st.slModifyCount = (int)ShortStateRead(st.positionIdentifier, "SMC");
   st.tpModifyCount = (int)ShortStateRead(st.positionIdentifier, "TMC");
   st.partialFillCount = (int)ShortStateRead(st.positionIdentifier, "PFC");
   st.lastConfirmedSLSource = (int)ShortStateRead(st.positionIdentifier, "LSS");
   st.lastConfirmedTPSource = (int)ShortStateRead(st.positionIdentifier, "LTS");
   st.exitIntent = (int)ShortStateRead(st.positionIdentifier, "EXI");
   st.lastManagedModifyTime = (datetime)ShortStateRead(st.positionIdentifier, "LMT");
   st.lastKnownVolume = ShortStateRead(st.positionIdentifier, "LKV");
   st.lastKnownOpenPrice = ShortStateRead(st.positionIdentifier, "LKP");
   st.externalVolumeChangeDetected = (ShortStateRead(st.positionIdentifier, "EVC") > 0.5);
   st.externalVolumeChangeTime = (datetime)ShortStateRead(st.positionIdentifier, "EVT");
   st.pendingExitFilledVolume = ShortStateRead(st.positionIdentifier, "PEF");
   st.pendingRetryCount = (int)ShortStateRead(st.positionIdentifier, "PRC");
   st.lastLifecycleExitDeal = (ulong)ShortStateRead(st.positionIdentifier, "LED");
   st.lastRegimeClosedBarTime = (datetime)ShortStateRead(st.positionIdentifier, "RBT");
   st.nettingReversalDetected = (ShortStateRead(st.positionIdentifier, "NRV") > 0.5);
   st.lifecycleSegmentStartTime = (datetime)ShortStateRead(st.positionIdentifier, "LST");
   st.floatingProfitSeconds = MathMax(ShortStateRead(st.positionIdentifier, "FTPS"),0.0);
   st.floatingLossSeconds = MathMax(ShortStateRead(st.positionIdentifier, "FTLS"),0.0);
   st.floatingFlatSeconds = MathMax(ShortStateRead(st.positionIdentifier, "FTFS"),0.0);
   st.longestFloatingLossSeconds = MathMax(ShortStateRead(st.positionIdentifier, "FTLL"),0.0);
   st.firstFloatingProfitTime = (datetime)ShortStateRead(st.positionIdentifier, "FTFP");
   st.floatingTimingObservationStartTime = (datetime)ShortStateRead(st.positionIdentifier, "FTOS");
   st.floatingTimingHasData = (ShortStateRead(st.positionIdentifier, "FTHD") > 0.5);
   st.floatingTimingFinalized = (ShortStateRead(st.positionIdentifier, "FTFN") > 0.5);
   if(st.lastKnownVolume <= 0.0 && PositionSelectByTicket(st.ticket))
      st.lastKnownVolume = PositionGetDouble(POSITION_VOLUME);
   if(st.lastKnownOpenPrice <= 0.0 && PositionSelectByTicket(st.ticket))
      st.lastKnownOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   st.stateDirty = false;
   st.lastStateSaveTime = TimeCurrent();
   st.stateVersion = 0;
   st.lastSavedVersion = 0;
   st.entryCostCacheReady = false;
   st.cachedEntryCost = 0.0;
   st.entryCostCacheTime = 0;
   st.entryCostCacheVolume = 0.0;
   st.entryCostCacheVersion = 0;
   // GetTickCount64不能跨终端会话恢复；离线时段保持未知，不续接旧连续段。
   st.floatingTimingCurrentState = 浮动状态_未知;
   st.floatingTimingCurrentStateSeconds = 0.0;
   st.floatingTimingLastSampleMs = 0;
   st.floatingTimingSampleReady = false;
   st.floatingTimingLastPersistObservedSeconds = st.floatingProfitSeconds+
                                                  st.floatingLossSeconds+
                                                  st.floatingFlatSeconds;
   st.floatingTimingSwitchCount = 0;
   st.floatingTimingEntryCostAttempted = false;
   PrintFormat("[短线状态] 已恢复 id=%I64u 初始手数=%.2f R=%s 分批=%d", st.positionIdentifier,
               st.initialVolume, st.shortRiskReady ? DoubleToString(st.shortInitialRisk, 2) : "未知", st.partialTPStage);
   states[stateIdx] = st;
   return true;
}

void ShortStateDelete(ulong positionIdentifier)
{
   if(positionIdentifier == 0) return;
   string fields[] = {"V","TK","OT","DR","ATM","IV","IR","ISL","ASL","RR","SC","RU","MP","ML","MPM","MLM","LRN","MLP","MLL","LPE",
                      "PS","PT","PP","PD","PEN","PST","PV","PF","PSV","PQT","F1","F2","F3","LD","RM",
                      "FR","FP","FT","MR","CR","RC","RT","TA","LP","PG","PA","PAT","PRQ","POR","PDE",
                      "PSL","PTP","PVO","PSV2","PSS","PTS","PEI","PFP","PFSL","PFR","CDT","FRC","FIN",
                      "SMC","TMC","PFC","LSS","LTS","EXI","LMT","LKV","LKP","EVC","EVT",
                      "PEF","PRC","LED","RBT","NRV","LST",
                      "FTPS","FTLS","FTFS","FTLL","FTFP","FTOS","FTHD","FTFN"};
   for(int i=0; i<ArraySize(fields); i++) GlobalVariableDel(ShortStateKey(positionIdentifier, fields[i]));
}

void ShortStateRestoreAll()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionInScope()) continue;
      EnsureState(ticket);
   }

   // 持仓可能已经消失但Summary尚未写完；重启后仍需从Global Variables接回等待结算状态。
   string prefix = StringFormat("S55.%I64d.%s.", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol);
   int prefixLen = StringLen(prefix);
   for(int g=GlobalVariablesTotal()-1; g>=0; g--)
   {
      string name = GlobalVariableName(g);
      int nameLen = StringLen(name);
      if(StringFind(name, prefix) != 0 || nameLen <= prefixLen+2 || StringSubstr(name, nameLen-2) != ".V") continue;
      ulong positionId = (ulong)StringToInteger(StringSubstr(name, prefixLen, nameLen-prefixLen-2));
      if(positionId == 0) continue;
      bool alreadyLoaded = false;
      for(int s=0; s<ArraySize(states); s++)
      {
         if(states[s].positionIdentifier == positionId) { alreadyLoaded = true; break; }
      }
      if(alreadyLoaded) continue;
      string summaryKey = StringFormat("S55.SUMMARY.%I64d.%s.%I64u", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol, positionId);
      if(GlobalVariableCheck(summaryKey)) continue;

      ulong savedTicket = (ulong)ShortStateRead(positionId, "TK");
      int stateIdx = EnsureState(savedTicket);
      states[stateIdx].positionIdentifier = positionId;
      states[stateIdx].positionOpenTime = (datetime)ShortStateRead(positionId, "OT");
      states[stateIdx].positionDirection = (int)ShortStateRead(positionId, "DR");
      if(!ShortStateLoad(stateIdx))
      {
         int last = ArraySize(states)-1;
         if(stateIdx != last) states[stateIdx] = states[last];
         ArrayResize(states,last);
         continue;
      }
      if(!PositionSelectByTicket(savedTicket))
      {
         states[stateIdx].lifecyclePhase = 生命周期_等待最终结算;
         if(states[stateIdx].closeDetectedTime == 0) states[stateIdx].closeDetectedTime = TimeCurrent();
         MarkShortStateDirty(stateIdx);
         PrintFormat("[短线状态] 重启接回待结算生命周期 id=%I64u ticket=%I64u", positionId, savedTicket);
         TradeJournalWriteLifecycle(stateIdx, "STATE_RECONCILED_AFTER_RESTART",
                                    "position_not_live;restored_waiting_finalization");
      }
   }
}

#endif
