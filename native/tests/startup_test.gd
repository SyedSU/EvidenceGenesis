extends SceneTree

func _initialize():call_deferred("run")

func run():
	# A valid index pointing at a missing profile must never enable legacy writes.
	var legacy=FileAccess.open(GenesisState.SAVE,FileAccess.WRITE)
	legacy.store_string("protected legacy save");legacy.close()
	var index=FileAccess.open(GenesisProfiles.INDEX,FileAccess.WRITE)
	index.store_string(JSON.stringify({"schema":4,"selected":"123","profiles":[{"id":"123","name":"Missing profile"}]}));index.close()
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	assert(not game.state.save_enabled)
	game.autosave=21
	await process_frame
	assert(FileAccess.get_file_as_string(GenesisState.SAVE)=="protected legacy save")
	assert(game.overlay.position.y+game.overlay.size.y<=720)
	game.state.data.settings.text_scale=1.15;game.apply_settings()
	assert(game.hud_name.get_theme_font_size("font_size")==20)
	print("GENESIS_STARTUP_TEST_OK: missing profile preserves legacy, menu fits, text scales")

	var backup=FileAccess.open("user://restore-test.json",FileAccess.WRITE);backup.store_string(JSON.stringify(GenesisState.new().fresh()));backup.close()
	game.export_kind="restore";game.panels.export_selected("user://restore-test.json")
	assert(game.state.save_path!=GenesisState.SAVE and game.profiles.entries.size()==2)
	assert(FileAccess.get_file_as_string(GenesisState.SAVE)=="protected legacy save")
	var previous=game.state.data.duplicate(true);var changed=previous.duplicate(true);changed.stars=7
	backup=FileAccess.open("user://restore-test.json",FileAccess.WRITE);backup.store_string(JSON.stringify(changed));backup.close()
	game.state.save_enabled=false;game.panels.export_selected("user://restore-test.json")
	assert(game.state.data.stars==previous.stars and not game.message.text.contains("Workshop restored"))
	print("GENESIS_RESTORE_TEST_OK: menu restore creates profile, failed restore rolls back")
	game.shutdown()
