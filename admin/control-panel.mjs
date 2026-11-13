import {bucketActivity} from './charts.mjs';
export const DEFAULT_PALETTE={background:'#060608',surface:'#101013',surfaceAlt:'#18181C',border:'#26262C',textPrimary:'#F5F6F8',textSecondary:'#9296A0',accent:'#FFFFFF',danger:'#E5484D'};
const luminance=hex=>{const c=hex.slice(1).match(/../g).map(x=>parseInt(x,16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4);return c[0]*.2126+c[1]*.7152+c[2]*.0722;};
export function validateThemeConfig(raw){
 const value=typeof raw==='string'?JSON.parse(raw):raw;
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!['schemaVersion','name','palette','decoration','headerLabel'].includes(k)))throw Error('Only schemaVersion, name, palette, decoration and headerLabel are supported');
 if(value.schemaVersion!==1||typeof value.name!=='string'||!value.name.trim()||value.name.length>60)throw Error('Use schemaVersion: 1 and a name of 1–60 characters');
 if(!value.palette||typeof value.palette!=='object'||Array.isArray(value.palette)||Object.entries(value.palette).some(([k,v])=>!Object.hasOwn(DEFAULT_PALETTE,k)||typeof v!=='string'||!/^#[0-9a-fA-F]{6}$/.test(v)))throw Error('Use only supported palette keys and #RRGGBB colours');
 const palette={...DEFAULT_PALETTE,...value.palette};
 if((luminance(palette.textPrimary)+.05)/(luminance(palette.background)+.05)<4.5)throw Error('Use a dark background and readable light text (4.5:1 contrast)');
 const decoration=value.decoration??'none',headerLabel=value.headerLabel??'';
 if(!['none','christmas','diwali'].includes(decoration)||typeof headerLabel!=='string'||headerLabel.length>80)throw Error('Invalid decoration or header label');
 return {schemaVersion:1,name:value.name.trim(),palette,decoration,headerLabel};
}
const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function initControlPanel({$,api,collection,fieldsOf,unpackDoc,dispatch,getSession,refresh}){
 let saved=new Map(),loadedFor='',jobTimer=null;
 async function write(path,fields){
  await api(':commit',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({writes:[{update:{name:`projects/max-player-cd43d/databases/(default)/documents/${path}`,fields:Object.fromEntries(Object.entries(fields).map(([k,v])=>[k,fieldsOf(v)]))},updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]})});
 }
 function preview(){const theme=validateThemeConfig($('themeCode').value),host=$('themePreview');host.replaceChildren();host.style.background=theme.palette.background;host.style.color=theme.palette.textPrimary;host.style.borderColor=theme.palette.accent;const title=document.createElement('strong'),body=document.createElement('p');title.textContent=theme.name;title.style.color=theme.palette.accent;body.textContent=(theme.decoration==='christmas'?'❄ ':theme.decoration==='diwali'?'✦ ':'')+(theme.headerLabel||'App theme preview');host.append(title,body);return theme;}
 async function loadSaved(){if(!getSession())return;const docs=await collection('themes');saved=new Map(docs.map(d=>{const t=unpackDoc(d);return[t.id,t];}));$('themeList').replaceChildren(new Option('Choose a saved theme',''));for(const [id,t]of saved)$('themeList').add(new Option(t.name,id));loadedFor=getSession()?.uid;}
 async function run(action){try{await action();}catch(e){$('themeStatus').textContent=e.message;}}
 $('loadPreset').onclick=()=>{
  const christmas=$('themePreset').value==='christmas';
  $('themeCode').value=JSON.stringify({schemaVersion:1,name:christmas?'Christmas':'Diwali',palette:christmas?{background:'#081810',surface:'#10251B',surfaceAlt:'#173322',border:'#32533D',accent:'#FFD98A',textPrimary:'#FFF8E8',textSecondary:'#C6D8C9'}:{background:'#160D08',surface:'#25180F',surfaceAlt:'#332217',border:'#65462B',accent:'#FFC75A',textPrimary:'#FFF4DB',textSecondary:'#D6BFA1'},decoration:christmas?'christmas':'diwali',headerLabel:christmas?'Merry Christmas':'Happy Diwali'},null,2);
  try{preview();$('themeStatus').textContent='Preset loaded. Edit, Save and Publish when ready.';}catch(e){$('themeStatus').textContent=e.message;}
 };
 $('validateTheme').onclick=()=>run(async()=>{preview();$('themeStatus').textContent='JSON valid. Preview is illustrative; native app components retain their layouts.';});
 $('saveTheme').onclick=()=>run(async()=>{const theme=preview(),id=$('themeList').value||crypto.randomUUID();await write('themes/'+id,{name:theme.name,config:theme});await loadSaved();$('themeList').value=id;$('themeStatus').textContent='Saved '+theme.name+'. Save does not publish.';});
 $('loadTheme').onclick=()=>run(async()=>{if(!saved.size)await loadSaved();const theme=saved.get($('themeList').value);if(!theme)throw Error('Choose a saved theme');$('themeCode').value=JSON.stringify(theme.config,null,2);preview();});
 $('publishTheme').onclick=()=>run(async()=>{const theme=preview();if(!confirm('Publish '+theme.name+' to all compatible +72 apps?'))return;await write('appConfig/theme',{enabled:true,theme});$('themeStatus').textContent='Published '+theme.name+'. Online +72 apps update through Firestore; offline apps keep their cached theme.';});
 $('defaultTheme').onclick=()=>run(async()=>{if(!confirm('Switch compatible apps back to Default?'))return;await write('appConfig/theme',{enabled:false});$('themeStatus').textContent='Default published. Apps restore their normal palette and user-selected accent when connected.';});
 window.addEventListener('max-admin-open',()=>{void run(loadSaved);const id=sessionStorage.getItem('max.reset.pending');if(id)void pollJob(id);});
 $('themes').addEventListener('pointerenter',()=>{if(getSession()&&loadedFor!==getSession().uid)void run(loadSaved);});
 $('themeList').addEventListener('focus',()=>{if(getSession()&&loadedFor!==getSession().uid)void run(loadSaved);});
 async function pollJob(id){
  if(!getSession())return;
  try{const job=unpackDoc(await api('adminJobs/'+id));$('resetStatus').textContent=`${job.status}: ${job.message||job.error||'Waiting for workflow'}`;if(['sent','done','failed','partial'].includes(job.status)){sessionStorage.removeItem('max.reset.pending');void refresh();return;}}catch(e){$('resetStatus').textContent=e.message;}
  jobTimer=setTimeout(()=>void pollJob(id),10000);
 }
 $('resetAnalytics').onclick=async()=>{
  const button=$('resetAnalytics');button.disabled=true;
  try{
   if($('resetConfirm').value!=='RESET ANALYTICS')throw Error('Type RESET ANALYTICS exactly');
   if(!confirm('Permanently delete analytics counters and error reports? Admins, device tokens, notices and themes are preserved. Export first.'))return;
   const id=sessionStorage.getItem('max.reset.pending')||crypto.randomUUID();
   const fields={action:'resetAnalytics',status:'pending',confirmation:'RESET ANALYTICS',actor:getSession().uid};
   sessionStorage.setItem('max.reset.pending',id);
   try{await api(':commit',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({writes:[{update:{name:`projects/max-player-cd43d/databases/(default)/documents/adminJobs/${id}`,fields:Object.fromEntries(Object.entries(fields).map(([k,v])=>[k,fieldsOf(v)]))},currentDocument:{exists:false},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'}]}]})});}
   catch(e){try{await api('adminJobs/'+id);}catch{throw Error(e.message+' The same reset ID is saved; retry checks it instead of creating another.');}}
   $('resetConfirm').value='';$('resetStatus').textContent='Reset queued. Requesting trusted workflow…';try{await dispatch();}catch(e){$('resetStatus').textContent='Reset queued; '+e.message;}
   clearTimeout(jobTimer);void pollJob(id);
  }catch(e){$('resetStatus').textContent=e.message;}finally{button.disabled=false;}
 };
}

export async function exportDetailedReport({$,api,collection,unpackDoc,periodRows,FEATURE_NAMES,plot,ipCountries,num,countryName}){
 const win=window.open('','_blank');if(!win){alert('Allow popups to export');return;}
 win.document.write('<!doctype html><title>Preparing report</title><p>Fetching all stored analytics and error reports… Keep this tab open.</p>');
 const button=$('pdfBtn');button.disabled=true;let chartHost=null;
 try{
  const [stats,reports]=await Promise.all([collection('stats'),collection('reports')]);
  const freshDaily=new Map(stats.filter(d=>d.name.split('/').pop().startsWith('daily_')).map(d=>[d.name.split('/').pop().slice(6),d.fields||{}]));
  const rows=periodRows().map(r=>({...r,f:freshDaily.get(r.date)||{}})),total=stats.find(d=>d.name.split('/').pop()==='total')?.fields||{};
  const metrics={appOpens:'App opens',videosPlayed:'Videos played',installs:'Install registrations (daily since +71)',streamsOpened:'Streams opened',iptvPlayed:'IPTV plays',...FEATURE_NAMES};
  const table=(headers,data)=>`<table><thead><tr>${headers.map(x=>'<th>'+escapeHtml(x)+'</th>').join('')}</tr></thead><tbody>${data.map(row=>'<tr>'+row.map(x=>'<td>'+escapeHtml(typeof x==='object'?JSON.stringify(x):x)+'</td>').join('')+'</tr>').join('')}</tbody></table>`;
  const host=document.createElement('div');chartHost=host;host.id='pdfChart';host.style.cssText='position:fixed;left:-10000px;width:750px';document.body.append(host);
  let charts='';
  for(const [key,label]of Object.entries(metrics)){
   const b=bucketActivity(rows,key,num);plot(host,b.points.map(p=>({...p,short:p.start.slice(5),description:p.start+' to '+p.end})),{label,color:'#445566'});
   charts+=`<section class="chart"><h2>${escapeHtml(label)}</h2><p>Total: ${rows.reduce((a,r)=>a+num(r.f[key]),0)} · ${b.mode} aggregation · ${escapeHtml($('from').value)} to ${escapeHtml($('to').value)}</p>${host.querySelector('svg').outerHTML}</section>`;
  }
  const hours=Array.from({length:24},(_,h)=>({value:rows.reduce((a,r)=>a+num(r.f['h_'+h]),0),short:h+':00',description:h+':00 local'}));plot(host,hours,{bars:true,color:'#445566',label:'app opens'});charts+=`<section class="chart"><h2>Hour of day · device-local</h2>${host.querySelector('svg').outerHTML}${table(['Hour','App opens'],hours.map((v,i)=>[i+':00',v.value]))}</section>`;host.remove();
  const mix={videosPlayed:'Videos played',streamsOpened:'Streams opened',iptvPlayed:'IPTV plays',...FEATURE_NAMES};const counts=Object.entries(mix).map(([k,label])=>[label,rows.reduce((a,r)=>a+num(r.f[k]),0)]);const mixTotal=counts.reduce((a,r)=>a+r[1],0);
  charts+=`<section class="chart"><h2>What gets used</h2><p>Mixed event types, not unique users. Feature opens start +70.</p>${counts.map(([label,n])=>`<div class="bar"><span>${escapeHtml(label)} · ${n}</span><i style="width:${mixTotal?100*n/mixTotal:0}%"></i></div>`).join('')}${table(['Metric','Events','Share'],counts.map(([label,n])=>[label,n,mixTotal?(100*n/mixTotal).toFixed(1)+'%':'—']))}</section>`;
  const countries=ipCountries(total,num),countryTotal=countries.reduce((a,c)=>a+c.count,0);
  charts+=`<section class="chart"><h2>Approximate IP-country sample · all time since +69</h2><p>Includes upgrades. VPN/provider inaccuracies apply. Old locale counts excluded.</p>${countries.map(c=>`<div class="bar"><span>${escapeHtml(countryName(c.cc))} · ${c.count}</span><i style="width:${countryTotal?100*c.count/countryTotal:0}%"></i></div>`).join('')}${table(['Country','Samples'],countries.map(c=>[countryName(c.cc),c.count]))}</section>`;
  const diagnostics=reports.map(unpackDoc);
  const rawStats=stats.map(d=>[d.name.split('/').pop(),JSON.stringify(unpackDoc(d))]);
  win.document.open();win.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>MaxPlayer detailed analytics</title><style>body{font:11px Arial;color:#111;margin:22px}h1{font-size:24px}h2{font-size:16px;margin-top:25px}p{line-height:1.5}svg{width:100%;height:240px}svg text{fill:#333!important;font-size:11px}.chart{break-before:page;break-inside:avoid}.bar{margin:12px 0}.bar span{display:block}.bar i{display:block;height:8px;background:#556677;margin-top:4px}table{border-collapse:collapse;width:100%;margin:14px 0;table-layout:fixed}td,th{border:1px solid #ccc;padding:6px;text-align:left;white-space:pre-wrap;overflow-wrap:anywhere}thead{display:table-header-group}tr{break-inside:avoid}pre{white-space:pre-wrap;overflow-wrap:anywhere}button{padding:10px}@page{size:A4;margin:12mm}@media print{button{display:none}}</style></head><body><button id="printReport">Print / Save as PDF</button><h1>MaxPlayer · detailed analytics report</h1><p>Generated ${escapeHtml(new Date().toISOString())}. Chart range ${escapeHtml($('from').value)} to ${escapeHtml($('to').value)}.</p><p>Charts use the selected dates. Install totals / IP samples are all-time. Daily install tracking starts +71, feature opens +70. Appended tables include ALL stored analytics and error-report records returned by pagination, including older dates and legacy fields. This excludes secrets, tokens, admin account records, themes and notice history. This is a live best-effort fetch, not an atomic backup. Nothing is reconstructed for dates never recorded.</p>${table(['Summary','Value'],[['All-time install registrations',num(total.installs)],['Stored stats documents',stats.length],['Stored error report records',reports.length]])}${charts}<h2>Daily detail · selected range</h2>${table(['Date','App opens','Videos','Installs (+71)','Streams','IPTV','Session seconds','Sessions'],rows.map(r=>[r.date,...['appOpens','videosPlayed','installs','streamsOpened','iptvPlayed','sessionSeconds','sessions'].map(k=>num(r.f[k]))]))}<h2>Feature-open detail · selected range</h2>${table(['Date',...Object.values(FEATURE_NAMES)],rows.map(r=>[r.date,...Object.keys(FEATURE_NAMES).map(k=>num(r.f[k]))]))}<h2>All stored analytics records · raw appendix</h2>${table(['Document','All fields (legacy fields retain their original meaning)'],rawStats)}<h2>All stored diagnostic records · raw appendix</h2>${table(['ID / type / app','Time','Full captured text'],diagnostics.map(r=>[r.id+' / '+(r.type||'')+' / '+(r.app||''),r.ts||'',r.text||JSON.stringify(r)]))}</body></html>`);win.document.close();win.document.getElementById('printReport').addEventListener('click',()=>win.print());win.focus();setTimeout(()=>win.print(),400);
 }catch(e){if(!win.closed)win.document.body.textContent='Export failed: '+e.message;}finally{chartHost?.remove();button.disabled=false;}
}
