extends SceneTree
## Automated test for Part 6: the spell book and its PSO numbers, learning
## rules (SOL curve, level caps by race and job, Goluman), casting from
## loadout slots, every spell shape against real enemies, buffs / debuffs,
## auras, Heal / leveled Cure / Teleportal, spell discs, Goluman traps and
## level hazards, and the Spells tab with a gamepad. Runs in the arena.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/magic_test.gd

const ARENA := Vector3(0.0, 0.1, 4.0)

var _main: Node
var _player: Player
var _combat: CombatController
var _menu: LoadoutMenu
var _failures := 0
var _feedback: Array[String] = []


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_combat = _player.combat
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_player.autosave = false
	_menu = _main.loadout_menu
	_menu.save_on_close = false
	_combat.stats.luck = 0.0
	_combat.combo_feedback.connect(func(t): _feedback.append(t))
	for room in ["Rooms/RoomA", "Rooms/RoomB"]:
		(_main.get_node(room) as WaveRoom).state = WaveRoom.RoomState.CLEARED
	await _frames(30)

	# --- Spell book ---------------------------------------------------------------
	var spells := SpellBook.spells_only()
	var traps := SpellBook.traps_only()
	_check("the grid: 42 element spells + 4 typeless, and 7 traps (%d / %d)" % [spells.size(), traps.size()],
		spells.size() == 46 and traps.size() == 7)
	var names := ["fajro", "mezglacio", "granfulmo", "dauarbo", "bonalumo", "malamalbo", "pasarbo", "bonarbo",
		"malarbo", "heal", "cure", "teleportal", "revive", "freeze_trap", "paralyze_trap"]
	var missing := names.filter(func(n: String) -> bool: return SpellBook.get_spell(StringName(n)) == null)
	_check("spells are named as in the grid (%s missing)" % [missing], missing.is_empty())
	var fajro := SpellBook.get_spell(&"fajro")
	_check("Fajro is PSO Foie: power 110 / 810 / 1800 at levels 1 / 15 / 30, LP 5 -> 42.7",
		fajro.power(1) == 110.0 and fajro.power(15) == 810.0 and fajro.power(30) == 1800.0
		and fajro.lp_cost(1) == 5.0 and is_equal_approx(fajro.lp_cost(30), 42.7))
	_check("Granfajro is Rafoie (979 at 30), Mezfulmo is Gizonde (398 at 10)",
		SpellBook.get_spell(&"granfajro").power(30) == 979.0 and SpellBook.get_spell(&"mezfulmo").power(10) == 398.0)
	_check("SOL needed: +20 a level to 15, +40 after (Fajro 40 / 60 / 320 / 360 / 920)",
		fajro.requirement(1) == 40 and fajro.requirement(2) == 60 and fajro.requirement(15) == 320
		and fajro.requirement(16) == 360 and fajro.requirement(30) == 920)
	var lumo := SpellBook.get_spell(&"lumo")
	_check("Lumo needs SOL 80, then 100 at level 2", lumo.requirement(1) == 80 and lumo.requirement(2) == 100)
	var cure := SpellBook.get_spell(&"cure")
	var revive := SpellBook.get_spell(&"revive")
	_check("Cure: 9 levels (8 statuses, then debuffs), +25 SOL a level (80 -> 280)",
		cure.max_level == 9 and cure.requirement(1) == 80 and cure.requirement(9) == 280)
	_check("Revive: 10 levels, +30 SOL then +60 (150 / 270 / 330 / 570); Teleportal has 1",
		revive.max_level == 10 and revive.requirement(5) == 270 and revive.requirement(6) == 330
		and revive.requirement(10) == 570 and SpellBook.get_spell(&"teleportal").max_level == 1)
	_check("single-target spells can't inflict status; other damage spells can",
		not fajro.status_ok and not lumo.status_ok and SpellBook.get_spell(&"mezfajro").status_ok
		and not SpellBook.get_spell(&"pasfajro").status_ok and SpellBook.get_spell(&"pasmalbo").status_ok)

	# --- Level caps ----------------------------------------------------------------
	var c := CharacterData.new()
	var bona := SpellBook.get_spell(&"bonafajro")
	var mala := SpellBook.get_spell(&"malafajro")
	var R := CharacterData.Race
	var J := CharacterData.Job
	# [race, job] -> [ordinary, buff, debuff]
	var expect := [
		[R.HUMAN, J.STRIKER, [15, 10, 15]], [R.HUMAN, J.RANGER, [15, 15, 10]], [R.HUMAN, J.INVOKER, [30, 30, 30]],
		[R.LUMERA, J.STRIKER, [20, 15, 20]], [R.LUMERA, J.RANGER, [20, 20, 15]], [R.LUMERA, J.INVOKER, [30, 30, 30]],
		[R.CORESIAN, J.STRIKER, [10, 5, 10]], [R.CORESIAN, J.RANGER, [10, 10, 5]], [R.CORESIAN, J.INVOKER, [30, 30, 30]],
	]
	var cap_wrong := []
	for e in expect:
		c.race = e[0]
		c.job = e[1]
		var got := [c.level_cap_for(fajro), c.level_cap_for(bona), c.level_cap_for(mala)]
		if got != e[2]:
			cap_wrong.append("%s %s %s" % [c.race_name(), c.job_name(), got])
	_check("spell caps: 15, Lumera +5, Coresian -5, Invokers 30; Strikers -5 on buffs, Rangers -5 on debuffs (%s)" % [cap_wrong],
		cap_wrong.is_empty())
	c.race = R.CORESIAN
	c.job = J.STRIKER
	_check("Cure, Revive and Teleportal always reach their own max (9 / 10 / 1)",
		c.level_cap_for(cure) == 9 and c.level_cap_for(revive) == 10 and c.level_cap_for(SpellBook.get_spell(&"teleportal")) == 1)
	c.race = R.GOLUMAN
	c.job = J.RANGER
	_check("Goluman can't learn spells, only traps (to level 15)",
		c.level_cap_for(fajro) == 0 and c.level_cap_for(traps[0]) == 15 and c.learn_error(fajro, 1, 999) != "")
	_check("Goluman can't be Invokers", not CharacterData.job_allowed(R.GOLUMAN, J.INVOKER)
		and CharacterData.job_allowed(R.LUMERA, J.INVOKER))
	_check("Goluman get +10 DEX and HP regen; others don't",
		c.race_bonuses().get(&"dexterity", 0.0) == 10.0 and c.hp_regen_fraction() > 0.0)
	c.race = R.HUMAN
	_check("humans get neither", c.race_bonuses().is_empty() and c.hp_regen_fraction() == 0.0)
	c.race = CharacterData.Race.HUMAN
	_check("learning checks SOL (Lumo 1 at SOL 79: %s)" % c.learn_error(lumo, 1, 79), c.learn_error(lumo, 1, 79).begins_with("Needs 80"))

	# --- Casting from loadout slots --------------------------------------------------
	var save := _player.save
	_check("a new Seeker knows Fajro, Glacio and Fulmo at level 1, and the Wand holds Fajro / Glacio",
		save.character.spell_level(&"fajro") == 1 and save.character.spell_level(&"fulmo") == 1
		and save.loadouts.loadouts[4].get_spell(0, 0) == &"fajro" and save.loadouts.loadouts[4].get_spell(0, 1) == &"glacio")
	_combat.set_job("I")
	save.character.job = CharacterData.Job.INVOKER
	_equip(null, load("res://data/weapons/staff.tres"))
	_feedback.clear()
	await _tap("hand_x")
	await _idle()
	_check("an empty slot says so (%s)" % [_feedback], "No spell in this slot (menu > Spells)" in _feedback)
	_combat.get_loadout().set_spell(1, 0, &"granfulmo")
	_feedback.clear()
	await _tap("hand_x")
	await _idle()
	_check("an unlearned spell won't cast (%s)" % [_feedback], "Granfulmo isn't learned" in _feedback)

	# Learn everything at level 10 for the shape tests.
	for s in spells:
		save.character.spells[s.id] = mini(10, s.max_level)
	SpellCaster.clear_cache()

	var expected := SpellCaster.damage_amount(_combat, load("res://data/weapons/staff.tres"), fajro, 10, false)
	_check("damage is PSO's: (SOL 40 + 560) / 5 x Staff 1.1 = 132 (%.1f)" % expected, is_equal_approx(expected, 132.0))
	# Enemies spread wide (orbs / areas), in a column (lines) or a tight
	# wedge (cones), so each shape is judged on the targets it should reach.
	var wide := [Vector3(-1.6, 0, -2.5), Vector3(0, 0, -3.5), Vector3(1.6, 0, -2.5)]
	var column := [Vector3(0, 0, -2), Vector3(0, 0, -3.5), Vector3(0.1, 0, -5)]
	var spaced := [Vector3(0, 0, -2), Vector3(0, 0, -3.8), Vector3(0, 0, -5.6)]  # room for a slow 1.1 m ball
	var wedge := [Vector3(-1.1, 0, -6), Vector3(0, 0, -7), Vector3(1.1, 0, -6)]
	var shapes := {
		"fajro": [1, wide], "glacio": [3, column], "fulmo": [1, wide], "arbo": [3, column],
		"lumo": [1, wide], "malbo": [1, wide],
		"mezfajro": [3, wide], "mezglacio": [3, wedge], "mezfulmo": [3, wide], "mezarbo": [3, wedge],
		"mezlumo": [3, wedge], "mezmalbo": [3, spaced],
		"granfajro": [3, wide], "granglacio": [3, wide], "granfulmo": [3, wide], "granarbo": [3, wide],
		"granlumo": [3, wide], "granmalbo": [3, wide],
		"daufajro": [1, wide], "daufulmo": [1, wide],
	}
	var wrong := []
	for id in shapes:
		var hit := await _cast_count(StringName(id), shapes[id][1])
		if hit < shapes[id][0]:
			wrong.append("%s %d/%d" % [id, hit, shapes[id][0]])
	_check("every damage shape reaches the enemies it should (%s)" % [wrong], wrong.is_empty())

	# Sustained: hold to channel.
	var enemies := _line_up([Vector3(0, 0, -1.5)])
	_combat.get_loadout().set_spell(1, 0, &"daufajro")
	await _place(ARENA)
	var hp_before := enemies[0].health.hp
	Input.action_press("hand_x")
	await _frames(70)
	var channeling := _combat._current != null and _combat._current.sustained
	Input.action_release("hand_x")
	await _idle()
	_check("holding a Sustained spell channels: several ticks (%.0f damage)" % (hp_before - enemies[0].health.hp),
		channeling and hp_before - enemies[0].health.hp > 30.0)
	_clear_enemies(enemies)

	# Buff / debuff.
	_combat.get_loadout().set_spell(1, 0, &"bonafajro")
	await _place(ARENA)
	await _tap("hand_x")
	await _idle()
	_check("Bonafajro raises STR, scaled by the Staff's support power (x%.3f)" % _player.status.stat_scale(&"strength"),
		is_equal_approx(_player.status.stat_scale(&"strength"), 1.0 + SpellBook.buff_fraction(10) * 1.1))
	enemies = _line_up([Vector3(0, 0, -2), Vector3(3, 0, -2)])
	_combat.get_loadout().set_spell(1, 0, &"malaglacio")
	await _place(ARENA)
	await _tap("hand_x")
	await _idle()
	_check("Malaglacio lowers enemy DEF around you (x%.2f)" % enemies[0].status.stat_scale(&"defense"),
		enemies[0].status.stat_scale(&"defense") < 1.0 and enemies[1].status.stat_scale(&"defense") < 1.0)
	_clear_enemies(enemies)

	# Aura.
	enemies = _line_up([Vector3(1.5, 0, 0)])
	_combat.get_loadout().set_spell(1, 0, &"pasfajro")
	await _place(ARENA)
	hp_before = enemies[0].health.hp
	await _tap("hand_x")
	await _idle()
	await _frames(70)
	var aura_on := false
	for child in _player.get_children():
		aura_on = aura_on or child is SpellAura
	_check("Pasfajro: an aura on you burns enemies close by (%.0f)" % (hp_before - enemies[0].health.hp),
		aura_on and hp_before - enemies[0].health.hp > 0.0 and not enemies[0].status.is_active(StatusEffects.Status.BURN))
	for child in _player.get_children():
		if child is SpellAura:
			child.queue_free()
	_clear_enemies(enemies)

	# Heal and Cure.
	_combat.get_loadout().set_spell(1, 0, &"heal")
	_combat.get_loadout().set_spell(1, 2, &"cure")  # the Staff has 4 slots: special + X is slot 3
	await _place(ARENA)
	_player.health.hp = 50.0
	await _tap("hand_x")
	await _idle()
	_check("Heal restores HP (50 -> %.0f)" % _player.health.hp, _player.health.hp > 120.0)
	save.character.spells[&"cure"] = 9
	SpellCaster.clear_cache()
	_player.status.apply(StatusEffects.Status.FREEZE, 0.2)  # thaws quickly so the cast can start
	_player.status.apply(StatusEffects.Status.POISON, 10.0)
	_player.status.apply_modifier(&"defense", -0.3, 20.0)
	await _frames(20)
	_feedback.clear()
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	await _idle()
	var debuffed := _player.status.modifiers.values().any(func(m: Dictionary) -> bool: return m.fraction < 0.0)
	_check("Cure 9 clears every status and debuff, and keeps the STR buff",
		_player.status.active.is_empty() and not debuffed and _player.status.modifiers.has(&"strength"))

	# Teleportal.
	_combat.get_loadout().set_spell(1, 0, &"teleportal")
	save.character.spells[&"teleportal"] = 1
	await _place(ARENA)
	await _tap("hand_x")
	await _idle()
	var portal: Teleporter = null
	for node in get_nodes_in_group("teleporters"):
		if (node as Teleporter).destination == SpellCaster.SHIP_SCENE and (node as Teleporter).lifetime > 0.0:
			portal = node
	_check("Teleportal opens a pad back to the ship (the gym for now)", portal != null)
	if portal:
		portal.queue_free()

	# Goluman can't cast.
	save.character.race = CharacterData.Race.GOLUMAN
	_combat.get_loadout().set_spell(1, 0, &"fajro")
	_feedback.clear()
	await _tap("hand_x")
	await _idle()
	_check("a Goluman can't cast spells (%s)" % [_feedback], "Goluman can't use magic" in _feedback)

	# --- Traps ---------------------------------------------------------------------------
	save.character.spells[&"damage_trap"] = 5
	save.character.spells[&"freeze_trap"] = 5
	SpellCaster.clear_cache()
	_combat.get_loadout().set_spell(1, 0, &"damage_trap")
	_combat.get_loadout().set_spell(1, 2, &"freeze_trap")
	await _place(ARENA)
	await _tap("hand_x")
	await _idle()
	var set_traps := get_nodes_in_group("traps")
	_check("a Goluman sets a trap at their feet", set_traps.size() == 1)
	await _frames(40)  # arms after 0.6 s
	enemies = _line_up([Vector3(0, 0, 0.6)])  # enemies placed on the plate
	hp_before = enemies[0].health.hp
	await _frames(40)
	_check("an enemy stepping on it springs it (%.0f damage)" % (hp_before - enemies[0].health.hp),
		hp_before - enemies[0].health.hp > 0.0 and get_nodes_in_group("traps").is_empty())
	_clear_enemies(enemies)
	await _place(ARENA)
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	await _idle()
	await _frames(40)
	enemies = _line_up([Vector3(0, 0, 0.6)])
	await _frames(40)
	_check("a Freeze Trap freezes what springs it", enemies[0].status.is_active(StatusEffects.Status.FREEZE))
	_clear_enemies(enemies)
	for i in 6:
		await _place(ARENA + Vector3(i * 0.2, 0, 0))
		await _tap("hand_x")
		await _idle()
	_check("at most 4 traps at once (%d)" % get_nodes_in_group("traps").size(), get_nodes_in_group("traps").size() == 4)
	for t in get_nodes_in_group("traps"):
		t.queue_free()
	save.character.race = CharacterData.Race.HUMAN
	_feedback.clear()
	await _tap("hand_x")
	await _idle()
	_check("only Goluman can set traps (%s)" % [_feedback], "Only Goluman can set traps" in _feedback)

	# --- Level hazards -------------------------------------------------------------------
	var hazard := _main.get_node("Hazards/HazardParalyze") as HazardTrap
	_check("hazards hide from non-Goluman", not hazard.is_visible_to(_player))
	save.character.race = CharacterData.Race.GOLUMAN
	_check("Goluman see them (trap vision)", hazard.is_visible_to(_player))
	save.character.race = CharacterData.Race.HUMAN
	_player.status.clear_all()
	await _place(hazard.global_position + Vector3.UP * 0.1)
	await _frames(5)
	_check("stepping on one springs it once (Paralyzed: can't act)",
		hazard.sprung and not _player.status.can_act())
	_player.status.clear_all()

	# --- Discs ------------------------------------------------------------------------------
	save.character.spells.erase(&"granfajro")
	_combat.stats.soul = 130.0
	_check("reading a disc you qualify for learns it (%s)" % _player.read_disc(&"granfajro", 1, true),
		save.character.spell_level(&"granfajro") == 1)
	var stored := _player.read_disc(&"lumo", 20, true)
	_check("a disc you can't read yet is stored (%s)" % stored, save.inventory.discs.size() == 1)
	_combat.stats.soul = 2000.0
	_check("and can be read later from the stash (%s)" % _player.read_stored_disc(0),
		save.character.spell_level(&"lumo") == 20 and save.inventory.discs.is_empty())
	_combat.stats.soul = 40.0
	var oro := save.inventory.oro
	_player.read_disc(&"fajro", 1, true)
	_check("a disc you already know is sold for Oro (+%d)" % (save.inventory.oro - oro), save.inventory.oro > oro)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var discs := 0
	var trap_discs := 0
	for i in 2000:
		var drop := Loot.roll_drop(load("res://data/enemies/grub_hound.tres"), 0, rng, i % 2 == 0)
		if drop.has("disc"):
			discs += 1
			if SpellBook.get_spell(StringName(drop.disc.id)).is_trap():
				trap_discs += 1
	_check("spell discs drop (~6%% of kills: %d / 2000), trap discs only for Goluman (%d)" % [discs, trap_discs],
		discs > 70 and discs < 180 and trap_discs > 20 and trap_discs < discs)

	# --- Spells tab with a gamepad ---------------------------------------------------------
	_equip(null, null)
	_menu._set = _combat.loadout_set
	_combat.loadout_set.loadouts[7] = Loadout.make(load("res://data/weapons/wand.tres"), null)
	_menu.open()
	while _menu._tab_name() != "Spells":
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	_check("the Spells tab lists casting items, and one is focused (%s)" % _focused_text(),
		_focused_text().contains("Wand"))
	for i in 10:
		if _focused_text().begins_with("8"):
			break
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("A picks the item and focuses its first slot (%s)" % _focused_text(), _focused_text().begins_with("Y:"))
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	var picked := _focused_text()
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	var assigned := _menu._set.loadouts[7].get_spell(0, 0)
	_check("A on a slot, then A on a spell, assigns it (%s -> %s)" % [picked, assigned],
		assigned != &"" and picked.begins_with(SpellBook.get_spell(assigned).display_name))
	_check("focus returns to the slot", _focused_text().begins_with("Y:"))
	await _pad(JOY_BUTTON_X)
	await _frames(3)
	_check("X clears the slot", _menu._set.loadouts[7].get_spell(0, 0) == &"")
	await _pad(JOY_BUTTON_B)
	await _frames(3)
	_check("B steps back to the items, still in the menu (%s)" % _focused_text(),
		_menu.visible and _focused_text().contains("Wand"))
	await _pad(JOY_BUTTON_B)
	_check("B again closes the menu", not _menu.visible)

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ------------------------------------------------------------------

