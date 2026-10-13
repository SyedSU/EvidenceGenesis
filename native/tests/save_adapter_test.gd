extends SceneTree

func _initialize():
	var storage=GenesisSaveFiles.new()
	if "--expect-missing" in OS.get_cmdline_user_args():
		if storage.native_available():quit(1);return
		var state=GenesisState.new();state.save_path="user://missing-adapter.json"
		if state.save() or FileAccess.file_exists(state.save_path) or not state.last_error.contains("unavailable"):quit(2);return
		print("GENESIS_MISSING_ADAPTER_OK: no buffered fallback or active save");quit();return
	if not storage.native_available():quit(3);return
	var path="user://adapter-ورکشاپ-🐾.json"
	var stage=FileAccess.open(path,FileAccess.WRITE);stage.store_string("original");stage.close()
	if storage.sync_file(path)!=OK:quit(4);return
	var invalid=ProjectSettings.globalize_path(path)+String.chr(0)+"ignored"
	if ClassDB.class_call_static("GenesisDurableFiles","sync_file",invalid)==0:quit(5);return
	if FileAccess.get_file_as_string(path)!="original":quit(6);return
	print("GENESIS_SAVE_ADAPTER_OK: C ABI, Unicode and NUL refusal");quit()
