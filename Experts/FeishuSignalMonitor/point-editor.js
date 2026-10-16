/* 手动草稿留在编辑区；快照刷新只更新自动来源和已发布信息，不抢走输入焦点。 */
(() => {
 const roles={buy:'做多 ↑',sell:'做空 ↓',support:'支撑 ↑',resistance:'压力 ↓',minor_support:'小支撑 ↑',minor_resistance:'小压力 ↓',neutral:'中性参考',watch:'仅展示 · 不交易'};
 let draft=null,revision=0,dirty=false,busy=false,view=null,parsed=null,autoSeen='',remoteConflict=false;
 const clone=v=>JSON.parse(JSON.stringify(v)),uid=()=>crypto.randomUUID().replaceAll('-','');
 const button=(label,fn)=>{const b=el('button',label);b.type='button';b.onclick=fn;return b;};
 const roleOf=r=>r[2]==='DIRECT'?(r[4]==='BUY'?'buy':'sell'):r[2]==='ROLE'?(Number(r[3])===55?'minor_':'')+(r[4]==='BUY'?'support':'resistance'):r[2]==='WATCH'?'watch':'neutral';
 const label=r=>`${fmt(Number(r[5]))} · ${r[2]==='INNER'?'小区间':r[2]==='OUTER'?'大区间':roles[roleOf(r)]}${['INNER','OUTER'].includes(r[2])?(r[4]==='BUY'?'下沿 ↑':'上沿 ↓'):''}`;
 const changed=()=>{dirty=true;txt('pe-status','有未保存修改；当前执行清单尚未改变。');controls();};
 function controls(){
  $('pe-save').disabled=busy||remoteConflict||!draft;
  $('pe-apply').disabled=busy||dirty||remoteConflict||!view?.saved||!view?.auto?.revision||!!view?.preview_error||!latest?.status?.online||!!latest?.status?.paused;
  $('pe-undo').disabled=busy||dirty||remoteConflict||!view?.can_undo;
  $('pe-parse').disabled=busy;$('pe-use-parse').disabled=busy||!parsed;
  for(const id of ['pe-mode','pe-add','pe-reload','pe-text'])$(id).disabled=busy;
  for(const box of ['pe-auto','pe-levels','pe-disabled','pe-deleted','pe-bands'])for(const e of $(box).querySelectorAll('input,select,button'))e.disabled=busy;
 }
 function removePrice(price,replaces=[]){
  const targets=new Set([price,...replaces].filter(v=>Number.isFinite(v)&&v>0));
  draft.levels=draft.levels.filter(p=>!targets.has(p.price)&&!p.replaces.some(v=>targets.has(v)));
  draft.disabled=draft.disabled.filter(p=>!targets.has(p));
  draft.deleted=[...new Set([...(draft.deleted||[]),...targets])];
  if(draft.mode==='auto')draft.mode='merge';
  changed();editRows();renderAuto();
 }
 function editRows(){
  draft.deleted??=[];
  $('pe-mode').value=draft.mode;
  const box=$('pe-levels');box.replaceChildren();
  for(const p of draft.levels){
   const row=el('div',undefined,'pe-row'),price=el('input'),role=el('select'),note=el('input');
   price.type='number';price.step='0.01';price.value=p.price||'';price.setAttribute('aria-label','完整价格');
   price.oninput=()=>{p.price=price.value===''?null:Number(price.value);changed();};
   for(const [value,text] of Object.entries(roles)){const o=el('option',text);o.value=value;role.append(o);}role.value=p.role;
   role.setAttribute('aria-label','点位作用');role.onchange=()=>{p.role=role.value;changed();};
   note.value=p.note;note.placeholder='备注 / 原文依据';note.maxLength=200;note.className='pe-note';note.setAttribute('aria-label','备注');
   note.oninput=()=>{p.note=note.value;changed();};
   row.append(price,role,button('删除',()=>{draft.levels=draft.levels.filter(v=>v.id!==p.id);removePrice(p.price,p.replaces);}),note,
     el('small',p.replaces.length?'替换原价格：'+p.replaces.map(fmt).join(' / '):'手动补充；同价自动候选会被此项替换'));
   if(p.replaces.length)row.append(button('恢复自动',()=>{draft.levels=draft.levels.filter(v=>v.id!==p.id);changed();editRows();renderAuto();}));
   const life=el('label','有效期（小时）'),hours=el('input');hours.type='number';hours.min=1;hours.max=720;hours.value=p.hours??24;
   hours.oninput=()=>{p.hours=Number(hours.value);changed();};life.append(hours);
   row.append(life,button(p.renew?'已选择重新确认':'重新确认此点',()=>{p.renew=!p.renew;changed();editRows();}));
   box.append(row);
  }
  if(!draft.levels.length)box.append(el('p','尚无手动修正，可在左侧修改或直接添加。','muted'));
  $('pe-disabled').replaceChildren(...draft.disabled.map(p=>button(fmt(p)+' · 恢复自动',()=>{draft.disabled=draft.disabled.filter(v=>v!==p);changed();editRows();renderAuto();})));
  $('pe-deleted').replaceChildren(...draft.deleted.map(p=>button(fmt(p)+' · 解除屏蔽',()=>{
   draft.deleted=draft.deleted.filter(v=>v!==p);changed();editRows();renderAuto();
  })));
  const bands=$('pe-bands');bands.replaceChildren();
  for(const [key,name] of [['inner_range','小区间'],['outer_range','大区间']]){
   const row=el('div',undefined,'pe-band'),select=el('select');row.append(el('h3',name));
   for(const [value,text] of [['inherit','跟随自动（全手动模式下不继承）'],['replace','手动指定'],['off','停用这个区间']]){const o=el('option',text);o.value=value;select.append(o);}
   select.value=draft[key].action;select.setAttribute('aria-label',name+'来源');select.onchange=()=>{draft[key]=select.value==='replace'?{action:'replace',low:null,high:null}:{action:select.value};changed();editRows();};row.append(select);
   if(draft[key].action==='replace')for(const [edge,text] of [['low','下沿做多 ↑'],['high','上沿做空 ↓']]){
    const lab=el('label',text),input=el('input');input.type='number';input.step='.01';input.value=draft[key][edge]??'';input.setAttribute('aria-label',name+text);
    input.oninput=()=>{draft[key][edge]=input.value===''?null:Number(input.value);changed();};lab.append(input);row.append(lab);
   }
   if(draft[key].action==='replace'){
    const lab=el('label','有效期（小时）'),hours=el('input');hours.type='number';hours.min=1;hours.max=720;hours.value=draft[key].hours??24;
    hours.oninput=()=>{draft[key].hours=Number(hours.value);changed();};lab.append(hours);row.append(lab,button(draft[key].renew?'已选择重新确认':'重新确认区间',()=>{draft[key].renew=!draft[key].renew;changed();editRows();}));
   }
   bands.append(row);
  }
  controls();
 }
 function renderAuto(){
  const box=$('pe-auto');box.replaceChildren();const table=el('table',undefined,'pe-table'),groups=new Map();
  for(const r of view?.auto?.rows||[]){const price=Number(r[5]);if(!groups.has(price))groups.set(price,[]);groups.get(price).push(r);}
  for(const [price,rows] of [...groups].sort((a,b)=>a[0]-b[0])){
   if((draft.deleted||[]).includes(price))continue;
   rows.sort((a,b)=>Number(b[3])-Number(a[3]));const r=rows[0],tr=el('tr'),actions=el('td');
   const overridden=draft.levels.some(p=>p.price===price||p.replaces.includes(price)),disabled=draft.disabled.includes(price);
   tr.append(el('td',fmt(price)),el('td',rows.map(label).map(s=>s.split(' · ').slice(1).join(' · ')).join(' / ')+(disabled?' · 已停用':overridden?' · 已手动修正':'')));
   actions.append(button('修改',()=>{
    const existing=draft.levels.find(p=>p.price===price||p.replaces.includes(price));
    if(existing){txt('pe-status','右侧已有这条修正，请直接编辑。');return;}
    draft.disabled=draft.disabled.filter(v=>v!==price);draft.levels.push({id:uid(),price,role:roleOf(r),note:'',replaces:[price]});if(draft.mode==='auto')draft.mode='merge';changed();editRows();renderAuto();
   }),button(disabled?'恢复':'停用',()=>{
    if(disabled)draft.disabled=draft.disabled.filter(v=>v!==price);
    else{if(overridden){txt('pe-status','请先移除对应手动修正，再停用原价格。');return;}draft.disabled.push(price);}
    if(draft.mode==='auto')draft.mode='merge';changed();editRows();renderAuto();
   }),button('删除',()=>removePrice(price)));
   const life=(latest?.point_lifecycle?.points||[]).find(p=>p.price===price);
   if(life){
    const details=el('details'),summary=el('summary',life.reason+' · 来源记录');details.append(summary);
    for(const source of life.sources||[])details.append(el('p',source.kind+' / '+source.side+' · '+tm(source.confirmed)+' · 到期 '+(source.expires?tm(source.expires):'仅观察')+' · '+source.reason+' · '+source.text));
    for(const event of (latest?.point_lifecycle?.events||[]).filter(e=>e.price===price).slice(-8).reverse())details.append(el('p',tm(event.at)+' · '+event.reason));
    actions.append(details);
   }
   tr.append(actions);table.append(tr);
  }
  box.append(table);if(!groups.size)box.append(el('p','尚无自动点位；可添加手动点位。','muted'));controls();
 }
 function preview(){
  $('pe-preview').replaceChildren(...(view.preview_rows||[]).map(r=>el('span',label(r)+(r[6]==='MANUAL'?' · 手动':''),'pe-chip')));
  const encode=p=>[p.kind,p.side,Number(p.price)].join('|');
  const before=new Set((latest?.execution_reference?.plans||[]).map(encode));
  const after=new Set((view.preview_rows||[]).map(r=>encode({kind:r[2],side:r[4],price:r[5]})));
  const add=[...after].filter(v=>!before.has(v)).length,remove=[...before].filter(v=>!after.has(v)).length;
  txt('pe-diff',view.preview_error||`相对当前导出：新增/改后 ${add} 项，移除/改前 ${remove} 项。下方是完整应用预览。`);
 }
 window.renderPointEditor=d=>{
  const next=d.point_editor;if(!next)return;view=next;
  if(draft===null){draft=clone(next.draft);draft.deleted??=[];revision=next.revision;editRows();}
  remoteConflict=next.revision!==revision;
  txt('pe-badge',dirty?'未保存草稿':remoteConflict?'另一页面已修改':'草稿已载入');
  txt('pe-source',remoteConflict?'另一页面已修改，请重新载入后操作。':next.changed?'自动点位已有新版本。你的手动修正仍保留；核对左侧新来源后，可保留修正应用，或逐条恢复自动。':!next.initialized?'首次应用网页清单后，将接管旧手动文件入口；目前执行计划不变。':`当前已应用：${{auto:'全部自动',merge:'自动＋手动修正',manual:'全部手动'}[next.applied?.draft.mode]} · ${tm(next.applied?.at)}`);
  $('pe-source').classList.toggle('pe-warn',next.changed||remoteConflict);
  const stamp=(next.auto?.revision||'')+JSON.stringify(d.point_lifecycle?.points||[]);if(autoSeen!==stamp){autoSeen=stamp;renderAuto();}
  preview();controls();
 };
 async function post(url,body){const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','X-Local-Token':actionToken},body:JSON.stringify(body)});const result=await r.json();if(!r.ok)throw Error(result.error||'操作失败');return result;}
 async function action(kind){
  if(busy)return;
  if(kind!=='save'&&(dirty||remoteConflict)){txt('pe-status','请先保存草稿或重新载入。');return;}
  if(kind!=='save'&&!confirm(kind==='undo'?'撤销上次应用，恢复之前的模式和手动修正。交易模式下可能影响新开仓。确认？':'将发布上方完整清单，交易模式下可能真实下单。确认应用？'))return;
  busy=true;controls();
  try{
   const payload=kind==='save'?{action:kind,revision,draft}:{action:kind,revision,auto_revision:view.auto.revision,confirmed:true};
   const result=await post('/api/points',payload);revision=result.revision;view=result;draft=clone(result.draft);dirty=false;remoteConflict=false;
   txt('pe-badge','草稿已保存');
   if(latest)latest.point_editor=result;editRows();renderAuto();preview();
   txt('pe-status',kind==='save'?'草稿已保存；核对完整清单后点击“应用到EA”。':'已保存应用版本，等待下一次导出；下方发布区显示实际结果，不代表成交。');
   setTimeout(refresh,1000);
  }catch(e){txt('pe-status',e.message);}finally{busy=false;controls();}
 }
 $('pe-mode').onchange=()=>{draft.mode=$('pe-mode').value;changed();};
 $('pe-add').onclick=()=>{draft.levels.push({id:uid(),price:null,role:'neutral',note:'',replaces:[]});if(draft.mode==='auto')draft.mode='merge';changed();editRows();};
 $('pe-reload').onclick=()=>{if(dirty&&!confirm('放弃未保存输入，重新载入服务器草稿？'))return;draft=clone(view.draft);revision=view.revision;dirty=false;remoteConflict=false;editRows();renderAuto();txt('pe-status','已重新载入草稿。');};
 $('pe-save').onclick=()=>action('save');$('pe-apply').onclick=()=>action('apply');$('pe-undo').onclick=()=>action('undo');
 $('pe-parse').onclick=async()=>{
  if(busy)return;busy=true;parsed=null;controls();txt('pe-status','DeepSeek正在整理粘贴内容；现有计划不变。');
  try{const result=await post('/api/points-parse',{text:$('pe-text').value});parsed=result.draft;
   $('pe-parsed').replaceChildren(...parsed.levels.map(p=>el('p',`${fmt(p.price)} · ${roles[p.role]} · ${p.note}`)));
   for(const [k,n] of [['inner_range','小区间'],['outer_range','大区间']])if(parsed[k].action==='replace')$('pe-parsed').append(el('p',`${n} ${fmt(parsed[k].low)}—${fmt(parsed[k].high)}`));
   txt('pe-status','整理完成；核对后加入编辑区，再保存和应用。');
  }catch(e){txt('pe-status',e.message);}finally{busy=false;controls();}
 };
 $('pe-use-parse').onclick=()=>{
  if(!parsed)return;
  const duplicate=parsed.levels.some(p=>draft.levels.some(v=>v.price===p.price));
  if(duplicate){txt('pe-status','解析结果含编辑区已有价格，请先修改或删除重复项再加入，避免覆盖。');return;}
  for(const k of ['inner_range','outer_range'])if(parsed[k].action==='replace'&&draft[k].action!=='inherit'){
   txt('pe-status','编辑区已有手动区间，请先设为跟随自动，再加入解析区间。');return;
  }
  draft.levels.push(...clone(parsed.levels));for(const k of ['inner_range','outer_range'])if(parsed[k].action==='replace')draft[k]=clone(parsed[k]);
  if(draft.mode==='auto')draft.mode='merge';parsed=null;changed();editRows();renderAuto();
 };
 if(latest)window.renderPointEditor(latest);
})();