## Casts the spell from slot X at three enemies ahead; returns how many it hurt.
func _cast_count(id: StringName, layout: Array) -> int:
	var enemies := _line_up(layout)
	_combat.get_loadout().set_spell(1, 0, id)
	await _place(ARENA)
	var before := []
	for e in enemies:
		before.append(e.health.hp)
	await _tap("hand_x")
	await _idle()
	await _frames(100)
	var hurt := 0
	for i in enemies.size():
		if enemies[i].health.hp < before[i]:
			hurt += 1
	_clear_enemies(enemies)
	return hurt


func _line_up(offsets: Array) -> Array[Enemy]:
	var list: Array[Enemy] = []
	for o in offsets:
		var data := (load("res://data/enemies/grub_hound.tres") as EnemyData).duplicate() as EnemyData
		data.aggro_range = 0.0
		data.max_hp = 9000.0
		data.attack_damage = 0.0
		var e := Enemy.create(data)
		_main.add_child(e)
		e.global_position = ARENA + o
		list.append(e)
	return list


func _clear_enemies(list: Array[Enemy]) -> void:
	for e in list:
		if is_instance_valid(e):
			e.queue_free()


func _equip(left: WeaponData, right: WeaponData) -> void:
	_combat.loadout_set.loadouts[7] = Loadout.make(left, right)
	_combat.select_loadout(7)


func _place(at: Vector3) -> void:
	_combat.cancel()
	_combat.lp = _combat.stats.max_lp
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(6)


func _idle() -> void:
	for i in 300:
		if not _combat.is_attacking():
			break
		await physics_frame
	await _frames(4)


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _focused_text() -> String:
	var f := _focused()
	if f is Button:
		return (f as Button).text.strip_edges().trim_prefix("> ").strip_edges()
	return ""


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
		await process_frame


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame
	await physics_frame
