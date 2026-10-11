class_name GenesisState
extends RefCounted

var data: Dictionary
var last_error = ""
var save_enabled = true
const SAVE = "user://workshop.json"
var save_path = SAVE

func _init():
	data = fresh()

func fresh() -> Dictionary:
	return {"version":4, "selected":0, "berries":5, "stars":0, "night":false, "garden":false,
		"tasks":[], "settings":{"volume":0.65,"text_scale":1.0,"motion":true,"fullscreen":false}, "sound":true, "harvest_at":0, "seen_intro":false, "documents":[], "journal":[], "progress":{"fed":0,"rested":0,"claims":[]},
		"decor":{"lanterns":false,"reading_corner":false},
		"crew":[{"name":"Milo", "role":"Document maker", "energy":80, "approved":0, "lessons":[], "x":5.5, "y":8.2},
		{"name":"Pip", "role":"Reviewer", "energy":90, "approved":0, "lessons":[], "x":8.2, "y":6.8}]}

func actor() -> Dictionary:
	return data.crew[int(data.selected)]

func event(text: String):
	data.journal.push_front({"text":text, "at":Time.get_datetime_string_from_system()})
	if data.journal.size() > 30: data.journal.resize(30)

func teach(kind: String, key: String, value: String) -> bool:
	var previous=data.duplicate(true)
	key = key.strip_edges(); value = value.strip_edges()
	if kind not in ["preference","vocabulary","instruction"] or key.is_empty() or value.is_empty() or key.length()>80 or value.length()>600:
		last_error = "Give the lesson a name and something to remember."; return false
	var lessons = actor().lessons
	for lesson in lessons:
		if lesson.kind==kind and lesson.key.to_lower()==key.to_lower():
			lesson.value=value; event(actor().name+" corrected “"+key+"”.");return commit(previous)
	if lessons.size()>=50: last_error="Notebook full. Edit or forget an existing lesson."; return false
	lessons.append({"id":str(Time.get_ticks_usec()),"kind":kind,"key":key,"value":value})
	event(actor().name+" learned “"+key+"”.");return commit(previous)

func template(title: String, notes: String) -> String:
	var numbered = false; var signoff = ""; var glossary = ""
	for lesson in actor().lessons:
		if lesson.kind=="preference" and lesson.key.to_lower()=="format": numbered="number" in lesson.value.to_lower() or "step" in lesson.value.to_lower()
		if lesson.kind=="preference" and lesson.key.to_lower()=="sign-off": signoff=lesson.value
		if lesson.kind=="vocabulary": glossary += "\n- "+lesson.key+": "+lesson.value
	var content = "# "+title+"\n\n"; var index = 0
	for line in notes.split("\n"):
		if line.strip_edges().is_empty(): continue
		index+=1; content+=(str(index)+". " if numbered else "- ")+line.strip_edges()+"\n"
	if not glossary.is_empty(): content+="\n## Your glossary\n"+glossary+"\n"
	if not signoff.is_empty(): content+="\n"+signoff
	return content

func draft_document(title: String, content: String, mode: String, actor_index: int) -> Dictionary:
	var doc={"id":str(Time.get_ticks_usec())+"-"+str(randi()),"title":title,"content":content,"mode":mode,"actor":actor_index,"accepted":false,"credited":false}
	data.documents.push_front(doc)
	if data.documents.size()>20:data.documents.resize(20)
	data.crew[actor_index].energy=maxi(0,int(data.crew[actor_index].energy)-8)
	event(data.crew[actor_index].name+" delivered “"+title+"”.")
	return doc

func deliver(title: String, content: String, mode: String, actor_index: int) -> Dictionary:
	var previous=data.duplicate(true)
	var doc=draft_document(title,content,mode,actor_index)
	return doc if commit(previous) else {}

func complete_task(id: String, content: String) -> Dictionary:
	for task in data.tasks:
		if task.id!=id:continue
		if task.status=="completed":
			for doc in data.documents:
				if doc.id==task.document:return doc
			return {}
		if task.status not in ["queued","running"]:return {}
		var previous=data.duplicate(true)
		var doc=draft_document(task.title,content,task.mode,int(task.actor))
		task.status="completed";task.document=doc.id;task.error=""
		return doc if commit(previous) else {}
	return {}

func forget(id: String) -> bool:
	var previous=data.duplicate(true)
	for lesson in actor().lessons:
		if lesson.id==id:
			actor().lessons.erase(lesson);event("A lesson was forgotten.");return commit(previous)
	return false

func approve(doc: Dictionary) -> bool:
	if doc.accepted:return true
	var previous=data.duplicate(true)
	doc.accepted=true
	if not doc.credited:
		doc.credited=true; data.crew[int(doc.actor)].approved+=1; data.stars+=1
		event("You approved “"+doc.title+"”. A skill star earned.")
	return commit(previous)

