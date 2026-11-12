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
 STATS=[];REPORTS=[];trackedId='';setText('noticeHistory','');setText('sendStatus','');setText('liveStatus','');
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
  setText('sendStatus','An earlier queue request was interrupted. Queue and Send will retry the ORIGINAL saved notice, ignoring edits. Check history first; do not create a duplicate.');
 }
}
async function query(collectionId,limit=30){
 const result=await api(':runQuery',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({structuredQuery:{select:{fields:['title','message','target','status','createdAt','acceptedRequests','acceptedTokens','failedTokens','error','errors','outcomeUncertain'].map(fieldPath=>({fieldPath}))},from:[{collectionId}],orderBy:[{field:{fieldPath:'createdAt'},direction:'DESCENDING'}],limit}})});
 return result.filter(x=>x.document).map(x=>x.document);
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
 if(!session||historyBusy||document.hidden)return;historyBusy=true;const generation=authGeneration;clearTimeout(historyTimer);
 try{
 const notices=(await query('notices')).map(unpackDoc);if(generation!==authGeneration)return;
 const body=$('noticeHistory');body.replaceChildren();
 for(const n of notices){
  const row=document.createElement('tr');
  for(const text of [(n.createdAt?new Date(n.createdAt).toLocaleString():'Pending timestamp')+'\n'+n.id,n.title+'\n'+(n.target==='all'?'Everyone':n.target),statusText(n)]){const cell=document.createElement('td');cell.textContent=text;cell.style.whiteSpace='pre-wrap';row.append(cell);}body.append(row);
 }
 if(!notices.length){const row=document.createElement('tr');const cell=document.createElement('td');cell.colSpan=3;cell.textContent='No notices yet.';row.append(cell);body.append(row);}
 let tracked=notices.find(n=>n.id===trackedId);
 if(trackedId&&!tracked){try{tracked=unpackDoc(await api('notices/'+encodeURIComponent(trackedId)));}catch{}}
 if(generation!==authGeneration)return;
 if(tracked)setText('liveStatus',tracked.id+' · '+statusText(tracked));
 setText('historyStatus','Updated '+new Date().toLocaleTimeString()+'. Counts are FCM acceptance, not confirmed phone delivery.');
 }catch(e){if(generation===authGeneration)setText('historyStatus',e.message+' Check Firebase admin membership and published rules.');}
 finally{historyBusy=false;if(session)historyTimer=setTimeout(()=>void refreshNotices(),15000);}
}

const COUNTRY = { IN:'India', US:'United States', GB:'United Kingdom', BR:'Brazil', ID:'Indonesia', PK:'Pakistan', BD:'Bangladesh', NG:'Nigeria', RU:'Russia', MX:'Mexico', PH:'Philippines', VN:'Vietnam', TR:'Turkey', EG:'Egypt', IR:'Iran', DE:'Germany', FR:'France', JP:'Japan', KR:'South Korea', SA:'Saudi Arabia', AE:'UAE', TH:'Thailand', IT:'Italy', ES:'Spain', PL:'Poland', CA:'Canada', AU:'Australia', NP:'Nepal', LK:'Sri Lanka', MY:'Malaysia', ZA:'South Africa', KE:'Kenya', AR:'Argentina', CO:'Colombia' };

let STATS = [], REPORTS = [];
const num = v => v && v.integerValue !== undefined ? Number(v.integerValue) : (v && v.doubleValue || 0);
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
 paint();$('status').textContent='Updated '+new Date().toLocaleString()+' · '+PROJECT_ID+' · installs/countries are all-time; activity/reports follow dates';
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

