extends Node2D

var state=GenesisState.new()
var profiles=GenesisProfiles.new()
var menu_open=false
var hud_parts: Array=[]
var world: GenesisWorld
var brain: GenesisBrain
var ui: Control
var overlay: PanelContainer
var panel_root: VBoxContainer
var panels: GenesisPanels
var notebook: GenesisNotebook
var hud_name: Label
var hud_stats: Label
var hud_quest: Label
var hud_location: Label
var crew_buttons: Array=[]
var hud_ai: Label
var message: Label
var audio: AudioStreamPlayer
var toast_timer=0.0
var autosave=0.0
var pending: Dictionary={}
var current_document: Dictionary={}
var document_editor: TextEdit
var file_dialog: FileDialog
var file_content=""
var export_kind=""
var session_chat: Array=[]
var chat_log: Label
var chat_input: LineEdit
var chat_button: Button
var screenshot_frames=0

func _ready():
	# Menu startup must never autosave a fresh state over a legacy file.
	state.save_enabled=false
	profiles.load_index()
	if not profiles.selected.is_empty():
		var existing=profiles.open_profile(profiles.selected)
		if existing!=null:state=existing
	if profiles.selected.is_empty():state.save_enabled=false
	world=GenesisWorld.new();add_child(world);world.setup(state)
	world.interact.connect(interaction);world.selected.connect(select_actor)
	brain=GenesisBrain.new();add_child(brain)
	brain.status_changed.connect(func(_text):refresh_hud())
	brain.finished.connect(ai_finished)
	build_hud()
	panels=GenesisPanels.new(self)
	notebook=GenesisNotebook.new(self)
	audio=AudioStreamPlayer.new();audio.stream=GenesisAudio.create();audio.volume_db=-19;add_child(audio)
	if state.data.sound:audio.play()
	get_tree().auto_accept_quit=false
	apply_settings();brain.start();refresh_hud()
	main_menu()
	if not state.last_error.is_empty():toast(state.last_error)
	if "--smoke-test" in OS.get_cmdline_user_args():smoke_test()
	if "--ai-smoke-test" in OS.get_cmdline_user_args():ai_smoke_test()

func build_hud():
	var layer=CanvasLayer.new();add_child(layer)
	ui=Control.new();ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.theme=GenesisUI.theme();layer.add_child(ui)
	var top=PanelContainer.new();top.position=Vector2(24,20);top.size=Vector2(1232,78);ui.add_child(top)
	hud_parts.append(top)
	var row=HBoxContainer.new();top.add_child(row)
	var brand=VBoxContainer.new();brand.custom_minimum_size.x=240;row.add_child(brand)
	brand.add_child(GenesisUI.label("evidence genesis",25));brand.add_child(GenesisUI.label("FIELDWORK / YOUR LITTLE WORLDS",10,GenesisUI.MUTED))
	var info=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(info)
	hud_name=GenesisUI.label("",18);hud_stats=GenesisUI.label("",12,GenesisUI.MUTED);info.add_child(hud_name);info.add_child(hud_stats)
	for index in 2:
		var crew_button=GenesisUI.button(state.data.crew[index].name,func():select_actor(index))
		crew_buttons.append(crew_button);row.add_child(crew_button)
	row.add_child(GenesisUI.button("Menu",main_menu))
	var quest=PanelContainer.new();quest.position=Vector2(24,115);quest.custom_minimum_size=Vector2(272,170);ui.add_child(quest)
	hud_parts.append(quest)
	var qbox=VBoxContainer.new();quest.add_child(qbox);hud_location=GenesisUI.label("WORKSHOP / YOUR NEXT STEP",10,GenesisUI.MUTED);qbox.add_child(hud_location)
	hud_quest=GenesisUI.label("",15);qbox.add_child(hud_quest)
	hud_ai=GenesisUI.label("",11,GenesisUI.PAPER);hud_ai.custom_minimum_size.x=260;hud_ai.position=Vector2(24,296);ui.add_child(hud_ai)
	message=GenesisUI.label("Click to walk · WASD / arrows · E to interact · Tab to switch",15,GenesisUI.PAPER)
	message.position=Vector2(280,586);message.size=Vector2(720,42);message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;ui.add_child(message)
	var dock=PanelContainer.new();dock.position=Vector2(60,640);dock.size=Vector2(1160,60);ui.add_child(dock)
	hud_parts.append(dock);hud_parts.append(message);hud_parts.append(hud_ai)
	var buttons=HBoxContainer.new();buttons.alignment=BoxContainer.ALIGNMENT_CENTER;dock.add_child(buttons)
	for item in [["Worlds",world_map],["Missions",missions_panel],["Teach",func():notebook.teach_panel()],["Memory",func():notebook.memory_panel()],["Create",func():notebook.task_panel()],["Talk",chat_panel],["Tasks",task_history],["Documents",documents_panel],["Workshop",garden_panel]]:
		buttons.add_child(GenesisUI.button(item[0],item[1],item[0]=="Create"))
	file_dialog=FileDialog.new();file_dialog.access=FileDialog.ACCESS_FILESYSTEM;file_dialog.use_native_dialog=true
	file_dialog.file_selected.connect(export_selected);ui.add_child(file_dialog)

