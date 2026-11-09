class_name LoadoutMenu
extends CanvasLayer
## Loadout editor (Start / Tab). Pauses the game while open.
##
## Pick a hand slot, then a weapon. Two-handed weapons clear the other hand.
## Each loadout shows whether it breaks a rule (one Heavy item unless the
## Double-Heavy augment is on). Broken or empty loadouts are skipped by LB/RB.
## Closing saves everything to user://save.tres (SaveData).
##
## Tabs (LB/RB switch): Loadouts, Inventory (found weapons, consumables, Oro,
## Lumidium) and Character (name, race, gender, job; the emblem follows from
## them). The weapon picker lists every base weapon plus the weapons you've
## found; weapons your job can't use are greyed out.
## SyncAIDa tab (Part 6): pair one of your SyncAIDa, feed it consumables or
## banked Lumidium, and pick its active Sync Burst.
## Levels tab (prototype only): switch levels and testing tools (refills,
## debug readout, hitboxes). Controls tab: the control reference.
##
## Fully usable by gamepad: d-pad / left stick move focus, A accepts, B goes
## back (or closes), LB / RB switch tabs, Start closes. Every tab switch moves
## focus into the new tab, and rebuilt lists put focus back on a real control.

signal closed

const WEAPON_DIR := "res://data/weapons/"
## Level select (prototype): [label, scene].
const LEVELS := [
	["Test room", "res://scenes/main.tscn"],
	["Arena (wave rooms, Lumidium, teleporters)", "res://scenes/arena.tscn"],
]
## Names for the gamepad-friendly "New name" button.
const NAMES := ["Seeker", "Ardent", "Brielle", "Cassian", "Dara", "Eamon", "Fenna", "Galen",
	"Halcyon", "Iris", "Jory", "Kestra", "Lumen", "Maren", "Nolan", "Orrin", "Perrin", "Quill",
	"Rook", "Sable", "Tamsin", "Ulric", "Vesper", "Wren"]

var combat: CombatController
## Tests turn this off so they never overwrite the player's saved loadouts.
var save_on_close := true

var _set: LoadoutSet
var _weapons: Array[WeaponData] = []
var _slot_buttons: Array = []  # [[left Button, right Button], ...]
var _slot_status: Array[Label] = []
var _picker: VBoxContainer
var _picker_title: Label
var _picker_list: VBoxContainer
var _message: Label
var _augment: Label
var _editing := Vector2i(-1, -1)  # (loadout index, hand)
var _root: Control
var _tabs: TabContainer
var _inventory_text: RichTextLabel
var _character_info: Label
var _name_edit: LineEdit
var _race: OptionButton
var _gender: OptionButton
var _job: OptionButton
var _sync_owned: VBoxContainer
var _spells_tab: SpellsTab
var _armor_tab: ArmorTab
var _learn_pick: OptionButton
var _learn_level := 1
var _learn_level_label: Label
var _sync_starter_title: Label
var _sync_starters: VBoxContainer
var _sync_info: Label
## Per-stat rows: stat -> [level Label, ProgressBar, percent Label].
var _sync_stat_rows := {}
var _sync_feeds: GridContainer
var _sync_burst: OptionButton
var _sync_message: Label
var _character_message: Label
var _infinite_lp: CheckButton
var _material_buttons := {}  # id -> Button
var _material_info: Label
## Debug: feeding doesn't use up items (for trying evolutions quickly).
var free_feeding := false
var _free_feeding_toggle: CheckButton
var _level_message: Label
var _debug_toggle: CheckButton
var _hitbox_toggle: CheckButton
var _free_feeding_levels: CheckButton
var _level_buttons: Array[Button] = []


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
	_rebuild_picker()
	_load_character()
	_tabs.set_current_tab(0)
	var seeker := _player()
	if seeker and seeker.save and seeker.save.syncaida.is_empty():
		_tabs.set_current_tab(_tab_index("SyncAIDa"))
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_close_picker()
	_refresh()
	_focus_tab()


func close() -> void:
	if not visible:
		return
	_close_picker()
	get_viewport().gui_release_focus()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	combat.apply_loadout_set(_set)
	var seeker := _player()
	if save_on_close and seeker:
		seeker.save_game()
	closed.emit()


func _player() -> Player:
	return combat.get_parent() as Player if combat else null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("loadout_next") or event.is_action_pressed("loadout_prev")):
		var step := 1 if event.is_action_pressed("loadout_next") else -1
		_close_picker()
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
		get_viewport().set_input_as_handled()
	elif visible and _tab_name() == "Spells" and _clear_input(event) == 1:
		if _spells_tab.clear_focused_slot():
			get_viewport().set_input_as_handled()
	elif visible and _tab_name() == "Spells" and event.is_action_pressed("ui_cancel") and _spells_tab.back():
		get_viewport().set_input_as_handled()
	elif visible and _tab_name() == "Armor" and _clear_input(event) == 1:
		if _armor_tab.clear_focused():
			get_viewport().set_input_as_handled()
	elif visible and _tab_name() == "Armor" and event.is_action_pressed("ui_cancel") and _armor_tab.back():
		get_viewport().set_input_as_handled()
	elif visible and _tab_name() == "Loadouts" and not _picker.visible and _clear_input(event) != 0:
		_clear_focused_slot(_clear_input(event) == 2)
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
	if weapon and weapon.two_handed:
		# A two-handed weapon is one item, held in the right hand.
		l.right = weapon
		l.left = null
		return l.validate(_set.double_heavy_augment)
	l.set_hand(hand, weapon)
	var other := l.get_hand(1 - hand)
	if other and other.two_handed and weapon != null:
		l.set_hand(1 - hand, null)
	return l.validate(_set.double_heavy_augment)


