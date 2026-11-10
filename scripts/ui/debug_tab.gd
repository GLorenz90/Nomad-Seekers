class_name DebugTab
extends ScrollContainer
## Menu tab (Part 9): every testing tool in one place, so it can be removed
## cleanly later (Grayson, 2026-11-09). To remove it: delete this file and
## the one line in LoadoutMenu._build that adds it. Nothing else calls into it
## except the tests.
##
## Character edits (name, race, gender, hand, job), level select, refills and
## grants, spell tools, pack and feeding switches, resets.

const LEVELS := [
	["Nomad-2 (hub)", "res://scenes/hub.tscn"],
	["Test room", "res://scenes/main.tscn"],
	["Arena (wave rooms, Lumidium)", "res://scenes/arena.tscn"],
]

var menu: LoadoutMenu
var _name_edit: LineEdit
var _race: OptionButton
var _gender: OptionButton
var _hand: OptionButton
var _job_label: Label
var _character_message: Label
var _message: Label
var _level_buttons: Array[Button] = []
var _infinite_lp: CheckButton
var _debug_toggle: CheckButton
var _hitbox_toggle: CheckButton
var _free_feeding: CheckButton
var _unlimited: CheckButton
var _learn_pick: OptionButton
var _learn_level := 1
var _learn_level_label: Label
var _weapon_pick: OptionButton
var _weapon_list: Array[WeaponData] = []


func _init(owner_menu: LoadoutMenu) -> void:
	menu = owner_menu
	name = "Debug"
	custom_minimum_size = Vector2(1130.0, 640.0)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true


func _ready() -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	add_child(columns)
	_build_character(_column(columns, 340.0))
	_build_levels(_column(columns, 330.0))
	_build_tools(_column(columns, 400.0))


