extends SceneTree
## Automated test for Part 6: SyncAIDa feeding, stat levels and the bonus to
## the Seeker, level cap, PSO-style evolutions, burst unlocks, owning several
## and pairing one, the Sync Burst gauge, and each burst. Runs in the arena.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/syncaida_test.gd

const TEST_SAVE := "user://syncaida_test_save.tres"
const ARENA := Vector3(0.0, 0.1, 4.0)

var _main: Node
var _player: Player
var _combat: CombatController
var _sync: SyncAIDaCompanion
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_combat = _player.combat
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_player.autosave = false
	_sync = _player.syncaida
	_combat.stats.luck = 0.0
	for room in ["Rooms/RoomA", "Rooms/RoomB"]:
		(_main.get_node(room) as WaveRoom).state = WaveRoom.RoomState.CLEARED
	await _frames(30)

	# --- Starting state ----------------------------------------------------
	var save := _player.save
	_check("a new Seeker owns two SyncAIDa and pairs the first (%s)" % _sync.data.display_name,
		save.syncaida.size() == 2 and _sync.data == save.syncaida[0])
	var pip := _sync.data
	_check("it starts at level 0 as a Mote, with no burst", pip.level() == 0 and pip.form == "Mote" and pip.bursts.is_empty())
	var base_str := _combat.stats.strength
	var base_def := _combat.stats.defense

	# --- Feeding -----------------------------------------------------------
	var gels := save.inventory.count(&"hp_gel")
	var events := _sync.feed(&"hp_gel")
	_check("feeding an HP Gel uses one up (%d -> %d)" % [gels, save.inventory.count(&"hp_gel")],
		save.inventory.count(&"hp_gel") == gels - 1 and not events.is_empty())
	_check("and gives DEF +40, SOL +10, DEX stays at 0 (%s)" % [pip.stat_xp],
		is_equal_approx(pip.stat_xp[&"def"], 40.0) and is_equal_approx(pip.stat_xp[&"sol"], 10.0)
		and is_equal_approx(pip.stat_xp[&"dex"], 0.0))
	_check("Lumidium you don't have can't be fed", _sync.feed(&"fire").is_empty())
	save.inventory.lumidium[&"fire"] = 2
	_sync.feed(&"fire")
	_check("banked Lumidium feeds it (fire left %d)" % save.inventory.lumidium[&"fire"], save.inventory.lumidium[&"fire"] == 1)

	# --- Levels, bonuses, evolutions, bursts -------------------------------
	var evolved_at := -1
	for i in 200:
		var e := _sync.feed(&"fire", true)
		if "evolved" in e:
			evolved_at = pip.level()
			break
	_check("level 10 evolves it by job: Striker -> Vanguard (%s at %d)" % [pip.form, evolved_at],
		evolved_at == 10 and pip.form == "Vanguard")
	_check("and unlocks the first burst, Lumen Nova (%s)" % pip.burst_name(), pip.active() == SyncAIDaData.Burst.LUMEN_NOVA)
	var str_levels := pip.stat_level(&"str")
	_check("each STR level adds 2 STR to the Seeker (+%.0f for %d levels)" % [_combat.stats.strength - base_str, str_levels],
		is_equal_approx(_combat.stats.strength - base_str, str_levels * 2.0))

	var nyx := save.syncaida[1]
	_player.pair_syncaida(1)
	_check("pairing the other SyncAIDa swaps the bonus out", is_equal_approx(_combat.stats.strength, base_str)
		and _sync.data == nyx)
	_player.pair_syncaida(0)
	_check("pairing back restores it", is_equal_approx(_combat.stats.strength - base_str, str_levels * 2.0))

	while pip.level() < 35:
		_sync.feed(&"fire", true)
	_check("level 35 takes its strongest stat's form: STR -> Talon (%s)" % pip.form, pip.form == "Talon")
	_check("and unlocks Aegis Pulse", pip.bursts.size() == 2 and pip.bursts[1] == SyncAIDaData.Burst.AEGIS_PULSE)
	while pip.level() < 50:
		_sync.feed(&"ice", true)
	_check("level 50 takes its two strongest stats' form: STR + DEX -> Falcon (%s)" % pip.form, pip.form == "Falcon")
	_check("and unlocks Mending Bloom (3 bursts)", pip.bursts.size() == 3 and pip.bursts[2] == SyncAIDaData.Burst.MENDING_BLOOM)
	while pip.level() < 100:
		_sync.feed(&"light", true)
	_check("level 100 is a Prime form (%s)" % pip.form, pip.form.ends_with(" Prime"))
	for i in 400:
		_sync.feed(&"raw", true)
	_check("level caps at 200 (%d)" % pip.level(), pip.level() == 200)
	_check("DEF bonus follows DEF levels (+%.0f)" % (_combat.stats.defense - base_def),
		is_equal_approx(_combat.stats.defense - base_def, pip.stat_level(&"def") * 2.0))

	var ranger := SyncAIDaData.create("Test")
	while ranger.level() < 10:
		ranger.feed(&"raw", CharacterData.Job.RANGER)
	_check("a Ranger's SyncAIDa becomes a Tracker at 10 (%s)" % ranger.form, ranger.form == "Tracker")
	var inv_job := SyncAIDaData.create("Test2")
	while inv_job.level() < 10:
		inv_job.feed(&"lp_cell", CharacterData.Job.INVOKER)
	_check("an Invoker's becomes a Lumen (%s)" % inv_job.form, inv_job.form == "Lumen")

	# Back to a modest SyncAIDa for the burst checks, so bonuses stay small.
	_player.pair_syncaida(1)
	for i in 10:
		_sync.feed(&"raw", true)
	_check("Nyx reaches level 12 with Lumen Nova (Lv %d)" % nyx.level(), nyx.level() >= 10 and nyx.active() >= 0)

	# --- Gauge ---------------------------------------------------------------
	nyx.gauge = 0.0
	var enemy := _spawn(ARENA + Vector3(0, 0, -3))
	_combat.report_hit(enemy, _info(50.0), 50.0)
	_check("damage dealt fills the gauge (50 dmg -> %.1f)" % nyx.gauge, is_equal_approx(nyx.gauge, 5.0))
	_player.health.take_damage(_info(20.0))
	_check("damage taken fills it faster (20 dmg -> +%.1f)" % (nyx.gauge - 5.0), is_equal_approx(nyx.gauge - 5.0, 7.0))
	_check("L3 does nothing until it's full", not _sync.fire())

	# --- Lumen Nova ----------------------------------------------------------
	await _place(ARENA)
	var near := _spawn(ARENA + Vector3(2, 0, -3))
	var far := _spawn(ARENA + Vector3(0, 0, -14))
	await _frames(5)
	var near_hp := near.health.hp
	var far_hp := far.health.hp
	nyx.gauge = 100.0
	await _tap("sync_burst")
	_check("L3 fires Lumen Nova: hits within 8 m (%.0f -> %.0f)" % [near_hp, near.health.hp], near.health.hp < near_hp)
	_check("but not 14 m away", is_equal_approx(far.health.hp, far_hp))
	_check("and empties the gauge", nyx.gauge == 0.0)

	# --- Aegis Pulse -------------------------------------------------------------
	nyx.bursts = [SyncAIDaData.Burst.LUMEN_NOVA, SyncAIDaData.Burst.AEGIS_PULSE]
	nyx.active_burst = 1
	var sword := load("res://data/weapons/sword.tres") as WeaponData
	var plain := _combat._make_damage(sword, sword.normal_attacks[0], false, 1.0).amount
	nyx.gauge = 100.0
	_sync.fire()
	var buffed := _combat._make_damage(sword, sword.normal_attacks[0], false, 1.0).amount
	_check("Aegis Pulse: +30%% damage dealt (%.1f -> %.1f)" % [plain, buffed], is_equal_approx(buffed, plain * 1.3))
	await _frames(60)  # past the burst's i-frames
	_combat.stats.evasion = 0.0
	_player.health.restore_full()
	var taken := _player.receive_hit(_info(100.0), null)
	var expected := 100.0 * Defense.scale_for(DamageInfo.Kind.MELEE, _combat.stats.defense, 0, 0) * 0.7
	_check("and -30%% damage taken (%.1f, expected %.1f)" % [taken, expected], is_equal_approx(taken, expected))

	# --- Mending Bloom -----------------------------------------------------------
	nyx.bursts = [SyncAIDaData.Burst.LUMEN_NOVA, SyncAIDaData.Burst.AEGIS_PULSE, SyncAIDaData.Burst.MENDING_BLOOM]
	nyx.active_burst = 2
	_player.health.hp = 50.0
	_combat.lp = 10.0
	_player.status.apply(StatusEffects.Status.BURN, 10.0)
	nyx.gauge = 100.0
	_sync.fire()
	_check("Mending Bloom heals half HP, gives 30 LP and cures (hp %.0f, lp %.0f)" % [_player.health.hp, _combat.lp],
		_player.health.hp >= 50.0 + _player.health.max_hp * 0.5 - 0.1 and _combat.lp >= 40.0 - 0.1
		and _player.status.active.is_empty())

	# --- Menu and save -------------------------------------------------------------
	var menu: LoadoutMenu = _main.loadout_menu
	menu.save_on_close = false
	menu.open()
	var has_tab := false
	for i in menu._tabs.get_tab_count():
		if menu._tabs.get_tab_title(i) == "SyncAIDa":
			has_tab = true
	_check("the menu has a SyncAIDa tab", has_tab)
	var lp_cells := save.inventory.count(&"lp_cell")
	menu._on_feed(&"lp_cell")
	_check("feeding from the menu uses the item (%d -> %d)" % [lp_cells, save.inventory.count(&"lp_cell")],
		save.inventory.count(&"lp_cell") == lp_cells - 1)
	menu.close()
	await _frames(5)

	ResourceSaver.save(save, TEST_SAVE)
	var loaded := ResourceLoader.load(TEST_SAVE, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	_check("save round-trip keeps every SyncAIDa, its form, bursts and pairing",
		loaded.syncaida.size() == 2 and loaded.paired == 1 and loaded.syncaida[0].form == pip.form
		and loaded.syncaida[0].level() == 200 and loaded.syncaida[1].bursts.size() == 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ------------------------------------------------------------------

func _info(amount: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	info.kind = DamageInfo.Kind.MELEE
	return info


func _spawn(at: Vector3) -> Enemy:
	var data := (load("res://data/enemies/grub_hound.tres") as EnemyData).duplicate() as EnemyData
	data.aggro_range = 0.0
	data.max_hp = 2000.0
	data.evasion = 0.0
	var enemy := Enemy.create(data)
	_main.add_child(enemy)
	enemy.global_position = at
	return enemy


func _place(at: Vector3) -> void:
	_combat.cancel()
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(10)


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
