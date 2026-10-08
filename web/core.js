/** Pure game rules. No network, DOM, or hidden model training. */
export const STORAGE_KEY = 'evidence-genesis-v1';
export const TYPES = ['preference', 'vocabulary', 'instruction'];
export const ROLES = ['Document maker', 'Reviewer'];
export function initialState() {
  return {version: 1, selected: 'milo', characters: [
    {id: 'milo', name: 'Milo', role: 'Document maker', palette: 'mint', energy: 72, tasks: 0, memories: []},
    {id: 'pip', name: 'Pip', role: 'Reviewer', palette: 'coral', energy: 84, tasks: 0, memories: []}
  ], documents: [], activity: [{text: 'Your workshop is ready. Teach your first lesson.', at: new Date().toISOString()}], room: {light: 'day', plant: true}};
}
export function character(state) { return state.characters.find(c => c.id === state.selected); }
export function log(state, text) {
  state.activity.unshift({text, at: new Date().toISOString()});
  state.activity = state.activity.slice(0, 30);
}
export function teach(state, {type, key, value}, id = globalThis.crypto.randomUUID()) {
  if (!TYPES.includes(type)) throw new Error('Choose a valid lesson type.');
  key = String(key).trim(); value = String(value).trim();
  if (!key || !value || key.length > 80 || value.length > 600) throw new Error('Add a lesson name (up to 80 characters) and a lesson (up to 600 characters).');
  const c = character(state);
  const existing = c.memories.find(m => m.type === type && m.key.toLowerCase() === key.toLowerCase());
  if (!existing && c.memories.length >= 50) throw new Error('This notebook holds 50 lessons. Edit or remove an existing lesson.');
  const lesson = {id: existing?.id || id, type, key, value, source: 'Taught by you', at: new Date().toISOString()};
  if (existing) Object.assign(existing, lesson); else c.memories.push(lesson);
  log(state, `${c.name} ${existing ? 'updated' : 'learned'} “${key}”.`);
  return lesson;
}
export function templateDocument(c, title, notes) {
  const lines = notes.split('\n').map(s => s.trim()).filter(Boolean);
  const format = c.memories.find(m => m.type === 'preference' && m.key.toLowerCase() === 'format')?.value.toLowerCase() || '';
  const signoff = c.memories.find(m => m.type === 'preference' && m.key.toLowerCase() === 'sign-off')?.value;
  const numbered = /number|step/.test(format);
  const body = lines.map((line, i) => `${numbered ? `${i + 1}.` : '-'} ${line}`).join('\n');
  const vocabulary = c.memories.filter(m => m.type === 'vocabulary');
  const glossary = vocabulary.length ? '\n\n## Your glossary\n' + vocabulary.map(m => `- ${m.key}: ${m.value}`).join('\n') : '';
  return `# ${title}\n\n${body}${glossary}${signoff ? '\n\n' + signoff : ''}`;
}
export function validateTask(title, notes) {
  if (!title.trim() || title.length > 120) throw new Error('Give the document a title (up to 120 characters).');
  if (!notes.trim() || notes.length > 6000) throw new Error('Add source notes (up to 6,000 characters).');
}
export function completeTask(state, {characterId, title, content, mode}, id = globalThis.crypto.randomUUID()) {
  const c = state.characters.find(c => c.id === characterId);
  if (!c || !content.trim()) throw new Error('The task did not return a document.');
  c.energy = Math.max(0, c.energy - 8);
  const doc = {id, title, content, characterId, author: c.name, mode, accepted: false, credited: false, at: new Date().toISOString()};
  state.documents.unshift(doc); state.documents = state.documents.slice(0, 20);
  log(state, `${c.name} delivered “${title}” for review.`);
  return doc;
}
export function acceptDocument(state, id) {
  const doc = state.documents.find(d => d.id === id);
  if (!doc || doc.accepted) return;
  doc.accepted = true;
  if (!doc.credited) { state.characters.find(c => c.id === doc.characterId).tasks += 1; doc.credited = true; }
  log(state, `You approved “${doc.title}”. Document skill +1.`);
}
export function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
export function exportHTML(doc) {
  // Deliberately small Markdown subset; all text is escaped before insertion.
  let list = null;
  const blocks = [];
  const closeList = () => { if (list) blocks.push(`</${list}>`); list = null; };
  for (const line of doc.content.split('\n')) {
    const heading = /^(#{1,3})\s+(.+)$/.exec(line);
    const item = /^(?:([-*])|\d+\.)\s+(.+)$/.exec(line);
    if (heading) { closeList(); blocks.push(`<h${heading[1].length}>${escapeHTML(heading[2])}</h${heading[1].length}>`); }
    else if (item) { const kind = item[1] ? 'ul' : 'ol'; if (list !== kind) { closeList(); blocks.push(`<${kind}>`); list = kind; } blocks.push(`<li>${escapeHTML(item[2])}</li>`); }
    else { closeList(); if (line.trim()) blocks.push(`<p>${escapeHTML(line)}</p>`); }
  }
  closeList();
  return `<!doctype html><html lang="en"><meta charset="utf-8"><title>${escapeHTML(doc.title)}</title><style>body{max-width:760px;margin:48px auto;padding:24px;font:18px/1.6 system-ui;color:#172b25;overflow-wrap:anywhere}h1,h2,h3{line-height:1.2}small{color:#53645c}li{margin-bottom:8px}@media print{body{margin:0}}</style><small>Prepared by ${escapeHTML(doc.author)} · ${escapeHTML(doc.mode)}</small><article dir="auto">${blocks.join('')}</article></html>`;
}
export function restoreState(raw) {
  const s = JSON.parse(raw);
  if (s.version !== 1 || !Array.isArray(s.characters) || s.characters.length !== 2 || !Array.isArray(s.documents) || s.documents.length > 20 || !Array.isArray(s.activity)) throw new Error('Unsupported save file.');
  const validText = (v, max) => typeof v === 'string' && v.length <= max;
  for (const [i, c] of s.characters.entries()) {
    if (c.id !== ['milo','pip'][i] || !validText(c.name, 24) || !c.name.trim() || !ROLES.includes(c.role) || !['mint','coral'].includes(c.palette) || !Number.isFinite(c.energy) || c.energy < 0 || c.energy > 100 || !Number.isInteger(c.tasks) || c.tasks < 0 || !Array.isArray(c.memories) || c.memories.length > 50) throw new Error('Invalid character data.');
    const ids = new Set();
    for (const m of c.memories) {
      if (!validText(m.id, 80) || ids.has(m.id) || !TYPES.includes(m.type) || !validText(m.key, 80) || !validText(m.value, 600) || !m.key.trim() || !m.value.trim()) throw new Error('Invalid lesson data.');
      ids.add(m.id);
    }
  }
  if (!s.characters.some(c => c.id === s.selected) || !['day','night'].includes(s.room?.light) || typeof s.room?.plant !== 'boolean') throw new Error('Invalid workshop data.');
  if (new Set(s.documents.map(d => d.id)).size !== s.documents.length) throw new Error('Duplicate document IDs.');
  for (const d of s.documents) if (!validText(d.id,80) || !validText(d.title,120) || !validText(d.content,20000) || !validText(d.author,24) || !['milo','pip'].includes(d.characterId) || !['Template','Local AI'].includes(d.mode) || typeof d.accepted !== 'boolean' || typeof d.credited !== 'boolean' || !validText(d.at,40)) throw new Error('Invalid document data.');
  if (s.activity.length > 30 || s.activity.some(a => !validText(a.text,500) || !validText(a.at,40))) throw new Error('Invalid activity data.');
  return s;
}
