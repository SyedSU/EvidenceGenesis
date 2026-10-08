extends Node2D

var state=GenesisState.new()
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
	state.load_save()
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
	brain.start();refresh_hud()
	if not state.data.seen_intro:welcome_panel()
	if not state.last_error.is_empty():toast(state.last_error)
	if "--smoke-test" in OS.get_cmdline_user_args():smoke_test()
	if "--ai-smoke-test" in OS.get_cmdline_user_args():ai_smoke_test()

func build_hud():
	var layer=CanvasLayer.new();add_child(layer)
	ui=Control.new();ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.theme=GenesisUI.theme();layer.add_child(ui)
	var top=PanelContainer.new();top.position=Vector2(24,20);top.size=Vector2(1232,78);ui.add_child(top)
	var row=HBoxContainer.new();top.add_child(row)
	var brand=VBoxContainer.new();brand.custom_minimum_size.x=240;row.add_child(brand)
	brand.add_child(GenesisUI.label("evidence genesis",25));brand.add_child(GenesisUI.label("THE FIRST LITTLE WORLD",10,GenesisUI.MUTED))
	var info=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(info)
	hud_name=GenesisUI.label("",18);hud_stats=GenesisUI.label("",12,GenesisUI.MUTED);info.add_child(hud_name);info.add_child(hud_stats)
	for index in 2:
		var crew_button=GenesisUI.button(state.data.crew[index].name,func():select_actor(index))
		crew_buttons.append(crew_button);row.add_child(crew_button)
	row.add_child(GenesisUI.button("Settings",settings_panel))
	var quest=PanelContainer.new();quest.position=Vector2(24,115);quest.custom_minimum_size=Vector2(272,110);ui.add_child(quest)
	var qbox=VBoxContainer.new();quest.add_child(qbox);qbox.add_child(GenesisUI.label("CHAPTER ONE / A FIRST SPARK",10,GenesisUI.MUTED))
	hud_quest=GenesisUI.label("",15);qbox.add_child(hud_quest)
	hud_ai=GenesisUI.label("",11,GenesisUI.PAPER);hud_ai.custom_minimum_size.x=260;hud_ai.position=Vector2(24,238);ui.add_child(hud_ai)
	message=GenesisUI.label("Click to walk · WASD / arrows · E to interact · Tab to switch",15,GenesisUI.PAPER)
	message.position=Vector2(280,586);message.size=Vector2(720,42);message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;ui.add_child(message)
	var dock=PanelContainer.new();dock.position=Vector2(140,640);dock.size=Vector2(1000,60);ui.add_child(dock)
	var buttons=HBoxContainer.new();buttons.alignment=BoxContainer.ALIGNMENT_CENTER;dock.add_child(buttons)
	for item in [["Missions",missions_panel],["Teach",func():notebook.teach_panel()],["Memory",func():notebook.memory_panel()],["Create",func():notebook.task_panel()],["Talk",chat_panel],["Documents",documents_panel],["Workshop",garden_panel]]:
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
	hud_quest.text=next+"\nOpen Missions to see your goals."

func panel(title: String) -> VBoxContainer:
	close_panel()
	world.paused=true
	overlay=PanelContainer.new();overlay.position=Vector2(822,112);overlay.size=Vector2(430,520);ui.add_child(overlay)
	panel_root=VBoxContainer.new();overlay.add_child(panel_root)
	var row=HBoxContainer.new();panel_root.add_child(row)
	var heading=GenesisUI.label(title,23);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(heading)
	row.add_child(GenesisUI.button("×",close_panel))
	return GenesisUI.scroll_box(panel_root)

func close_panel():
	if is_instance_valid(overlay):overlay.queue_free();overlay=null
	if world!=null:world.paused=false

func toast(text: String):
	message.text=text;toast_timer=7

func select_actor(index: int):
	if not pending.is_empty():toast("Wait for the current task before changing companions.");return
	state.data.selected=index;close_panel();refresh_hud();state.save()

func interaction(kind: String):
	if not pending.is_empty():toast("Your companion is working. You can review documents when it finishes.");return
	match kind:
		"shelf","notebook":notebook.teach_panel()
		"desk":notebook.task_panel()
		"bed":
			var resting=int(state.data.selected)
			if world.actions[resting]=="Resting":return
			world.actions[resting]="Resting";world.go(resting,Vector2(8.2,8.8))
			toast(state.actor().name+" is taking a rest…")
			await get_tree().create_timer(3).timeout
			state.rest(resting);world.actions[resting]="Idle";refresh_hud();toast("Rest restored 30 energy.")
		"bush":toast(state.harvest());refresh_hud()
		"plant":garden_panel()
		"lamp":state.data.night=not state.data.night;state.save();toast("Evening light." if state.data.night else "Morning light.")

