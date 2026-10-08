#ifndef SMA_UI_CANVAS_PANEL_MQH
#define SMA_UI_CANVAS_PANEL_MQH

uint CanvasDirectionColor(bool isBuy)
{
   return isBuy?CanvasPanelTheme.directionBuy:CanvasPanelTheme.directionSell;
}

int CanvasScalePx(int logicalPixels)
{
   return MathMax((int)MathRound(logicalPixels*CanvasPanelMetrics.dpiScale),1);
}

int CanvasFontSize(double logicalSize)
{
   return -MathMax((int)MathRound(logicalSize*10.0*CanvasPanelMetrics.dpiScale),10);
}

string ResolveCanvasUIFont(void)
{
   string candidates[3]={"Microsoft YaHei UI","Microsoft YaHei","Segoe UI"};
   for(int i=0;i<3;i++)
      if(CanvasPanelRenderer.FontAvailable(candidates[i],CanvasPanelMetrics.fontBody))
         return candidates[i];
   if(CanvasPanelRenderer.FontAvailable(CanvasResolvedFont,CanvasPanelMetrics.fontBody))
      return CanvasResolvedFont;
   return "Segoe UI";
}

void CalculateCanvasMetrics(int logicalHeight)
{
   double dpi=(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0;
   CanvasPanelMetrics.dpiScale=MathMax(0.85,MathMin(dpi,1.75));
   int logicalWidth=CanvasPanelState.displayMode==面板迷你 ? MathMax(迷你面板宽度,390) :
                    (CanvasPanelState.displayMode==面板隐藏 ? 230 : MathMax(560,MathMin(面板宽度,640)));
   CanvasPanelMetrics.width=CanvasScalePx(logicalWidth);
   CanvasPanelMetrics.height=CanvasScalePx(logicalHeight);
   bool fullPanel=(CanvasPanelState.displayMode==面板完整);
   CanvasPanelMetrics.margin=CanvasScalePx(fullPanel?12:10);
   CanvasPanelMetrics.gap=CanvasScalePx(fullPanel?8:6);
   CanvasPanelMetrics.padding=CanvasScalePx(fullPanel?12:8);
   CanvasPanelMetrics.radius=CanvasScalePx(5);
   CanvasPanelMetrics.space2=CanvasScalePx(2);
   CanvasPanelMetrics.space4=CanvasScalePx(4);
   CanvasPanelMetrics.space6=CanvasScalePx(6);
   CanvasPanelMetrics.space8=CanvasScalePx(8);
   CanvasPanelMetrics.space10=CanvasScalePx(10);
   CanvasPanelMetrics.space12=CanvasScalePx(12);
   CanvasPanelMetrics.space16=CanvasScalePx(16);
   CanvasPanelMetrics.radiusButton=CanvasScalePx(4);
   CanvasPanelMetrics.radiusCard=CanvasScalePx(6);
   CanvasPanelMetrics.radiusContainer=CanvasScalePx(7);
   CanvasPanelMetrics.radiusBadge=CanvasScalePx(7);
   CanvasPanelMetrics.headerHeight=CanvasScalePx(fullPanel?40:34);
   CanvasPanelMetrics.tabHeight=CanvasScalePx(fullPanel?34:26);
   CanvasPanelMetrics.cardHeight=CanvasScalePx(fullPanel?84:66);
   // CCanvas 字号统一经由 CanvasFontSize() 以 1/10 point 负值传入；各角色不再共用小字号。
   CanvasPanelMetrics.fontHeader=CanvasFontSize(13.0);
   CanvasPanelMetrics.fontTab=CanvasFontSize(11.0);
   CanvasPanelMetrics.fontLabel=CanvasFontSize(10.0);
   CanvasPanelMetrics.fontBody=CanvasFontSize(11.0);
   CanvasPanelMetrics.fontValue=CanvasFontSize(16.0);
   CanvasPanelMetrics.fontCaption=CanvasFontSize(9.5);
   CanvasPanelMetrics.fontTitle=CanvasPanelMetrics.fontHeader;
   CanvasPanelMetrics.fontSmall=CanvasPanelMetrics.fontCaption;

   CanvasPanelMetrics.fontName=CanvasResolvedFont;

   CanvasPanelTheme.root=ColorToARGB(C'12,20,31',255);
   CanvasPanelTheme.background=CanvasPanelTheme.root;
   CanvasPanelTheme.header=ColorToARGB(C'16,27,42',255);
   CanvasPanelTheme.toolbar=ColorToARGB(C'20,33,50',255);
   CanvasPanelTheme.container=ColorToARGB(C'22,36,54',255);
   CanvasPanelTheme.card=ColorToARGB(C'25,41,60',255);
   CanvasPanelTheme.cardRaised=ColorToARGB(C'28,46,66',255);
   CanvasPanelTheme.row=ColorToARGB(C'25,40,58',255);
   CanvasPanelTheme.rowAlt=ColorToARGB(C'29,45,64',255);
   CanvasPanelTheme.selected=ColorToARGB(C'27,72,78',255);
   CanvasPanelTheme.surface=CanvasPanelTheme.card;
   CanvasPanelTheme.surfaceAlt=CanvasPanelTheme.container;
   CanvasPanelTheme.hover=ColorToARGB(C'33,52,73',255);
   CanvasPanelTheme.borderWeak=ColorToARGB(C'41,58,78',255);
   CanvasPanelTheme.borderNormal=ColorToARGB(C'52,73,96',255);
   CanvasPanelTheme.borderStrong=ColorToARGB(C'62,90,116',255);
   CanvasPanelTheme.border=CanvasPanelTheme.borderNormal;
   CanvasPanelTheme.topHighlight=ColorToARGB(C'66,88,112',255);
   CanvasPanelTheme.bottomShadow=ColorToARGB(C'7,13,21',255);
   CanvasPanelTheme.text=ColorToARGB(C'225,232,241',255);
   CanvasPanelTheme.muted=ColorToARGB(C'150,165,184',255);
   CanvasPanelTheme.dim=ColorToARGB(C'94,108,128',255);
   CanvasPanelTheme.accent=ColorToARGB(C'45,190,177',255);
   CanvasPanelTheme.profit=ColorToARGB(C'255,122,89',255);
   CanvasPanelTheme.loss=ColorToARGB(C'77,163,255',255);
   CanvasPanelTheme.pnlFlat=CanvasPanelTheme.muted;
   CanvasPanelTheme.directionBuy=ColorToARGB(C'45,190,177',255);
   CanvasPanelTheme.directionSell=ColorToARGB(C'167,139,250',255);
   CanvasPanelTheme.warning=ColorToARGB(C'232,169,70',255);
   CanvasPanelTheme.infoFill=ColorToARGB(C'19,59,67',255);
   CanvasPanelTheme.infoBorder=ColorToARGB(C'38,120,119',255);
   CanvasPanelTheme.infoText=ColorToARGB(C'105,221,210',255);
   CanvasPanelTheme.successFill=ColorToARGB(C'19,55,59',255);
   CanvasPanelTheme.successBorder=ColorToARGB(C'45,119,117',255);
   CanvasPanelTheme.successText=ColorToARGB(C'105,221,210',255);
   CanvasPanelTheme.warningFill=ColorToARGB(C'66,50,24',255);
   CanvasPanelTheme.warningBorder=ColorToARGB(C'145,107,42',255);
   CanvasPanelTheme.warningText=ColorToARGB(C'232,169,70',255);
   CanvasPanelTheme.warningBadgeText=ColorToARGB(C'245,192,91',255);
   CanvasPanelTheme.dangerFill=ColorToARGB(C'60,32,52',255);
   CanvasPanelTheme.dangerBorder=ColorToARGB(C'136,64,100',255);
   CanvasPanelTheme.dangerText=ColorToARGB(C'240,98,146',255);
   CanvasPanelTheme.disabledFill=ColorToARGB(C'18,29,44',255);
   CanvasPanelTheme.disabledText=ColorToARGB(C'73,87,105',255);
}

void DeleteLegacyPanelObjectsForCanvas(void)
{
   ulong perfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
   for(int i=ObjectsTotal(0,-1,-1)-1; i>=0; i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(name=="SMA_CANVAS") continue;
      if(name=="SMA_BTN_NEWS_FREEZE" || name=="SMA_BTN_NEWS_RELEASE" || name=="SMA_BTN_NEWS_CANCEL" || name=="SMA_BTN_NEWS_FLAT") continue;
      if(StringFind(name,"SMA_PANEL_")==0 || StringFind(name,"SMA_BTN_")==0 || StringFind(name,"SMA_UI_")==0)
         ObjectDelete(0,name);
   }
   CanvasUIPerfStage("Delete legacy objects",perfStart,20000);
}

void EnsureLegacyPanelObjectsClearedForCanvas(void)
{
   if(CanvasLegacyObjectsCleared) return;
   DeleteLegacyPanelObjectsForCanvas();
   CanvasLegacyObjectsCleared=true;
}

void HideCanvasNewsButtons(void)
{
   if(!CanvasNewsButtonsVisible) return;
   string names[4]={"SMA_BTN_NEWS_FREEZE","SMA_BTN_NEWS_RELEASE","SMA_BTN_NEWS_CANCEL","SMA_BTN_NEWS_FLAT"};
   for(int i=0;i<4;i++) ObjectDelete(0,names[i]);
   CanvasNewsButtonsVisible=false;
   CanvasNewsButtonsSignature="";
}

uint CanvasSeverityColor(UISeverity severity)
{
   if(severity==UI_SEVERITY_SUCCESS) return CanvasPanelTheme.successText;
   if(severity==UI_SEVERITY_WARNING) return CanvasPanelTheme.warningText;
   if(severity==UI_SEVERITY_DANGER) return CanvasPanelTheme.dangerText;
   if(severity==UI_SEVERITY_INFO) return CanvasPanelTheme.infoText;
   return CanvasThemeMuted();
}

uint CanvasSurfaceFill(PanelSurfaceLevel level)
{
   if(level==SURFACE_HEADER) return CanvasPanelTheme.header;
   if(level==SURFACE_TOOLBAR) return CanvasPanelTheme.toolbar;
   if(level==SURFACE_CONTAINER) return CanvasPanelTheme.container;
   if(level==SURFACE_CARD) return CanvasPanelTheme.card;
   if(level==SURFACE_CARD_RAISED) return CanvasPanelTheme.cardRaised;
   if(level==SURFACE_ROW) return CanvasPanelTheme.row;
   if(level==SURFACE_ROW_ALT) return CanvasPanelTheme.rowAlt;
   if(level==SURFACE_SELECTED) return CanvasPanelTheme.selected;
   if(level==SURFACE_WARNING) return CanvasPanelTheme.warningFill;
   if(level==SURFACE_DANGER) return CanvasPanelTheme.dangerFill;
   return CanvasPanelTheme.root;
}

void DrawSoftDivider(int x1, int y1, int x2, int y2)
{
   CanvasPanelRenderer.Line(x1,y1,x2,y2,CanvasPanelTheme.borderWeak);
}

void DrawSurface(const UIRect &rect, PanelSurfaceLevel level, int radius,
                 bool drawBorder=true, bool drawTopHighlight=false, bool drawBottomShadow=false)
{
   uint fill=CanvasSurfaceFill(level);
   uint border=drawBorder ? (level==SURFACE_SELECTED?CanvasPanelTheme.borderStrong:CanvasPanelTheme.borderNormal) : fill;
   CanvasPanelRenderer.FillRoundRect(rect,radius,fill,border);
   int inset=MathMax(radius,CanvasPanelMetrics.space4);
   if(drawTopHighlight && rect.w>inset*2+2)
      CanvasPanelRenderer.Line(rect.x+inset,rect.y+1,rect.x+rect.w-inset-1,rect.y+1,CanvasPanelTheme.topHighlight);
   if(drawBottomShadow && rect.w>inset*2+2)
      CanvasPanelRenderer.Line(rect.x+inset,rect.y+rect.h-2,rect.x+rect.w-inset-1,rect.y+rect.h-2,CanvasPanelTheme.bottomShadow);
}

void DrawColorEdge(const UIRect &rect, uint colorValue, int thickness, bool leftEdge=true)
{
   if(rect.w<=0 || rect.h<=0) return;
   int size=MathMax(thickness,1);
   if(leftEdge)
      CanvasPanelRenderer.FillRect(MakeUIRect(rect.x,rect.y+CanvasPanelMetrics.space6,size,MathMax(rect.h-CanvasPanelMetrics.space12,1)),colorValue);
   else
      CanvasPanelRenderer.FillRect(MakeUIRect(rect.x+CanvasPanelMetrics.space6,rect.y,MathMax(rect.w-CanvasPanelMetrics.space12,1),size),colorValue);
}

void DrawAccentEdge(const UIRect &rect, UISeverity severity, int thickness, bool leftEdge=true)
{
   DrawColorEdge(rect,CanvasSeverityColor(severity),thickness,leftEdge);
}

void DrawRaisedCard(const UIRect &rect, PanelSurfaceLevel level, int radius, UISeverity severity=UI_SEVERITY_MUTED)
{
   DrawSurface(rect,level,radius,true,true,true);
   if(severity!=UI_SEVERITY_MUTED)
      DrawAccentEdge(rect,severity,CanvasPanelMetrics.space2,true);
}

void DrawInsetPanel(const UIRect &rect, int radius)
{
   DrawSurface(rect,SURFACE_CONTAINER,radius,true,false,true);
}

void DrawBadge(const UIRect &rect, string text, UISeverity severity, BadgeStyle style=BADGE_STATUS)
{
   uint fill=CanvasPanelTheme.container;
   uint border=CanvasPanelTheme.borderWeak;
   uint textColor=CanvasPanelTheme.muted;
   if(severity==UI_SEVERITY_SUCCESS)
   {
      fill=CanvasPanelTheme.successFill; border=CanvasPanelTheme.successBorder; textColor=CanvasPanelTheme.successText;
   }
   else if(severity==UI_SEVERITY_WARNING)
   {
      fill=CanvasPanelTheme.warningFill; border=CanvasPanelTheme.warningBorder; textColor=CanvasPanelTheme.warningBadgeText;
   }
   else if(severity==UI_SEVERITY_DANGER)
   {
      fill=CanvasPanelTheme.dangerFill; border=CanvasPanelTheme.dangerBorder; textColor=CanvasPanelTheme.dangerText;
   }
   else if(severity==UI_SEVERITY_INFO)
   {
      fill=CanvasPanelTheme.infoFill; border=CanvasPanelTheme.infoBorder; textColor=CanvasPanelTheme.infoText;
   }
   int radius=style==BADGE_STATUS?MathMax(CanvasPanelMetrics.radiusBadge,rect.h/2):CanvasPanelMetrics.radiusBadge;
   CanvasPanelRenderer.FillRoundRect(rect,radius,fill,border);
   CanvasPanelRenderer.TextCenter(rect,text,textColor,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
}

void DrawCanvasButton(const UIRect &rect, string text, CanvasControlVisualState state,
                      UISeverity severity=UI_SEVERITY_MUTED, bool accentLine=false)
{
   PanelSurfaceLevel level=SURFACE_TOOLBAR;
   uint border=CanvasPanelTheme.borderWeak;
   uint textColor=CanvasPanelTheme.muted;
   if(state==CONTROL_HOVER)
   {
      CanvasPanelRenderer.FillRoundRect(rect,CanvasPanelMetrics.radiusButton,CanvasPanelTheme.hover,CanvasPanelTheme.borderNormal);
      textColor=CanvasPanelTheme.text;
   }
   else if(state==CONTROL_PRESSED)
   {
      CanvasPanelRenderer.FillRoundRect(rect,CanvasPanelMetrics.radiusButton,CanvasPanelTheme.root,CanvasPanelTheme.borderStrong);
      textColor=CanvasPanelTheme.text;
   }
   else if(state==CONTROL_SELECTED)
   {
      level=SURFACE_SELECTED;
      DrawSurface(rect,level,CanvasPanelMetrics.radiusButton,true,true,false);
      textColor=CanvasPanelTheme.text;
   }
   else if(state==CONTROL_DISABLED)
   {
      CanvasPanelRenderer.FillRoundRect(rect,CanvasPanelMetrics.radiusButton,CanvasPanelTheme.disabledFill,CanvasPanelTheme.borderWeak);
      textColor=CanvasPanelTheme.disabledText;
   }
   else
   {
      CanvasPanelRenderer.FillRoundRect(rect,CanvasPanelMetrics.radiusButton,CanvasPanelTheme.toolbar,border);
   }
   UIRect textRect=rect;
   if(state==CONTROL_PRESSED) textRect.y+=1;
   if(severity==UI_SEVERITY_DANGER && state!=CONTROL_DISABLED) textColor=CanvasPanelTheme.dangerText;
   CanvasPanelRenderer.TextCenter(textRect,text,textColor,CanvasResolvedFont,CanvasPanelMetrics.fontTab);
   if((state==CONTROL_SELECTED || accentLine) && rect.w>CanvasPanelMetrics.space12)
      CanvasPanelRenderer.FillRect(MakeUIRect(rect.x+CanvasPanelMetrics.space6,rect.y+rect.h-CanvasPanelMetrics.space2,
                                             rect.w-CanvasPanelMetrics.space12,CanvasPanelMetrics.space2),CanvasPanelTheme.accent);
}

CanvasControlVisualState HoldingToolbarControlState(PanelAction action, bool selected=false)
{
   if(CanvasPanelState.pressedAction==action) return CONTROL_PRESSED;
   if(CanvasPanelState.hoverAction==action && !selected) return CONTROL_HOVER;
   return selected?CONTROL_SELECTED:CONTROL_NORMAL;
}

void DrawHoldingToolbarButton(const UIRect &rect, string text, CanvasControlVisualState state, bool selected=false)
{
   uint fill=CanvasPanelTheme.toolbar;
   uint border=CanvasPanelTheme.borderNormal;
   uint textColor=CanvasPanelTheme.muted;
   if(state==CONTROL_HOVER)
   {
      fill=CanvasPanelTheme.hover;
      textColor=CanvasPanelTheme.text;
   }
   else if(state==CONTROL_PRESSED)
   {
      fill=CanvasPanelTheme.root;
      border=CanvasPanelTheme.borderStrong;
      textColor=CanvasPanelTheme.text;
   }
   else if(state==CONTROL_SELECTED)
   {
      fill=CanvasPanelTheme.selected;
      border=CanvasPanelTheme.borderStrong;
      textColor=CanvasPanelTheme.text;
   }
   CanvasPanelRenderer.FillRoundRect(rect,CanvasPanelMetrics.radiusButton,fill,border);
   if(StringLen(text)>0)
      CanvasPanelRenderer.TextCenter(rect,text,textColor,CanvasResolvedFont,CanvasPanelMetrics.fontTab);
   if(selected && rect.w>CanvasPanelMetrics.space10*2)
      CanvasPanelRenderer.FillRect(MakeUIRect(rect.x+CanvasPanelMetrics.space10,
                                             rect.y+rect.h-CanvasPanelMetrics.space2,
                                             rect.w-CanvasPanelMetrics.space10*2,
                                             CanvasPanelMetrics.space2),CanvasPanelTheme.accent);
}

string CanvasTemplateName(int templateId)
{
   if(templateId==(int)配置_黄金超短快保) return "短线";
   if(templateId==(int)配置_黄金稳健托管) return "长线";
   if(templateId==(int)配置_黄金消息对冲) return "消息";
   if(templateId==(int)配置_黄金支压止盈 || templateId==(int)配置_自定义) return "手动";
   return "未记录";
}

持仓显示筛选类型 TemplateToPositionFilter(管理配置模板 templateValue)
{
   if(templateValue==配置_黄金超短快保) return 持仓筛选_短线;
   if(templateValue==配置_黄金稳健托管) return 持仓筛选_长线;
   if(templateValue==配置_黄金消息对冲) return 持仓筛选_消息;
   if(templateValue==配置_黄金支压止盈) return 持仓筛选_手动;
   return 持仓筛选_全部;
}

string PositionFilterLabel(持仓显示筛选类型 filter)
{
   if(filter==持仓筛选_短线) return "短线";
   if(filter==持仓筛选_长线) return "长线";
   if(filter==持仓筛选_消息) return "消息";
   if(filter==持仓筛选_手动) return "手动";
   return "全部";
}

string EntryTemplateLabel(管理配置模板 templateValue)
{
   return CanvasTemplateName((int)templateValue);
}

bool PositionMatchesDisplayFilter(const PositionPanelViewModel &position, 持仓显示筛选类型 filter)
{
   if(filter==持仓筛选_全部) return true;
   if(position.templateId<(int)配置_自定义 || position.templateId>(int)配置_黄金消息对冲) return false;
   return TemplateToPositionFilter((管理配置模板)position.templateId)==filter;
}

void BuildFilteredPositionIndexes(const PositionPanelViewModel &positions[],
                                  持仓显示筛选类型 filter,
                                  int &indexes[])
{
   ArrayResize(indexes,0);
   for(int i=0;i<ArraySize(positions);i++)
   {
      if(!PositionMatchesDisplayFilter(positions[i],filter)) continue;
      int n=ArraySize(indexes);
      ArrayResize(indexes,n+1);
      indexes[n]=i;
   }
}

void BuildFilteredPositionSummary(const PositionPanelViewModel &positions[],
                                  const int &indexes[],
                                  FilteredPositionSummary &summary)
{
   summary.managedCount=0;
   summary.buyCount=0;
   summary.sellCount=0;
   summary.buyLots=0.0;
   summary.sellLots=0.0;
   summary.totalLots=0.0;
   summary.floatingProfit=0.0;
   summary.peakProfit=0.0;
   summary.slCount=0;
   summary.tpCount=0;
   summary.protectedCount=0;
   summary.riskSummary="空仓";

   for(int i=0;i<ArraySize(indexes);i++)
   {
      int positionIndex=indexes[i];
      if(positionIndex<0 || positionIndex>=ArraySize(positions)) continue;
      PositionPanelViewModel position=positions[positionIndex];
      summary.managedCount++;
      summary.totalLots+=position.volume;
      summary.floatingProfit+=position.profit;
      summary.peakProfit+=position.peakProfit;
      if(position.type==POSITION_TYPE_BUY)
      {
         summary.buyCount++;
         summary.buyLots+=position.volume;
      }
      else
      {
         summary.sellCount++;
         summary.sellLots+=position.volume;
      }
      if(position.hasSL) summary.slCount++;
      if(position.hasTP) summary.tpCount++;
      if(position.protectedPosition) summary.protectedCount++;
   }

   if(summary.managedCount<=0)
      summary.riskSummary="空仓";
   else if(summary.slCount<summary.managedCount)
      summary.riskSummary=StringFormat("缺 SL %d",summary.managedCount-summary.slCount);
   else if(summary.protectedCount==summary.managedCount)
      summary.riskSummary="已保护";
   else
      summary.riskSummary="待保护";
}

void RebuildHoldingDisplayProjection(HoldingPanelViewModel &holding)
{
   BuildFilteredPositionIndexes(holding.positions,CanvasPanelState.positionFilter,holding.filteredPositionIndexes);
   BuildFilteredPositionSummary(holding.positions,holding.filteredPositionIndexes,holding.filteredSummary);
}

string EntryTemplateStatusText(void)
{
   return "新单："+EntryTemplateLabel(当前参数配置模板);
}

void DrawCurrentEntryTemplateMarker(const UIRect &buttonRect, bool active)
{
   if(!active || buttonRect.w<=0 || buttonRect.h<=0) return;
   int markerH=MathMax(CanvasScalePx(2),2);
   int markerW=MathMax(buttonRect.w*45/100,CanvasScalePx(18));
   markerW=MathMin(markerW,MathMax(buttonRect.w-CanvasPanelMetrics.space12*2,1));
   int markerX=buttonRect.x+MathMax((buttonRect.w-markerW)/2,0);
   int bottomGap=MathMax(CanvasPanelMetrics.space4,CanvasScalePx(3));
   int markerY=buttonRect.y+buttonRect.h-bottomGap-markerH;
   CanvasPanelRenderer.FillRect(MakeUIRect(markerX,markerY,markerW,markerH),CanvasThemeWarning());
}

bool CanvasDisplayTextMissing(string text)
{
   return (StringLen(text)<=0 || text=="(null)" || text=="NULL" || text=="null");
}

string FormatHoldMinutes(int minutes, bool compact=true)
{
   if(compact)
   {
      if(minutes<=0) return "<1m";
      if(minutes<60) return IntegerToString(minutes)+"m";
      if(minutes<1440) return StringFormat("%dh %dm",minutes/60,minutes%60);
      return StringFormat("%dd %dh",minutes/1440,(minutes%1440)/60);
   }
   if(minutes<=0) return "<1分钟";
   if(minutes<60) return IntegerToString(minutes)+"分钟";
   if(minutes<1440) return StringFormat("%d小时%d分钟",minutes/60,minutes%60);
   return StringFormat("%d天%d小时",minutes/1440,(minutes%1440)/60);
}

UISeverity CanvasStatusSeverity(string text)
{
   if(StringFind(text,"失败")>=0 || StringFind(text,"紧急")>=0 || StringFind(text,"无止损")>=0 || StringFind(text,"没有止损")>=0)
      return UI_SEVERITY_DANGER;
   if(StringFind(text,"警告")>=0 || StringFind(text,"待确认")>=0 || StringFind(text,"不足")>=0 || StringFind(text,"不可用")>=0 || StringFind(text,"未记录")>=0 || StringFind(text,"未设置")>=0)
      return UI_SEVERITY_WARNING;
   if(StringFind(text,"成功")>=0 || StringFind(text,"完成")>=0 || StringFind(text,"已保护")>=0 || StringFind(text,"正常运行")>=0)
      return UI_SEVERITY_SUCCESS;
   if(StringFind(text,"已更新")>=0 || StringFind(text,"切换")>=0 || StringFind(text,"ticket=")>=0)
      return UI_SEVERITY_INFO;
   return UI_SEVERITY_MUTED;
}

datetime CanvasCurrentServerTime()
{
   datetime serverNow=TimeTradeServer();
   if(serverNow<=0) serverNow=TimeCurrent();
   return serverNow;
}

datetime CanvasCurrentBeijingTime()
{
   datetime utcNow=TimeGMT();
   if(utcNow<=0) return 0;
   return utcNow+8*60*60;
}

string FormatCanvasBeijingClock(datetime beijingNow)
{
   if(beijingNow<=0) return "";
   MqlDateTime value;
   if(!TimeToStruct(beijingNow,value)) return "";
   return StringFormat("%02d:%02d:%02d",value.hour,value.min,value.sec);
}

bool UpdateCanvasHeaderClockCache(bool markDirty=true)
{
   datetime beijingNow=CanvasCurrentBeijingTime();
   if(beijingNow<=0 || beijingNow==CanvasLastDisplayedBeijingSecond) return false;

   string clockText=FormatCanvasBeijingClock(beijingNow);
   if(clockText=="") return false;

   CanvasLastDisplayedBeijingSecond=beijingNow;
   CanvasCachedBeijingClock=clockText;
   if(markDirty) MarkCanvasPanelDirty(PANEL_DIRTY_HEADER_CLOCK);
   return true;
}

string CanvasHeaderClockText()
{
   if(CanvasCachedBeijingClock=="") UpdateCanvasHeaderClockCache(false);
   return "北京 "+(CanvasCachedBeijingClock==""?"--:--:--":CanvasCachedBeijingClock);
}

string CanvasHeaderTitleText()
{
   return _Symbol+" · "+CanvasHeaderClockText();
}

int CanvasCurrentSessionIndex()
{
   return LifecycleBeijingSession(CanvasCurrentServerTime());
}

enum CanvasMarketSessionState
{
   CANVAS_MARKET_CLOSED = 0,
   CANVAS_MARKET_ASIA,
   CANVAS_MARKET_LONDON,
   CANVAS_MARKET_NEWYORK,
   CANVAS_MARKET_LOW_ACTIVITY
};

int CanvasSessionSeconds(datetime sessionTime)
{
   MqlDateTime value;
   TimeToStruct(sessionTime,value);
   return value.hour*3600+value.min*60+value.sec;
}

bool CanvasSymbolTradingSessionOpen(datetime serverNow)
{
   ENUM_SYMBOL_TRADE_MODE tradeMode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(tradeMode==SYMBOL_TRADE_MODE_DISABLED) return false;

   MqlDateTime nowParts;
   TimeToStruct(serverNow,nowParts);
   int nowSeconds=nowParts.hour*3600+nowParts.min*60+nowParts.sec;
   ENUM_DAY_OF_WEEK currentDay=(ENUM_DAY_OF_WEEK)nowParts.day_of_week;
   ENUM_DAY_OF_WEEK previousDay=(ENUM_DAY_OF_WEEK)((nowParts.day_of_week+6)%7);
   bool sessionInformationAvailable=false;

   for(uint sessionIndex=0;sessionIndex<64;sessionIndex++)
   {
      datetime sessionFrom=0,sessionTo=0;
      if(!SymbolInfoSessionTrade(_Symbol,currentDay,sessionIndex,sessionFrom,sessionTo)) break;
      sessionInformationAvailable=true;
      int fromSeconds=CanvasSessionSeconds(sessionFrom);
      int toSeconds=CanvasSessionSeconds(sessionTo);
      if(fromSeconds==toSeconds ||
         (fromSeconds<toSeconds && nowSeconds>=fromSeconds && nowSeconds<toSeconds) ||
         (fromSeconds>toSeconds && nowSeconds>=fromSeconds))
         return true;
   }

   for(uint sessionIndex=0;sessionIndex<64;sessionIndex++)
   {
      datetime sessionFrom=0,sessionTo=0;
      if(!SymbolInfoSessionTrade(_Symbol,previousDay,sessionIndex,sessionFrom,sessionTo)) break;
      sessionInformationAvailable=true;
      int fromSeconds=CanvasSessionSeconds(sessionFrom);
      int toSeconds=CanvasSessionSeconds(sessionTo);
      if(fromSeconds>toSeconds && nowSeconds<toSeconds) return true;
   }

   if(sessionInformationAvailable) return false;
   if(nowParts.day_of_week==0 || nowParts.day_of_week==6) return false;
   return true;
}

CanvasMarketSessionState CanvasCurrentMarketSession()
{
   datetime serverNow=CanvasCurrentServerTime();
   if(!CanvasSymbolTradingSessionOpen(serverNow)) return CANVAS_MARKET_CLOSED;
   int session=LifecycleBeijingSession(serverNow);
   if(session==0) return CANVAS_MARKET_ASIA;
   if(session==1) return CANVAS_MARKET_LONDON;
   if(session==2) return CANVAS_MARKET_NEWYORK;
   return CANVAS_MARKET_LOW_ACTIVITY;
}

string CanvasCurrentSessionText()
{
   CanvasMarketSessionState session=CanvasCurrentMarketSession();
   if(session==CANVAS_MARKET_CLOSED) return "休市";
   if(session==CANVAS_MARKET_ASIA) return "亚洲盘";
   if(session==CANVAS_MARKET_LONDON) return "伦敦盘";
   if(session==CANVAS_MARKET_NEWYORK) return "纽约盘";
   return "低活跃时段";
}

string CanvasHeaderStatusText(UISeverity severity)
{
   if(severity==UI_SEVERITY_DANGER) return "● 异常";
   if(severity==UI_SEVERITY_WARNING) return "● 注意";
   return CanvasCurrentSessionText();
}

void RenderInlineMetrics(const UIRect &rect, string &labels[], string &values[])
{
   int count=MathMin(ArraySize(labels),ArraySize(values));
   if(count<=0 || rect.w<=0 || rect.h<=0) return;
   int cellW=rect.w/count;
   for(int i=0;i<count;i++)
   {
      int left=rect.x+i*cellW;
      int right=(i==count-1)?rect.x+rect.w:left+cellW;
      UIRect cell=MakeUIRect(left,rect.y,right-left,rect.h);
      int inset=CanvasPanelMetrics.space10;
      int labelW=CanvasPanelRenderer.TextWidth(labels[i],CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      labelW=MathMin(labelW,MathMax(cell.w*40/100,1));
      CanvasPanelRenderer.TextLeft(MakeUIRect(cell.x+inset,cell.y,labelW,cell.h),labels[i],CanvasThemeDim(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      CanvasPanelRenderer.TextRight(MakeUIRect(cell.x+inset+labelW+CanvasPanelMetrics.space4,cell.y,MathMax(cell.w-labelW-inset*2-CanvasPanelMetrics.space4,1),cell.h),values[i],CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      if(i<count-1)
         CanvasPanelRenderer.Divider(MakeUIRect(cell.x+cell.w-1,cell.y+CanvasPanelMetrics.space6,1,MathMax(cell.h-CanvasPanelMetrics.space12,1)),CanvasThemeBorder(),true);
   }
}

string MiniCanvasTitle(const PanelViewModel &model)
{
   if(model.mini.managedCount<=0) return model.mini.symbol+" · 空仓";
   return StringFormat("%s · 托管%d单",model.mini.symbol,model.mini.managedCount);
}

int MiniPriceDistanceDigits(void)
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) return MathMax(2,MathMin(_Digits,5));
   int digits=0;
   double scaled=tickSize;
   while(digits<5 && MathAbs(scaled-MathRound(scaled))>0.00000001)
   {
      scaled*=10.0;
      digits++;
   }
   return MathMax(2,digits);
}

string FormatMiniPriceDistance(double distance, bool valid, int digits)
{
   if(!valid) return "--";
   return DoubleToString(MathMax(distance,0.0),MathMax(0,MathMin(digits,5)));
}

string FormatMiniSignedProfit(double value, int digits=2)
{
   if(MathAbs(value)<=0.005) return DoubleToString(0.0,digits);
   return StringFormat("%+.*f",digits,value);
}

int MiniCanvasLogicalHeight(const PanelViewModel &model)
{
   int count=ArraySize(model.holding.positions);
   int listHeight=count<=0?44:(4+24+count*31+6);
   return 34+6+54+6+listHeight+6+26+7;
}

void BuildMiniPanelViewModel(PanelViewModel &model)
{
   // 迷你面板直接复用完整持仓 ViewModel 的一次扫描结果；渲染阶段不再查询持仓或行情。
   BuildHoldingPanelViewModel(model);
   model.mini.symbol=_Symbol;
   model.mini.managedCount=model.holding.managedCount;
   model.mini.buyCount=model.holding.buyCount;
   model.mini.sellCount=model.holding.sellCount;
   model.mini.floatingProfit=model.holding.floatingProfit;
   model.mini.slCount=model.holding.slCount;
   model.mini.nearestResistance=0.0;
   model.mini.nearestSupport=0.0;
   model.mini.profitSeverity=model.mini.floatingProfit>0.0 ? UI_SEVERITY_SUCCESS :
                              (model.mini.floatingProfit<0.0 ? UI_SEVERITY_DANGER : UI_SEVERITY_MUTED);
   model.mini.riskSeverity=model.mini.managedCount<=0 ? UI_SEVERITY_MUTED :
                           (model.mini.slCount==model.mini.managedCount ? UI_SEVERITY_SUCCESS :
                           (model.mini.slCount<=0 ? UI_SEVERITY_DANGER : UI_SEVERITY_WARNING));
   model.statusText=lastStatus;
}

void CalculateMiniPanelLayout(void)
{
   int w=CanvasPanelMetrics.width;
   int h=CanvasPanelMetrics.height;
   int m=CanvasPanelMetrics.margin;
   int header=CanvasPanelMetrics.headerHeight;
   int count=ArraySize(CanvasPanelModel.holding.positions);
   CanvasPanelLayout.panel=MakeUIRect(0,0,w,h);
   CanvasPanelLayout.header=MakeUIRect(0,0,w,header);

   int buttonH=CanvasScalePx(24);
   int buttonY=MathMax((header-buttonH)/2,0);
   int buttonGap=CanvasScalePx(5);
   int buttonPad=CanvasPanelMetrics.space10*2;
   int expandW=MathMax(CanvasScalePx(48),CanvasPanelRenderer.TextWidth("展开",CanvasResolvedFont,CanvasPanelMetrics.fontTab)+buttonPad);
   int hideW=MathMax(CanvasScalePx(48),CanvasPanelRenderer.TextWidth("隐藏",CanvasResolvedFont,CanvasPanelMetrics.fontTab)+buttonPad);
   CanvasPanelLayout.mainTabs[4]=MakeUIRect(w-m-hideW,buttonY,hideW,buttonH);
   CanvasPanelLayout.mainTabs[3]=MakeUIRect(CanvasPanelLayout.mainTabs[4].x-buttonGap-expandW,buttonY,expandW,buttonH);
   string title=MiniCanvasTitle(CanvasPanelModel);
   int titleX=m+CanvasPanelMetrics.space2;
   int titleAvailable=MathMax(CanvasPanelLayout.mainTabs[3].x-titleX-CanvasPanelMetrics.space8,1);
   int titleNeeded=CanvasPanelRenderer.TextWidth(title,CanvasResolvedFont,CanvasPanelMetrics.fontHeader)+CanvasPanelMetrics.space4;
   CanvasPanelLayout.headerTitle=MakeUIRect(titleX,0,MathMin(titleNeeded,titleAvailable),header);

   int y=header+CanvasPanelMetrics.space6;
   int contentW=w-m*2;
   int summaryH=CanvasScalePx(54);
   CanvasPanelLayout.miniSummaryStrip=MakeUIRect(m,y,contentW,summaryH);
   int summaryCellW=contentW/3;
   for(int i=0;i<3;i++)
   {
      int cellX=m+i*summaryCellW;
      int cellRight=(i==2)?m+contentW:cellX+summaryCellW;
      CanvasPanelLayout.miniSummaryCells[i]=MakeUIRect(cellX,y,cellRight-cellX,summaryH);
      CanvasPanelLayout.miniSummaryLabels[i]=MakeUIRect(cellX+CanvasPanelMetrics.space8,y+CanvasPanelMetrics.space6,
                                                        MathMax(cellRight-cellX-CanvasPanelMetrics.space16,1),CanvasScalePx(18));
      CanvasPanelLayout.miniSummaryValues[i]=MakeUIRect(cellX+CanvasPanelMetrics.space8,y+summaryH-CanvasPanelMetrics.space6-CanvasScalePx(20),
                                                        MathMax(cellRight-cellX-CanvasPanelMetrics.space16,1),CanvasScalePx(20));
   }

   y+=summaryH+CanvasPanelMetrics.space6;
   int listH=count<=0?CanvasScalePx(44):CanvasScalePx(4+24+count*31+6);
   CanvasPanelLayout.miniPositionList=MakeUIRect(m,y,contentW,listH);
   if(count>0)
   {
      int contentX=CanvasPanelLayout.miniPositionList.x+CanvasScalePx(13);
      int listRight=CanvasPanelLayout.miniPositionList.x+CanvasPanelLayout.miniPositionList.w-CanvasPanelMetrics.space8;
      int columnsW=MathMax(listRight-contentX,1);
      int widths[4];
      widths[0]=columnsW*27/100;
      widths[1]=columnsW*21/100;
      widths[2]=columnsW*25/100;
      widths[3]=columnsW-widths[0]-widths[1]-widths[2];
      CanvasPanelLayout.miniPositionListHeader=MakeUIRect(contentX,y+CanvasPanelMetrics.space4,columnsW,CanvasScalePx(24));
      int columnX=contentX;
      for(int i=0;i<4;i++)
      {
         CanvasPanelLayout.miniPositionColumns[i]=MakeUIRect(columnX,CanvasPanelLayout.miniPositionListHeader.y,widths[i],CanvasPanelLayout.miniPositionListHeader.h);
         columnX+=widths[i];
      }
   }
   else
   {
      CanvasPanelLayout.miniPositionListHeader=MakeUIRect(0,0,0,0);
      for(int i=0;i<4;i++) CanvasPanelLayout.miniPositionColumns[i]=MakeUIRect(0,0,0,0);
   }

   y+=listH+CanvasPanelMetrics.space6;
   CanvasPanelLayout.miniSupportFooter=MakeUIRect(m,y,contentW,CanvasScalePx(26));
   int footerHalf=contentW/2;
   CanvasPanelLayout.miniR1Rect=MakeUIRect(m,y,footerHalf,CanvasPanelLayout.miniSupportFooter.h);
   CanvasPanelLayout.miniS1Rect=MakeUIRect(m+footerHalf,y,contentW-footerHalf,CanvasPanelLayout.miniSupportFooter.h);
   CanvasPanelLayout.footer=CanvasPanelLayout.miniSupportFooter;
   当前面板宽度=w;
   当前面板高度=h;
}

void AddCanvasHit(const UIRect &rect, PanelAction action, bool enabled=true)
{
   int n=ArraySize(CanvasPanelHitRegions);
   ArrayResize(CanvasPanelHitRegions,n+1);
   CanvasPanelHitRegions[n].rect=rect;
   CanvasPanelHitRegions[n].action=action;
   CanvasPanelHitRegions[n].enabled=enabled;
}

void BuildMiniHitRegions(void)
{
   ArrayResize(CanvasPanelHitRegions,0);
   AddCanvasHit(CanvasPanelLayout.mainTabs[3],PANEL_ACTION_MODE_FULL);
   AddCanvasHit(CanvasPanelLayout.mainTabs[4],PANEL_ACTION_MODE_HIDE);
}

int MiniValueFontForRect(const UIRect &rect, string text, int baseFont)
{
   int available=MathMax(rect.w-CanvasPanelMetrics.space8,1);
   if(CanvasPanelRenderer.TextWidth(text,CanvasResolvedFont,baseFont)<=available) return baseFont;
   return CanvasFontSize(10.0);
}

void RenderMiniCanvasPanel(const PanelViewModel &model)
{
   CanvasPanelRenderer.Begin(CanvasThemeBackground());
   DrawSurface(CanvasPanelLayout.panel,SURFACE_ROOT,CanvasPanelMetrics.radiusContainer,true,false,true);
   CanvasPanelRenderer.FillRect(CanvasPanelLayout.header,CanvasPanelTheme.header);
   DrawSoftDivider(CanvasPanelLayout.header.x,CanvasPanelLayout.header.y+CanvasPanelLayout.header.h-1,
                   CanvasPanelLayout.header.x+CanvasPanelLayout.header.w-1,CanvasPanelLayout.header.y+CanvasPanelLayout.header.h-1);
   CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.headerTitle,MiniCanvasTitle(model),CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontHeader);
   DrawCanvasButton(CanvasPanelLayout.mainTabs[3],"展开",CONTROL_NORMAL);
   DrawCanvasButton(CanvasPanelLayout.mainTabs[4],"隐藏",CONTROL_NORMAL);

   DrawInsetPanel(CanvasPanelLayout.miniSummaryStrip,CanvasPanelMetrics.radiusContainer);
   string labels[3]={"总浮盈","止损覆盖","总手数"};
   string values[3];
   values[0]=FormatMiniSignedProfit(model.holding.floatingProfit,2);
   values[1]=StringFormat("%d / %d",model.holding.slCount,model.holding.managedCount);
   values[2]=DoubleToString(model.holding.totalLots,2);
   uint valueColors[3];
   valueColors[0]=CanvasPnLColor(model.holding.floatingProfit);
   valueColors[1]=model.holding.managedCount<=0?CanvasThemeMuted():
                  (model.holding.slCount==model.holding.managedCount?CanvasThemeSuccess():
                  (model.holding.slCount<=0?CanvasThemeDanger():CanvasThemeWarning()));
   valueColors[2]=model.holding.totalLots>0.0?CanvasThemeAccent():CanvasThemeMuted();
   for(int i=0;i<3;i++)
   {
      CanvasPanelRenderer.TextCenter(CanvasPanelLayout.miniSummaryLabels[i],labels[i],CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      CanvasPanelRenderer.TextCenter(CanvasPanelLayout.miniSummaryValues[i],values[i],valueColors[i],CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      if(i<2)
         CanvasPanelRenderer.Divider(MakeUIRect(CanvasPanelLayout.miniSummaryCells[i].x+CanvasPanelLayout.miniSummaryCells[i].w-1,
                                               CanvasPanelLayout.miniSummaryStrip.y+CanvasPanelMetrics.space8,1,
                                               MathMax(CanvasPanelLayout.miniSummaryStrip.h-CanvasPanelMetrics.space16,1)),CanvasPanelTheme.borderWeak,true);
   }

   int count=ArraySize(model.holding.positions);
   DrawSurface(CanvasPanelLayout.miniPositionList,SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,false,true);
   if(count<=0)
   {
      CanvasPanelRenderer.TextLeft(CanvasPanelLayout.miniPositionList,"当前没有受管持仓",CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontBody,CanvasPanelMetrics.space12);
   }
   else
   {
      string headers[4]={"方向/手数","浮盈","距SL","距TP"};
      CanvasPanelRenderer.TextLeft(CanvasPanelLayout.miniPositionColumns[0],headers[0],CanvasThemeDim(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      for(int i=1;i<4;i++)
         CanvasPanelRenderer.TextRight(CanvasPanelLayout.miniPositionColumns[i],headers[i],CanvasThemeDim(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption,i<3?CanvasPanelMetrics.space8:0);
      DrawSoftDivider(CanvasPanelLayout.miniPositionList.x+CanvasPanelMetrics.space8,
                      CanvasPanelLayout.miniPositionListHeader.y+CanvasPanelLayout.miniPositionListHeader.h-1,
                      CanvasPanelLayout.miniPositionList.x+CanvasPanelLayout.miniPositionList.w-CanvasPanelMetrics.space8,
                      CanvasPanelLayout.miniPositionListHeader.y+CanvasPanelLayout.miniPositionListHeader.h-1);
      for(int col=0;col<3;col++)
         CanvasPanelRenderer.Divider(MakeUIRect(CanvasPanelLayout.miniPositionColumns[col].x+CanvasPanelLayout.miniPositionColumns[col].w-1,
                                               CanvasPanelLayout.miniPositionListHeader.y,1,
                                               MathMax(CanvasPanelLayout.miniPositionList.h-CanvasPanelMetrics.space10,1)),CanvasPanelTheme.borderWeak,true);

      int rowsTop=CanvasPanelLayout.miniPositionListHeader.y+CanvasPanelLayout.miniPositionListHeader.h;
      int rowsBottom=CanvasPanelLayout.miniPositionList.y+CanvasPanelLayout.miniPositionList.h-CanvasPanelMetrics.space6;
      int rowsHeight=MathMax(rowsBottom-rowsTop,1);
      for(int i=0;i<count;i++)
      {
         int rowY=rowsTop+rowsHeight*i/count;
         int rowBottom=rowsTop+rowsHeight*(i+1)/count;
         int rowH=MathMax(rowBottom-rowY,1);
         PositionPanelViewModel position=model.holding.positions[i];
         uint directionColor=CanvasDirectionColor(position.type==POSITION_TYPE_BUY);
         CanvasPanelRenderer.FillRect(MakeUIRect(CanvasPanelLayout.miniPositionList.x+CanvasPanelMetrics.space2,
                                                rowY+CanvasPanelMetrics.space6,CanvasScalePx(3),MathMax(rowH-CanvasPanelMetrics.space12,1)),directionColor);

         UIRect rowColumns[4];
         for(int col=0;col<4;col++)
            rowColumns[col]=MakeUIRect(CanvasPanelLayout.miniPositionColumns[col].x,rowY,CanvasPanelLayout.miniPositionColumns[col].w,rowH);
         string directionText=StringFormat("%s %.2f",position.type==POSITION_TYPE_BUY?"多":"空",position.volume);
         int directionFont=MiniValueFontForRect(rowColumns[0],directionText,CanvasPanelMetrics.fontBody);
         CanvasPanelRenderer.TextLeft(rowColumns[0],directionText,directionColor,CanvasResolvedFont,directionFont);

         string profitText=FormatMiniSignedProfit(position.profit,2);
         int profitFont=MiniValueFontForRect(rowColumns[1],profitText,CanvasPanelMetrics.fontBody);
         if(profitFont!=CanvasPanelMetrics.fontBody) profitText=FormatMiniSignedProfit(position.profit,1);
         uint profitColor=CanvasPnLColor(position.profit);
         CanvasPanelRenderer.TextRight(rowColumns[1],profitText,profitColor,CanvasResolvedFont,profitFont,CanvasPanelMetrics.space8);

         string slText=position.distanceToSLText;
         int slFont=MiniValueFontForRect(rowColumns[2],slText,CanvasPanelMetrics.fontBody);
         if(slFont!=CanvasPanelMetrics.fontBody && position.distanceToSLValid) slText=DoubleToString(position.distanceToSL,1);
         CanvasPanelRenderer.TextRight(rowColumns[2],slText,position.distanceToSLValid?CanvasThemeMuted():CanvasThemeDanger(),CanvasResolvedFont,slFont,CanvasPanelMetrics.space8);

         string tpText=position.distanceToTPText;
         int tpFont=MiniValueFontForRect(rowColumns[3],tpText,CanvasPanelMetrics.fontBody);
         if(tpFont!=CanvasPanelMetrics.fontBody && position.distanceToTPValid) tpText=DoubleToString(position.distanceToTP,1);
         CanvasPanelRenderer.TextRight(rowColumns[3],tpText,position.distanceToTPValid?CanvasThemeMuted():CanvasThemeDim(),CanvasResolvedFont,tpFont);

         if(i<count-1)
            DrawSoftDivider(CanvasPanelLayout.miniPositionList.x+CanvasPanelMetrics.space8,rowBottom-1,
                            CanvasPanelLayout.miniPositionList.x+CanvasPanelLayout.miniPositionList.w-CanvasPanelMetrics.space8,rowBottom-1);
      }
   }

   DrawInsetPanel(CanvasPanelLayout.miniSupportFooter,CanvasPanelMetrics.radiusButton);
   CanvasPanelRenderer.TextLeft(CanvasPanelLayout.miniR1Rect,model.holding.resistanceText,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption,CanvasPanelMetrics.space10);
   CanvasPanelRenderer.TextRight(CanvasPanelLayout.miniS1Rect,model.holding.supportText,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption,CanvasPanelMetrics.space10);
   CanvasPanelRenderer.Divider(MakeUIRect(CanvasPanelLayout.miniSupportFooter.x+CanvasPanelLayout.miniSupportFooter.w/2,
                                         CanvasPanelLayout.miniSupportFooter.y+CanvasPanelMetrics.space6,1,
                                         MathMax(CanvasPanelLayout.miniSupportFooter.h-CanvasPanelMetrics.space12,1)),CanvasPanelTheme.borderWeak,true);
   CanvasPanelRenderer.End();
}

void CalculateHiddenCanvasPanelLayout(void)
{
   int w=CanvasPanelMetrics.width;
   int h=CanvasPanelMetrics.height;
   CanvasPanelLayout.panel=MakeUIRect(0,0,w,h);
   CanvasPanelLayout.mainTabs[3]=MakeUIRect(w-CanvasScalePx(66),CanvasScalePx(8),CanvasScalePx(54),CanvasScalePx(26));
   当前面板宽度=w;
   当前面板高度=h;
}

void BuildHiddenCanvasHitRegions(void)
{
   ArrayResize(CanvasPanelHitRegions,0);
   AddCanvasHit(CanvasPanelLayout.mainTabs[3],PANEL_ACTION_MODE_FULL);
}

void RenderHiddenCanvasPanel(void)
{
   int w=CanvasPanelMetrics.width;
   int h=CanvasPanelMetrics.height;
   CanvasPanelRenderer.Begin(CanvasThemeBackground());
   DrawSurface(CanvasPanelLayout.panel,SURFACE_HEADER,CanvasPanelMetrics.radiusContainer,true,true,true);
   CanvasPanelRenderer.TextEllipsized(MakeUIRect(CanvasScalePx(12),0,w-CanvasScalePx(88),h),CanvasHeaderClockText()+" · 已隐藏",CanvasThemeAccent(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
   DrawCanvasButton(CanvasPanelLayout.mainTabs[3],"展开",CONTROL_SELECTED);
   CanvasPanelRenderer.End();
}

void ShowCanvasMiniOrHiddenPanel(void)
{
   SyncCanvasStateFromLegacy();
   MarkCanvasPanelDirty(PANEL_DIRTY_DATA|PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER);
   RefreshCanvasPanelByDirtyFlags(false);
}

int ResolveTrendCurvePointIndexAtX(const UIRect &plotRect, int localX, int tradeCount)
{
   if(tradeCount<=0 || plotRect.w<=0) return -1;
   int relativeX=MathMax(0,MathMin(localX-plotRect.x,plotRect.w-1));
   int visualIndex=(int)MathRound((double)relativeX*tradeCount/MathMax(plotRect.w-1,1));
   return MathMax(0,MathMin(visualIndex-1,tradeCount-1));
}

int ResolveTrendBarIndexAtX(const UIRect &plotRect, int localX, int tradeCount)
{
   if(tradeCount<=0 || plotRect.w<=0) return -1;
   int relativeX=MathMax(0,MathMin(localX-plotRect.x,plotRect.w-1));
   int visualIndex=(int)MathRound((double)relativeX*tradeCount/MathMax(plotRect.w-1,1));
   return MathMax(0,MathMin(visualIndex-1,tradeCount-1));
}

PanelAction CanvasHitActionAt(int chartX, int chartY)
{
   int localX=chartX-CanvasPanelState.panelX;
   int localY=chartY-CanvasPanelState.panelY;
   for(int i=ArraySize(CanvasPanelHitRegions)-1;i>=0;i--)
      if(CanvasPanelHitRegions[i].enabled && UIContains(CanvasPanelHitRegions[i].rect,localX,localY))
      {
         PanelAction action=CanvasPanelHitRegions[i].action;
         if(action==PANEL_ACTION_TREND_SELECT)
         {
            int count=ArraySize(CanvasPanelModel.stats.trend.points);
            int pointIndex=UIContains(CanvasPanelLayout.trendCurvePlotInner,localX,localY)?
                           ResolveTrendCurvePointIndexAtX(CanvasPanelLayout.trendCurvePlotInner,localX,count):
                           ResolveTrendBarIndexAtX(CanvasPanelLayout.trendBarsPlotInner,localX,count);
            CanvasPanelState.pendingTrendPointIndex=(pointIndex>=0 && pointIndex<count)?pointIndex:-1;
         }
         return action;
      }
   return PANEL_ACTION_NONE;
}

bool CanvasPointInPanel(int chartX, int chartY)
{
   return chartX>=CanvasPanelState.panelX && chartX<CanvasPanelState.panelX+CanvasPanelMetrics.width &&
          chartY>=CanvasPanelState.panelY && chartY<CanvasPanelState.panelY+CanvasPanelMetrics.height;
}

void ClampCanvasPanelPosition(void)
{
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int visibleX=CanvasScalePx(80);
   int visibleY=CanvasScalePx(40);
   CanvasPanelState.panelX=MathMax(0,MathMin(CanvasPanelState.panelX,MathMax(cw-visibleX,0)));
   CanvasPanelState.panelY=MathMax(0,MathMin(CanvasPanelState.panelY,MathMax(ch-visibleY,0)));
}

void MoveCanvasNativeButtons(void)
{
   if(!当前模板使用消息对冲()) return;
   string names[4]={"SMA_BTN_NEWS_FREEZE","SMA_BTN_NEWS_RELEASE","SMA_BTN_NEWS_CANCEL","SMA_BTN_NEWS_FLAT"};
   for(int i=0;i<4;i++)
   {
      if(ObjectFind(0,names[i])<0) continue;
      ObjectSetInteger(0,names[i],OBJPROP_XDISTANCE,CanvasPanelState.panelX+CanvasPanelLayout.newsButtons[i].x);
      ObjectSetInteger(0,names[i],OBJPROP_YDISTANCE,CanvasPanelState.panelY+CanvasPanelLayout.newsButtons[i].y);
   }
}

void DispatchCanvasPanelAction(PanelAction action)
{
   ulong perfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
   int dirty=PANEL_DIRTY_NONE;
   if(action==PANEL_ACTION_MODE_FULL)
   {
      if(CanvasPanelState.displayMode==面板完整) return;
      CanvasPanelState.displayMode=面板完整;
      dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_MODE_HIDE)
   {
      if(CanvasPanelState.displayMode==面板隐藏) return;
      CanvasPanelState.displayMode=面板隐藏;
      dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_MODE_MINI)
   {
      if(CanvasPanelState.displayMode==面板迷你) return;
      CanvasPanelState.displayMode=面板迷你;
      dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_PAGE_HOLDING)
   {
      if(CanvasPanelState.page==页面持仓) return;
      CanvasPanelState.page=页面持仓;
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_PAGE_STATS)
   {
      if(CanvasPanelState.page==页面今日) return;
      CanvasPanelState.statsFilter=统计筛选_全部;
      CanvasPanelState.page=页面今日;
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_DENSITY_TOGGLE)
   {
      CanvasPanelState.density=CanvasPanelState.density==面板信息_简单?面板信息_专业:面板信息_简单;
      当前面板信息模式=CanvasPanelState.density;
      保存面板信息模式();
      dirty=PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_POSITION_FILTER_ALL)
   {
      if(CanvasPanelState.positionFilter==持仓筛选_全部 && CanvasPanelState.positionPage==0) return;
      CanvasPanelState.positionFilter=持仓筛选_全部;
      CanvasPanelState.positionPage=0;
      if(CanvasHoldingModelValid)
      {
         RebuildHoldingDisplayProjection(CanvasPanelModel.holding);
         CanvasPanelModel.holding.statusText="显示全部持仓；新单配置保持为"+EntryTemplateLabel(当前参数配置模板);
         CanvasPanelModel.holding.statusSeverity=UI_SEVERITY_INFO;
      }
      lastStatus="显示全部持仓；新单配置保持为"+EntryTemplateLabel(当前参数配置模板);
      dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_TEMPLATE_CUSTOM || action==PANEL_ACTION_TEMPLATE_FAST || action==PANEL_ACTION_TEMPLATE_TREND ||
           action==PANEL_ACTION_TEMPLATE_NORMAL || action==PANEL_ACTION_TEMPLATE_NEWS)
   {
      管理配置模板 target=配置_自定义;
      if(action==PANEL_ACTION_TEMPLATE_FAST) target=配置_黄金超短快保;
      else if(action==PANEL_ACTION_TEMPLATE_TREND) target=配置_黄金稳健托管;
      else if(action==PANEL_ACTION_TEMPLATE_NORMAL) target=配置_黄金支压止盈;
      else if(action==PANEL_ACTION_TEMPLATE_NEWS) target=配置_黄金消息对冲;
      持仓显示筛选类型 targetFilter=TemplateToPositionFilter(target);
      bool templateChanged=(当前参数配置模板!=target);
      bool filterChanged=(CanvasPanelState.positionFilter!=targetFilter || CanvasPanelState.positionPage!=0);
      if(!templateChanged && !filterChanged) return;
      if(templateChanged) ApplyPanelConfigTemplate(target);
      CanvasPanelState.positionFilter=targetFilter;
      CanvasPanelState.positionPage=0;
      if(CanvasHoldingModelValid)
      {
         RebuildHoldingDisplayProjection(CanvasPanelModel.holding);
         CanvasPanelModel.holding.statusText="显示"+PositionFilterLabel(targetFilter)+"持仓；新单配置："+EntryTemplateLabel(当前参数配置模板);
         CanvasPanelModel.holding.statusSeverity=UI_SEVERITY_INFO;
      }
      lastStatus="显示"+PositionFilterLabel(targetFilter)+"持仓；新单配置："+EntryTemplateLabel(当前参数配置模板);
      dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_MARKER_TOGGLE)
   {
      if(!启用手机标记挂单) lastStatus="提示挂单受参数开关关闭，未执行任何订单操作";
      else
      {
         手机标记挂单面板开关=!手机标记挂单面板开关;
         保存手机标记挂单面板开关();
         ManageMobileMarkerOrders(true);
         lastStatus=手机标记挂单面板开关?"提示挂单开启：正在同步":"提示挂单关闭：已请求撤销";
      }
      CanvasMiniModelValid=false;
      CanvasHoldingModelValid=false;
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_POSITION_PREV)
   {
      CanvasPanelState.positionPage=MathMax(CanvasPanelState.positionPage-1,0);
      dirty=PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_POSITION_NEXT)
   {
      CanvasPanelState.positionPage++;
      dirty=PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_NEWS_FREEZE) { NewsFreezeBoxByUser(); dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER; }
   else if(action==PANEL_ACTION_NEWS_RELEASE)
   {
      if(newsState.stage==消息阶段_箱体冻结 && newsState.buyTicket==0 && newsState.sellTicket==0)
         NewsDeployStopPair();
      else NewsEnableRelease();
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_NEWS_CANCEL)
   {
      if(newsState.stopToken>0) NewsCancelStopDeployment();
      else if(newsState.stage!=消息阶段_待命) NewsRequestGroupExit("用户取消本次消息");
      else
      {
         NewsCloseEligiblePositions("用户取消本次消息");
         newsState.waitStartTime=TimeCurrent()-MathMax(消息对冲配对等待秒,1);
      }
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_NEWS_FLAT)
   {
      if(newsState.stage!=消息阶段_待命) NewsRequestGroupExit("用户消息紧急全平");
      else
      {
         NewsCloseEligiblePositions("用户消息紧急全平");
         newsState.waitStartTime=TimeCurrent()-MathMax(消息对冲配对等待秒,1);
      }
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_STATS_DAY || action==PANEL_ACTION_STATS_WEEK || action==PANEL_ACTION_STATS_MONTH)
   {
      统计周期模式 target=统计_日;
      if(action==PANEL_ACTION_STATS_WEEK) target=统计_周;
      else if(action==PANEL_ACTION_STATS_MONTH) target=统计_月;
      if(CanvasPanelState.statsPeriod==target) return;
      CanvasPanelState.statsPeriod=target;
      CanvasPanelState.reviewIndex=0;
      InvalidateStatsCache();
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_PERIOD_PREV)
   {
      if(CanvasPanelState.statsPeriod==统计_日) CanvasPanelState.dayOffset--;
      else if(CanvasPanelState.statsPeriod==统计_周) CanvasPanelState.weekOffset--;
      else CanvasPanelState.monthOffset--;
      CanvasPanelState.reviewIndex=0;
      InvalidateStatsCache();
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_PERIOD_CURRENT)
   {
      if(CanvasPanelState.statsPeriod==统计_日) { if(CanvasPanelState.dayOffset==0) return; CanvasPanelState.dayOffset=0; }
      else if(CanvasPanelState.statsPeriod==统计_周) { if(CanvasPanelState.weekOffset==0) return; CanvasPanelState.weekOffset=0; }
      else { if(CanvasPanelState.monthOffset==0) return; CanvasPanelState.monthOffset=0; }
      CanvasPanelState.reviewIndex=0;
      InvalidateStatsCache();
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_PERIOD_NEXT)
   {
      if(CanvasPanelState.statsPeriod==统计_日) CanvasPanelState.dayOffset++;
      else if(CanvasPanelState.statsPeriod==统计_周) CanvasPanelState.weekOffset++;
      else CanvasPanelState.monthOffset++;
      CanvasPanelState.reviewIndex=0;
      InvalidateStatsCache();
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_FILTER_ALL || action==PANEL_ACTION_FILTER_SHORT || action==PANEL_ACTION_FILTER_TREND ||
           action==PANEL_ACTION_FILTER_NORMAL || action==PANEL_ACTION_FILTER_NEWS)
   {
      统计策略筛选 target=统计筛选_全部;
      if(action==PANEL_ACTION_FILTER_SHORT) target=统计筛选_短线;
      else if(action==PANEL_ACTION_FILTER_TREND) target=统计筛选_趋势;
      else if(action==PANEL_ACTION_FILTER_NORMAL) target=统计筛选_普通;
      else if(action==PANEL_ACTION_FILTER_NEWS) target=统计筛选_消息;
      if(CanvasPanelState.statsFilter==target) return;
      CanvasPanelState.statsFilter=target;
      CanvasPanelState.reviewIndex=0;
      InvalidateStatsCache(true);
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_FILTER_NEXT)
   {
      if(CanvasPanelState.statsFilter==统计筛选_全部) CanvasPanelState.statsFilter=统计筛选_短线;
      else if(CanvasPanelState.statsFilter==统计筛选_短线) CanvasPanelState.statsFilter=统计筛选_趋势;
      else if(CanvasPanelState.statsFilter==统计筛选_趋势) CanvasPanelState.statsFilter=统计筛选_消息;
      else if(CanvasPanelState.statsFilter==统计筛选_消息) CanvasPanelState.statsFilter=统计筛选_普通;
      else CanvasPanelState.statsFilter=统计筛选_全部;
      CanvasPanelState.reviewIndex=0;
      InvalidateStatsCache(true);
      dirty=PANEL_DIRTY_DATA|PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_DETAIL_OVERVIEW || action==PANEL_ACTION_DETAIL_STRATEGY || action==PANEL_ACTION_DETAIL_MANAGE ||
           action==PANEL_ACTION_DETAIL_EXEC || action==PANEL_ACTION_DETAIL_REVIEW || action==PANEL_ACTION_DETAIL_TREND)
   {
      统计详情页面 target=统计详情_总览;
      if(action==PANEL_ACTION_DETAIL_STRATEGY) target=统计详情_策略;
      else if(action==PANEL_ACTION_DETAIL_MANAGE) target=统计详情_管理;
      else if(action==PANEL_ACTION_DETAIL_EXEC) target=统计详情_执行;
      else if(action==PANEL_ACTION_DETAIL_REVIEW) target=统计详情_复盘;
      else if(action==PANEL_ACTION_DETAIL_TREND) target=统计详情_走势;
      if(CanvasPanelState.statsDetail==target) return;
      CanvasPanelState.statsDetail=target;
      CanvasPanelState.reviewIndex=0;
      dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
      if(target==统计详情_复盘 && (!CanvasStatsModelValid || !CanvasReviewCacheMatchesStats(CanvasPanelModel.stats.stats)))
         dirty|=PANEL_DIRTY_DATA;
      if(target==统计详情_走势 && (!CanvasStatsModelValid || !CanvasTrendCacheMatchesStats(CanvasPanelModel.stats.stats) ||
                                    !CanvasReviewCacheMatchesStats(CanvasPanelModel.stats.stats)))
         dirty|=PANEL_DIRTY_DATA;
   }
   else if(action==PANEL_ACTION_OVERVIEW_BEST_REVIEW || action==PANEL_ACTION_OVERVIEW_WORST_REVIEW)
   {
      bool best=(action==PANEL_ACTION_OVERVIEW_BEST_REVIEW);
      ulong positionId=best?CanvasPanelModel.stats.stats.bestTradePositionId:
                            CanvasPanelModel.stats.stats.worstTradePositionId;
      if(positionId==0)
      {
         CanvasPanelState.statsActionMessage=best?"当前没有可查看的最佳交易":"当前没有可查看的最差交易";
         dirty=PANEL_DIRTY_RENDER;
      }
      else
      {
         EnsureCanvasReviewItemsForStats(CanvasPanelModel.stats.stats,CanvasPanelModel.stats.reviews);
         int reviewIndex=FindCanvasReviewIndexByPositionId(CanvasPanelModel.stats.reviews,positionId);
         if(reviewIndex<0)
         {
            CanvasPanelState.statsActionMessage=(best?"最佳交易":"最差交易")+"缺少完整复盘档案，无法查看复盘";
            dirty=PANEL_DIRTY_RENDER;
         }
         else
         {
            CanvasPanelState.reviewIndex=reviewIndex;
            CanvasPanelState.statsDetail=统计详情_复盘;
            CanvasPanelState.statsActionMessage="";
            dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
         }
      }
   }
   else if(action==PANEL_ACTION_TREND_SELECT)
   {
      int pointIndex=CanvasPanelState.pendingTrendPointIndex;
      CanvasPanelState.pendingTrendPointIndex=-1;
      int pointCount=ArraySize(CanvasPanelModel.stats.trend.points);
      if(pointIndex<0 || pointIndex>=pointCount)
      {
         CanvasPanelState.selectedTrendPointIndex=-1;
         CanvasPanelState.trendSelectionValid=false;
         CanvasPanelState.trendSelectionMessage="当前没有可选交易";
      }
      else
      {
         CanvasPanelState.selectedTrendPointIndex=pointIndex;
         CanvasPanelState.trendSelectionValid=true;
         CanvasPanelState.trendSelectionMessage="";
         CanvasPanelState.trendSelectionGeneration=CanvasStatsTradeGeneration;
      }
      dirty=PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_TREND_OPEN_REVIEW)
   {
      int pointIndex=CanvasPanelState.selectedTrendPointIndex;
      int pointCount=ArraySize(CanvasPanelModel.stats.trend.points);
      if(!CanvasPanelState.trendSelectionValid || pointIndex<0 || pointIndex>=pointCount)
      {
         CanvasPanelState.trendSelectionMessage="当前没有可选交易";
         dirty=PANEL_DIRTY_RENDER;
      }
      else if(!CanvasSelectedTrendReviewAvailable())
      {
         CanvasPanelState.trendSelectionMessage="该笔交易缺少完整复盘档案，无法查看复盘";
         dirty=PANEL_DIRTY_RENDER;
      }
      else
      {
         TrendTradePoint point=CanvasPanelModel.stats.trend.points[pointIndex];
         int reviewIndex=point.reviewIndex;
         CanvasPanelState.reviewIndex=reviewIndex;
         CanvasPanelState.statsDetail=统计详情_复盘;
         CanvasPanelState.trendSelectionMessage="";
         dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
      }
   }
   else if(action==PANEL_ACTION_REVIEW_PREV)
   {
      int reviewCount=ArraySize(CanvasPanelModel.stats.reviews);
      if(reviewCount<=0) CanvasPanelState.reviewIndex=0;
      else CanvasPanelState.reviewIndex=MathMin(CanvasPanelState.reviewIndex+1,reviewCount-1);
      dirty=PANEL_DIRTY_RENDER;
   }
   else if(action==PANEL_ACTION_REVIEW_NEXT)
   {
      int reviewCount=ArraySize(CanvasPanelModel.stats.reviews);
      if(reviewCount<=0) CanvasPanelState.reviewIndex=0;
      else CanvasPanelState.reviewIndex=MathMax(MathMin(CanvasPanelState.reviewIndex,reviewCount-1)-1,0);
      dirty=PANEL_DIRTY_RENDER;
   }
   else return;

   if(action!=PANEL_ACTION_OVERVIEW_BEST_REVIEW && action!=PANEL_ACTION_OVERVIEW_WORST_REVIEW)
      CanvasPanelState.statsActionMessage="";
   SyncLegacyStateFromCanvas();
   CanvasPanelState.dragging=false;
   ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
   if(!CanvasCurrentViewModelValid()) dirty|=PANEL_DIRTY_DATA;
   MarkCanvasPanelDirty(dirty);
   上次面板状态文本="";
   RefreshCanvasPanelByDirtyFlags(false);
   // 动作内可能同步提示挂单并等待服务器返回；以完成时刻刷新去重基准，
   // 防止同一次物理点击的第二个 CLICK/OBJECT_CLICK 在慢操作后再次执行。
   CanvasPanelState.lastClickTick=GetTickCount64();
   CanvasPanelState.lastClickAction=action;
   CanvasUIPerfStage("Dispatch action",perfStart,20000);
}

bool IsDuplicateCanvasPhysicalClick(int chartX, int chartY, PanelAction action)
{
   ulong now=GetTickCount64();
   if(CanvasPanelState.suppressClickUntilTick>0 && now<=CanvasPanelState.suppressClickUntilTick)
      return true;
   int tolerance=CanvasScalePx(4);
   bool samePoint=(MathAbs(chartX-CanvasPanelState.lastClickX)<=tolerance &&
                   MathAbs(chartY-CanvasPanelState.lastClickY)<=tolerance);
   ulong duplicateWindow=(action==PANEL_ACTION_MARKER_TOGGLE)?500:110;
   bool duplicate=(CanvasPanelState.lastClickTick>0 && now>=CanvasPanelState.lastClickTick &&
                   now-CanvasPanelState.lastClickTick<=duplicateWindow && samePoint &&
                   CanvasPanelState.lastClickAction==action);
   if(duplicate) return true;
   CanvasPanelState.lastClickTick=now;
   CanvasPanelState.lastClickX=chartX;
   CanvasPanelState.lastClickY=chartY;
   CanvasPanelState.lastClickAction=action;
   return false;
}

bool IsStatsToolbarAction(PanelAction action)
{
   return (action==PANEL_ACTION_STATS_DAY || action==PANEL_ACTION_STATS_WEEK || action==PANEL_ACTION_STATS_MONTH ||
           action==PANEL_ACTION_PERIOD_PREV || action==PANEL_ACTION_PERIOD_CURRENT || action==PANEL_ACTION_PERIOD_NEXT ||
           action==PANEL_ACTION_FILTER_NEXT || action==PANEL_ACTION_OVERVIEW_BEST_REVIEW ||
           action==PANEL_ACTION_OVERVIEW_WORST_REVIEW);
}

bool IsHoldingToolbarAction(PanelAction action)
{
   return (action==PANEL_ACTION_POSITION_FILTER_ALL || action==PANEL_ACTION_TEMPLATE_FAST ||
           action==PANEL_ACTION_TEMPLATE_TREND || action==PANEL_ACTION_TEMPLATE_NEWS ||
           action==PANEL_ACTION_TEMPLATE_NORMAL || action==PANEL_ACTION_MARKER_TOGGLE);
}

bool CanvasHoldingToolbarVisible(void)
{
   return (CanvasPanelState.displayMode==面板完整 && CanvasPanelState.page==页面持仓 &&
           CanvasPanelLayoutValid && CanvasPanelLayout.templateBar.w>0 && CanvasPanelLayout.templateBar.h>0);
}

bool CanvasStatsToolbarVisible(void)
{
   return (CanvasPanelState.displayMode==面板完整 && CanvasPanelState.page==页面今日 &&
           CanvasPanelLayoutValid && CanvasPanelLayout.statsToolbar.w>0 && CanvasPanelLayout.statsToolbar.h>0);
}

void UpdateCanvasToolbarPointerState(int chartX, int chartY, bool leftDown)
{
   PanelAction hit=PANEL_ACTION_NONE;
   if(CanvasHoldingToolbarVisible())
   {
      int localX=chartX-CanvasPanelState.panelX;
      int localY=chartY-CanvasPanelState.panelY;
      if(UIContains(CanvasPanelLayout.templateBar,localX,localY))
      {
         PanelAction candidate=CanvasHitActionAt(chartX,chartY);
         if(IsHoldingToolbarAction(candidate)) hit=candidate;
      }
   }
   else if(CanvasStatsToolbarVisible())
   {
      int localX=chartX-CanvasPanelState.panelX;
      int localY=chartY-CanvasPanelState.panelY;
      bool inPointerArea=UIContains(CanvasPanelLayout.statsToolbar,localX,localY);
      if(CanvasPanelState.statsDetail==统计详情_总览)
         inPointerArea=inPointerArea || UIContains(CanvasPanelLayout.statsSummary[2],localX,localY) ||
                                      UIContains(CanvasPanelLayout.statsSummary[3],localX,localY);
      if(inPointerArea)
      {
         PanelAction candidate=CanvasHitActionAt(chartX,chartY);
         if(IsStatsToolbarAction(candidate)) hit=candidate;
      }
   }

   PanelAction nextHover=hit;
   PanelAction nextPressed=leftDown?hit:PANEL_ACTION_NONE;
   if(CanvasPanelState.hoverAction==nextHover && CanvasPanelState.pressedAction==nextPressed) return;
   CanvasPanelState.hoverAction=nextHover;
   CanvasPanelState.pressedAction=nextPressed;
   MarkCanvasPanelDirty(PANEL_DIRTY_RENDER);
   RefreshCanvasPanelByDirtyFlags(false);
}

bool HandleCanvasMiniChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   bool canvasPage=使用新版Canvas面板;
   if(!canvasPage) return false;
   int mx=(int)lparam;
   int my=(int)dparam;

   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      PanelAction nativeAction=PANEL_ACTION_NONE;
      if(sparam=="SMA_BTN_NEWS_FREEZE") nativeAction=PANEL_ACTION_NEWS_FREEZE;
      else if(sparam=="SMA_BTN_NEWS_RELEASE") nativeAction=PANEL_ACTION_NEWS_RELEASE;
      else if(sparam=="SMA_BTN_NEWS_CANCEL") nativeAction=PANEL_ACTION_NEWS_CANCEL;
      else if(sparam=="SMA_BTN_NEWS_FLAT") nativeAction=PANEL_ACTION_NEWS_FLAT;
      else if(sparam=="SMA_BTN_MARKER_VIS") nativeAction=PANEL_ACTION_MARKER_TOGGLE;
      if(nativeAction!=PANEL_ACTION_NONE)
      {
         if(sparam=="SMA_BTN_MARKER_VIS") ObjectDelete(0,sparam);
         else ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         if(IsDuplicateCanvasPhysicalClick(mx,my,nativeAction)) return true;
         DispatchCanvasPanelAction(nativeAction);
         return true;
      }
   }

   if(id==CHARTEVENT_CHART_CHANGE)
   {
      int chartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
      int chartHeight=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
      double dpiScale=MathMax(0.85,MathMin((double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0,1.75));
      int oldX=CanvasPanelState.panelX;
      int oldY=CanvasPanelState.panelY;
      ClampCanvasPanelPosition();
      bool positionChanged=(oldX!=CanvasPanelState.panelX || oldY!=CanvasPanelState.panelY);
      bool sizeChanged=(chartWidth!=CanvasLastChartWidth || chartHeight!=CanvasLastChartHeight);
      bool dpiChanged=(MathAbs(dpiScale-CanvasLastDpiScale)>0.0001);
      CanvasLastChartWidth=chartWidth;
      CanvasLastChartHeight=chartHeight;
      CanvasLastDpiScale=dpiScale;
      if(!positionChanged && !sizeChanged && !dpiChanged) return true;
      SyncLegacyStateFromCanvas();
      int dirty=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
      if(dpiChanged) dirty|=PANEL_DIRTY_STYLE;
      MarkCanvasPanelDirty(dirty);
      RefreshCanvasPanelByDirtyFlags(false);
      return true;
   }

   if(id==CHARTEVENT_MOUSE_MOVE)
      UpdateCanvasToolbarPointerState(mx,my,LeftMouseDownFromMask(sparam));

   if(id==CHARTEVENT_MOUSE_MOVE && 允许鼠标拖动面板)
   {
      bool leftDown=LeftMouseDownFromMask(sparam);
      if(leftDown)
      {
         PanelAction hit=CanvasHitActionAt(mx,my);
         if(!CanvasPanelState.dragging && hit==PANEL_ACTION_NONE && CanvasPointInPanel(mx,my))
         {
            CanvasPanelState.dragging=true;
            CanvasPanelState.dragMouseX=mx;
            CanvasPanelState.dragMouseY=my;
            CanvasPanelState.dragPanelX=CanvasPanelState.panelX;
            CanvasPanelState.dragPanelY=CanvasPanelState.panelY;
            ChartSetInteger(0,CHART_MOUSE_SCROLL,false);
         }
         if(CanvasPanelState.dragging)
         {
            CanvasPanelState.panelX=CanvasPanelState.dragPanelX+(mx-CanvasPanelState.dragMouseX);
             CanvasPanelState.panelY=CanvasPanelState.dragPanelY+(my-CanvasPanelState.dragMouseY);
             ClampCanvasPanelPosition();
             CanvasPanelRenderer.Move(CanvasPanelState.panelX,CanvasPanelState.panelY);
             MoveCanvasNativeButtons();
             return true;
         }
      }
      else if(CanvasPanelState.dragging)
      {
         CanvasPanelState.dragging=false;
         CanvasPanelState.suppressClickUntilTick=GetTickCount64()+140;
         ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
         SyncLegacyStateFromCanvas();
         MarkCanvasPanelDirty(PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER);
         RefreshCanvasPanelByDirtyFlags(false);
         return true;
      }
      return CanvasPointInPanel(mx,my);
   }

   if(id==CHARTEVENT_CLICK || (id==CHARTEVENT_OBJECT_CLICK && sparam=="SMA_CANVAS"))
   {
      PanelAction action=CanvasHitActionAt(mx,my);
      if(action!=PANEL_ACTION_NONE)
      {
         if(IsDuplicateCanvasPhysicalClick(mx,my,action)) return true;
         DispatchCanvasPanelAction(action);
         return true;
      }
      return CanvasPointInPanel(mx,my);
   }
   return false;
}

void BuildHoldingPanelViewModel(PanelViewModel &model)
{
   ulong perfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
   model.holding.managedCount=0;
   model.holding.buyCount=0;
   model.holding.sellCount=0;
   model.holding.buyLots=0.0;
   model.holding.sellLots=0.0;
   model.holding.totalLots=0.0;
   model.holding.floatingProfit=0.0;
   model.holding.peakProfit=0.0;
   model.holding.slCount=0;
   model.holding.tpCount=0;
   model.holding.protectedCount=0;
   model.holding.markerEnabled=当前启用手机标记挂单();
   ArrayResize(model.holding.positions,0);
   int miniDistanceDigits=MiniPriceDistanceDigits();

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket) || !PositionInScope()) continue;
      int n=ArraySize(model.holding.positions);
      ArrayResize(model.holding.positions,n+1);
      PositionPanelViewModel position;
      position.ticket=0;
      position.type=0;
      position.volume=0.0;
      position.openPrice=0.0;
      position.currentPrice=0.0;
      position.sl=0.0;
      position.tp=0.0;
      position.profit=0.0;
      position.peakProfit=0.0;
      position.profitPrice=0.0;
      position.riskDistance=0.0;
      position.hasSL=false;
      position.hasTP=false;
      position.hasCurrentPrice=false;
      position.distanceToSLValid=false;
      position.distanceToTPValid=false;
      position.distanceToSL=0.0;
      position.distanceToTP=0.0;
      position.distanceToSLText="--";
      position.distanceToTPText="--";
      position.protectedPosition=false;
      position.heldMinutes=0;
      position.templateId=(int)配置_自定义;
      position.templateName="";
      position.lifecycleName="";
      position.protectionText="";
      position.nextActionText="";
      position.severity=UI_SEVERITY_MUTED;
      position.ticket=ticket;
      position.type=PositionGetInteger(POSITION_TYPE);
      position.volume=PositionGetDouble(POSITION_VOLUME);
      position.openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      position.currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);
      position.sl=PositionGetDouble(POSITION_SL);
      position.tp=PositionGetDouble(POSITION_TP);
      position.profit=PositionGetDouble(POSITION_PROFIT);
      position.peakProfit=position.profit;
      position.profitPrice=position.type==POSITION_TYPE_BUY ? position.currentPrice-position.openPrice : position.openPrice-position.currentPrice;
      position.hasSL=position.sl>0.0;
      position.hasTP=position.tp>0.0;
      position.hasCurrentPrice=position.currentPrice>0.0;
      position.distanceToSLValid=position.hasCurrentPrice && position.hasSL;
      position.distanceToTPValid=position.hasCurrentPrice && position.hasTP;
      if(position.distanceToSLValid)
         position.distanceToSL=MathMax(position.type==POSITION_TYPE_BUY ? position.currentPrice-position.sl : position.sl-position.currentPrice,0.0);
      if(position.distanceToTPValid)
         position.distanceToTP=MathMax(position.type==POSITION_TYPE_BUY ? position.tp-position.currentPrice : position.currentPrice-position.tp,0.0);
      position.distanceToSLText=FormatMiniPriceDistance(position.distanceToSL,position.distanceToSLValid,miniDistanceDigits);
      position.distanceToTPText=FormatMiniPriceDistance(position.distanceToTP,position.distanceToTPValid,miniDistanceDigits);
      position.riskDistance=position.hasSL ? MathAbs(position.openPrice-position.sl) : 0.0;
      position.protectedPosition=position.hasSL && ((position.type==POSITION_TYPE_BUY && position.sl>=position.openPrice) ||
                                                     (position.type==POSITION_TYPE_SELL && position.sl<=position.openPrice));
      datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
      position.heldMinutes=(openTime>0)?(int)MathMax((TimeCurrent()-openTime)/60,0):0;
      int stateIdx=FindState(ticket);
      int templateId=(int)当前参数配置模板;
      position.lifecycleName="已接管";
      position.protectionText=!position.hasSL?"无止损":(position.protectedPosition?"已保护":"待保护");
      if(stateIdx>=0 && stateIdx<ArraySize(states))
      {
         if(states[stateIdx].adoptedTemplate>=(int)配置_自定义 && states[stateIdx].adoptedTemplate<=(int)配置_黄金消息对冲)
            templateId=states[stateIdx].adoptedTemplate;
         position.lifecycleName=LifecyclePhaseText(states[stateIdx].lifecyclePhase);
         if(position.hasSL && !position.protectedPosition && states[stateIdx].protectionStage!=保护阶段_无有效SL)
            position.protectionText=ProtectionStageText(states[stateIdx].protectionStage);
         if(states[stateIdx].pendingAction!=待确认动作_无)
            position.nextActionText="等待"+PendingActionText(states[stateIdx].pendingAction)+"确认";
         position.peakProfit=MathMax(position.profit,states[stateIdx].maxProfitMoney);
      }
      position.templateId=templateId;
      position.templateName=CanvasTemplateName(templateId);
      if(CanvasDisplayTextMissing(position.nextActionText))
         position.nextActionText=简化面板下一步提示(templateId,(ENUM_POSITION_TYPE)position.type,position.openPrice,position.sl,position.tp);
      if(CanvasDisplayTextMissing(position.nextActionText))
         position.nextActionText="按当前规则管理";
      position.severity=!position.hasSL ? UI_SEVERITY_DANGER :
                        (position.protectedPosition ? UI_SEVERITY_SUCCESS :
                        (position.profit<0.0 ? UI_SEVERITY_WARNING : UI_SEVERITY_INFO));
      model.holding.positions[n]=position;
      model.holding.peakProfit+=position.peakProfit;
      model.holding.managedCount++;
      model.holding.floatingProfit+=position.profit;
      model.holding.totalLots+=position.volume;
      if(position.type==POSITION_TYPE_BUY)
      {
         model.holding.buyCount++;
         model.holding.buyLots+=position.volume;
      }
      else
      {
         model.holding.sellCount++;
         model.holding.sellLots+=position.volume;
      }
      if(position.hasSL) model.holding.slCount++;
      if(position.hasTP) model.holding.tpCount++;
      if(position.protectedPosition) model.holding.protectedCount++;
   }

   if(model.holding.managedCount<=0)
      model.holding.riskSummary="空仓";
   else if(model.holding.slCount<model.holding.managedCount)
      model.holding.riskSummary=StringFormat("缺 SL %d",model.holding.managedCount-model.holding.slCount);
   else if(model.holding.protectedCount==model.holding.managedCount)
      model.holding.riskSummary="已保护";
   else
      model.holding.riskSummary="待保护";

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double mid=(bid>0.0 && ask>0.0)?(bid+ask)/2.0:0.0;
   SRLevel level;
   model.holding.resistanceText="R1 --";
   model.holding.supportText="S1 --";
   if(mid>0.0 && GetNearestResistance(mid,level)) model.holding.resistanceText="R1 "+DoubleToString(level.price,_Digits);
   if(mid>0.0 && GetNearestSupport(mid,level)) model.holding.supportText="S1 "+DoubleToString(level.price,_Digits);
   model.holding.statusText=lastStatus;
   model.holding.statusSeverity=CanvasStatusSeverity(lastStatus);
   model.spreadPoints=(bid>0.0 && ask>0.0)?(ask-bid)/_Point:0.0;
   NewsBuildFrozenStopPreview(model.holding.newsStopPreview);
   RebuildHoldingDisplayProjection(model.holding);
   CanvasUIPerfStage("Build holding model",perfStart,20000);
}

int HoldingCanvasLogicalHeight(const HoldingPanelViewModel &model)
{
   int visible=MathMin(ArraySize(model.filteredPositionIndexes),3);
   int positionArea=visible<=0?68:visible*84+MathMax(visible-1,0)*8;
   int logicalHeight=40+6+36+8+72+8+28+8+positionArea+8+32+6+30+8;
   if(当前模板使用消息对冲()) logicalHeight+=38;
   return logicalHeight;
}

void CalculateCanvasHeaderLayout(void)
{
   int w=CanvasPanelMetrics.width;
   int m=CanvasPanelMetrics.margin;
   int header=CanvasPanelMetrics.headerHeight;
   int headerH=CanvasScalePx(28);
   int headerY=MathMax((header-headerH)/2,0);
   int controlGap=CanvasPanelMetrics.space4;
   int x=w-m;
   int closeW=CanvasScalePx(24);
   int miniW=CanvasScalePx(24);
   int pageW=CanvasScalePx(48);
   CanvasPanelLayout.mainTabs[4]=MakeUIRect(x-closeW,headerY,closeW,headerH); x-=closeW+controlGap;
   CanvasPanelLayout.mainTabs[3]=MakeUIRect(x-miniW,headerY,miniW,headerH); x-=miniW+controlGap;
   CanvasPanelLayout.mainTabs[1]=MakeUIRect(x-pageW,headerY,pageW,headerH); x-=pageW+controlGap;
   CanvasPanelLayout.mainTabs[0]=MakeUIRect(x-pageW,headerY,pageW,headerH);
   CanvasPanelLayout.mainTabs[2]=MakeUIRect(0,0,0,0);

   int navLeft=CanvasPanelLayout.mainTabs[0].x;
   UISeverity runSeverity=CanvasStatusSeverity(lastStatus);
   string runText=CanvasHeaderStatusText(runSeverity);
   int measuredStatus=CanvasPanelRenderer.TextWidth(runText,CanvasResolvedFont,CanvasPanelMetrics.fontCaption)+CanvasPanelMetrics.space8;
   int statusW=MathMax(CanvasScalePx(50),MathMin(measuredStatus,CanvasScalePx(58)));
   CanvasPanelLayout.headerStatus=MakeUIRect(navLeft-statusW-CanvasPanelMetrics.space8,0,statusW,header);

   int titleAvailable=MathMax(CanvasPanelLayout.headerStatus.x-m-CanvasPanelMetrics.space10,1);
   CanvasPanelLayout.headerTitle=MakeUIRect(m,0,titleAvailable,header);
}

void CalculateHoldingPanelLayout(void)
{
   int w=CanvasPanelMetrics.width;
   int h=CanvasPanelMetrics.height;
   int m=CanvasPanelMetrics.margin;
   int header=CanvasPanelMetrics.headerHeight;
   int gap6=CanvasPanelMetrics.space6;
   int gap8=CanvasPanelMetrics.space8;
   CanvasPanelLayout.panel=MakeUIRect(0,0,w,h);
   CanvasPanelLayout.header=MakeUIRect(0,0,w,header);
   CalculateCanvasHeaderLayout();

   int templateY=header+gap6;
   int templateH=CanvasScalePx(36);
   CanvasPanelLayout.templateBar=MakeUIRect(m,templateY,w-m*2,templateH);
   int contentW=CanvasPanelLayout.templateBar.w;
   int normalGap=CanvasScalePx(7);
   int functionGap=CanvasScalePx(10);
   int buttonInsetY=CanvasScalePx(1);
   int buttonY=templateY+buttonInsetY;
   int buttonH=MathMax(templateH-buttonInsetY*2,CanvasScalePx(32));
   int markerW=CanvasScalePx(116);
   int filterAreaW=MathMax(contentW-markerW-functionGap,1);
   int availableForFilters=MathMax(filterAreaW-normalGap*4,5);
   int filterW=MathMax(availableForFilters/5,1);
   int tabX=m;
   for(int i=0;i<5;i++)
   {
      int tabW=(i==4)?MathMax(m+filterAreaW-tabX,1):filterW;
      CanvasPanelLayout.templateTabs[i]=MakeUIRect(tabX,buttonY,tabW,buttonH);
      tabX+=tabW+(i<4?normalGap:0);
   }
   CanvasPanelLayout.markerBadge=MakeUIRect(m+filterAreaW+functionGap,buttonY,markerW,buttonH);

   int metricsY=templateY+templateH+gap8;
   int metricAvailable=w-m*2;
   int metricWidths[4];
   metricWidths[0]=metricAvailable*27/100;
   metricWidths[1]=metricAvailable*27/100;
   metricWidths[2]=metricAvailable*23/100;
   metricWidths[3]=metricAvailable-metricWidths[0]-metricWidths[1]-metricWidths[2];
   int metricH=CanvasScalePx(72);
   int metricX=m;
   for(int i=0;i<4;i++)
   {
      CanvasPanelLayout.metricCards[i]=MakeUIRect(metricX,metricsY,metricWidths[i],metricH);
      metricX+=metricWidths[i];
   }

   int positionsHeaderY=CanvasPanelLayout.metricCards[0].y+CanvasPanelLayout.metricCards[0].h+gap8;
   int positionsHeaderH=CanvasScalePx(28);
   CanvasPanelLayout.positionsHeader=MakeUIRect(m,positionsHeaderY,w-m*2,positionsHeaderH);
   int total=ArraySize(CanvasPanelModel.holding.filteredPositionIndexes);
   int pageCount=MathMax((total+2)/3,1);
   CanvasPanelState.positionPage=MathMax(0,MathMin(CanvasPanelState.positionPage,pageCount-1));

   string entryStatus=EntryTemplateStatusText();
   int entryStatusW=CanvasPanelRenderer.TextWidth(entryStatus,CanvasResolvedFont,CanvasPanelMetrics.fontCaption)+CanvasPanelMetrics.space12*2;
   entryStatusW=MathMax(CanvasScalePx(96),MathMin(entryStatusW,CanvasPanelLayout.positionsHeader.w*28/100));
   CanvasPanelLayout.positionEntryTemplate=MakeUIRect(CanvasPanelLayout.positionsHeader.x+CanvasPanelLayout.positionsHeader.w-entryStatusW,
                                                       positionsHeaderY,entryStatusW,positionsHeaderH);
   int titleRight=CanvasPanelLayout.positionEntryTemplate.x-CanvasPanelMetrics.space10;
   if(pageCount>1)
   {
      int pageRight=CanvasPanelLayout.positionEntryTemplate.x-CanvasPanelMetrics.space8;
      CanvasPanelLayout.positionNext=MakeUIRect(pageRight-CanvasScalePx(26),positionsHeaderY,CanvasScalePx(26),positionsHeaderH);
      CanvasPanelLayout.positionPageLabel=MakeUIRect(CanvasPanelLayout.positionNext.x-CanvasScalePx(52),positionsHeaderY,CanvasScalePx(52),positionsHeaderH);
      CanvasPanelLayout.positionPrev=MakeUIRect(CanvasPanelLayout.positionPageLabel.x-CanvasScalePx(26),positionsHeaderY,CanvasScalePx(26),positionsHeaderH);
      titleRight=CanvasPanelLayout.positionPrev.x-CanvasPanelMetrics.space8;
   }
   else
   {
      CanvasPanelLayout.positionPrev=MakeUIRect(0,0,0,0);
      CanvasPanelLayout.positionPageLabel=MakeUIRect(0,0,0,0);
      CanvasPanelLayout.positionNext=MakeUIRect(0,0,0,0);
   }
   CanvasPanelLayout.positionFilterScope=MakeUIRect(CanvasPanelLayout.positionsHeader.x+CanvasPanelMetrics.space12,
                                                    positionsHeaderY,
                                                    MathMax(titleRight-CanvasPanelLayout.positionsHeader.x-CanvasPanelMetrics.space12,1),
                                                    positionsHeaderH);

   int positionY=CanvasPanelLayout.positionsHeader.y+CanvasPanelLayout.positionsHeader.h+gap8;
   int visible=MathMin(total,3);
   for(int slot=0;slot<3;slot++)
   {
      UIRect rect=MakeUIRect(m,positionY+slot*CanvasScalePx(92),w-m*2,CanvasScalePx(84));
      CanvasPanelLayout.positionCards[slot]=rect;
      int row1Y=rect.y+CanvasPanelMetrics.space8;
      int row1H=CanvasScalePx(22);
      int profitW=CanvasScalePx(88);
      int badgeW=CanvasScalePx(72);
      CanvasPanelLayout.positionDirection[slot]=MakeUIRect(rect.x+CanvasPanelMetrics.space12,row1Y,CanvasScalePx(42),row1H);
      CanvasPanelLayout.positionProfit[slot]=MakeUIRect(rect.x+rect.w-profitW-CanvasPanelMetrics.space12,row1Y,profitW,row1H);
      CanvasPanelLayout.positionProtection[slot]=MakeUIRect(CanvasPanelLayout.positionProfit[slot].x-badgeW-CanvasPanelMetrics.space8,row1Y+CanvasScalePx(1),badgeW,CanvasScalePx(20));
      int identityX=CanvasPanelLayout.positionDirection[slot].x+CanvasPanelLayout.positionDirection[slot].w+CanvasPanelMetrics.space6;
      CanvasPanelLayout.positionIdentity[slot]=MakeUIRect(identityX,row1Y,MathMax(CanvasPanelLayout.positionProtection[slot].x-identityX-CanvasPanelMetrics.space8,CanvasScalePx(80)),row1H);
      CanvasPanelLayout.positionPrices[slot]=MakeUIRect(rect.x+CanvasPanelMetrics.space12,rect.y+CanvasScalePx(34),rect.w-CanvasPanelMetrics.space12*2,CanvasScalePx(20));
      CanvasPanelLayout.positionMeta[slot]=MakeUIRect(rect.x+CanvasPanelMetrics.space12,rect.y+CanvasScalePx(58),rect.w-CanvasPanelMetrics.space12*2,CanvasScalePx(18));
   }
   CanvasPanelLayout.emptyState=MakeUIRect(m,positionY,w-m*2,CanvasScalePx(68));
   CanvasPanelLayout.emptyTitle=MakeUIRect(m+CanvasPanelMetrics.space16,positionY+CanvasPanelMetrics.space8,w-m*2-CanvasPanelMetrics.space16*2,CanvasScalePx(26));
   CanvasPanelLayout.emptyCaption=MakeUIRect(m+CanvasPanelMetrics.space16,positionY+CanvasScalePx(36),w-m*2-CanvasPanelMetrics.space16*2,CanvasScalePx(24));

   int positionArea=visible<=0?CanvasScalePx(68):CanvasScalePx(visible*84+MathMax(visible-1,0)*8);
   int supportY=positionY+positionArea+gap8;
   CanvasPanelLayout.supportRow=MakeUIRect(m,supportY,w-m*2,CanvasScalePx(32));
   CanvasPanelLayout.statusRow=MakeUIRect(m,CanvasPanelLayout.supportRow.y+CanvasPanelLayout.supportRow.h+gap6,w-m*2,CanvasScalePx(30));
   CanvasPanelLayout.footer=MakeUIRect(m,CanvasPanelLayout.supportRow.y,w-m*2,CanvasPanelLayout.statusRow.y+CanvasPanelLayout.statusRow.h-CanvasPanelLayout.supportRow.y);

   int dangerY=CanvasPanelLayout.statusRow.y+CanvasPanelLayout.statusRow.h+gap8;
   int dangerGap=CanvasPanelMetrics.space6;
   int dangerW=(w-m*2-dangerGap*3)/4;
   for(int i=0;i<4;i++)
      CanvasPanelLayout.newsButtons[i]=MakeUIRect(m+i*(dangerW+dangerGap),dangerY,dangerW,CanvasScalePx(30));
   当前面板宽度=w;
   当前面板高度=h;
}

void RenderCanvasHeader(void)
{
   CanvasPanelRenderer.FillRect(CanvasPanelLayout.header,CanvasPanelTheme.header);
   DrawSoftDivider(CanvasPanelLayout.header.x,CanvasPanelLayout.header.y+CanvasPanelLayout.header.h-1,
                   CanvasPanelLayout.header.x+CanvasPanelLayout.header.w-1,CanvasPanelLayout.header.y+CanvasPanelLayout.header.h-1);
   CanvasPanelRenderer.FillRect(MakeUIRect(0,0,CanvasScalePx(3),CanvasPanelLayout.header.h),CanvasThemeAccent());
   CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.headerTitle,CanvasHeaderTitleText(),CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontHeader,0,CanvasScalePx(2));
   UISeverity runSeverity=CanvasStatusSeverity(lastStatus);
   string runText=CanvasHeaderStatusText(runSeverity);
   CanvasMarketSessionState marketSession=CanvasCurrentMarketSession();
   uint normalSessionColor=(marketSession==CANVAS_MARKET_CLOSED?CanvasThemeDim():
                            (marketSession==CANVAS_MARKET_LOW_ACTIVITY?CanvasThemeMuted():CanvasThemeAccent()));
   uint runColor=runSeverity==UI_SEVERITY_DANGER?CanvasThemeDanger():(runSeverity==UI_SEVERITY_WARNING?CanvasThemeWarning():normalSessionColor);
   CanvasPanelRenderer.TextLeft(CanvasPanelLayout.headerStatus,runText,runColor,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);

   string pageTexts[2]={"持仓","统计"};
   for(int i=0;i<2;i++)
   {
      bool active=(i==0 && CanvasPanelState.page==页面持仓) || (i==1 && CanvasPanelState.page==页面今日);
      DrawCanvasButton(CanvasPanelLayout.mainTabs[i],pageTexts[i],active?CONTROL_SELECTED:CONTROL_NORMAL);
   }
   CanvasPanelRenderer.TextCenter(CanvasPanelLayout.mainTabs[3],"－",CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontHeader);
   CanvasPanelRenderer.TextCenter(CanvasPanelLayout.mainTabs[4],"×",CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontHeader);
}

void BuildHoldingHitRegions(void)
{
   ArrayResize(CanvasPanelHitRegions,0);
   AddCanvasHit(CanvasPanelLayout.mainTabs[0],PANEL_ACTION_PAGE_HOLDING);
   AddCanvasHit(CanvasPanelLayout.mainTabs[1],PANEL_ACTION_PAGE_STATS);
   AddCanvasHit(CanvasPanelLayout.mainTabs[3],PANEL_ACTION_MODE_MINI);
   AddCanvasHit(CanvasPanelLayout.mainTabs[4],PANEL_ACTION_MODE_HIDE);
   PanelAction templateActions[5]={PANEL_ACTION_POSITION_FILTER_ALL,PANEL_ACTION_TEMPLATE_FAST,PANEL_ACTION_TEMPLATE_TREND,
                                   PANEL_ACTION_TEMPLATE_NEWS,PANEL_ACTION_TEMPLATE_NORMAL};
   for(int i=0;i<5;i++) AddCanvasHit(CanvasPanelLayout.templateTabs[i],templateActions[i]);
   AddCanvasHit(CanvasPanelLayout.markerBadge,PANEL_ACTION_MARKER_TOGGLE);
   int pageCount=MathMax((ArraySize(CanvasPanelModel.holding.filteredPositionIndexes)+2)/3,1);
   if(pageCount>1)
   {
      AddCanvasHit(CanvasPanelLayout.positionPrev,PANEL_ACTION_POSITION_PREV,CanvasPanelState.positionPage>0);
      AddCanvasHit(CanvasPanelLayout.positionNext,PANEL_ACTION_POSITION_NEXT,CanvasPanelState.positionPage<pageCount-1);
   }
}

void SyncCanvasNewsButtons(const HoldingPanelViewModel &model)
{
   string names[4]={"SMA_BTN_NEWS_FREEZE","SMA_BTN_NEWS_RELEASE","SMA_BTN_NEWS_CANCEL","SMA_BTN_NEWS_FLAT"};
   if(!当前模板使用消息对冲())
   {
      HideCanvasNewsButtons();
      return;
   }
   bool enabled[4];
   bool preEntryFreeze=(启用消息双Stop真实挂单 && newsState.stage==消息阶段_待命 && !NewsHasAnyStrategyStopObject());
   bool stopDeploy=(启用消息双Stop真实挂单 && newsState.stage==消息阶段_箱体冻结 &&
                    newsState.boxFrozenByUser && newsState.boxValid && newsState.buyTicket==0 && newsState.sellTicket==0 &&
                    newsState.stopStage==消息双Stop_空闲);
   enabled[0]=(newsState.stage==消息阶段_配对安全 || preEntryFreeze);
   bool manualRelease=(newsState.stage==消息阶段_箱体冻结 && newsState.boxFrozenByUser && newsState.boxValid &&
                       newsState.buyTicket>0 && newsState.sellTicket>0);
   enabled[1]=(stopDeploy || manualRelease);
   enabled[2]=(newsState.stage!=消息阶段_待命 || newsState.waitTicket>0 || newsState.stopToken>0);
   enabled[3]=(model.managedCount>0 || newsState.runnerTicket>0 || newsState.buyTicket>0 || newsState.sellTicket>0);
   string texts[4]={enabled[0]?"冻结箱体":"冻结不可用",stopDeploy?"部署双Stop":(enabled[1]?"开放拆锁":"开放不可用"),"取消本次","消息紧急全平"};
   string signature=StringFormat("%d|%d|%d|%I64u|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d",
                                 CanvasPanelState.panelX,CanvasPanelState.panelY,(int)newsState.stage,newsState.waitTicket,model.managedCount,
                                 enabled[0],enabled[1],enabled[2],enabled[3],
                                 CanvasPanelLayout.newsButtons[0].x,CanvasPanelLayout.newsButtons[0].y,CanvasPanelLayout.newsButtons[0].w,CanvasPanelLayout.newsButtons[0].h,
                                 CanvasPanelLayout.newsButtons[1].x,CanvasPanelLayout.newsButtons[1].y,CanvasPanelLayout.newsButtons[1].w,CanvasPanelLayout.newsButtons[1].h,
                                 CanvasPanelLayout.newsButtons[2].x,CanvasPanelLayout.newsButtons[2].y,CanvasPanelLayout.newsButtons[2].w,CanvasPanelLayout.newsButtons[2].h,
                                  CanvasPanelLayout.newsButtons[3].x,CanvasPanelLayout.newsButtons[3].y,CanvasPanelLayout.newsButtons[3].w,CanvasPanelLayout.newsButtons[3].h,
                                  newsState.boxFrozenByUser,newsState.boxValid);
   signature+="|"+IntegerToString(newsState.stopStage)+"|"+texts[1];
   bool allAlive=true;
   for(int i=0;i<4;i++) if(ObjectFind(0,names[i])<0) { allAlive=false; break; }
   if(CanvasNewsButtonsVisible && allAlive && signature==CanvasNewsButtonsSignature) return;
   for(int i=0;i<4;i++)
   {
      UIRect rect=CanvasPanelLayout.newsButtons[i];
      CreatePanelButton(names[i],texts[i],rect.x,rect.y,rect.w,rect.h,enabled[i]);
      ObjectSetInteger(0,names[i],OBJPROP_ZORDER,30);
   }
   CanvasNewsButtonsVisible=true;
   CanvasNewsButtonsSignature=signature;
}

int RenderCanvasInlineToken(const UIRect &rect, int x, string text, uint colorValue, int fontSize, int gapAfter=0)
{
   int right=rect.x+rect.w;
   if(x>=right) return x;
   int width=CanvasPanelRenderer.TextWidth(text,CanvasResolvedFont,fontSize);
   int available=MathMax(right-x,1);
   int shownWidth=MathMin(width,available);
   CanvasPanelRenderer.TextEllipsized(MakeUIRect(x,rect.y,shownWidth,rect.h),text,colorValue,CanvasResolvedFont,fontSize);
   return x+shownWidth+gapAfter;
}

void RenderPositionPriceLine(const UIRect &rect, const PositionPanelViewModel &position)
{
   int x=rect.x;
   int gap=CanvasPanelMetrics.space4;
   x=RenderCanvasInlineToken(rect,x,"开仓 ",CanvasThemeDim(),CanvasPanelMetrics.fontCaption,0);
   x=RenderCanvasInlineToken(rect,x,DoubleToString(position.openPrice,_Digits),CanvasThemeText(),CanvasPanelMetrics.fontBody,gap);
   x=RenderCanvasInlineToken(rect,x,"→",CanvasThemeDim(),CanvasPanelMetrics.fontCaption,gap);
   x=RenderCanvasInlineToken(rect,x,"现价 ",CanvasThemeDim(),CanvasPanelMetrics.fontCaption,0);
   x=RenderCanvasInlineToken(rect,x,DoubleToString(position.currentPrice,_Digits),CanvasThemeText(),CanvasPanelMetrics.fontBody,CanvasPanelMetrics.space8);
   x=RenderCanvasInlineToken(rect,x,"SL ",CanvasThemeDim(),CanvasPanelMetrics.fontCaption,0);
   x=RenderCanvasInlineToken(rect,x,position.hasSL?DoubleToString(position.sl,_Digits):"--",position.hasSL?CanvasThemeText():CanvasThemeDanger(),CanvasPanelMetrics.fontBody,CanvasPanelMetrics.space8);
   x=RenderCanvasInlineToken(rect,x,"TP ",CanvasThemeDim(),CanvasPanelMetrics.fontCaption,0);
   RenderCanvasInlineToken(rect,x,position.hasTP?DoubleToString(position.tp,_Digits):"--",CanvasThemeText(),CanvasPanelMetrics.fontBody,0);
}

void RenderPositionMetaLine(const UIRect &rect, const PositionPanelViewModel &position)
{
   string nextAction=position.nextActionText;
   if(CanvasDisplayTextMissing(nextAction)) nextAction="按当前规则管理";
   string prefix=StringFormat("%s · 持有 %s · %s · ",position.templateName,FormatHoldMinutes(position.heldMinutes),position.lifecycleName);
   int prefixWidth=CanvasPanelRenderer.TextWidth(prefix,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   int nextWidth=MathMax(rect.w-MathMin(prefixWidth,rect.w),1);
   CanvasPanelRenderer.TextEllipsized(MakeUIRect(rect.x,rect.y,MathMin(prefixWidth,rect.w),rect.h),prefix,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   if(prefixWidth<rect.w)
      CanvasPanelRenderer.TextEllipsized(MakeUIRect(rect.x+prefixWidth,rect.y,nextWidth,rect.h),"下一步："+nextAction,CanvasPanelTheme.infoText,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
}

void RenderHoldingMetricCell(const UIRect &rect, string label, string value, string caption, uint valueColor)
{
   int padX=CanvasPanelMetrics.space10;
   int padY=CanvasPanelMetrics.space8;
   UIRect content=MakeUIRect(rect.x+padX,rect.y+padY,MathMax(rect.w-padX*2,1),MathMax(rect.h-padY*2,1));
   int labelH=CanvasPanelRenderer.TextHeight(label,CanvasResolvedFont,CanvasPanelMetrics.fontLabel);
   int valueH=CanvasPanelRenderer.TextHeight(value,CanvasResolvedFont,CanvasPanelMetrics.fontValue);
   int captionFont=CanvasPanelMetrics.fontCaption;
   int captionH=CanvasPanelRenderer.TextHeight(caption,CanvasResolvedFont,captionFont);
   int rowH=MathMax(valueH,captionH);
   int rowY=content.y+content.h-rowH;
   CanvasPanelRenderer.TextLeft(MakeUIRect(content.x,content.y,content.w,labelH),label,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontLabel);

   string captionShown=caption;
   int valueW=CanvasPanelRenderer.TextWidth(value,CanvasResolvedFont,CanvasPanelMetrics.fontValue);
   int captionW=CanvasPanelRenderer.TextWidth(captionShown,CanvasResolvedFont,captionFont);
   int safeGap=CanvasPanelMetrics.space6;
   if(valueW+safeGap+captionW>content.w)
   {
      captionFont=CanvasFontSize(8.5);
      captionH=CanvasPanelRenderer.TextHeight(captionShown,CanvasResolvedFont,captionFont);
      captionW=CanvasPanelRenderer.TextWidth(captionShown,CanvasResolvedFont,captionFont);
   }
   if(valueW+safeGap+captionW>content.w)
   {
      StringReplace(captionShown," ","");
      captionW=CanvasPanelRenderer.TextWidth(captionShown,CanvasResolvedFont,captionFont);
   }
   rowH=MathMax(valueH,captionH);
   rowY=content.y+content.h-rowH;
   CanvasPanelRenderer.TextLeft(MakeUIRect(content.x,rowY,valueW,rowH),value,valueColor,CanvasResolvedFont,CanvasPanelMetrics.fontValue);
   int captionX=content.x+content.w-captionW;
   CanvasPanelRenderer.TextRight(MakeUIRect(captionX,rowY,captionW,rowH),captionShown,CanvasThemeDim(),CanvasResolvedFont,captionFont);
}

void RenderHoldingCanvasPanel(const PanelViewModel &model)
{
   CanvasPanelRenderer.Begin(CanvasThemeBackground());
   DrawSurface(CanvasPanelLayout.panel,SURFACE_ROOT,CanvasPanelMetrics.radiusContainer,true,false,true);
   RenderCanvasHeader();

   // templateBar只保留为布局与指针范围；不绘制表面，让按钮四周露出根背景。
   string templateTexts[5]={"全部","短线","长线","消息","手动"};
   持仓显示筛选类型 templateFilters[5]={持仓筛选_全部,持仓筛选_短线,持仓筛选_长线,持仓筛选_消息,持仓筛选_手动};
   PanelAction templateActions[5]={PANEL_ACTION_POSITION_FILTER_ALL,PANEL_ACTION_TEMPLATE_FAST,PANEL_ACTION_TEMPLATE_TREND,
                                   PANEL_ACTION_TEMPLATE_NEWS,PANEL_ACTION_TEMPLATE_NORMAL};
   持仓显示筛选类型 entryTemplateFilter=TemplateToPositionFilter(当前参数配置模板);
   for(int i=0;i<5;i++)
   {
      bool active=CanvasPanelState.positionFilter==templateFilters[i];
      CanvasControlVisualState state=HoldingToolbarControlState(templateActions[i],active);
      DrawHoldingToolbarButton(CanvasPanelLayout.templateTabs[i],templateTexts[i],state,active);
      DrawCurrentEntryTemplateMarker(CanvasPanelLayout.templateTabs[i],i>0 && entryTemplateFilter==templateFilters[i]);
   }

   CanvasControlVisualState markerState=HoldingToolbarControlState(PANEL_ACTION_MARKER_TOGGLE,false);
   DrawHoldingToolbarButton(CanvasPanelLayout.markerBadge,"",markerState,false);
   int markerPad=CanvasPanelMetrics.space10;
   int markerTextGap=CanvasPanelMetrics.space8;
   string markerLabel="提示挂单";
   string markerStatus=model.holding.markerEnabled?"开":"关";
   int markerLabelW=CanvasPanelRenderer.TextWidth(markerLabel,CanvasResolvedFont,CanvasPanelMetrics.fontTab);
   int markerStateW=CanvasPanelRenderer.TextWidth(markerStatus,CanvasResolvedFont,CanvasPanelMetrics.fontTab);
   int markerLabelX=CanvasPanelLayout.markerBadge.x+markerPad;
   int markerStateX=CanvasPanelLayout.markerBadge.x+CanvasPanelLayout.markerBadge.w-markerPad-markerStateW;
   int markerLabelAvailable=MathMax(markerStateX-markerTextGap-markerLabelX,1);
   uint markerLabelColor=(markerState==CONTROL_HOVER || markerState==CONTROL_PRESSED)?CanvasThemeText():CanvasThemeMuted();
   CanvasPanelRenderer.TextLeft(MakeUIRect(markerLabelX,CanvasPanelLayout.markerBadge.y,
                                           MathMin(markerLabelW,markerLabelAvailable),CanvasPanelLayout.markerBadge.h),
                                markerLabel,markerLabelColor,CanvasResolvedFont,CanvasPanelMetrics.fontTab);
   CanvasPanelRenderer.TextRight(MakeUIRect(markerStateX,CanvasPanelLayout.markerBadge.y,markerStateW,CanvasPanelLayout.markerBadge.h),
                                 markerStatus,model.holding.markerEnabled?CanvasThemeSuccess():CanvasThemeDim(),
                                 CanvasResolvedFont,CanvasPanelMetrics.fontTab);

   UIRect metricBand=MakeUIRect(CanvasPanelMetrics.margin,CanvasPanelLayout.metricCards[0].y,
                                CanvasPanelMetrics.width-CanvasPanelMetrics.margin*2,CanvasPanelLayout.metricCards[0].h);
   DrawRaisedCard(metricBand,SURFACE_CARD_RAISED,CanvasPanelMetrics.radiusContainer);
   string labels[4]={"浮盈","风险","持仓","保护"};
   string values[4];
   string captions[4];
   FilteredPositionSummary summary=model.holding.filteredSummary;
   values[0]=FormatMiniSignedProfit(summary.floatingProfit,2);
   values[1]=summary.riskSummary;
   values[2]=StringFormat("%d单",summary.managedCount);
   values[3]=StringFormat("SL %d/%d",summary.slCount,summary.managedCount);
   captions[0]="峰 "+FormatMiniSignedProfit(MathMax(summary.peakProfit,0.0),2);
   captions[1]=StringFormat("保护 %d/%d",summary.protectedCount,summary.managedCount);
   captions[2]=DoubleToString(summary.totalLots,2)+"手";
   captions[3]=StringFormat("TP %d/%d",summary.tpCount,summary.managedCount);
   uint metricColors[4];
   metricColors[0]=CanvasPnLColor(summary.floatingProfit);
   metricColors[1]=(summary.managedCount>0 && summary.slCount<summary.managedCount)?CanvasThemeDanger():
                   (summary.managedCount<=0?CanvasThemeMuted():(summary.protectedCount==summary.managedCount?CanvasThemeSuccess():CanvasThemeWarning()));
   metricColors[2]=CanvasPanelTheme.infoText;
   metricColors[3]=(summary.managedCount>0 && summary.slCount<summary.managedCount)?CanvasThemeDanger():
                   (summary.managedCount>0?CanvasThemeSuccess():CanvasThemeMuted());
   for(int i=0;i<4;i++)
   {
      RenderHoldingMetricCell(CanvasPanelLayout.metricCards[i],labels[i],values[i],captions[i],metricColors[i]);
      if(i<3) DrawSoftDivider(CanvasPanelLayout.metricCards[i].x+CanvasPanelLayout.metricCards[i].w-1,
                              CanvasPanelLayout.metricCards[i].y+CanvasPanelMetrics.space8,
                              CanvasPanelLayout.metricCards[i].x+CanvasPanelLayout.metricCards[i].w-1,
                              CanvasPanelLayout.metricCards[i].y+CanvasPanelLayout.metricCards[i].h-CanvasPanelMetrics.space8);
   }

   int total=ArraySize(model.holding.positions);
   int filteredTotal=ArraySize(model.holding.filteredPositionIndexes);
   int pageCount=MathMax((filteredTotal+2)/3,1);
   CanvasPanelState.positionPage=MathMax(0,MathMin(CanvasPanelState.positionPage,pageCount-1));
   string positionHeader=CanvasPanelState.positionFilter==持仓筛选_全部 ? StringFormat("持仓明细 · 全部 %d笔",total) :
                         StringFormat("持仓明细 · %s %d/%d笔",PositionFilterLabel(CanvasPanelState.positionFilter),filteredTotal,total);
   DrawSurface(CanvasPanelLayout.positionsHeader,SURFACE_TOOLBAR,CanvasPanelMetrics.radiusButton,true,false,true);
   CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.positionFilterScope,positionHeader,CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
   CanvasPanelRenderer.TextRight(CanvasPanelLayout.positionEntryTemplate,EntryTemplateStatusText(),CanvasThemeWarning(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption,CanvasPanelMetrics.space10);
   if(pageCount>1)
   {
      DrawCanvasButton(CanvasPanelLayout.positionPrev,"‹",CanvasPanelState.positionPage>0?CONTROL_NORMAL:CONTROL_DISABLED);
      CanvasPanelRenderer.TextCenter(CanvasPanelLayout.positionPageLabel,StringFormat("%d / %d",CanvasPanelState.positionPage+1,pageCount),CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      DrawCanvasButton(CanvasPanelLayout.positionNext,"›",CanvasPanelState.positionPage<pageCount-1?CONTROL_NORMAL:CONTROL_DISABLED);
   }

   if(filteredTotal<=0)
   {
      DrawRaisedCard(CanvasPanelLayout.emptyState,SURFACE_CONTAINER,CanvasPanelMetrics.radiusCard,UI_SEVERITY_INFO);
      string emptyTitle=CanvasPanelState.positionFilter==持仓筛选_全部 ? "当前没有受管持仓" :
                        "当前没有"+PositionFilterLabel(CanvasPanelState.positionFilter)+"配置的持仓";
      string emptyCaption="新持仓出现后将在此显示";
      CanvasPanelRenderer.TextLeft(CanvasPanelLayout.emptyTitle,emptyTitle,CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.emptyCaption,emptyCaption,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   }
   for(int slot=0;slot<3;slot++)
   {
      int filteredIndex=CanvasPanelState.positionPage*3+slot;
      if(filteredIndex>=filteredTotal) continue;
      int index=model.holding.filteredPositionIndexes[filteredIndex];
      if(index<0 || index>=total) continue;
      UIRect rect=CanvasPanelLayout.positionCards[slot];
      PositionPanelViewModel position=model.holding.positions[index];
      string direction=position.type==POSITION_TYPE_BUY?"BUY":"SELL";
      uint directionColor=CanvasDirectionColor(position.type==POSITION_TYPE_BUY);
      uint borderColor=!position.hasSL?CanvasThemeDanger():CanvasThemeBorder();
      DrawRaisedCard(rect,SURFACE_CARD,CanvasPanelMetrics.radiusCard);
      UIRect cardTop=MakeUIRect(rect.x+1,rect.y+1,rect.w-2,CanvasScalePx(32));
      CanvasPanelRenderer.FillRoundedRect(cardTop,MathMax(CanvasPanelMetrics.radiusCard-1,1),CanvasPanelTheme.cardRaised);
      DrawSoftDivider(rect.x+CanvasPanelMetrics.space10,rect.y+CanvasScalePx(33),rect.x+rect.w-CanvasPanelMetrics.space10,rect.y+CanvasScalePx(33));
      DrawColorEdge(rect,directionColor,CanvasScalePx(3),true);
      if(!position.hasSL)
         CanvasPanelRenderer.StrokeRoundedRect(rect,CanvasPanelMetrics.radiusCard,borderColor);
      CanvasPanelRenderer.TextLeft(CanvasPanelLayout.positionDirection[slot],direction,directionColor,CanvasResolvedFont,CanvasPanelMetrics.fontHeader);
      CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.positionIdentity[slot],StringFormat("%.2f 手 · #%I64u",position.volume,position.ticket),CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      UISeverity protectionSeverity=!position.hasSL?UI_SEVERITY_DANGER:(position.protectedPosition?UI_SEVERITY_SUCCESS:UI_SEVERITY_WARNING);
      DrawBadge(CanvasPanelLayout.positionProtection[slot],position.protectionText,protectionSeverity,BADGE_STATUS);
       CanvasPanelRenderer.TextRight(CanvasPanelLayout.positionProfit[slot],FormatMiniSignedProfit(position.profit,2),CanvasPnLColor(position.profit),CanvasResolvedFont,CanvasPanelMetrics.fontHeader);
       NewsStopPreview preview=model.holding.newsStopPreview;
       if(preview.visible && preview.priceValid && (position.type==POSITION_TYPE_BUY || position.type==POSITION_TYPE_SELL))
       {
          bool isBuy=(position.type==POSITION_TYPE_BUY);
          string previewText=StringFormat("%s Stop %s · 灾难SL %s",isBuy ? "Buy" : "Sell",
                                          DoubleToString(isBuy ? preview.buyStop : preview.sellStop,_Digits),
                                          DoubleToString(isBuy ? preview.buyDisasterSL : preview.sellDisasterSL,_Digits));
          CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.positionPrices[slot],previewText,CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
       }
       else
          RenderPositionPriceLine(CanvasPanelLayout.positionPrices[slot],position);
       RenderPositionMetaLine(CanvasPanelLayout.positionMeta[slot],position);
   }

   DrawInsetPanel(CanvasPanelLayout.supportRow,CanvasPanelMetrics.radiusButton);
   NewsStopPreview preview=model.holding.newsStopPreview;
   string supportLabels[5]={"R1","S1","SL","TP","点差"};
   string supportValues[5]={StringSubstr(model.holding.resistanceText,3),StringSubstr(model.holding.supportText,3),IntegerToString(summary.slCount)+"/"+IntegerToString(summary.managedCount),
                            IntegerToString(summary.tpCount)+"/"+IntegerToString(summary.managedCount),DoubleToString(model.spreadPoints,0)};
   if(preview.visible)
   {
      supportLabels[0]="B损";
      supportLabels[1]="S损";
      supportLabels[2]="最坏";
      supportLabels[3]="B保";
      supportLabels[4]="S保";
      supportValues[0]=preview.buyLossAvailable ? DoubleToString(preview.buyLossMoney,2) : "不可用";
      supportValues[1]=preview.sellLossAvailable ? DoubleToString(preview.sellLossMoney,2) : "不可用";
      supportValues[2]=(preview.buyLossAvailable && preview.sellLossAvailable) ? DoubleToString(preview.buyLossMoney+preview.sellLossMoney,2) : "不可用";
      supportValues[3]=preview.buyMarginAvailable ? DoubleToString(preview.buyMargin,2) : "不可用";
      supportValues[4]=preview.sellMarginAvailable ? DoubleToString(preview.sellMargin,2) : "不可用";
   }
   RenderInlineMetrics(CanvasPanelLayout.supportRow,supportLabels,supportValues);
   string holdingStatusText=model.holding.statusText;
   if(preview.visible)
      holdingStatusText=preview.status+" | 双边保证金 "+
                        ((preview.buyMarginAvailable && preview.sellMarginAvailable) ? DoubleToString(preview.buyMargin+preview.sellMargin,2) : "不可用");
   DrawSurface(CanvasPanelLayout.statusRow,SURFACE_TOOLBAR,CanvasPanelMetrics.radiusButton,true,false,true);
   DrawAccentEdge(CanvasPanelLayout.statusRow,model.holding.statusSeverity==UI_SEVERITY_MUTED?UI_SEVERITY_INFO:model.holding.statusSeverity,CanvasPanelMetrics.space2,true);
   DrawSoftDivider(CanvasPanelLayout.statusRow.x+CanvasPanelMetrics.space6,CanvasPanelLayout.statusRow.y,
                   CanvasPanelLayout.statusRow.x+CanvasPanelLayout.statusRow.w-CanvasPanelMetrics.space6,CanvasPanelLayout.statusRow.y);
   CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.statusRow,"状态："+holdingStatusText,CanvasSeverityColor(model.holding.statusSeverity),CanvasResolvedFont,CanvasPanelMetrics.fontCaption,0,CanvasPanelMetrics.space10);
   CanvasPanelRenderer.End();
   SyncCanvasNewsButtons(model.holding);
}

void ShowCanvasHoldingPanel(void)
{
   SyncCanvasStateFromLegacy();
   MarkCanvasPanelDirty(PANEL_DIRTY_DATA|PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER);
   RefreshCanvasPanelByDirtyFlags(false);
}

bool CanvasReviewCacheMatchesCurrent(void)
{
   return (CanvasReviewCacheValid &&
           CanvasReviewCacheKey.period==(int)当前统计周期 &&
           CanvasReviewCacheKey.filter==(int)当前统计筛选 &&
           CanvasReviewCacheKey.dayOffset==统计日期偏移天数 &&
           CanvasReviewCacheKey.weekOffset==统计周偏移周数 &&
           CanvasReviewCacheKey.monthOffset==统计月偏移月数 &&
           CanvasReviewCacheKey.tradeGeneration==CanvasStatsTradeGeneration &&
           CanvasReviewCacheKey.symbol==_Symbol);
}

bool CanvasReviewCacheMatchesStats(const LifecycleStats &stats)
{
   if(!CanvasReviewCacheMatchesCurrent() ||
      CanvasReviewCacheKey.serverStart!=stats.serverStart ||
      CanvasReviewCacheKey.serverEnd!=stats.serverEnd)
      return false;

   int count=ArraySize(CanvasReviewCache);
   for(int i=0;i<count;i++)
      if(CanvasReviewCache[i].closeTime<stats.serverStart || CanvasReviewCache[i].closeTime>=stats.serverEnd)
         return false;
   return true;
}

bool CanvasTrendCacheMatchesCurrent(void)
{
   return (CanvasTrendCacheValid &&
           CanvasTrendCacheKey.period==(int)当前统计周期 &&
           CanvasTrendCacheKey.filter==(int)当前统计筛选 &&
           CanvasTrendCacheKey.dayOffset==统计日期偏移天数 &&
           CanvasTrendCacheKey.weekOffset==统计周偏移周数 &&
           CanvasTrendCacheKey.monthOffset==统计月偏移月数 &&
           CanvasTrendCacheKey.tradeGeneration==CanvasStatsTradeGeneration &&
           CanvasTrendCacheKey.symbol==_Symbol);
}

bool CanvasTrendCacheMatchesStats(const LifecycleStats &stats)
{
   return (CanvasTrendCacheMatchesCurrent() &&
           CanvasTrendCacheKey.serverStart==stats.serverStart &&
           CanvasTrendCacheKey.serverEnd==stats.serverEnd);
}

void SaveCanvasReviewCacheKey(const LifecycleStats &stats)
{
   CanvasReviewCacheKey.period=(int)当前统计周期;
   CanvasReviewCacheKey.filter=(int)当前统计筛选;
   CanvasReviewCacheKey.dayOffset=统计日期偏移天数;
   CanvasReviewCacheKey.weekOffset=统计周偏移周数;
   CanvasReviewCacheKey.monthOffset=统计月偏移月数;
   CanvasReviewCacheKey.tradeGeneration=CanvasStatsTradeGeneration;
   CanvasReviewCacheKey.symbol=_Symbol;
   CanvasReviewCacheKey.serverStart=stats.serverStart;
   CanvasReviewCacheKey.serverEnd=stats.serverEnd;
}

void SaveCanvasTrendCacheKey(const LifecycleStats &stats)
{
   CanvasTrendCacheKey.period=(int)当前统计周期;
   CanvasTrendCacheKey.filter=(int)当前统计筛选;
   CanvasTrendCacheKey.dayOffset=统计日期偏移天数;
   CanvasTrendCacheKey.weekOffset=统计周偏移周数;
   CanvasTrendCacheKey.monthOffset=统计月偏移月数;
   CanvasTrendCacheKey.tradeGeneration=CanvasStatsTradeGeneration;
   CanvasTrendCacheKey.symbol=_Symbol;
   CanvasTrendCacheKey.serverStart=stats.serverStart;
   CanvasTrendCacheKey.serverEnd=stats.serverEnd;
}

void ClearStatsTrendViewModel(StatsTrendViewModel &trend)
{
   ArrayResize(trend.points,0);
   trend.cumulativeProfit=0.0;
   trend.currentDrawdown=0.0;
   trend.peakProfit=0.0;
   trend.maxDrawdown=0.0;
   trend.recentProfit=0.0;
   trend.recentCount=0;
   trend.hasData=false;
   trend.statusText="暂无走势数据";
}

void CopyStatsTrendViewModel(StatsTrendViewModel &target, const StatsTrendViewModel &source)
{
   ArrayResize(target.points,0);
   ArrayCopy(target.points,source.points);
   target.cumulativeProfit=source.cumulativeProfit;
   target.currentDrawdown=source.currentDrawdown;
   target.peakProfit=source.peakProfit;
   target.maxDrawdown=source.maxDrawdown;
   target.recentProfit=source.recentProfit;
   target.recentCount=source.recentCount;
   target.hasData=source.hasData;
   target.statusText=source.statusText;
}

int FindCanvasReviewIndexByPositionId(const LifecycleReviewItem &reviews[], ulong positionId)
{
   for(int i=0;i<ArraySize(reviews);i++)
      if(reviews[i].positionId==positionId) return i;
   return -1;
}

bool CanvasSelectedTrendReviewAvailable(void)
{
   if(!CanvasPanelState.trendSelectionValid) return false;
   int pointIndex=CanvasPanelState.selectedTrendPointIndex;
   int pointCount=ArraySize(CanvasPanelModel.stats.trend.points);
   if(pointIndex<0 || pointIndex>=pointCount) return false;
   TrendTradePoint point=CanvasPanelModel.stats.trend.points[pointIndex];
   if(point.positionId<=0 || !point.reviewAvailable) return false;
   int reviewCount=ArraySize(CanvasPanelModel.stats.reviews);
   return (point.reviewIndex>=0 && point.reviewIndex<reviewCount &&
           CanvasPanelModel.stats.reviews[point.reviewIndex].positionId==point.positionId);
}

void BuildCanvasTrendViewModel(const LifecycleStats &stats, const LifecycleReviewItem &reviews[], StatsTrendViewModel &trend)
{
   ClearStatsTrendViewModel(trend);
   LifecycleTrendItem items[];
   GetCurrentLifecycleTrendItems(stats,items);
   int count=ArraySize(items);
   if(count<=0) return;

   ArrayResize(trend.points,count);
   double cumulative=0.0;
   double peak=0.0;
   double maxDrawdown=0.0;
   for(int i=0;i<count;i++)
   {
      cumulative+=items[i].netProfit;
      peak=MathMax(peak,cumulative);
      double drawdown=cumulative-peak;
      maxDrawdown=MathMin(maxDrawdown,drawdown);
      trend.points[i].positionId=items[i].positionId;
      trend.points[i].closeTime=items[i].closeTime;
      trend.points[i].netProfit=items[i].netProfit;
      trend.points[i].cumulativeProfit=cumulative;
      trend.points[i].peakProfit=peak;
      trend.points[i].drawdown=drawdown;
      trend.points[i].reviewIndex=FindCanvasReviewIndexByPositionId(reviews,items[i].positionId);
      trend.points[i].reviewAvailable=(trend.points[i].reviewIndex>=0);
   }
   trend.cumulativeProfit=cumulative;
   trend.currentDrawdown=trend.points[count-1].drawdown;
   trend.peakProfit=peak;
   trend.maxDrawdown=maxDrawdown;
   trend.recentCount=MathMin(10,count);
   for(int i=count-trend.recentCount;i<count;i++) trend.recentProfit+=trend.points[i].netProfit;
   trend.hasData=true;
   trend.statusText=trend.currentDrawdown<0.0?
                    ("当前处于回撤中 · 距离区间收益高点 "+DoubleToString(MathAbs(trend.currentDrawdown),2)):
                    "当前位于区间收益高点";
}

void ValidateCanvasTrendSelection(const StatsTrendViewModel &trend)
{
   int count=ArraySize(trend.points);
   if(count<=0)
   {
      CanvasPanelState.selectedTrendPointIndex=-1;
      CanvasPanelState.trendSelectionValid=false;
      CanvasPanelState.trendSelectionMessage="";
      CanvasPanelState.trendSelectionGeneration=CanvasStatsTradeGeneration;
      return;
   }
   bool generationChanged=(CanvasPanelState.trendSelectionGeneration!=CanvasStatsTradeGeneration);
   bool indexInvalid=(CanvasPanelState.selectedTrendPointIndex<0 || CanvasPanelState.selectedTrendPointIndex>=count);
   if(generationChanged || !CanvasPanelState.trendSelectionValid || indexInvalid)
   {
      CanvasPanelState.selectedTrendPointIndex=count-1;
      CanvasPanelState.trendSelectionValid=true;
      CanvasPanelState.trendSelectionMessage="";
   }
   CanvasPanelState.trendSelectionGeneration=CanvasStatsTradeGeneration;
}

void EnsureCanvasReviewItemsForStats(const LifecycleStats &stats, LifecycleReviewItem &reviews[])
{
   if(CanvasReviewCacheMatchesStats(stats))
   {
      CopyLifecycleReviewItemsExact(reviews,CanvasReviewCache);
      return;
   }
   ulong reviewPerfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
   GetCurrentLifecycleReviewItems(stats,reviews);
   CopyLifecycleReviewItemsExact(CanvasReviewCache,reviews);
   SaveCanvasReviewCacheKey(stats);
   CanvasReviewCacheValid=true;
   CanvasUIPerfStage("Build review items",reviewPerfStart,20000);
}

void BuildStatsPanelViewModel(PanelViewModel &model, bool includeReviews=false, bool includeTrend=false)
{
   ulong perfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
   GetCurrentLifecycleStats(model.stats.stats);
   model.stats.periodText=LifecycleStatsPeriodText();
   model.stats.filterText=LifecycleStatsFilterText();
   model.stats.rangeText=FormatBJDate(model.stats.stats.bjDate);
   if(当前统计周期==统计_周) model.stats.rangeText+="-"+FormatBJDate(model.stats.stats.bjDate+4*86400);
   else if(当前统计周期==统计_月) model.stats.rangeText+="-"+FormatBJDate(AddBJMonths(model.stats.stats.bjDate,1)-86400);
   color ignoredColor;
   GetLifecycleStatsInsight(model.stats.stats,model.stats.insight,ignoredColor);
   model.stats.resultSeverity=model.stats.stats.netProfit>0.0?UI_SEVERITY_SUCCESS:
                              (model.stats.stats.netProfit<0.0?UI_SEVERITY_DANGER:UI_SEVERITY_MUTED);
   if(includeReviews)
      EnsureCanvasReviewItemsForStats(model.stats.stats,model.stats.reviews);
   else if(CanvasReviewCacheMatchesStats(model.stats.stats))
      CopyLifecycleReviewItemsExact(model.stats.reviews,CanvasReviewCache);
   else
      ArrayResize(model.stats.reviews,0);
   if(includeTrend)
   {
      if(CanvasTrendCacheMatchesStats(model.stats.stats))
         CopyStatsTrendViewModel(model.stats.trend,CanvasTrendCache);
      else
      {
         BuildCanvasTrendViewModel(model.stats.stats,model.stats.reviews,model.stats.trend);
         CopyStatsTrendViewModel(CanvasTrendCache,model.stats.trend);
         SaveCanvasTrendCacheKey(model.stats.stats);
         CanvasTrendCacheValid=true;
      }
   }
   else if(CanvasTrendCacheMatchesStats(model.stats.stats))
      CopyStatsTrendViewModel(model.stats.trend,CanvasTrendCache);
   else
      ClearStatsTrendViewModel(model.stats.trend);
   model.statusText=lastStatus;
   CanvasUIPerfStage("Build stats model",perfStart,20000);
}

int StatsCanvasLogicalHeight(const StatsPanelViewModel &model)
{
   if(CanvasPanelState.statsDetail==统计详情_复盘)
      return ArraySize(model.reviews)>0?660:308;
   if(CanvasPanelState.statsDetail==统计详情_总览) return 474;
   if(CanvasPanelState.statsDetail==统计详情_策略) return 506;
   if(CanvasPanelState.statsDetail==统计详情_走势) return model.trend.hasData?614:446;
   if(CanvasPanelState.statsDetail==统计详情_管理) return 426;
   return 416;
}

void CalculateStatsPanelLayout(void)
{
   int w=CanvasPanelMetrics.width;
   int h=CanvasPanelMetrics.height;
   int m=CanvasPanelMetrics.margin;
   int header=CanvasPanelMetrics.headerHeight;
   int gap6=CanvasPanelMetrics.space6;
   int gap8=CanvasPanelMetrics.space8;
   CanvasPanelLayout.panel=MakeUIRect(0,0,w,h);
   CanvasPanelLayout.header=MakeUIRect(0,0,w,header);
   CalculateCanvasHeaderLayout();

   int detailY=header+gap6;
   int detailGap=CanvasPanelMetrics.space6;
   int detailW=(w-m*2-detailGap*(CANVAS_STATS_TAB_COUNT-1))/CANVAS_STATS_TAB_COUNT;
   for(int i=0;i<CANVAS_STATS_TAB_COUNT;i++)
      CanvasPanelLayout.statsDetailTabs[i]=MakeUIRect(m+i*(detailW+detailGap),detailY,detailW,CanvasScalePx(34));
   CanvasPanelLayout.statsDetailTabs[4]=MakeUIRect(0,0,0,0);

   int toolbarY=detailY+CanvasScalePx(34)+gap8;
   int toolbarH=CanvasScalePx(36);
   int toolbarGap=CanvasPanelMetrics.space8;
   CanvasPanelLayout.statsToolbar=MakeUIRect(m,toolbarY,w-m*2,toolbarH);

   int selectorW=CanvasScalePx(132);
   int filterW=CanvasScalePx(104);
   CanvasPanelLayout.statsPeriodSelector=MakeUIRect(m,toolbarY,selectorW,toolbarH);
   CanvasPanelLayout.statsFilterTabs[0]=MakeUIRect(w-m-filterW,toolbarY,filterW,toolbarH);
   for(int i=1;i<5;i++) CanvasPanelLayout.statsFilterTabs[i]=MakeUIRect(0,0,0,0);

   int selectorSegmentW=selectorW/3;
   int selectorX=CanvasPanelLayout.statsPeriodSelector.x;
   for(int i=0;i<3;i++)
   {
      int segmentX=selectorX+i*selectorSegmentW;
      int segmentW=(i==2)?selectorX+selectorW-segmentX:selectorSegmentW;
      CanvasPanelLayout.statsPeriodTabs[i]=MakeUIRect(segmentX,toolbarY,segmentW,toolbarH);
   }

   int dateX=CanvasPanelLayout.statsPeriodSelector.x+CanvasPanelLayout.statsPeriodSelector.w+toolbarGap;
   int dateRight=CanvasPanelLayout.statsFilterTabs[0].x-toolbarGap;
   CanvasPanelLayout.statsDateNavigator=MakeUIRect(dateX,toolbarY,MathMax(dateRight-dateX,CanvasScalePx(184)),toolbarH);
   int arrowW=CanvasScalePx(42);
   CanvasPanelLayout.statsPeriodNav[0]=MakeUIRect(dateX,toolbarY,arrowW,toolbarH);
   CanvasPanelLayout.statsPeriodNav[2]=MakeUIRect(dateX+CanvasPanelLayout.statsDateNavigator.w-arrowW,toolbarY,arrowW,toolbarH);
   CanvasPanelLayout.statsPeriodNav[1]=MakeUIRect(dateX+arrowW,toolbarY,
                                                MathMax(CanvasPanelLayout.statsDateNavigator.w-arrowW*2,CanvasScalePx(100)),toolbarH);

   int contentY=toolbarY+toolbarH+CanvasPanelMetrics.space10;
   int footerY=h-CanvasScalePx(38);
   CanvasPanelLayout.content=MakeUIRect(m,contentY,w-m*2,footerY-contentY-gap8);
   CanvasPanelLayout.footer=MakeUIRect(m,footerY,w-m*2,CanvasScalePx(30));
   CanvasPanelLayout.statsFooterText=CanvasPanelLayout.footer;

   if(CanvasPanelState.statsDetail==统计详情_总览)
   {
      int summaryH=CanvasScalePx(82);
      int summaryGap=CanvasPanelMetrics.space8;
      int summaryAvailable=CanvasPanelLayout.content.w-summaryGap*3;
      int summaryW=summaryAvailable/4;
      for(int i=0;i<4;i++)
      {
         int x=CanvasPanelLayout.content.x+i*(summaryW+summaryGap);
         int width=(i==3)?CanvasPanelLayout.content.x+CanvasPanelLayout.content.w-x:summaryW;
         CanvasPanelLayout.statsSummary[i]=MakeUIRect(x,CanvasPanelLayout.content.y,width,summaryH);
      }
      int rowsY=CanvasPanelLayout.content.y+summaryH+gap8;
      int columnGap=CanvasScalePx(14);
      int columnW=(CanvasPanelLayout.content.w-columnGap)/2;
      int rowH=CanvasScalePx(29);
      int rowsH=rowH*7;
      CanvasPanelLayout.statsLeftColumn=MakeUIRect(CanvasPanelLayout.content.x,rowsY,columnW,rowsH);
      CanvasPanelLayout.statsRightColumn=MakeUIRect(CanvasPanelLayout.content.x+columnW+columnGap,rowsY,columnW,rowsH);
      for(int i=0;i<7;i++)
      {
         CanvasPanelLayout.statsLeftRows[i]=MakeUIRect(CanvasPanelLayout.statsLeftColumn.x,rowsY+i*rowH,columnW,rowH);
         CanvasPanelLayout.statsRightRows[i]=MakeUIRect(CanvasPanelLayout.statsRightColumn.x,rowsY+i*rowH,columnW,rowH);
      }
      CanvasPanelLayout.statsNote=MakeUIRect(0,0,0,0);
   }
   else if(CanvasPanelState.statsDetail==统计详情_策略)
   {
      int y=CanvasPanelLayout.content.y;
      int tableHeaderH=CanvasScalePx(26);
      int tableRowH=CanvasScalePx(27);
      CanvasPanelLayout.statsTableHeader=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,tableHeaderH);
      y+=tableHeaderH;
      for(int i=0;i<4;i++) CanvasPanelLayout.statsTableRows[i]=MakeUIRect(CanvasPanelLayout.content.x,y+i*tableRowH,CanvasPanelLayout.content.w,tableRowH);
      y+=tableRowH*4+gap6;
      CanvasPanelLayout.statsNote=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,tableHeaderH);
      y+=tableHeaderH;
      for(int i=0;i<4;i++) CanvasPanelLayout.statsTableRows[4+i]=MakeUIRect(CanvasPanelLayout.content.x,y+i*tableRowH,CanvasPanelLayout.content.w,tableRowH);
      y+=tableRowH*4+CanvasPanelMetrics.space4;
      int remaining=CanvasPanelLayout.content.y+CanvasPanelLayout.content.h-y;
      int conclusionH=MathMin(CanvasScalePx(24),MathMax(remaining/2,CanvasScalePx(18)));
      CanvasPanelLayout.statsPerformanceConclusion=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,conclusionH);
      y+=conclusionH;
      CanvasPanelLayout.statsPerformanceSampleNote=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,
                                                               MathMax(CanvasPanelLayout.content.y+CanvasPanelLayout.content.h-y,CanvasScalePx(18)));
   }
   else if(CanvasPanelState.statsDetail==统计详情_管理)
   {
      int columnGap=CanvasScalePx(14);
      int columnW=(CanvasPanelLayout.content.w-columnGap)/2;
      int rowH=CanvasScalePx(30);
      int rowsH=rowH*5;
      CanvasPanelLayout.statsLeftColumn=MakeUIRect(CanvasPanelLayout.content.x,CanvasPanelLayout.content.y,columnW,rowsH);
      CanvasPanelLayout.statsRightColumn=MakeUIRect(CanvasPanelLayout.content.x+columnW+columnGap,CanvasPanelLayout.content.y,columnW,rowsH);
      for(int i=0;i<5;i++)
      {
         CanvasPanelLayout.statsLeftRows[i]=MakeUIRect(CanvasPanelLayout.statsLeftColumn.x,CanvasPanelLayout.content.y+i*rowH,columnW,rowH);
         CanvasPanelLayout.statsRightRows[i]=MakeUIRect(CanvasPanelLayout.statsRightColumn.x,CanvasPanelLayout.content.y+i*rowH,columnW,rowH);
      }
      CanvasPanelLayout.statsNote=MakeUIRect(CanvasPanelLayout.content.x,CanvasPanelLayout.content.y+rowsH+gap8,CanvasPanelLayout.content.w,MathMax(CanvasPanelLayout.content.h-rowsH-gap8,CanvasScalePx(54)));
   }
   else if(CanvasPanelState.statsDetail==统计详情_执行)
   {
      int y=CanvasPanelLayout.content.y;
      int tableHeaderH=CanvasScalePx(28);
      int tableRowH=CanvasScalePx(29);
      CanvasPanelLayout.statsTableHeader=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,tableHeaderH);
      y+=tableHeaderH;
      for(int i=0;i<4;i++) CanvasPanelLayout.statsTableRows[i]=MakeUIRect(CanvasPanelLayout.content.x,y+i*tableRowH,CanvasPanelLayout.content.w,tableRowH);
      y+=tableRowH*4+gap8;
      CanvasPanelLayout.statsNote=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,MathMax(CanvasPanelLayout.content.y+CanvasPanelLayout.content.h-y,CanvasScalePx(64)));
   }
   else if(CanvasPanelState.statsDetail==统计详情_走势)
   {
      int y=CanvasPanelLayout.content.y;
      int summaryH=CanvasScalePx(70);
      int summaryGap=CanvasPanelMetrics.space8;
      int summaryAvailable=CanvasPanelLayout.content.w-summaryGap*3;
      int summaryW=summaryAvailable/4;
      for(int i=0;i<4;i++)
      {
         int x=CanvasPanelLayout.content.x+i*(summaryW+summaryGap);
         int width=(i==3)?CanvasPanelLayout.content.x+CanvasPanelLayout.content.w-x:summaryW;
         CanvasPanelLayout.trendSummary[i]=MakeUIRect(x,y,width,summaryH);
      }
      y+=summaryH+gap8;
      if(CanvasPanelModel.stats.trend.hasData)
      {
         int curveH=CanvasScalePx(152);
         CanvasPanelLayout.trendCurveCard=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,curveH);
         CanvasPanelLayout.trendCurveTitle=MakeUIRect(CanvasPanelLayout.trendCurveCard.x+CanvasPanelMetrics.space12,y+CanvasPanelMetrics.space4,
                                                     CanvasPanelLayout.trendCurveCard.w-CanvasPanelMetrics.space12*2,CanvasScalePx(24));
         CanvasPanelLayout.trendCurvePlot=MakeUIRect(CanvasPanelLayout.trendCurveCard.x+CanvasPanelMetrics.space10,y+CanvasScalePx(30),
                                                    CanvasPanelLayout.trendCurveCard.w-CanvasPanelMetrics.space10*2,curveH-CanvasScalePx(38));
         int axisW=CanvasScalePx(60);
         int axisGap=CanvasPanelMetrics.space8;
         int rightGap=CanvasPanelMetrics.space8;
         int xAxisH=CanvasScalePx(20);
         int plotTopGap=CanvasPanelMetrics.space6;
         CanvasPanelLayout.trendCurvePlotInner=MakeUIRect(CanvasPanelLayout.trendCurvePlot.x+axisW+axisGap,
                                                         CanvasPanelLayout.trendCurvePlot.y+plotTopGap,
                                                         CanvasPanelLayout.trendCurvePlot.w-axisW-axisGap-rightGap,
                                                         CanvasPanelLayout.trendCurvePlot.h-xAxisH-plotTopGap);
         CanvasPanelLayout.trendCurveAxisY=MakeUIRect(CanvasPanelLayout.trendCurvePlot.x,CanvasPanelLayout.trendCurvePlotInner.y,
                                                     axisW,CanvasPanelLayout.trendCurvePlotInner.h);
         CanvasPanelLayout.trendCurveAxisX=MakeUIRect(CanvasPanelLayout.trendCurvePlotInner.x,
                                                     CanvasPanelLayout.trendCurvePlotInner.y+CanvasPanelLayout.trendCurvePlotInner.h,
                                                     CanvasPanelLayout.trendCurvePlotInner.w,xAxisH);
         y+=curveH+gap8;
         int barsH=CanvasScalePx(132);
         CanvasPanelLayout.trendBarsCard=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,barsH);
         CanvasPanelLayout.trendBarsTitle=MakeUIRect(CanvasPanelLayout.trendBarsCard.x+CanvasPanelMetrics.space12,y+CanvasPanelMetrics.space4,
                                                    CanvasPanelLayout.trendBarsCard.w-CanvasPanelMetrics.space12*2,CanvasScalePx(24));
         CanvasPanelLayout.trendBarsPlot=MakeUIRect(CanvasPanelLayout.trendBarsCard.x+CanvasPanelMetrics.space10,y+CanvasScalePx(30),
                                                   CanvasPanelLayout.trendBarsCard.w-CanvasPanelMetrics.space10*2,barsH-CanvasScalePx(38));
         CanvasPanelLayout.trendBarsPlotInner=MakeUIRect(CanvasPanelLayout.trendBarsPlot.x+axisW+axisGap,
                                                        CanvasPanelLayout.trendBarsPlot.y+plotTopGap,
                                                        CanvasPanelLayout.trendBarsPlot.w-axisW-axisGap-rightGap,
                                                        CanvasPanelLayout.trendBarsPlot.h-xAxisH-plotTopGap);
         CanvasPanelLayout.trendBarsAxisY=MakeUIRect(CanvasPanelLayout.trendBarsPlot.x,CanvasPanelLayout.trendBarsPlotInner.y,
                                                    axisW,CanvasPanelLayout.trendBarsPlotInner.h);
         CanvasPanelLayout.trendBarsAxisX=MakeUIRect(CanvasPanelLayout.trendBarsPlotInner.x,
                                                    CanvasPanelLayout.trendBarsPlotInner.y+CanvasPanelLayout.trendBarsPlotInner.h,
                                                    CanvasPanelLayout.trendBarsPlotInner.w,xAxisH);
         y+=barsH+gap8;
         CanvasPanelLayout.trendEmptyState=MakeUIRect(0,0,0,0);
      }
      else
      {
         int emptyH=CanvasScalePx(120);
         CanvasPanelLayout.trendEmptyState=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,emptyH);
         y+=emptyH+gap8;
      }
      int selectionH=CanvasScalePx(56);
      CanvasPanelLayout.trendSelectionPanel=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,selectionH);
      CanvasPanelLayout.trendStatus=CanvasPanelLayout.trendSelectionPanel;
      int reviewButtonW=CanvasScalePx(92);
      CanvasPanelLayout.trendReviewButton=MakeUIRect(CanvasPanelLayout.trendSelectionPanel.x+CanvasPanelLayout.trendSelectionPanel.w-reviewButtonW-CanvasPanelMetrics.space10,
                                                    y+CanvasScalePx(10),reviewButtonW,CanvasScalePx(36));
      int selectionTextW=CanvasPanelLayout.trendReviewButton.x-CanvasPanelLayout.trendSelectionPanel.x-CanvasPanelMetrics.space16;
      CanvasPanelLayout.trendSelectionLine1=MakeUIRect(CanvasPanelLayout.trendSelectionPanel.x+CanvasPanelMetrics.space10,y+CanvasPanelMetrics.space4,
                                                      selectionTextW,CanvasScalePx(23));
      CanvasPanelLayout.trendSelectionLine2=MakeUIRect(CanvasPanelLayout.trendSelectionPanel.x+CanvasPanelMetrics.space10,y+CanvasScalePx(28),
                                                      selectionTextW,CanvasScalePx(23));
   }
   else
   {
      int y=CanvasPanelLayout.content.y;
      int reviewNavH=CanvasScalePx(34);
      CanvasPanelLayout.reviewNav=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,reviewNavH);
      CanvasPanelLayout.reviewNext=MakeUIRect(CanvasPanelLayout.content.x+CanvasPanelLayout.content.w-CanvasScalePx(82),y+CanvasScalePx(1),CanvasScalePx(82),CanvasScalePx(32));
      CanvasPanelLayout.reviewPrev=MakeUIRect(CanvasPanelLayout.reviewNext.x-CanvasScalePx(90),y+CanvasScalePx(1),CanvasScalePx(82),CanvasScalePx(32));
      y+=reviewNavH+gap8;
      int reviewCount=ArraySize(CanvasPanelModel.stats.reviews);
      if(reviewCount<=0)
      {
         int emptyH=CanvasScalePx(82);
         CanvasPanelLayout.reviewSummary=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,emptyH);
         int emptyTitleH=CanvasScalePx(28);
         int emptyCaptionH=CanvasScalePx(26);
         int emptyTextGap=CanvasScalePx(2);
         int emptyTextY=y+(emptyH-emptyTitleH-emptyTextGap-emptyCaptionH)/2;
         CanvasPanelLayout.reviewSummaryRows[0]=MakeUIRect(CanvasPanelLayout.reviewSummary.x+CanvasPanelMetrics.space12,emptyTextY,CanvasPanelLayout.reviewSummary.w-CanvasPanelMetrics.space12*2,emptyTitleH);
         CanvasPanelLayout.reviewSummaryRows[1]=MakeUIRect(CanvasPanelLayout.reviewSummary.x+CanvasPanelMetrics.space12,emptyTextY+emptyTitleH+emptyTextGap,CanvasPanelLayout.reviewSummary.w-CanvasPanelMetrics.space12*2,emptyCaptionH);
         CanvasPanelLayout.reviewHint=MakeUIRect(0,0,0,0);
      }
      else
      {
         int summaryBlockH=CanvasScalePx(74);
         CanvasPanelLayout.reviewSummary=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,summaryBlockH);
         int summaryX=CanvasPanelLayout.reviewSummary.x+CanvasPanelMetrics.space12;
         int summaryTop=y+CanvasPanelMetrics.space8;
         int summaryH=CanvasScalePx(30);
         int summaryGap=CanvasPanelMetrics.space6;
         int directionW=CanvasScalePx(42);
         int volumeW=CanvasScalePx(58);
         int netLabelW=CanvasScalePx(48);
         int netValueW=CanvasScalePx(86);
         int rW=CanvasScalePx(78);
         CanvasPanelLayout.reviewDirection=MakeUIRect(summaryX,summaryTop,directionW,summaryH);
         summaryX+=directionW+summaryGap;
         CanvasPanelLayout.reviewVolume=MakeUIRect(summaryX,summaryTop,volumeW,summaryH);
         summaryX+=volumeW+summaryGap;
         CanvasPanelLayout.reviewNetLabel=MakeUIRect(summaryX,summaryTop,netLabelW,summaryH);
         summaryX+=netLabelW;
         CanvasPanelLayout.reviewNetValue=MakeUIRect(summaryX,summaryTop,netValueW,summaryH);
         summaryX+=netValueW+summaryGap;
         CanvasPanelLayout.reviewRValue=MakeUIRect(summaryX,summaryTop,rW,summaryH);
         summaryX+=rW+summaryGap;
         int summaryRight=CanvasPanelLayout.reviewSummary.x+CanvasPanelLayout.reviewSummary.w-CanvasPanelMetrics.space12;
         CanvasPanelLayout.reviewDuration=MakeUIRect(summaryX,summaryTop,MathMax(summaryRight-summaryX,1),summaryH);
         CanvasPanelLayout.reviewTimeRange=MakeUIRect(CanvasPanelLayout.reviewSummary.x+CanvasPanelMetrics.space12,y+CanvasScalePx(46),CanvasPanelLayout.reviewSummary.w-CanvasPanelMetrics.space12*2,CanvasScalePx(22));
         y+=summaryBlockH+gap8;
         int columnGap=CanvasScalePx(10);
         int columnW=(CanvasPanelLayout.content.w-columnGap)/2;
         int sectionH=CanvasScalePx(140);
         int titleH=CanvasScalePx(28);
         CanvasPanelLayout.reviewPrice=MakeUIRect(CanvasPanelLayout.content.x,y,columnW,sectionH);
         CanvasPanelLayout.reviewClassification=MakeUIRect(CanvasPanelLayout.content.x+columnW+columnGap,y,columnW,sectionH);
         CanvasPanelLayout.reviewPriceTitle=MakeUIRect(CanvasPanelLayout.reviewPrice.x+CanvasPanelMetrics.space10,y+CanvasScalePx(2),CanvasPanelLayout.reviewPrice.w-CanvasPanelMetrics.space10*2,titleH);
         CanvasPanelLayout.reviewClassificationTitle=MakeUIRect(CanvasPanelLayout.reviewClassification.x+CanvasPanelMetrics.space10,y+CanvasScalePx(2),CanvasPanelLayout.reviewClassification.w-CanvasPanelMetrics.space10*2,titleH);
         for(int i=0;i<4;i++)
         {
            CanvasPanelLayout.reviewPriceRows[i]=MakeUIRect(CanvasPanelLayout.reviewPrice.x+CanvasPanelMetrics.space10,y+titleH+i*CanvasScalePx(28),columnW-CanvasPanelMetrics.space10*2,CanvasScalePx(28));
            CanvasPanelLayout.reviewClassRows[i]=MakeUIRect(CanvasPanelLayout.reviewClassification.x+CanvasPanelMetrics.space10,y+titleH+i*CanvasScalePx(28),columnW-CanvasPanelMetrics.space10*2,CanvasScalePx(28));
         }
         y+=sectionH+gap8;
         int managementH=CanvasScalePx(140);
         CanvasPanelLayout.reviewManagement=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,managementH);
         CanvasPanelLayout.reviewManagementTitle=MakeUIRect(CanvasPanelLayout.reviewManagement.x+CanvasPanelMetrics.space10,y+CanvasScalePx(2),CanvasPanelLayout.reviewManagement.w-CanvasPanelMetrics.space10*2,titleH);
         int manageBodyX=CanvasPanelLayout.reviewManagement.x+CanvasPanelMetrics.space10;
         int manageBodyY=y+titleH;
         int manageBodyW=CanvasPanelLayout.reviewManagement.w-CanvasPanelMetrics.space10*2;
         int manageGap=CanvasScalePx(10);
         int manageHalf=(manageBodyW-manageGap)/2;
         int manageRowH=CanvasScalePx(28);
         for(int row=0;row<4;row++)
         {
            CanvasPanelLayout.reviewManageCells[row*2]=MakeUIRect(manageBodyX,manageBodyY+row*manageRowH,manageHalf,manageRowH);
            CanvasPanelLayout.reviewManageCells[row*2+1]=MakeUIRect(manageBodyX+manageHalf+manageGap,manageBodyY+row*manageRowH,manageHalf,manageRowH);
         }
         y+=managementH+gap8;
         CanvasPanelLayout.reviewHint=MakeUIRect(CanvasPanelLayout.content.x,y,CanvasPanelLayout.content.w,MathMax(CanvasPanelLayout.content.y+CanvasPanelLayout.content.h-y,CanvasScalePx(60)));
      }
   }
   当前面板宽度=w;
   当前面板高度=h;
}

