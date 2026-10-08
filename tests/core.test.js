import test from 'node:test';
import assert from 'node:assert/strict';
import {initialState,teach,character,templateDocument,completeTask,acceptDocument,restoreState,exportHTML,validateTask} from '../web/core.js';
test('lessons persist, corrections replace lessons, and notebooks belong to each character',()=>{
  const s=initialState();teach(s,{type:'preference',key:'format',value:'numbered steps'},'first');
  assert.equal(character(s).memories.length,1);s.selected='pip';assert.equal(character(s).memories.length,0);
  s.selected='milo';teach(s,{type:'preference',key:'FORMAT',value:'bullet points'},'second');
  assert.equal(character(s).memories.length,1);assert.equal(character(s).memories[0].id,'first');
  assert.equal(character(restoreState(JSON.stringify(s))).memories[0].value,'bullet points');
});
test('teaching format changes actual output; sign-off and glossary are included',()=>{
  const s=initialState(),c=character(s);assert.match(templateDocument(c,'Plan','One\nTwo'),/- One/);
  teach(s,{type:'preference',key:'format',value:'numbered steps'});teach(s,{type:'preference',key:'sign-off',value:'From our workshop'});teach(s,{type:'vocabulary',key:'Sach',value:'Truth'});
  const doc=templateDocument(c,'Plan','One\nTwo');assert.match(doc,/1\. One\n2\. Two/);assert.match(doc,/Sach: Truth/);assert.match(doc,/From our workshop$/);
});
test('only user approval grants progress and repeated approval does not duplicate it',()=>{
  const s=initialState();const d=completeTask(s,{characterId:'milo',title:'A',content:'Real document',mode:'Template'});
  assert.equal(character(s).tasks,0);assert.equal(character(s).energy,64);acceptDocument(s,d.id);acceptDocument(s,d.id);assert.equal(character(s).tasks,1);d.accepted=false;acceptDocument(s,d.id);assert.equal(character(s).tasks,1);
});
test('export keeps Urdu text and escapes executable HTML',()=>{
  const html=exportHTML({title:'سلام',author:'Milo',mode:'Template',content:'<script>alert(1)</script> اردو'});
  assert.match(html,/سلام/);assert.match(html,/اردو/);assert.ok(!html.includes('<script>'));assert.match(html,/&lt;script&gt;/);
});
test('invalid saves and oversized notes are rejected',()=>{
  assert.throws(()=>restoreState('{}'));const s=initialState();s.characters[0].energy=-1;assert.throws(()=>restoreState(JSON.stringify(s)));
  assert.throws(()=>validateTask('Title',''));assert.throws(()=>validateTask('Title','x'.repeat(6001)));
});

test('printable export renders headings and lists without executing HTML',()=>{
 const html=exportHTML({title:'Plan',author:'Milo',mode:'Template',content:'# Plan\n1. First\n2. Second\n\n## Notes\n- Item'});
 assert.match(html,/<h1>Plan<\/h1>/);assert.match(html,/<ol><li>First<\/li><li>Second<\/li><\/ol>/);assert.match(html,/<ul><li>Item<\/li><\/ul>/);
});
