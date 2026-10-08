class_name GenesisUI
extends RefCounted

const INK=Color("233e36")
const PAPER=Color("f4f0df")
const MUTED=Color("617566")
const GOLD=Color("e9ca84")

static func style(color: Color, radius=8, padding=14) -> StyleBoxFlat:
	var box=StyleBoxFlat.new();box.bg_color=color
	box.set_corner_radius_all(radius);box.set_content_margin_all(padding)
	box.border_color=Color("72826a");box.set_border_width_all(1)
	return box

static func theme() -> Theme:
	var t=Theme.new();t.default_font_size=16
	t.set_color("font_color","Label",INK)
	t.set_color("font_color","Button",INK)
	t.set_color("font_hover_color","Button",INK)
	t.set_stylebox("normal","Button",style(Color("e3e8d0")))
	t.set_stylebox("hover","Button",style(Color("d5e4b9")))
	t.set_stylebox("pressed","Button",style(Color("bfce9b")))
	t.set_stylebox("disabled","Button",style(Color("b2b8a6")))
	var focus=style(Color.TRANSPARENT);focus.border_color=GOLD;focus.set_border_width_all(3)
	t.set_stylebox("focus","Button",focus)
	for type in ["LineEdit","TextEdit"]:
		t.set_stylebox("normal",type,style(Color("fff9e9"),6,10));t.set_stylebox("focus",type,focus)
		t.set_color("font_color",type,INK);t.set_color("caret_color",type,INK)
		t.set_color("font_placeholder_color",type,MUTED)
	t.set_stylebox("panel","PanelContainer",style(PAPER))
	t.set_stylebox("panel","PopupMenu",style(PAPER))
	t.set_color("font_color","PopupMenu",INK)
	t.set_stylebox("normal","OptionButton",style(Color("e3e8d0")))
	t.set_stylebox("hover","OptionButton",style(Color("d5e4b9")))
	t.set_color("font_color","OptionButton",INK)
	t.set_constant("separation","VBoxContainer",10)
	t.set_constant("separation","HBoxContainer",10)
	return t

static func label(text: String, size=16, color=INK) -> Label:
	var l=Label.new();l.text=text;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, callback: Callable, primary=false) -> Button:
	var b=Button.new();b.text=text;b.custom_minimum_size.y=44;b.pressed.connect(callback)
	if primary:
		b.add_theme_stylebox_override("normal",style(INK));b.add_theme_stylebox_override("hover",style(Color("375d4a")))
		b.add_theme_color_override("font_color",PAPER);b.add_theme_color_override("font_hover_color",PAPER)
	return b

static func input(placeholder: String, max_length=120) -> LineEdit:
	var field=LineEdit.new();field.placeholder_text=placeholder;field.max_length=max_length;field.custom_minimum_size.y=44;return field

static func area(placeholder: String, height=150) -> TextEdit:
	var field=TextEdit.new();field.placeholder_text=placeholder;field.custom_minimum_size.y=height;field.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;return field

static func field(parent: Node, title: String, control: Control):
	parent.add_child(label(title,13,MUTED));parent.add_child(control)

static func scroll_box(parent: Control) -> VBoxContainer:
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(box);return box