void BuildStatsHitRegions(void)
{
   ArrayResize(CanvasPanelHitRegions,0);
   AddCanvasHit(CanvasPanelLayout.mainTabs[0],PANEL_ACTION_PAGE_HOLDING);
   AddCanvasHit(CanvasPanelLayout.mainTabs[1],PANEL_ACTION_PAGE_STATS);
   AddCanvasHit(CanvasPanelLayout.mainTabs[3],PANEL_ACTION_MODE_MINI);
   AddCanvasHit(CanvasPanelLayout.mainTabs[4],PANEL_ACTION_MODE_HIDE);
   PanelAction details[4]={PANEL_ACTION_DETAIL_OVERVIEW,PANEL_ACTION_DETAIL_STRATEGY,PANEL_ACTION_DETAIL_TREND,PANEL_ACTION_DETAIL_REVIEW};
   PanelAction periods[3]={PANEL_ACTION_STATS_DAY,PANEL_ACTION_STATS_WEEK,PANEL_ACTION_STATS_MONTH};
   PanelAction navs[3]={PANEL_ACTION_PERIOD_PREV,PANEL_ACTION_PERIOD_CURRENT,PANEL_ACTION_PERIOD_NEXT};
   for(int i=0;i<CANVAS_STATS_TAB_COUNT;i++) AddCanvasHit(CanvasPanelLayout.statsDetailTabs[i],details[i]);
   for(int i=0;i<3;i++) AddCanvasHit(CanvasPanelLayout.statsPeriodTabs[i],periods[i]);
   for(int i=0;i<3;i++) AddCanvasHit(CanvasPanelLayout.statsPeriodNav[i],navs[i]);
   AddCanvasHit(CanvasPanelLayout.statsFilterTabs[0],PANEL_ACTION_FILTER_NEXT);
   if(CanvasPanelState.statsDetail==统计详情_总览)
   {
      LifecycleStats stats=CanvasPanelModel.stats.stats;
      AddCanvasHit(CanvasPanelLayout.statsSummary[2],PANEL_ACTION_OVERVIEW_BEST_REVIEW,
                   stats.bestTradeValid && stats.bestTradePositionId>0);
      AddCanvasHit(CanvasPanelLayout.statsSummary[3],PANEL_ACTION_OVERVIEW_WORST_REVIEW,
                   stats.worstTradeValid && stats.worstTradePositionId>0);
   }
   if(CanvasPanelState.statsDetail==统计详情_复盘)
   {
      int reviewCount=ArraySize(CanvasPanelModel.stats.reviews);
      if(reviewCount>0)
      {
         AddCanvasHit(CanvasPanelLayout.reviewPrev,PANEL_ACTION_REVIEW_PREV,CanvasPanelState.reviewIndex<reviewCount-1);
         AddCanvasHit(CanvasPanelLayout.reviewNext,PANEL_ACTION_REVIEW_NEXT,CanvasPanelState.reviewIndex>0);
      }
   }
   else if(CanvasPanelState.statsDetail==统计详情_走势)
   {
      int pointCount=ArraySize(CanvasPanelModel.stats.trend.points);
      if(CanvasPanelModel.stats.trend.hasData && pointCount>0)
      {
         AddCanvasHit(CanvasPanelLayout.trendCurvePlotInner,PANEL_ACTION_TREND_SELECT);
         AddCanvasHit(CanvasPanelLayout.trendBarsPlotInner,PANEL_ACTION_TREND_SELECT);
      }
      int selectedIndex=CanvasPanelState.selectedTrendPointIndex;
      bool reviewButtonClickable=(CanvasPanelState.trendSelectionValid && selectedIndex>=0 && selectedIndex<pointCount &&
                                  CanvasPanelModel.stats.trend.points[selectedIndex].positionId>0);
      AddCanvasHit(CanvasPanelLayout.trendReviewButton,PANEL_ACTION_TREND_OPEN_REVIEW,reviewButtonClickable);
   }
}

