extends SceneTree

func _initialize():
	var state=GenesisState.new();state.save_path="user://crash.json"
	state.load_save()
	if "--released" in OS.get_cmdline_user_args():
		assert(state.save_enabled)
		assert(state.save())
		print("GENESIS_TRANSACTION_RELEASED_OK")
	else:
		assert(not state.save_enabled)
		assert(state.last_error.contains("transaction lock"))
		print("GENESIS_TRANSACTION_BUSY_OK")
	quit()
