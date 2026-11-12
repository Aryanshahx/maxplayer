export const MAX_IMAGE_BYTES = 300 * 1024;
export function fieldsOf(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'number') return { integerValue: String(value) };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(fieldsOf) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k,v])=>[k,fieldsOf(v)])) } };
}
export function unpack(v) {
  if (!v) return undefined;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(unpack);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k,x])=>[k,unpack(x)]));
  return null;
}
export function unpackDoc(doc) {
  return { id: doc.name.split('/').pop(), ...Object.fromEntries(Object.entries(doc.fields || {}).map(([k,v])=>[k,unpack(v)])) };
}
export function imageByteSize(data) {
  if (!/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(data)) throw Error('Picture must be a JPEG data URL');
  const b64=data.slice(data.indexOf(',')+1);
  return b64.length*3/4-(b64.endsWith('==')?2:b64.endsWith('=')?1:0);
}
export function validateDraft(draft) {
  if (!draft.title.trim() || draft.title.length>80) throw Error('Title must be 1–80 characters');
  if (draft.message.length>900) throw Error('Message must be at most 900 characters');
  if (!/^(all|[A-Za-z0-9_-]{1,128})$/.test(draft.target)) throw Error('Paste a valid installation ID from the app');
  if (draft.link) {
    const uri=new URL(draft.link);
    if (uri.protocol!=='https:' || !uri.hostname || uri.username || uri.password || draft.link.length>2048) throw Error('Link must be HTTPS without embedded credentials');
  }
  if (draft.imageData && (imageByteSize(draft.imageData)>MAX_IMAGE_BYTES || draft.imageData.length>420000)) throw Error('Picture must be smaller than 300 KiB');
  const data={ noticeId:'x'.repeat(36), title:draft.title, message:draft.message };
  if(draft.link)data.link=draft.link;
  if(draft.imageData)data.image='https://raw.githubusercontent.com/Aryanshahx/maxplayer/notice-images/notices/'+'x'.repeat(36)+'.jpg';
  const bytes=new TextEncoder().encode(JSON.stringify(data)).length;
  if(bytes>(draft.target==='all'?1900:3800))throw Error('Message is too large for FCM. Shorten the message, especially emoji/non-English text.');
  if(new TextEncoder().encode(JSON.stringify(draft)).length>900000)throw Error('Notice exceeds the safe Firestore document size');
  return draft;
}
export function statusText(n) {
  if(n.status==='pending')return 'Pending — waiting for sender (may be rate-limited)';
  if(n.status==='sending')return 'Sending — workflow processing';
  if(n.status==='sent')return n.target==='all'?'Accepted by FCM — phone count unavailable':`FCM accepted ${n.acceptedTokens||0} token(s); failed ${n.failedTokens||0}`;
  if(n.status==='failed')return (n.outcomeUncertain?'Uncertain delivery — review before retry. ':'Failed — ')+(n.error||(n.errors||[]).join(', ')||'See workflow log');
  return n.status||'Unknown';
}