CanvasControlVisualState StatsToolbarControlState(PanelAction action, bool selected=false, bool hoverOverridesSelected=false)
{
   if(CanvasPanelState.pressedAction==action) return CONTROL_PRESSED;
   if(CanvasPanelState.hoverAction==action && (!selected || hoverOverridesSelected)) return CONTROL_HOVER;
   return selected?CONTROL_SELECTED:CONTROL_NORMAL;
}

int StatsToolbarTextFont(const UIRect &rect, string text, int horizontalPadding)
{
   int available=MathMax(rect.w-horizontalPadding*2,1);
   int fontSize=CanvasFontSize(13.0);
   if(CanvasPanelRenderer.TextWidth(text,CanvasResolvedFont,fontSize)<=available) return fontSize;
   fontSize=CanvasFontSize(12.0);
   if(CanvasPanelRenderer.TextWidth(text,CanvasResolvedFont,fontSize)<=available) return fontSize;
   return CanvasFontSize(11.0);
}

void DrawStatsSegmentState(const UIRect &rect, CanvasControlVisualState state, bool first, bool last)
{
   if(state==CONTROL_NORMAL) return;
   uint fill=CanvasPanelTheme.toolbar;
   if(state==CONTROL_SELECTED) fill=CanvasPanelTheme.selected;
   else if(state==CONTROL_HOVER) fill=CanvasPanelTheme.hover;
   else if(state==CONTROL_PRESSED) fill=CanvasPanelTheme.root;
   int borderInset=CanvasScalePx(1);
   int leftInset=first?borderInset:0;
   int rightInset=last?borderInset:0;
   CanvasPanelRenderer.FillRect(MakeUIRect(rect.x+leftInset,rect.y+borderInset,
                                          MathMax(rect.w-leftInset-rightInset,1),MathMax(rect.h-borderInset*2,1)),fill);
}

