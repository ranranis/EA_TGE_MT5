// Run the actual editor UI with a tiny DOM; no local server mutations or external calls.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class Element{
 constructor(tag,text=''){this.tag=tag;this.text=text;this.children=[];this.classList={toggle(){}};}
 append(...nodes){this.children.push(...nodes);}
 replaceChildren(...nodes){this.children=[...nodes];}
 setAttribute(){}
 querySelectorAll(tags){return this.children.flatMap(n=>[...(tags.split(',').includes(n.tag)?[n]:[]),...n.querySelectorAll(tags)]);}
}
function setup(manual=false){
 const nodes=new Map(),get=id=>{if(!nodes.has(id))nodes.set(id,new Element('div'));return nodes.get(id);};
 const draft={mode:'merge',levels:manual?[{id:'p',price:4182,role:'sell',note:'',replaces:[4180]}]:[],
  disabled:[],inner_range:{action:'inherit'},outer_range:{action:'inherit'}};
 const auto={revision:'r1',rows:[['PLAN','one','DIRECT',90,'SELL','4180','teacher']]};
 const view={revision:0,draft,auto,saved:true,preview_rows:[],can_undo:false};
 const posts=[],x=vm.createContext({
  window:{},$ :get,el:(t,v)=>new Element(t,v),txt:(id,t)=>{get(id).text=t;},
  fmt:String,tm:String,latest:{point_editor:view,status:{online:true},point_lifecycle:{points:[]}},
  actionToken:'test',crypto:{randomUUID:()=> 'id'},setTimeout(){},refresh(){},confirm:()=>true,
  fetch:async(url,options)=>{
   const body=JSON.parse(options.body);posts.push(body);
   return {ok:true,json:async()=>({...view,revision:posts.length,draft:body.draft,auto})};
  }
 });
 vm.runInContext(fs.readFileSync('FeishuSignalMonitor/point-editor.js','utf8'),x);
 return {x,get,posts};
}
function button(box,text){const b=box.querySelectorAll('button').find(n=>n.text===text);assert(b,'missing button '+text);return b;}
(async()=>{
 let e=setup();button(e.get('pe-auto'),'删除').onclick();
 assert.equal(e.get('pe-auto').querySelectorAll('button').length,0);
 await e.get('pe-save').onclick();
 assert.deepEqual(e.posts[0].draft.deleted,[4180]);assert.deepEqual(e.posts[0].draft.disabled,[]);
 button(e.get('pe-deleted'),'4180 · 解除屏蔽').onclick();
 await e.get('pe-save').onclick();assert.deepEqual(e.posts[1].draft.deleted,[]);
 assert(button(e.get('pe-auto'),'删除'));
 e=setup(true);button(e.get('pe-levels'),'删除').onclick();await e.get('pe-save').onclick();
 assert.deepEqual(e.posts[0].draft.levels,[]);assert.deepEqual(e.posts[0].draft.deleted.sort(),[4180,4182]);
 assert(button(e.get('pe-deleted'),'4180 · 解除屏蔽'));
 console.log('PASS 自动点位删除入口、删除不重现、解除屏蔽、手动改价连同原价屏蔽；未发真实请求');
})().catch(e=>{console.error(e);process.exitCode=1;});
