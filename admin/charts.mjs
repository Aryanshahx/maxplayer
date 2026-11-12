export function bucketActivity(rows, key, number) {
  const mode=rows.length>180?'month':rows.length>45?'week':'day';
  const map=new Map();
  rows.forEach((r,i)=>{
    const group=mode==='month'?r.date.slice(0,7):mode==='week'?String(Math.floor(i/7)):r.date;
    if(!map.has(group))map.set(group,{start:r.date,end:r.date,value:0});
    const entry=map.get(group);entry.end=r.date;entry.value+=Math.max(0,number(r.f[key]));
  });
  return {mode,points:[...map.values()]};
}
export function niceScale(max) {
  if(!Number.isFinite(max)||max<=0)return {step:1,max:4};
  const rough=max/4, power=10**Math.floor(Math.log10(rough));
  const step=Math.max(1,[1,2,5,10].map(v=>v*power).find(v=>v>=rough)||power*10);
  return {step,max:Math.ceil(max/step)*step};
}
export function ipCountries(fields, number) {
  return Object.entries(fields).filter(([k])=>/^ip_c_[A-Z]{2}$/.test(k)).map(([k,v])=>({cc:k.slice(5),count:Math.max(0,number(v))})).filter(r=>r.count>0).sort((a,b)=>b.count-a.count);
}