func refresh_hud():
	if hud_name==null:return
	hud_name.text=state.actor().name+" · "+state.actor().role+" · Lv "+str(state.level(int(state.data.selected)))
	for i in 2:crew_buttons[i].text=state.data.crew[i].name
	hud_stats.text="Energy "+str(int(state.actor().energy))+"/100    Berries "+str(int(state.data.berries))+"    Skill stars "+str(int(state.data.stars))+"    Approved "+str(int(state.actor().approved))
	hud_ai.text=brain.status
	var next="Every mission complete! Build your workshop and keep creating."
	for mission in state.missions():
		if mission.id not in state.data.progress.claims:
			next=("Reward ready: " if mission.ready else "Next: ")+mission.title
			break
	if state.actor().lessons.is_empty():next="Start: move with arrows, visit the shelf or open Teach. Your first lesson is editable in Memory."
	elif state.data.documents.is_empty():next="Next: Create from your notes. Template mode is always offline."
	elif int(state.actor().approved)==0:next="Next: open Documents, review the draft, save corrections, then Approve."
	if state.data.exploration.zone!="workshop":
		next="Find the open field journal. Move nearby and press E to record its notes." if state.data.exploration.zone not in state.data.exploration.discoveries else "Make a field report, review it, then collect expedition rewards in Worlds."
	hud_location.text=String(state.data.exploration.zone).to_upper()+" / YOUR NEXT STEP"
	hud_quest.text=next+"\nOpen Missions to see your goals."

func panel(title: String) -> VBoxContainer:
	close_panel()
	world.paused=true
	overlay=PanelContainer.new();overlay.clip_contents=true;overlay.position=Vector2(822,112);overlay.size=Vector2(430,520);ui.add_child(overlay)
	panel_root=VBoxContainer.new();overlay.add_child(panel_root)
	var row=HBoxContainer.new();panel_root.add_child(row)
	var heading=GenesisUI.label(title,23);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(heading)
	row.add_child(GenesisUI.button("×",func():
		if menu_open:main_menu()
		else:close_panel()))
	fit_panel(overlay,Vector2(430,520))
	return GenesisUI.scroll_box(panel_root)

func close_panel():
	if is_instance_valid(overlay):overlay.queue_free();overlay=null
	if world!=null:world.paused=menu_open

func toast(text: String):
	message.text=text;toast_timer=7

func commit_change(change: Callable, success="") -> bool:
	var previous=state.data.duplicate(true)
	change.call()
	var saved=state.commit(previous)
	apply_settings();refresh_hud()
	if not saved:toast(state.last_error)
	elif not success.is_empty():toast(success)
	return saved

func select_actor(index: int):
	if not pending.is_empty():toast("Wait for the current task before changing companions.");return
	if commit_change(func():state.data.selected=index):close_panel()

func interaction(kind: String):
	if not pending.is_empty():toast("Your companion is working. You can review documents when it finishes.");return
	match kind:
		"waystone":world_map()
		"discovery":field_journal()
		"shelf","notebook":notebook.teach_panel()
		"desk":notebook.task_panel()
		"bed":
			var resting=int(state.data.selected)
			var resting_state=state
			if world.actions[resting]=="Resting":return
			world.actions[resting]="Resting";world.go(resting,Vector2(8.2,8.8))
			toast(state.actor().name+" is taking a rest…")
			await get_tree().create_timer(3).timeout
			if state!=resting_state:return
			var saved=state.rest(resting);world.actions[resting]="Idle";refresh_hud();toast("Rest restored 30 energy." if saved else state.last_error)
		"bush":toast(state.harvest());refresh_hud()
		"plant":garden_panel()
		"lamp":commit_change(func():state.data.night=not state.data.night,"Lighting changed.")

