class_name GenesisState
extends RefCounted

var data: Dictionary
var last_error = ""
var save_enabled = true
const SAVE = "user://workshop.json"

func _init():
	data = fresh()

func fresh() -> Dictionary:
	return {"version":2, "selected":0, "berries":5, "stars":0, "night":false, "garden":false,
		"sound":true, "harvest_at":0, "seen_intro":false, "documents":[], "journal":[],
		"crew":[{"name":"Milo", "role":"Document maker", "energy":80, "approved":0, "lessons":[], "x":5.5, "y":8.2},
		{"name":"Pip", "role":"Reviewer", "energy":90, "approved":0, "lessons":[], "x":8.2, "y":6.8}]}

func actor() -> Dictionary:
	return data.crew[int(data.selected)]

func event(text: String):
	data.journal.push_front({"text":text, "at":Time.get_datetime_string_from_system()})
	if data.journal.size() > 30: data.journal.resize(30)

func teach(kind: String, key: String, value: String) -> bool:
	key = key.strip_edges(); value = value.strip_edges()
	if kind not in ["preference","vocabulary","instruction"] or key.is_empty() or value.is_empty() or key.length()>80 or value.length()>600:
		last_error = "Give the lesson a name and something to remember."; return false
	var lessons = actor().lessons
	for lesson in lessons:
		if lesson.kind==kind and lesson.key.to_lower()==key.to_lower():
			lesson.value=value; event(actor().name+" corrected “"+key+"”."); save(); return true
	if lessons.size()>=50: last_error="Notebook full. Edit or forget an existing lesson."; return false
	lessons.append({"id":str(Time.get_ticks_usec()),"kind":kind,"key":key,"value":value})
	event(actor().name+" learned “"+key+"”."); save(); return true

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

func deliver(title: String, content: String, mode: String, actor_index: int) -> Dictionary:
	var doc={"id":str(Time.get_ticks_usec())+"-"+str(randi()),"title":title,"content":content,"mode":mode,"actor":actor_index,"accepted":false,"credited":false}
	data.documents.push_front(doc)
	if data.documents.size()>20: data.documents.resize(20)
	data.crew[actor_index].energy=maxi(0,int(data.crew[actor_index].energy)-8)
	event(data.crew[actor_index].name+" delivered “"+title+"”."); save(); return doc

func approve(doc: Dictionary):
	if doc.accepted: return
	doc.accepted=true
	if not doc.credited:
		doc.credited=true; data.crew[int(doc.actor)].approved+=1; data.stars+=1
		event("You approved “"+doc.title+"”. A skill star earned.")
	save()

func feed() -> String:
	if int(data.berries)<=0: return "The basket is empty. Visit the berry bush."
	if int(actor().energy)>=100: return actor().name+" is already full of energy."
	data.berries-=1; actor().energy=mini(100,int(actor().energy)+22)
	event(actor().name+" enjoyed a berry."); save(); return "+22 energy. Thank you for the berry!"

func harvest() -> String:
	var now = int(Time.get_unix_time_from_system())
	if now-int(data.harvest_at)<30: return "New berries will be ready in "+str(30-(now-int(data.harvest_at)))+" seconds."
	data.harvest_at=now; data.berries=mini(50,int(data.berries)+3); save(); return "You gathered 3 berries for your companions."

func save() -> bool:
	if not save_enabled: return false
	var file=FileAccess.open(SAVE+".tmp",FileAccess.WRITE)
	if file==null: last_error="Save unavailable. Back up your workshop from Settings."; return false
	file.store_string(JSON.stringify(data,"\t")); file.close()
	if FileAccess.file_exists(SAVE):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE),ProjectSettings.globalize_path(SAVE+".backup"))
	var result=DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE+".tmp"),ProjectSettings.globalize_path(SAVE))
	if result!=OK: last_error="Could not save. Back up from Settings."; return false
	return true

func load_save():
	if not FileAccess.file_exists(SAVE): return
	var file=FileAccess.open(SAVE,FileAccess.READ)
	if file==null or file.get_length()>1500000:
		last_error="Save unreadable. Original file preserved."; save_enabled=false; return
	var parser=JSON.new()
	var parsed: Variant=null
	if parser.parse(file.get_as_text())==OK:parsed=parser.data
	if valid(parsed): data=parsed
	else: last_error="Invalid save. Original file preserved; use Settings to restore a backup."; save_enabled=false

func valid(s: Variant) -> bool:
	if not s is Dictionary or s.get("version")!=2: return false
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
	return true

func text_ok(value: Variant, limit: int) -> bool:
	return value is String and value.length()<=limit

func actor_index_ok(value: Variant) -> bool:
	return (value is int or value is float) and (value==0 or value==1)
