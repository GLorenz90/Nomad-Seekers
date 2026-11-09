class_name LoadoutMenu
extends CanvasLayer
## The pause menu (Start / Tab). Pauses the game while open. (Named for its
## first job, editing loadouts; it holds every tab now.)
##
## Tabs (Part 9, Grayson 2026-11-09: PSO's menus with PSU's palettes), LB / RB
## switch:
## - Inventory (InventoryTab): the 30-slot pack and the satchel; equip, wear,
##   use, read and drop from here.
## - Equip (EquipTab): Palette (the 8 PSU-style palettes, built here), Spells
##   (SpellsTab) and Armor (ArmorTab); LT / RT switch sections.
## - Status: the character and their stats.
## - SyncAIDa: pair one, feed it, pick its Sync Burst.
## - Options: controls, save and quit to the title screen.
## - Debug (DebugTab): every testing tool, removable in one line.
##
## Closing saves everything (SaveData). Fully usable by gamepad: d-pad / left
## stick move focus, A accepts, B goes back (or closes), Start closes. Every
## tab switch moves focus into the new tab, and rebuilt lists put focus back on
## a real control.

signal closed


var combat: CombatController
## Tests turn this off so they never overwrite the player's saved loadouts.
var save_on_close := true

var _set: LoadoutSet
var _slot_buttons: Array = []  # [[off-hand Button, primary Button], ...] (indexed by Hand)
var _slot_status: Array[Label] = []
var _picker: VBoxContainer
var _picker_title: Label
var _picker_list: VBoxContainer
var _message: Label
var _augment: Label
var _editing := Vector2i(-1, -1)  # (loadout index, hand)
var _root: Control
var _tabs: TabContainer
var _sync_owned: VBoxContainer
var _inventory_tab: InventoryTab
var _equip_tab: EquipTab
var _spells_tab: SpellsTab
var _armor_tab: ArmorTab
var debug_tab: DebugTab
var _status_text: RichTextLabel
var _sync_starter_title: Label
var _sync_starters: VBoxContainer
var _sync_info: Label
## Per-stat rows: stat -> [level Label, ProgressBar, percent Label].
var _sync_stat_rows := {}
var _sync_feeds: GridContainer
var _sync_burst: OptionButton
var _sync_message: Label
## Debug: feeding doesn't use up items (for trying evolutions quickly).
var free_feeding := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	visible = false


func setup(controller: CombatController) -> void:
	combat = controller


func is_open() -> bool:
	return visible


func open() -> void:
	if combat == null or not get_tree().get_nodes_in_group("modal_menus").is_empty():
		return  # a counter or the teleporter's list is open
	_set = combat.loadout_set
	_rebuild_picker()
	if debug_tab:
		debug_tab.load_character()
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
	if seeker:
		seeker.hold_input()  # the B / Start that closed the menu mustn't dash
	if save_on_close and seeker:
		seeker.save_game()
	closed.emit()


func _player() -> Player:
	return combat.get_parent() as Player if combat else null


## Gamepad safety net: a press with nothing in the menu focused refocuses the
## current tab instead of being lost (see MenuFocus).
func _input(event: InputEvent) -> void:
	if visible:
		MenuFocus.recover(self, event, _focus_tab)


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
	elif visible and _tabs.get_current_tab_control() == _equip_tab and (event.is_action_pressed("block") or event.is_action_pressed("shift")):
		_close_picker()
		_equip_tab.step_section(1 if event.is_action_pressed("shift") else -1)
		get_viewport().set_input_as_handled()
	elif visible and _tab_name() == "Inventory" and event.is_action_pressed("ui_cancel") and _inventory_tab.back():
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
	elif visible and _tab_name() == "Palette" and not _picker.visible and _clear_input(event) != 0:
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
		# A two-handed weapon is one item, held in the primary hand.
		l.primary = weapon
		l.off_hand = null
		return l.validate(_set.double_heavy_augment)
	l.set_hand(hand, weapon)
	var other := l.get_hand(1 - hand)
	if other and other.two_handed and weapon != null:
		l.set_hand(1 - hand, null)
	return l.validate(_set.double_heavy_augment)


func _on_slot_pressed(index: int, hand: int) -> void:
	_editing = Vector2i(index, hand)
	_rebuild_picker()
	_picker_title.text = "Palette %d, %s (%s)" % [
		index + 1, CombatController.hand_name(hand).to_lower(), combat.button_for(hand)]
	_picker.visible = true
	(_picker_list.get_child(0) as Button).grab_focus()