func _process(delta):
	autosave+=delta
	if autosave>20:autosave=0;state.save()
	if toast_timer>0:
		toast_timer-=delta
		if toast_timer<=0:message.text="Click to walk · WASD / arrows · E to interact · Tab to switch"
	if "--capture" in OS.get_cmdline_user_args():
		screenshot_frames+=1
		if screenshot_frames==90:
			close_panel()
			if "--capture-panel" in OS.get_cmdline_user_args():missions_panel()
			if "--capture-upgrades" in OS.get_cmdline_user_args():
				state.data.garden=true;state.data.decor.lanterns=true;state.data.decor.reading_corner=true;state.data.night=true;world.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("GENESIS_CAPTURE_PATH"))
			get_tree().quit()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if is_instance_valid(overlay):close_panel()
		else:settings_panel()

func _notification(what):
	if what==NOTIFICATION_WM_CLOSE_REQUEST:state.save();get_tree().quit()

func welcome_panel():
	var box=panel("Welcome to your first little world")
	box.add_child(GenesisUI.label("A companion. A lesson. A possibility.",25))
	box.add_child(GenesisUI.label("Choose Milo or Pip. Walk with WASD, arrow keys, or a click on the ground. Press E near furniture to interact.",16))
	box.add_child(GenesisUI.label("The bookshelf opens lessons. The desk creates documents. The bed restores energy. The berry bush replenishes your basket.",16))
	box.add_child(GenesisUI.label("Open Missions for goals and rewards. Workshop lets you add a flower garden, lanterns and a reading corner. The included local model starts automatically. You can use template mode while it loads. No paid AI service is required.",15))
	box.add_child(GenesisUI.button("Begin our adventure",func():state.data.seen_intro=true;state.save();close_panel(),true))

func ai_finished(content: String, error: String):
	if pending.is_empty():return
	var task=pending.duplicate(true);pending={};world.actions[int(task.actor)]="Idle"
	if not error.is_empty():
		toast(error)
		if task.kind=="document":
			notebook.task_panel();notebook.title_field.text=task.title;notebook.notes_field.text=task.notes
		else:chat_panel();chat_input.text=task.notes
		return
	if task.kind=="document":
		var doc=state.deliver(task.title,content,"Local AI",int(task.actor));refresh_hud();document_panel(doc);toast("Document delivered. Review it before approving.")
	else:
		session_chat.append({"name":state.data.crew[int(task.actor)].name,"text":content});chat_panel();toast("Your companion replied.")

func smoke_test():
	close_panel()
	assert(state.teach("preference","format","numbered steps"))
	assert("1. Test" in state.template("Check","Test\nAgain"))
	var doc=state.deliver("Smoke check",state.template("Smoke check","One\nTwo"),"Template",0)
	var before=int(state.data.stars);state.approve(doc);state.approve(doc);assert(int(state.data.stars)==before+1)
	assert(state.valid(state.data))
	notebook.teach_panel();notebook.memory_panel();notebook.task_panel();missions_panel();documents_panel();document_panel(doc);settings_panel();chat_panel();garden_panel();close_panel()
	print("GENESIS_NATIVE_SMOKE_OK")
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
	close_panel()
	for i in range(100):
		if brain.available:break
		await get_tree().create_timer(1).timeout
	if not brain.available:
		push_error("AI_SMOKE_START_FAILED");get_tree().quit(1);return
	state.teach("preference","format","Use three numbered steps")
	pending={"kind":"document","actor":0,"title":"Garden routine","notes":"Water the plants. Gather berries. Feed Milo."}
	brain.generate(state.actor(),pending.title,pending.notes)
	for i in range(180):
		if pending.is_empty():break
		await get_tree().create_timer(1).timeout
	if state.data.documents.is_empty() or state.data.documents[0].mode!="Local AI":
		push_error("AI_SMOKE_GENERATION_FAILED");get_tree().quit(1);return
	print("GENESIS_AI_SMOKE_OK: "+state.data.documents[0].content.left(250))
	get_tree().quit()