void DrawStatsPeriodSegmentedControl(void)
{
   CanvasPanelRenderer.FillRoundRect(CanvasPanelLayout.statsPeriodSelector,CanvasScalePx(5),
                                     CanvasPanelTheme.toolbar,CanvasPanelTheme.borderNormal);
   string periods[3]={"日","周","月"};
   PanelAction actions[3]={PANEL_ACTION_STATS_DAY,PANEL_ACTION_STATS_WEEK,PANEL_ACTION_STATS_MONTH};
   int textFont=CanvasFontSize(13.0);
   for(int i=0;i<3;i++)
   {
      bool active=(int)CanvasPanelState.statsPeriod==i;
      CanvasControlVisualState state=StatsToolbarControlState(actions[i],active,false);
      DrawStatsSegmentState(CanvasPanelLayout.statsPeriodTabs[i],state,i==0,i==2);
      uint textColor=(state==CONTROL_NORMAL)?CanvasPanelTheme.muted:CanvasPanelTheme.text;
      CanvasPanelRenderer.TextCenter(CanvasPanelLayout.statsPeriodTabs[i],periods[i],textColor,CanvasResolvedFont,textFont);
      if(active)
      {
         UIRect tab=CanvasPanelLayout.statsPeriodTabs[i];
         int underlineH=CanvasScalePx(2);
         CanvasPanelRenderer.FillRect(MakeUIRect(tab.x+CanvasPanelMetrics.space8,
                                                tab.y+tab.h-underlineH-CanvasScalePx(1),
                                                MathMax(tab.w-CanvasPanelMetrics.space8*2,1),underlineH),CanvasPanelTheme.accent);
      }
   }
   for(int i=1;i<3;i++)
   {
      int separatorX=CanvasPanelLayout.statsPeriodTabs[i].x;
      CanvasPanelRenderer.Line(separatorX,CanvasPanelLayout.statsPeriodSelector.y+CanvasPanelMetrics.space6,
                               separatorX,CanvasPanelLayout.statsPeriodSelector.y+CanvasPanelLayout.statsPeriodSelector.h-CanvasPanelMetrics.space6,
                               CanvasPanelTheme.borderWeak);
   }
}