func _process(delta):
	autosave+=delta
	if autosave>20:
		autosave=0
		if state.save_enabled and not state.save():toast(state.last_error)
	if toast_timer>0:
		toast_timer-=delta
		if toast_timer<=0:message.text="Click to walk · WASD / arrows · E to interact · Tab to switch"
	if "--capture" in OS.get_cmdline_user_args():
		screenshot_frames+=1
		if screenshot_frames==90:
			menu_open=false
			for part in hud_parts:part.show()
			close_panel()
			if "--capture-mosswood" in OS.get_cmdline_user_args():state.data.exploration.zone="mosswood";world.setup(state)
			if "--capture-archive" in OS.get_cmdline_user_args():state.data.exploration.zone="archive";world.setup(state)
			if "--capture-memory" in OS.get_cmdline_user_args():notebook.memory_panel()
			if "--capture-document" in OS.get_cmdline_user_args() and not state.data.documents.is_empty():document_panel(state.data.documents[0])
			if "--capture-menu" in OS.get_cmdline_user_args():main_menu()
			if "--capture-panel" in OS.get_cmdline_user_args():missions_panel()
			if "--capture-upgrades" in OS.get_cmdline_user_args():
				state.data.garden=true;state.data.decor.lanterns=true;state.data.decor.reading_corner=true;state.data.night=true;world.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("GENESIS_CAPTURE_PATH"))
			get_tree().quit()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if menu_open:main_menu()
		elif is_instance_valid(overlay):close_panel()
		else:settings_panel()

func _notification(what):
	if what==NOTIFICATION_WM_CLOSE_REQUEST:shutdown()

func welcome_panel():
	var box=panel("Welcome to your first little world")
	box.add_child(GenesisUI.label("A companion. A lesson. A possibility.",25))
	box.add_child(GenesisUI.label("Choose Milo or Pip. Walk with WASD, arrow keys, or a click on the ground. Press E near furniture to interact.",16))
	box.add_child(GenesisUI.label("The bookshelf opens lessons. The desk creates documents. The bed restores energy. The berry bush replenishes your basket.",16))
	box.add_child(GenesisUI.label("Open Missions for goals and rewards. Workshop lets you add a flower garden, lanterns and a reading corner. The included local model starts automatically. You can use template mode while it loads. No paid AI service is required.",15))
	box.add_child(GenesisUI.button("Begin our adventure",func():if commit_change(func():state.data.seen_intro=true):close_panel(),true))

func ai_finished(content: String, error: String):
	if pending.is_empty():return
	var task=pending.duplicate(true);pending={};world.actions[int(task.actor)]="Idle"
	if not error.is_empty():
		toast(error)
		if task.kind=="document":
			state.task_status(task.get("id",""),"failed",error)
			notebook.task_panel();notebook.title_field.text=task.title;notebook.notes_field.text=task.notes
		else:chat_panel();chat_input.text=task.notes
		return
	if task.kind=="document":
		var doc=state.complete_task(task.get("id",""),content)
		if doc.is_empty():toast(state.last_error);return
		refresh_hud();document_panel(doc);toast("Document delivered. Review it before approving.")
	else:
		session_chat.append({"name":state.data.crew[int(task.actor)].name,"text":content});chat_panel();toast("Your companion replied.")

func smoke_test():
	menu_open=false
	begin_workshop(profiles.create("Smoke workshop"))
	close_panel()
	assert(state.teach("preference","format","numbered steps"))
	assert("1. Test" in state.template("Check","Test\nAgain"))
	var doc=state.deliver("Smoke check",state.template("Smoke check","One\nTwo"),"Template",0)
	var before=int(state.data.stars);state.approve(doc);state.approve(doc);assert(int(state.data.stars)==before+1)
	assert(state.valid(state.data))
	notebook.teach_panel();notebook.memory_panel();notebook.task_panel()
	notebook.title_field.text="Template task integration";notebook.notes_field.text="One\nTwo";notebook.mode.select(1);notebook.submit()
	assert(state.data.tasks[0].status=="completed" and state.data.tasks[0].document==state.data.documents[0].id)
	task_history();main_menu();new_workshop();begin_workshop(state);close_panel();missions_panel();documents_panel();document_panel(doc);settings_panel();chat_panel();garden_panel();close_panel()
	state.data.garden=true
	assert(state.travel("mosswood"));world.setup(state);world_map();field_journal()
	notebook.title_field.text="Field report: Mosswood";notebook.notes_field.text=state.field_notes("mosswood");notebook.mode.select(1);notebook.submit()
	assert(state.data.tasks[0].status=="completed")
	state.data.crew[0].approved=3;assert(state.travel("archive"));world.setup(state)
	assert(world.blocked(Vector2(13.5,6)))
	field_journal();world_map();assert(state.travel("workshop"));world.setup(state);close_panel()
	print("GENESIS_NATIVE_SMOKE_OK")
	audio.stop();audio.stream=null
	await get_tree().create_timer(.3).timeout
	get_tree().quit()

