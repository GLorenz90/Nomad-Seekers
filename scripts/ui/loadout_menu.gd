class_name LoadoutMenu
extends CanvasLayer
## Loadout editor (Start / Tab). Pauses the game while open.
##
## Pick a hand slot, then a weapon. Two-handed weapons clear the other hand.
## Each loadout shows whether it breaks a rule (one Heavy item unless the
## Double-Heavy augment is on). Broken or empty loadouts are skipped by LB/RB.
## Closing saves to user://loadouts.tres.

signal closed

const WEAPON_DIR := "res://data/weapons/"

var combat: CombatController
## Tests turn this off so they never overwrite the player's saved loadouts.
var save_on_close := true

var _set: LoadoutSet
var _weapons: Array[WeaponData] = []
var _slot_buttons: Array = []  # [[left Button, right Button], ...]
var _slot_status: Array[Label] = []
var _picker: VBoxContainer
var _picker_title: Label
var _message: Label
var _augment: CheckButton
var _powerstance: CheckButton
var _editing := Vector2i(-1, -1)  # (loadout index, hand)
var _root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_weapons = _scan_weapons()
	_build()
	visible = false


func setup(controller: CombatController) -> void:
	combat = controller


func is_open() -> bool:
	return visible


func open() -> void:
	if combat == null:
		return
	_set = combat.loadout_set
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_close_picker()
	_refresh()
	(_slot_buttons[combat.loadout_index][0] as Button).grab_focus()


func close() -> void:
	if not visible:
		return
	_close_picker()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if save_on_close:
		_set.save()
	combat.apply_loadout_set(_set)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		if _picker.visible:
			var back_to: Button = _slot_buttons[_editing.x][_editing.y]
			_close_picker()
			back_to.grab_focus()
		else:
			close()
		get_viewport().set_input_as_handled()


# --- Editing ------------------------------------------------------------------

## Equip a weapon into a slot, applying the two-handed rule. Returns the
## loadout's rule error ("" when valid). Used by the menu and by tests.
func equip(index: int, hand: int, weapon: WeaponData) -> String:
	var l := _set.loadouts[index]
	l.set_hand(hand, weapon)
	if weapon and weapon.two_handed:
		l.set_hand(1 - hand, null)
	else:
		var other := l.get_hand(1 - hand)
		if other and other.two_handed and weapon != null:
			l.set_hand(1 - hand, null)
	return l.validate(_set.double_heavy_augment)


func _on_slot_pressed(index: int, hand: int) -> void:
	_editing = Vector2i(index, hand)
	_picker_title.text = "Loadout %d, %s hand (%s)" % [
		index + 1, "left" if hand == 0 else "right", combat.button_for(hand)]
	_picker.visible = true
	(_picker.get_child(1) as Button).grab_focus()


func _on_weapon_picked(weapon: WeaponData) -> void:
	var error := equip(_editing.x, _editing.y, weapon)
	var back_to: Button = _slot_buttons[_editing.x][_editing.y]
	_close_picker()
	_refresh()
	_message.text = error if error != "" else "Loadout %d updated." % (_editing.x + 1)
	back_to.grab_focus()


func _close_picker() -> void:
	if _picker:
		_picker.visible = false


func _refresh() -> void:
	if _set == null:
		return
	for i in _set.loadouts.size():
		var l := _set.loadouts[i]
		var two_hand := l.two_handed_weapon()
		for hand in 2:
			var b: Button = _slot_buttons[i][hand]
			var w := l.get_hand(hand)
			if w == null and two_hand:
				b.text = "(%s)" % two_hand.display_name
			else:
				b.text = _weapon_label(w)
		var error := l.validate(_set.double_heavy_augment)
		var status := _slot_status[i]
		if l.is_empty():
			status.text = "empty"
			status.modulate = Color(0.6, 0.6, 0.6)
		elif error != "":
			status.text = "breaks a rule"
			status.modulate = Color(1.0, 0.5, 0.4)
		else:
			status.text = _lt_short(l)
			status.modulate = Color(0.6, 1.0, 0.6)
	_augment.set_pressed_no_signal(_set.double_heavy_augment)
	_powerstance.set_pressed_no_signal(_set.powerstance_default)


func _lt_short(l: Loadout) -> String:
	match l.get_lt_mode():
		Loadout.LTMode.SHIELD:
			return "LT shield %d%%" % roundi(l.block_strength() * 100.0)
		Loadout.LTMode.TWO_HAND:
			return "LT 2h block %d%%" % roundi(l.block_strength() * 100.0)
		Loadout.LTMode.POWERSTANCE:
			return "LT powerstance"
		Loadout.LTMode.ARMS_UP:
			return "LT arms-up %d%%" % roundi(l.block_strength() * 100.0)
	return ""


func _weapon_label(w: WeaponData) -> String:
	if w == null:
		return "-"
	var tags := PackedStringArray()
	tags.append("Heavy" if w.is_heavy() else "Light")
	if w.two_handed:
		tags.append("2h")
	if w.is_shield:
		tags.append("shield")
	if w.sustained:
		tags.append("sustained")
	return "%s  (%s)" % [w.display_name, ", ".join(tags)]


func _scan_weapons() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		return list
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds list text resources as *.tres.remap.
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var w := load(WEAPON_DIR + file) as WeaponData
			if w:
				list.append(w)
	return list


# --- Layout -------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -590.0
	panel.offset_top = -330.0
	panel.offset_right = 590.0
	panel.offset_bottom = 330.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20.0)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 780.0
	columns.add_child(left)
	left.add_child(_label("Loadouts", 26))
	left.add_child(_label("Pick a hand, then a weapon.  A/Enter: select   B/Esc: back   Start/Tab: close and save", 14))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for header in ["", "Left hand", "Right hand", "LT"]:
		grid.add_child(_label(header, 14))
	for i in LoadoutSet.SLOT_COUNT:
		grid.add_child(_label(str(i + 1), 18))
		var pair := []
		for hand in 2:
			var b := Button.new()
			b.custom_minimum_size = Vector2(270.0, 34.0)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(_on_slot_pressed.bind(i, hand))
			grid.add_child(b)
			pair.append(b)
		_slot_buttons.append(pair)
		var status := _label("", 14)
		status.custom_minimum_size.x = 150.0
		grid.add_child(status)
		_slot_status.append(status)

	_augment = CheckButton.new()
	_augment.text = "Double-Heavy augment (two Heavy one-handed items)"
	_augment.toggled.connect(func(on: bool):
		_set.double_heavy_augment = on
		_refresh())
	left.add_child(_augment)
	_powerstance = CheckButton.new()
	_powerstance.text = "Powerstance by default (hold LT for single-hand attacks)"
	_powerstance.toggled.connect(func(on: bool):
		_set.powerstance_default = on
		_refresh())
	left.add_child(_powerstance)
	_message = _label("", 16)
	_message.modulate = Color(1.0, 0.85, 0.5)
	left.add_child(_message)

	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 4)
	_picker.custom_minimum_size.x = 330.0
	columns.add_child(_picker)
	_picker_title = _label("", 18)
	_picker.add_child(_picker_title)
	var empty := Button.new()
	empty.text = "(Empty)"
	empty.alignment = HORIZONTAL_ALIGNMENT_LEFT
	empty.pressed.connect(_on_weapon_picked.bind(null))
	_picker.add_child(empty)
	for w in _weapons:
		var b := Button.new()
		b.text = _weapon_label(w)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_weapon_picked.bind(w))
		_picker.add_child(b)
	_picker.visible = false


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label
