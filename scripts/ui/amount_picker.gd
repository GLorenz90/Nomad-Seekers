class_name AmountPicker
extends HBoxContainer
## How many: - / + (and bigger steps for Oro), the amount, and All. Used to
## drop, buy, sell, deposit and withdraw stacks (Parts 9-10).
##
## Its focus neighbors are set by hand (wire()): full-width buttons above and
## below would otherwise catch d-pad left / right.

signal changed(value: int)

var value := 1
var maximum := 1
var _label: Label
var _buttons: Array[Button] = []


## `big_steps` adds -100 / -10 and +10 / +100 around - and +.
func setup(have: int, start: int, big_steps: bool = false) -> AmountPicker:
	maximum = maxi(have, 1)
	add_theme_constant_override("separation", 6)
	var steps := [-100, -10, -1, 1, 10, 100] if big_steps else [-1, 1]
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.custom_minimum_size.x = 80.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for step in steps:
		if step > 0 and _label.get_parent() == null:
			add_child(_label)
		var b := Button.new()
		b.text = ("-" if step < 0 else "+") + (str(absi(step)) if absi(step) > 1 else "")
		b.custom_minimum_size.x = 44.0
		b.pressed.connect(func(): set_value(value + step))
		add_child(b)
		_buttons.append(b)
	var all := Button.new()
	all.text = "All"
	all.pressed.connect(func(): set_value(maximum))
	add_child(all)
	_buttons.append(all)
	set_value(start)
	return self


func set_value(v: int) -> void:
	value = clampi(v, 1, maximum)
	if _label:
		_label.text = str(value)
	changed.emit(value)


func plus_button() -> Button:
	for b in _buttons:
		if b.text == "+":
			return b
	return _buttons[0]


func label_text() -> String:
	return _label.text if _label else ""


## Left / right along the row; up to `above` (or stay), down to `below`.
## Also points `above` down and `below` up at the + button.
func wire(above: Control, below: Control) -> void:
	for i in _buttons.size():
		var b := _buttons[i]
		b.focus_neighbor_left = b.get_path_to(_buttons[maxi(i - 1, 0)])
		b.focus_neighbor_right = b.get_path_to(_buttons[mini(i + 1, _buttons.size() - 1)])
		b.focus_neighbor_top = b.get_path_to(above if above else b)
		if below:
			b.focus_neighbor_bottom = b.get_path_to(below)
	if below:
		below.focus_neighbor_top = below.get_path_to(plus_button())
	if above:
		above.focus_neighbor_bottom = above.get_path_to(plus_button())
