extends SceneTree

class InterruptedStorage extends GenesisSaveFiles:
	var phase=""
	func boundary(name: String):
		if phase!=name:return
		print("CRASH_BOUNDARY:"+name)
		var marker=FileAccess.open("user://boundary.json",FileAccess.WRITE)
		marker.store_string(JSON.stringify({"phase":name}));marker.flush();marker.close()
		while true:OS.delay_msec(20)
	func store_checked(path: String, bytes: PackedByteArray) -> String:
		var result=super.store_checked(path,bytes)
		if result.is_empty() and path.begins_with("user://crash.json.tmp-"):boundary("after_stage")
		return result
	func replace(source: String, destination: String) -> Error:
		if destination=="user://crash.json" and phase=="after_delete":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(destination));boundary("after_delete")
		if destination=="user://crash.json":boundary("before_replace")
		var result=super.replace(source,destination)
		if result==OK:
			if destination=="user://crash.json.backup":boundary("after_backup")
			if destination=="user://crash.json":boundary("after_commit")
		return result

func _initialize():
	var args=OS.get_cmdline_user_args()
	print("CRASH_INIT:"+JSON.stringify({"args":args,"userDirectory":OS.get_user_data_dir(),"native":ClassDB.class_exists("GenesisDurableFiles")}))
	var kind="index" if "--index" in args else "state"
	if "--read" in args:
		if kind=="index":
			var profiles=GenesisProfiles.new();profiles.index_path="user://crash.json";profiles.load_index()
			print("CRASH_READ:"+JSON.stringify({"ok":profiles.writable and profiles.entries.size()==1,"value":profiles.entries[0].name if not profiles.entries.is_empty() else "missing"}));quit();return
		var loaded=GenesisState.new();loaded.save_path="user://crash.json";loaded.load_save()
		var stars=loaded.data.stars;var credits=loaded.data.crew[0].approved
		if not loaded.data.documents.is_empty():loaded.approve(loaded.data.documents[0])
		print("CRASH_READ:"+JSON.stringify({"ok":loaded.save_enabled and loaded.valid(loaded.data),"value":stars,"dedupe":loaded.data.stars==stars and loaded.data.crew[0].approved==credits}));quit();return
	var adapter=InterruptedStorage.new()
	for arg in args:
		if arg.begins_with("--phase="):adapter.phase=arg.trim_prefix("--phase=")
	if kind=="index":
		var profiles=GenesisProfiles.new();profiles.index_path="user://crash.json";profiles.entries=[{"id":"1","name":"Before"}];profiles.selected="1"
		print("CRASH_BASELINE:index")
		if not profiles.persist() or not profiles.persist():print("CRASH_BASELINE_FAILED:"+profiles.error);quit(2);return
		print("CRASH_BASELINE_OK:index")
		profiles.storage=adapter;profiles.entries[0].name="After";profiles.persist()
	else:
		var state=GenesisState.new();state.save_path="user://crash.json"
		var doc=state.deliver("Recovery","Reviewed notes","Template",0)
		if doc.is_empty() or not state.approve(doc) or not state.save():quit(2);return
		state.storage=adapter;state.data.stars+=1;state.save()
	quit(3) # Parent must kill us at the requested real operation boundary.