func feed() -> String:
	if int(data.berries)<=0: return "The basket is empty. Visit the berry bush."
	if int(actor().energy)>=100: return actor().name+" is already full of energy."
	data.berries-=1; actor().energy=mini(100,int(actor().energy)+22)
	data.progress.fed+=1; event(actor().name+" enjoyed a berry."); save(); return "+22 energy. Thank you for the berry!"

func harvest() -> String:
	var now = int(Time.get_unix_time_from_system())
	if now-int(data.harvest_at)<30: return "New berries will be ready in "+str(30-(now-int(data.harvest_at)))+" seconds."
	data.harvest_at=now; data.berries=mini(50,int(data.berries)+3); save(); return "You gathered 3 berries for your companions."

func save() -> bool:
	if not save_enabled: return false
	var file=FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if file==null: last_error="Save unavailable. Back up your workshop from Settings."; return false
	file.store_string(JSON.stringify(data,"\t")); file.close()
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(save_path+".backup"))
	var result=DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".tmp"),ProjectSettings.globalize_path(save_path))
	if result!=OK: last_error="Could not save. Back up from Settings."; return false
	return true

func load_save():
	if not FileAccess.file_exists(save_path): return
	var file=FileAccess.open(save_path,FileAccess.READ)
	if file==null or file.get_length()>1500000:
		last_error="Save unreadable. Original file preserved."; save_enabled=false; return
	var parser=JSON.new()
	var parsed: Variant=null
	if parser.parse(file.get_as_text())==OK:parsed=parser.data
	if valid(parsed): adopt(parsed)
	else: last_error="Invalid save. Original file preserved; use Settings to restore a backup."; save_enabled=false

func valid(s: Variant) -> bool:
	if not s is Dictionary:return false
	if not (s.get("version") is int or s.get("version") is float):return false
	if s.version!=2 and s.version!=3 and s.version!=4:return false
	if not s.get("crew") is Array or s.crew.size()!=2: return false
	if not actor_index_ok(s.get("selected")) or not s.get("documents") is Array or s.documents.size()>20: return false
	for field in ["berries","stars","harvest_at"]:
		if not s.get(field) is float and not s.get(field) is int: return false
		if s[field]<0: return false
	for field in ["night","garden","sound","seen_intro"]:
		if not s.get(field) is bool: return false
	if not s.get("journal") is Array or s.journal.size()>30: return false
	for entry in s.journal:
		if not entry is Dictionary or not text_ok(entry.get("text"),500) or not text_ok(entry.get("at"),40): return false
	for crew in s.crew:
		if not crew is Dictionary or not text_ok(crew.get("name"),24) or crew.get("role") not in ["Document maker","Reviewer"]: return false
		if not crew.get("lessons") is Array or crew.lessons.size()>50: return false
		if not crew.get("energy") is float and not crew.get("energy") is int: return false
		if crew.energy<0 or crew.energy>100 or not (crew.get("approved") is float or crew.get("approved") is int) or crew.approved<0: return false
		for axis in ["x","y"]:
			if not (crew.get(axis) is float or crew.get(axis) is int) or crew[axis]<1 or crew[axis]>14: return false
		for lesson in crew.lessons:
			if not lesson is Dictionary or lesson.get("kind") not in ["preference","vocabulary","instruction"]: return false
			if not text_ok(lesson.get("id"),80) or not text_ok(lesson.get("key"),80) or not text_ok(lesson.get("value"),600): return false
	for doc in s.documents:
		if not doc is Dictionary or not text_ok(doc.get("id"),80) or not text_ok(doc.get("title"),120) or not text_ok(doc.get("content"),20000): return false
		if not actor_index_ok(doc.get("actor")) or doc.get("mode") not in ["Template","Local AI"] or not doc.get("accepted") is bool or not doc.get("credited") is bool: return false
	if s.version>=3:
		if not s.get("progress") is Dictionary or not s.get("decor") is Dictionary:return false
		for counter in ["fed","rested"]:
			if not (s.progress.get(counter) is int or s.progress.get(counter) is float) or s.progress[counter]<0:return false
		if not s.progress.get("claims") is Array or s.progress.claims.size()>6:return false
		var known=[]
		for claim in s.progress.claims:
			if claim not in ["lesson","delivery","approval","care","team","garden"] or claim in known:return false
			known.append(claim)
		for decoration in ["lanterns","reading_corner"]:
			if not s.decor.get(decoration) is bool:return false
	if s.version==4:
		if not s.get("tasks") is Array or s.tasks.size()>60 or not s.get("settings") is Dictionary:return false
		for task in s.tasks:
			if not task is Dictionary or task.get("status") not in ["queued","running","completed","failed","canceled"] or not text_ok(task.get("id"),80) or not text_ok(task.get("title"),120) or not text_ok(task.get("notes"),4000) or not actor_index_ok(task.get("actor")) or task.get("mode") not in ["Template","Local AI"] or not text_ok(task.get("error"),500) or not text_ok(task.get("document"),80):return false
		for key in ["volume","text_scale"]:
			if not (s.settings.get(key) is int or s.settings.get(key) is float):return false
		if s.settings.volume<0 or s.settings.volume>1 or s.settings.text_scale<1 or s.settings.text_scale>1.25 or not s.settings.get("motion") is bool or not s.settings.get("fullscreen") is bool:return false
	return true