func _on_slot_pressed(index: int, hand: int) -> void:
	_editing = Vector2i(index, hand)
	_picker_title.text = "Loadout %d, %s hand (%s)" % [
		index + 1, "left" if hand == 0 else "right", combat.button_for(hand)]
	_picker.visible = true
	(_picker_list.get_child(0) as Button).grab_focus()


func _on_weapon_picked(weapon: WeaponData) -> void:
	if weapon and combat and not weapon.can_be_used_by(combat.job_code):
		_message.text = "%s needs %s (change job in the Character tab)." % [weapon.display_name, weapon.jobs_text()]
		return
	var error := equip(_editing.x, _editing.y, weapon)
	if error == "":
		error = combat.job_error(_set.loadouts[_editing.x])
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
				b.text = "(both hands)"
			else:
				b.text = _weapon_label(w)
		var error := l.validate(_set.double_heavy_augment)
		var job_error := combat.job_error(l)
		var status := _slot_status[i]
		if l.is_empty():
			status.text = "empty"
			status.modulate = Color(0.6, 0.6, 0.6)
		elif error != "":
			status.text = "breaks a rule"
			status.modulate = Color(1.0, 0.5, 0.4)
		elif job_error != "":
			status.text = "job locked"
			status.modulate = Color(1.0, 0.7, 0.3)
		else:
			status.text = _lt_short(l)
			status.modulate = Color(0.6, 1.0, 0.6)
	_augment.text = "Double-Heavy augment: %s" % ("worn (two Heavy one-handed items allowed)" \
		if _set.double_heavy_augment else "not worn (slot one into your armor in the Armor tab)")
	_refresh_inventory()
	_refresh_character()
	_refresh_syncaida()
	_refresh_levels()
	if _spells_tab:
		_spells_tab.refresh()
	if _armor_tab:
		_armor_tab.refresh()


func _lt_short(l: Loadout) -> String:
	if l.is_powerstance():
		return "powerstance, LT %d%%" % roundi(l.block_strength() * 100.0)
	match l.get_lt_mode():
		Loadout.LTMode.SHIELD:
			return "LT shield %d%%" % roundi(l.block_strength() * 100.0)
		Loadout.LTMode.TWO_HAND:
			return "LT 2h block %d%%" % roundi(l.block_strength() * 100.0)
		Loadout.LTMode.ARMS_UP:
			return "LT arms-up %d%%" % roundi(l.block_strength() * 100.0)
	return ""


func _weapon_label(w: WeaponData) -> String:
	if w == null:
		return "-"
	var tags := PackedStringArray()
	if w.jobs.size() < 3:
		tags.append(w.jobs_text())
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
	panel.offset_top = -360.0
	panel.offset_right = 590.0
	panel.offset_bottom = 360.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20.0)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	_tabs = TabContainer.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	# Tabs switch with LB / RB; keep the d-pad out of the tab bar.
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(func(_t: int):
		if visible:
			_refresh()
			_focus_tab.call_deferred())
	panel.add_child(_tabs)
	var columns := HBoxContainer.new()
	columns.name = "Loadouts"
	columns.add_theme_constant_override("separation", 24)
	_tabs.add_child(columns)
	_spells_tab = SpellsTab.new(self)
	_tabs.add_child(_spells_tab)
	_armor_tab = ArmorTab.new(self)
	_tabs.add_child(_armor_tab)
	_build_inventory_tab()
	_build_character_tab()
	_build_syncaida_tab()
	_build_levels_tab()
	_build_controls_tab()

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 780.0
	columns.add_child(left)
	left.add_child(_label("Loadouts", 26))
	left.add_child(_label("Pick a hand, then a weapon.  A/Enter: select   B/Esc: back   LB/RB: tabs   Start/Tab: close and save\nX/Delete: unequip that hand   Y/Shift+Delete: clear the whole loadout", 14))

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
		status.custom_minimum_size.x = 170.0
		grid.add_child(status)
		_slot_status.append(status)

	var clear_all := Button.new()
	clear_all.text = "Clear all loadouts (testing)"
	clear_all.pressed.connect(_clear_all_loadouts)
	clear_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(clear_all)
	_augment = _label("", 14)
	_augment.modulate = Color(0.75, 0.85, 1.0)
	left.add_child(_augment)
	left.add_child(_label("A pair of the same weapon type is powerstanced: every attack uses both. RT + a hand uses that hand's special.", 13))
	_message = _label("", 16)
	_message.modulate = Color(1.0, 0.85, 0.5)
	left.add_child(_message)

	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 4)
	_picker.custom_minimum_size.x = 330.0
	columns.add_child(_picker)
	_picker_title = _label("", 18)
	_picker.add_child(_picker_title)
	_picker_list = VBoxContainer.new()
	_picker_list.add_theme_constant_override("separation", 2)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330.0, 560.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.add_child(_picker_list)
	_picker.add_child(scroll)
	_rebuild_picker()
	_picker.visible = false


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


# --- Picker, inventory and character tabs (Part 5) -----------------------------

