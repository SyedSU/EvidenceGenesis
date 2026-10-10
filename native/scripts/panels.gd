class_name GenesisPanels
extends RefCounted
var game: Node

func _init(owner_game: Node):game=owner_game

func documents():
	var box=game.panel("Things you made together")
	box.add_child(GenesisUI.button("+ Create a document",game.notebook.task_panel))
	if game.state.data.documents.is_empty():box.add_child(GenesisUI.label("Your first creation will appear here."));return
	for doc in game.state.data.documents:
		box.add_child(GenesisUI.button(doc.title+"\n"+doc.mode+" · "+("Approved" if doc.accepted else "Review needed"),func():document(doc)))

func document(doc: Dictionary):
	game.current_document=doc
	var box=game.panel(doc.title)
	box.add_child(GenesisUI.label(doc.mode+" · "+("Approved" if doc.accepted else "Review before approving"),12,GenesisUI.MUTED))
	game.document_editor=GenesisUI.area("",250);game.document_editor.text=doc.content;box.add_child(game.document_editor)
	box.add_child(GenesisUI.button("Save edits",func():if save_edits():game.toast("Edits saved.")))
	box.add_child(GenesisUI.button("Approve & award skill star",func():
		if save_edits():
			var approved=game.state.approve(doc);game.refresh_hud();document(doc)
			game.toast("Approved. Each document earns one skill star." if approved else game.state.last_error),true))
	box.add_child(GenesisUI.button("Export Markdown",func():if save_edits():game.choose_export("document-md")))
	box.add_child(GenesisUI.button("Export printable HTML",func():if save_edits():game.choose_export("document-html")))
	box.add_child(GenesisUI.label("Open exported HTML in your browser and use Print → Save as PDF. This build does not silently install a PDF printer.",12,GenesisUI.MUTED))

func save_edits() -> bool:
	var text=game.document_editor.text
	if text.strip_edges().is_empty() or text.length()>20000:game.toast("Document must contain between 1 and 20,000 characters.");return false
	var previous=game.current_document.duplicate(true)
	if text!=game.current_document.content:game.current_document.content=text;game.current_document.accepted=false
	if not game.state.save():
		game.current_document.clear();game.current_document.merge(previous,true);game.toast(game.state.last_error);return false
	return true

func settings():
	var box=game.panel("Make this world yours")
	box.add_child(GenesisUI.label("Document maker turns notes into drafts; Reviewer identifies gaps. Energy is spent only on delivered work. Every three approvals earns a level; levels describe practice, not model training.",14))
	var volume=HSlider.new();volume.min_value=0;volume.max_value=1;volume.step=0.05;volume.value=game.state.data.settings.volume
	GenesisUI.field(box,"Music volume",volume)
	volume.value_changed.connect(func(value):game.state.data.settings.volume=value;game.apply_settings();game.state.save())
	var text=OptionButton.new();text.add_item("Standard text");text.add_item("Large text");text.select(1 if game.state.data.settings.text_scale>1 else 0);box.add_child(text)
	text.item_selected.connect(func(index):game.state.data.settings.text_scale=1.15 if index==1 else 1.0;game.apply_settings();game.state.save();settings())
	box.add_child(GenesisUI.button("Reduce ambient motion / restore",func():game.state.data.settings.motion=not game.state.data.settings.motion;game.state.save()))
	box.add_child(GenesisUI.label("Controls: WASD/arrows or click to move · E interact · Tab switch · Escape close panel. Keyboard movement and click are both available; remapping is not implemented.",13))
	var name=GenesisUI.input("Companion name",24);name.text=game.state.actor().name
	var role=OptionButton.new();role.add_item("Document maker");role.add_item("Reviewer");role.custom_minimum_size.y=44
	role.select(0 if game.state.actor().role=="Document maker" else 1)
	GenesisUI.field(box,"Selected companion",name);GenesisUI.field(box,"Role",role)
	box.add_child(GenesisUI.button("Save companion",func():
		if name.text.strip_edges().is_empty():game.toast("Give your companion a name.");return
		game.state.actor().name=name.text.strip_edges();game.state.actor().role=role.get_item_text(role.selected);game.state.save();game.refresh_hud();game.toast("Companion updated.")))
	box.add_child(GenesisUI.button("Feed a berry",func():game.toast(game.state.feed());game.refresh_hud()))
	box.add_child(GenesisUI.button("Switch morning / evening",func():game.state.data.night=not game.state.data.night;game.state.save();game.toast("Lighting changed.")))
	box.add_child(GenesisUI.button("Music on / off",func():
		game.state.data.sound=not game.state.data.sound
		if game.state.data.sound:game.audio.play()
		else:game.audio.stop()
		game.state.save()))
	box.add_child(GenesisUI.button("Fullscreen / window",func():game.state.data.settings.fullscreen=not game.state.data.settings.fullscreen;game.apply_settings();game.state.save()))
	box.add_child(GenesisUI.label(game.brain.status,13,GenesisUI.MUTED))
	if game.brain.needs_runtime:
		box.add_child(GenesisUI.label("Install the official Microsoft x64 runtime once, then restart this game. The setup download needs internet. Your companions and template mode work while AI is unavailable.",14))
		box.add_child(GenesisUI.button("Download Microsoft AI support",func():OS.shell_open(GenesisBrain.SUPPORT_URL),true))
	box.add_child(GenesisUI.button("Download save backup",func():game.choose_export("backup")))
	box.add_child(GenesisUI.button("Restore a backup",func():game.choose_export("restore")))
	box.add_child(GenesisUI.button("Open save folder",func():OS.shell_open(ProjectSettings.globalize_path("user://"))))
	box.add_child(GenesisUI.button("Return",game.main_menu if game.menu_open else game.close_panel,true))

