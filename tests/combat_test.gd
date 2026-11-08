extends SceneTree
## Automated test for Part 2. Drives the hand buttons with simulated input and
## checks timing combos, weapon-step rules, Hard attacks, LP, spells, elemental
## weakness, dash-cancel and navmesh movement.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/combat_test.gd

var _main: Node
var _player: Player
var _combat: CombatController
var _dummy: TargetDummy
var _failures := 0
var _hits: Array[float] = []
var _feedback: Array[String] = []
var _started: Array[String] = []

# Default loadout slots (CombatController.DEFAULT_LOADOUTS).
const WAND := 4
const DERVISH := 6


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_combat = _player.combat
	_combat.stats.luck = 0.0  # no random crits in tests
	# Never depend on (or overwrite) the player's saved loadouts.
	_combat.apply_loadout_set(CombatController.make_default_loadouts())
	_dummy = _main.get_node("Dummies/DummyA")
	_combat.hit_landed.connect(func(_t, _i, amount): _hits.append(amount))
	_combat.combo_feedback.connect(func(text): _feedback.append(text))
	_combat.attack_started.connect(func(_h, _w, attack, _c, _hd): _started.append(attack.display_name))
	await _frames(30)

	var sword := 20.0 * 1.3  # base damage x (1 + STR 30 / 100)

	# --- Single tap ---
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	await _idle()
	_check("tap X swings the sword and hits (got %s)" % [_hits], _hits.size() == 1 and is_equal_approx(_hits[0], sword))

	# --- Full 3-step sword combo in rhythm ---
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	var max_chain := 1
	for i in 2:
		await _until_window()
		await _tap("hand_x")
		max_chain = maxi(max_chain, _combat.chain_step)
	await _idle()
	_check("rhythm presses chain 3 steps (max chain %d)" % max_chain, max_chain == 3)
	_check("plays Slash, Return Slash, Cleave (got %s)" % [_started], _started == ["Slash", "Return Slash", "Cleave"])
	_check("step bonus damage x1.0 / x1.1 / x1.3 (got %s)" % [_hits], _hits.size() == 3
		and is_equal_approx(_hits[1], sword * 1.1) and is_equal_approx(_hits[2], sword * 1.3))
	_check("finisher feedback shown", "Finisher!" in _feedback)

	# --- PSO cadence: two pistol shots can't be closer than 14 frames at 30 fps ---
	await _reset(Vector3(0, 0.1, -5.5))
	var times: Array[float] = []
	_combat.attack_started.connect(func(_h, _w, _a, _c, _hd): times.append(Time.get_ticks_msec() / 1000.0))
	for i in 6:
		await _tap("hand_y")
	await _idle()
	var pistol: WeaponData = _combat.current_weapon(CombatController.Hand.RIGHT)
	_check("mashing the pistol can't beat PSO's 14-frame window (opens %.2f s)" % pistol.normal_attacks[0].window_open,
		is_equal_approx(pistol.normal_attacks[0].window_open, 14.0 / 30.0) and _started.size() <= 2)

	# --- PSO cadence: a rhythm sword chain moves on at PSO's combo frames ---
	await _reset(Vector3(0, 0.1, -5.5))
	var starts: Array[float] = []
	var t0 := Time.get_ticks_msec()
	var on_start := func(_h, _w, _a, _c, _hd): starts.append(_combat._time)
	_combat.attack_started.connect(on_start)
	await _tap("hand_x")
	await _until_window()
	await _tap("hand_x")
	await _idle()
	_combat.attack_started.disconnect(on_start)
	var gap := starts[1] - starts[0] if starts.size() == 2 else 99.0
	_check("Slash chains into Return Slash about 0.43 s in, like PSO's saber (gap %.2f s)" % gap, gap > 0.4 and gap < 0.6)

	# --- Input buffer: a slightly early press fires right when the window opens ---
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	var first: AttackData = _combat._current.attack
	while _combat._current.elapsed < first.window_open - 0.1:
		await physics_frame
	var opened_hits := 0
	Input.action_press("hand_x")
	await physics_frame
	Input.action_release("hand_x")
	for i in 30:
		await physics_frame
		if _started.size() == 2:
			break
	opened_hits = _hits.size()
	await _idle()
	_check("a press 0.1 s early is buffered and chains (%s)" % [_started], _started == ["Slash", "Return Slash"])
	_check("the buffered press doesn't cut the first swing short (%d hits before step 2)" % opened_hits, opened_hits >= 1)

	# --- Three Hard attacks chain: slower, not tighter ---
	await _reset(Vector3(0, 0.1, -5.5))
	var hard_chain := 0
	for i in 3:
		if i > 0:
			await _until_window()
		Input.action_press("hand_x")
		await _frames(20)  # hold past hold_threshold
		Input.action_release("hand_x")
		await _frames(2)
		hard_chain = maxi(hard_chain, _combat.chain_step)
	await _idle()
	_check("three Hard attacks chain when each hold starts in the window (%s)" % [_started],
		hard_chain == 3 and _started == ["Heavy Slash", "Heavy Return", "Piercing Thrust"])

	# --- Too early breaks the combo ---
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	await _frames(3)
	await _tap("hand_x")  # well before window_open
	await _until_window()
	await _tap("hand_x")  # would have chained
	await _frames(2)
	_check("early press shows 'Too early!'", "Too early!" in _feedback)
	_check("after a too-early press, an in-window press doesn't chain (%s)" % [_started],
		_started == ["Slash"])
	await _idle()
	_check("the chain ends after a broken combo", _combat.chain_step == 0)

	# --- Late press starts a fresh chain ---
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	await _idle()
	await _frames(30)
	await _tap("hand_x")
	await _frames(2)
	_check("late press starts a new chain at step 1 (%s)" % [_started], _started == ["Slash", "Slash"] and _combat.chain_step == 1)
	await _idle()

	# --- Mixing weapons resets each weapon's step ---
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	await _until_window()
	await _tap("hand_y")
	await _until_window()
	await _tap("hand_x")
	await _frames(2)
	_check("Sword, Pistol, Sword = chain step 3 (got %d)" % _combat.chain_step, _combat.chain_step == 3)
	_check("sword restarts at step 1 after the pistol (%s)" % [_started], _started == ["Slash", "Shot", "Slash"])
	await _idle()

	# --- Hard attack and LP ---
	await _reset(Vector3(0, 0.1, -5.5))
	Input.action_press("hand_x")
	await _frames(20)
	Input.action_release("hand_x")
	await _idle()
	_check("holding X gives a Hard attack (%s, %s)" % [_started, _hits],
		_started == ["Heavy Slash"] and _hits.size() == 1 and is_equal_approx(_hits[0], sword * 1.8))

	await _reset(Vector3(0, 0.1, -5.5))
	var lp_before := _combat.lp
	await _tap("hand_y")
	await _frames(10)  # LP is spent when the shot starts; regen waits 0.75 s
	_check("pistol shot costs 1 LP (%.1f -> %.1f)" % [lp_before, _combat.lp], absf(lp_before - 1.0 - _combat.lp) < 0.01)
	await _idle()
	_check("pistol projectile hits from range (%s)" % [_hits], _hits.size() == 1 and is_equal_approx(_hits[0], 12.0 * 1.3))

	# --- Dash cancels an attack after its hit ---
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	while _combat.is_attacking() and _combat._current.elapsed < _combat._current.attack.active_end + 0.02:
		await physics_frame
	await _tap("dash")
	await _frames(2)
	_check("dash cancels the sword's recovery", not _combat.is_attacking() and _player.state == Player.State.DASH)
	await _frames(30)

	# --- Wand: spells, elemental weakness, Shift for slot 2 ---
	await _reset(Vector3(0, 0.1, -5.5))
	Input.action_press("loadout_next")
	await _frames(2)
	Input.action_release("loadout_next")
	_check("LB/RB cycles to the next loadout (now %d)" % (_combat.loadout_index + 1), _combat.loadout_index == 1)
	_set_loadout(WAND)
	_check("wand loadout equipped", _combat.current_weapon(CombatController.Hand.LEFT).display_name == "Wand")
	_dummy.health.multipliers[Element.Type.FIRE] = 2.0
	await _tap("hand_x")
	await _idle()
	await _frames(30)
	var bolt := 18.0 * 1.3 * 2.0
	_check("Fire Bolt does double to a fire-weak dummy (%s)" % [_hits], _hits.size() == 1 and is_equal_approx(_hits[0], bolt))
	await _reset(Vector3(0, 0.1, -5.5))
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	await _idle()
	await _frames(30)
	_check("Shift casts the second spell (%s)" % [_started], _started == ["Frost Lance"])
	# Frost Lance pierces, so it can also catch the patrolling DummyB behind DummyA.
	_check("Frost Lance deals Ice damage (%s)" % [_hits], _hits.size() >= 1 and is_equal_approx(_hits[0], 18.0 * 0.85 * 1.3))
	_dummy.health.multipliers.erase(Element.Type.FIRE)
	_set_loadout(0)

	# --- Mobility: rooted vs moving attacks (PSU-style) ---
	var run := _player.move_speed
	var sword_tap := await _speed_while(0, "hand_x", false)
	_check("sword roots you (%.1f m/s)" % sword_tap, sword_tap < 1.5)
	var pistol_tap := await _speed_while(0, "hand_y", false)
	_check("Normal pistol shots keep you moving at half speed (%.1f m/s)" % pistol_tap, absf(pistol_tap - run * 0.5) < 0.8)
	var pistol_hold := await _speed_while(0, "hand_y", true)
	_check("Charged pistol shots root you (%.1f m/s)" % pistol_hold, pistol_hold < 1.0)
	var wand_tap := await _speed_while(WAND, "hand_x", false)
	_check("Normal spells keep you moving at half speed (%.1f m/s)" % wand_tap, absf(wand_tap - run * 0.5) < 0.8)
	var wand_hold := await _speed_while(WAND, "hand_x", true)
	_check("Hard spells root you (%.1f m/s)" % wand_hold, wand_hold < 1.0)
	var dervish_tap := await _speed_while(DERVISH, "hand_x", false)
	_check("Dervish Blades slashes keep you moving (%.1f m/s)" % dervish_tap, absf(dervish_tap - run * 0.5) < 0.8)
	var dervish_hold := await _speed_while(DERVISH, "hand_x", true)
	_check("Dervish Blades spin keeps you moving (%.1f m/s)" % dervish_hold, absf(dervish_hold - run * 0.6) < 0.8)

	# --- Dervish Blades: two-handed combo and sustained spin ---
	_set_loadout(DERVISH)
	await _reset(Vector3(0, 0.1, -6.5))
	_check("two-handed Dervish Blades answer both buttons",
		_combat.current_weapon(CombatController.Hand.RIGHT) == _combat.current_weapon(CombatController.Hand.LEFT))
	await _tap("hand_x")
	await _until_window()
	await _tap("hand_y")
	await _until_window()
	await _tap("hand_x")
	await _idle()
	_check("X, Y, X with one two-handed weapon reaches its step 3 (%s)" % [_started], _started == ["Whirl Cut", "Whirl Cut", "Cyclone"])
	await _reset(Vector3(0, 0.1, -6.5))
	Input.action_press("hand_x")
	await _frames(60)
	var spinning := _combat.is_attacking() and _combat._current.sustained
	Input.action_release("hand_x")
	await _frames(30)
	_check("holding X spins and hits about every 0.2 s (%d hits in 1 s)" % _hits.size(), spinning and _hits.size() >= 3 and _hits.size() <= 5)
	_check("releasing ends the spin", not _combat.is_attacking())
	_set_loadout(0)

	# --- Death and respawn ---
	_dummy.health.hp = 1.0
	await _reset(Vector3(0, 0.1, -5.5), false)
	await _tap("hand_y")
	await _idle()
	_check("dummy dies and leaves the lockable group", not _dummy.is_in_group("lockable") and not _dummy.visible)

	# --- Navmesh ---
	var map := _player.get_world_3d().navigation_map
	_check("navmesh baked (%d polygons)" % _main.get_node("Navigation").navigation_mesh.get_polygon_count(),
		_main.get_node("Navigation").navigation_mesh.get_polygon_count() > 0 and NavigationServer3D.map_get_iteration_id(map) > 0)
	var patroller: TargetDummy = _main.get_node("Dummies/DummyB")
	var patrol_x0 := patroller.global_position.x
	var chaser: TargetDummy = _main.get_node("Dummies/DummyE")
	_player.global_position = Vector3(8, 0.1, 18.0)
	_player.reset_physics_interpolation()
	var d0 := chaser.global_position.distance_to(_player.global_position)
	await _frames(180)
	var d1 := chaser.global_position.distance_to(_player.global_position)
	_check("chase dummy paths toward the Seeker (%.1f -> %.1f m)" % [d0, d1], d1 < d0 - 3.0 and d1 > 1.5)
	_check("patrol dummy moves along its route (x %.1f -> %.1f)" % [patrol_x0, patroller.global_position.x],
		absf(patroller.global_position.x - patrol_x0) > 2.0)

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _set_loadout(index: int) -> void:
	_combat.select_loadout(index)


