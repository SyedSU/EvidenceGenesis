class_name GenesisNotebook
extends RefCounted

var game: Node
var title_field: LineEdit
var notes_field: TextEdit
var mode: OptionButton
var run_button: Button

func _init(owner_game: Node):game=owner_game

func teach_panel(kind="preference", key="", value=""):
	var box=game.panel("Teach a little. Grow together.")
	box.add_child(GenesisUI.label(game.state.actor().name+" remembers lessons you can inspect and correct.",15))
	var type=OptionButton.new();type.custom_minimum_size.y=44
	for item in ["Preference","Word or phrase","Instruction"]:type.add_item(item)
	type.select(["preference","vocabulary","instruction"].find(kind))
	var name=GenesisUI.input("e.g. format",80);name.text=key
	var lesson=GenesisUI.area("e.g. numbered steps",130);lesson.text=value
	GenesisUI.field(box,"Lesson type",type);GenesisUI.field(box,"Lesson name",name);GenesisUI.field(box,"What should I remember?",lesson)
	box.add_child(GenesisUI.button("Save this lesson",func():
		if game.state.teach(["preference","vocabulary","instruction"][type.selected],name.text,lesson.text):
			game.toast(game.state.actor().name+" remembers “"+name.text+"”.");game.refresh_hud();memory_panel()
		else:game.toast(game.state.last_error),true))
	box.add_child(GenesisUI.button("Use a first lesson",func():type.select(0);name.text="format";lesson.text="numbered steps"))
	box.add_child(GenesisUI.button("Open memory journal",memory_panel))
	box.add_child(GenesisUI.label("Lessons are saved context, not neural-network training. Local AI uses the most recent lessons that fit its context window. Template mode supports format, sign-off and vocabulary.",12,GenesisUI.MUTED))

func memory_panel():
	var box=game.panel(game.state.actor().name+"’s memory journal")
	box.add_child(GenesisUI.button("+ Teach a new lesson",teach_panel))
	if game.state.actor().lessons.is_empty():box.add_child(GenesisUI.label("An unwritten notebook. Your first lesson belongs here."));return
	for lesson in game.state.actor().lessons:
		var card=PanelContainer.new();var body=VBoxContainer.new();card.add_child(body);box.add_child(card)
		body.add_child(GenesisUI.label(String(lesson.kind).to_upper()+" · TAUGHT BY YOU",11,GenesisUI.MUTED))
		body.add_child(GenesisUI.label(lesson.key,19));body.add_child(GenesisUI.label(lesson.value,15))
		var row=HBoxContainer.new();body.add_child(row)
		row.add_child(GenesisUI.button("Edit",func():teach_panel(lesson.kind,lesson.key,lesson.value)))
		row.add_child(GenesisUI.button("Forget",func():
			if not game.state.forget(lesson.id):game.toast(game.state.last_error)
			game.refresh_hud();memory_panel()))

func task_panel():
	var box=game.panel("Make something real")
	box.add_child(GenesisUI.label("Your companion will bring a document back to the workshop. Review it before awarding a skill star.",15))
	title_field=GenesisUI.input("Our next adventure",120)
	notes_field=GenesisUI.area("Write your source notes here. One idea per line.",170)
	GenesisUI.field(box,"Document title",title_field);GenesisUI.field(box,"Source notes (up to 4,000 characters)",notes_field)
	mode=OptionButton.new();mode.custom_minimum_size.y=44;mode.add_item("Local AI · bundled model");mode.add_item("Offline template · no AI")
	GenesisUI.field(box,"Creation mode",mode)
	run_button=GenesisUI.button("Give this task to "+game.state.actor().name,submit,true);box.add_child(run_button)
	box.add_child(GenesisUI.button("Use example notes",func():title_field.text="My first companion adventure";notes_field.text="Choose a companion\nTeach a useful preference\nCreate and review a document"))
	box.add_child(GenesisUI.button("Open delivered documents",game.documents_panel))
	if game.pending.size()>0:run_button.disabled=true

func submit():
	if not game.pending.is_empty():game.toast("A task is already running.");return
	var title=title_field.text.strip_edges();var notes=notes_field.text.strip_edges()
	if title.is_empty() or notes.is_empty() or notes.length()>4000:game.toast("Add a title and source notes up to 4,000 characters.");return
	if int(game.state.actor().energy)<8:game.toast("Your companion needs a berry or a rest first.");return
	if mode.selected==1:
		var task=game.state.queue_task(title,notes,int(game.state.data.selected),"Template")
		if task.is_empty():game.toast(game.state.last_error);return
		if not game.state.task_status(task.id,"running"):game.toast(game.state.last_error);return
		var content=game.state.template(title,notes)
		var doc=game.state.complete_task(task.id,content)
		if doc.is_empty():game.toast(game.state.last_error);return
		game.refresh_hud();game.document_panel(doc);return
	if not game.brain.available:game.toast(game.brain.status);return
	run_button.disabled=true
	var task=game.state.queue_task(title,notes,int(game.state.data.selected),"Local AI")
	if task.is_empty():game.toast(game.state.last_error);return
	if not game.state.task_status(task.id,"running"):game.toast(game.state.last_error);return
	game.pending={"id":task.id,"kind":"document","title":title,"notes":notes,"actor":int(game.state.data.selected)}
	game.world.actions[int(game.state.data.selected)]="Working"
	game.world.go(int(game.state.data.selected),Vector2(7.5,5.8) if game.state.data.exploration.zone=="workshop" else Vector2(5.5,6.5));game.world.paused=false
	game.toast(game.state.actor().name+" is working on your document…")
	game.brain.generate(game.state.actor().duplicate(true),title,notes)