func chat():
	var box=game.panel("A conversation with "+game.state.actor().name)
	box.add_child(GenesisUI.label("Local AI · saved lessons included · responses need your judgment",12,GenesisUI.MUTED))
	var transcript=""
	for entry in game.session_chat.slice(maxi(0,game.session_chat.size()-8)):transcript+=entry.name+": "+entry.text+"\n\n"
	game.chat_log=GenesisUI.label(transcript if not transcript.is_empty() else "Ask something. Tell me about our next adventure.",15)
	box.add_child(game.chat_log)
	game.chat_input=GenesisUI.input("Your message…",1000);box.add_child(game.chat_input)
	game.chat_button=GenesisUI.button("Talk to "+game.state.actor().name,send_chat,true);box.add_child(game.chat_button)
	game.chat_button.disabled=not game.pending.is_empty()
	game.chat_input.text_submitted.connect(func(_text):send_chat())
	box.add_child(GenesisUI.label("Conversation history is shown for this session. Only explicitly taught lessons become persistent companion memory.",12,GenesisUI.MUTED))

func send_chat():
	if not game.pending.is_empty():game.toast("Please wait for the current reply.");return
	var text=game.chat_input.text.strip_edges()
	if text.is_empty():return
	if not game.brain.available:game.toast(game.brain.status);return
	game.pending={"kind":"chat","actor":int(game.state.data.selected),"notes":text}
	game.session_chat.append({"name":"You","text":text})
	game.chat_button.disabled=true;game.world.actions[int(game.state.data.selected)]="Working"
	game.brain.generate(game.state.actor().duplicate(true),"Conversation",text,true)
	game.toast("Your companion is thinking…")

func missions():
	var box=game.panel("The workshop mission board")
	box.add_child(GenesisUI.label("Small lessons. Useful work. A world that grows with you.",15))
	var complete=game.state.data.progress.claims.size()
	box.add_child(GenesisUI.label(str(complete)+" / 6 rewards collected",13,GenesisUI.MUTED))
	for mission in game.state.missions():
		var card=PanelContainer.new();var body=VBoxContainer.new();card.add_child(body);box.add_child(card)
		body.add_child(GenesisUI.label(mission.title,19))
		body.add_child(GenesisUI.label(mission.description,14))
		var reward=str(mission.stars)+" skill stars" if mission.stars>0 else str(mission.berries)+" berries"
		var claimed=mission.id in game.state.data.progress.claims
		var button=GenesisUI.button("Collected" if claimed else "Collect · "+reward,func():
			game.toast(game.state.claim_mission(mission.id));game.refresh_hud();missions(),mission.ready and not claimed)
		button.disabled=claimed or not mission.ready;body.add_child(button)
	box.add_child(GenesisUI.button("Open Workshop upgrades",game.garden_panel))

func garden():
	var box=game.panel("Build your little workshop")
	box.add_child(GenesisUI.label("Spend earned skill stars on permanent additions. Your upgrades stay with your save.",16))
	for item in [["garden","Flower garden",2],["lanterns","Evening lanterns",3],["reading_corner","Outdoor reading corner",4]]:
		var owned=bool(game.state.data.garden) if item[0]=="garden" else bool(game.state.data.decor[item[0]])
		var button=GenesisUI.button(item[1]+(" · Built" if owned else " · "+str(item[2])+" stars"),func():
			game.toast(game.state.buy_upgrade(item[0]));game.refresh_hud();game.world.queue_redraw();garden(),not owned)
		button.disabled=owned;box.add_child(button)
	box.add_child(GenesisUI.button("Gather berries",func():game.toast(game.state.harvest());game.refresh_hud()))
	box.add_child(GenesisUI.button("Feed your companion",func():game.toast(game.state.feed());game.refresh_hud()))
	box.add_child(GenesisUI.button("Open mission board",missions))
	box.add_child(GenesisUI.button("Read the workshop journal",func():
		var journal=game.panel("Life in the workshop")
		for entry in game.state.data.journal:journal.add_child(GenesisUI.label(entry.text,15))))

func choose_export(kind: String):
	if not game.pending.is_empty() and kind=="restore":game.toast("Wait for the current task before restoring.");return
	game.export_kind=kind
	var dialog=game.file_dialog
	if kind=="restore":
		dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.filters=PackedStringArray(["*.json ; Workshop save"]);dialog.popup_centered_ratio(.7);return
	dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE
	match kind:
		"backup":game.file_content=JSON.stringify(game.state.data,"\t");dialog.current_file="Genesis-workshop-backup.json";dialog.filters=PackedStringArray(["*.json ; Workshop save"])
		"document-md":game.file_content=game.current_document.content;dialog.current_file="Genesis-document.md";dialog.filters=PackedStringArray(["*.md ; Markdown document"])
		"document-html":game.file_content=GenesisDocuments.html(game.current_document);dialog.current_file="Genesis-document.html";dialog.filters=PackedStringArray(["*.html ; Printable document"])
	dialog.popup_centered_ratio(.7)

func export_selected(path: String):
	if game.export_kind=="restore":
		var input=FileAccess.open(path,FileAccess.READ)
		if input==null or input.get_length()>1500000:game.toast("Backup unreadable or too large.");return
		var parsed=JSON.parse_string(input.get_as_text());input.close()
		if not game.state.valid(parsed):game.toast("Invalid backup. Your current workshop is unchanged.");return
		game.state.adopt(parsed);game.state.save_enabled=true;game.state.save();game.world.setup(game.state);game.refresh_hud();game.close_panel();game.toast("Workshop restored.");return
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:game.toast("Could not write to that folder. Choose another location.");return
	file.store_string(game.file_content);file.close();game.toast("Saved: "+path.get_file())