func _on_weapon_picked(weapon: WeaponData) -> void:
	if weapon and combat and not weapon.can_be_used_by(combat.job_code):
		_message.text = "%s needs %s." % [weapon.display_name, weapon.jobs_text()]
		return
	if weapon and combat and weapon.requirement_error(combat.stats) != "":
		_message.text = "%s: %s." % [weapon.display_name, weapon.requirement_error(combat.stats)]
		return
	var error := equip(_editing.x, _editing.y, weapon)
	if error == "":
		error = combat.job_error(_set.loadouts[_editing.x])
	var back_to: Button = _slot_buttons[_editing.x][_editing.y]
	_close_picker()
	_refresh()
	_message.text = error if error != "" else "Palette %d updated." % (_editing.x + 1)
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
		if _set.double_heavy_augment else "not worn (slot one into your armor: Equip > Armor)")
	if _inventory_tab:
		_inventory_tab.refresh()
	_refresh_status()
	_refresh_syncaida()
	if debug_tab:
		debug_tab.refresh()
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
	columns.name = "Palette"
	columns.add_theme_constant_override("separation", 24)
	_spells_tab = SpellsTab.new(self)
	_armor_tab = ArmorTab.new(self)
	_inventory_tab = InventoryTab.new(self)
	_tabs.add_child(_inventory_tab)
	_equip_tab = EquipTab.new(self, columns, _spells_tab, _armor_tab)
	_tabs.add_child(_equip_tab)
	_build_status_tab()
	_build_syncaida_tab()
	_build_options_tab()
	# Testing tools: remove this line (and debug_tab.gd) to drop the tab.
	debug_tab = DebugTab.new(self)
	_tabs.add_child(debug_tab)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 780.0
	columns.add_child(left)
	left.add_child(_label("Palettes", 24))
	left.add_child(_label("Pick a hand, then a weapon from your pack.  A/Enter: select   B/Esc: back   Start/Tab: close and save\nX/Delete: unequip that hand   Y/Shift+Delete: clear the whole palette   LB/RB: tabs   LT/RT: sections", 14))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	# Primary hand first (X), then the off hand (Y): the order players read.
	for header in ["", "Primary (X)", "Off hand (Y)", "LT"]:
		grid.add_child(_label(header, 14))
	for i in LoadoutSet.SLOT_COUNT:
		grid.add_child(_label(str(i + 1), 18))
		var pair := [null, null]  # indexed by hand
		for hand in [CombatController.Hand.PRIMARY, CombatController.Hand.OFF]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(270.0, 34.0)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(_on_slot_pressed.bind(i, hand))
			grid.add_child(b)
			pair[hand] = b
		_slot_buttons.append(pair)
		var status := _label("", 14)
		status.custom_minimum_size.x = 170.0
		grid.add_child(status)
		_slot_status.append(status)

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
	scroll.custom_minimum_size = Vector2(330.0, 520.0)
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


# --- Picker and Status tab -------------------------------------------------------

## The weapons in your pack (PSU: palettes are filled from the inventory),
## grouped like the North Star's weapon table. The one already in the other
## hand of this palette is left out (one item can't be in both hands).
## Job-locked ones stay focusable but greyed.
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
	var seeker := _player()
	if seeker == null or seeker.save == null:
		return
	var other: WeaponData = null
	if _set and _editing.x >= 0:
		other = _set.loadouts[_editing.x].get_hand(1 - _editing.y)
	var any := false
	for group in [["Melee", WeaponData.WeaponClass.MELEE, false], ["Ranged", WeaponData.WeaponClass.RANGED, false],
			["Magic", WeaponData.WeaponClass.MAGIC, false], ["Shields", -1, true]]:
		var header_added := false
		for w in seeker.save.inventory.weapons:
			if w == other or w.is_shield != group[2] or not (group[2] or w.weapon_class == group[1]):
				continue
			if not header_added:
				var header := _label(group[0], 14)
				header.modulate = Color(0.7, 0.8, 1.0)
				_picker_list.add_child(header)
				header_added = true
			_picker_list.add_child(_weapon_button(w))
			any = true
	if not any:
		_picker_list.add_child(_label("No other weapons in your pack.", 14))


func _weapon_button(w: WeaponData) -> Button:
	var b := Button.new()
	b.text = _weapon_label(w)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = Loot.describe(w)
	b.modulate = Color(1.0, 0.6, 1.0) if w.rare else Color(0.85, 0.92, 1.0)
	if combat and (not w.can_be_used_by(combat.job_code) or w.requirement_error(combat.stats) != ""):
		# Still focusable (so the d-pad doesn't skip it); A explains the lock.
		b.modulate = Color(0.55, 0.55, 0.6)
		b.set_meta("locked", true)
	b.pressed.connect(_on_weapon_picked.bind(w))
	return b


func _build_status_tab() -> void:
	_status_text = RichTextLabel.new()
	_status_text.name = "Status"
	_status_text.bbcode_enabled = true
	_status_text.custom_minimum_size = Vector2(1100.0, 600.0)
	_status_text.add_theme_font_size_override("normal_font_size", 18)
	# Focusable so the d-pad / left stick scroll it.
	_status_text.focus_mode = Control.FOCUS_ALL
	_status_text.scroll_active = true
	_tabs.add_child(_status_text)