## Base weapons, then found weapons (newest first). Job-locked ones are disabled.
func _rebuild_picker() -> void:
	if _picker_list == null:
		return
	for child in _picker_list.get_children():
		_picker_list.remove_child(child)
		child.queue_free()
	var empty := Button.new()
	empty.text = "(Empty)"
	empty.alignment = HORIZONTAL_ALIGNMENT_LEFT
	empty.pressed.connect(_on_weapon_picked.bind(null))
	_picker_list.add_child(empty)
	var found: Array[WeaponData] = []
	var seeker := _player()
	if seeker and seeker.save:
		found = seeker.save.inventory.weapons.duplicate()
		found.reverse()
	if not found.is_empty():
		_picker_list.add_child(_label("Found", 14))
	for w in found:
		_picker_list.add_child(_weapon_button(w, true))
	# Base weapons grouped like the North Star's weapon table, A-Z in each group.
	for group in [["Melee", WeaponData.WeaponClass.MELEE, false], ["Ranged", WeaponData.WeaponClass.RANGED, false],
			["Magic", WeaponData.WeaponClass.MAGIC, false], ["Shields", -1, true]]:
		var header := _label(group[0], 14)
		header.modulate = Color(0.7, 0.8, 1.0)
		_picker_list.add_child(header)
		for w in _weapons:
			if w.is_shield == group[2] and (group[2] or w.weapon_class == group[1]):
				_picker_list.add_child(_weapon_button(w, false))


func _weapon_button(w: WeaponData, found: bool) -> Button:
	var b := Button.new()
	b.text = _weapon_label(w)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = Loot.describe(w)
	if found:
		b.modulate = Color(1.0, 0.6, 1.0) if w.rare else Color(0.75, 0.9, 1.0)
	if combat and not w.can_be_used_by(combat.job_code):
		# Still focusable (so the d-pad doesn't skip it); A explains the lock.
		b.modulate = Color(0.55, 0.55, 0.6)
		b.set_meta("locked", true)
	b.pressed.connect(_on_weapon_picked.bind(w))
	return b


func _build_inventory_tab() -> void:
	_inventory_text = RichTextLabel.new()
	_inventory_text.name = "Inventory"
	_inventory_text.bbcode_enabled = true
	_inventory_text.custom_minimum_size = Vector2(1100.0, 600.0)
	_inventory_text.add_theme_font_size_override("normal_font_size", 17)
	# Focusable so the d-pad / left stick scroll it.
	_inventory_text.focus_mode = Control.FOCUS_ALL
	_inventory_text.scroll_active = true
	_tabs.add_child(_inventory_text)


func _refresh_inventory() -> void:
	var seeker := _player()
	if _inventory_text == null or seeker == null or seeker.save == null:
		return
	var inv := seeker.save.inventory
	var lines := PackedStringArray()
	lines.append("[b]Oro[/b] %d" % inv.oro)
	var lum := PackedStringArray()
	for color in Inventory.LUMIDIUM:
		lum.append("%s %d" % [String(color).capitalize(), int(inv.lumidium.get(color, 0))])
	lines.append("[b]Banked Lumidium[/b]  " + "   ".join(lum))
	lines.append("[b]Carried Lumidium[/b] %d (lost on death until deposited)" % seeker.carried_lumidium_total())
	var items := PackedStringArray()
	for id in Inventory.CONSUMABLES:
		items.append("%s x%d" % [Inventory.CONSUMABLES[id], inv.count(id)])
	lines.append("[b]Consumables[/b]  " + "   ".join(items))
	var mats := PackedStringArray()
	for id in Materials.ALL:
		if inv.count(id) > 0:
			mats.append("%s x%d" % [Materials.display_name(id), inv.count(id)])
	lines.append("[b]Materials[/b]  " + ("   ".join(mats) if not mats.is_empty() else "none (use them in the Character tab)"))
	lines.append("[b]Armor[/b] %d spare piece%s, %d augment%s (wear and slot them in the Armor tab)" % [
		inv.armors.size(), "" if inv.armors.size() == 1 else "s",
		inv.units.values().reduce(func(t, n): return t + int(n), 0), "" if inv.units.size() == 1 else "s"])
	lines.append("")
	lines.append("[b]Found weapons[/b] (%d)" % inv.weapons.size())
	if inv.weapons.is_empty():
		lines.append("  none yet: enemies drop them from your emblem's pool")
	for i in range(inv.weapons.size() - 1, -1, -1):
		var w := inv.weapons[i]
		var color := "#ff99ff" if w.rare else "#bfe0ff"
		lines.append("  [color=%s]%s[/color]  [%s]  %s" % [color, w.display_name, w.jobs_text(), Loot.describe(w)])
	_inventory_text.text = "\n".join(lines)


