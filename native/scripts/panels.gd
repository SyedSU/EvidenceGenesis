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
		if save_edits():game.state.approve(doc);game.refresh_hud();document(doc);game.toast("Approved. Each document earns one skill star."),true))
	box.add_child(GenesisUI.button("Export Markdown",func():if save_edits():game.choose_export("document-md")))
	box.add_child(GenesisUI.button("Export printable HTML",func():if save_edits():game.choose_export("document-html")))
	box.add_child(GenesisUI.label("Open exported HTML in your browser and use Print → Save as PDF. This build does not silently install a PDF printer.",12,GenesisUI.MUTED))

func save_edits() -> bool:
	var text=game.document_editor.text
	if text.strip_edges().is_empty() or text.length()>20000:game.toast("Document must contain between 1 and 20,000 characters.");return false
	if text!=game.current_document.content:game.current_document.content=text;game.current_document.accepted=false
	game.state.save();return true

func settings():
	var box=game.panel("Make this world yours")
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
	box.add_child(GenesisUI.button("Fullscreen / window",func():DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)))
	box.add_child(GenesisUI.label(game.brain.status,13,GenesisUI.MUTED))
	box.add_child(GenesisUI.button("Download save backup",func():game.choose_export("backup")))
	box.add_child(GenesisUI.button("Restore a backup",func():game.choose_export("restore")))
	box.add_child(GenesisUI.button("Open save folder",func():OS.shell_open(ProjectSettings.globalize_path("user://"))))
	box.add_child(GenesisUI.button("Return to the workshop",game.close_panel,true))

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

func garden():
	var box=game.panel("A little room to grow")
	box.add_child(GenesisUI.label("Earn skill stars by reviewing documents. Spend two stars to add a flower garden to the meadow.",16))
	box.add_child(GenesisUI.button("Plant a flower garden · 2 stars",func():
		if game.state.data.garden:game.toast("Your garden is already growing.");return
		if int(game.state.data.stars)<2:game.toast("Create and approve two documents first.");return
		game.state.data.stars-=2;game.state.data.garden=true;game.state.save();game.refresh_hud();game.toast("Your first flower garden is growing!"),true))
	box.add_child(GenesisUI.button("Gather berries",func():game.toast(game.state.harvest());game.refresh_hud()))
	box.add_child(GenesisUI.button("Feed your companion",func():game.toast(game.state.feed());game.refresh_hud()))
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
		game.state.data=parsed;game.state.save_enabled=true;game.state.save();game.world.setup(game.state);game.refresh_hud();game.close_panel();game.toast("Workshop restored.");return
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:game.toast("Could not write to that folder. Choose another location.");return
	file.store_string(game.file_content);file.close();game.toast("Saved: "+path.get_file())
