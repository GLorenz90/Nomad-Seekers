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
var _picker_list: VBoxContainer
var _message: Label
var _augment: CheckButton
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
var _sync_info: Label
var _sync_feeds: GridContainer
var _sync_burst: OptionButton
var _sync_message: Label
## Debug: feeding doesn't use up items (for trying evolutions quickly).
var free_feeding := false


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
	_tabs.current_tab = 0
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
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
		_refresh()
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
	_augment.set_pressed_no_signal(_set.double_heavy_augment)
	_refresh_inventory()
	_refresh_character()
	_refresh_syncaida()


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
	panel.add_child(_tabs)
	var columns := HBoxContainer.new()
	columns.name = "Loadouts"
	columns.add_theme_constant_override("separation", 24)
	_tabs.add_child(columns)
	_build_inventory_tab()
	_build_character_tab()
	_build_syncaida_tab()

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 780.0
	columns.add_child(left)
	left.add_child(_label("Loadouts", 26))
	left.add_child(_label("Pick a hand, then a weapon.  A/Enter: select   B/Esc: back   LB/RB: tabs   Start/Tab: close and save", 14))

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

	_augment = CheckButton.new()
	_augment.text = "Double-Heavy augment (two Heavy one-handed items)"
	_augment.toggled.connect(func(on: bool):
		_set.double_heavy_augment = on
		_refresh())
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
		child.free()
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
	_picker_list.add_child(_label("Base weapons", 14))
	for w in _weapons:
		_picker_list.add_child(_weapon_button(w, false))


func _weapon_button(w: WeaponData, found: bool) -> Button:
	var b := Button.new()
	b.text = _weapon_label(w)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = Loot.describe(w)
	if found:
		b.modulate = Color(1.0, 0.6, 1.0) if w.rare else Color(0.75, 0.9, 1.0)
	if combat and not w.can_be_used_by(combat.job_code):
		b.disabled = true
	b.pressed.connect(_on_weapon_picked.bind(w))
	return b


func _build_inventory_tab() -> void:
	_inventory_text = RichTextLabel.new()
	_inventory_text.name = "Inventory"
	_inventory_text.bbcode_enabled = true
	_inventory_text.custom_minimum_size = Vector2(1100.0, 600.0)
	_inventory_text.add_theme_font_size_override("normal_font_size", 17)
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
	_name_edit.text_changed.connect(func(_t: String): _apply_character())
	grid.add_child(_name_edit)
	_race = _option(grid, "Race", CharacterData.Race.keys())
	_gender = _option(grid, "Gender", CharacterData.Gender.keys())
	_job = _option(grid, "Job", CharacterData.Job.keys())
	_character_info = _label("", 18)
	box.add_child(_character_info)
	box.add_child(_label("The emblem comes from name, race and gender (PSO section IDs). It picks the weapon\nfamilies and rares your drops favor. Jobs lock weapons: S = Striker, R = Ranger, I = Invoker.", 14))


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
	c.race = _race.selected as CharacterData.Race
	c.gender = _gender.selected as CharacterData.Gender
	var job_changed := c.job != _job.selected
	c.job = _job.selected as CharacterData.Job
	if job_changed:
		combat.job_code = c.job_code()
		_rebuild_picker()
		_refresh()
	_refresh_character()


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
	_character_info.modulate = c.emblem_color().lightened(0.4)


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

	var mid := VBoxContainer.new()
	mid.custom_minimum_size.x = 420.0
	mid.add_theme_constant_override("separation", 8)
	columns.add_child(mid)
	_sync_info = _label("", 17)
	mid.add_child(_sync_info)
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
	mid.add_child(_label("Forms: Lv 10 by job, Lv 35 by strongest stat, Lv 50+ by the two strongest\n(re-checked every 5 levels). Each of those milestones unlocks a Sync Burst.", 13))

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
	var free := CheckButton.new()
	free.text = "Free feeding (debug)"
	free.toggled.connect(func(on: bool): free_feeding = on)
	right.add_child(free)
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


func _on_feed(item: StringName) -> void:
	var seeker := _player()
	if seeker == null:
		return
	var events := seeker.syncaida.feed(item, free_feeding)
	var d := seeker.syncaida.data
	if events.is_empty():
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
	for child in _sync_owned.get_children():
		child.free()
	for i in seeker.save.syncaida.size():
		var d := seeker.save.syncaida[i]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s%s  Lv %d %s" % ["> " if i == seeker.save.paired else "   ", d.display_name, d.level(), d.form]
		b.modulate = d.color().lightened(0.3)
		b.pressed.connect(func():
			seeker.pair_syncaida(i)
			_sync_message.text = "Paired with %s." % d.display_name
			_refresh_syncaida())
		_sync_owned.add_child(b)
	var d := seeker.save.paired_syncaida()
	if d == null:
		_sync_info.text = "No SyncAIDa."
		return
	var next := d.next_milestone()
	var bonus := d.bonuses()
	_sync_info.text = "%s  (%s)\nLevel %d / %d%s\n%s\nAdds to you: DEF +%d  STR +%d  DEX +%d  SOL +%d\nSync gauge %d%%" % [
		d.display_name, d.form, d.level(), SyncAIDaData.MAX_LEVEL,
		"   next evolution at %d" % next if next > 0 else "",
		d.describe_stats(), int(bonus[&"def"]), int(bonus[&"str"]), int(bonus[&"dex"]), int(bonus[&"sol"]),
		roundi(d.gauge)]
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
	var inv := seeker.save.inventory
	for child in _sync_feeds.get_children():
		if child is Button:
			var item: StringName = child.get_meta("item")
			var have := inv.count(item) if Inventory.CONSUMABLES.has(item) else int(inv.lumidium.get(item, 0))
			var label: String = Inventory.CONSUMABLES.get(item, "%s Lumidium" % String(item).capitalize())
			(child as Button).text = "%s x%d" % [label, have]
