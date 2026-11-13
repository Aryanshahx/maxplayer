import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { PROJECT, validate, decodeImage, messageData, rateWindow, permanentTokenError } from './core.mjs';

const account = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || '{}');
if (account.project_id !== PROJECT) throw Error('FIREBASE_SERVICE_ACCOUNT must belong to ' + PROJECT);
initializeApp({ credential: cert(account), projectId: PROJECT });
const db = getFirestore(), messaging = getMessaging();
const repository = process.env.GITHUB_REPOSITORY;
if (repository !== 'Aryanshahx/maxplayer') throw Error('Unexpected repository');
const run = process.env.GITHUB_RUN_ID || 'manual';
const branch = 'notice-images';
const cleanError = e => String(e?.code || '') + ': ' + String(e?.message || 'Unknown error').replace(/ya29\.[A-Za-z0-9._-]+/g, '[redacted]').slice(0, 650);
async function github(path, method = 'GET', body) {
  const response = await fetch(`https://api.github.com/repos/${repository}/${path}`, {
    method, headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30000),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) { const e = Error(`GitHub ${response.status}: ${result.message || 'request failed'}`); e.status = response.status; throw e; }
  return result;
}
async function imageUrl(id, data) {
  const bytes = decodeImage(data);
  let parent;
  try { parent = (await github('git/ref/heads/' + branch)).object.sha; }
  catch (e) { if (e.status !== 404) throw e; }
  const base = parent ? (await github('git/commits/' + parent)).tree.sha : undefined;
  const blob = await github('git/blobs', 'POST', { content: bytes.toString('base64'), encoding: 'base64' });
  const tree = await github('git/trees', 'POST', { ...(base ? { base_tree: base } : {}), tree: [{ path: `notices/${id}.jpg`, mode: '100644', type: 'blob', sha: blob.sha }] });
  const commit = await github('git/commits', 'POST', { message: `Notice image ${id}`, tree: tree.sha, parents: parent ? [parent] : [] });
  if (parent) await github('git/refs/heads/' + branch, 'PATCH', { sha: commit.sha, force: false });
  else await github('git/refs', 'POST', { ref: 'refs/heads/' + branch, sha: commit.sha });
  const url = `https://raw.githubusercontent.com/${repository}/${branch}/notices/${id}.jpg`;
  // Unique URLs avoid stale content, but propagation can still take time.
  for (let attempt = 0; attempt < 4; attempt++) {
    const check = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (check.ok) { await check.body?.cancel(); return url; }
    await check.body?.cancel();
    await new Promise(resolve => setTimeout(resolve, 2000 * (attempt + 1)));
  }
  throw Error('Image committed, but public URL is not available yet; not sending a broken image');
}
async function claim(ref) {
  return db.runTransaction(async tx => {
    const [snapshot, throttle] = await Promise.all([tx.get(ref), tx.get(db.doc('_pushControl/hourly'))]);
    if (!snapshot.exists || snapshot.data().status !== 'pending') return null;
    const now = Date.now(), starts = rateWindow(throttle.data()?.starts, now);
    if (starts.length >= 10) return null;
    tx.set(db.doc('_pushControl/hourly'), { starts: [...starts, now] });
    tx.update(ref, { status: 'sending', claimedAt: FieldValue.serverTimestamp(), runId: run });
    return snapshot.data();
  });
}
async function processNotice(doc) {
  const n = await claim(doc.ref);
  if (!n) return;
  let sendStarted = false;
  try {
    validate(doc.id, n);
    let image = '';
    if (n.imageData) {
      image = await imageUrl(doc.id, n.imageData);
      await doc.ref.update({ imageUrl: image, imageData: FieldValue.delete() });
    }
    const data = messageData(doc.id, n, image);
    const base = { data, android: { priority: 'high', ttl: 24 * 60 * 60 * 1000 } };
    let acceptedRequests = 0, acceptedTokens = 0, failedTokens = 0, tokenCount = 0;
    const errors = [], warnings = [];
    if (n.target === 'all') {
      sendStarted = true;
      await messaging.send({ ...base, topic: 'all' });
      acceptedRequests = 1; // NOT a delivered-phone count.
    } else {
      const tokens = await db.collection('users').doc(n.target).collection('tokens').limit(1001).get();
      if (tokens.size > 1000) throw Error('Installation has over 1000 token records; review registration before sending');
      const docs = tokens.docs.filter(d => typeof d.data().token === 'string' && d.data().token);
      tokenCount = docs.length;
      if (!tokenCount) throw Error('No registered notification tokens for this installation');
      for (let offset = 0; offset < docs.length; offset += 500) {
        const batch = docs.slice(offset, offset + 500);
        sendStarted = true;
        const result = await messaging.sendEachForMulticast({ ...base, tokens: batch.map(d => d.data().token) });
        acceptedTokens += result.successCount; failedTokens += result.failureCount;
        for (let i = 0; i < result.responses.length; i++) {
          const failure = result.responses[i].error;
          if (!failure) continue;
          if (errors.length < 10) errors.push(failure.code);
          if (permanentTokenError(failure.code)) {
            try { await batch[i].ref.delete(); }
            catch { warnings.push('Could not remove an invalid token'); }
          }
        }
      }
      acceptedRequests = acceptedTokens;
    }
    const status = acceptedRequests > 0 ? 'sent' : 'failed';
    // Atomic status + public/private history update, without copying the queue's private data.
    const batch = db.batch();
    batch.update(doc.ref, { status, finishedAt: FieldValue.serverTimestamp(), acceptedRequests, acceptedTokens, failedTokens, tokenCount, errors, warnings, deliveryNote: 'FCM acceptance is not confirmation of device delivery' });
    if (status === 'sent') {
      const history = n.target === 'all' ? db.collection('publishedNotices').doc(doc.id) : db.collection('users').doc(n.target).collection('inbox').doc(doc.id);
      batch.set(history, { title: n.title, message: n.message, imageUrl: image, link: n.link || '', screen: n.screen || 'home', ...(n.screen==='movie'?{movieId:n.movieId,movieKind:n.movieKind,movieTitle:n.movieTitle}:{}), createdAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
    console.log(`Notice ${doc.id}: ${status}; FCM accepted ${acceptedRequests} request(s)`);
  } catch (e) {
    // Never automatically requeue after an uncertain FCM/network outcome: doing so can duplicate a broadcast.
    await doc.ref.update({ status: 'failed', finishedAt: FieldValue.serverTimestamp(), error: cleanError(e), outcomeUncertain: sendStarted, retryAutomatically: false });
    console.log(`Notice ${doc.id}: failed${sendStarted ? ' (delivery may have partially succeeded; review before retry)' : ''}`);
  }
}
// A killed runner leaves 'sending'. Mark stale jobs failed, never resend blindly.
const active = await db.collection('notices').where('status', '==', 'sending').limit(100).get();
for (const doc of active.docs) {
  const at = doc.data().claimedAt?.toMillis?.();
  if (at && at < Date.now() - 20 * 60 * 1000) {
    await doc.ref.update({ status: 'failed', outcomeUncertain: true, retryAutomatically: false, error: 'Sender stopped before final status. Delivery may have occurred; do not blindly retry.', finishedAt: FieldValue.serverTimestamp() });
  }
}
const pending = await db.collection('notices').where('status', '==', 'pending').limit(30).get();
const ordered = [...pending.docs].sort((a, b) => (a.data().createdAt?.toMillis?.() || 0) - (b.data().createdAt?.toMillis?.() || 0));
for (const doc of ordered) await processNotice(doc);
console.log(`Checked ${pending.size} pending notice(s). Rate-limited notices remain pending.`);