func text_ok(value: Variant, limit: int) -> bool:
	return value is String and value.length()<=limit

func actor_index_ok(value: Variant) -> bool:
	return (value is int or value is float) and (value==0 or value==1)

func adopt(value: Dictionary):
	data=value.duplicate(true)
	if data.version==2:
		data.version=3
		data.progress={"fed":0,"rested":0,"claims":[]}
		data.decor={"lanterns":false,"reading_corner":false}

	if data.version<4:
		data.version=4;data.tasks=[];data.settings={"volume":0.65,"text_scale":1.0,"motion":true,"fullscreen":false}
	for task in data.tasks:
		if task.status in ["queued","running"]:task.status="failed";task.error="Interrupted before completion. Notes preserved; retry intentionally."

func rest(index: int):
	data.crew[index].energy=mini(100,int(data.crew[index].energy)+30)
	data.progress.rested+=1
	event(data.crew[index].name+" rested at the workshop.");save()

func level(index: int) -> int:
	return 1+int(int(data.crew[index].approved)/3.0)

func missions() -> Array:
	var lessons=data.crew[0].lessons.size()+data.crew[1].lessons.size()
	var approved=int(data.crew[0].approved)+int(data.crew[1].approved)
	return [
		{"id":"lesson","title":"A first word","description":"Teach either companion a lesson.","ready":lessons>0,"stars":0,"berries":2},
		{"id":"delivery","title":"Something worth making","description":"Create your first document in either mode.","ready":not data.documents.is_empty() or approved>0,"stars":0,"berries":2},
		{"id":"approval","title":"A careful eye","description":"Review and approve one document.","ready":approved>0,"stars":1,"berries":0},
		{"id":"care","title":"A little kindness","description":"Feed a companion and let one rest at the bed.","ready":data.progress.fed>0 and data.progress.rested>0,"stars":0,"berries":3},
		{"id":"team","title":"Better together","description":"Approve at least one document from each companion.","ready":data.crew[0].approved>0 and data.crew[1].approved>0,"stars":2,"berries":0},
		{"id":"garden","title":"Room to grow","description":"Plant the flower garden in Workshop.","ready":data.garden,"stars":0,"berries":5}]

func claim_mission(id: String) -> String:
	var previous=data.duplicate(true)
	if id in data.progress.claims:return "That mission reward has already been collected."
	for mission in missions():
		if mission.id!=id:continue
		if not mission.ready:return "Complete the mission before collecting its reward."
		data.progress.claims.append(id);data.stars+=mission.stars;data.berries=mini(50,int(data.berries)+mission.berries)
		event("Mission complete: "+mission.title+".")
		if not commit(previous):return last_error
		return "Mission complete! Your reward is in the basket."
	return "Mission not found."

func buy_upgrade(id: String) -> String:
	var previous=data.duplicate(true)
	var costs={"garden":2,"lanterns":3,"reading_corner":4}
	if not costs.has(id):return "Upgrade not found."
	var owned=bool(data.garden) if id=="garden" else bool(data.decor[id])
	if owned:return "This upgrade is already part of your workshop."
	if int(data.stars)<int(costs[id]):return "Earn more skill stars by reviewing documents and collecting mission rewards."
	data.stars-=costs[id]
	if id=="garden":data.garden=true
	else:data.decor[id]=true
	event("Workshop upgraded: "+id.replace("_"," ")+".")
	if not commit(previous):return last_error
	return "Your workshop has a new addition!"

func queue_task(title: String, notes: String, index: int, mode: String) -> Dictionary:
	var task={"id":str(Time.get_ticks_usec())+"-"+str(randi()),"title":title,"notes":notes,"actor":index,"mode":mode,"status":"queued","error":"","document":""}
	data.tasks.push_front(task)
	if data.tasks.size()>60:data.tasks.resize(60)
	if not save():
		data.tasks.erase(task);last_error="Task could not be saved. Choose a writable workshop before creating.";return {}
	return task

func task_status(id: String, status: String, error="", document="") -> bool:
	var previous=data.duplicate(true)
	for task in data.tasks:
		if task.id==id:
			task.status=status;task.error=error;task.document=document;return commit(previous)
	return false

func commit(previous: Dictionary) -> bool:
	if save():return true
	# Keep document references held by review panels while rolling back rewards.
	for i in previous.documents.size():
		for doc in data.documents:
			if doc.id==previous.documents[i].id:
				doc.clear();doc.merge(previous.documents[i],true);previous.documents[i]=doc;break
	data=previous
	last_error="Changes could not be saved. Your previous workshop state was kept. Back up from Settings and check save folder permissions."
	return false
