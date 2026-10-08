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

bool ShortStateWrite(ulong positionIdentifier, string field, double value)
{
   return positionIdentifier > 0 && MathIsValidNumber(value) &&
          GlobalVariableSet(ShortStateKey(positionIdentifier, field), value)>0;
}

bool ShortStateFieldsValid(ulong id, string &fields[])
{
   for(int i=0;i<ArraySize(fields);i++)
   {
      string key=ShortStateKey(id,fields[i]);
      if(!GlobalVariableCheck(key) || !MathIsValidNumber(GlobalVariableGet(key))) return false;
   }
   return true;
}

void ShortStateLoadProtectionFields(TicketState &st)
{
   ulong id=st.positionIdentifier;
   double tick=MathMax(_Point,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE));
   bool committed=(ShortStateRead(id,"V")>=7.0 && ShortStateRead(id,"PC")>0.5);
   st.trendRiskReady=false;
   st.trendRiskUnknown=(st.adoptedTemplate==(int)配置_黄金稳健托管);
   st.trendInitialRisk=0.0;
   st.trendInitialSL=0.0;
   st.trendHighSinceOpen=0.0;
   st.trendLowSinceOpen=0.0;
   if(PositionSelectByTicket(st.ticket))
   {
      double currentOpen=PositionGetDouble(POSITION_PRICE_OPEN);
      double currentVolume=PositionGetDouble(POSITION_VOLUME);
      double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=id ||
         (int)PositionGetInteger(POSITION_TYPE)!=st.positionDirection ||
         currentOpen<=0.0 || st.lastKnownOpenPrice<=0.0 ||
         MathAbs(currentOpen-st.lastKnownOpenPrice)>tick*1.5 ||
         (step>0.0 && currentVolume>st.lastKnownVolume+step*0.5))
         committed=false; // 离线期间组合改变，不能继承旧R/回本资格/老师计划。
   }
   string trendFields[]={"TRR","TRU","TIR","TIS","THI","TLO"};
   if(committed && ShortStateFieldsValid(id,trendFields))
   {
      st.trendRiskUnknown=ShortStateRead(id,"TRU")>0.5;
      st.trendInitialRisk=ShortStateRead(id,"TIR");
      st.trendInitialSL=ShortStateRead(id,"TIS");
      st.trendHighSinceOpen=MathMax(ShortStateRead(id,"THI"),0.0);
      st.trendLowSinceOpen=MathMax(ShortStateRead(id,"TLO"),0.0);
      if(ShortStateRead(id,"TRR")>0.5)
      {
         bool valid=st.lastKnownOpenPrice>0.0 && st.trendInitialRisk>tick &&
                    TrendLongSLIsRiskSide((ENUM_POSITION_TYPE)st.positionDirection,st.lastKnownOpenPrice,st.trendInitialSL) &&
                    MathAbs(MathAbs(st.lastKnownOpenPrice-st.trendInitialSL)-st.trendInitialRisk)<=tick*1.5;
         st.trendRiskReady=valid && !st.trendRiskUnknown;
         if(!valid) st.trendRiskUnknown=true;
      }
   }
   st.recoveryArmed=false;
   st.recoveryArmedTime=0;
   st.recoveryArmLossPrice=0.0;
   st.recoveryArmTrigger=0.0;
   string recoveryFields[]={"RAR","RAT","RAL","RAG"};
   if(committed && ShortStateFieldsValid(id,recoveryFields) && ShortStateRead(id,"RAR")>0.5)
   {
      st.recoveryArmedTime=(datetime)ShortStateRead(id,"RAT");
      st.recoveryArmLossPrice=ShortStateRead(id,"RAL");
      st.recoveryArmTrigger=ShortStateRead(id,"RAG");
      st.recoveryArmed=st.recoveryArmedTime>0 && st.recoveryArmLossPrice>0.0 && st.recoveryArmTrigger>0.0 &&
                       st.recoveryArmLossPrice+tick*0.5>=st.recoveryArmTrigger;
   }
   // 缺少旧计划时保留“已初始化但无计划”，不套用这次加载的新老师文本。
   st.teacherPlanInitialized=true;
   st.teacherPlanValid=false;
   st.teacherPlanSignature=0;
   st.teacherPlanMode=老师点位辅助_仅TP;
   st.teacherPrimaryTP=0.0;
   st.teacherSecondaryTP=0.0;
   string teacherFields[]={"TPI","TPV","TPSL","TPSH","TPMD","TPT1","TPT2"};
   if(committed && ShortStateFieldsValid(id,teacherFields))
   {
      double lo=ShortStateRead(id,"TPSL"),hi=ShortStateRead(id,"TPSH");
      if(lo<0 || lo>4294967295.0 || hi<0 || hi>4294967295.0 || lo!=MathFloor(lo) || hi!=MathFloor(hi)) return;
      st.teacherPlanInitialized=ShortStateRead(id,"TPI")>0.5;
      st.teacherPlanSignature=((ulong)(uint)hi<<32)|(ulong)(uint)lo;
      st.teacherPlanMode=(int)ShortStateRead(id,"TPMD");
      st.teacherPrimaryTP=ShortStateRead(id,"TPT1");
      st.teacherSecondaryTP=ShortStateRead(id,"TPT2");
      bool validMode=(st.teacherPlanMode==老师点位辅助_仅TP || st.teacherPlanMode==老师点位辅助_TP与突破保护SL);
      int sign=st.positionDirection==POSITION_TYPE_BUY ? 1 : -1;
      st.teacherPlanValid=ShortStateRead(id,"TPV")>0.5 && st.teacherPlanInitialized && validMode &&
                          st.lastKnownOpenPrice>0.0 && st.teacherPlanSignature>0 && st.teacherPrimaryTP>0.0 &&
                          sign*(st.teacherPrimaryTP-st.lastKnownOpenPrice)>tick*0.5 &&
                          (st.teacherSecondaryTP==0.0 || (st.teacherSecondaryTP>0.0 &&
                           sign*(st.teacherSecondaryTP-st.teacherPrimaryTP)>tick*0.5));
   }
}