func _build_character_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Character"
	box.add_theme_constant_override("separation", 10)
	_tabs.add_child(box)
	box.add_child(_label("Character (placeholder until character creation)", 22))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	grid.add_child(_label("Name", 18))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 300.0
	# Typing needs a keyboard: click to edit. Gamepads use "New name".
	_name_edit.focus_mode = Control.FOCUS_CLICK
	_name_edit.text_changed.connect(func(_t: String): _apply_character())
	var name_row := HBoxContainer.new()
	name_row.add_child(_name_edit)
	var new_name := Button.new()
	new_name.text = "New name"
	new_name.pressed.connect(func():
		var i := (NAMES.find(_name_edit.text) + 1) % NAMES.size()
		_name_edit.text = NAMES[i]
		_apply_character())
	name_row.add_child(new_name)
	grid.add_child(name_row)
	_race = _option(grid, "Race", CharacterData.Race.keys())
	_gender = _option(grid, "Gender", CharacterData.Gender.keys())
	_job = _option(grid, "Job", CharacterData.Job.keys())
	# Chosen at character creation and fixed afterwards (debug: Levels tab).
	_job.disabled = true
	_job.focus_mode = Control.FOCUS_NONE
	_character_info = _label("", 18)
	box.add_child(_character_info)
	var reset := Button.new()
	reset.text = "Reset character to level 1 (testing)"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_reset_character)
	box.add_child(reset)
	# PSO materials: each use raises a stat by 2, up to the race's limits.
	box.add_child(_label("Materials", 20))
	_material_info = _label("", 15)
	box.add_child(_material_info)
	var mats := GridContainer.new()
	mats.columns = 3
	mats.add_theme_constant_override("h_separation", 10)
	mats.add_theme_constant_override("v_separation", 6)
	box.add_child(mats)
	for id in Materials.ALL:
		var b := Button.new()
		b.custom_minimum_size.x = 330.0
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_use_material.bind(id))
		mats.add_child(b)
		_material_buttons[id] = b
	_character_message = _label("", 15)
	_character_message.modulate = Color(1.0, 0.85, 0.5)
	box.add_child(_character_message)
	box.add_child(_label("The emblem comes from name, race, gender and job (like PSO section IDs). It picks the weapon\nfamilies and rares your drops favor. The job is set at character creation and can't change\n(Levels tab has a debug switch). Jobs lock weapons: S = Striker, R = Ranger, I = Invoker.", 14))


func _option(parent: Node, caption: String, names: Array) -> OptionButton:
	parent.add_child(_label(caption, 18))
	var option := OptionButton.new()
	for n in names:
		option.add_item(String(n).capitalize())
	option.item_selected.connect(func(_i: int): _apply_character())
	parent.add_child(option)
	return option


func _load_character() -> void:
	var seeker := _player()
	if seeker == null or seeker.save == null or _name_edit == null:
		return
	var c := seeker.save.character
	_name_edit.text = c.seeker_name
	_race.select(c.race)
	_gender.select(c.gender)
	_job.select(c.job)


func _apply_character() -> void:
	var seeker := _player()
	if seeker == null or seeker.save == null:
		return
	var c := seeker.save.character
	c.seeker_name = _name_edit.text if _name_edit.text.strip_edges() != "" else "Seeker"
	var new_race := _race.selected as CharacterData.Race
	if not CharacterData.job_allowed(new_race, c.job):
		_race.select(c.race)
		_character_message.text = "Goluman can't be Invokers."
	elif new_race != c.race:
		c.race = new_race
	c.gender = _gender.selected as CharacterData.Gender
	var removed := ArmorBook.strip_unwearable(seeker.save)
	if not removed.is_empty():
		_character_message.text = "Took off %s (can't wear it now)." % ", ".join(removed)
	seeker.apply_bonuses()  # race stat bonuses, armor
	_refresh_character()


## Debug only (Levels tab): the job is otherwise fixed at creation.
func _tool_cycle_job() -> void:
	var seeker := _player()
	var c := seeker.save.character
	c.job = ((c.job + 1) % CharacterData.Job.size()) as CharacterData.Job
	if not CharacterData.job_allowed(c.race, c.job):  # Goluman skip Invoker
		c.job = ((c.job + 1) % CharacterData.Job.size()) as CharacterData.Job
	combat.job_code = c.job_code()
	_job.select(c.job)
	ArmorBook.strip_unwearable(seeker.save)
	seeker.apply_bonuses()
	_rebuild_picker()
	_refresh()
	_level_message.text = "Job is now %s (emblem %s)." % [c.job_name(), c.emblem_name()]


func _refresh_character() -> void:
	var seeker := _player()
	if _character_info == null or seeker == null or seeker.save == null:
		return
	var c := seeker.save.character
	var favored: Array = Loot.FAVORED[c.emblem_index()]
	var rares := PackedStringArray()
	for w in Loot.rares_for(c.emblem_index()):
		rares.append(w.display_name)
	_character_info.text = "Emblem: %s    EXP: %d\nFavored drops: %s, %s\nRares in this pool: %s" % [
		c.emblem_name(), c.experience, String(favored[0]).capitalize(), String(favored[1]).capitalize(),
		", ".join(rares) if not rares.is_empty() else "none"]
	_character_info.modulate = c.emblem_text_color()
	if _material_info:
		_material_info.text = "Used: stat materials %s   HP %s   LP %s   (A uses one: +%d to its stat, permanent)" % [
			Materials.limit_text(c, &"stat"), Materials.limit_text(c, &"hp"), Materials.limit_text(c, &"lp"),
			int(Materials.PER_USE)]
		for id in _material_buttons:
			var b: Button = _material_buttons[id]
			var have := seeker.save.inventory.count(id)
			b.text = "%s x%d  (%s +2, used %d)" % [Materials.display_name(id), have, Materials.stat_label(id),
				int(c.materials.get(id, 0))]
			# Greyed but still pressable, so A explains why it can't be used.
			b.modulate = Color(1, 1, 1, 0.45) if have <= 0 or Materials.use_error(c, id) != "" else Color.WHITE


func _use_material(id: StringName) -> void:
	var seeker := _player()
	if seeker == null:
		return
	_character_message.text = seeker.use_material(id)
	_refresh_character()


# --- SyncAIDa tab (Part 6) -------------------------------------------------------