function paint() {
  const rows = periodRows();
  document.getElementById('chartSub').textContent = `app opens · last ${periodDays()} days`;
  let installs = 0, countries = {};
  STATS.forEach(d => {
    const name = d.name.split('/').pop();
    if (name === 'total') {
      installs = num((d.fields || {}).installs);
      Object.keys(d.fields || {}).forEach(k => { if (k.startsWith('c_')) countries[k.slice(2)] = num(d.fields[k]); });
    }
  });
  document.getElementById('sInstalls').textContent = installs;
  document.getElementById('sOpens').textContent   = sum(rows, 'appOpens');
  document.getElementById('sVideos').textContent  = sum(rows, 'videosPlayed');
  document.getElementById('sStreams').textContent = sum(rows, 'streamsOpened');
  document.getElementById('sIptv').textContent    = sum(rows, 'iptvPlayed');
  document.getElementById('sFail').textContent    = sum(rows, 'playFailed');
  document.getElementById('sAds').textContent     = sum(rows, 'adImpressions');
  const secs = sum(rows, 'sessionSeconds'), sess = Math.max(1, sum(rows, 'sessions'));
  document.getElementById('sSession').textContent = (secs / sess / 60).toFixed(1);

  // opens chart
  drawBars(document.getElementById('chart'), rows.map(r => num(r.f.appOpens)),
    rows.map(r => r.date.slice(5)), '#ec4899', '#8b5cf6');

  // countries
  document.getElementById('countries').innerHTML =
    Object.entries(countries).sort((a, b) => b[1] - a[1])
      .map(([cc, n]) => `<tr><td>${esc(countryName(cc))}</td><td style="text-align:right;color:var(--cyan);font-weight:700">${n}</td></tr>`).join('')
    || '<tr><td colspan="2" style="color:var(--dim)">No country data yet (needs 1.0.1+65 installs)</td></tr>';

  // hourly usage across the period
  const hours = Array.from({length: 24}, (_, h) => sum(rows, 'h_' + h));
  drawBars(document.getElementById('hoursChart'), hours,
    hours.map((_, h) => h % 6 === 0 ? String(h) : ''), '#22d3ee', '#34d399');

  // reports
  document.getElementById('reports').innerHTML = filteredReports().slice(0, 100).map(r => {
    const t = str(r.type) || 'report';
    const when = str(r.ts).replace('T', ' ').slice(0, 16);
    const body = str(r.text).slice(0, 400);
    const host = str(r.host), kind = str(r.kind);
    return `<tr><td><span class="pill">${esc(t.toUpperCase())}</span></td><td style="color:var(--dim)">${esc(when)}</td><td><div class="rpt">${esc(host ? 'host: ' + host + (kind ? ' · ' + kind : '') + '\n' + body : body)}</div></td></tr>`;
  }).join('') || '<tr><td colspan="3" style="color:var(--dim)">No reports yet — devices upload from 1.0.1+65</td></tr>';
}

function esc(x) { const d = document.createElement('div'); d.textContent = x; return d.innerHTML; }

function countryName(cc){try{return new Intl.DisplayNames(['en'],{type:'region'}).of(cc)||cc;}catch{return COUNTRY[cc]||cc;}}
function filteredReports(){return REPORTS.filter(r=>{const d=str(r.ts).slice(0,10);return d>=$('from').value && d<=$('to').value;});}
function drawBars(canvas, vals, labels, c1, c2) {
 const width=canvas.clientWidth||800,height=200,dpr=window.devicePixelRatio||1;
 canvas.width=width*dpr;canvas.height=height*dpr;canvas.style.height=height+'px';
 const x=canvas.getContext('2d');x.scale(dpr,dpr);
 const left=42,top=16,bottom=32,w=width-left-10,h=height-top-bottom,max=Math.max(1,...vals);
 x.font='10px system-ui';
 for(let i=0;i<=4;i++){const y=top+h-i*h/4;x.strokeStyle='#2c2c3a';x.beginPath();x.moveTo(left,y);x.lineTo(width-10,y);x.stroke();x.fillStyle='#aaa';x.textAlign='right';x.fillText(String(Math.round(max*i/4)),left-6,y+3);}
 const bw=w/Math.max(1,vals.length),step=Math.max(1,Math.ceil(vals.length/Math.max(2,Math.floor(w/50))));
 vals.forEach((v,i)=>{x.fillStyle=c1;x.fillRect(left+i*bw+1,top+h-v/max*h,Math.max(1,bw-2),v/max*h);if(i%step===0&&labels[i]){x.fillStyle='#aaa';x.textAlign='center';x.fillText(labels[i],left+(i+.5)*bw,height-10);}});
 if(!vals.some(v=>v)){x.fillStyle='#aaa';x.textAlign='center';x.fillText('No activity in selected period',width/2,80);}
 canvas.onmousemove=e=>{const i=Math.floor((e.offsetX-left)/bw);canvas.title=i>=0&&i<vals.length?`${labels[i]||i}: ${vals[i]}`:'';};
}
window.addEventListener('resize',()=>{if($('dash').style.display==='block')paint();});


