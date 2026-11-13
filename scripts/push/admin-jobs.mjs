import {initializeApp,cert} from 'firebase-admin/app';
import {getFirestore,FieldValue,FieldPath} from 'firebase-admin/firestore';
import {PROJECT} from './core.mjs';

export const RESET_COLLECTIONS=Object.freeze(['stats','reports']);
export function validReset(job){return job?.action==='resetAnalytics'&&job?.confirmation==='RESET ANALYTICS'&&typeof job.actor==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(job.actor);}

export async function processAdminJobs(db,runId){
 const stale=await db.collection('adminJobs').where('status','==','processing').limit(30).get();
 for(const doc of stale.docs){const ms=doc.data().startedAt?.toMillis?.();if(ms&&ms<Date.now()-20*60000)await doc.ref.update({status:'partial',message:'Workflow stopped. Some data may have been deleted; no automatic retry.',finishedAt:FieldValue.serverTimestamp()});}
 const jobs=await db.collection('adminJobs').where('status','==','pending').limit(5).get();
 for(const doc of jobs.docs){
  const claimed=await db.runTransaction(async tx=>{
   const [job,rate]=await Promise.all([tx.get(doc.ref),tx.get(db.doc('_pushControl/reset'))]);
   if(!job.exists||job.data().status!=='pending')return null;
   const data=job.data();if(!validReset(data)){tx.update(doc.ref,{status:'failed',error:'Invalid reset request'});return null;}
   const admin=await tx.get(db.collection('admins').doc(data.actor));
   if(!admin.exists){tx.update(doc.ref,{status:'failed',error:'Admin access revoked'});return null;}
   const previous=rate.data()?.at?.toMillis?.()||0;
   if(Date.now()-previous<3600000){tx.update(doc.ref,{status:'failed',error:'Reset limited to once per hour'});return null;}
   tx.set(db.doc('_pushControl/reset'),{at:FieldValue.serverTimestamp()});
   tx.update(doc.ref,{status:'processing',startedAt:FieldValue.serverTimestamp(),runId,message:'Deleting analytics counters and error reports only'});return data;
  });
  if(!claimed)continue;
  let deleted=0,skipped=0;
  try{
   for(const name of RESET_COLLECTIONS){
    let cursor=null;
    for(;;){
     let query=db.collection(name).orderBy(FieldPath.documentId()).limit(200);if(cursor)query=query.startAfter(cursor);
     const page=await query.get();if(page.empty)break;
     const writer=db.bulkWriter();writer.onWriteError(()=>false);
     const tasks=page.docs.map(snapshot=>writer.delete(snapshot.ref,{lastUpdateTime:snapshot.updateTime}).then(()=>deleted++).catch(()=>skipped++));
     await writer.close();await Promise.all(tasks);cursor=page.docs.at(-1);
     await doc.ref.update({deleted,skipped,message:`Removed ${deleted} records; ${skipped} changed/failed records preserved`});
    }
   }
   await doc.ref.update({status:skipped?'partial':'done',deleted,skipped,finishedAt:FieldValue.serverTimestamp(),message:`Removed ${deleted} analytics/report documents. ${skipped} changed/failed records preserved. Active apps may write new data. Admins, tokens, notices and themes were not touched.`});
  }catch(e){await doc.ref.update({status:'partial',deleted,skipped,error:String(e.message||e).slice(0,500),message:'Reset stopped; some data may have been removed. No automatic retry.',finishedAt:FieldValue.serverTimestamp()});}
 }
}
if(process.argv[1]&&new URL(import.meta.url).pathname===process.argv[1]){
 const account=JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT||'{}');if(account.project_id!==PROJECT)throw Error('Wrong Firebase project for reset worker');
 initializeApp({credential:cert(account),projectId:PROJECT});await processAdminJobs(getFirestore(),process.env.GITHUB_RUN_ID||'manual');
}