func _build_syncaida_tab() -> void:
	var columns := HBoxContainer.new()
	columns.name = "SyncAIDa"
	columns.add_theme_constant_override("separation", 28)
	_tabs.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300.0
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	left.add_child(_label("Your SyncAIDa (pick one to pair)", 18))
	_sync_owned = VBoxContainer.new()
	left.add_child(_sync_owned)
	_sync_starter_title = _label("", 18)
	left.add_child(_sync_starter_title)
	_sync_starters = VBoxContainer.new()
	left.add_child(_sync_starters)
	for i in SyncAIDaData.STARTERS.size():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = SyncAIDaData.starter_text(i)
		b.modulate = SyncAIDaData.STAT_COLORS[SyncAIDaData.STARTERS[i][1]].lightened(0.3)
		b.pressed.connect(_on_starter.bind(i))
		_sync_starters.add_child(b)

	var mid := VBoxContainer.new()
	mid.custom_minimum_size.x = 420.0
	mid.add_theme_constant_override("separation", 8)
	columns.add_child(mid)
	_sync_info = _label("", 17)
	mid.add_child(_sync_info)
	# PSO-style per-stat progress: level, a bar to the next level, and percent.
	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", 10)
	mid.add_child(stats)
	for stat in SyncAIDaData.STATS:
		var stat_label := _label(SyncAIDaData.STAT_NAMES[stat], 17)
		stat_label.modulate = SyncAIDaData.STAT_COLORS[stat].lightened(0.3)
		stat_label.custom_minimum_size.x = 48.0
		stats.add_child(stat_label)
		var lv := _label("", 17)
		lv.custom_minimum_size.x = 64.0
		stats.add_child(lv)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220.0, 16.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = SyncAIDaData.STAT_COLORS[stat]
		bar.add_theme_stylebox_override("fill", fill)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.2, 0.22, 0.28)
		bar.add_theme_stylebox_override("background", track)
		stats.add_child(bar)
		var pct := _label("", 15)
		pct.custom_minimum_size.x = 56.0
		stats.add_child(pct)
		_sync_stat_rows[stat] = [lv, bar, pct]
	var burst_row := HBoxContainer.new()
	burst_row.add_child(_label("Active Sync Burst ", 17))
	_sync_burst = OptionButton.new()
	_sync_burst.item_selected.connect(func(i: int):
		var d := _paired_data()
		if d:
			d.active_burst = i
			_refresh_syncaida())
	burst_row.add_child(_sync_burst)
	mid.add_child(burst_row)
	mid.add_child(_label("Forms: Lv 10 and Lv 35 by strongest stat, Lv 50+ by the two strongest\n(re-checked every 5 levels). Each of those milestones unlocks a Sync Burst.\nForms only depend on stats, so you can raise one for another character.", 13))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	right.add_child(_label("Feed", 18))
	_sync_feeds = GridContainer.new()
	_sync_feeds.columns = 2
	_sync_feeds.add_theme_constant_override("h_separation", 10)
	right.add_child(_sync_feeds)
	for item in SyncAIDaData.FEEDS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 150.0
		b.pressed.connect(_on_feed.bind(item))
		b.set_meta("item", item)
		_sync_feeds.add_child(b)
		var effect := _label(_feed_text(item), 13)
		_sync_feeds.add_child(effect)
	var reset := Button.new()
	reset.text = "Reset to base stats (testing)"
	reset.pressed.connect(_reset_syncaida)
	right.add_child(reset)
	_free_feeding_toggle = CheckButton.new()
	_free_feeding_toggle.text = "Free feeding (debug)"
	_free_feeding_toggle.toggled.connect(_set_free_feeding)
	right.add_child(_free_feeding_toggle)
	_sync_message = _label("", 16)
	_sync_message.modulate = Color(1.0, 0.85, 0.5)
	right.add_child(_sync_message)


func _feed_text(item: StringName) -> String:
	var parts := PackedStringArray()
	var effect: Dictionary = SyncAIDaData.FEEDS[item]
	for stat in SyncAIDaData.STATS:
		if effect.has(stat):
			parts.append("%s %+d" % [SyncAIDaData.STAT_NAMES[stat], roundi(float(effect[stat]))])
	return " ".join(parts)


func _paired_data() -> SyncAIDaData:
	var seeker := _player()
	return seeker.save.paired_syncaida() if seeker and seeker.save else null


func _on_pair(index: int) -> void:
	var seeker := _player()
	if seeker == null:
		return
	seeker.pair_syncaida(index)
	_sync_message.text = "Paired with %s." % seeker.syncaida.data.display_name
	_refresh_syncaida.call_deferred()


func _on_starter(index: int) -> void:
	var seeker := _player()
	if seeker == null:
		return
	seeker.choose_starter(index)
	_sync_message.text = "%s joined you." % seeker.syncaida.data.display_name
	_refresh_syncaida.call_deferred()
	_focus_paired.call_deferred()


func _on_feed(item: StringName) -> void:
	var seeker := _player()
	if seeker == null:
		return
	var events := seeker.syncaida.feed(item, free_feeding)
	var d := seeker.syncaida.data
	if d == null:
		_sync_message.text = "Choose a starter first."
	elif events.is_empty():
		_sync_message.text = "You don't have any to feed."
	elif "evolved" in events:
		_sync_message.text = "%s evolved into %s!" % [d.display_name, d.form]
	elif "level" in events:
		_sync_message.text = "%s reached level %d." % [d.display_name, d.level()]
	else:
		_sync_message.text = "%s ate it." % d.display_name
	if "burst" in events:
		_sync_message.text += "  New Sync Burst: %s" % SyncAIDaData.BURST_NAMES[d.bursts[-1]]
	_refresh_syncaida()


