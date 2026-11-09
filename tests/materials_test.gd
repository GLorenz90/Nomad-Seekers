extends SceneTree
## Automated test for PSO materials: the ten materials, PSO's usage limits
## (+25 on the shared one), Goluman restrictions, stat gains (including max HP
## and hit chance), drops and pickups, the save round-trip, the debug reset,
## and using one from the Character tab with a gamepad. Runs in the arena.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/materials_test.gd

const TEST_SAVE := "user://materials_test_save.tres"

var _main: Node
var _player: Player
var _menu: LoadoutMenu
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_player.autosave = false
	_menu = _main.loadout_menu
	_menu.save_on_close = false
	await _frames(10)
	var c := _player.save.character
	var inv := _player.save.inventory
	var s := _player.combat.stats

	# --- Limits -------------------------------------------------------------------
	_check("ten materials: PSO's seven plus Dex, Res and Accuracy", Materials.ALL.size() == 10
		and Materials.is_material(&"dex_material") and Materials.is_material(&"res_material")
		and Materials.is_material(&"accuracy_material"))
	var limits := []
	for race in [CharacterData.Race.HUMAN, CharacterData.Race.LUMERA, CharacterData.Race.CORESIAN, CharacterData.Race.GOLUMAN]:
		limits.append(Materials.stat_limit(race))
	_check("shared stat limit: Human 250 + 25, Lumera / Coresian 150 + 25, Goluman 150 (%s)" % [limits], limits == [275, 175, 175, 150])
	_check("HP and LP materials have their own 125 each", Materials.pool_limit(c, &"hp") == 125 and Materials.pool_limit(c, &"lp") == 125)
	c.race = CharacterData.Race.GOLUMAN
	_check("Goluman can't use Mind, can use HP, and LP up to half as many (62)",
		Materials.use_error(c, &"mind_material") != "" and Materials.use_error(c, &"lp_material") == ""
		and Materials.use_error(c, &"hp_material") == "" and Materials.pool_limit(c, &"lp") == 62
		and Materials.pool_limit(c, &"hp") == 125)
	c.materials[&"lp_material"] = 62
	_check("the 63rd LP Material is refused for a Goluman", Materials.use_error(c, &"lp_material") != "")
	c.materials.clear()
	c.race = CharacterData.Race.HUMAN

	# --- Using them ---------------------------------------------------------------
	var str_before := s.strength
	_check("using one you don't have says so (%s)" % _player.use_material(&"power_material"),
		s.strength == str_before)
	inv.add_consumable(&"power_material", 3)
	var msg := _player.use_material(&"power_material")
	_check("a Power Material: STR +2, one used up (%s)" % msg,
		s.strength == str_before + 2.0 and inv.count(&"power_material") == 2 and int(c.materials[&"power_material"]) == 1)
	var hp_before := _player.health.max_hp
	inv.add_consumable(&"hp_material", 1)
	_player.use_material(&"hp_material")
	_check("an HP Material raises max HP by 2 (%.0f -> %.0f)" % [hp_before, _player.health.max_hp],
		_player.health.max_hp == hp_before + 2.0 and s.max_hp == hp_before + 2.0)
	var info := DamageInfo.new()
	info.accuracy = s.accuracy
	var before_pct := Accuracy.hit_percent(info, 300.0, null)
	inv.add_consumable(&"accuracy_material", 5)
	for i in 5:
		_player.use_material(&"accuracy_material")
	info.accuracy = s.accuracy
	_check("Accuracy Materials raise ATA, so hits land more (ATA %.0f, vs EVA 300: %.0f%% -> %.0f%%)" % [
		s.accuracy, before_pct, Accuracy.hit_percent(info, 300.0, null)],
		s.accuracy == 50.0 and Accuracy.hit_percent(info, 300.0, null) > before_pct)
	var dex_before := s.dexterity
	inv.add_consumable(&"dex_material", 1)
	_player.use_material(&"dex_material")
	_check("a Dex Material: DEX +2", s.dexterity == dex_before + 2.0)
	var res_before := s.resolve
	inv.add_consumable(&"res_material", 1)
	_player.use_material(&"res_material")
	_check("a Res Material: RES +2", s.resolve == res_before + 2.0)

	# Shared limit: 275 for a human, HP / LP outside it.
	c.materials[&"def_material"] = 275 - Materials.pool_used(c, &"stat") - 1
	_player.apply_materials()
	inv.add_consumable(&"luck_material", 2)
	_player.use_material(&"luck_material")
	var refused := _player.use_material(&"luck_material")
	_check("the 275th stat material is the last (%s)" % refused,
		Materials.pool_used(c, &"stat") == 275 and refused.begins_with("Material limit reached") and inv.count(&"luck_material") == 1)
	inv.add_consumable(&"lp_material", 1)
	_player.use_material(&"lp_material")
	_check("LP Materials still work with the stat limit full", int(c.materials.get(&"lp_material", 0)) == 1)
	c.materials[&"hp_material"] = 125
	_player.apply_materials()
	inv.add_consumable(&"hp_material", 1)
	_check("HP stops at 125 (%s)" % _player.use_material(&"hp_material"), int(c.materials[&"hp_material"]) == 125)
	c.race = CharacterData.Race.LUMERA
	_check("a Lumera's limit is 175, and the ones already used stay", Materials.limit_text(c, &"stat") == "275 / 175"
		and Materials.use_error(c, &"power_material") != "")
	c.race = CharacterData.Race.HUMAN

	# --- Save and reload ------------------------------------------------------------
	var def_now := s.defense
	ResourceSaver.save(_player.save, TEST_SAVE)
	var loaded := ResourceLoader.load(TEST_SAVE, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	var kept := loaded.character.materials.size() == c.materials.size()
	for id in c.materials:
		kept = kept and int(loaded.character.materials.get(id, -1)) == int(c.materials[id])
	_check("the save keeps materials used (%s)" % [loaded.character.materials], kept)
	_player.use_save(loaded)
	_check("switching to that save re-applies them once, not twice (DEF %.0f)" % s.defense, s.defense == def_now)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_check("a fresh save has none, and the stats go back (STR %.0f, DEF %.0f, HP %.0f)" % [s.strength, s.defense, s.max_hp],
		s.strength == str_before and s.defense == 20.0 and s.max_hp == hp_before and _player.health.max_hp == hp_before)
	c = _player.save.character
	inv = _player.save.inventory

	# --- Drops ----------------------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var found := {}
	var drops := 0
	for i in 4000:
		var drop := Loot.roll_drop(load("res://data/enemies/grub_hound.tres"), 0, rng)
		if drop.has("material"):
			drops += 1
			found[drop.material] = true
	_check("materials drop (~2.4%% of kills: %d / 4000), all ten kinds (%d)" % [drops, found.size()],
		drops > 60 and drops < 150 and found.size() == 10)
	var pickup: ItemPickup = _main.spawn_drop({"material": &"mind_material"}, _player.global_position + Vector3(4, 0, 0))
	_check("a material pickup is labelled (%s)" % pickup.describe(), pickup.describe() == "Mind Material")
	pickup.collect(_player)
	_check("picking it up puts it in the inventory", inv.count(&"mind_material") == 1)

	# --- Character tab with a gamepad -------------------------------------------------
	var sol_before := s.soul
	_menu.open()
	while _menu._tab_name() != "Character":
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	var mind_button: Button = _menu._material_buttons[&"mind_material"]
	mind_button.grab_focus()
	await _frames(2)
	_check("the Character tab lists materials (%s)" % mind_button.text, mind_button.text.begins_with("Mind Material x1"))
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("A uses one: SOL +2 (%s)" % _menu._character_message.text, s.soul == sol_before + 2.0 and inv.count(&"mind_material") == 0)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("A with none left explains why (%s)" % _menu._character_message.text, _menu._character_message.text.begins_with("No Mind"))
	_menu._reset_character()
	_check("Reset character forgets materials used (SOL back to %.0f)" % s.soul, c.materials.is_empty() and s.soul == sol_before)
	_menu.close()

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
		await process_frame