void DrawStatsDateNavigator(string rangeText)
{
   CanvasPanelRenderer.FillRoundRect(CanvasPanelLayout.statsDateNavigator,CanvasScalePx(5),
                                     CanvasPanelTheme.toolbar,CanvasPanelTheme.borderNormal);
   PanelAction actions[3]={PANEL_ACTION_PERIOD_PREV,PANEL_ACTION_PERIOD_CURRENT,PANEL_ACTION_PERIOD_NEXT};
   for(int i=0;i<3;i++)
   {
      CanvasControlVisualState state=StatsToolbarControlState(actions[i],false,false);
      DrawStatsSegmentState(CanvasPanelLayout.statsPeriodNav[i],state,i==0,i==2);
   }

   int arrowFont=CanvasFontSize(13.0);
   CanvasControlVisualState leftState=StatsToolbarControlState(PANEL_ACTION_PERIOD_PREV,false,false);
   CanvasControlVisualState rightState=StatsToolbarControlState(PANEL_ACTION_PERIOD_NEXT,false,false);
   CanvasPanelRenderer.TextCenter(CanvasPanelLayout.statsPeriodNav[0],"‹",
                                  leftState==CONTROL_NORMAL?CanvasPanelTheme.muted:CanvasPanelTheme.text,
                                  CanvasResolvedFont,arrowFont);
   int dateFont=StatsToolbarTextFont(CanvasPanelLayout.statsPeriodNav[1],rangeText,CanvasPanelMetrics.space6);
   CanvasPanelRenderer.TextCenter(CanvasPanelLayout.statsPeriodNav[1],rangeText,CanvasPanelTheme.text,CanvasResolvedFont,dateFont);
   CanvasPanelRenderer.TextCenter(CanvasPanelLayout.statsPeriodNav[2],"›",
                                  rightState==CONTROL_NORMAL?CanvasPanelTheme.muted:CanvasPanelTheme.text,
                                  CanvasResolvedFont,arrowFont);

   for(int i=1;i<3;i++)
   {
      int separatorX=CanvasPanelLayout.statsPeriodNav[i].x;
      CanvasPanelRenderer.Line(separatorX,CanvasPanelLayout.statsDateNavigator.y+CanvasPanelMetrics.space6,
                               separatorX,CanvasPanelLayout.statsDateNavigator.y+CanvasPanelLayout.statsDateNavigator.h-CanvasPanelMetrics.space6,
                               CanvasPanelTheme.borderWeak);
   }
}

