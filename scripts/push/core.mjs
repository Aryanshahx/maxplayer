export const SCREENS = ['home','discover','private','folders','playlists','audio','network','cloud','quickShare','stream','iptv','statistics','movie','external'];
export const PROJECT = 'max-player-cd43d';
export const MAX_IMAGE = 300 * 1024;
export function validate(id, n) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw Error('Invalid notice ID');
  if (typeof n.title !== 'string' || !n.title.trim() || n.title.length > 80) throw Error('Title must be 1–80 characters');
  if (typeof n.message !== 'string' || n.message.length > 900) throw Error('Message must be at most 900 characters');
  if (typeof n.target !== 'string' || !/^(all|[A-Za-z0-9_-]{1,128})$/.test(n.target)) throw Error('Invalid target');
  if (!n.createdAt || typeof n.createdAt.toMillis !== 'function') throw Error('Missing server creation timestamp');
  if (n.link) {
    const url = new URL(n.link);
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || n.link.length > 2048) throw Error('Link must be HTTPS without credentials');
  }
  if (n.screen !== undefined && !SCREENS.includes(n.screen)) throw Error('Invalid app screen');
  if (n.screen === 'external' && !n.link) throw Error('External destination needs an HTTPS link');
  if(n.screen==='movie'&&(!/^[1-9][0-9]{0,8}$/.test(String(n.movieId))||!['movie','tv'].includes(n.movieKind)||typeof n.movieTitle!=='string'||!n.movieTitle.trim()||n.movieTitle.length>150))throw Error('Invalid movie destination');
  if (n.imageData !== undefined) decodeImage(n.imageData);
}
export function decodeImage(data) {
  if (typeof data !== 'string' || data.length > 420000 || !/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(data)) throw Error('Invalid JPEG data');
  const encoded = data.substring(data.indexOf(',') + 1);
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.toString('base64') !== encoded || bytes.length > MAX_IMAGE || bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216 || bytes.at(-2) !== 255 || bytes.at(-1) !== 217) throw Error('JPEG must be valid base64 and at most 300 KiB');
  return bytes;
}
export function messageData(id, n, image = '') {
  const data = { noticeId: id, title: n.title, message: n.message };
  if (n.screen) data.screen = n.screen;
  if(n.screen==='movie')Object.assign(data,{movieId:String(n.movieId),movieKind:n.movieKind,movieTitle:n.movieTitle});
  if (image) data.image = image;
  if (n.link) data.link = n.link;
  // FCM permits 4096 bytes for most messages, but topic payloads are capped at 2048.
  if (Buffer.byteLength(JSON.stringify(data), 'utf8') > (n.target === 'all' ? 1900 : 3800)) throw Error('Message exceeds the FCM byte limit. Shorten title/message (especially emoji or non-ASCII text).');
  return data;
}
export function rateWindow(previous, now) {
  return (Array.isArray(previous) ? previous : []).filter(t => Number.isFinite(t) && t > now - 3600000 && t <= now);
}
export function permanentTokenError(code) {
  return ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code);
}
