class_name GenesisProfiles
extends RefCounted
const INDEX="user://profiles.json"
var index_path=INDEX
var entries: Array=[]
var selected=""
var error=""
var writable=true
var storage = GenesisSaveFiles.new()
var disk_revision: Dictionary={"active":null,"backup":null}
var revision_path=""

func valid_index(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema")!=4 or not value.get("profiles") is Array or value.profiles.size()>20:return false
	var ids=[]
	for entry in value.profiles:
		if not entry is Dictionary or not entry.get("id") is String or not (entry.id.is_valid_int() and not entry.id.begins_with("-") and entry.id.length()<=24) or entry.id in ids or not entry.get("name") is String or entry.name.length()>40:return false
		ids.append(entry.id)
	return value.get("selected") is String and (value.selected.is_empty() or value.selected in ids)

func load_index():
	var record=storage.read_json(index_path,valid_index,20000)
	if record.has("revision"):disk_revision=record.revision;revision_path=index_path
	if record.get("missing",false):return
	error=record.error
	if not record.ok:writable=false;return
	entries=record.data.profiles;selected=record.data.selected

func persist() -> bool:
	if not writable:error="Profile index writes disabled to preserve the original.";return false
	var expected=disk_revision if revision_path==index_path else {"active":null,"backup":null}
	error=storage.write_json(index_path,JSON.stringify({"schema":4,"selected":selected,"profiles":entries}),valid_index,20000,expected)
	if not storage.last_revision.is_empty():disk_revision=storage.last_revision.duplicate();revision_path=index_path
	return error.is_empty()

func create(name: String, legacy=false, restored: Dictionary={}) -> GenesisState:
	if not writable or entries.size()>=20:return null
	var state=GenesisState.new()
	if legacy:
		state.load_save()
		if not state.save_enabled:error=state.last_error;return null
	if not restored.is_empty():
		if not state.valid(restored):error="Invalid backup; original workshops preserved.";return null
		state.adopt(restored)
	var id=str(int(Time.get_unix_time_from_system()*1000000))
	while entries.any(func(item):return item.id==id):id=str(int(id)+1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://profiles"))
	state.save_path="user://profiles/"+id+".json"
	if not state.save():error=state.last_error;return null
	var previous_selected=selected
	entries.append({"id":id,"name":name.strip_edges().left(40) if not name.strip_edges().is_empty() else "My workshop"});selected=id
	if not persist():
		entries.pop_back();selected=previous_selected;return null
	return state

func open_profile(id: String) -> GenesisState:
	if not entries.any(func(item):return item.id==id):return null
	var state=GenesisState.new();state.save_path="user://profiles/"+id+".json"
	if not FileAccess.file_exists(state.save_path) and not FileAccess.file_exists(state.save_path+".backup"):error="Profile save missing. Other workshops preserved.";return null
	state.load_save()
	if not state.save_enabled:error=state.last_error;return null
	if not state.save():error=state.last_error;return null
	var previous_selected=selected;selected=id
	if not persist():selected=previous_selected;return null
	return state
