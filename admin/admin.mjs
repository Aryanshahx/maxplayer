import { bucketActivity, niceScale, ipCountries } from './charts.mjs';
import { fieldsOf, unpackDoc, validateDraft, imageByteSize, MAX_IMAGE_BYTES, statusText } from './push-core.mjs';
const PROJECT_ID='max-player-cd43d';
const API_KEY='AIzaSyDOz1FWZPP4aOzfiRYvE6xy8CF2mXiXPOY';
const ROOT=`projects/${PROJECT_ID}/databases/(default)/documents`;
const API=`https://firestore.googleapis.com/v1/${ROOT}`;
let session=null, refreshFlight=null, imageData='', imageBusy=false, imageGeneration=0, sending=false, historyBusy=false, historyTimer=null, trackedId=sessionStorage.getItem('max.push.tracked')||'';
let authGeneration=0;
const SESSION_KEY='max.push.auth';
const TOKEN_KEY='max.push.github';
function setText(id,value){document.getElementById(id).textContent=value;}
function readSession(){try{return JSON.parse(sessionStorage.getItem(SESSION_KEY)||'null');}catch{return null;}}
function persistSession(){sessionStorage.setItem(SESSION_KEY,JSON.stringify(session));}
async function readJson(response){const data=await response.json().catch(()=>({}));if(!response.ok){const error=Error(`HTTP ${response.status}: ${data.error?.message||data.message||response.statusText}`);error.status=response.status;throw error;}return data;}
async function refreshAuth(){
 if(refreshFlight)return refreshFlight;
 const generation=authGeneration;
 refreshFlight=(async()=>{
  if(!session?.refreshToken)throw Error('Please sign in again');
  const response=await fetch(`https://securetoken.googleapis.com/v1/token?key=${API_KEY}`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'refresh_token',refresh_token:session.refreshToken}),signal:AbortSignal.timeout(20000)});
  const data=await readJson(response);
  if(generation!==authGeneration)throw Error('Session changed');
  session={...session,idToken:data.id_token,refreshToken:data.refresh_token,expiresAt:Date.now()+Number(data.expires_in)*1000};persistSession();
 })().finally(()=>{refreshFlight=null;});
 return refreshFlight;
}
async function api(path,options={}){
 if(!session)throw Error('Sign in first');
 if(session.expiresAt<Date.now()+60000)await refreshAuth();
 const generation=authGeneration;
 const url=path.startsWith(':')?API+path:API+'/'+path;
 const run=()=>fetch(url,{...options,headers:{...options.headers,Authorization:'Bearer '+session.idToken},signal:AbortSignal.timeout(25000)});
 let response=await run();
 if(response.status===401){await refreshAuth();response=await run();}
 const data=await readJson(response);
 if(generation!==authGeneration)throw Error('Session changed');
 return data;
}
async function assertAdmin(){
 try{await api('admins/'+encodeURIComponent(session.uid));}
 catch(e){throw Error(e.status===404?'No admin record found. Create admins/'+session.uid+' in this project.':e.message);}
}
async function signIn(event){
 event.preventDefault();$('go').disabled=true;setText('err','Signing in…');
 try{
 const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:$('email').value.trim(),password:$('password').value,returnSecureToken:true}),signal:AbortSignal.timeout(20000)});
 const data=await readJson(response);authGeneration++;
 session={idToken:data.idToken,refreshToken:data.refreshToken,uid:data.localId,email:data.email,expiresAt:Date.now()+Number(data.expiresIn)*1000};
 await assertAdmin();persistSession();$('password').value='';setText('err','');openDashboard();
 }catch(e){session=null;sessionStorage.removeItem(SESSION_KEY);setText('err',e.message);}finally{$('go').disabled=false;}
}
function signOut(){
 authGeneration++;session=null;sessionStorage.removeItem(SESSION_KEY);sessionStorage.removeItem(TOKEN_KEY);sessionStorage.removeItem('max.push.attempt');sessionStorage.removeItem('max.push.tracked');
 localStorage.removeItem(TOKEN_KEY);$('githubToken').value='';$('rememberToken').checked=false;
 clearTimeout(historyTimer);$('dash').style.display='none';$('login').style.display='block';$('password').value='';
 STATS=[];REPORTS=[];trackedId='';setText('sendStatus','');setText('liveStatus','');
 imageGeneration++;clearPicture();$('noticeForm').reset();updatePreview();setText('err','Signed out. Browser dispatch token cleared.');
}
function openDashboard(){
 $('login').style.display='none';$('dash').style.display='block';setText('identity',session.email+' · authenticated admin · '+PROJECT_ID);
 setDates();void refresh();void refreshNotices();
 if(sessionStorage.getItem('max.push.attempt')) {
  try {
    const saved=JSON.parse(sessionStorage.getItem('max.push.attempt')).draft;
    $('title').value=saved.title;$('message').value=saved.message;
    $('target').value=saved.target==='all'?'all':'one';$('targetUid').value=saved.target==='all'?'':saved.target;
    $('link').value=saved.link||'';imageData=saved.imageData||'';
    if(imageData){$('previewImage').src=imageData;$('previewImage').hidden=false;}
    updatePreview();
  }catch{}
  setText('sendStatus','An earlier queue request was interrupted. Queue and Send will retry the ORIGINAL saved notice, ignoring edits. Check the current notice status before retrying; do not create a duplicate.');
 }
}
async function recentReports(){
 // Reports use ISO string ts rather than server createdAt timestamps.
 const result=await api(':runQuery',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({structuredQuery:{from:[{collectionId:'reports'}],orderBy:[{field:{fieldPath:'ts'},direction:'DESCENDING'}],limit:100}})});
 return result.filter(x=>x.document).map(x=>x.document);
}
function updatePreview(){setText('previewTitle',$('title').value||'Notification title');setText('previewMessage',$('message').value||'Your message appears here.');$('targetUid').hidden=$('target').value!=='one';$('targetUid').required=$('target').value==='one';}
function clearPicture(){imageGeneration++;imageBusy=false;$('send').disabled=sending;imageData='';$('picture').value='';$('previewImage').removeAttribute('src');$('previewImage').hidden=true;setText('imageInfo','');}
async function choosePicture(){
 const generation=++imageGeneration;imageData='';$('previewImage').hidden=true;
 const file=$('picture').files[0];if(!file)return;
 imageBusy=true;$('send').disabled=true;
 try{
  if(!file.type.startsWith('image/')||file.size>20*1024*1024)throw Error('Choose an image smaller than 20 MB');
  setText('imageInfo','Resizing picture…');
  const bitmap=await createImageBitmap(file);const canvas=document.createElement('canvas');
  const scale=Math.min(1,1080/Math.max(bitmap.width,bitmap.height));canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
  const ctx=canvas.getContext('2d');ctx.fillStyle='#ffffff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();
  const resized=canvas.toDataURL('image/jpeg',0.8);
  if(imageByteSize(resized)>MAX_IMAGE_BYTES)throw Error('Resized image is still over 300 KiB. Choose a smaller or less detailed picture.');
  if(generation!==imageGeneration)return;
  imageData=resized;$('previewImage').src=imageData;$('previewImage').hidden=false;setText('imageInfo',`${canvas.width} × ${canvas.height} · ${(imageByteSize(imageData)/1024).toFixed(0)} KiB JPEG · public on GitHub after sending`);
 }catch(e){if(generation===imageGeneration){imageData='';setText('imageInfo',e.message);}}
 finally{if(generation===imageGeneration){imageBusy=false;$('send').disabled=sending;}}
}
function dispatchToken(){return sessionStorage.getItem(TOKEN_KEY)||localStorage.getItem(TOKEN_KEY)||'';}
function saveToken(){
 const value=$('githubToken').value.trim();
 if(!/^github_pat_[A-Za-z0-9_]+$/.test(value)){setText('settingsStatus','Paste a GitHub token, not a Firebase key. Use a fine-grained github_pat_ token limited to this repo.');return;}
 sessionStorage.removeItem(TOKEN_KEY);localStorage.removeItem(TOKEN_KEY);
 ($('rememberToken').checked?localStorage:sessionStorage).setItem(TOKEN_KEY,value);$('githubToken').value='';setText('settingsStatus','Dispatch token saved '+($('rememberToken').checked?'on this browser.':'for this tab only.'));
}
async function dispatch(){
 const token=dispatchToken();if(!token)throw Error('No dispatch token saved. Notice stays queued; scheduled sending can still process it.');
 const response=await fetch('https://api.github.com/repos/Aryanshahx/maxplayer/actions/workflows/send-notices.yml/dispatches',{method:'POST',headers:{Authorization:'Bearer '+token,Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','Content-Type':'application/json'},body:JSON.stringify({ref:'main'}),signal:AbortSignal.timeout(20000)});
 if(!response.ok){const data=await response.json().catch(()=>({}));throw Error('GitHub dispatch HTTP '+response.status+': '+(data.message||'Check token expiry and Actions read/write permission'));}
}
async function queueAttempt(attempt){
 const fields=Object.fromEntries(Object.entries(attempt.draft).map(([k,v])=>[k,fieldsOf(v)]));
 try{
 await api(':commit',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({writes:[{update:{name:ROOT+'/notices/'+attempt.id,fields},currentDocument:{exists:false},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'}]}]})});
 }catch(error){
  // A lost response may follow a successful commit. Read this same ID; never generate a replacement automatically.
  try{await api('notices/'+attempt.id);}catch{throw error;}
 }
}
async function sendNotice(event){
 event.preventDefault();if(sending||imageBusy)return;sending=true;$('send').disabled=true;
 try{
 await assertAdmin();
 let attempt;try{attempt=JSON.parse(sessionStorage.getItem('max.push.attempt')||'null');}catch{}
 if(!attempt){
  const draft={title:$('title').value.trim(),message:$('message').value,target:$('target').value==='all'?'all':$('targetUid').value.trim(),status:'pending'};
  if($('link').value.trim())draft.link=$('link').value.trim();if(imageData)draft.imageData=imageData;
  validateDraft(draft);
  if(!confirm(`Queue this notification for ${draft.target==='all'?'EVERYONE':draft.target}? Pictures will be publicly accessible.`))return;
  attempt={id:crypto.randomUUID(),draft};sessionStorage.setItem('max.push.attempt',JSON.stringify(attempt));
 }
 setText('sendStatus','Queuing notice '+attempt.id+'…');await queueAttempt(attempt);
 trackedId=attempt.id;sessionStorage.setItem('max.push.tracked',trackedId);sessionStorage.removeItem('max.push.attempt');
 $('noticeForm').reset();clearPicture();updatePreview();setText('sendStatus','Queued '+trackedId+'. Starting sender…');
 try{await dispatch();setText('sendStatus','Queued '+trackedId+'. GitHub accepted the workflow start request. Waiting for sender status.');}
 catch(e){setText('sendStatus','Queued '+trackedId+'. '+e.message+' Do not submit it again.');}
 void refreshNotices();
 }catch(e){setText('sendStatus',e.message+' If a queue request was interrupted, retry checks the SAME saved notice ID.');}
 finally{sending=false;$('send').disabled=imageBusy;}
}
async function refreshNotices(){
 if(!session||!trackedId||historyBusy||document.hidden)return;
 historyBusy=true;const generation=authGeneration;clearTimeout(historyTimer);let active=false;
 try{
 const mask=['title','target','status','acceptedTokens','failedTokens','error','errors','outcomeUncertain'].map(x=>'mask.fieldPaths='+x).join('&');
 const notice=unpackDoc(await api('notices/'+encodeURIComponent(trackedId)+'?'+mask));
 if(generation!==authGeneration)return;
 setText('liveStatus',notice.id+' · '+statusText(notice));active=['pending','sending'].includes(notice.status);
 }catch(e){if(generation===authGeneration)setText('liveStatus',e.message);active=true;}
 finally{historyBusy=false;if(session&&active)historyTimer=setTimeout(()=>void refreshNotices(),15000);}
}

const COUNTRY = { IN:'India', US:'United States', GB:'United Kingdom', BR:'Brazil', ID:'Indonesia', PK:'Pakistan', BD:'Bangladesh', NG:'Nigeria', RU:'Russia', MX:'Mexico', PH:'Philippines', VN:'Vietnam', TR:'Turkey', EG:'Egypt', IR:'Iran', DE:'Germany', FR:'France', JP:'Japan', KR:'South Korea', SA:'Saudi Arabia', AE:'UAE', TH:'Thailand', IT:'Italy', ES:'Spain', PL:'Poland', CA:'Canada', AU:'Australia', NP:'Nepal', LK:'Sri Lanka', MY:'Malaysia', ZA:'South Africa', KE:'Kenya', AR:'Argentina', CO:'Colombia' };

let STATS = [], REPORTS = [];
const num = v => {const n=Number(v?.integerValue ?? v?.doubleValue ?? 0);return Number.isFinite(n)?Math.max(0,n):0;};
const str = v => v && v.stringValue !== undefined ? v.stringValue : '';
const $ = id => document.getElementById(id);

const periodDays = () => Math.max(1, Math.round((new Date($('to').value+'T12:00:00') - new Date($('from').value+'T12:00:00'))/86400000)+1);
function setDates() {
 if ($('period').value !== 'custom') {
  const end = new Date(), start = new Date(); start.setDate(end.getDate()-Number($('period').value)+1);
  const local = d => new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,10);
  $('from').value=local(start); $('to').value=local(end);
 }
 paint();
}

async function collection(name) {
 const docs=[];let token='';
 do {const result=await api(`${name}?pageSize=300${token?'&pageToken='+encodeURIComponent(token):''}`);docs.push(...(result.documents||[]));token=result.nextPageToken||'';}while(token);
 return docs;
}
async function refresh() {
 if(!session)return;
 $('status').textContent='Connecting to '+PROJECT_ID+'…';
 try {
 const [stats,reports]=await Promise.all([collection('stats'),recentReports()]);
 STATS=stats;REPORTS=reports.map(d=>d.fields||{}).sort((a,b)=>str(b.ts).localeCompare(str(a.ts)));
 paint();$('status').textContent='Updated '+new Date().toLocaleString()+' · '+PROJECT_ID+' · registrations / IP samples are all-time; activity / reports follow dates';
 }catch(e){$('status').textContent=e.message;}
}

function periodRows() {
  const days = new Map();
  STATS.forEach(d => {
    const name = d.name.split('/').pop();
    if (name.startsWith('daily_')) days.set(name.slice(6), d.fields || {});
  });
  const dates = [];
  if(!$('from').value || !$('to').value || $('from').value>$('to').value)return [];
  if(periodDays()>3660){$('status').textContent='Choose a range of 10 years or less';return [];}
  for(let d=new Date($('from').value+'T12:00:00'), end=new Date($('to').value+'T12:00:00');d<=end;d.setDate(d.getDate()+1)){const key=new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,10);dates.push(key);}

  return dates.map(d => ({ date: d, f: days.get(d) || {} }));
}
const sum = (rows, k) => rows.reduce((a, r) => a + num(r.f[k]), 0);

function esc(x) { const d = document.createElement('div'); d.textContent = x; return d.innerHTML; }

function countryName(cc){try{return new Intl.DisplayNames(['en'],{type:'region'}).of(cc)||cc;}catch{return COUNTRY[cc]||cc;}}
function filteredReports(){return REPORTS.filter(r=>{const d=str(r.ts).slice(0,10);return d>=$('from').value && d<=$('to').value;});}
const METRICS={appOpens:'app opens',videosPlayed:'videos played',streamsOpened:'streams opened',iptvPlayed:'IPTV plays'};
const fmt=n=>new Intl.NumberFormat('en').format(n);
function shortDate(s){const [y,m,d]=s.split('-');return new Date(Number(y),Number(m)-1,Number(d)).toLocaleDateString('en',{month:'short',day:'numeric'});}
function plot(host,points,{bars=false,color='#b9f584',label='opens'}={}){
 const w=Math.max(300,host.clientWidth||700),h=230,left=40,right=15,top=18,bottom=36,pw=w-left-right,ph=h-top-bottom;
 const max=Math.max(0,...points.map(p=>p.value)),scale=niceScale(max),x=i=>left+(i+.5)*pw/Math.max(1,points.length),y=v=>top+ph-v/scale.max*ph;
 let svg=`<svg viewBox="0 0 ${w} ${h}" aria-hidden="true"><defs><linearGradient id="grad-${host.id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="${color}" stop-opacity=".24"/><stop offset="100%" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>`;
 for(let v=0;v<=scale.max;v+=scale.step){const yy=y(v);svg+=`<path d="M${left} ${yy}H${w-right}" stroke="#273747" stroke-dasharray="3 5"/><text x="${left-9}" y="${yy+4}" fill="#91a8bd" text-anchor="end">${fmt(v)}</text>`;}
 const stride=Math.max(1,Math.ceil(points.length/Math.max(2,Math.floor(pw/75))));
 points.forEach((p,i)=>{if(i%stride===0||i===points.length-1&&points.length<8)svg+=`<text x="${x(i)}" y="${h-9}" fill="#91a8bd" text-anchor="middle">${esc(p.short)}</text>`;});
 if(bars){const bw=pw/Math.max(1,points.length);points.forEach((p,i)=>{svg+=`<rect x="${x(i)-bw*.32}" y="${y(p.value)}" width="${bw*.64}" height="${top+ph-y(p.value)}" rx="3" fill="${color}"/>`;});}
 else if(points.length){const path=points.map((p,i)=>(i?'L':'M')+x(i)+' '+y(p.value)).join(' ');svg+=`<path d="${path} L${x(points.length-1)} ${top+ph} L${x(0)} ${top+ph}Z" fill="url(#grad-${host.id})"/><path d="${path}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linejoin="round"/>`;points.forEach((p,i)=>{if(points.length<=14)svg+=`<circle cx="${x(i)}" cy="${y(p.value)}" r="3" fill="${color}"/>`;});}
 points.forEach((p,i)=>{svg+=`<rect x="${left+i*pw/Math.max(1,points.length)}" y="${top}" width="${pw/Math.max(1,points.length)}" height="${ph}" fill="transparent" tabindex="0" data-index="${i}" role="button" aria-label="${esc(p.description)}: ${p.value} ${label}"><title>${esc(p.description)}: ${p.value} ${label}</title></rect>`;});
 if(!max)svg+=`<text x="${w/2}" y="${top+ph/2}" text-anchor="middle" fill="#b9c9d9">No recorded activity in this range</text>`;
 host.innerHTML=svg+'</svg><div class="tooltip" hidden></div>';
 host.setAttribute('aria-label',`${label}: ${fmt(points.reduce((a,p)=>a+p.value,0))} recorded. Hover, tap or focus to read exact values.`);
 const tooltip=host.querySelector('.tooltip');
 const show=event=>{const target=event.target.closest?.('[data-index]');if(!target)return;const i=Number(target.dataset.index),p=points[i];tooltip.textContent=p.description+'\n'+fmt(p.value)+' '+label;tooltip.hidden=false;tooltip.style.left=Math.max(0,Math.min(w-180,x(i)-70))+'px';tooltip.style.top='25px';};
 host.onpointermove=show;host.onpointerdown=show;host.onpointerleave=()=>tooltip.hidden=true;
 host.querySelectorAll('[data-index]').forEach(el=>{el.addEventListener('focus',show);el.addEventListener('blur',()=>tooltip.hidden=true);});
}
function rankRows(host,rows,total){
 host.replaceChildren();
 for(const r of rows){const wrapper=document.createElement('div'),head=document.createElement('div');head.className='rankHead';const name=document.createElement('b'),value=document.createElement('span');name.textContent=r.name;value.textContent=fmt(r.count)+(total?' · '+(100*r.count/total).toFixed(1)+'%':'');head.append(name,value);const track=document.createElement('div'),fill=document.createElement('div');track.className='track';fill.className='fill';fill.style.width=(total?100*r.count/total:0)+'%';if(r.color)fill.style.background=r.color;track.append(fill);wrapper.append(head,track);host.append(wrapper);}
}
function paint(){
 const rows=periodRows(),key=$('chartMetric').value||'appOpens';
 const total=STATS.find(d=>d.name.split('/').pop()==='total')?.fields||{};
 for(const [id,k] of [['sOpens','appOpens'],['sVideos','videosPlayed'],['sStreams','streamsOpened'],['sIptv','iptvPlayed'],['sFail','playFailed'],['sAds','adImpressions']])setText(id,fmt(sum(rows,k)));
 setText('sInstalls',fmt(num(total.installs)));
 const sessions=sum(rows,'sessions');setText('sSession',sessions?(sum(rows,'sessionSeconds')/sessions/60).toFixed(1):'—');
 const {mode,points}=bucketActivity(rows,key,num),label=METRICS[key];
 setText('chartTotal',fmt(sum(rows,key)));setText('chartSub',label+' · '+(mode==='day'?'daily':mode==='week'?'7-day buckets':'calendar months'));
 plot($('chart'),points.map(p=>({...p,short:mode==='month'?new Date(p.start+'T12:00:00').toLocaleDateString('en',{month:'short',year:'2-digit'}):shortDate(p.start),description:p.start===p.end?p.start:p.start+' to '+p.end})),{label});
 const peak=rows.reduce((a,r)=>num(r.f[key])>num(a?.f[key])?r:a,null);
 setText('chartInsight',peak&&num(peak.f[key])?`Busiest recorded day: ${shortDate(peak.date)} · ${fmt(num(peak.f[key]))} ${label}. Hover or tap the chart for exact values.`:'No events recorded for this metric. Empty dates show zero; they do not confirm that every device reported.');
 $('chartTable').innerHTML=rows.map(r=>`<tr><td>${r.date}</td>${['appOpens','videosPlayed','streamsOpened','iptvPlayed'].map(k=>'<td>'+fmt(num(r.f[k]))+'</td>').join('')}</tr>`).join('');
 const features=[{name:'Local videos',count:sum(rows,'videosPlayed')},{name:'Streams',count:sum(rows,'streamsOpened'),color:'#69cfef'},{name:'IPTV',count:sum(rows,'iptvPlayed'),color:'#b3a1f0'}];rankRows($('featureMix'),features,features.reduce((a,r)=>a+r.count,0));
 const hours=Array.from({length:24},(_,h)=>({value:sum(rows,'h_'+h),short:String(h).padStart(2,'0')+':00',description:String(h).padStart(2,'0')+':00–'+String(h).padStart(2,'0')+':59'}));plot($('hoursChart'),hours,{bars:true,color:'#69cfef',label:'app opens'});
 const busiest=hours.reduce((a,p)=>p.value>a.value?p:a,hours[0]);setText('hourInsight',busiest.value?`Peak local hour: ${busiest.description} · ${fmt(busiest.value)} opens.`:'No hourly activity recorded in this range.');
 const countries=ipCountries(total,num),sample=countries.reduce((a,c)=>a+c.count,0);
 setText('countrySummary',sample?`${fmt(sample)} country samples collected since +69 · top ${Math.min(20,countries.length)} countries shown. Not filtered by activity dates.`:'Waiting for IP-country samples from the +69 app. Old locale-based numbers are intentionally not shown.');
 rankRows($('countries'),countries.slice(0,20).map(c=>({name:countryName(c.cc),count:c.count})),sample);
 $('reports').innerHTML=filteredReports().slice(0,100).map(r=>`<tr><td><span class="pill">${esc(str(r.type)||'report')}</span></td><td>${esc(str(r.ts).replace('T',' ').slice(0,16))}</td><td class="rpt">${esc(str(r.text).slice(0,500))}</td></tr>`).join('')||'<tr><td colspan="3">No captured reports in these dates.</td></tr>';
}
window.addEventListener('resize',()=>{if($('dash').style.display==='block')paint();});

function downloadPdf() {
 const win=window.open('','_blank');if(!win){alert('Allow popups to open the printable PDF report.');return;}
 const rows=periodRows();
 const table=(head,rows)=>`<table><thead><tr>${head.map(x=>'<th>'+esc(String(x))+'</th>').join('')}</tr></thead><tbody>${rows.map(row=>'<tr>'+row.map(x=>'<td>'+esc(String(x))+'</td>').join('')+'</tr>').join('')}</tbody></table>`;
 const total=STATS.find(d=>d.name.split('/').pop()==='total')?.fields||{};
 win.document.write(`<!doctype html><html><head><title>Max Player report</title><style>body{font:12px Arial;color:#111;margin:25px}table{border-collapse:collapse;width:100%;margin:15px 0}td,th{border:1px solid #ccc;padding:6px;text-align:left;white-space:pre-wrap;word-break:break-word}tr{break-inside:avoid}h2{margin-top:25px}@media print{button{display:none}}@page{margin:12mm}</style></head><body><button id="printReport">Print / Save as PDF</button><h1>Max Player activity report</h1><p>${esc($('from').value)} to ${esc($('to').value)} · generated ${esc(new Date().toLocaleString())}</p><p>Use the print destination “Save as PDF”. Install registrations and IP-country samples are all-time; activity and reports follow the selected dates. Country samples are approximate, not historical install locations.</p><h2>Summary</h2>${table(['Metric','Value'],[['Installs (all-time)',num(total.installs)],...['appOpens','videosPlayed','streamsOpened','iptvPlayed','playFailed','adImpressions','sessions','sessionSeconds'].map(k=>[k,sum(rows,k)])])}<h2>Countries (IP sample since +69; all-time, including upgrades)</h2>${table(['Country','IP samples'],ipCountries(total,num).map(c=>[countryName(c.cc),c.count]))}<h2>Hourly app opens (device-local)</h2>${table(['Hour','Opens'],Array.from({length:24},(_,h)=>[h+':00',sum(rows,'h_'+h)]))}<h2>Daily activity</h2>${table(['Date','Opens','Videos','Streams','IPTV','Failures','Ads','Seconds'],rows.map(r=>[r.date,...['appOpens','videosPlayed','streamsOpened','iptvPlayed','playFailed','adImpressions','sessionSeconds'].map(k=>num(r.f[k]))]))}<h2>Problem reports</h2>${table(['Type','Time','Details'],filteredReports().map(r=>[str(r.type),str(r.ts),str(r.text)]))}</body></html>`);
 win.document.close();win.document.getElementById('printReport').addEventListener('click',()=>win.print());win.focus();setTimeout(()=>win.print(),300);
}


$('loginForm').addEventListener('submit',signIn);
$('logout').onclick=signOut;
$('from').onchange=$('to').onchange=()=>{$('period').value='custom';paint();};
$('period').onchange=setDates;
$('chartMetric').onchange=paint;
$('refresh').onclick=refresh;
$('pdfBtn').onclick=downloadPdf;
$('title').oninput=$('message').oninput=$('target').onchange=updatePreview;
$('picture').onchange=choosePicture;
$('removePicture').onclick=clearPicture;
$('noticeForm').addEventListener('submit',sendNotice);
$('saveToken').onclick=saveToken;
$('forgetToken').onclick=()=>{sessionStorage.removeItem(TOKEN_KEY);localStorage.removeItem(TOKEN_KEY);$('githubToken').value='';setText('settingsStatus','Dispatch token removed.');};
$('dispatch').onclick=async()=>{ $('dispatch').disabled=true;try{await assertAdmin();await dispatch();setText('settingsStatus','Workflow start accepted. Watch notice status or open the workflow link.');}catch(e){setText('settingsStatus',e.message);}finally{$('dispatch').disabled=false;} };
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&session)void refreshNotices();});
setInterval(()=>{if(session&&!document.hidden)void refresh();},60000);
setDates();updatePreview();
if(localStorage.getItem(TOKEN_KEY)){$('rememberToken').checked=true;setText('settingsStatus','A dispatch token is remembered on this browser.');}
else if(sessionStorage.getItem(TOKEN_KEY))setText('settingsStatus','A dispatch token is saved for this tab.');
// Remove the obsolete visual PIN lock. It never authorized Firebase requests.
sessionStorage.removeItem('max.admin.unlocked');
session=readSession();
if(session){try{await assertAdmin();openDashboard();}catch(e){session=null;sessionStorage.removeItem(SESSION_KEY);setText('err','Please sign in again. '+e.message);}}
