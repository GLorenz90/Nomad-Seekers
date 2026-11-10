extends SceneTree
## Automated test for Part 11: character levels (Grayson, 2026-11-09).
##
## - PSO's EXP curve (exact at its anchor levels), levels 1-200.
## - Seven growth tables (four races, three jobs) that combine; LCK never
##   grows; combinations line up with PSO's classes.
## - Gaining a level: stats grow, HP and LP refill, the HUD flashes, shows the
##   banner and the gains, and the EXP bar fills below LP.
## - Armor level requirements, weapon stat requirements (palette picker and
##   Inventory refuse), shop tiers by level, the Debug tab's level tools.
## Runs in the arena with its rooms switched off.
##   godot --headless --path . --script res://tests/leveling_test.gd

var _main: Node
var _player: Player
var _save: SaveData
var _failures := 0
var _level_ups: Array = []


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_save = SaveData.create("Tester", CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
		CharacterData.Job.STRIKER, 1)
	_player.use_save(_save)
	_player.autosave = false
	_player.leveled_up.connect(func(level: int, gains: Dictionary): _level_ups.append([level, gains]))
	for room in ["Rooms/RoomA", "Rooms/RoomB"]:
		(_main.get_node(room) as WaveRoom).state = WaveRoom.RoomState.CLEARED
	await _frames(20)
	var c := _save.character
	var s := _player.combat.stats

	# --- PSO's EXP curve ---------------------------------------------------------------
	var anchors := {1: 0, 2: 50, 10: 4050, 20: 20539, 50: 319847, 100: 2339735, 120: 4835405,
		150: 15741551, 199: 78415384, 200: 83227800}
	var exact := true
	for level in anchors:
		exact = exact and Leveling.exp_for(level) == anchors[level]
	_check("the EXP table matches PSO's at its anchor levels (level 200: %d)" % Leveling.exp_for(200), exact)
	var rising := true
	for i in range(1, Leveling.EXP_TABLE.size()):
		rising = rising and Leveling.EXP_TABLE[i] > Leveling.EXP_TABLE[i - 1]
	_check("every level needs more EXP than the last (200 levels)", rising and Leveling.EXP_TABLE.size() == 200)
	_check("level_for: 49 EXP is level 1, 50 is 2, 83,227,800 is 200, more stays 200",
		Leveling.level_for(49) == 1 and Leveling.level_for(50) == 2 and Leveling.level_for(83227800) == 200
		and Leveling.level_for(999999999) == 200)

	# --- Seven tables ----------------------------------------------------------------------
	_check("one table per race and per job (%d + %d)" % [Leveling.RACE_GROWTH.size(), Leveling.JOB_GROWTH.size()],
		Leveling.RACE_GROWTH.size() == CharacterData.Race.size() and Leveling.JOB_GROWTH.size() == CharacterData.Job.size())
	var at_one := Leveling.gains(CharacterData.Race.HUMAN, CharacterData.Job.STRIKER, 1)
	var none := true
	for stat in at_one:
		none = none and float(at_one[stat]) == 0.0
	_check("level 1 gains nothing", none)
	var hu := Leveling.gains(CharacterData.Race.HUMAN, CharacterData.Job.STRIKER, 200)
	var cast := Leveling.gains(CharacterData.Race.CORESIAN, CharacterData.Job.STRIKER, 200)
	var newm := Leveling.gains(CharacterData.Race.LUMERA, CharacterData.Job.INVOKER, 200)
	var fo := Leveling.gains(CharacterData.Race.HUMAN, CharacterData.Job.INVOKER, 200)
	var ra := Leveling.gains(CharacterData.Race.GOLUMAN, CharacterData.Job.RANGER, 200)
	_check("Human Striker at 200 gains HUmar's growth (STR +%d, HP +%d)" % [hu[&"strength"], hu[&"max_hp"]],
		hu[&"strength"] == 898.0 and hu[&"max_hp"] == 1380.0)
	_check("Coresian Striker grows like HUcast: more HP and STR than a Human (HP +%d, STR +%d)" % [cast[&"max_hp"], cast[&"strength"]],
		cast[&"max_hp"] > hu[&"max_hp"] and cast[&"strength"] > hu[&"strength"])
	_check("Lumera Invoker grows like a Newman Force: more SOL and LP than a Human Invoker (SOL +%d)" % newm[&"soul"],
		newm[&"soul"] > fo[&"soul"] and newm[&"max_lp"] > fo[&"max_lp"])
	_check("Rangers grow ATA most; Goluman Ranger DEX +%d over STR +%d" % [ra[&"dexterity"], ra[&"strength"]],
		Leveling.JOB_GROWTH[CharacterData.Job.RANGER][&"accuracy"] > Leveling.JOB_GROWTH[CharacterData.Job.STRIKER][&"accuracy"]
		and ra[&"dexterity"] > ra[&"strength"])
	_check("LCK never grows (PSO)", not hu.has(&"luck") and not Leveling.STATS.has(&"luck"))

	# --- Gaining a level --------------------------------------------------------------------
	var hp_before := s.max_hp
	var str_before := s.strength
	_player.health.hp = 10.0
	_player.combat.lp = 1.0
	_player.gain_exp(50)
	await _frames(3)
	_check("50 EXP: level 2 (%d)" % c.level(), c.level() == 2 and _level_ups.size() == 1)
	var g: Dictionary = _level_ups[0][1]
	_check("stats grow by the gains (STR %.0f -> %.0f, HP %.0f -> %.0f)" % [str_before, s.strength, hp_before, s.max_hp],
		s.strength == str_before + float(g.get(&"strength", 0.0)) and s.max_hp == hp_before + float(g.get(&"max_hp", 0.0))
		and s.strength > str_before)
	_check("a level-up refills HP and LP", _player.health.hp == _player.health.max_hp and _player.combat.lp == s.max_lp)
	var hud: DebugHud = _main.hud
	_check("the HUD shows LEVEL UP and the gains (%s)" % hud.level_up_text().replace("\n", ", "),
		hud._banner.text == "LEVEL UP!  Lv 2" and hud.level_up_text().begins_with("Lv 2") and hud.level_up_text().contains("STR  +"))
	_check("the screen flashes", hud._flash.color.a > 0.0)
	await _frames(5)
	_check("the EXP bar sits under LP and shows the level (%s)" % hud._level_label.text,
		hud._exp_bar.get_parent().get_index() == hud._lp_bar.get_parent().get_index() + 1 and hud._level_label.text == "Lv 2")
	_player.gain_exp(Leveling.exp_for(2) + 10 - c.experience)  # partway to 3
	await _frames(3)
	_check("the EXP bar fills toward the next level (%.2f)" % hud._exp_bar.value, hud._exp_bar.value > 0.0 and hud._exp_bar.value < 1.0)
	# A jump of several levels adds up.
	var before_jump := s.strength
	_player.gain_exp(Leveling.exp_for(20) - c.experience)
	var expected: float = Leveling.gains(c.race, c.job, 20)[&"strength"] - Leveling.gains(c.race, c.job, 2)[&"strength"]
	_check("jumping to level 20 adds every level's growth (STR +%.0f)" % (s.strength - before_jump),
		c.level() == 20 and s.strength - before_jump == expected)

	# --- Armor level requirements -------------------------------------------------------------
	var lumen := ArmorBook.make(&"lumen_hood")
	_check("tiers need levels 1 / 25 / 60 / 100 (Lumen Hood: %d)" % lumen.level_req(), lumen.level_req() == 60
		and ArmorBook.make(ArmorBook.STARTER).level_req() == 1)
	_save.take_armor(lumen)
	_check("level 20 can't wear it (%s)" % ArmorBook.equip_error(c, lumen), ArmorBook.equip(_save, lumen).begins_with("Needs level 60"))
	_check("rares have their own (Pathfinder Treads: %d)" % ArmorBook.template(&"pathfinder_treads").level_req(),
		ArmorBook.template(&"pathfinder_treads").level_req() == 20)

	# --- Weapon stat requirements ---------------------------------------------------------------
	var gs := (load("res://data/weapons/great_sword.tres") as WeaponData).duplicate() as WeaponData
	var arb := (load("res://data/weapons/arbalest.tres") as WeaponData).duplicate() as WeaponData
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	_check("requirements: Pistol %s, Great Sword %s, Arbalest %s" % [pistol.requirement_text(), gs.requirement_text(), arb.requirement_text()],
		pistol.requirement_value() == 0 and gs.requirement_text() == "STR 85" and arb.requirement_text() == "DEX 240")
	_check("rares need 80 more (%s)" % Loot.rare_weapons()[0].requirement_text(), Loot.rare_weapons()[0].requirement_value() >= 80)
	_save.take_weapon(arb)
	var menu: LoadoutMenu = _main.loadout_menu
	menu.save_on_close = false
	menu.open()
	menu.show_tab("Palette")
	await _frames(3)
	_player.combat.job_code = "R"  # a Ranger, so only DEX stands in the way
	menu._on_slot_pressed(1, CombatController.Hand.PRIMARY)
	menu._on_weapon_picked(arb)
	_check("the palette refuses a weapon your stats can't use (%s)" % menu._message.text,
		_save.loadouts.loadouts[1].primary == null and menu._message.text.contains("Needs DEX 240"))
	_player.combat.job_code = c.job_code()
	menu.close()
	await _frames(3)

	# --- Shop tiers by level ----------------------------------------------------------------------
	_check("shop armor tiers by level: 1 at Lv 1, 2 at Lv 20, 3 at Lv 55, 4 at Lv 95",
		Prices.max_armor_tier(1) == 1 and Prices.max_armor_tier(20) == 2 and Prices.max_armor_tier(55) == 3
		and Prices.max_armor_tier(95) == 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var high := Prices.roll_armor_stock(rng, 120)
	var tiers := {}
	for a in high:
		tiers[a.tier] = true
	_check("a level 120 armor shop sells tiers 3-4 (%s)" % [tiers.keys()], not tiers.has(1) and not tiers.has(2))
	var grades := {}
	for id in Prices.roll_unit_stock(rng, 120):
		grades[int(UnitBook.get_unit(id).grade)] = true
	_check("augment grades rise with level (Lv 1: I only; Lv 120 can show III)",
		Prices.max_unit_grade(1) == 0 and Prices.max_unit_grade(40) == 1 and Prices.max_unit_grade(120) == 2)

	# --- Debug tab level tools ----------------------------------------------------------------------
	var ups := _level_ups.size()
	menu.debug_tab._tool_levels(10)
	_check("Debug +10 levels: level 30 with a level-up shown", c.level() == 30 and _level_ups.size() == ups + 1)
	menu.debug_tab._tool_levels(Leveling.MAX_LEVEL)
	_check("Debug Max: level 200 (STR %.0f, HP %.0f)" % [s.strength, s.max_hp], c.level() == 200)
	_check("now the Arbalest's requirement is met (DEX %.0f)" % s.dexterity, arb.requirement_error(s) == "")
	_check("and the Lumen Hood can be worn", ArmorBook.equip(_save, lumen) == "")
	menu.debug_tab._reset_character()
	await _frames(3)
	_check("Reset character: level 1, base stats, high armor off (STR %.0f)" % s.strength,
		c.level() == 1 and s.strength == str_before and _save.character.head == null)

	# --- The save ---------------------------------------------------------------------------------
	_save.character.experience = Leveling.exp_for(42) + 5
	var path := "user://leveling_test_save.tres"
	ResourceSaver.save(_save, path)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	_check("the level comes back with the save (%d)" % loaded.character.level(), loaded.character.level() == 42)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame
