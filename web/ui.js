import {character, escapeHTML as esc} from './core.js';
import {portrait} from './scene.js';
export const $=id=>document.getElementById(id);
export function feedback(text,error=false){$('feedback').textContent=text;$('feedback').dataset.error=String(error);}
export function render(state,select,edit,remove,open){
  const c=character(state);
  $('crew').innerHTML=state.characters.map(ch=>`<button class="companion" data-id="${ch.id}" aria-pressed="${ch.id===state.selected}"><canvas class="portrait" width="44" height="44" aria-hidden="true" data-palette="${ch.palette}"></canvas><span><strong>${esc(ch.name)}</strong><small>${esc(ch.role)}</small></span><span class="companion-stats">Energy ${ch.energy}/100 · ${ch.tasks} approved<span class="energy-track"><span style="width:${ch.energy}%"></span></span></span></button>`).join('');
  $('crew').querySelectorAll('button').forEach(b=>b.onclick=()=>select(b.dataset.id));
  $('crew').querySelectorAll('canvas').forEach(canvas=>portrait(canvas,canvas.dataset.palette));
  $('companion-title').textContent=`${c.name}’s notebook`;
  $('companion-subtitle').textContent=c.role==='Reviewer'?'A reviewer, learning from you.':'A document maker, learning from you.';
  $('memory-count').textContent=c.memories.length;
  $('world-status').textContent=`${c.name} · ${c.tasks ? 'Document skill: '+c.tasks+' approved' : 'Ready for a first lesson'}`;
  $('light-button').textContent=state.room.light==='day'?'Evening light':'Morning light';
  $('memories').innerHTML=c.memories.length?c.memories.map(m=>`<article class="memory-card"><small>${esc(m.type.toUpperCase())} · TAUGHT BY YOU</small><strong>${esc(m.key)}</strong><p dir="auto">${esc(m.value)}</p><button data-edit="${esc(m.id)}">Edit</button><button data-remove="${esc(m.id)}" aria-label="Forget ${esc(m.key)}">Forget</button></article>`).join(''):'<p class="empty">An unwritten notebook.<br>Teach a word, a preference, or an instruction to begin.</p>';
  $('memories').querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>edit(b.dataset.edit));
  $('memories').querySelectorAll('[data-remove]').forEach(b=>b.onclick=()=>remove(b.dataset.remove));
  $('activity').innerHTML=state.activity.slice(0,5).map(a=>`<li><time>${time(a.at)}</time><span>${esc(a.text)}</span></li>`).join('');
  $('document-count').textContent=`${state.documents.length} document${state.documents.length===1?'':'s'}`;
  $('deliveries').innerHTML=state.documents.length?state.documents.map(d=>`<article class="delivery"><div><strong>${esc(d.title)}</strong><small>${esc(d.author)} · ${esc(d.mode)} · ${d.accepted?'Approved':'Awaiting your review'}</small></div><button data-doc="${esc(d.id)}">Review ↗</button></article>`).join(''):'<p class="empty">Your first creation belongs here.<br>Open Create and give your companion some notes.</p>';
  $('deliveries').querySelectorAll('[data-doc]').forEach(b=>b.onclick=()=>open(b.dataset.doc));
}
function time(value){const date=new Date(value);return Number.isNaN(+date)?'—':esc(date.toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}));}
export function tab(name,focus=false){
  for(const t of ['teach','task','memory']){
    const active=t===name;$(`tab-${t}`).setAttribute('aria-selected',String(active));$(`tab-${t}`).tabIndex=active?0:-1;$(`panel-${t}`).hidden=!active;
  }
  if(focus)$(`tab-${name}`).focus();
}
export function download(name,content,type){
  const url=URL.createObjectURL(new Blob([content],{type}));
  const link=document.createElement('a');link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
export function safeName(name){return name.replace(/[^a-zA-Z0-9_-]/g,'-').replace(/-+/g,'-').slice(0,64)||'genesis-document';}