## Runs forward in an empty corner, attacks, and returns the speed mid-attack.
func _speed_while(loadout: int, action: StringName, hold: bool) -> float:
	_set_loadout(loadout)
	await _reset(Vector3(-24, 0.1, 10))
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_press(action)
	if hold:
		await _frames(28)
	else:
		await _frames(2)
		Input.action_release(action)
		await _frames(26)
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var attacking := _combat.is_attacking()
	Input.action_release(action)
	Input.action_release("move_forward")
	await _idle()
	_set_loadout(0)
	return speed if attacking else -1.0


func _reset(at: Vector3, heal := true) -> void:
	_combat.cancel()
	_combat.lp = _combat.stats.max_lp
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	if heal:
		_dummy.health.restore_full()
	await _frames(20)
	_hits.clear()
	_feedback.clear()
	_started.clear()


## Waits until the current attack's chain window is open (PSO: just after the hit).
func _until_window() -> void:
	for i in 180:
		var cur = _combat._current
		if cur == null or cur.elapsed >= cur.attack.window_open + 0.03:
			return
		await physics_frame


func _idle() -> void:
	for i in 180:
		if not _combat.is_attacking():
			break
		await physics_frame
	await _frames(20)


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
	# physics_frame fires before nodes process, so wait two frames for the
	# release to be handled before the test reads any state.
	await physics_frame
	await physics_frame