## PSO's Status screen: who you are and your stats with everything applied.
func _refresh_status() -> void:
	var seeker := _player()
	if _status_text == null or seeker == null or seeker.save == null:
		return
	var c := seeker.save.character
	var s := combat.stats
	var favored: Array = Loot.FAVORED[c.emblem_index()]
	var rares := PackedStringArray()
	for w in Loot.rares_for(c.emblem_index()):
		rares.append(w.display_name)
	var lines := PackedStringArray()
	lines.append("[font_size=26]%s[/font_size]" % c.seeker_name)
	lines.append("[b]Level %d[/b]   EXP %d   %s" % [c.level(), c.experience,
		"next level in %d" % Leveling.to_next(c.experience) if c.level() < Leveling.MAX_LEVEL else "max level"])
	lines.append("%s %s %s   %s-handed   Emblem [color=#%s]%s[/color]" % [
		CharacterData.Race.keys()[c.race].capitalize(), CharacterData.Gender.keys()[c.gender].capitalize(),
		c.job_name(), "Left" if c.left_handed else "Right", c.emblem_text_color().to_html(false),
		c.emblem_name()])
	lines.append("")
	lines.append("[b]HP[/b] %d / %d    [b]LP[/b] %d / %d" % [roundi(seeker.health.hp), roundi(s.max_hp),
		roundi(combat.lp), roundi(s.max_lp)])
	lines.append("[b]STR[/b] %d    [b]DEX[/b] %d    [b]SOL[/b] %d    [b]ATA[/b] %d    [b]LCK[/b] %d" % [
		roundi(s.strength), roundi(s.dexterity), roundi(s.soul), roundi(s.accuracy), roundi(s.luck)])
	lines.append("[b]DEF[/b] %d    [b]RES[/b] %d    [b]EVA[/b] %d" % [roundi(s.defense), roundi(s.resolve), roundi(s.evasion)])
	lines.append("")
	lines.append("[b]Materials used[/b]  stat %s   HP %s   LP %s   (use them from the Inventory)" % [
		Materials.limit_text(c, &"stat"), Materials.limit_text(c, &"hp"), Materials.limit_text(c, &"lp")])
	lines.append("[b]Spell levels[/b]  %s" % c.spell_cap_text())
	lines.append("[b]Drops favor[/b]  %s, %s.   Rares in this pool: %s" % [String(favored[0]).capitalize(),
		String(favored[1]).capitalize(), ", ".join(rares) if not rares.is_empty() else "none"])
	lines.append("")
	lines.append("[color=#9aa8c0]The emblem comes from name, race, gender and job (like PSO section IDs). Jobs lock weapons: S = Striker, R = Ranger, I = Invoker.[/color]")
	_status_text.text = "\n".join(lines)


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
	right.add_child(_label("Consumables come from your pack,\nLumidium from the bank.", 13))
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
	if page == _inventory_tab:
		_inventory_tab.focus_default()
		return
	if page == _equip_tab:
		match _equip_tab.section:
			"Palette":
				if combat:
					(_slot_buttons[combat.loadout_index][CombatController.Hand.PRIMARY] as Button).grab_focus()
			"Spells":
				_spells_tab.focus_default()
			"Armor":
				_armor_tab.focus_default()
		return
	if page.name == "SyncAIDa" and _focus_paired():
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


## Debug tab switch: feeding doesn't use anything up.
func _set_free_feeding(on: bool) -> void:
	free_feeding = on
	_refresh_syncaida()


# --- Options tab ---------------------------------------------------------------------

func _build_options_tab() -> void:
	var columns := HBoxContainer.new()
	columns.name = "Options"
	columns.add_theme_constant_override("separation", 40)
	_tabs.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 360.0
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	left.add_child(_label("Options", 22))
	var to_title := Button.new()
	to_title.text = "Save and quit to the title screen"
	to_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	to_title.pressed.connect(_quit_to_title)
	left.add_child(to_title)
	left.add_child(_label("Carried Lumidium is banked first.", 13))
	left.add_child(_label("More settings will live here.", 13))
	var right := VBoxContainer.new()
	columns.add_child(right)
	right.add_child(_label("Controls", 22))
	right.add_child(_label(DebugHud.HELP, 16))


func _hud() -> DebugHud:
	for node in get_tree().get_nodes_in_group("hud"):
		return node as DebugHud
	return null


func _quit_to_title() -> void:
	var seeker := _player()
	if seeker:
		seeker.deposit_lumidium()
	save_on_close = false
	close()
	Session.quit_to_title()


# --- Palette helpers ----------------------------------------------------------------

## The current tab's name, or the Equip tab's section (Palette, Spells, Armor).
func _tab_name() -> String:
	var page := _tabs.get_current_tab_control()
	if page == _equip_tab:
		return _equip_tab.section
	return String(page.name) if page else ""


## Opens the menu's tab (or Equip section) by name (tests, shortcuts).
func show_tab(tab: String) -> void:
	if tab in EquipTab.SECTIONS:
		_tabs.current_tab = _tab_index("Equip")
		_equip_tab.show_section(tab)
	else:
		_tabs.current_tab = _tab_index(tab)


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
				l.off_hand = null
				l.primary = null
				_message.text = "Loadout %d cleared." % (i + 1)
			else:
				var two := l.two_handed_weapon()
				if two:
					l.off_hand = null
					l.primary = null  # a two-handed weapon fills both hands
				else:
					l.set_hand(hand, null)
				_message.text = "Loadout %d, %s unequipped." % [i + 1, CombatController.hand_name(hand).to_lower()]
			_refresh()
			return
