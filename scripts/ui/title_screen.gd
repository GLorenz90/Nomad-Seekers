class_name TitleScreen
extends Control
## The game's first screen (Part 8): main menu, character select (4 slots,
## like PSO) and character creation. Fully usable with a gamepad: A accepts,
## B goes back, X deletes the highlighted character (after a confirm).
##
## Creating a character saves it to its slot straight away and goes to
## Nomad-2 (the hub).

const RACE_NOTES := {
	CharacterData.Race.HUMAN: "Balanced. +5 STR, DEX and SOL. Spells to level 15.",
	CharacterData.Race.GOLUMAN: "Built by humans. +10 DEX, slowly regenerates HP, sees traps. No magic: sets traps instead. Can't be an Invoker.",
	CharacterData.Race.LUMERA: "Lumidium-touched humans. +10 SOL. Spells to level 20.",
	CharacterData.Race.CORESIAN: "Coris natives. +10 STR. Spells to level 10.",
}
const JOB_NOTES := {
	CharacterData.Job.STRIKER: "Melee. Wears any armor.",
	CharacterData.Job.RANGER: "Guns, bows and throwing weapons. Wears any armor.",
	CharacterData.Job.INVOKER: "Magic: every spell to level 30. Light armor only.",
}

var _pages: Dictionary = {}
var _message: Label
## Main menu
var _continue: Button
## Character select
var _slot_box: VBoxContainer
var _confirm_delete := -1
## Creation
var _create_slot := -1
var _name: LineEdit
var _race: OptionButton
var _gender: OptionButton
var _hand: OptionButton
var _job: OptionButton
var _starter: OptionButton
var _preview: Label
var _create_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Session.migrate_legacy()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a click on it mustn't clear focus
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 760.0
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var title := _label("NOMAD'S SEEKERS", 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.7, 0.9, 1.0)
	column.add_child(title)
	var sub := _label("Prototype", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.6, 0.65, 0.75)
	column.add_child(sub)
	_pages["main"] = _build_main(column)
	_pages["select"] = _build_select(column)
	_pages["create"] = _build_create(column)
	_message = _label("", 16)
	_message.modulate = Color(1.0, 0.85, 0.5)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	var help := _label("A: accept   B: back   X: delete a character", 14)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(0.55, 0.6, 0.7)
	column.add_child(help)
	show_page("main")


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func current_page() -> String:
	for key in _pages:
		if (_pages[key] as Control).visible:
			return key
	return ""


func show_page(key: String) -> void:
	for k in _pages:
		(_pages[k] as Control).visible = k == key
	_confirm_delete = -1
	match key:
		"main":
			_refresh_main()
		"select":
			_refresh_slots()
	focus_default.call_deferred()


## The button a page starts on (and goes back to if focus is ever lost).
func focus_default() -> void:
	match current_page():
		"main":
			(_continue if not _continue.disabled else _pages.main.get_child(1)).grab_focus()
		"select":
			(_slot_box.get_child(0) as Button).grab_focus()
		"create":
			_race.grab_focus()  # not the name box: a gamepad can't type, and it would grab the d-pad


## Gamepad safety net: with nothing focused, the first press or stick push
## focuses the page's default button instead of being lost.
func _input(event: InputEvent) -> void:
	MenuFocus.recover(self, event, focus_default)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and current_page() == "main":
		# Start works like A on the title screen.
		var focus := get_viewport().gui_get_focus_owner()
		if focus is Button:
			(focus as Button).pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		match current_page():
			"select":
				show_page("main")
			"create":
				show_page("select")
		get_viewport().set_input_as_handled()
	elif current_page() == "select" and _is_delete(event):
		var focus := get_viewport().gui_get_focus_owner()
		if focus and _slot_box.is_ancestor_of(focus):
			_delete(int(focus.get_meta("slot", -1)))
			get_viewport().set_input_as_handled()


func _is_delete(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		return true
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE


# --- Main menu ----------------------------------------------------------------------

func _build_main(column: VBoxContainer) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	column.add_child(page)
	_continue = _button(page, "Continue", _on_continue)
	_button(page, "Character select", show_page.bind("select"))
	_button(page, "Quit", get_tree().quit)
	return page


func _refresh_main() -> void:
	var last := Session.last_slot()
	var data := Session.load_slot(last) if last >= 0 else null
	_continue.disabled = data == null
	_continue.text = "Continue: %s" % _slot_text(data) if data else "Continue (no character yet)"


func _on_continue() -> void:
	if not Session.play(Session.last_slot()):
		_message.text = "That character can't be loaded."


# --- Character select -------------------------------------------------------------------

func _build_select(column: VBoxContainer) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	column.add_child(page)
	page.add_child(_label("Choose a character", 26))
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 8)
	page.add_child(_slot_box)
	_button(page, "Back", show_page.bind("main"))
	return page


func _slot_text(data: SaveData) -> String:
	var c := data.character
	var sync := data.paired_syncaida()
	return "%s   Lv %d %s %s %s%s   %s emblem%s" % [c.seeker_name, c.level(), c.race_name(),
		"F" if c.gender == CharacterData.Gender.FEMALE else "M", c.job_name(), " (left-handed)" if c.left_handed else "",
		c.emblem_name(),
		"   SyncAIDa: %s Lv %d" % [sync.display_name, sync.level()] if sync else ""]