func documents_panel():panels.documents()
func document_panel(doc: Dictionary):panels.document(doc)
func settings_panel():panels.settings()
func chat_panel():panels.chat()
func garden_panel():panels.garden()
func missions_panel():panels.missions()
func choose_export(kind: String):panels.choose_export(kind)
func export_selected(path: String):panels.export_selected(path)

func _exit_tree():
	if audio!=null:audio.stop();audio.stream=null
	if panels!=null:panels.game=null
	if notebook!=null:notebook.game=null

func ai_smoke_test():
	begin_workshop(profiles.create("AI integration workshop"))
	close_panel()
	for i in range(100):
		if brain.available:break
		await get_tree().create_timer(1).timeout
	if not brain.available:
		push_error("AI_SMOKE_START_FAILED");get_tree().quit(1);return
	state.teach("preference","format","Use three numbered steps")
	var queued=state.queue_task("Garden routine","Water the plants. Gather berries. Feed Milo.",0,"Local AI")
	if queued.is_empty():get_tree().quit(1);return
	state.task_status(queued.id,"running")
	pending={"id":queued.id,"kind":"document","actor":0,"title":"Garden routine","notes":"Water the plants. Gather berries. Feed Milo."}
	brain.generate(state.actor(),pending.title,pending.notes)
	for i in range(180):
		if pending.is_empty():break
		await get_tree().create_timer(1).timeout
	if state.data.documents.is_empty() or state.data.documents[0].mode!="Local AI" or state.data.tasks[0].status!="completed":
		push_error("AI_SMOKE_GENERATION_FAILED");get_tree().quit(1);return
	print("GENESIS_AI_SMOKE_OK: "+state.data.documents[0].content.left(250))
	shutdown()

func begin_workshop(next_state: GenesisState):
	if next_state==null:toast(profiles.error);return
	state=next_state;menu_open=false;
	for part in hud_parts:part.show()
	world.setup(state);session_chat=[];close_panel();apply_settings();refresh_hud()
	if not state.data.seen_intro:welcome_panel()

func main_menu():
	if not pending.is_empty():toast("Finish or cancel the current task before changing workshops.");task_history();return
	menu_open=true
	for part in hud_parts:part.hide()
	var box=panel("Evidence Genesis · 0.5.0")
	overlay.position=Vector2(410,116);overlay.size=Vector2(460,500)
	fit_panel(overlay,Vector2(460,500))
	box.add_child(GenesisUI.label("A small workshop. Work you can trust.",21))
	var continue_button=GenesisUI.button("Continue workshop",func():begin_workshop(profiles.open_profile(profiles.selected)),true)
	continue_button.disabled=profiles.selected.is_empty() or not profiles.writable;box.add_child(continue_button)
	box.add_child(GenesisUI.button("New Workshop",new_workshop))
	for entry in profiles.entries:box.add_child(GenesisUI.button("Open · "+entry.name,func():begin_workshop(profiles.open_profile(entry.id))))
	if FileAccess.file_exists(GenesisState.SAVE):box.add_child(GenesisUI.button("Import legacy workshop (keep original)",func():begin_workshop(profiles.create("Legacy workshop",true))))
	box.add_child(GenesisUI.button("Settings",settings_panel))
	box.add_child(GenesisUI.button("Credits",func():
		var credits=panel("Credits & local AI")
		credits.add_child(GenesisUI.label("Evidence Genesis · original procedural art and ambient music. Godot Engine (MIT), llama.cpp (MIT), Qwen2.5 model (Apache 2.0). Packaged license notices are in licenses/. Editable memory is context, not model training. AI has no tools and never falls back to cloud services.",16))
		credits.add_child(GenesisUI.button("Main menu",main_menu))))
	box.add_child(GenesisUI.button("Exit",shutdown))
	if not profiles.error.is_empty():box.add_child(GenesisUI.label(profiles.error,14))