function downloadPdf() {
 const win=window.open('','_blank');if(!win){alert('Allow popups to open the printable PDF report.');return;}
 const rows=periodRows();
 const table=(head,rows)=>`<table><thead><tr>${head.map(x=>'<th>'+esc(String(x))+'</th>').join('')}</tr></thead><tbody>${rows.map(row=>'<tr>'+row.map(x=>'<td>'+esc(String(x))+'</td>').join('')+'</tr>').join('')}</tbody></table>`;
 const total=STATS.find(d=>d.name.split('/').pop()==='total')?.fields||{};
 win.document.write(`<!doctype html><html><head><title>Max Player report</title><style>body{font:12px Arial;color:#111;margin:25px}table{border-collapse:collapse;width:100%;margin:15px 0}td,th{border:1px solid #ccc;padding:6px;text-align:left;white-space:pre-wrap;word-break:break-word}tr{break-inside:avoid}h2{margin-top:25px}@media print{button{display:none}}@page{margin:12mm}</style></head><body><button id="printReport">Print / Save as PDF</button><h1>Max Player activity report</h1><p>${esc($('from').value)} to ${esc($('to').value)} · generated ${esc(new Date().toLocaleString())}</p><p>Use the print destination “Save as PDF”. Installs and countries are all-time; activity and reports follow the selected dates.</p><h2>Summary</h2>${table(['Metric','Value'],[['Installs (all-time)',num(total.installs)],...['appOpens','videosPlayed','streamsOpened','iptvPlayed','playFailed','adImpressions','sessions','sessionSeconds'].map(k=>[k,sum(rows,k)])])}<h2>Countries (device locale)</h2>${table(['Country','Installs'],Object.entries(total).filter(([k])=>k.startsWith('c_')).map(([k,v])=>[countryName(k.slice(2)),num(v)]))}<h2>Hourly app opens (device-local)</h2>${table(['Hour','Opens'],Array.from({length:24},(_,h)=>[h+':00',sum(rows,'h_'+h)]))}<h2>Daily activity</h2>${table(['Date','Opens','Videos','Streams','IPTV','Failures','Ads','Seconds'],rows.map(r=>[r.date,...['appOpens','videosPlayed','streamsOpened','iptvPlayed','playFailed','adImpressions','sessionSeconds'].map(k=>num(r.f[k]))]))}<h2>Problem reports</h2>${table(['Type','Time','Details'],filteredReports().map(r=>[str(r.type),str(r.ts),str(r.text)]))}</body></html>`);
 win.document.close();win.document.getElementById('printReport').addEventListener('click',()=>win.print());win.focus();setTimeout(()=>win.print(),300);
}


$('loginForm').addEventListener('submit',signIn);
$('logout').onclick=signOut;
$('from').onchange=$('to').onchange=()=>{$('period').value='custom';paint();};
$('period').onchange=setDates;
$('refresh').onclick=refresh;
$('pdfBtn').onclick=downloadPdf;
$('title').oninput=$('message').oninput=$('target').onchange=updatePreview;
$('picture').onchange=choosePicture;
$('removePicture').onclick=clearPicture;
$('noticeForm').addEventListener('submit',sendNotice);
$('saveToken').onclick=saveToken;
$('forgetToken').onclick=()=>{sessionStorage.removeItem(TOKEN_KEY);localStorage.removeItem(TOKEN_KEY);$('githubToken').value='';setText('settingsStatus','Dispatch token removed.');};
$('dispatch').onclick=async()=>{ $('dispatch').disabled=true;try{await assertAdmin();await dispatch();setText('settingsStatus','Workflow start accepted. Watch notice status or open the workflow link.');}catch(e){setText('settingsStatus',e.message);}finally{$('dispatch').disabled=false;} };
$('refreshNotices').onclick=()=>void refreshNotices();
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&session)void refreshNotices();});
setInterval(()=>{if(session&&!document.hidden)void refresh();},60000);
setDates();updatePreview();
if(localStorage.getItem(TOKEN_KEY)){$('rememberToken').checked=true;setText('settingsStatus','A dispatch token is remembered on this browser.');}
else if(sessionStorage.getItem(TOKEN_KEY))setText('settingsStatus','A dispatch token is saved for this tab.');
// Remove the obsolete visual PIN lock. It never authorized Firebase requests.
sessionStorage.removeItem('max.admin.unlocked');
session=readSession();
if(session){try{await assertAdmin();openDashboard();}catch(e){session=null;sessionStorage.removeItem(SESSION_KEY);setText('err','Please sign in again. '+e.message);}}