func _refresh_slots() -> void:
	for child in _slot_box.get_children():
		_slot_box.remove_child(child)
		child.queue_free()
	for i in Session.SLOT_COUNT:
		var data := Session.load_slot(i)
		var b := _button(_slot_box, "", _on_slot.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("slot", i)
		if data:
			b.text = "%d   %s" % [i + 1, _slot_text(data)]
			b.modulate = data.character.emblem_text_color().lerp(Color.WHITE, 0.4)
		else:
			b.text = "%d   (empty: create a new character)" % (i + 1)
			b.modulate = Color(0.7, 0.75, 0.8)


func _on_slot(index: int) -> void:
	if Session.has_slot(index):
		if not Session.play(index):
			_message.text = "Slot %d can't be loaded." % (index + 1)
		return
	_create_slot = index
	_reset_creation()
	show_page("create")


## X on a filled slot asks once, then deletes on the second press.
func _delete(index: int) -> void:
	if index < 0 or not Session.has_slot(index):
		return
	if _confirm_delete != index:
		_confirm_delete = index
		_message.text = "Press X again to delete slot %d for good." % (index + 1)
		return
	Session.delete_slot(index)
	_confirm_delete = -1
	_message.text = "Slot %d deleted." % (index + 1)
	_refresh_slots()
	(_slot_box.get_child(index) as Button).grab_focus.call_deferred()


# --- Character creation ------------------------------------------------------------------

func _build_create(column: VBoxContainer) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	column.add_child(page)
	page.add_child(_label("New character", 26))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	page.add_child(grid)
	grid.add_child(_label("Name", 20))
	var name_row := HBoxContainer.new()
	_name = LineEdit.new()
	_name.custom_minimum_size.x = 340.0
	_name.max_length = 16
	_name.text_changed.connect(func(_t: String): _update_preview())
	name_row.add_child(_name)
	var roll := Button.new()
	roll.text = "New name"
	roll.pressed.connect(_next_name)
	name_row.add_child(roll)
	grid.add_child(name_row)
	_race = _option(grid, "Race", CharacterData.Race.keys())
	_gender = _option(grid, "Gender", CharacterData.Gender.keys())
	_hand = _option(grid, "Primary hand", ["Right", "Left"])
	_job = _option(grid, "Job", CharacterData.Job.keys())
	_starter = _option(grid, "SyncAIDa", [])
	for i in SyncAIDaData.STARTERS.size():
		_starter.add_item(SyncAIDaData.starter_text(i))
	_preview = _label("", 16)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size.x = 740.0
	page.add_child(_preview)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	page.add_child(buttons)
	_create_button = _button(buttons, "Create and enter Nomad-2", _create)
	_button(buttons, "Back", show_page.bind("select"))
	return page


func _option(grid: GridContainer, title: String, items: Array) -> OptionButton:
	grid.add_child(_label(title, 20))
	var o := OptionButton.new()
	o.custom_minimum_size.x = 460.0
	for item in items:
		o.add_item(String(item).capitalize())
	o.item_selected.connect(func(_i: int): _update_preview())
	grid.add_child(o)
	return o


func _reset_creation() -> void:
	_name.text = CharacterData.NAMES[randi() % CharacterData.NAMES.size()]
	_race.select(CharacterData.Race.HUMAN)
	_gender.select(CharacterData.Gender.MALE)
	_hand.select(0)
	_job.select(CharacterData.Job.STRIKER)
	_starter.select(0)
	_update_preview()


func _next_name() -> void:
	var i := (CharacterData.NAMES.find(_name.text) + 1) % CharacterData.NAMES.size()
	_name.text = CharacterData.NAMES[i]
	_update_preview()


## A throwaway CharacterData with the current choices (for the preview).
func _draft() -> CharacterData:
	var c := CharacterData.new()
	c.seeker_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Seeker"
	c.race = _race.selected as CharacterData.Race
	c.gender = _gender.selected as CharacterData.Gender
	c.job = _job.selected as CharacterData.Job
	c.left_handed = _hand.selected == 1
	return c


func _update_preview() -> void:
	if _job == null or _race == null:
		return
	# Goluman can't be Invokers: grey the choice out.
	var golu := _race.selected == CharacterData.Race.GOLUMAN
	_job.set_item_disabled(CharacterData.Job.INVOKER, golu)
	if golu and _job.selected == CharacterData.Job.INVOKER:
		_job.select(CharacterData.Job.RANGER)
	var c := _draft()
	var favored: Array = Loot.FAVORED[c.emblem_index()]
	_preview.text = "%s\n%s\n%s: primary weapon (X) in the %s hand, off hand (Y) in the %s.\nEmblem: %s (favors %s)%s\n%s" % [
		RACE_NOTES[c.race], JOB_NOTES[c.job], c.handedness_name(), "left" if c.left_handed else "right",
		"right" if c.left_handed else "left", c.emblem_name(),
		", ".join(favored.map(func(id: StringName) -> String: return String(id).replace("_", " ").capitalize())),
		"  ·  finds armor twice as often" if c.emblem_index() == Loot.ARMOR_EMBLEM else "",
		"The job is fixed once created. The emblem comes from name, race, gender and job."]
	_preview.modulate = c.emblem_text_color().lerp(Color.WHITE, 0.5)


func _create() -> void:
	if _create_slot < 0:
		_create_slot = Session.first_empty_slot()
	if _create_slot < 0:
		_message.text = "Every slot is full. Delete a character first."
		return
	var c := _draft()
	if not CharacterData.job_allowed(c.race, c.job):
		_message.text = "Goluman can't be Invokers."
		return
	var data := SaveData.create(c.seeker_name, c.race, c.gender, c.job, _starter.selected)
	data.character.left_handed = c.left_handed
	if Session.write_slot(_create_slot, data) != OK:
		_message.text = "Couldn't save the character."
		return
	Session.use_slot(_create_slot, data)
	get_tree().change_scene_to_file.call_deferred(Session.HUB_SCENE)
