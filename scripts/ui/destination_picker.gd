class_name DestinationPicker
extends CanvasLayer
## The teleporter's destination list (Part 8, PSU-style): pauses the game and
## lists where the pad can go. A picks, B cancels (step off and back on to
## open it again).

var _box: VBoxContainer
var _done: Callable


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("modal_menus")


func open(names: PackedStringArray, on_done: Callable) -> void:
	_done = on_done
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 420.0
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)
	var title := Label.new()
	title.text = "Teleport to..."
	title.add_theme_font_size_override("font_size", 26)
	_box.add_child(title)
	for i in names.size():
		_add_button(names[i], i)
	_add_button("Stay here", -1)
	(_box.get_child(1) as Button).grab_focus.call_deferred()


func _add_button(text: String, index: int) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(_finish.bind(index))
	_box.add_child(b)


func _input(event: InputEvent) -> void:
	if _box:
		MenuFocus.recover(_box, event, func(): (_box.get_child(1) as Button).grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish(-1)


## Index of the destination chosen, or -1 to stay.
func _finish(index: int) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for p in get_tree().get_nodes_in_group("player"):
		(p as Player).hold_input()
	var done := _done
	queue_free()
	if done.is_valid():
		done.call(index)


func button_names() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _box.get_children():
		if child is Button:
			out.append((child as Button).text)
	return out
