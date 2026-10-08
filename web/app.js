import {initialState,STORAGE_KEY,character,teach,log,templateDocument,validateTask,completeTask,acceptDocument,restoreState,exportHTML} from './core.js';
import {createScene} from './scene.js';
import {$,render,feedback,tab,download,safeName} from './ui.js';
let state=initialState(), storageError=false, preserveBadSave=false;
try{const raw=localStorage.getItem(STORAGE_KEY);if(raw)state=restoreState(raw);}catch{storageError=true;preserveBadSave=true;}
let busy=false,activeDoc=null;
const scene=createScene($('world'),()=>state);
function save(){try{if(preserveBadSave)throw new Error();localStorage.setItem(STORAGE_KEY,JSON.stringify(state));storageError=false;}catch{storageError=true;}$('save-status').textContent=storageError?'Save unavailable · download a backup':'Saved on this device';}
function update(){render(state,select,editMemory,removeMemory,openDocument);scene.refresh();save();}
function select(id){if(busy){feedback('Wait for this document before changing companions.');return;}state.selected=id;feedback('');update();}
function editMemory(id){const m=character(state).memories.find(m=>m.id===id);$('lesson-type').value=m.type;$('lesson-key').value=m.key;$('lesson-value').value=m.value;tab('teach');$('lesson-value').focus();feedback('Save with the same type and name to update this lesson.');}
function removeMemory(id){if(busy){feedback('Wait for the current task before editing memory.');return;}const c=character(state);const m=c.memories.find(m=>m.id===id);c.memories=c.memories.filter(m=>m.id!==id);log(state,`${c.name} forgot “${m.key}”.`);update();tab('memory');}
for(const t of ['teach','task','memory'])$(`tab-${t}`).onclick=()=>tab(t);
document.querySelector('.tabs').onkeydown=e=>{if(!['ArrowRight','ArrowLeft','Home','End'].includes(e.key))return;e.preventDefault();const tabs=['teach','task','memory'];const i=tabs.findIndex(t=>$(`tab-${t}`).getAttribute('aria-selected')==='true');tab(tabs[e.key==='Home'?0:e.key==='End'?2:(i+(e.key==='ArrowRight'?1:2))%3],true);};
$('lesson-form').onsubmit=e=>{e.preventDefault();if(busy)return;try{const m=teach(state,{type:$('lesson-type').value,key:$('lesson-key').value,value:$('lesson-value').value});update();feedback(`${character(state).name} remembers “${m.key}”.`);$('world-caption').textContent='A little lesson. A new possibility.';$('lesson-form').reset();}catch(err){feedback(err.message,true);}};
$('example-button').onclick=()=>{tab('teach');$('lesson-type').value='preference';$('lesson-key').value='format';$('lesson-value').value='numbered steps';$('lesson-value').focus();};
$('task-form').onsubmit=async e=>{
  e.preventDefault();if(busy)return;
  const title=$('task-title').value.trim(),notes=$('task-notes').value.trim(),mode=$('task-mode').value,c=character(state);
  try{validateTask(title,notes);if(c.energy<8)throw new Error('Your companion needs a berry or a rest first.');
    busy=true;$('run-button').disabled=true;$('lesson-form').querySelector('button').disabled=true;scene.setBusy(c.id);
    feedback(`${c.name} is preparing your document…`);$('world-caption').textContent='An idea is becoming something you can keep.';
    let content;
    if(mode==='local'){
      const response=await fetch('/api/generate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({title,notes,character:{name:c.name,role:c.role},memories:c.memories}),signal:AbortSignal.timeout(125000)});
      const result=await response.json();if(!response.ok)throw new Error(result.error||'The local model could not finish.');content=result.content;
    }else{content=templateDocument(c,title,notes);}
    const doc=completeTask(state,{characterId:c.id,title,content,mode:mode==='local'?'Local AI':'Template'});update();feedback('Document delivered. Review it before approving.');openDocument(doc.id);
  }catch(err){feedback(err.name==='TimeoutError'?'The local model timed out. Your notes are still here.':err.message,true);$('world-caption').textContent='We can try again. Your notes are still here.';}
  finally{busy=false;$('run-button').disabled=false;$('lesson-form').querySelector('button').disabled=false;scene.setBusy(null);}
};
function care(kind){if(busy)return;const c=character(state);c.energy=Math.min(100,c.energy+(kind==='feed'?18:28));log(state,`${c.name} ${kind==='feed'?'enjoyed a berry':'took a quiet rest'}.`);update();feedback(`${c.name} has ${c.energy}/100 energy.`);$('world-caption').textContent=kind==='feed'?'Good things grow with a little care.':'A moment to breathe, then begin again.';}
$('feed-button').onclick=()=>care('feed');$('rest-button').onclick=()=>care('rest');
$('light-button').onclick=()=>{state.room.light=state.room.light==='day'?'night':'day';update();};
$('plant-button').onclick=()=>{state.room.plant=!state.room.plant;update();};
$('settings-button').onclick=()=>{const c=character(state);$('character-name').value=c.name;$('character-role').value=c.role;$('settings-feedback').textContent='';$('settings').showModal();};
$('save-character').onclick=()=>{if(busy){$('settings-feedback').textContent='Wait for the current document first.';return;}const name=$('character-name').value.trim();if(!name){$('settings-feedback').textContent='Your companion needs a name.';return;}const c=character(state);c.name=name;c.role=$('character-role').value;log(state,`${name} is now your ${c.role.toLowerCase()}.`);update();$('settings-feedback').textContent='Companion updated.';};
$('check-model').onclick=async()=>{const b=$('check-model');b.disabled=true;$('model-status').textContent='Checking your local model…';try{const response=await fetch('/api/health',{signal:AbortSignal.timeout(6000)});const info=await response.json();$('model-status').textContent=info.available?`Connected: ${info.model}. Local AI mode is ready.`:'No local model connected. Start your model server; template mode remains available.';}catch{$('model-status').textContent='Local runtime unavailable. Start with python runtime/server.py.';}finally{b.disabled=false;}};
$('backup-button').onclick=()=>download('genesis-workshop-backup.json',JSON.stringify(state,null,2),'application/json');
document.querySelector('.file-button').onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();$('restore-file').click();}};
$('restore-file').onchange=async e=>{const file=e.target.files[0];if(!file)return;try{if(busy)throw new Error('Wait for the document before restoring a save.');if(file.size>1500000)throw new Error('Backup is too large.');const restored=restoreState(await file.text());state=restored;preserveBadSave=false;update();$('settings').close();feedback('Workshop restored.');}catch(err){$('settings-feedback').textContent=err.message;}finally{e.target.value='';}};
function openDocument(id){activeDoc=id;const d=state.documents.find(d=>d.id===id);$('document-title').textContent=d.title;$('document-meta').textContent=`${d.author} · ${d.mode} · ${d.accepted?'Approved':'Waiting for your review'}`;$('document-content').value=d.content;$('approve-document').disabled=d.accepted;$('approve-document').textContent=d.accepted?'Already approved':'Approve document';$('document-feedback').textContent='';$('document-dialog').showModal();}
function editedDoc(){const d=state.documents.find(d=>d.id===activeDoc);const text=$('document-content').value;if(!text.trim()){$('document-feedback').textContent='The document cannot be empty.';return null;}if(d.content!==text){d.content=text;d.accepted=false;$('approve-document').disabled=false;$('approve-document').textContent='Approve document';update();}return d;}
$('save-document').onclick=()=>{if(editedDoc())$('document-feedback').textContent='Edits saved. Review and approve the current version.';};
$('download-md').onclick=()=>{const d=editedDoc();if(d)download(safeName(d.title)+'.md',d.content,'text/markdown;charset=utf-8');};
$('download-html').onclick=()=>{const d=editedDoc();if(d)download(safeName(d.title)+'.html',exportHTML(d),'text/html;charset=utf-8');};
$('print-document').onclick=()=>{const d=editedDoc();if(!d)return;const frame=document.createElement('iframe');frame.style.display='none';frame.title='Printable document';frame.onload=()=>{frame.contentWindow.focus();frame.contentWindow.print();setTimeout(()=>frame.remove(),1000);};frame.srcdoc=exportHTML(d);document.body.append(frame);};
$('approve-document').onclick=()=>{const d=editedDoc();if(!d)return;acceptDocument(state,d.id);update();$('approve-document').disabled=true;$('approve-document').textContent='Already approved';$('document-meta').textContent=`${d.author} · ${d.mode} · Approved`;$('document-feedback').textContent='Approved. Your companion earned document skill progress.';};
update();if(storageError)feedback('Your previous save could not be loaded or storage is blocked. It has not been overwritten. Download a backup of this session.',true);
