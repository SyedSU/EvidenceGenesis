class_name GenesisProfiles
extends RefCounted
const INDEX="user://profiles.json"
var entries: Array=[]
var selected=""
var error=""
var writable=true

func load_index():
	if not FileAccess.file_exists(INDEX):return
	var file=FileAccess.open(INDEX,FileAccess.READ)
	if file==null or file.get_length()>20000:error="Profile index unreadable. Original preserved.";writable=false;return
	var parser=JSON.new();var value: Variant=null
	if parser.parse(file.get_as_text())==OK:value=parser.data
	file.close()
	if not value is Dictionary or value.get("schema")!=4 or not value.get("profiles") is Array or value.profiles.size()>20:
		error="Profile index invalid. Original preserved.";writable=false;return
	var ids=[]
	for entry in value.profiles:
		if not entry is Dictionary or not entry.get("id") is String or not (entry.id.is_valid_int() and not entry.id.begins_with("-") and entry.id.length()<=24) or entry.id in ids or not entry.get("name") is String or entry.name.length()>40:
			error="Profile index invalid. Original preserved.";writable=false;return
		ids.append(entry.id)
	entries=value.profiles;selected=value.get("selected","")
	if not selected is String or (not selected.is_empty() and selected not in ids):error="Invalid selected profile.";writable=false

func persist() -> bool:
	if not writable:return false
	var file=FileAccess.open(INDEX+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify({"schema":4,"selected":selected,"profiles":entries}));file.close()
	if FileAccess.file_exists(INDEX):DirAccess.copy_absolute(ProjectSettings.globalize_path(INDEX),ProjectSettings.globalize_path(INDEX+".backup"))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(INDEX+".tmp"),ProjectSettings.globalize_path(INDEX))==OK

func create(name: String, legacy=false) -> GenesisState:
	if not writable or entries.size()>=20:return null
	var state=GenesisState.new()
	if legacy:
		state.load_save()
		if not state.save_enabled:error=state.last_error;return null
	var id=str(int(Time.get_unix_time_from_system()*1000000))
	while entries.any(func(item):return item.id==id):id=str(int(id)+1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://profiles"))
	state.save_path="user://profiles/"+id+".json"
	if not state.save():error=state.last_error;return null
	entries.append({"id":id,"name":name.strip_edges().left(40) if not name.strip_edges().is_empty() else "My workshop"});selected=id
	if not persist():
		entries.pop_back();selected="";error="Profile index could not save. Existing workshops preserved.";return null
	return state

func open_profile(id: String) -> GenesisState:
	if not entries.any(func(item):return item.id==id):return null
	var state=GenesisState.new();state.save_path="user://profiles/"+id+".json"
	if not FileAccess.file_exists(state.save_path):error="Profile save missing. Other workshops preserved.";return null
	state.load_save()
	if not state.save_enabled:error=state.last_error;return null
	selected=id
	if not persist():error="Profile index could not save.";return null
	if not state.save():error=state.last_error;return null
	return state
