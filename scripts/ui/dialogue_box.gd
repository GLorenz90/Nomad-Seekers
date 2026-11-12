class_name DialogueBox
extends CanvasLayer
## A level's dialogue (Part 13a, level editor Layer 2): lines with a speaker,
## shown at the bottom of the screen like a SyncAIDa holo-call, then
## optional choices. A (or a click) goes to the next line. When it ends,
## `finished` gives the choice picked ("" without choices) and the level's
## wiring hears "dialogue_ended".
##
## Doesn't pause (like the menus since Part 11): the Seeker reading it just
## stops taking game input.
##
## Data (interaction.json "dialogues"):
##   {"id": "intro", "lines": [{"speaker": "Commander Brandt", "text": "..."}],
##    "choices": [{"id": "yes", "text": "On my way."}]}

signal finished(dialogue_id: String, choice: String)

var player: Player
var dialogue := {}
var _index := 0
var _speaker: Label
var _text: Label
var _buttons: VBoxContainer


func _init() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("modal_menus")
	add_to_group("dialogue_boxes")


func open(data: Dictionary, seeker: Player = null) -> void:
	dialogue = data
	player = seeker
	if player:
		player.input_locked = true
		player.set_mouse_captured(false)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.offset_top = -230.0
	for side in ["left", "right", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 40)
	add_child(root)
	var panel := PanelContainer.new()
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 22)
	_speaker.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	box.add_child(_speaker)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 22)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 600.0
	box.add_child(_text)
	_buttons = VBoxContainer.new()
	box.add_child(_buttons)
	_show(0)


func lines() -> Array:
	return dialogue.get("lines", [])


func _show(i: int) -> void:
	_index = i
	for b in _buttons.get_children():
		_buttons.remove_child(b)
		b.queue_free()
	var all := lines()
	if i < all.size():
		var line: Dictionary = all[i]
		_speaker.text = String(line.get("speaker", ""))
		_text.text = String(line.get("text", ""))
		var last := i == all.size() - 1 and (dialogue.get("choices", []) as Array).is_empty()
		_add_button("Close" if last else "Next", func(): _advance())
	else:
		for c in dialogue.get("choices", []):
			_add_button(String(c.get("text", c.get("id", ""))), _finish.bind(String(c.get("id", ""))))
	(_buttons.get_child(_buttons.get_child_count() - 1) as Button).grab_focus.call_deferred()


func _add_button(text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	_buttons.add_child(b)


## Next line, or the choices, or the end.
func _advance() -> void:
	if _index + 1 < lines().size() or (_index + 1 == lines().size() \
			and not (dialogue.get("choices", []) as Array).is_empty()):
		_show(_index + 1)
	else:
		_finish("")


func _input(event: InputEvent) -> void:
	if _buttons and _buttons.get_child_count() > 0:
		MenuFocus.recover(_buttons, event, func(): (_buttons.get_child(0) as Button).grab_focus())


func _finish(choice: String) -> void:
	if player and is_instance_valid(player):
		player.input_locked = player.downed
		player.set_mouse_captured(true)
		player.hold_input()
	finished.emit(String(dialogue.get("id", "")), choice)
	queue_free()