void ShortStateSave(int stateIdx)
{
   PerformanceScope perfScope(PERF_SHORT_STATE_SAVE);
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   TicketState st = states[stateIdx];
   if(!st.shortStateManaged || st.positionIdentifier == 0) return;
   ulong id = st.positionIdentifier;
   // 单独撤销保护字段提交标记；失败时仍可恢复旧版已有的身份和pending字段。
   if(!ShortStateWrite(id,"PC",0.0)) { states[stateIdx].stateDirty=true; return; }
   bool saved=true;
   saved=ShortStateWrite(id, "TK", (double)st.ticket) && saved;
   saved=ShortStateWrite(id, "OT", (double)st.positionOpenTime) && saved;
   saved=ShortStateWrite(id, "DR", (double)st.positionDirection) && saved;
   saved=ShortStateWrite(id, "ATM", (double)st.adoptedTemplate) && saved;
   saved=ShortStateWrite(id, "TAP", st.teacherActivePlan ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "IV", st.initialVolume) && saved;
   saved=ShortStateWrite(id, "IR", st.shortInitialRisk) && saved;
   saved=ShortStateWrite(id, "ISL", st.shortInitialSL) && saved;
   saved=ShortStateWrite(id, "ASL", st.shortActualInitialSL) && saved;
   saved=ShortStateWrite(id, "RR", st.shortRiskReady ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "SC", st.shortInitialSLConfirmed ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "RU", st.shortRiskUnknown ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "MP", st.maxProfitPrice) && saved;
   saved=ShortStateWrite(id, "ML", st.maxLossPrice) && saved;
   saved=ShortStateWrite(id, "MPM", st.maxProfitMoney) && saved;
   saved=ShortStateWrite(id, "MLM", st.maxLossMoney) && saved;
   saved=ShortStateWrite(id, "LRN", st.lifecycleRealizedNetMoney) && saved;
   saved=ShortStateWrite(id, "MLP", st.maxLifecycleProfitMoney) && saved;
   saved=ShortStateWrite(id, "MLL", st.maxLifecycleLossMoney) && saved;
   saved=ShortStateWrite(id, "LPE", st.lifecyclePnlEnvelopeInitialized ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "PS", (double)st.partialTPStage) && saved;
   saved=ShortStateWrite(id, "PT", (double)st.lastPartialTPTime) && saved;
   saved=ShortStateWrite(id, "PP", st.lastPartialTPProfit) && saved;
   saved=ShortStateWrite(id, "PD", st.partialTPDone ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "PEN", st.partialRequestPending ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "PST", (double)st.pendingPartialStage) && saved;
   saved=ShortStateWrite(id, "PV", st.pendingPartialVolume) && saved;
   saved=ShortStateWrite(id, "PF", st.pendingPartialFilledVolume) && saved;
   saved=ShortStateWrite(id, "PSV", st.pendingPartialStartVolume) && saved;
   saved=ShortStateWrite(id, "PQT", (double)st.pendingPartialRequestTime) && saved;
   saved=ShortStateWrite(id, "F1", st.partialFilledVolumeStage1) && saved;
   saved=ShortStateWrite(id, "F2", st.partialFilledVolumeStage2) && saved;
   saved=ShortStateWrite(id, "F3", st.partialFilledVolumeStage3) && saved;
   saved=ShortStateWrite(id, "LD", (double)st.lastShortDeal) && saved;
   saved=ShortStateWrite(id, "RM", (double)st.runnerMode) && saved;
   saved=ShortStateWrite(id, "FR", st.fixedTPRemoved ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "FP", st.fastProtectionActivated ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "FT", (double)st.fastProtectionTime) && saved;
   saved=ShortStateWrite(id, "MR", (double)st.confirmedMarketRegime) && saved;
   saved=ShortStateWrite(id, "CR", (double)st.candidateMarketRegime) && saved;
   saved=ShortStateWrite(id, "RC", (double)st.candidateRegimeCount) && saved;
   saved=ShortStateWrite(id, "RT", (double)st.regimeChangedTime) && saved;
   saved=ShortStateWrite(id, "TA", (double)st.tradeArchetype) && saved;
   saved=ShortStateWrite(id, "LP", (double)st.lifecyclePhase) && saved;
   saved=ShortStateWrite(id, "PG", (double)st.protectionStage) && saved;
   saved=ShortStateWrite(id, "PA", (double)st.pendingAction) && saved;
   saved=ShortStateWrite(id, "PAT", (double)st.pendingActionTime) && saved;
   saved=ShortStateWrite(id, "PRQ", (double)st.pendingRequestId) && saved;
   saved=ShortStateWrite(id, "POR", (double)st.pendingOrder) && saved;
   saved=ShortStateWrite(id, "PDE", (double)st.pendingDeal) && saved;
   saved=ShortStateWrite(id, "PSL", st.pendingRequestedSL) && saved;
   saved=ShortStateWrite(id, "PTP", st.pendingRequestedTP) && saved;
   saved=ShortStateWrite(id, "PVO", st.pendingRequestedVolume) && saved;
   saved=ShortStateWrite(id, "PSV2", st.pendingStartVolume) && saved;
   saved=ShortStateWrite(id, "PSS", (double)st.pendingSLSource) && saved;
   saved=ShortStateWrite(id, "PTS", (double)st.pendingTPSource) && saved;
   saved=ShortStateWrite(id, "PEI", (double)st.pendingExitIntent) && saved;
   saved=ShortStateWrite(id, "PFP", st.pendingFastProtection ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "PFSL", st.pendingFastProtectionSL) && saved;
   saved=ShortStateWrite(id, "PFR", st.pendingFixedTPRemoval ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "CDT", (double)st.closeDetectedTime) && saved;
   saved=ShortStateWrite(id, "FRC", (double)st.finalizeRetryCount) && saved;
   saved=ShortStateWrite(id, "FIN", st.tradeFinalized ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "SMC", (double)st.slModifyCount) && saved;
   saved=ShortStateWrite(id, "TMC", (double)st.tpModifyCount) && saved;
   saved=ShortStateWrite(id, "PFC", (double)st.partialFillCount) && saved;
   saved=ShortStateWrite(id, "LSS", (double)st.lastConfirmedSLSource) && saved;
   saved=ShortStateWrite(id, "LTS", (double)st.lastConfirmedTPSource) && saved;
   saved=ShortStateWrite(id, "EXI", (double)st.exitIntent) && saved;
   saved=ShortStateWrite(id, "LMT", (double)st.lastManagedModifyTime) && saved;
   saved=ShortStateWrite(id, "LKV", st.lastKnownVolume) && saved;
   saved=ShortStateWrite(id, "LKP", st.lastKnownOpenPrice) && saved;
   saved=ShortStateWrite(id, "EVC", st.externalVolumeChangeDetected ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "EVT", (double)st.externalVolumeChangeTime) && saved;
   saved=ShortStateWrite(id, "PEF", st.pendingExitFilledVolume) && saved;
   saved=ShortStateWrite(id, "PRC", (double)st.pendingRetryCount) && saved;
   saved=ShortStateWrite(id, "LED", (double)st.lastLifecycleExitDeal) && saved;
   saved=ShortStateWrite(id, "RBT", (double)st.lastRegimeClosedBarTime) && saved;
   saved=ShortStateWrite(id, "NRV", st.nettingReversalDetected ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "LST", (double)st.lifecycleSegmentStartTime) && saved;
   saved=ShortStateWrite(id, "FTPS", st.floatingProfitSeconds) && saved;
   saved=ShortStateWrite(id, "FTLS", st.floatingLossSeconds) && saved;
   saved=ShortStateWrite(id, "FTFS", st.floatingFlatSeconds) && saved;
   saved=ShortStateWrite(id, "FTLL", st.longestFloatingLossSeconds) && saved;
   saved=ShortStateWrite(id, "FTFP", (double)st.firstFloatingProfitTime) && saved;
   saved=ShortStateWrite(id, "FTOS", (double)st.floatingTimingObservationStartTime) && saved;
   saved=ShortStateWrite(id, "FTHD", st.floatingTimingHasData ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "FTFN", st.floatingTimingFinalized ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "TRR", st.trendRiskReady ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "TRU", st.trendRiskUnknown ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "TIR", st.trendInitialRisk) && saved;
   saved=ShortStateWrite(id, "TIS", st.trendInitialSL) && saved;
   saved=ShortStateWrite(id, "THI", st.trendHighSinceOpen) && saved;
   saved=ShortStateWrite(id, "TLO", st.trendLowSinceOpen) && saved;
   saved=ShortStateWrite(id, "RAR", st.recoveryArmed ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "RAT", (double)st.recoveryArmedTime) && saved;
   saved=ShortStateWrite(id, "RAL", st.recoveryArmLossPrice) && saved;
   saved=ShortStateWrite(id, "RAG", st.recoveryArmTrigger) && saved;
   saved=ShortStateWrite(id, "TPI", st.teacherPlanInitialized ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "TPV", st.teacherPlanValid ? 1.0 : 0.0) && saved;
   saved=ShortStateWrite(id, "TPSL", (double)(uint)(st.teacherPlanSignature & 0xFFFFFFFF)) && saved;
   saved=ShortStateWrite(id, "TPSH", (double)(uint)(st.teacherPlanSignature >> 32)) && saved;
   saved=ShortStateWrite(id, "TPMD", (double)st.teacherPlanMode) && saved;
   saved=ShortStateWrite(id, "TPT1", st.teacherPrimaryTP) && saved;
   saved=ShortStateWrite(id, "TPT2", st.teacherSecondaryTP) && saved;
   if(!saved || !ShortStateWrite(id,"V",7.0) || !ShortStateWrite(id,"PC",1.0))
   {
      states[stateIdx].stateDirty=true;
      PrintRateLimited("short_state_write_failed",10,"[状态] 写入失败，保留dirty；不提交不完整快照");
      return;
   }
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
   if(GlobalVariableCheck(ShortStateKey(st.positionIdentifier, "TAP")))
      st.teacherActivePlan = ShortStateRead(st.positionIdentifier, "TAP") > 0.5;
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
   ShortStateLoadProtectionFields(st);
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
                      "PEF","PRC","LED","RBT","NRV","LST","TAP",
                      "FTPS","FTLS","FTFS","FTLL","FTFP","FTOS","FTHD","FTFN",
                      "PC","TRR","TRU","TIR","TIS","THI","TLO","RAR","RAT","RAL","RAG",
                      "TPI","TPV","TPSL","TPSH","TPMD","TPT1","TPT2"};
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