void DrawStatsFilterButton(string filterText)
{
   PanelAction action=PANEL_ACTION_FILTER_NEXT;
   CanvasControlVisualState state=StatsToolbarControlState(action,true,true);
   uint fill=CanvasPanelTheme.selected;
   uint border=CanvasPanelTheme.borderStrong;
   uint textColor=CanvasPanelTheme.infoText;
   if(state==CONTROL_HOVER)
   {
      fill=CanvasPanelTheme.hover;
      textColor=CanvasPanelTheme.text;
   }
   else if(state==CONTROL_PRESSED)
   {
      fill=CanvasPanelTheme.root;
      textColor=CanvasPanelTheme.text;
   }
   UIRect rect=CanvasPanelLayout.statsFilterTabs[0];
   CanvasPanelRenderer.FillRoundRect(rect,CanvasScalePx(5),fill,border);
   string text="筛选："+filterText;
   int textFont=StatsToolbarTextFont(rect,text,CanvasPanelMetrics.space10);
   CanvasPanelRenderer.TextCenter(rect,text,textColor,CanvasResolvedFont,textFont);
}

void RenderStatsNavigation(const StatsPanelViewModel &model)
{
   统计详情页面 pages[4]={统计详情_总览,统计详情_策略,统计详情_走势,统计详情_复盘};
   string details[4]={"总览","表现","走势","复盘"};
   for(int i=0;i<CANVAS_STATS_TAB_COUNT;i++)
   {
      bool active=CanvasPanelState.statsDetail==pages[i];
      DrawCanvasButton(CanvasPanelLayout.statsDetailTabs[i],details[i],active?CONTROL_SELECTED:CONTROL_NORMAL);
   }
   DrawStatsPeriodSegmentedControl();
   DrawStatsDateNavigator(model.rangeText);
   DrawStatsFilterButton(model.filterText);
}

void RenderStatsKeyValue(const UIRect &rect, string label, string value, uint valueColor, bool alternate=false)
{
   CanvasPanelRenderer.FillRect(rect,alternate?CanvasPanelTheme.rowAlt:CanvasPanelTheme.row);
   CanvasPanelRenderer.TextLeft(MakeUIRect(rect.x+CanvasPanelMetrics.space10,rect.y,rect.w*56/100-CanvasPanelMetrics.space10,rect.h),label,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontLabel);
   CanvasPanelRenderer.TextRight(MakeUIRect(rect.x+rect.w*56/100,rect.y,rect.w*44/100-CanvasPanelMetrics.space10,rect.h),value,valueColor,CanvasResolvedFont,CanvasPanelMetrics.fontBody);
   DrawSoftDivider(rect.x+CanvasPanelMetrics.space6,rect.y+rect.h-1,rect.x+rect.w-CanvasPanelMetrics.space6,rect.y+rect.h-1);
}

void SplitCanvasTextTwoLines(string text, int maxWidth, string fontName, int fontSize, string &line1, string &line2)
{
   line1=text;
   line2="";
   if(maxWidth<=0 || CanvasPanelRenderer.TextWidth(text,fontName,fontSize)<=maxWidth) return;
   int length=StringLen(text);
   int lastFit=0;
   for(int i=1;i<length;i++)
   {
      if(CanvasPanelRenderer.TextWidth(StringSubstr(text,0,i),fontName,fontSize)>maxWidth) break;
      lastFit=i;
   }
   if(lastFit<=0)
   {
      line1=CanvasPanelRenderer.Ellipsize(text,maxWidth,fontName,fontSize);
      return;
   }
   line1=StringSubstr(text,0,lastFit);
   line2=StringSubstr(text,lastFit);
   StringTrimLeft(line2);
   line2=CanvasPanelRenderer.Ellipsize(line2,maxWidth,fontName,fontSize);
}

void RenderSectionTitle(const UIRect &rect, string title)
{
   CanvasPanelRenderer.TextLeft(rect,title,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontLabel);
   DrawSoftDivider(rect.x,rect.y+rect.h-1,rect.x+rect.w-1,rect.y+rect.h-1);
}

void RenderInsightBox(const UIRect &rect, string title, string text, UISeverity severity)
{
   DrawSurface(rect,severity==UI_SEVERITY_WARNING?SURFACE_WARNING:SURFACE_CONTAINER,
               CanvasPanelMetrics.radiusCard,true,false,true);
   DrawAccentEdge(rect,severity==UI_SEVERITY_MUTED?UI_SEVERITY_INFO:severity,CanvasPanelMetrics.space2,true);
   int inset=CanvasPanelMetrics.space12;
   int titleH=CanvasPanelRenderer.TextHeight(title,CanvasResolvedFont,CanvasPanelMetrics.fontLabel)+CanvasPanelMetrics.space6;
   titleH=MathMin(titleH,MathMax(rect.h/2,1));
   UIRect titleRect=MakeUIRect(rect.x+inset,rect.y+CanvasPanelMetrics.space6,MathMax(rect.w-inset*2,1),titleH);
   UIRect bodyRect=MakeUIRect(rect.x+inset,titleRect.y+titleRect.h,MathMax(rect.w-inset*2,1),MathMax(rect.y+rect.h-titleRect.y-titleRect.h-CanvasPanelMetrics.space8,1));
   uint titleColor=severity==UI_SEVERITY_MUTED?CanvasThemeMuted():CanvasSeverityColor(severity);
   CanvasPanelRenderer.TextLeft(titleRect,title,titleColor,CanvasResolvedFont,CanvasPanelMetrics.fontLabel);
   string line1,line2;
   SplitCanvasTextTwoLines(text,bodyRect.w,CanvasResolvedFont,CanvasPanelMetrics.fontCaption,line1,line2);
   CanvasPanelRenderer.TextBlockTwoLines(bodyRect,line1,line2,CanvasThemeMuted(),CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption,0,CanvasScalePx(1));
}

