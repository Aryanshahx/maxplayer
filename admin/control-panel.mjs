import {bucketActivity} from './charts.mjs';
const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function initControlPanel({$,api,collection,fieldsOf,unpackDoc,dispatch,getSession,refresh}){
 let jobTimer=null;
 window.addEventListener('max-admin-open',()=>{const id=sessionStorage.getItem('max.reset.pending');if(id)void pollJob(id);});
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