func _refresh_syncaida() -> void:
	var seeker := _player()
	if _sync_owned == null or seeker == null or seeker.save == null:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var had_focus := focus != null and (_sync_owned.is_ancestor_of(focus) or _sync_starters.is_ancestor_of(focus))
	for child in _sync_owned.get_children():
		# Never free() here: this can run from one of these buttons' own signals.
		_sync_owned.remove_child(child)
		child.queue_free()
	for i in seeker.save.syncaida.size():
		var d := seeker.save.syncaida[i]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s%s  Lv %d %s" % ["> " if i == seeker.save.paired else "   ", d.display_name, d.level(), d.form]
		b.modulate = d.color().lightened(0.3)
		b.pressed.connect(_on_pair.bind(i))
		_sync_owned.add_child(b)
		if had_focus and i == seeker.save.paired:
			b.grab_focus.call_deferred()
	var inv := seeker.save.inventory
	for child in _sync_feeds.get_children():
		if child is Button:
			var item: StringName = child.get_meta("item")
			var have := inv.count(item) if Inventory.CONSUMABLES.has(item) else int(inv.lumidium.get(item, 0))
			var label: String = Inventory.CONSUMABLES.get(item, "%s Lumidium" % String(item).capitalize())
			(child as Button).text = "%s x%d" % [label, have]
	var none := seeker.save.syncaida.is_empty()
	_sync_starter_title.text = "Choose your starting SyncAIDa" if none else "\nAdopt another starter (debug)"
	_sync_starters.visible = none or free_feeding
	_sync_starter_title.visible = _sync_starters.visible
	var d := seeker.save.paired_syncaida()
	if d == null:
		_sync_info.text = "No SyncAIDa yet. Pick a starter on the left:\neach begins at level 5 in one stat."
		_sync_burst.clear()
		_sync_burst.disabled = true
		for stat in SyncAIDaData.STATS:
			var row: Array = _sync_stat_rows[stat]
			(row[0] as Label).text = "-"
			(row[1] as ProgressBar).value = 0.0
			(row[2] as Label).text = ""
		return
	var next := d.next_milestone()
	var bonus := d.bonuses()
	_sync_info.text = "%s  (%s)\nLevel %d / %d%s\nAdds to you: DEF +%d  STR +%d  DEX +%d  SOL +%d\nSync gauge %d%%" % [
		d.display_name, d.form, d.level(), SyncAIDaData.MAX_LEVEL,
		"   next evolution at %d" % next if next > 0 else "",
		int(bonus[&"def"]), int(bonus[&"str"]), int(bonus[&"dex"]), int(bonus[&"sol"]),
		roundi(d.gauge)]
	for stat in SyncAIDaData.STATS:
		var row: Array = _sync_stat_rows[stat]
		(row[0] as Label).text = "Lv %d" % d.stat_level(stat)
		(row[1] as ProgressBar).value = d.stat_progress(stat)
		(row[2] as Label).text = "%d%%" % floori(d.stat_progress(stat) * 100.0)
	_sync_info.modulate = d.color().lightened(0.4)
	_sync_burst.clear()
	for b in d.bursts:
		_sync_burst.add_item(SyncAIDaData.BURST_NAMES[b])
	if d.bursts.is_empty():
		_sync_burst.add_item("(none until level 10)")
		_sync_burst.disabled = true
	else:
		_sync_burst.disabled = false
		_sync_burst.select(clampi(d.active_burst, 0, d.bursts.size() - 1))


# --- Gamepad focus --------------------------------------------------------------

func _tab_index(tab_name: String) -> int:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_control(i).name == tab_name:
			return i
	return 0


## Puts focus on the first usable control of the current tab, so the d-pad
## and A always have something to work with.
func _focus_tab() -> void:
	if not visible:
		return
	var page := _tabs.get_current_tab_control()
	if page == null:
		return
	if page.name == "Loadouts" and combat:
		(_slot_buttons[combat.loadout_index][0] as Button).grab_focus()
		return
	if page.name == "SyncAIDa" and _focus_paired():
		return
	if page == _spells_tab:
		_spells_tab.focus_default()
		return
	if page == _armor_tab:
		_armor_tab.focus_default()
		return
	var first := page if page.focus_mode == Control.FOCUS_ALL else _first_focusable(page)
	if first:
		first.grab_focus()
	else:
		get_viewport().gui_release_focus()


func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		var c := child as Control
		if c and c.is_visible_in_tree() and c.focus_mode == Control.FOCUS_ALL \
				and not (c is BaseButton and (c as BaseButton).disabled):
			return c
		var inner := _first_focusable(child)
		if inner:
			return inner
	return null


func _focus_paired() -> bool:
	var seeker := _player()
	if seeker == null or seeker.save == null:
		return false
	if seeker.save.syncaida.is_empty():
		if _sync_starters.get_child_count() > 0:
			(_sync_starters.get_child(0) as Button).grab_focus()
			return true
		return false
	for child in _sync_owned.get_children():
		if child is Button and not child.is_queued_for_deletion() \
				and child.get_index() == seeker.save.paired:
			(child as Button).grab_focus()
			return true
	return false


func _set_free_feeding(on: bool) -> void:
	free_feeding = on
	if _free_feeding_toggle:
		_free_feeding_toggle.set_pressed_no_signal(on)
	if _free_feeding_levels:
		_free_feeding_levels.set_pressed_no_signal(on)
	_refresh_syncaida()


# --- Levels tab (prototype) -------------------------------------------------------