void RenderReviewFieldCell(const UIRect &rect, string label, string value, uint valueColor, bool alternate=false, bool wide=false)
{
   CanvasPanelRenderer.FillRect(rect,alternate?CanvasPanelTheme.rowAlt:CanvasPanelTheme.row);
   int labelPart=wide?28:44;
   int inset=CanvasPanelMetrics.space8;
   int labelW=rect.w*labelPart/100;
   CanvasPanelRenderer.TextLeft(MakeUIRect(rect.x+inset,rect.y,MathMax(labelW-inset,1),rect.h),label,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   CanvasPanelRenderer.TextRight(MakeUIRect(rect.x+labelW,rect.y,MathMax(rect.w-labelW-inset,1),rect.h),value,valueColor,CanvasResolvedFont,CanvasPanelMetrics.fontBody);
   DrawSoftDivider(rect.x+CanvasPanelMetrics.space4,rect.y+rect.h-1,rect.x+rect.w-CanvasPanelMetrics.space4,rect.y+rect.h-1);
}

string StatsSuccessRate(int confirmed, int failed)
{
   int total=confirmed+failed;
   return total>0?DoubleToString(100.0*confirmed/total,1)+"%":"-";
}

string FormatStatsSignedPriceDiff(double value, int digits=2)
{
   double threshold=digits<=1?0.05:0.005;
   if(value>=threshold) return "+"+DoubleToString(value,digits)+"点";
   if(value<=-threshold) return DoubleToString(value,digits)+"点";
   return DoubleToString(0.0,digits)+"点";
}

bool StatsOverviewCaptionFits(const UIRect &rect, string text, int fontSize)
{
   int available=MathMax(rect.w-CanvasPanelMetrics.space12*2,1);
   return CanvasPanelRenderer.TextWidth(text,CanvasResolvedFont,fontSize)<=available;
}

bool StatsOverviewCaptionFitsSupportedFonts(const UIRect &rect, string text)
{
   return StatsOverviewCaptionFits(rect,text,CanvasPanelMetrics.fontCaption) ||
          StatsOverviewCaptionFits(rect,text,CanvasFontSize(8.5));
}

int StatsOverviewCaptionFont(const UIRect &rect, string text)
{
   return StatsOverviewCaptionFits(rect,text,CanvasPanelMetrics.fontCaption)?
          CanvasPanelMetrics.fontCaption:CanvasFontSize(8.5);
}

string StatsOverviewNetPointsCaption(const LifecycleStats &st, const UIRect &rect)
{
   if(st.trades<=0) return "净点数 —";
   string full="净点数 "+FormatStatsSignedPriceDiff(st.priceDiff,2);
   if(StatsOverviewCaptionFitsSupportedFonts(rect,full)) return full;
   return "净点数 "+FormatStatsSignedPriceDiff(st.priceDiff,1);
}

string StatsOverviewTradeCountCaption(const LifecycleStats &st, const UIRect &rect)
{
   string full=StringFormat("多%d 空%d · %.2f手",st.buyTrades,st.sellTrades,st.entryVolume);
   if(StatsOverviewCaptionFitsSupportedFonts(rect,full)) return full;
   return StringFormat("多%d空%d·%.2f手",st.buyTrades,st.sellTrades,st.entryVolume);
}

string StatsExtremeTradeCaption(bool valid, int direction, double volume, double priceDiff, const UIRect &rect)
{
   if(!valid) return "暂无交易";
   string directionText=direction==POSITION_TYPE_BUY?"多":(direction==POSITION_TYPE_SELL?"空":"未知");
   string volumeText=DoubleToString(volume,2)+"手";
   string full=directionText+" · "+volumeText+" · "+FormatStatsSignedPriceDiff(priceDiff,2);
   if(StatsOverviewCaptionFitsSupportedFonts(rect,full)) return full;
   string compact=directionText+"·"+volumeText+"·"+FormatStatsSignedPriceDiff(priceDiff,2);
   if(StatsOverviewCaptionFitsSupportedFonts(rect,compact)) return compact;
   return directionText+"·"+volumeText+"·"+FormatStatsSignedPriceDiff(priceDiff,1);
}

void DrawStatsOverviewReviewCardSurface(const UIRect &rect, PanelAction action, bool clickable)
{
   if(!clickable)
   {
      DrawRaisedCard(rect,SURFACE_CARD_RAISED,CanvasPanelMetrics.radiusCard);
      return;
   }
   CanvasControlVisualState state=StatsToolbarControlState(action,false,false);
   if(state==CONTROL_HOVER)
      CanvasPanelRenderer.FillRoundRect(rect,CanvasPanelMetrics.radiusCard,CanvasPanelTheme.hover,CanvasPanelTheme.borderStrong);
   else if(state==CONTROL_PRESSED)
      CanvasPanelRenderer.FillRoundRect(rect,CanvasPanelMetrics.radiusCard,CanvasPanelTheme.root,CanvasPanelTheme.borderStrong);
   else
      DrawRaisedCard(rect,SURFACE_CARD_RAISED,CanvasPanelMetrics.radiusCard);
}

void RenderStatsOverview(const StatsPanelViewModel &model)
{
   LifecycleStats st=model.stats;
   bool hasTrades=st.trades>0;
   bool hasWins=st.wins>0;
   bool hasLosses=st.losses>0;
   bool hasProfitFactor=hasWins && hasLosses && MathAbs(st.grossLoss)>0.005;
   bool hasPayoffRatio=hasWins && hasLosses && MathAbs(st.avgLoss)>0.005;
   double winRate=st.trades>0?100.0*st.wins/st.trades:0.0;
   double avgNet=st.trades>0?st.netProfit/st.trades:0.0;
   double avgPriceDiff=st.trades>0?st.priceDiff/st.trades:0.0;
   double avgHold=st.holdKnownTrades>0?st.totalHoldMinutes/st.holdKnownTrades:0.0;
   double avgWinningHold=st.winningHoldKnownTrades>0?st.winningHoldMinutes/st.winningHoldKnownTrades:0.0;
   double avgLosingHold=st.losingHoldKnownTrades>0?st.losingHoldMinutes/st.losingHoldKnownTrades:0.0;
   string labels[4]={"净利润","交易数","最佳交易","最差交易"};
   string values[4]={LifecycleStatsSignedMoney(st.netProfit),IntegerToString(st.trades),
                     st.bestTradeValid?LifecycleStatsSignedMoney(st.bestProfit):"—",
                     st.worstTradeValid?LifecycleStatsSignedMoney(st.worstProfit):"—"};
   string captions[4]={StatsOverviewNetPointsCaption(st,CanvasPanelLayout.statsSummary[0]),
                       StatsOverviewTradeCountCaption(st,CanvasPanelLayout.statsSummary[1]),
                       StatsExtremeTradeCaption(st.bestTradeValid,st.bestTradeDirection,st.bestTradeVolume,st.bestTradePriceDiff,CanvasPanelLayout.statsSummary[2]),
                       StatsExtremeTradeCaption(st.worstTradeValid,st.worstTradeDirection,st.worstTradeVolume,st.worstTradePriceDiff,CanvasPanelLayout.statsSummary[3])};
   uint summaryColors[4]={CanvasPnLColor(st.netProfit),CanvasPanelTheme.infoText,
                          st.bestTradeValid?CanvasPnLColor(st.bestProfit):CanvasThemeMuted(),
                          st.worstTradeValid?CanvasPnLColor(st.worstProfit):CanvasThemeMuted()};
   uint summaryCaptionColors[4]={hasTrades?CanvasPnLColor(st.priceDiff):CanvasThemeMuted(),CanvasThemeMuted(),CanvasThemeMuted(),CanvasThemeMuted()};
   int captionFonts[4];
   for(int i=0;i<4;i++) captionFonts[i]=StatsOverviewCaptionFont(CanvasPanelLayout.statsSummary[i],captions[i]);
   for(int i=0;i<4;i++)
   {
      bool bestCard=(i==2);
      bool worstCard=(i==3);
      bool reviewCardClickable=(bestCard && st.bestTradeValid && st.bestTradePositionId>0) ||
                               (worstCard && st.worstTradeValid && st.worstTradePositionId>0);
      PanelAction reviewAction=bestCard?PANEL_ACTION_OVERVIEW_BEST_REVIEW:
                               (worstCard?PANEL_ACTION_OVERVIEW_WORST_REVIEW:PANEL_ACTION_NONE);
      DrawStatsOverviewReviewCardSurface(CanvasPanelLayout.statsSummary[i],reviewAction,reviewCardClickable);
      CanvasPanelRenderer.MetricCellThreeLine(CanvasPanelLayout.statsSummary[i],labels[i],values[i],captions[i],summaryColors[i],CanvasThemeMuted(),summaryCaptionColors[i],
                                              CanvasResolvedFont,CanvasPanelMetrics.fontLabel,CanvasPanelMetrics.fontValue,captionFonts[i],CanvasPanelMetrics.space12);
      if(reviewCardClickable)
      {
         UIRect cueRect=MakeUIRect(CanvasPanelLayout.statsSummary[i].x+CanvasPanelLayout.statsSummary[i].w-CanvasScalePx(50),
                                   CanvasPanelLayout.statsSummary[i].y+CanvasPanelMetrics.space6,
                                   CanvasScalePx(40),CanvasScalePx(18));
         CanvasPanelRenderer.TextRight(cueRect,"复盘 ›",CanvasPanelTheme.accent,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      }
   }

   DrawSurface(CanvasPanelLayout.statsLeftColumn,SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
   DrawSurface(CanvasPanelLayout.statsRightColumn,SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
   string leftLabels[7]={"胜率","单均收益","平均盈利","平均亏损","总盈亏比","平均盈亏比","最大回撤"};
   string leftValues[7]={hasTrades?DoubleToString(winRate,1)+"%":"—",hasTrades?LifecycleStatsSignedMoney(avgNet):"—",
                         hasWins?LifecycleStatsSignedMoney(st.avgWin):"—",hasLosses?LifecycleStatsSignedMoney(st.avgLoss):"—",
                         hasProfitFactor?DoubleToString(st.profitFactor,2):"—",hasPayoffRatio?DoubleToString(st.payoffRatio,2):"—",
                         hasTrades?DoubleToString(st.maxRealizedDrawdown,2):"—"};
   uint leftColors[7]={hasTrades?CanvasPanelTheme.infoText:CanvasThemeMuted(),hasTrades?CanvasPnLColor(avgNet):CanvasThemeMuted(),
                       hasWins?CanvasPnLColor(st.avgWin):CanvasThemeMuted(),hasLosses?CanvasPnLColor(st.avgLoss):CanvasThemeMuted(),
                       hasProfitFactor?CanvasPanelTheme.infoText:CanvasThemeMuted(),hasPayoffRatio?CanvasPanelTheme.infoText:CanvasThemeMuted(),
                       hasTrades?CanvasThemeWarning():CanvasThemeMuted()};
   string rightLabels[7]={"单均点数","平均持仓","盈利单均持仓","亏损单均持仓","多单净收益","空单净收益","总交易成本"};
   string rightValues[7]={hasTrades?FormatStatsSignedPriceDiff(avgPriceDiff,2):"—",
                          st.holdKnownTrades>0?FormatHoldMinutes((int)MathRound(avgHold),false):"—",
                          st.winningHoldKnownTrades>0?FormatHoldMinutes((int)MathRound(avgWinningHold),false):"—",
                          st.losingHoldKnownTrades>0?FormatHoldMinutes((int)MathRound(avgLosingHold),false):"—",
                          LifecycleStatsSignedMoney(st.buyProfit),LifecycleStatsSignedMoney(st.sellProfit),DoubleToString(st.totalTradingCost,2)};
   uint rightColors[7]={hasTrades?CanvasPnLColor(avgPriceDiff):CanvasThemeMuted(),CanvasThemeMuted(),
                        st.winningHoldKnownTrades>0?CanvasPanelTheme.infoText:CanvasThemeMuted(),
                        st.losingHoldKnownTrades>0?CanvasPanelTheme.infoText:CanvasThemeMuted(),
                        CanvasPnLColor(st.buyProfit),CanvasPnLColor(st.sellProfit),CanvasThemeMuted()};
   for(int i=0;i<7;i++)
   {
      RenderStatsKeyValue(CanvasPanelLayout.statsLeftRows[i],leftLabels[i],leftValues[i],leftColors[i],(i%2)==1);
      RenderStatsKeyValue(CanvasPanelLayout.statsRightRows[i],rightLabels[i],rightValues[i],rightColors[i],(i%2)==1);
   }
}

UIRect CanvasRowsContainer(const UIRect &headerRect, const UIRect &lastRow)
{
   return MakeUIRect(headerRect.x,headerRect.y,headerRect.w,
                     MathMax(lastRow.y+lastRow.h-headerRect.y,headerRect.h));
}

void DrawCanvasTableRowDivider(const UIRect &rect)
{
   DrawSoftDivider(rect.x+CanvasPanelMetrics.space6,rect.y+rect.h-1,
                   rect.x+rect.w-CanvasPanelMetrics.space6,rect.y+rect.h-1);
}

void PerformanceTableColumns(const UIRect &rect, UIRect &columns[])
{
   ArrayResize(columns,5);
   int widths[5];
   widths[0]=rect.w*30/100;
   widths[1]=rect.w*12/100;
   widths[2]=rect.w*17/100;
   widths[3]=rect.w*21/100;
   widths[4]=rect.w-widths[0]-widths[1]-widths[2]-widths[3];
   int x=rect.x;
   for(int i=0;i<5;i++)
   {
      columns[i]=MakeUIRect(x,rect.y,widths[i],rect.h);
      x+=widths[i];
   }
}

void RenderPerformanceTableHeader(const UIRect &rect, string firstColumn)
{
   CanvasPanelRenderer.FillRect(MakeUIRect(rect.x+1,rect.y+1,MathMax(rect.w-2,1),MathMax(rect.h-1,1)),CanvasThemeHeader());
   UIRect columns[];
   PerformanceTableColumns(rect,columns);
   int inset=CanvasPanelMetrics.space8;
   string labels[5]={firstColumn,"笔数","胜率","净收益","单均收益"};
   CanvasPanelRenderer.TextLeft(columns[0],labels[0],CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontLabel,inset);
   for(int i=1;i<5;i++)
      CanvasPanelRenderer.TextRight(columns[i],labels[i],CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontLabel,inset);
}

string PerformanceWinRateText(const StatsPerformanceBucket &bucket)
{
   if(bucket.trades<=0) return "—";
   return DoubleToString(100.0*bucket.wins/bucket.trades,1)+"%";
}

double PerformanceAverageProfit(const StatsPerformanceBucket &bucket)
{
   return bucket.trades>0?bucket.netProfit/bucket.trades:0.0;
}

double PerformanceAverageHoldMinutes(const StatsPerformanceBucket &bucket)
{
   return bucket.holdKnownTrades>0?bucket.totalHoldMinutes/bucket.holdKnownTrades:0.0;
}

string PerformanceAverageHoldText(const StatsPerformanceBucket &bucket, bool compact=false)
{
   if(bucket.holdKnownTrades<=0) return "—";
   int minutes=(int)MathRound(PerformanceAverageHoldMinutes(bucket));
   if(!compact) return FormatHoldMinutes(minutes,false);
   if(minutes<=0) return "<1分";
   if(minutes<60) return IntegerToString(minutes)+"分";
   if(minutes<1440) return StringFormat("%d时%d分",minutes/60,minutes%60);
   return StringFormat("%d天%d时",minutes/1440,(minutes%1440)/60);
}

void RenderPerformanceTableRow(const UIRect &rect, string name,
                               const StatsPerformanceBucket &bucket, bool alternate)
{
   if(alternate)
      CanvasPanelRenderer.FillRect(MakeUIRect(rect.x+1,rect.y,MathMax(rect.w-2,1),rect.h),CanvasThemeSurfaceAlt());
   UIRect columns[];
   PerformanceTableColumns(rect,columns);
   int inset=CanvasPanelMetrics.space8;
   double averageProfit=PerformanceAverageProfit(bucket);
   string averageProfitText=bucket.trades>0?LifecycleStatsSignedMoney(averageProfit):"—";
   string values[5]={name,IntegerToString(bucket.trades),PerformanceWinRateText(bucket),
                     LifecycleStatsSignedMoney(bucket.netProfit),averageProfitText};
   uint colors[5]={CanvasThemeText(),CanvasThemeText(),CanvasThemeMuted(),CanvasPnLColor(bucket.netProfit),
                   bucket.trades>0?CanvasPnLColor(averageProfit):CanvasThemeDim()};
   CanvasPanelRenderer.TextLeft(columns[0],values[0],colors[0],CanvasResolvedFont,CanvasPanelMetrics.fontBody,inset);
   for(int i=1;i<5;i++)
      CanvasPanelRenderer.TextRight(columns[i],values[i],colors[i],CanvasResolvedFont,CanvasPanelMetrics.fontBody,inset);
   DrawCanvasTableRowDivider(rect);
}

bool PerformanceBucketQualified(const StatsPerformanceBucket &bucket)
{
   return bucket.trades>=3;
}

bool PerformanceBucketBetter(const StatsPerformanceBucket &candidate,
                             const StatsPerformanceBucket &currentBest)
{
   double candidateAverage=PerformanceAverageProfit(candidate);
   double bestAverage=PerformanceAverageProfit(currentBest);
   if(MathAbs(candidateAverage-bestAverage)>0.005) return candidateAverage>bestAverage;
   if(MathAbs(candidate.netProfit-currentBest.netProfit)>0.005) return candidate.netProfit>currentBest.netProfit;
   double candidateWinRate=candidate.trades>0?(double)candidate.wins/candidate.trades:0.0;
   double bestWinRate=currentBest.trades>0?(double)currentBest.wins/currentBest.trades:0.0;
   if(MathAbs(candidateWinRate-bestWinRate)>0.0000001) return candidateWinRate>bestWinRate;
   return candidate.trades>currentBest.trades;
}

int BestPerformanceBucket(const StatsPerformanceBucket &buckets[])
{
   int best=-1;
   for(int i=0;i<ArraySize(buckets);i++)
   {
      if(!PerformanceBucketQualified(buckets[i])) continue;
      if(best<0 || PerformanceBucketBetter(buckets[i],buckets[best])) best=i;
   }
   return best;
}

void RenderStatsStrategy(const StatsPanelViewModel &model)
{
   LifecycleStats st=model.stats;
   string templateNames[STATS_TEMPLATE_COUNT]={"短线","长线","消息","手动"};
   string sessionNames[4]={"亚洲盘","伦敦盘","纽约盘","其他时段"};
   string compactSessionNames[4]={"亚洲","伦敦","纽约","其他"};
   StatsPerformanceBucket templateRows[];
   ArrayResize(templateRows,STATS_TEMPLATE_COUNT);
   for(int i=0;i<STATS_TEMPLATE_COUNT;i++) templateRows[i]=st.templatePerformance[i];

   DrawSurface(CanvasRowsContainer(CanvasPanelLayout.statsTableHeader,CanvasPanelLayout.statsTableRows[3]),
               SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
   RenderPerformanceTableHeader(CanvasPanelLayout.statsTableHeader,"配置表现");
   for(int i=0;i<STATS_TEMPLATE_COUNT;i++)
      RenderPerformanceTableRow(CanvasPanelLayout.statsTableRows[i],templateNames[i],templateRows[i],(i%2)==1);

   int selectedTemplate=LifecycleSelectedPerformanceTemplateBucket();
   StatsPerformanceBucket sessionRows[];
   ArrayResize(sessionRows,4);
   for(int i=0;i<4;i++)
      sessionRows[i]=selectedTemplate<0?st.sessionPerformanceAll[i]:st.sessionPerformanceByTemplate[selectedTemplate][i];

   DrawSurface(CanvasRowsContainer(CanvasPanelLayout.statsNote,CanvasPanelLayout.statsTableRows[7]),
               SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
   string sessionScope=selectedTemplate<0?"全部配置":templateNames[selectedTemplate]+"配置";
   RenderPerformanceTableHeader(CanvasPanelLayout.statsNote,"交易时段 · "+sessionScope);
   for(int i=0;i<4;i++)
      RenderPerformanceTableRow(CanvasPanelLayout.statsTableRows[4+i],sessionNames[i],sessionRows[i],(i%2)==1);

   int totalTrades=0;
   for(int i=0;i<STATS_TEMPLATE_COUNT;i++) totalTrades+=templateRows[i].trades;
   int bestTemplate=BestPerformanceBucket(templateRows);
   int bestSession=BestPerformanceBucket(sessionRows);
   string conclusion="";
   if(totalTrades<=0) conclusion="当前范围暂无已完成交易";
   else if(bestTemplate<0 && bestSession<0) conclusion="当前样本较少，暂不生成表现排序";
   else if(bestTemplate>=0 && bestSession>=0) conclusion="当前较优："+templateNames[bestTemplate]+"配置 · "+sessionNames[bestSession];
   else if(bestTemplate>=0) conclusion="当前较优配置："+templateNames[bestTemplate];
   else conclusion="当前较优时段："+sessionNames[bestSession];

   string holdFull="";
   string holdCompact="";
   if(bestTemplate>=0 && templateRows[bestTemplate].holdKnownTrades>0)
   {
      holdFull=templateNames[bestTemplate]+" "+PerformanceAverageHoldText(templateRows[bestTemplate],false);
      holdCompact=templateNames[bestTemplate]+PerformanceAverageHoldText(templateRows[bestTemplate],true);
   }
   if(bestSession>=0 && sessionRows[bestSession].holdKnownTrades>0)
   {
      string separator=holdFull==""?"":" · ";
      holdFull+=separator+sessionNames[bestSession]+" "+PerformanceAverageHoldText(sessionRows[bestSession],false);
      separator=holdCompact==""?"":" · ";
      holdCompact+=separator+compactSessionNames[bestSession]+PerformanceAverageHoldText(sessionRows[bestSession],true);
   }

   string auxiliaryText="样本少于5笔时，胜率与单均收益仅供参考";
   if(holdFull!="") auxiliaryText="平均持仓："+holdFull+"｜样本少于5笔仅供参考";
   int auxiliaryAvailable=MathMax(CanvasPanelLayout.statsPerformanceSampleNote.w-CanvasPanelMetrics.space8*2,1);
   if(CanvasPanelRenderer.TextWidth(auxiliaryText,CanvasResolvedFont,CanvasPanelMetrics.fontCaption)>auxiliaryAvailable && holdCompact!="")
      auxiliaryText="均持仓："+holdCompact+"｜样本<5笔仅供参考";
   if(CanvasPanelRenderer.TextWidth(auxiliaryText,CanvasResolvedFont,CanvasPanelMetrics.fontCaption)>auxiliaryAvailable && holdCompact!="")
   {
      string conclusionWithSample=conclusion+"｜样本<5笔参考";
      int conclusionAvailable=MathMax(CanvasPanelLayout.statsPerformanceConclusion.w-CanvasPanelMetrics.space8*2,1);
      if(CanvasPanelRenderer.TextWidth(conclusionWithSample,CanvasResolvedFont,CanvasPanelMetrics.fontBody)<=conclusionAvailable)
      {
         conclusion=conclusionWithSample;
         auxiliaryText="均持仓："+holdCompact;
      }
      else auxiliaryText="样本<5笔仅供参考";
   }

   DrawSoftDivider(CanvasPanelLayout.statsPerformanceConclusion.x,CanvasPanelLayout.statsPerformanceConclusion.y,
                   CanvasPanelLayout.statsPerformanceConclusion.x+CanvasPanelLayout.statsPerformanceConclusion.w,
                   CanvasPanelLayout.statsPerformanceConclusion.y);
   CanvasPanelRenderer.TextLeft(CanvasPanelLayout.statsPerformanceConclusion,conclusion,
                                totalTrades>0?CanvasPanelTheme.infoText:CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontBody,CanvasPanelMetrics.space8);
   CanvasPanelRenderer.TextLeft(CanvasPanelLayout.statsPerformanceSampleNote,auxiliaryText,
                                CanvasThemeWarning(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption,CanvasPanelMetrics.space8);
}

void RenderStatsManagement(const StatsPanelViewModel &model)
{
   LifecycleStats st=model.stats;
   DrawSurface(CanvasPanelLayout.statsLeftColumn,SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
   DrawSurface(CanvasPanelLayout.statsRightColumn,SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
   string leftLabels[5]={"风险记录覆盖","平均风险金额","快速保护次数","SL 调整次数","TP 调整次数"};
   string leftValues[5]={StringFormat("%d / %d",st.riskKnownTrades,st.trades),DoubleToString(st.avgInitialRMoney,2),IntegerToString(st.fastProtectionTrades),IntegerToString(st.slModifyTotal),IntegerToString(st.tpModifyTotal)};
   UISeverity leftSeverity[5]={st.riskKnownTrades<st.trades?UI_SEVERITY_WARNING:UI_SEVERITY_SUCCESS,UI_SEVERITY_MUTED,UI_SEVERITY_SUCCESS,UI_SEVERITY_INFO,UI_SEVERITY_INFO};
   string rightLabels[5]={"平均 MFE","平均 MAE","实际捕获率","分批成交次数","尾仓类型分布"};
   string rightValues[5]={DoubleToString(st.avgMfeR,2)+"R",DoubleToString(st.avgMaeR,2)+"R",DoubleToString(st.avgCaptureRatio*100.0,1)+"%",IntegerToString(st.partialFillTotal),StringFormat("结构%d 固定%d 箱体%d 快退%d",st.runnerStructureTrades,st.runnerFixedTrades,st.runnerBoxTrades,st.runnerFastExitTrades)};
   UISeverity rightSeverity[5]={UI_SEVERITY_INFO,UI_SEVERITY_WARNING,UI_SEVERITY_INFO,UI_SEVERITY_MUTED,UI_SEVERITY_MUTED};
   for(int i=0;i<5;i++)
   {
      RenderStatsKeyValue(CanvasPanelLayout.statsLeftRows[i],leftLabels[i],leftValues[i],CanvasSeverityColor(leftSeverity[i]),(i%2)==1);
      RenderStatsKeyValue(CanvasPanelLayout.statsRightRows[i],rightLabels[i],rightValues[i],CanvasSeverityColor(rightSeverity[i]),(i%2)==1);
   }
   RenderInsightBox(CanvasPanelLayout.statsNote,"管理观察",model.insight,st.riskKnownTrades<st.trades?UI_SEVERITY_WARNING:UI_SEVERITY_MUTED);
}

void RenderStatsExecution(const StatsPanelViewModel &model)
{
   LifecycleStats st=model.stats;
   DrawSurface(CanvasRowsContainer(CanvasPanelLayout.statsTableHeader,CanvasPanelLayout.statsTableRows[3]),
               SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
   CanvasPanelRenderer.TableHeader(CanvasPanelLayout.statsTableHeader,"动作","确认 / 实际","失败","成功率","",CanvasThemeHeader(),CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontLabel);
   string actions[4]={"SL/TP 设置","分批离场","全部平仓","快速保护"};
   string confirmed[4]={IntegerToString(st.sltpConfirmed),IntegerToString(st.partialFillEvents),IntegerToString(st.fullCloseFilled),IntegerToString(st.fastProtectionConfirmed)};
   string failed[4]={IntegerToString(st.sltpFailed),"未单列",IntegerToString(st.fullCloseFailed),IntegerToString(st.fastProtectionFailed)};
   string rates[4]={StatsSuccessRate(st.sltpConfirmed,st.sltpFailed),"-",StatsSuccessRate(st.fullCloseFilled,st.fullCloseFailed),StatsSuccessRate(st.fastProtectionConfirmed,st.fastProtectionFailed)};
   int failures[4]={st.sltpFailed,0,st.fullCloseFailed,st.fastProtectionFailed};
   for(int i=0;i<4;i++)
   {
      uint valueColor=failures[i]>0?CanvasThemeWarning():CanvasThemeSuccess();
      CanvasPanelRenderer.TableRow(CanvasPanelLayout.statsTableRows[i],actions[i],confirmed[i],failed[i],rates[i],"",(i%2)==1,CanvasThemeSurfaceAlt(),CanvasThemeText(),valueColor,CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      DrawCanvasTableRowDivider(CanvasPanelLayout.statsTableRows[i]);
   }
   string completeness=StringFormat("数据完整度 %d/%d",st.metadataTrades,st.trades);
   string cost=DoubleToString(MathAbs(st.commission+st.swap+st.fee),2);
   RenderInsightBox(CanvasPanelLayout.statsNote,"执行摘要",completeness+" · 退出 Deal "+IntegerToString(st.exitDeals)+" · 成交成本 "+cost+" · 分批请求 "+IntegerToString(st.partialRequested),
                     st.metadataTrades<st.trades?UI_SEVERITY_WARNING:UI_SEVERITY_MUTED);
}

string BuildExecutionAlertText(const LifecycleStats &st, UISeverity &severity)
{
   severity=UI_SEVERITY_MUTED;
   bool hasFailures=(st.sltpFailed>0 || st.fullCloseFailed>0 || st.fastProtectionFailed>0);
   if(hasFailures)
   {
      string text="执行异常：";
      if(st.sltpFailed>0) text+="SL/TP失败 "+IntegerToString(st.sltpFailed);
      if(st.fullCloseFailed>0)
      {
         if(StringLen(text)>5) text+=" · ";
         text+="全平失败 "+IntegerToString(st.fullCloseFailed);
      }
      if(st.fastProtectionFailed>0)
      {
         if(StringLen(text)>5) text+=" · ";
         text+="快保失败 "+IntegerToString(st.fastProtectionFailed);
      }
      severity=st.fullCloseFailed>0?UI_SEVERITY_DANGER:UI_SEVERITY_WARNING;
      return text;
   }
   if(st.metadataTrades<st.trades)
   {
      severity=UI_SEVERITY_WARNING;
      return "记录不完整："+IntegerToString(st.metadataTrades)+" / "+IntegerToString(st.trades);
   }
   return "";
}

int TrendValueToY(double value, double minimum, double maximum, const UIRect &rect)
{
   if(rect.h<=1 || maximum<=minimum) return rect.y+rect.h/2;
   double ratio=(value-minimum)/(maximum-minimum);
   ratio=MathMax(0.0,MathMin(ratio,1.0));
   return rect.y+rect.h-1-(int)MathRound(ratio*(rect.h-1));
}

double NiceAxisStep(double range, int targetTicks)
{
   if(range<=0.0) return 1.0;
   double rawStep=range/MathMax(targetTicks-1,1);
   double magnitude=MathPow(10.0,MathFloor(MathLog10(rawStep)));
   if(magnitude<=0.0) magnitude=1.0;
   double normalized=rawStep/magnitude;
   double niceNormalized=1.0;
   if(normalized<=1.0) niceNormalized=1.0;
   else if(normalized<=2.0) niceNormalized=2.0;
   else if(normalized<=5.0) niceNormalized=5.0;
   else niceNormalized=10.0;
   return niceNormalized*magnitude;
}

void ExpandTrendAxisRange(double rawMinimum, double rawMaximum, double &drawMinimum, double &drawMaximum)
{
   double range=rawMaximum-rawMinimum;
   if(range<=0.0)
   {
      double padding=MathMax(MathAbs(rawMaximum)*0.10,1.0);
      drawMinimum=rawMinimum-padding;
      drawMaximum=rawMaximum+padding;
   }
   else
   {
      double padding=MathMax(range*0.10,0.01);
      drawMinimum=rawMinimum-padding;
      drawMaximum=rawMaximum+padding;
   }
   double step=NiceAxisStep(drawMaximum-drawMinimum,5);
   if(step>0.0)
   {
      drawMinimum=MathFloor(drawMinimum/step)*step;
      drawMaximum=MathCeil(drawMaximum/step)*step;
   }
}

int BuildAxisTicks(double minimum, double maximum, int targetTicks, double &ticks[])
{
   ArrayResize(ticks,0);
   if(maximum<=minimum) return 0;
   double step=NiceAxisStep(maximum-minimum,MathMax(targetTicks,2));
   if(step<=0.0) return 0;
   double first=MathCeil(minimum/step-0.000000001)*step;
   for(int i=0;i<16;i++)
   {
      double value=first+i*step;
      if(value>maximum+step*0.000001) break;
      if(MathAbs(value)<=step*0.000001) value=0.0;
      int size=ArraySize(ticks);
      ArrayResize(ticks,size+1);
      ticks[size]=value;
   }
   if(ArraySize(ticks)<3)
   {
      ArrayResize(ticks,3);
      ticks[0]=minimum;
      ticks[1]=0.0;
      ticks[2]=maximum;
   }
   return ArraySize(ticks);
}

string FormatTrendAxisMoney(double value)
{
   if(MathAbs(value)<=0.005) return "0.00";
   int digits=MathAbs(value)>=100.0?0:(MathAbs(value)>=10.0?1:2);
   string number=DoubleToString(value,digits);
   return value>0.0?"+"+number:number;
}

string FormatTrendAxisTick(double value)
{
   if(MathAbs(value)<0.0000001) return "0";
   int digits=MathAbs(value)>=10.0?0:1;
   string number=DoubleToString(value,digits);
   return value>0.0?"+"+number:number;
}

struct TrendAxisRenderData
{
   double curveMinimum;
   double curveMaximum;
   double barsMinimum;
   double barsMaximum;
   int    curvePeakIndex;
   int    maximumProfitIndex;
   int    maximumLossIndex;
};

struct TrendAxisRenderStyle
{
   int fontSize;
   int tickTarget;
   int textHeight;
   int verticalPadding;
};

bool BuildTrendAxisRenderData(const StatsTrendViewModel &trend, TrendAxisRenderData &data)
{
   int count=ArraySize(trend.points);
   data.curveMinimum=0.0;
   data.curveMaximum=0.0;
   data.barsMinimum=0.0;
   data.barsMaximum=0.0;
   data.curvePeakIndex=0;
   data.maximumProfitIndex=-1;
   data.maximumLossIndex=-1;
   if(count<=0) return false;

   double peakValue=trend.points[0].cumulativeProfit;
   for(int i=0;i<count;i++)
   {
      double cumulative=trend.points[i].cumulativeProfit;
      double result=trend.points[i].netProfit;
      data.curveMinimum=MathMin(data.curveMinimum,cumulative);
      data.curveMaximum=MathMax(data.curveMaximum,cumulative);
      data.barsMinimum=MathMin(data.barsMinimum,result);
      data.barsMaximum=MathMax(data.barsMaximum,result);
      if(cumulative>peakValue)
      {
         peakValue=cumulative;
         data.curvePeakIndex=i;
      }
      if(result>0.0 && (data.maximumProfitIndex<0 || result>trend.points[data.maximumProfitIndex].netProfit))
         data.maximumProfitIndex=i;
      if(result<0.0 && (data.maximumLossIndex<0 || result<trend.points[data.maximumLossIndex].netProfit))
         data.maximumLossIndex=i;
   }

   double rawCurveMinimum=data.curveMinimum;
   double rawCurveMaximum=data.curveMaximum;
   double rawBarsMinimum=data.barsMinimum;
   double rawBarsMaximum=data.barsMaximum;
   ExpandTrendAxisRange(rawCurveMinimum,rawCurveMaximum,data.curveMinimum,data.curveMaximum);
   ExpandTrendAxisRange(rawBarsMinimum,rawBarsMaximum,data.barsMinimum,data.barsMaximum);
   return true;
}

UIRect TrendSafePlotRect(const UIRect &rawPlotRect, const TrendAxisRenderStyle &style)
{
   int maxPadding=MathMax((rawPlotRect.h-2)/2,0);
   int padding=MathMin(MathMax(style.verticalPadding,0),maxPadding);
   return MakeUIRect(rawPlotRect.x,rawPlotRect.y+padding,rawPlotRect.w,MathMax(rawPlotRect.h-padding*2,1));
}

int TrendAxisMaximumLabelWidth(double minimum, double maximum, int targetTicks, int fontSize)
{
   double ticks[];
   int tickCount=BuildAxisTicks(minimum,maximum,targetTicks,ticks);
   int maximumWidth=0;
   for(int i=0;i<tickCount;i++)
      maximumWidth=MathMax(maximumWidth,CanvasPanelRenderer.TextWidth(FormatTrendAxisTick(ticks[i]),CanvasResolvedFont,fontSize));
   return maximumWidth;
}

int TrendAxisMinimumTickGap(double minimum, double maximum, int targetTicks, const UIRect &safePlotRect)
{
   double ticks[];
   int tickCount=BuildAxisTicks(minimum,maximum,targetTicks,ticks);
   if(tickCount<2) return 2147483647;
   int minimumGap=2147483647;
   int previousY=TrendValueToY(ticks[0],minimum,maximum,safePlotRect);
   for(int i=1;i<tickCount;i++)
   {
      int currentY=TrendValueToY(ticks[i],minimum,maximum,safePlotRect);
      int gap=currentY>previousY?currentY-previousY:previousY-currentY;
      minimumGap=MathMin(minimumGap,gap);
      previousY=currentY;
   }
   return minimumGap;
}

void ResolveSharedTrendAxisStyle(const TrendAxisRenderData &data,
                                 const UIRect &curveAxisRect, const UIRect &curvePlotRect,
                                 const UIRect &barsAxisRect, const UIRect &barsPlotRect,
                                 TrendAxisRenderStyle &style)
{
   int candidates[3]={CanvasFontSize(10.0),CanvasFontSize(9.0),CanvasFontSize(8.0)};
   int availableWidth=MathMax(MathMin(curveAxisRect.w,barsAxisRect.w)-CanvasPanelMetrics.space6,1);
   int minimumTextGap=CanvasScalePx(4);
   style.fontSize=candidates[2];
   style.tickTarget=4;
   style.textHeight=CanvasPanelRenderer.TextHeight("0",CanvasResolvedFont,style.fontSize);
   style.verticalPadding=style.textHeight/2+CanvasPanelMetrics.space2;

   for(int i=0;i<3;i++)
   {
      TrendAxisRenderStyle candidate;
      candidate.fontSize=candidates[i];
      candidate.tickTarget=5;
      candidate.textHeight=CanvasPanelRenderer.TextHeight("0",CanvasResolvedFont,candidate.fontSize);
      candidate.verticalPadding=candidate.textHeight/2+CanvasPanelMetrics.space2;
      UIRect curveSafe=TrendSafePlotRect(curvePlotRect,candidate);
      UIRect barsSafe=TrendSafePlotRect(barsPlotRect,candidate);
      int maximumLabelWidth=MathMax(TrendAxisMaximumLabelWidth(data.curveMinimum,data.curveMaximum,candidate.tickTarget,candidate.fontSize),
                                    TrendAxisMaximumLabelWidth(data.barsMinimum,data.barsMaximum,candidate.tickTarget,candidate.fontSize));
      int curveGap=TrendAxisMinimumTickGap(data.curveMinimum,data.curveMaximum,candidate.tickTarget,curveSafe);
      int barsGap=TrendAxisMinimumTickGap(data.barsMinimum,data.barsMaximum,candidate.tickTarget,barsSafe);
      if(maximumLabelWidth<=availableWidth &&
         curveGap>=candidate.textHeight+minimumTextGap &&
         barsGap>=candidate.textHeight+minimumTextGap)
      {
         style=candidate;
         return;
      }
   }
}

void RenderTrendAxisAndGrid(const UIRect &axisRect, const UIRect &plotRect,
                            double minimum, double maximum, const TrendAxisRenderStyle &style)
{
   double ticks[];
   int tickCount=BuildAxisTicks(minimum,maximum,style.tickTarget,ticks);
   int textH=style.textHeight;
   for(int i=0;i<tickCount;i++)
   {
      double value=ticks[i];
      int y=TrendValueToY(value,minimum,maximum,plotRect);
      bool zero=(MathAbs(value)<0.0000001);
      uint gridColor=zero?CanvasPanelTheme.borderStrong:CanvasPanelTheme.borderWeak;
      CanvasPanelRenderer.Line(plotRect.x,y,plotRect.x+plotRect.w-1,y,gridColor);
      if(zero && y+1<plotRect.y+plotRect.h)
         CanvasPanelRenderer.Line(plotRect.x,y+1,plotRect.x+plotRect.w-1,y+1,CanvasPanelTheme.borderNormal);
      // tickY同时服务网格线和文字中心；纵向安全区已统一预留，不再逐标签Clamp。
      UIRect labelRect=MakeUIRect(axisRect.x+CanvasPanelMetrics.space6,y-textH/2,
                                  MathMax(axisRect.w-CanvasPanelMetrics.space6,1),textH);
      CanvasPanelRenderer.TextRight(labelRect,FormatTrendAxisTick(value),zero?CanvasThemeText():CanvasThemeDim(),CanvasResolvedFont,style.fontSize);
   }
}

int TrendTradePointX(const UIRect &plotRect, int tradeIndex, int tradeCount)
{
   if(tradeCount<=0) return plotRect.x;
   return plotRect.x+(int)MathRound((double)(tradeIndex+1)*(plotRect.w-1)/tradeCount);
}

void RenderTrendXAxisLabel(const UIRect &axisRect, int centerX, string text)
{
   int textW=CanvasPanelRenderer.TextWidth(text,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   int x=MathMax(axisRect.x,MathMin(centerX-textW/2,axisRect.x+axisRect.w-textW));
   CanvasPanelRenderer.TextLeft(MakeUIRect(x,axisRect.y,MathMax(textW,1),axisRect.h),text,CanvasThemeDim(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
}

int TrendLabelOverlapArea(const UIRect &labelRect, const UIRect &avoidRect, int safeGap)
{
   if(labelRect.w<=0 || labelRect.h<=0 || avoidRect.w<=0 || avoidRect.h<=0) return 0;
   int left=MathMax(labelRect.x,avoidRect.x-safeGap);
   int top=MathMax(labelRect.y,avoidRect.y-safeGap);
   int right=MathMin(labelRect.x+labelRect.w,avoidRect.x+avoidRect.w+safeGap);
   int bottom=MathMin(labelRect.y+labelRect.h,avoidRect.y+avoidRect.h+safeGap);
   if(right<=left || bottom<=top) return 0;
   return (right-left)*(bottom-top);
}

bool PlaceTrendValueLabel(const UIRect &plotRect, int anchorX, int anchorY,
                          int prefSideX, int prefSideY, string text,
                          const UIRect &avoidA, const UIRect &avoidB, UIRect &outRect)
{
   int edgeInset=MathMax(CanvasPanelMetrics.space2,1);
   int anchorGap=MathMax(CanvasPanelMetrics.space4,2);
   int textW=CanvasPanelRenderer.TextWidth(text,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   int textH=CanvasPanelRenderer.TextHeight(text,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   int width=MathMin(textW+CanvasPanelMetrics.space8,MathMax(plotRect.w-edgeInset*2,1));
   int height=MathMin(textH+CanvasPanelMetrics.space4,MathMax(plotRect.h-edgeInset*2,1));
   if(width<=0 || height<=0) return false;

   int minX=plotRect.x+edgeInset;
   int maxX=plotRect.x+plotRect.w-edgeInset-width;
   int minY=plotRect.y+edgeInset;
   int maxY=plotRect.y+plotRect.h-edgeInset-height;
   if(maxX<minX || maxY<minY) return false;

   int preferredX=prefSideX>=0?1:-1;
   int preferredY=prefSideY>0?1:(prefSideY<0?-1:0);
   int sideX[8];
   int sideY[8];
   sideX[0]=preferredX;  sideY[0]=preferredY;
   sideX[1]=preferredX;  sideY[1]=-preferredY;
   sideX[2]=-preferredX; sideY[2]=preferredY;
   sideX[3]=-preferredX; sideY[3]=-preferredY;
   sideX[4]=0;           sideY[4]=preferredY;
   sideX[5]=0;           sideY[5]=-preferredY;
   sideX[6]=preferredX;  sideY[6]=0;
   sideX[7]=-preferredX; sideY[7]=0;

   int bestScore=2147483647;
   UIRect bestRect=MakeUIRect(minX,minY,width,height);
   for(int i=0;i<8;i++)
   {
      int x=anchorX-width/2;
      if(sideX[i]>0) x=anchorX+anchorGap;
      else if(sideX[i]<0) x=anchorX-width-anchorGap;
      int y=anchorY-height/2;
      if(sideY[i]>0) y=anchorY+anchorGap;
      else if(sideY[i]<0) y=anchorY-height-anchorGap;
      x=MathMax(minX,MathMin(x,maxX));
      y=MathMax(minY,MathMin(y,maxY));
      UIRect candidate=MakeUIRect(x,y,width,height);
      int score=TrendLabelOverlapArea(candidate,avoidA,CanvasPanelMetrics.space2)
               +TrendLabelOverlapArea(candidate,avoidB,CanvasPanelMetrics.space2);
      if(score<bestScore)
      {
         bestScore=score;
         bestRect=candidate;
         if(score==0) break;
      }
   }
   outRect=bestRect;
   return true;
}

void RenderTrendValueLabel(const UIRect &labelRect, string text, uint textColor)
{
   CanvasPanelRenderer.FillRoundRect(labelRect,CanvasPanelMetrics.radiusButton,CanvasPanelTheme.header,CanvasPanelTheme.borderWeak);
   CanvasPanelRenderer.TextCenter(labelRect,text,textColor,CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
}

void RenderTrendEquityCurve(const UIRect &axisRect, const UIRect &plotRect, const UIRect &xAxisRect,
                            const StatsTrendViewModel &trend, const TrendAxisRenderData &axisData,
                            const TrendAxisRenderStyle &axisStyle, int selectedIndex)
{
   int count=ArraySize(trend.points);
   if(count<=0 || plotRect.w<=1 || plotRect.h<=1) return;
   UIRect safePlotRect=TrendSafePlotRect(plotRect,axisStyle);
   double drawMinimum=axisData.curveMinimum;
   double drawMaximum=axisData.curveMaximum;
   int peakIndex=axisData.curvePeakIndex;
   double peakValue=trend.points[peakIndex].cumulativeProfit;
   RenderTrendAxisAndGrid(axisRect,safePlotRect,drawMinimum,drawMaximum,axisStyle);

   bool selectionValid=(selectedIndex>=0 && selectedIndex<count);
   int selectedX=selectionValid?TrendTradePointX(safePlotRect,selectedIndex,count):safePlotRect.x;
   if(selectionValid)
      CanvasPanelRenderer.Line(selectedX,safePlotRect.y,selectedX,safePlotRect.y+safePlotRect.h-1,CanvasPanelTheme.borderStrong);

   int previousX=safePlotRect.x;
   int previousY=TrendValueToY(0.0,drawMinimum,drawMaximum,safePlotRect);
   CanvasPanelRenderer.FillCircle(previousX,previousY,CanvasScalePx(2),CanvasThemeMuted());
   for(int i=0;i<count;i++)
   {
      int x=TrendTradePointX(safePlotRect,i,count);
      int y=TrendValueToY(trend.points[i].cumulativeProfit,drawMinimum,drawMaximum,safePlotRect);
      CanvasPanelRenderer.LineAA(previousX,previousY,x,y,CanvasThemeAccent());
      previousX=x;
      previousY=y;
   }

   int lastIndex=count-1;
   int lastX=TrendTradePointX(safePlotRect,lastIndex,count);
   int lastY=TrendValueToY(trend.points[lastIndex].cumulativeProfit,drawMinimum,drawMaximum,safePlotRect);
   int peakX=TrendTradePointX(safePlotRect,peakIndex,count);
   int peakY=TrendValueToY(trend.points[peakIndex].cumulativeProfit,drawMinimum,drawMaximum,safePlotRect);
   CanvasPanelRenderer.FillCircle(peakX,peakY,CanvasScalePx(3),CanvasPnLColor(peakValue));
   CanvasPanelRenderer.FillCircle(lastX,lastY,CanvasScalePx(3),CanvasThemeAccent());
   UIRect occupiedA=MakeUIRect(0,0,0,0);
   UIRect occupiedB=MakeUIRect(0,0,0,0);
   UIRect labelRect=MakeUIRect(0,0,0,0);
   bool hasOccupiedA=false;
   if(selectionValid)
   {
      int selectedY=TrendValueToY(trend.points[selectedIndex].cumulativeProfit,drawMinimum,drawMaximum,safePlotRect);
      CanvasPanelRenderer.FillCircle(selectedX,selectedY,CanvasScalePx(5),CanvasThemeAccent());
      CanvasPanelRenderer.FillCircle(selectedX,selectedY,CanvasScalePx(3),CanvasPanelTheme.card);
      CanvasPanelRenderer.FillCircle(selectedX,selectedY,CanvasScalePx(2),CanvasThemeAccent());
      int prefX=selectedX<safePlotRect.x+safePlotRect.w/2?1:-1;
      int prefY=selectedY<safePlotRect.y+safePlotRect.h/2?1:-1;
      string selectedLabel="累计 "+FormatTrendAxisMoney(trend.points[selectedIndex].cumulativeProfit);
      if(PlaceTrendValueLabel(safePlotRect,selectedX,selectedY,prefX,prefY,selectedLabel,occupiedA,occupiedB,labelRect))
      {
         RenderTrendValueLabel(labelRect,selectedLabel,CanvasPnLColor(trend.points[selectedIndex].cumulativeProfit));
         occupiedA=labelRect;
         hasOccupiedA=true;
      }
   }
   if(peakIndex!=selectedIndex && peakIndex!=lastIndex)
   {
      int prefX=peakX<safePlotRect.x+safePlotRect.w/2?1:-1;
      int prefY=peakY<safePlotRect.y+safePlotRect.h/2?1:-1;
      string peakLabel="高点 "+FormatTrendAxisMoney(trend.points[peakIndex].cumulativeProfit);
      if(PlaceTrendValueLabel(safePlotRect,peakX,peakY,prefX,prefY,peakLabel,occupiedA,occupiedB,labelRect))
      {
         RenderTrendValueLabel(labelRect,peakLabel,CanvasPnLColor(trend.points[peakIndex].cumulativeProfit));
         if(!hasOccupiedA)
         {
            occupiedA=labelRect;
            hasOccupiedA=true;
         }
         else
            occupiedB=labelRect;
      }
   }
   if(lastIndex!=selectedIndex)
   {
      string currentLabel=(lastIndex==peakIndex?"当前/高点 ":"当前 ")+FormatTrendAxisMoney(trend.points[lastIndex].cumulativeProfit);
      int prefX=lastX<safePlotRect.x+safePlotRect.w/2?1:-1;
      int prefY=lastY<safePlotRect.y+safePlotRect.h/2?1:-1;
      if(PlaceTrendValueLabel(safePlotRect,lastX,lastY,prefX,prefY,currentLabel,occupiedA,occupiedB,labelRect))
         RenderTrendValueLabel(labelRect,currentLabel,CanvasPnLColor(trend.points[lastIndex].cumulativeProfit));
   }

   RenderTrendXAxisLabel(xAxisRect,safePlotRect.x,"起点");
   if(count>1)
   {
      int middleIndex=(count-1)/2;
      RenderTrendXAxisLabel(xAxisRect,TrendTradePointX(safePlotRect,middleIndex,count),"第"+IntegerToString(middleIndex+1)+"笔");
   }
   RenderTrendXAxisLabel(xAxisRect,lastX,"第"+IntegerToString(count)+"笔");
}

void RenderTrendProfitBars(const UIRect &axisRect, const UIRect &plotRect, const UIRect &xAxisRect,
                           const StatsTrendViewModel &trend, const TrendAxisRenderData &axisData,
                           const TrendAxisRenderStyle &axisStyle, int selectedIndex)
{
   int count=ArraySize(trend.points);
   if(count<=0 || plotRect.w<=1 || plotRect.h<=1) return;
   UIRect safePlotRect=TrendSafePlotRect(plotRect,axisStyle);
   double drawMinimum=axisData.barsMinimum;
   double drawMaximum=axisData.barsMaximum;
   int maximumProfitIndex=axisData.maximumProfitIndex;
   int maximumLossIndex=axisData.maximumLossIndex;
   RenderTrendAxisAndGrid(axisRect,safePlotRect,drawMinimum,drawMaximum,axisStyle);
   int zeroY=TrendValueToY(0.0,drawMinimum,drawMaximum,safePlotRect);

   bool selectionValid=(selectedIndex>=0 && selectedIndex<count);
   int selectedX=selectionValid?TrendTradePointX(safePlotRect,selectedIndex,count):safePlotRect.x;
   if(selectionValid)
      CanvasPanelRenderer.Line(selectedX,safePlotRect.y,selectedX,safePlotRect.y+safePlotRect.h-1,CanvasPanelTheme.borderStrong);

   int slotW=MathMax(safePlotRect.w/(count+1),1);
   int barW=MathMax(MathMin(slotW-1,CanvasScalePx(8)),1);
   for(int i=0;i<count;i++)
   {
      int centerX=TrendTradePointX(safePlotRect,i,count);
      int x=MathMax(safePlotRect.x,MathMin(centerX-barW/2,safePlotRect.x+safePlotRect.w-barW));
      double value=trend.points[i].netProfit;
      int valueY=TrendValueToY(value,drawMinimum,drawMaximum,safePlotRect);
      UIRect barRect;
      if(value>0.0)
         barRect=MakeUIRect(x,valueY,barW,MathMax(zeroY-valueY,1));
      else if(value<0.0)
         barRect=MakeUIRect(x,zeroY+1,barW,MathMax(valueY-zeroY,1));
      else
         barRect=MakeUIRect(x,zeroY,barW,1);
      uint barColor=CanvasPnLColor(value);
      CanvasPanelRenderer.FillRect(barRect,barColor);
      if(value>0.005)
         CanvasPanelRenderer.Line(barRect.x,barRect.y,barRect.x+barRect.w-1,barRect.y,CanvasThemeText());
      else if(value<-0.005)
         CanvasPanelRenderer.Line(barRect.x,barRect.y+barRect.h-1,barRect.x+barRect.w-1,barRect.y+barRect.h-1,CanvasThemeText());
      if(i==selectedIndex && barRect.w>1 && barRect.h>1)
         CanvasPanelRenderer.StrokeRoundedRect(barRect,1,CanvasThemeAccent());
   }

   UIRect occupiedA=MakeUIRect(0,0,0,0);
   UIRect occupiedB=MakeUIRect(0,0,0,0);
   UIRect labelRect=MakeUIRect(0,0,0,0);
   bool hasOccupiedA=false;

   if(maximumProfitIndex>=0 && maximumProfitIndex!=selectedIndex)
   {
      int x=TrendTradePointX(safePlotRect,maximumProfitIndex,count);
      int y=TrendValueToY(trend.points[maximumProfitIndex].netProfit,drawMinimum,drawMaximum,safePlotRect);
      string text=FormatTrendAxisMoney(trend.points[maximumProfitIndex].netProfit);
      int prefX=x<safePlotRect.x+safePlotRect.w/2?1:-1;
      if(PlaceTrendValueLabel(safePlotRect,x,y,prefX,-1,text,occupiedA,occupiedB,labelRect))
      {
         RenderTrendValueLabel(labelRect,text,CanvasPnLColor(trend.points[maximumProfitIndex].netProfit));
         occupiedA=labelRect;
         hasOccupiedA=true;
      }
   }
   if(maximumLossIndex>=0 && maximumLossIndex!=selectedIndex)
   {
      int x=TrendTradePointX(safePlotRect,maximumLossIndex,count);
      int y=TrendValueToY(trend.points[maximumLossIndex].netProfit,drawMinimum,drawMaximum,safePlotRect);
      string text=FormatTrendAxisMoney(trend.points[maximumLossIndex].netProfit);
      int prefX=x<safePlotRect.x+safePlotRect.w/2?1:-1;
      if(PlaceTrendValueLabel(safePlotRect,x,y,prefX,1,text,occupiedA,occupiedB,labelRect))
      {
         RenderTrendValueLabel(labelRect,text,CanvasPnLColor(trend.points[maximumLossIndex].netProfit));
         if(!hasOccupiedA)
         {
            occupiedA=labelRect;
            hasOccupiedA=true;
         }
         else
            occupiedB=labelRect;
      }
   }
   if(selectionValid)
   {
      int y=TrendValueToY(trend.points[selectedIndex].netProfit,drawMinimum,drawMaximum,safePlotRect);
      uint valueColor=CanvasPnLColor(trend.points[selectedIndex].netProfit);
      string text=FormatTrendAxisMoney(trend.points[selectedIndex].netProfit);
      int prefX=selectedX<safePlotRect.x+safePlotRect.w/2?1:-1;
      int barPixelH=y>=zeroY?y-zeroY:zeroY-y;
      int textH=CanvasPanelRenderer.TextHeight(text,CanvasResolvedFont,CanvasPanelMetrics.fontCaption)+CanvasPanelMetrics.space4;
      int prefY=barPixelH<textH+CanvasPanelMetrics.space4?0:(trend.points[selectedIndex].netProfit>=0.0?-1:1);
      if(PlaceTrendValueLabel(safePlotRect,selectedX,y,prefX,prefY,text,occupiedA,occupiedB,labelRect))
         RenderTrendValueLabel(labelRect,text,valueColor);
   }

   if(count>0) RenderTrendXAxisLabel(xAxisRect,TrendTradePointX(safePlotRect,0,count),"第1笔");
   if(count>2)
   {
      int middleIndex=(count-1)/2;
      RenderTrendXAxisLabel(xAxisRect,TrendTradePointX(safePlotRect,middleIndex,count),"第"+IntegerToString(middleIndex+1)+"笔");
   }
   if(count>1) RenderTrendXAxisLabel(xAxisRect,TrendTradePointX(safePlotRect,count-1,count),"第"+IntegerToString(count)+"笔");
}

string FormatTrendSelectionTime(datetime closeTime)
{
   datetime beijingTime=ConvertServerTimeToBeijing(closeTime);
   MqlDateTime value;
   if(beijingTime<=0 || !TimeToStruct(beijingTime,value)) return "北京时间 --";
   if(CanvasPanelState.statsPeriod==统计_日)
      return StringFormat("北京时间 %02d:%02d",value.hour,value.min);
   return "北京时间 "+FormatBeijingTimeCompact(closeTime);
}

void RenderTrendSelectionValues(const UIRect &rect, const TrendTradePoint &point)
{
   string parts[6]={"单笔 ",LifecycleStatsSignedMoney(point.netProfit)," · 累计 ",LifecycleStatsSignedMoney(point.cumulativeProfit)," · 回撤 ",LifecycleStatsSignedMoney(point.drawdown)};
   uint colors[6]={CanvasThemeMuted(),CanvasPnLColor(point.netProfit),
                   CanvasThemeMuted(),CanvasPnLColor(point.cumulativeProfit),
                   CanvasThemeMuted(),point.drawdown<0.0?CanvasThemeWarning():CanvasThemeMuted()};
   int x=rect.x;
   int right=rect.x+rect.w;
   for(int i=0;i<6 && x<right;i++)
   {
      int textW=CanvasPanelRenderer.TextWidth(parts[i],CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      int available=right-x;
      CanvasPanelRenderer.TextEllipsized(MakeUIRect(x,rect.y,available,rect.h),parts[i],colors[i],CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      x+=MathMin(textW,available);
   }
}

void RenderStatsTrend(const StatsPanelViewModel &model)
{
   const StatsTrendViewModel trend=model.trend;
   string labels[4]={"累计净收益","当前回撤","收益高点","最近 "+IntegerToString(trend.recentCount)+" 笔"};
   string values[4]={LifecycleStatsSignedMoney(trend.cumulativeProfit),LifecycleStatsSignedMoney(trend.currentDrawdown),
                     LifecycleStatsSignedMoney(trend.peakProfit),LifecycleStatsSignedMoney(trend.recentProfit)};
   string captions[4]={"共 "+IntegerToString(ArraySize(trend.points))+" 笔","最大回撤 "+LifecycleStatsSignedMoney(trend.maxDrawdown),"区间累计高点","逐笔净收益合计"};
   uint summaryColors[4]={CanvasPnLColor(trend.cumulativeProfit),
                          trend.currentDrawdown<0.0?CanvasThemeWarning():CanvasThemeSuccess(),
                          CanvasPnLColor(trend.peakProfit),CanvasPnLColor(trend.recentProfit)};
   uint summaryCaptionColors[4]={CanvasThemeDim(),trend.maxDrawdown<0.0?CanvasThemeWarning():CanvasThemeDim(),CanvasThemeDim(),CanvasThemeDim()};
   for(int i=0;i<4;i++)
   {
      DrawRaisedCard(CanvasPanelLayout.trendSummary[i],SURFACE_CARD_RAISED,CanvasPanelMetrics.radiusCard);
      CanvasPanelRenderer.MetricCellThreeLine(CanvasPanelLayout.trendSummary[i],labels[i],values[i],captions[i],summaryColors[i],CanvasThemeMuted(),summaryCaptionColors[i],
                                              CanvasResolvedFont,CanvasPanelMetrics.fontLabel,CanvasPanelMetrics.fontValue,CanvasPanelMetrics.fontCaption,CanvasPanelMetrics.space10);
   }

   int selectedIndex=CanvasPanelState.trendSelectionValid?CanvasPanelState.selectedTrendPointIndex:-1;
   if(!trend.hasData)
   {
      DrawRaisedCard(CanvasPanelLayout.trendEmptyState,SURFACE_CONTAINER,CanvasPanelMetrics.radiusCard,UI_SEVERITY_INFO);
      int emptyTitleH=CanvasScalePx(30);
      int emptyCaptionH=CanvasScalePx(26);
      int emptyTextGap=CanvasScalePx(2);
      int emptyTextY=CanvasPanelLayout.trendEmptyState.y+
                     (CanvasPanelLayout.trendEmptyState.h-emptyTitleH-emptyTextGap-emptyCaptionH)/2;
      UIRect emptyTitle=MakeUIRect(CanvasPanelLayout.trendEmptyState.x+CanvasPanelMetrics.space16,emptyTextY,
                                  CanvasPanelLayout.trendEmptyState.w-CanvasPanelMetrics.space16*2,emptyTitleH);
      UIRect emptyCaption=MakeUIRect(emptyTitle.x,emptyTitle.y+emptyTitleH+emptyTextGap,emptyTitle.w,emptyCaptionH);
      CanvasPanelRenderer.TextCenter(emptyTitle,"当前统计范围内暂无已平仓交易",CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      CanvasPanelRenderer.TextCenter(emptyCaption,"切换周期、日期或筛选后可查看对应走势",CanvasThemeDim(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   }
   else
   {
      TrendAxisRenderData axisData;
      TrendAxisRenderStyle axisStyle;
      BuildTrendAxisRenderData(trend,axisData);
      ResolveSharedTrendAxisStyle(axisData,
                                  CanvasPanelLayout.trendCurveAxisY,CanvasPanelLayout.trendCurvePlotInner,
                                  CanvasPanelLayout.trendBarsAxisY,CanvasPanelLayout.trendBarsPlotInner,
                                  axisStyle);
      DrawSurface(CanvasPanelLayout.trendCurveCard,SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
      RenderSectionTitle(CanvasPanelLayout.trendCurveTitle,"累计净收益");
      RenderTrendEquityCurve(CanvasPanelLayout.trendCurveAxisY,CanvasPanelLayout.trendCurvePlotInner,CanvasPanelLayout.trendCurveAxisX,
                             trend,axisData,axisStyle,selectedIndex);
      DrawSurface(CanvasPanelLayout.trendBarsCard,SURFACE_CONTAINER,CanvasPanelMetrics.radiusContainer,true,true,true);
      RenderSectionTitle(CanvasPanelLayout.trendBarsTitle,"每笔盈亏");
      RenderTrendProfitBars(CanvasPanelLayout.trendBarsAxisY,CanvasPanelLayout.trendBarsPlotInner,CanvasPanelLayout.trendBarsAxisX,
                            trend,axisData,axisStyle,selectedIndex);
   }
   DrawSurface(CanvasPanelLayout.trendSelectionPanel,SURFACE_TOOLBAR,CanvasPanelMetrics.radiusButton,true,false,true);
   int pointCount=ArraySize(trend.points);
   bool selectionValid=(CanvasPanelState.trendSelectionValid && selectedIndex>=0 && selectedIndex<pointCount);
   bool reviewEnabled=false;
   if(selectionValid)
   {
      TrendTradePoint point=trend.points[selectedIndex];
      string line1="第 "+IntegerToString(selectedIndex+1)+" / "+IntegerToString(pointCount)+" 笔 · "+FormatTrendSelectionTime(point.closeTime);
      CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.trendSelectionLine1,line1,CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      if(StringLen(CanvasPanelState.trendSelectionMessage)>0)
         CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.trendSelectionLine2,CanvasPanelState.trendSelectionMessage,CanvasThemeWarning(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      else
         RenderTrendSelectionValues(CanvasPanelLayout.trendSelectionLine2,point);
       reviewEnabled=CanvasSelectedTrendReviewAvailable();
   }
   else
   {
      CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.trendSelectionLine1,trend.statusText,CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      string line2=StringLen(CanvasPanelState.trendSelectionMessage)>0?CanvasPanelState.trendSelectionMessage:"点击折线或柱子可查看单笔数据";
      CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.trendSelectionLine2,line2,StringLen(CanvasPanelState.trendSelectionMessage)>0?CanvasThemeWarning():CanvasThemeDim(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   }
    DrawCanvasButton(CanvasPanelLayout.trendReviewButton,"查看复盘",reviewEnabled?CONTROL_SELECTED:CONTROL_DISABLED);
}

void RenderStatsReview(const StatsPanelViewModel &model)
{
   int count=ArraySize(model.reviews);
   DrawSurface(CanvasPanelLayout.reviewNav,SURFACE_TOOLBAR,CanvasPanelMetrics.radiusButton,true,false,true);
   if(count<=0)
   {
      CanvasPanelRenderer.TextLeft(CanvasPanelLayout.reviewNav,"复盘 0 / 0",CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontBody,CanvasScalePx(8));
      DrawRaisedCard(CanvasPanelLayout.reviewSummary,SURFACE_CONTAINER,CanvasPanelMetrics.radiusCard,UI_SEVERITY_INFO);
      CanvasPanelRenderer.TextCenter(CanvasPanelLayout.reviewSummaryRows[0],"当前筛选和周期内没有可复盘的完整托管单",CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
      CanvasPanelRenderer.TextCenter(CanvasPanelLayout.reviewSummaryRows[1],"仅读取已结算完整档案，不补造旧历史管理过程",CanvasThemeDim(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
      return;
   }
   CanvasPanelState.reviewIndex=MathMax(0,MathMin(CanvasPanelState.reviewIndex,count-1));
   当前复盘序号=CanvasPanelState.reviewIndex;
   LifecycleReviewItem item=model.reviews[CanvasPanelState.reviewIndex];
   int holdMinutes=item.closeTime>item.openTime?(int)((item.closeTime-item.openTime)/60):0;
   string insight;
   color ignoredColor;
   GetLifecycleReviewInsight(item,insight,ignoredColor);
   PrefixLifecycleReviewTimingCoverage(item,insight);
   UIRect reviewNavTitle=MakeUIRect(CanvasPanelLayout.reviewNav.x,CanvasPanelLayout.reviewNav.y,MathMax(CanvasPanelLayout.reviewPrev.x-CanvasPanelLayout.reviewNav.x-CanvasScalePx(6),1),CanvasPanelLayout.reviewNav.h);
   CanvasPanelRenderer.TextLeft(reviewNavTitle,StringFormat("复盘 %d / %d    #%I64u",CanvasPanelState.reviewIndex+1,count,item.positionId),CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody,CanvasPanelMetrics.space10);
   DrawCanvasButton(CanvasPanelLayout.reviewPrev,"‹ 上一单",CanvasPanelState.reviewIndex<count-1?CONTROL_NORMAL:CONTROL_DISABLED);
   DrawCanvasButton(CanvasPanelLayout.reviewNext,"下一单 ›",CanvasPanelState.reviewIndex>0?CONTROL_NORMAL:CONTROL_DISABLED);

   DrawRaisedCard(CanvasPanelLayout.reviewSummary,SURFACE_CARD_RAISED,CanvasPanelMetrics.radiusCard);
   DrawColorEdge(CanvasPanelLayout.reviewSummary,CanvasPnLColor(item.net),CanvasPanelMetrics.space2,true);
   uint directionColor=CanvasDirectionColor(item.direction==POSITION_TYPE_BUY);
   string rText=item.initialRMoney>0.0?LifecycleStatsSignedR(item.realizedR):"R 未记录";
   uint rColor=item.initialRMoney<=0.0?CanvasThemeWarning():CanvasPnLColor(item.realizedR);
   CanvasPanelRenderer.TextLeft(CanvasPanelLayout.reviewDirection,LifecycleReviewDirectionText(item.direction),directionColor,CanvasResolvedFont,CanvasPanelMetrics.fontHeader);
   CanvasPanelRenderer.TextLeft(CanvasPanelLayout.reviewVolume,DoubleToString(item.entryVolume,2)+" 手",CanvasThemeText(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
   CanvasPanelRenderer.TextRight(CanvasPanelLayout.reviewNetLabel,"净收益",CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);
   CanvasPanelRenderer.TextRight(CanvasPanelLayout.reviewNetValue,LifecycleStatsSignedMoney(item.net),CanvasPnLColor(item.net),CanvasResolvedFont,CanvasPanelMetrics.fontHeader);
   CanvasPanelRenderer.TextRight(CanvasPanelLayout.reviewRValue,rText,rColor,CanvasResolvedFont,CanvasPanelMetrics.fontBody);
   CanvasPanelRenderer.TextRight(CanvasPanelLayout.reviewDuration,"持有 "+FormatHoldMinutes(holdMinutes,false),CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontBody);
   CanvasPanelRenderer.TextLeft(CanvasPanelLayout.reviewTimeRange,"北京时间: "+FormatBeijingTime(item.openTime)+" → "+FormatBeijingTime(item.closeTime),CanvasThemeMuted(),CanvasResolvedFont,CanvasPanelMetrics.fontCaption);

   DrawSurface(CanvasPanelLayout.reviewPrice,SURFACE_CARD,CanvasPanelMetrics.radiusCard,true,true,true);
   DrawSurface(CanvasPanelLayout.reviewClassification,SURFACE_CARD,CanvasPanelMetrics.radiusCard,true,true,true);
   RenderSectionTitle(CanvasPanelLayout.reviewPriceTitle,"价格与风险");
   RenderSectionTitle(CanvasPanelLayout.reviewClassificationTitle,"分类与结果");
   string priceLabels[4]={"进场","平仓","初始 SL","风险金额"};
   string priceValues[4]={DoubleToString(item.entryPrice,_Digits),DoubleToString(item.exitPrice,_Digits),item.initialSL>0.0?DoubleToString(item.initialSL,_Digits):"未记录",DoubleToString(item.initialRMoney,2)};
   uint priceColors[4]={CanvasPanelTheme.infoText,CanvasThemeText(),item.initialSL>0.0?CanvasThemeMuted():CanvasThemeDanger(),item.initialRMoney>0.0?CanvasThemeMuted():CanvasThemeWarning()};
   double reviewHighestProfit=LifecycleReviewHighestFloatingProfit(item);
   double reviewMaximumLoss=LifecycleReviewMaximumFloatingLoss(item);
   string classLabels[4]={"模板","类型","最高浮盈","最大浮亏"};
   string classValues[4]={CanvasTemplateName(item.templateId),LifecycleStatsArchetypeText(item.archetype),LifecycleStatsSignedMoney(reviewHighestProfit),LifecycleStatsSignedMoney(-reviewMaximumLoss)};
   uint classColors[4]={CanvasPanelTheme.infoText,CanvasThemeMuted(),reviewHighestProfit>0.005?CanvasThemeProfit():CanvasThemeMuted(),reviewMaximumLoss>0.005?CanvasThemeLoss():CanvasThemeMuted()};
   for(int i=0;i<4;i++)
   {
      RenderStatsKeyValue(CanvasPanelLayout.reviewPriceRows[i],priceLabels[i],priceValues[i],priceColors[i],(i%2)==1);
      RenderStatsKeyValue(CanvasPanelLayout.reviewClassRows[i],classLabels[i],classValues[i],classColors[i],(i%2)==1);
   }

   DrawSurface(CanvasPanelLayout.reviewManagement,SURFACE_CARD_RAISED,CanvasPanelMetrics.radiusContainer,true,true,true);
   RenderSectionTitle(CanvasPanelLayout.reviewManagementTitle,"管理过程");
   string profitDurationText="未记录";
   string lossDurationText="未记录";
   string firstProfitText="未记录";
   string longestLossText="未记录";
   if(item.floatingTimingHasData && item.floatingTimingObservedSeconds>0.0)
   {
      profitDurationText=FormatReviewDurationWithRatio(item.floatingProfitSeconds,item.floatingTimingObservedSeconds);
      lossDurationText=FormatReviewDurationWithRatio(item.floatingLossSeconds,item.floatingTimingObservedSeconds);
      firstProfitText=FormatFirstProfitTiming(item);
      longestLossText=FormatReviewDuration(item.longestFloatingLossSeconds);
   }
   string manageLabels[8]={"分批退出","浮盈时长","SL 调整","浮亏时长","TP 调整","首次观测浮盈","实际退出","最长浮亏"};
   string manageValues[8]={IntegerToString(item.partialFills)+"次",profitDurationText,IntegerToString(item.slModifyCount)+"次",lossDurationText,
                           IntegerToString(item.tpModifyCount)+"次",firstProfitText,LifecycleReviewActualExitText(item.actualExitReason),longestLossText};
   uint firstProfitColor=CanvasThemeMuted();
   if(item.floatingTimingHasData && item.floatingTimingObservedSeconds>0.0)
      firstProfitColor=item.firstFloatingProfitTime>0?CanvasThemeSuccess():CanvasThemeLoss();
   uint manageColors[8]={CanvasThemeText(),item.floatingProfitSeconds>0.0?CanvasThemeProfit():CanvasThemeMuted(),
                         CanvasThemeText(),item.floatingLossSeconds>0.0?CanvasThemeLoss():CanvasThemeMuted(),
                         CanvasThemeText(),firstProfitColor,CanvasThemeText(),
                         item.longestFloatingLossSeconds>0.0?CanvasThemeLoss():CanvasThemeMuted()};
   for(int i=0;i<8;i++)
      RenderReviewFieldCell(CanvasPanelLayout.reviewManageCells[i],manageLabels[i],manageValues[i],manageColors[i],((i/2)%2)==1,false);

   RenderInsightBox(CanvasPanelLayout.reviewHint,"复盘提示",insight,item.initialRMoney>0.0?UI_SEVERITY_MUTED:UI_SEVERITY_WARNING);
}

void RenderStatsCanvasPanel(const PanelViewModel &model)
{
   CanvasPanelRenderer.Begin(CanvasThemeBackground());
   DrawSurface(CanvasPanelLayout.panel,SURFACE_ROOT,CanvasPanelMetrics.radiusContainer,true,false,true);
   RenderCanvasHeader();
   RenderStatsNavigation(model.stats);
   if(CanvasPanelState.statsDetail==统计详情_总览) RenderStatsOverview(model.stats);
   else if(CanvasPanelState.statsDetail==统计详情_策略) RenderStatsStrategy(model.stats);
   else if(CanvasPanelState.statsDetail==统计详情_走势) RenderStatsTrend(model.stats);
   else if(CanvasPanelState.statsDetail==统计详情_复盘) RenderStatsReview(model.stats);
   DrawSurface(CanvasPanelLayout.footer,SURFACE_HEADER,CanvasPanelMetrics.radiusButton,true,false,true);
   string footerText=model.stats.periodText+" · "+model.stats.rangeText+" · "+model.stats.filterText;
   uint footerColor=CanvasThemeMuted();
   if(CanvasPanelState.statsActionMessage!="")
   {
      footerText="提示："+CanvasPanelState.statsActionMessage;
      footerColor=CanvasThemeWarning();
   }
   CanvasPanelRenderer.TextEllipsized(CanvasPanelLayout.statsFooterText,footerText,footerColor,
                                      CanvasResolvedFont,CanvasPanelMetrics.fontCaption,0,CanvasPanelMetrics.space12);
   CanvasPanelRenderer.End();
   HideCanvasNewsButtons();
}

void ShowCanvasStatsPanel(void)
{
   SyncCanvasStateFromLegacy();
   MarkCanvasPanelDirty(PANEL_DIRTY_DATA|PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER);
   RefreshCanvasPanelByDirtyFlags(false);
}

bool CanvasCurrentViewModelValid(void)
{
   if(CanvasPanelState.displayMode==面板隐藏) return true;
   if(CanvasPanelState.displayMode==面板迷你) return CanvasMiniModelValid;
   if(CanvasPanelState.page==页面持仓) return CanvasHoldingModelValid;
   return CanvasStatsModelValid;
}

int CanvasCurrentLogicalHeight(void)
{
   if(CanvasPanelState.displayMode==面板隐藏) return 44;
   if(CanvasPanelState.displayMode==面板迷你) return MiniCanvasLogicalHeight(CanvasPanelModel);
   if(CanvasPanelState.page==页面持仓) return HoldingCanvasLogicalHeight(CanvasPanelModel.holding);
   return StatsCanvasLogicalHeight(CanvasPanelModel.stats);
}

bool RefreshCanvasPanelByDirtyFlags(bool force)
{
   ulong totalPerfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
   EnsureLegacyPanelObjectsClearedForCanvas();
   SyncCanvasStateFromLegacy();
   UpdateCanvasHeaderClockCache(true);

   if(force && (CanvasPanelDirty==PANEL_DIRTY_NONE || CanvasPanelDirty==PANEL_DIRTY_HEADER_CLOCK))
   {
      MarkCanvasPanelDirty(PANEL_DIRTY_RENDER);
      if(!CanvasCurrentViewModelValid()) MarkCanvasPanelDirty(PANEL_DIRTY_DATA);
      if(!CanvasPanelLayoutValid) MarkCanvasPanelDirty(PANEL_DIRTY_LAYOUT);
   }
   if(CanvasPanelDirty==PANEL_DIRTY_NONE) return false;

   int flags=CanvasPanelDirty;
   if(flags==PANEL_DIRTY_HEADER_CLOCK)
   {
      // 迷你标题栏当前不显示时钟，只保留最新缓存；展开时会直接使用最新秒值。
      if(CanvasPanelState.displayMode==面板迷你)
      {
         CanvasPanelDirty=PANEL_DIRTY_NONE;
         return false;
      }

      // 时钟单独变化时不计算尺寸、不重建ViewModel和HitRegion，只刷新可见标题栏。
      if(CanvasPanelLayoutValid && CanvasPanelRenderer.Alive(CanvasPanelMetrics.width,CanvasPanelMetrics.height))
      {
         if(CanvasPanelState.displayMode==面板隐藏)
            RenderHiddenCanvasPanel();
         else
         {
            CanvasPanelRenderer.BeginPartial();
            RenderCanvasHeader();
            CanvasPanelRenderer.End();
         }
         CanvasPanelDirty=PANEL_DIRTY_NONE;
         ChartRedraw(0);
         CanvasUIPerfStage("Header clock refresh",totalPerfStart,10000);
         return true;
      }

      // Canvas或布局失效时沿用现有自愈路径；正常逐秒刷新不会进入这里。
      flags|=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER;
      if(!CanvasCurrentViewModelValid()) flags|=PANEL_DIRTY_DATA;
      CanvasPanelDirty=flags;
   }
   if(CanvasPanelState.displayMode==面板迷你 && ((flags&PANEL_DIRTY_DATA)!=0 || !CanvasMiniModelValid))
   {
      BuildMiniPanelViewModel(CanvasPanelModel);
      CanvasMiniModelValid=true;
   }
   else if(CanvasPanelState.displayMode==面板完整 && CanvasPanelState.page==页面持仓 &&
           ((flags&PANEL_DIRTY_DATA)!=0 || !CanvasHoldingModelValid))
   {
      BuildHoldingPanelViewModel(CanvasPanelModel);
      CanvasHoldingModelValid=true;
   }
   else if(CanvasPanelState.displayMode==面板完整 && CanvasPanelState.page==页面今日 &&
            ((flags&PANEL_DIRTY_DATA)!=0 || !CanvasStatsModelValid))
   {
      bool needsReviews=(CanvasPanelState.statsDetail==统计详情_复盘 || CanvasPanelState.statsDetail==统计详情_走势);
      BuildStatsPanelViewModel(CanvasPanelModel,needsReviews,CanvasPanelState.statsDetail==统计详情_走势);
      CanvasStatsModelValid=true;
   }

   if(CanvasPanelState.displayMode==面板完整 && CanvasPanelState.page==页面今日 &&
      CanvasPanelState.statsDetail==统计详情_走势)
      ValidateCanvasTrendSelection(CanvasPanelModel.stats.trend);

   int oldWidth=CanvasPanelMetrics.width;
   int oldHeight=CanvasPanelMetrics.height;
   double oldDpi=CanvasPanelMetrics.dpiScale;
   CalculateCanvasMetrics(CanvasCurrentLogicalHeight());
   bool metricsChanged=(oldWidth!=CanvasPanelMetrics.width || oldHeight!=CanvasPanelMetrics.height ||
                        MathAbs(oldDpi-CanvasPanelMetrics.dpiScale)>0.0001);
   if(metricsChanged) flags|=PANEL_DIRTY_LAYOUT|PANEL_DIRTY_STYLE|PANEL_DIRTY_RENDER;

   if(!CanvasPanelRenderer.Ensure(CanvasPanelState.panelX,CanvasPanelState.panelY,CanvasPanelMetrics.width,CanvasPanelMetrics.height))
      return false;
   if(CanvasResolvedFont=="" || CanvasPanelRenderer.Recreated())
   {
      CanvasResolvedFont=ResolveCanvasUIFont();
      CanvasPanelMetrics.fontName=CanvasResolvedFont;
   }

   bool layoutNeeded=((flags&(PANEL_DIRTY_LAYOUT|PANEL_DIRTY_STYLE))!=0 || !CanvasPanelLayoutValid);
   if(layoutNeeded)
   {
      ulong layoutPerfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
      if(CanvasPanelState.displayMode==面板隐藏) CalculateHiddenCanvasPanelLayout();
      else if(CanvasPanelState.displayMode==面板迷你) CalculateMiniPanelLayout();
      else if(CanvasPanelState.page==页面持仓) CalculateHoldingPanelLayout();
      else CalculateStatsPanelLayout();
      CanvasPanelLayoutValid=true;
      CanvasUIPerfStage("Calculate layout",layoutPerfStart,20000);
   }

   bool renderNeeded=((flags&(PANEL_DIRTY_DATA|PANEL_DIRTY_LAYOUT|PANEL_DIRTY_STYLE|PANEL_DIRTY_RENDER))!=0);
   if(renderNeeded)
   {
      ulong renderPerfStart=CANVAS_UI_PERF_LOG?GetMicrosecondCount():0;
      if(CanvasPanelState.displayMode==面板隐藏)
      {
         RenderHiddenCanvasPanel();
         HideCanvasNewsButtons();
      }
      else if(CanvasPanelState.displayMode==面板迷你)
      {
         RenderMiniCanvasPanel(CanvasPanelModel);
         HideCanvasNewsButtons();
      }
      else if(CanvasPanelState.page==页面持仓)
         RenderHoldingCanvasPanel(CanvasPanelModel);
      else
         RenderStatsCanvasPanel(CanvasPanelModel);
      CanvasUIPerfStage("Render Canvas",renderPerfStart,20000);

      // 翻页会改变可用的上一页/下一页动作，只重建命中表，不重算布局或 ViewModel。
      if(CanvasPanelState.displayMode==面板隐藏) BuildHiddenCanvasHitRegions();
      else if(CanvasPanelState.displayMode==面板迷你) BuildMiniHitRegions();
      else if(CanvasPanelState.page==页面持仓) BuildHoldingHitRegions();
      else BuildStatsHitRegions();
   }

   CanvasPanelDirty=PANEL_DIRTY_NONE;
   CanvasLastChartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   CanvasLastChartHeight=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   CanvasLastDpiScale=CanvasPanelMetrics.dpiScale;
   if((flags&PANEL_DIRTY_DATA)!=0) 上次完整面板刷新毫秒=GetTickCount64();
   ChartRedraw(0);
   CanvasUIPerfStage("Total UI refresh",totalPerfStart,40000);
   return true;
}

#endif