func new_workshop():
	var box=panel("New workshop · originals stay safe")
	var name=GenesisUI.input("Workshop name",40);box.add_child(name)
	box.add_child(GenesisUI.label("Each workshop keeps its own companions, lessons, documents, tasks and rewards. Existing saves are preserved.",15))
	box.add_child(GenesisUI.button("Create workshop",func():begin_workshop(profiles.create(name.text)),true))
	box.add_child(GenesisUI.button("Back",main_menu))

func task_history():
	var box=panel("Task history · real work")
	if not pending.is_empty() and pending.get("kind")=="document":box.add_child(GenesisUI.button("Cancel current task",func():
		brain.request.cancel_request();brain.busy=false;state.task_status(pending.get("id",""),"canceled","Canceled by you; notes retained.")
		world.actions[int(pending.actor)]="Idle";pending={};task_history()))
	if state.data.tasks.is_empty():box.add_child(GenesisUI.label("Create a document to start a task. Only approval earns progress."))
	for task in state.data.tasks:
		box.add_child(GenesisUI.label(task.title+" · "+String(task.status).to_upper(),18))
		box.add_child(GenesisUI.label(task.get("error","")+"\n"+task.notes,13,GenesisUI.MUTED))
		if task.status=="completed":
			for doc in state.data.documents:
				if doc.id==task.document:box.add_child(GenesisUI.button("Open delivery · "+("Approved" if doc.accepted else "Review needed"),func():document_panel(doc)))
		if task.status in ["failed","canceled"]:box.add_child(GenesisUI.button("Use notes for a new task",func():notebook.task_panel();notebook.title_field.text=task.title;notebook.notes_field.text=task.notes))

func apply_settings():
	GenesisUI.text_scale=float(state.data.settings.text_scale)
	if ui!=null:
		ui.theme=GenesisUI.theme();scale_labels(ui)
	audio.volume_db=linear_to_db(float(state.data.settings.volume)*0.22)
	if state.data.sound and not audio.playing:audio.play()
	if not state.data.sound:audio.stop()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if state.data.settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func shutdown():
	if state.save_enabled and not state.save():toast(state.last_error);return
	if audio!=null:audio.stop();audio.stream=null
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()

func fit_panel(target: Control, dimensions: Vector2):
	for i in 3:await get_tree().process_frame
	if is_instance_valid(target):target.size=dimensions

func scale_labels(node: Node):
	if node is Label and node.has_meta("base_font_size"):node.add_theme_font_size_override("font_size",int(node.get_meta("base_font_size")*GenesisUI.text_scale))
	for child in node.get_children():scale_labels(child)


func world_map():
	var box=panel("Your world map")
	box.add_child(GenesisUI.label("Grow the workshop, then take your companion into the field.",16))
	for destination in state.destinations():
		box.add_child(GenesisUI.label(destination.name+" · "+destination.description,16))
		var button=GenesisUI.button("Travel to "+destination.name,func():
			if not pending.is_empty() or "Resting" in world.actions:toast("Finish the current task or rest before traveling.");return
			if state.travel(destination.id):world.setup(state);close_panel();refresh_hud();toast("Arrived at "+destination.name+". Find the open field journal or return with Worlds.")
			else:toast(state.last_error))
		button.disabled=not destination.unlocked or not pending.is_empty();box.add_child(button)
	box.add_child(GenesisUI.label("Mosswood: plant your garden. Tidal Archive: approve three documents.",13,GenesisUI.MUTED))
	for mission in state.expedition_missions():
		var collected=mission.id in state.data.exploration.claims
		var reward=GenesisUI.button(mission.title+(" · Collected" if collected else " · "+str(mission.berries)+" berries"),func():
			if state.claim_expedition(mission.id):toast("Expedition reward collected.");refresh_hud();world_map()
			else:toast(state.last_error))
		reward.disabled=collected or not mission.ready;box.add_child(reward)

func field_journal():
	var box=panel("A notebook from the field")
	var zone=String(state.data.exploration.zone)
	box.add_child(GenesisUI.label(state.field_notes(zone),17))
	box.add_child(GenesisUI.button("Record and make a field report",func():
		if not state.discover():toast(state.last_error);return
		notebook.task_panel();notebook.title_field.text="Field report: "+zone.capitalize();notebook.notes_field.text=state.field_notes(zone),true))
	box.add_child(GenesisUI.label("These are editable source notes. Choose local AI or explicit template mode, then review the result yourself.",13,GenesisUI.MUTED))
