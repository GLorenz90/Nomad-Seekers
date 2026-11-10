class_name JoinPicker
extends CanvasLayer
## Co-op join (Part 12): shown in a new split-screen pane when Start is pressed
## on a controller nobody plays with. Lists the four character slots; ones
## already playing or empty can't be picked. A picks, B cancels.

signal picked(slot: int)
signal cancelled

var _box: VBoxContainer
var _message: Label


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(in_use: Array[int]) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 440.0
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	var title := Label.new()
	title.text = "Join the party: choose a character"
	title.add_theme_font_size_override("font_size", 24)
	_box.add_child(title)
	var first: Button = null
	for i in Session.SLOT_COUNT:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 20)
		var data := Session.load_slot(i)
		if data == null:
			b.text = "%d. (empty: create characters from the title screen)" % (i + 1)
			b.disabled = true
		else:
			var c := data.character
			b.text = "%d. %s  Lv %d %s %s" % [i + 1, c.seeker_name, c.level(), c.race_name(), c.job_name()]
			if i in in_use:
				b.text += "  (playing)"
				b.disabled = true
		b.pressed.connect(func(): picked.emit(i))
		_box.add_child(b)
		if first == null and not b.disabled:
			first = b
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.pressed.connect(func(): cancelled.emit())
	_box.add_child(cancel)
	_message = Label.new()
	_box.add_child(_message)
	(first if first else cancel).grab_focus.call_deferred()


func show_message(text: String) -> void:
	_message.text = text


## The slot buttons' texts (for tests).
func entries() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _box.get_children():
		if child is Button:
			out.append((child as Button).text)
	return out


func _input(event: InputEvent) -> void:
	if _box:
		MenuFocus.recover(_box, event, func():
			for child in _box.get_children():
				if child is Button and not (child as Button).disabled:
					(child as Button).grab_focus()
					return)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
