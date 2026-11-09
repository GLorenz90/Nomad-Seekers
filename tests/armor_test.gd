extends SceneTree
## Automated test for Part 7 armor: the armor book (tiers, Light / Heavy,
## job-locked sets, rares), drop rolls (DEF / EVA bonus, augment slots),
## the starter Field Frame, who can wear what (Invokers Light only, job and
## rare restrictions), swapping pieces, augments (stat, element, monster type,
## Double-Heavy), resistances in real hits, unwearable armor coming off after
## a race change, drops (Blue emblem 2x), pickups, the save, old saves, and
## the Armor tab with a gamepad. Runs in the arena.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/armor_test.gd

const TEST_SAVE := "user://armor_test_save.tres"

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
	var data := SaveData.fresh(CombatController.make_default_loadouts())
	data.character.experience = Leveling.exp_for(100)  # every tier wearable (Part 11 level requirements)
	_player.use_save(data)
	_player.autosave = false
	_menu = _main.loadout_menu
	_menu.save_on_close = false
	await _frames(10)
	var save := _player.save
	var c := save.character
	var inv := save.inventory
	var s := _player.combat.stats

	# --- The book ------------------------------------------------------------------
	var tiered := 0
	var rares := 0
	var slot_rule := true
	var heavy_jobs := true
	for id in ArmorBook.all():
		var a: ArmorData = ArmorBook.all()[id]
		if a.rare:
			rares += 1
			continue
		tiered += 1
		slot_rule = slot_rule and a.max_slots == (4 if a.slot == ArmorData.Slot.TORSO else 1)
	_check("24 tiered pieces (4 tiers x Head / Torso / Legs x Light / Heavy) and 5 rares (%d / %d)" % [tiered, rares],
		tiered == 24 and rares == 5)
	_check("Torso holds up to 4 augments, Head and Legs 1", slot_rule)
	var crown := ArmorBook.template(&"wardens_crown")
	var path := ArmorBook.template(&"pathfinder_treads")
	_check("rare exceptions: Warden's Crown and Pathfinder Treads have 2 slots", crown.max_slots == 2 and path.max_slots == 2)
	_check("job-locked sets: Core Ranger, Titan Striker, Aether Invoker",
		ArmorBook.template(&"core_armor").jobs == "R" and ArmorBook.template(&"titan_helm").jobs == "S"
		and ArmorBook.template(&"aether_frame").jobs == "I")
	var frame := ArmorBook.template(&"field_frame")
	var head := ArmorBook.template(&"field_hood")
	_check("Head and Legs are about 40%% of a Torso (Field Frame DEF %d, Field Hood DEF %d)" % [frame.defense, head.defense],
		head.defense == roundf(frame.defense * 0.4))

	# --- Rolls -----------------------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var torso_slots := {}
	var head_slots := {}
	var bonus_ok := true
	for i in 600:
		var t := ArmorBook.roll(&"bastion_armor", rng)
		torso_slots[t.slots] = true
		bonus_ok = bonus_ok and t.def_bonus <= t.max_def_bonus and t.eva_bonus <= t.max_eva_bonus and t.units.size() == t.slots
		head_slots[ArmorBook.roll(&"bastion_helm", rng).slots] = true
	_check("drops roll 0-4 slots on a Torso (%s), 0-1 on a Head (%s), and a DEF / EVA bonus within range" % [
		torso_slots.keys(), head_slots.keys()], torso_slots.size() == 5 and head_slots.size() == 2 and bonus_ok)
	_check("rares keep their fixed slots", ArmorBook.roll(&"wardens_crown", rng).slots == 2)

	# --- Starter -----------------------------------------------------------------------
	_check("a new Seeker wears a Field Frame with 1 augment slot",
		c.torso != null and c.torso.id == &"field_frame" and c.torso.slots == 1 and c.head == null and c.legs == null)
	var def_with := s.defense
	var eva_with := s.evasion
	ArmorBook.unequip(save, ArmorData.Slot.TORSO)
	_player.apply_bonuses()
	_check("taking it off removes DEF 4, EVA 6, RES 4 (DEF %.0f -> %.0f)" % [def_with, s.defense],
		s.defense == def_with - 4.0 and s.evasion == eva_with - 6.0 and inv.armors.size() == 1)
	ArmorBook.equip(save, inv.armors[0])
	_player.apply_bonuses()
	_check("and wearing it again puts them back", s.defense == def_with and inv.armors.is_empty())

	# --- Who can wear what -------------------------------------------------------------
	var heavy := ArmorBook.make(&"plate_armor")
	c.job = CharacterData.Job.INVOKER
	_check("Invokers wear Light only (%s)" % ArmorBook.equip_error(c, heavy), ArmorBook.equip_error(c, heavy) != ""
		and ArmorBook.equip_error(c, ArmorBook.make(&"weave_frame")) == "")
	c.job = CharacterData.Job.RANGER
	_check("Rangers wear Heavy and Light", ArmorBook.equip_error(c, heavy) == "" and ArmorBook.equip_error(c, frame) == "")
	_check("but not the Striker-only Titan set (%s)" % ArmorBook.equip_error(c, ArmorBook.make(&"titan_armor")),
		ArmorBook.equip_error(c, ArmorBook.make(&"titan_armor")) != "" and ArmorBook.equip_error(c, ArmorBook.make(&"core_armor")) == "")
	c.job = CharacterData.Job.STRIKER
	_check("Strikers wear Heavy, Light, and Titan, not Core or Aether",
		ArmorBook.equip_error(c, heavy) == "" and ArmorBook.equip_error(c, ArmorBook.make(&"titan_armor")) == ""
		and ArmorBook.equip_error(c, ArmorBook.make(&"core_armor")) != "" and ArmorBook.equip_error(c, ArmorBook.make(&"aether_frame")) != "")
	var shell := ArmorBook.make(&"ironclad_shell")
	var huntress := ArmorBook.make(&"huntress_treads")
	_check("rares: Ironclad Shell is Goluman only, Huntress Treads female only",
		ArmorBook.equip_error(c, shell) == "Goluman only" and ArmorBook.equip_error(c, huntress) == "Female only")
	c.gender = CharacterData.Gender.FEMALE
	_check("a female Seeker can wear the Huntress Treads", ArmorBook.equip_error(c, huntress) == "")
	c.gender = CharacterData.Gender.MALE

	# --- Swapping and augments ------------------------------------------------------------
	inv.armors.append(heavy)
	var old_frame := c.torso
	old_frame.units[0] = &"str_1"
	_check("wearing Plate Armor works", ArmorBook.equip(save, heavy) == "" and c.torso == heavy)
	_check("the Field Frame goes back to the inventory with its augment still in it",
		old_frame in inv.armors and old_frame.units[0] == &"str_1")
	heavy.slots = 3
	heavy.ensure_units()
	_player.apply_bonuses()
	var str_before := s.strength
	inv.add_unit(&"str_3")
	_check("slotting STR Augment III: STR +15", ArmorBook.insert_unit(save, heavy, 0, &"str_3") == "")
	_player.apply_bonuses()
	_check("(STR %.0f -> %.0f, none left in the bag)" % [str_before, s.strength],
		s.strength == str_before + 15.0 and inv.unit_count(&"str_3") == 0)
	_check("an augment you don't have is refused", ArmorBook.insert_unit(save, heavy, 1, &"dex_3") != "")
	ArmorBook.remove_unit(save, heavy, 0)
	_player.apply_bonuses()
	_check("taking it out returns it", s.strength == str_before and inv.unit_count(&"str_3") == 1)

	# --- Resistances in real hits -------------------------------------------------------------
	var hound_data := (load("res://data/enemies/grub_hound.tres") as EnemyData).duplicate() as EnemyData
	hound_data.aggro_range = 0.0
	var hound := Enemy.create(hound_data)
	_main.add_child(hound)
	hound.global_position = _player.global_position + Vector3(0, 0, -2)
	await _frames(3)
	var plain := await _hit(hound, Element.Type.FIRE)
	inv.add_unit(&"fire_ward_2", 2)
	ArmorBook.insert_unit(save, heavy, 0, &"fire_ward_2")
	ArmorBook.insert_unit(save, heavy, 1, &"fire_ward_2")
	var warded := await _hit(hound, Element.Type.FIRE)
	_check("two Fire Ward IIs take 40%% off Fire hits (%.1f -> %.1f)" % [plain, warded], is_equal_approx(warded, plain * 0.6))
	var generic := await _hit(hound, Element.Type.GENERIC)
	inv.add_unit(&"beast_guard")
	ArmorBook.insert_unit(save, heavy, 2, &"beast_guard")
	var guarded := await _hit(hound, Element.Type.GENERIC)
	_check("a Beast Guard takes 15%% off hits from Beast-type enemies (%.1f -> %.1f)" % [generic, guarded],
		is_equal_approx(guarded, generic * 0.85))
	hound.queue_free()

	# --- Double-Heavy ---------------------------------------------------------------------------
	_check("no Double-Heavy without the augment", not _player.combat.loadout_set.double_heavy_augment)
	inv.add_unit(UnitBook.DOUBLE_HEAVY)
	ArmorBook.insert_unit(save, heavy, 2, UnitBook.DOUBLE_HEAVY)
	_player.apply_bonuses()
	var axes := Loadout.make(load("res://data/weapons/axe.tres"), load("res://data/weapons/axe.tres"))
	_check("slotting the Double-Heavy augment allows two Axes",
		_player.combat.loadout_set.double_heavy_augment and axes.validate(_player.combat.loadout_set.double_heavy_augment) == "")
	ArmorBook.remove_unit(save, heavy, 2)
	_player.apply_bonuses()
	_check("and removing it takes that away", not _player.combat.loadout_set.double_heavy_augment)

	# --- Race change strips what can't be worn ------------------------------------------------
	c.race = CharacterData.Race.GOLUMAN
	inv.armors.append(shell)
	_check("a Goluman wears the Ironclad Shell", ArmorBook.equip(save, shell) == "")
	_player.apply_bonuses()
	_menu.debug_tab._race.select(CharacterData.Race.HUMAN)
	_menu.debug_tab._apply_character()
	_check("switching to Human takes it off (%s)" % _menu.debug_tab._character_message.text,
		c.torso == null and shell in inv.armors and c.race == CharacterData.Race.HUMAN)
	ArmorBook.equip(save, heavy)
	_player.apply_bonuses()

	# --- Drops -----------------------------------------------------------------------------------
	rng.seed = 21
	var counts := {"armor": 0, "unit": 0, "blue": 0, "rare": 0}
	for i in 20000:
		var drop := Loot.roll_drop(hound_data, 0, rng)
		if drop.has("armor"):
			counts.armor += 1
			if (drop.armor as ArmorData).rare:
				counts.rare += 1
		if drop.has("unit"):
			counts.unit += 1
		if Loot.roll_drop(hound_data, Loot.ARMOR_EMBLEM, rng).has("armor"):
			counts.blue += 1
	_check("armor drops from ~4.8%% of kills (%d / 20000), augments ~2.4%% (%d), a few rares (%d)" % [
		counts.armor, counts.unit, counts.rare], counts.armor > 800 and counts.armor < 1150
		and counts.unit > 380 and counts.unit < 580 and counts.rare > 10)
	_check("the Blue emblem finds armor about twice as often (%d)" % counts.blue,
		counts.blue > counts.armor * 1.6 and counts.blue < counts.armor * 2.4)
	var dropped := ArmorBook.roll(&"lumen_hood", rng)
	var pickup: ItemPickup = _main.spawn_drop({"armor": dropped}, _player.global_position + Vector3(5, 0, 0))
	pickup.collect(_player)
	var unit_pickup: ItemPickup = _main.spawn_drop({"unit": &"hp_2"}, _player.global_position + Vector3(5, 0, 0))
	_check("an augment pickup is named (%s)" % unit_pickup.describe(), unit_pickup.describe() == "HP Augment II")
	unit_pickup.collect(_player)
	_check("picking up armor and augments puts them in the inventory", dropped in inv.armors and inv.unit_count(&"hp_2") == 1)

	# --- Save ------------------------------------------------------------------------------------
	ResourceSaver.save(save, TEST_SAVE)
	var loaded := ResourceLoader.load(TEST_SAVE, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	_check("the save keeps worn armor, its augments, spare armor and augments",
		loaded.character.torso.id == &"plate_armor" and loaded.character.torso.units[0] == &"fire_ward_2"
		and loaded.inventory.armors.size() == inv.armors.size() and loaded.inventory.unit_count(&"hp_2") == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	var old := SaveData.new()
	old.character = CharacterData.new()
	old._fill_missing(CombatController.make_default_loadouts())
	_check("an old save with no armor gets the starter Field Frame once",
		old.character.torso != null and old.character.armor_granted)
	ArmorBook.unequip(old, ArmorData.Slot.TORSO)
	old._fill_missing(CombatController.make_default_loadouts())
	_check("(and not again after taking it off)", old.character.torso == null)

	# --- Armor tab with a gamepad ----------------------------------------------------------------
	_menu.open()
	_menu.show_tab("Armor")
	await _frames(3)
	_check("the Armor tab opens on the worn list (%s)" % _focused_text(), _focused_text().begins_with("Head"))
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("A on Head lists head armor you own (%s)" % _focused_text(), _focused_text().begins_with("Lumen Hood"))
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("A wears it", c.head == dropped)
	_check("focus returns to the Head row (%s)" % _focused_text(), _focused_text().begins_with("Head"))
	await _pad(JOY_BUTTON_X)
	await _frames(3)
	_check("X takes it off", c.head == null and dropped in inv.armors)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _frames(2)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _frames(2)
	_check("down reaches the Torso's first augment slot (%s)" % _focused_text(), _focused_text().begins_with("Slot 1"))
	await _pad(JOY_BUTTON_X)
	await _frames(3)
	_check("X empties it", c.torso.units[0] == &"" and inv.unit_count(&"fire_ward_2") == 1)
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	var pick := _focused_text()
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("A, then A on an augment, slots it (%s -> %s)" % [pick, c.torso.units[0]], c.torso.units[0] != &"")
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	await _pad(JOY_BUTTON_B)
	await _frames(3)
	_check("B steps back from the list to the worn column", _menu.visible and _focused_text().begins_with("Slot 1"))
	_menu.close()

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Damage the Seeker takes from one never-missing hit of 50 from the hound.
func _hit(attacker: Enemy, element: Element.Type) -> float:
	_player.health.restore_full()
	_player.status.clear_all()
	var info := DamageInfo.new()
	info.amount = 50.0
	info.damage_type = element
	info.kind = DamageInfo.Kind.MELEE
	info.accuracy = -1.0
	info.status_power = 0.0
	var dealt := _player.receive_hit(info, attacker)
	await _frames(2)
	return dealt


func _focused_text() -> String:
	var f := root.gui_get_focus_owner()
	if f is Button:
		return (f as Button).text.strip_edges().trim_prefix("> ").strip_edges()
	return ""


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
