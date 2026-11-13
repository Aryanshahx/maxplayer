export const COUNTRY_CODES='AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW'.split(' ');
// Deliberately editable cultural/festival starting points, NOT religious censuses.
export const COUNTRY_PRESETS={christian:['US','GB','CA','BR','PH','IT','ES','DE','FR','AU'],hindu:['IN','NP'],muslim:['ID','PK','BD','SA','AE','MY','TR','EG'],buddhist:['TH','LK','MM','KH','BT'],jewish:['IL']};
export function selectedCountries(mode,values){
 if(mode==='all')return ['ALL'];
 const codes=[...new Set(values)];
 if(!codes.length||codes.some(c=>!COUNTRY_CODES.includes(c)))throw Error('Choose at least one valid country');
 return codes;
}
export function presetTheme(kind){
 const c=kind==='christmas';
 return {schemaVersion:2,name:c?'Christmas':'Diwali',palette:c?{background:'#07150F',surface:'#10271D',surfaceAlt:'#19392A',border:'#426047',accent:'#FFD580',textPrimary:'#FFF8EB',textSecondary:'#C8D8C9',danger:'#FF7474'}:{background:'#160D08',surface:'#25180F',surfaceAlt:'#332217',border:'#65462B',accent:'#FFC75A',textPrimary:'#FFF4DB',textSecondary:'#D6BFA1',danger:'#FF7474'},decoration:c?'christmas':'diwali',headerLabel:c?'Merry Christmas':'Happy Diwali',visuals:{buttonStyle:c?'snowcap':'lantern',cardStyle:c?'ribbon':'goldOutline',background:c?'snow':'stars',rounded:'pill'}};
}
export function initThemeDesigner({$,api,fieldsOf,collection,unpackDoc,getSession,validateThemeConfig}){
 let saved=new Map();
 const countryName=new Intl.DisplayNames(['en'],{type:'region'});
 for(const cc of COUNTRY_CODES){const o=new Option(countryName.of(cc)+' ('+cc+')',cc);$('themeCountries').add(o);}
 function scope(){return selectedCountries($('themeScope').value,[...$('themeCountries').selectedOptions].map(o=>o.value));}
 function audience(){
  const all=$('themeScope').value==='all';$('countryOptions').hidden=all;
  const codes=all?['ALL']:[...$('themeCountries').selectedOptions].map(o=>o.value);
  $('themeAudienceSummary').textContent=all?'Everyone · All countries. Publishing replaces all country overrides.':codes.length?codes.map(c=>countryName.of(c)).join(', ')+'. Everyone in these countries, regardless of religion. Other country themes stay unchanged.':'Select countries below. No religion is identified or stored.';
 }
 function preview(){
  const t=validateThemeConfig($('themeCode').value),h=$('themePreview');
  h.replaceChildren();h.style.background=t.palette.background;h.style.color=t.palette.textPrimary;h.style.borderColor=t.palette.accent;h.dataset.button=t.visuals?.buttonStyle||'plain';h.dataset.card=t.visuals?.cardStyle||'plain';h.dataset.background=t.visuals?.background||'none';
  const title=document.createElement('h3');title.textContent=(t.decoration==='christmas'?'❄ ':t.decoration==='diwali'?'✦ ':'')+t.name;
  const p=document.createElement('p');p.textContent=t.headerLabel;
  const btn=document.createElement('span');btn.className='sampleTile';btn.textContent='♫  Audio';btn.style.color=t.palette.accent;btn.style.background=t.palette.surfaceAlt;
  const note=document.createElement('small');note.textContent='Illustrative preview · visual details appear on Home quick-action tiles; native UI and video stay unchanged.';h.append(title,p,btn,note);
  $('activeThemeName').textContent=t.name;return t;
 }
 const run=fn=>async()=>{try{await fn();}catch(e){$('themeStatus').textContent=e.message;}};
 async function loadSaved(){if(!getSession())return;saved=new Map((await collection('themes')).map(d=>{const t=unpackDoc(d);return[t.id,t];}));$('themeList').replaceChildren(new Option('Choose saved theme',''));for(const[id,t]of saved)$('themeList').add(new Option(t.name,id));}
 function setPreset(){ $('themeCode').value=JSON.stringify(presetTheme($('themePreset').value),null,2);$('themeList').value='';preview();$('themeStatus').textContent='Preview ready. Choose audience, then Publish.'; }
 async function commit(writes){await api(':commit',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({writes})});}
 const write=(path,fields,mask)=>({update:{name:'projects/max-player-cd43d/databases/(default)/documents/'+path,fields:Object.fromEntries(Object.entries(fields).map(([k,v])=>[k,fieldsOf(v)]))},...(mask?{updateMask:{fieldPaths:mask}}:{}),updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]});
 async function publish(enabled){
  const countries=scope(),t=enabled?preview():null,all=countries[0]==='ALL';
  if(!confirm((enabled?'Publish '+t.name:'Restore Default')+' for '+(all?'ALL COUNTRIES (clears country overrides)':countries.map(c=>countryName.of(c)).join(', '))+'? Applies to everyone there, not only one religion.'))return;
  const value=enabled?{enabled:true,theme:t}:{enabled:false};
  const slots=Object.fromEntries(countries.map(c=>[c,value]));
  const writes=[write('appConfig/themeAudience',{slots},all?null:countries.map(c=>'slots.'+c))];
  // Preserve +72 compatibility for global changes; targeted changes never leak to old clients.
  if(all){const legacy=enabled?{enabled:true,theme:{...t,schemaVersion:1}}:value;if(enabled)delete legacy.theme.visuals;writes.push(write('appConfig/theme',legacy));}
  await commit(writes);$('themeStatus').textContent=(enabled?'Published '+t.name:'Default restored')+' · '+(all?'All countries':countries.join(', '))+'. Country targeting and rich visuals require +73. Offline apps update when connected.';await loadPublication();
 }
 async function loadPublication(){
  try{const d=unpackDoc(await api('appConfig/themeAudience'));const entries=Object.entries(d.slots||{});$('publishedThemes').textContent=entries.length?entries.map(([cc,v])=>(cc==='ALL'?'All countries':countryName.of(cc))+': '+(v.enabled?v.theme?.name||'Theme':'Default')).join(' · '):'No +73 publication yet; apps use the existing global theme.';}catch(e){$('publishedThemes').textContent=e.message.includes('404')?'No +73 publication yet.':'Could not load publication: '+e.message;}
 }
 $('themePreset').onchange=run(setPreset);$('loadPreset').onclick=run(setPreset);
 $('themeScope').onchange=audience;$('themeCountries').onchange=audience;
 $('religionPreset').onchange=()=>{const codes=COUNTRY_PRESETS[$('religionPreset').value]||[];for(const o of $('themeCountries').options)o.selected=codes.includes(o.value);$('themeScope').value='countries';audience();};
 $('validateTheme').onclick=run(()=>{preview();$('themeStatus').textContent='Valid. Review audience, then Publish.';});
 $('themeCode').oninput=()=>{$('themeStatus').textContent='Advanced JSON changed. Preview before publishing.';};
 $('saveTheme').onclick=run(async()=>{const t=preview(),id=$('themeList').value||crypto.randomUUID();await commit([write('themes/'+id,{name:t.name,config:t})]);await loadSaved();$('themeList').value=id;$('themeStatus').textContent='Saved '+t.name+'. Not published yet.';});
 $('loadTheme').onclick=run(()=>{const t=saved.get($('themeList').value);if(!t)throw Error('Choose a saved theme');$('themeCode').value=JSON.stringify(t.config,null,2);preview();$('themeStatus').textContent='Loaded '+t.name+'. Not published yet.';});
 $('themeList').onchange=$('loadTheme').onclick;
 $('publishTheme').onclick=run(()=>publish(true));$('defaultTheme').onclick=run(()=>publish(false));
 window.addEventListener('max-admin-open',()=>{void run(async()=>{await loadSaved();await loadPublication();})();});
 setPreset();audience();
}