func _build_levels_tab() -> void:
	var columns := HBoxContainer.new()
	columns.name = "Levels"
	columns.add_theme_constant_override("separation", 40)
	_tabs.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 480.0
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	left.add_child(_label("Level select (prototype)", 22))
	for level in LEVELS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 38.0
		b.set_meta("scene", level[1])
		b.set_meta("title", level[0])
		b.pressed.connect(_on_level.bind(level[1]))
		left.add_child(b)
		_level_buttons.append(b)
	left.add_child(_label("Switching saves first. Carried Lumidium is banked on the way.", 13))
	_level_message = _label("", 16)
	_level_message.modulate = Color(1.0, 0.85, 0.5)
	left.add_child(_level_message)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 420.0
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	right.add_child(_label("Testing tools", 22))
	for spec in [["Refill HP, LP and Sync gauge", _tool_refill], ["Clear statuses", _tool_cure],
			["+1000 Oro", _tool_oro], ["+5 of each consumable", _tool_items],
			["+10 of each material", _tool_materials],
			["One of every armor piece, 3 of every augment", _tool_armor],
			["+10 of each Lumidium (banked)", _tool_lumidium], ["Respawn at start", _tool_respawn],
			["Change job (debug; fixed at creation)", _tool_cycle_job],
			["Learn every spell or trap your race can use, at your max level", _tool_learn_all],
			["Learn every spell or trap your race can use, at level 1", _tool_learn_all_level_1],
			["Forget every spell and trap", _tool_forget_all],
			["+50 SOL and +50 DEX (until you leave the level)", _tool_stats_up]]:
		var b := Button.new()
		b.text = spec[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(spec[1])
		right.add_child(b)
	_infinite_lp = CheckButton.new()
	_infinite_lp.text = "Infinite LP (until you leave the level)"
	_infinite_lp.toggled.connect(_toggle_infinite_lp)
	right.add_child(_infinite_lp)
	# Learn one spell or trap at any level, ignoring requirements (testing).
	var learn_row := HBoxContainer.new()
	_learn_pick = OptionButton.new()
	for spell in SpellBook.all():
		_learn_pick.add_item("%s (%s)" % [spell.display_name, spell.element_name()])
	learn_row.add_child(_learn_pick)
	var minus := Button.new()
	minus.text = " - "
	minus.pressed.connect(func(): _set_learn_level(_learn_level - 1))
	learn_row.add_child(minus)
	_learn_level_label = _label("Lv 1", 16)
	learn_row.add_child(_learn_level_label)
	var plus := Button.new()
	plus.text = " + "
	plus.pressed.connect(func(): _set_learn_level(_learn_level + 1))
	learn_row.add_child(plus)
	var learn := Button.new()
	learn.text = "Learn"
	learn.pressed.connect(_tool_learn_one)
	learn_row.add_child(learn)
	right.add_child(learn_row)
	_debug_toggle = CheckButton.new()
	_debug_toggle.text = "Debug readout (Select / F3)"
	_debug_toggle.toggled.connect(func(on: bool):
		var hud := _hud()
		if hud:
			hud.set_debug_visible(on))
	right.add_child(_debug_toggle)
	_hitbox_toggle = CheckButton.new()
	_hitbox_toggle.text = "Show hitboxes (yours and enemies')"
	_hitbox_toggle.toggled.connect(func(on: bool):
		if combat:
			combat.show_hitboxes = on)
	right.add_child(_hitbox_toggle)
	_free_feeding_levels = CheckButton.new()
	_free_feeding_levels.text = "Free SyncAIDa feeding"
	_free_feeding_levels.toggled.connect(_set_free_feeding)
	right.add_child(_free_feeding_levels)


func _hud() -> DebugHud:
	for node in get_tree().get_nodes_in_group("hud"):
		return node as DebugHud
	return null


func _refresh_levels() -> void:
	if _debug_toggle == null:
		return
	if _infinite_lp and _player():
		_infinite_lp.set_pressed_no_signal(_player().combat.infinite_lp)
	var current := get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	for b in _level_buttons:
		var here: bool = b.get_meta("scene") == current
		b.text = ("> " if here else "   ") + String(b.get_meta("title")) + ("  (here)" if here else "")
	_free_feeding_levels.set_pressed_no_signal(free_feeding)
	var hud := _hud()
	_debug_toggle.set_pressed_no_signal(hud != null and hud.is_debug_visible())
	_hitbox_toggle.set_pressed_no_signal(combat != null and combat.show_hitboxes)


func _on_level(scene: String) -> void:
	var seeker := _player()
	if seeker:
		seeker.deposit_lumidium()
		seeker.save_game()
	save_on_close = false  # already saved
	close()
	get_tree().change_scene_to_file(scene)


func _tool_refill() -> void:
	var seeker := _player()
	seeker.health.restore_full()
	combat.lp = combat.stats.max_lp
	if seeker.syncaida.data:
		seeker.syncaida.data.gauge = SyncAIDaCompanion.GAUGE_MAX
	_level_message.text = "HP, LP and Sync gauge refilled."


func _tool_cure() -> void:
	_player().status.clear_all()
	_level_message.text = "Statuses cleared."


func _tool_oro() -> void:
	_player().save.inventory.oro += 1000
	_level_message.text = "+1000 Oro."


func _tool_items() -> void:
	for id in Inventory.CONSUMABLES:
		_player().save.inventory.add_consumable(id, 5)
	_level_message.text = "+5 of each consumable."


func _tool_armor() -> void:
	var inv := _player().save.inventory
	for id in ArmorBook.all():
		inv.armors.append(ArmorBook.make(id))
	for id in UnitBook.ids():
		inv.add_unit(id, 3)
	_level_message.text = "Added %d armor pieces (max slots) and 3 of each augment (Armor tab)." % ArmorBook.all().size()
	_refresh()


func _tool_materials() -> void:
	for id in Materials.ALL:
		_player().save.inventory.add_consumable(id, 10)
	_level_message.text = "+10 of each material (use them in the Character tab)."


func _tool_lumidium() -> void:
	var inv := _player().save.inventory
	for color in Inventory.LUMIDIUM:
		inv.lumidium[color] = int(inv.lumidium.get(color, 0)) + 10
	_level_message.text = "+10 of each Lumidium in the bank."


func _tool_respawn() -> void:
	get_tree().call_group("respawner", "respawn_player")
	_level_message.text = "Back at the start."


# --- Controls tab -------------------------------------------------------------------

func _build_controls_tab() -> void:
	var help := _label(DebugHud.HELP, 18)
	help.name = "Controls"
	_tabs.add_child(help)


# --- Testing helpers (Loadouts, SyncAIDa and Character tabs) ------------------

func _tab_name() -> String:
	var page := _tabs.get_current_tab_control()
	return String(page.name) if page else ""


## 1 = clear the focused hand (gamepad X / Delete), 2 = clear the whole
## loadout (gamepad Y / Shift+Delete), 0 = neither.
func _clear_input(event: InputEvent) -> int:
	var pad := event as InputEventJoypadButton
	if pad and pad.pressed:
		if pad.button_index == JOY_BUTTON_X:
			return 1
		if pad.button_index == JOY_BUTTON_Y:
			return 2
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_DELETE:
		return 2 if key.shift_pressed else 1
	return 0


func _clear_focused_slot(whole: bool) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	for i in _slot_buttons.size():
		for hand in 2:
			if _slot_buttons[i][hand] != focus:
				continue
			var l := _set.loadouts[i]
			if whole:
				l.left = null
				l.right = null
				_message.text = "Loadout %d cleared." % (i + 1)
			else:
				var two := l.two_handed_weapon()
				if two:
					l.left = null
					l.right = null  # a two-handed weapon fills both hands
				else:
					l.set_hand(hand, null)
				_message.text = "Loadout %d, %s hand unequipped." % [i + 1, "left" if hand == 0 else "right"]
			_refresh()
			return


func _clear_all_loadouts() -> void:
	for l in _set.loadouts:
		l.left = null
		l.right = null
	_refresh()
	_message.text = "All loadouts cleared (equip something before closing to fight)."


func _reset_syncaida() -> void:
	var seeker := _player()
	if seeker == null or seeker.syncaida.data == null:
		return
	seeker.syncaida.reset_to_base()
	_sync_message.text = "%s reset to its base stats." % seeker.syncaida.data.display_name
	_refresh_syncaida()


func _reset_character() -> void:
	var seeker := _player()
	if seeker == null or seeker.save == null:
		return
	seeker.save.character.experience = 0
	seeker.reset_materials()
	seeker.health.restore_full()
	combat.lp = combat.stats.max_lp
	_refresh_character()
	_character_message.text = "Back to level 1 (EXP 0). Materials used are forgotten too. Character levels aren't in yet."


# --- Spell testing tools (Levels tab) ------------------------------------------

func _set_learn_level(level: int) -> void:
	var spell: SpellDef = SpellBook.all()[maxi(_learn_pick.selected, 0)]
	_learn_level = clampi(level, 1, spell.max_level)
	_learn_level_label.text = "Lv %d" % _learn_level


func _tool_learn_one() -> void:
	var spell: SpellDef = SpellBook.all()[maxi(_learn_pick.selected, 0)]
	_set_learn_level(_learn_level)
	_player().save.character.spells[spell.id] = _learn_level
	SpellCaster.clear_cache()
	_level_message.text = "Learned %s %d (requirements ignored for testing)." % [spell.display_name, _learn_level]
	if not _player().save.character.can_use_traps() and spell.is_trap() \
			or _player().save.character.can_use_traps() and not spell.is_trap():
		_level_message.text += " Your race can't use it, though."
	_refresh()


func _tool_learn_all() -> void:
	var c := _player().save.character
	var n := 0
	for spell in SpellBook.all():
		var cap := c.level_cap_for(spell)
		if cap > 0:
			c.spells[spell.id] = cap
			n += 1
	SpellCaster.clear_cache()
	_level_message.text = "Learned %d at your max level (%s)." % [n, c.spell_cap_text()]
	_refresh()


func _tool_learn_all_level_1() -> void:
	var c := _player().save.character
	var n := 0
	for spell in SpellBook.all():
		if c.level_cap_for(spell) > 0:
			c.spells[spell.id] = 1
			n += 1
	SpellCaster.clear_cache()
	_level_message.text = "Learned %d at level 1 (requirements ignored)." % n
	_refresh()


func _toggle_infinite_lp(on: bool) -> void:
	_player().combat.infinite_lp = on
	_level_message.text = "Infinite LP %s." % ("on" if on else "off")


func _tool_forget_all() -> void:
	_player().save.character.spells.clear()
	SpellCaster.clear_cache()
	_level_message.text = "Every spell and trap forgotten."
	_refresh()


func _tool_stats_up() -> void:
	combat.stats.soul += 50.0
	combat.stats.dexterity += 50.0
	_level_message.text = "SOL %d, DEX %d (resets when the level reloads)." % [roundi(combat.stats.soul), roundi(combat.stats.dexterity)]
	_refresh()