func _column(parent: Node, width: float) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.custom_minimum_size.x = width
	c.add_theme_constant_override("separation", 6)
	parent.add_child(c)
	return c


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _check(parent: Node, text: String, callback: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.toggled.connect(callback)
	parent.add_child(c)
	return c


func _player() -> Player:
	return menu.combat.get_parent() as Player if menu and menu.combat else null


func _combat() -> CombatController:
	return menu.combat


# --- Character ----------------------------------------------------------------------

func _build_character(box: VBoxContainer) -> void:
	box.add_child(_label("Character (testing)", 20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	grid.add_child(_label("Name", 16))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 200.0
	# Typing needs a keyboard: click to edit. Gamepads use "New name".
	_name_edit.focus_mode = Control.FOCUS_CLICK
	_name_edit.text_changed.connect(func(_t: String): _apply_character())
	grid.add_child(_name_edit)
	grid.add_child(_label("", 16))
	_button(grid, "New name", func():
		var i := (CharacterData.NAMES.find(_name_edit.text) + 1) % CharacterData.NAMES.size()
		_name_edit.text = CharacterData.NAMES[i]
		_apply_character())
	_race = _option(grid, "Race", CharacterData.Race.keys())
	_gender = _option(grid, "Gender", CharacterData.Gender.keys())
	_hand = _option(grid, "Primary hand", ["Right", "Left"])
	_job_label = _label("", 16)
	box.add_child(_job_label)
	_button(box, "Change job (fixed at creation)", _tool_cycle_job)
	_button(box, "Reset character to level 1", _reset_character)
	_button(box, "Reset SyncAIDa to base stats", _reset_syncaida)
	_button(box, "Clear all palettes", _clear_all_loadouts)
	_character_message = _label("", 15)
	_character_message.modulate = Color(1.0, 0.85, 0.5)
	_character_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_character_message.custom_minimum_size.x = 330.0
	box.add_child(_character_message)


func _option(parent: Node, caption: String, names: Array) -> OptionButton:
	parent.add_child(_label(caption, 16))
	var option := OptionButton.new()
	for n in names:
		option.add_item(String(n).capitalize())
	option.item_selected.connect(func(_i: int): _apply_character())
	parent.add_child(option)
	return option


func load_character() -> void:
	var seeker := _player()
	if seeker == null or seeker.save == null or _name_edit == null:
		return
	var c := seeker.save.character
	_name_edit.text = c.seeker_name
	_race.select(c.race)
	_gender.select(c.gender)
	_hand.select(1 if c.left_handed else 0)


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
	c.left_handed = _hand.selected == 1
	seeker.combat.set_left_handed(c.left_handed)
	var removed := ArmorBook.strip_unwearable(seeker.save)
	if not removed.is_empty():
		_character_message.text = "Took off %s (can't wear it now)." % ", ".join(removed)
	seeker.apply_bonuses()  # race stat bonuses, armor
	refresh()


func _tool_cycle_job() -> void:
	var seeker := _player()
	var c := seeker.save.character
	c.job = ((c.job + 1) % CharacterData.Job.size()) as CharacterData.Job
	if not CharacterData.job_allowed(c.race, c.job):  # Goluman skip Invoker
		c.job = ((c.job + 1) % CharacterData.Job.size()) as CharacterData.Job
	_combat().job_code = c.job_code()
	ArmorBook.strip_unwearable(seeker.save)
	seeker.apply_bonuses()
	menu._refresh()
	_message.text = "Job is now %s (emblem %s)." % [c.job_name(), c.emblem_name()]


func _reset_character() -> void:
	var seeker := _player()
	if seeker == null or seeker.save == null:
		return
	seeker.save.character.experience = 0
	seeker.reset_materials()
	seeker.health.restore_full()
	_combat().lp = _combat().stats.max_lp
	menu._refresh()
	ArmorBook.strip_unwearable(seeker.save)
	seeker.apply_bonuses()
	seeker.health.restore_full()
	_character_message.text = "Back to level 1 (EXP 0). Materials used are forgotten too; armor above level 1 came off."


func _reset_syncaida() -> void:
	var seeker := _player()
	if seeker == null or seeker.syncaida.data == null:
		return
	seeker.syncaida.reset_to_base()
	_character_message.text = "%s reset to its base stats." % seeker.syncaida.data.display_name
	menu._refresh()


func _clear_all_loadouts() -> void:
	for l in menu._set.loadouts:
		l.off_hand = null
		l.primary = null
	menu._refresh()
	_character_message.text = "All palettes cleared (equip something before closing to fight)."


# --- Levels and switches ---------------------------------------------------------------

func _build_levels(box: VBoxContainer) -> void:
	box.add_child(_label("Level select", 20))
	for level in LEVELS:
		var b := _button(box, String(level[0]), _on_level.bind(level[1]))
		b.set_meta("scene", level[1])
		b.set_meta("title", level[0])
		_level_buttons.append(b)
	box.add_child(_label("Switching saves first; carried Lumidium is banked.", 13))
	box.add_child(_label("Switches", 20))
	_infinite_lp = _check(box, "Infinite LP", _toggle_infinite_lp)
	_unlimited = _check(box, "No pack limit", func(on: bool):
		Inventory.unlimited = on
		menu._refresh())
	_free_feeding = _check(box, "Free SyncAIDa feeding", menu._set_free_feeding)
	_debug_toggle = _check(box, "Debug readout (Select / F3)", func(on: bool):
		var hud := menu._hud()
		if hud:
			hud.set_debug_visible(on))
	_hitbox_toggle = _check(box, "Show hitboxes", func(on: bool):
		if _combat():
			_combat().show_hitboxes = on)
	_message = _label("", 15)
	_message.modulate = Color(1.0, 0.85, 0.5)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 320.0
	box.add_child(_message)


func _on_level(scene: String) -> void:
	var seeker := _player()
	if seeker:
		seeker.save_game()
	menu.save_on_close = false  # already saved
	menu.close()
	if seeker:
		CoopDirector.travel(seeker, scene)
	else:
		get_tree().change_scene_to_file(scene)


func _toggle_infinite_lp(on: bool) -> void:
	_player().combat.infinite_lp = on
	_message.text = "Infinite LP %s (until you leave the level)." % ("on" if on else "off")


# --- Tools ---------------------------------------------------------------------------

func _build_tools(box: VBoxContainer) -> void:
	box.add_child(_label("Testing tools", 20))
	var level_row := HBoxContainer.new()
	level_row.add_child(_label("Level: ", 16))
	for step in [1, 10, 50]:
		_button(level_row, "+%d" % step, _tool_levels.bind(step))
	_button(level_row, "Max (200)", _tool_levels.bind(Leveling.MAX_LEVEL))
	box.add_child(level_row)
	for spec in [["Refill HP, LP and Sync gauge", _tool_refill], ["Clear statuses", _tool_cure],
			["+1000 Oro", _tool_oro], ["Fill your consumable stacks", _tool_items],
			["+10 of each material", _tool_materials],
			["One of every armor piece, 3 of every augment", _tool_armor],
			["+10 of each Lumidium (banked)", _tool_lumidium], ["Fill the satchel with Lumidium", _tool_satchel],
			["Respawn at start", _tool_respawn],
			["Learn every usable spell at your max level", _tool_learn_all],
			["Learn every usable spell at level 1", _tool_learn_all_level_1],
			["Forget every spell and trap", _tool_forget_all],
			["+50 SOL and DEX (this level only)", _tool_stats_up]]:
		_button(box, spec[0], spec[1])
	# Learn one spell or trap at any level, ignoring requirements.
	var learn_row := HBoxContainer.new()
	_learn_pick = OptionButton.new()
	_learn_pick.custom_minimum_size.x = 200.0
	for spell in SpellBook.all():
		_learn_pick.add_item("%s (%s)" % [spell.display_name, spell.element_name()])
	learn_row.add_child(_learn_pick)
	_button(learn_row, " - ", func(): _set_learn_level(_learn_level - 1))
	_learn_level_label = _label("Lv 1", 16)
	learn_row.add_child(_learn_level_label)
	_button(learn_row, " + ", func(): _set_learn_level(_learn_level + 1))
	_button(learn_row, "Learn", _tool_learn_one)
	box.add_child(learn_row)
	# Any weapon into the pack (palettes only take weapons from the pack).
	var weapon_row := HBoxContainer.new()
	_weapon_pick = OptionButton.new()
	_weapon_pick.custom_minimum_size.x = 260.0
	_weapon_list.assign(Loot.base_weapons() + Loot.rare_weapons())
	for w in _weapon_list:
		_weapon_pick.add_item(("%s (rare)" % w.display_name) if w.rare else w.display_name)
	weapon_row.add_child(_weapon_pick)
	_button(weapon_row, "Add to pack", _tool_add_weapon)
	box.add_child(weapon_row)


## Levels up through EXP, so the level-up shows like a real one.
func _tool_levels(count: int) -> void:
	var seeker := _player()
	var c := seeker.save.character
	var target := mini(c.level() + count, Leveling.MAX_LEVEL)
	seeker.gain_exp(Leveling.exp_for(target) - c.experience)
	_message.text = "Level %d." % c.level()
	menu._refresh()


func _tool_refill() -> void:
	var seeker := _player()
	seeker.health.restore_full()
	_combat().lp = _combat().stats.max_lp
	if seeker.syncaida.data:
		seeker.syncaida.data.gauge = SyncAIDaCompanion.GAUGE_MAX
	_message.text = "HP, LP and Sync gauge refilled."


func _tool_cure() -> void:
	_player().status.clear_all()
	_message.text = "Statuses cleared."


func _tool_oro() -> void:
	_player().save.inventory.add_oro(1000)
	_message.text = "+1000 Oro."
	menu._refresh()


func _tool_items() -> void:
	var save := _player().save
	var added := 0
	for id in Inventory.CONSUMABLES:
		added += save.take_stack(id, Inventory.STACK_MAX)
	_message.text = "+%d consumables (stacks of %d)%s." % [added, Inventory.STACK_MAX, _full_note()]
	menu._refresh()


func _tool_materials() -> void:
	var save := _player().save
	var added := 0
	for id in Materials.ALL:
		added += save.take_stack(id, 10)
	_message.text = "+%d materials (use them from the Inventory)%s." % [added, _full_note()]
	menu._refresh()


func _tool_armor() -> void:
	var save := _player().save
	var pieces := 0
	for id in ArmorBook.all():
		if save.take_armor(ArmorBook.make(id)):
			pieces += 1
	var units := 0
	for id in UnitBook.ids():
		for i in 3:
			if save.take_unit(id):
				units += 1
	_message.text = "Added %d armor pieces and %d augments%s." % [pieces, units, _full_note()]
	menu._refresh()


func _full_note() -> String:
	return "" if _player().save.pack_free() > 0 else " (pack full: turn on No pack limit for more)"


func _tool_lumidium() -> void:
	var inv := _player().save.inventory
	for color in Inventory.LUMIDIUM:
		inv.lumidium[color] = int(inv.lumidium.get(color, 0)) + 10
	_message.text = "+10 of each Lumidium in the bank."
	menu._refresh()


func _tool_satchel() -> void:
	var seeker := _player()
	var colors := Inventory.LUMIDIUM
	var i := 0
	while seeker.satchel_room() > 0:
		seeker.add_lumidium(colors[i % colors.size()])
		i += 1
	_message.text = "Satchel full: %d Lumidium carried." % seeker.carried_lumidium_total()
	menu._refresh()


func _tool_respawn() -> void:
	var level := Scope.level(menu._player())
	if level:
		level.call("respawn_player", menu._player())
	_message.text = "Back at the start."


func _tool_add_weapon() -> void:
	var w: WeaponData = _weapon_list[maxi(_weapon_pick.selected, 0)].duplicate()
	if _player().save.take_weapon(w):
		_message.text = "%s added to your pack." % w.display_name
	else:
		_message.text = "Your pack is full."
	menu._refresh()


func _set_learn_level(level: int) -> void:
	var spell: SpellDef = SpellBook.all()[maxi(_learn_pick.selected, 0)]
	_learn_level = clampi(level, 1, spell.max_level)
	_learn_level_label.text = "Lv %d" % _learn_level


func _tool_learn_one() -> void:
	var spell: SpellDef = SpellBook.all()[maxi(_learn_pick.selected, 0)]
	_set_learn_level(_learn_level)
	var c := _player().save.character
	c.spells[spell.id] = _learn_level
	SpellCaster.clear_cache()
	_message.text = "Learned %s %d (requirements ignored)." % [spell.display_name, _learn_level]
	if c.can_use_traps() != spell.is_trap():
		_message.text += " Your race can't use it, though."
	menu._refresh()


func _tool_learn_all() -> void:
	var c := _player().save.character
	var n := 0
	for spell in SpellBook.all():
		var cap := c.level_cap_for(spell)
		if cap > 0:
			c.spells[spell.id] = cap
			n += 1
	SpellCaster.clear_cache()
	_message.text = "Learned %d at your max level (%s)." % [n, c.spell_cap_text()]
	menu._refresh()


func _tool_learn_all_level_1() -> void:
	var c := _player().save.character
	var n := 0
	for spell in SpellBook.all():
		if c.level_cap_for(spell) > 0:
			c.spells[spell.id] = 1
			n += 1
	SpellCaster.clear_cache()
	_message.text = "Learned %d at level 1 (requirements ignored)." % n
	menu._refresh()


func _tool_forget_all() -> void:
	_player().save.character.spells.clear()
	SpellCaster.clear_cache()
	_message.text = "Every spell and trap forgotten."
	menu._refresh()


func _tool_stats_up() -> void:
	_combat().stats.soul += 50.0
	_combat().stats.dexterity += 50.0
	_message.text = "SOL %d, DEX %d (resets when the level reloads)." % [roundi(_combat().stats.soul), roundi(_combat().stats.dexterity)]
	menu._refresh()


# --- Refresh ---------------------------------------------------------------------------

func refresh() -> void:
	var seeker := _player()
	if _job_label == null or seeker == null or seeker.save == null:
		return
	var c := seeker.save.character
	_job_label.text = "Job: %s   Emblem: %s" % [c.job_name(), c.emblem_name()]
	_infinite_lp.set_pressed_no_signal(seeker.combat.infinite_lp)
	_unlimited.set_pressed_no_signal(Inventory.unlimited)
	_free_feeding.set_pressed_no_signal(menu.free_feeding)
	var hud := menu._hud()
	_debug_toggle.set_pressed_no_signal(hud != null and hud.is_debug_visible())
	_hitbox_toggle.set_pressed_no_signal(_combat() != null and _combat().show_hitboxes)
	var level := Scope.level(seeker) if seeker else null
	var current := level.scene_file_path if level else ""
	for b in _level_buttons:
		var here: bool = b.get_meta("scene") == current
		b.text = ("> " if here else "   ") + String(b.get_meta("title")) + ("  (here)" if here else "")
