extends SceneTree
## Automated test for Part 3: loadout rules, LT modes, blocking, parrying,
## shield deflect and shove, dodge i-frames, powerstance twin attacks, and the
## loadout menu.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/loadout_test.gd

const SWORD_PISTOL := 0
const SHIELD_SWORD := 1
const TWIN_SWORDS := 2
const TWIN_PISTOLS := 3
const GREAT_SWORD := 5
const EMPTY_SLOT := 7

var _main: Node
var _player: Player
var _combat: CombatController
var _dummy: TargetDummy
var _swinger: TargetDummy
var _failures := 0
var _hits: Array[float] = []
var _feedback: Array[String] = []
var _started: Array[String] = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_combat = _player.combat
	_combat.stats.luck = 0.0
	# Keep these checks about blocking and combos free of defense and EVA misses.
	_combat.stats.defense = 0.0
	_combat.stats.resolve = 0.0
	_combat.stats.evasion = 0.0
	_combat.x_is_left = true  # these checks were written with X = left hand
	# A fresh save (Striker, default loadouts) that is never written to disk.
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	# The expected numbers here use base stats: take the Human race bonus back off.
	var race_bonus := _player.save.character.race_bonuses()
	for stat in race_bonus:
		_combat.stats.set(stat, float(_combat.stats.get(stat)) - float(race_bonus[stat]))
	_player.autosave = false
	_dummy = _main.get_node("Dummies/DummyA")
	_swinger = _main.get_node("Dummies/Swinger")
	_swinger.attack_mode = TargetDummy.AttackMode.NONE  # driven by hand below
	(_main.get_node("Dummies/Shooter") as TargetDummy).attack_mode = TargetDummy.AttackMode.NONE
	_combat.hit_landed.connect(func(_t, _i, amount): _hits.append(amount))
	_combat.combo_feedback.connect(func(text): _feedback.append(text))
	_combat.attack_started.connect(func(_h, _w, attack, _c, _hd): _started.append(attack.display_name))
	await _frames(30)

	var w := func(name: String) -> WeaponData: return CombatController.load_weapon(name)

	# --- Loadout rules ---
	var axe_heavy := Loadout.make(w.call("axe"), w.call("heavy_shield"))
	_check("Axe + Heavy Shield breaks the one-Heavy rule", axe_heavy.validate(false) != "")
	_check("Double-Heavy augment allows Axe + Heavy Shield", axe_heavy.validate(true) == "")
	_check("Axe + Sword is fine (one Heavy)", Loadout.make(w.call("axe"), w.call("sword")).validate(false) == "")
	_check("Great Sword can't share hands", Loadout.make(w.call("great_sword"), w.call("sword")).validate(true) != "")

	var menu: LoadoutMenu = _main.loadout_menu
	menu.save_on_close = false
	menu._set = _combat.loadout_set
	menu.equip(EMPTY_SLOT, 0, w.call("sword"))
	menu.equip(EMPTY_SLOT, 1, w.call("pistol"))
	menu.equip(EMPTY_SLOT, 0, w.call("great_sword"))
	var slot := _combat.loadout_set.loadouts[EMPTY_SLOT]
	_check("a two-handed weapon goes in the right hand and clears the left",
		slot.right.display_name == "Great Sword" and slot.left == null)
	menu.equip(EMPTY_SLOT, 1, w.call("pistol"))
	_check("equipping a one-handed weapon clears a two-handed one", slot.left == null and slot.right.display_name == "Pistol")
	menu.equip(EMPTY_SLOT, 0, w.call("axe"))
	menu.equip(EMPTY_SLOT, 1, w.call("heavy_shield"))
	_combat.select_loadout(6)
	_combat.cycle_loadout(1)
	_check("LB/RB skips a loadout that breaks the rules (landed on %d)" % (_combat.loadout_index + 1), _combat.loadout_index == 0)
	_combat.loadout_set.double_heavy_augment = true
	_combat.select_loadout(6)
	_combat.cycle_loadout(1)
	_check("with the augment it becomes usable (landed on %d)" % (_combat.loadout_index + 1), _combat.loadout_index == EMPTY_SLOT)
	_combat.loadout_set.double_heavy_augment = false
	_combat.loadout_set.loadouts[EMPTY_SLOT] = Loadout.new()
	_combat.select_loadout(SHIELD_SWORD)
	_combat.cycle_loadout(-1)
	_combat.cycle_loadout(-1)
	_check("LB/RB skips empty loadouts backwards (landed on %d)" % (_combat.loadout_index + 1), _combat.loadout_index == 6)

	# --- LT mode per loadout ---
	var expected := {
		SWORD_PISTOL: Loadout.LTMode.ARMS_UP, SHIELD_SWORD: Loadout.LTMode.SHIELD,
		TWIN_SWORDS: Loadout.LTMode.ARMS_UP, TWIN_PISTOLS: Loadout.LTMode.ARMS_UP,
		GREAT_SWORD: Loadout.LTMode.TWO_HAND}
	var modes_ok := true
	for index in expected:
		modes_ok = modes_ok and _combat.loadout_set.loadouts[index].get_lt_mode() == expected[index]
	_check("LT blocks with every loadout: arms-up, shield, pairs (arms-up), 2h", modes_ok)
	var sets := _combat.loadout_set.loadouts
	_check("same-type pairs are powerstanced, mixed pairs aren't",
		sets[TWIN_SWORDS].is_powerstance() and sets[TWIN_PISTOLS].is_powerstance()
		and not sets[SWORD_PISTOL].is_powerstance() and not sets[SHIELD_SWORD].is_powerstance())

	# --- Two-handed weapons are one item ---
	_combat.select_loadout(GREAT_SWORD)
	var meshes := 0
	for m in _combat._meshes:
		if m.mesh != null:
			meshes += 1
	_check("Great Sword shows as one weapon, in the right hand (%d meshes)" % meshes,
		meshes == 1 and _combat._meshes[CombatController.Hand.RIGHT].mesh != null)
	_check("both buttons use the one Great Sword",
		_combat.current_weapon(0) == _combat.current_weapon(1) and _combat.current_weapon(0).display_name == "Great Sword")

	# --- Blocking (hits from the Swinger, 20 damage) ---
	_check("no block takes full damage (%.0f)" % await _hit_after(SWORD_PISTOL, false, 0), is_equal_approx(_last_taken, 20.0))
	await _hit_after(SHIELD_SWORD, true, 30)
	_check("shield block stops 60%% (took %.0f)" % _last_taken, is_equal_approx(_last_taken, 8.0) and "Blocked" in _feedback)
	await _hit_after(SHIELD_SWORD, true, 3)
	_check("hit right after raising the shield is parried (took %.0f)" % _last_taken, _last_taken == 0.0 and "Parry!" in _feedback)
	_check("parry staggers the attacker (%.1f s)" % _swinger._stagger, _swinger._stagger > 1.0)
	await _hit_after(SWORD_PISTOL, true, 30)
	_check("arms-up block stops 25%% (took %.0f)" % _last_taken, is_equal_approx(_last_taken, 15.0))
	await _hit_after(SWORD_PISTOL, true, 3)
	_check("arms-up can't parry (took %.0f)" % _last_taken, is_equal_approx(_last_taken, 15.0))
	await _hit_after(GREAT_SWORD, true, 30)
	_check("two-handed block stops 35%% (took %.0f)" % _last_taken, is_equal_approx(_last_taken, 13.0))
	await _hit_after(SHIELD_SWORD, true, 30, true)
	_check("blocks don't cover your back (took %.0f)" % _last_taken, is_equal_approx(_last_taken, 20.0))
	_check("blocking slows you to 40%% speed", is_equal_approx(_combat.block_move_scale, 0.4))

	# With a shield you keep blocking while attacking, at 66% damage.
	_combat.select_loadout(SHIELD_SWORD)
	await _reset(Vector3(0, 0.1, -5.5))
	Input.action_press("block")
	await _frames(20)
	await _tap("hand_y")
	var still_blocking := _combat.is_blocking()
	await _idle()
	Input.action_release("block")
	_check("shield stays up while you attack (blocking: %s)" % still_blocking, still_blocking)
	_check("attacks made while shield-blocking deal 66%% (%s)" % [_hits],
		_hits.size() == 1 and is_equal_approx(_hits[0], 20.0 * 1.3 * 0.66))
	_combat.select_loadout(SWORD_PISTOL)
	await _reset(Vector3(0, 0.1, -5.5))
	Input.action_press("block")
	await _frames(20)
	await _tap("hand_x")
	var arms_up_blocking := _combat.is_blocking()
	await _idle()
	Input.action_release("block")
	_check("an arms-up block drops for the attack, at full damage (%s)" % [_hits],
		not arms_up_blocking and _hits.size() == 1 and is_equal_approx(_hits[0], 20.0 * 1.3))

	# Shield hand button: Deflect opens a parry window.
	await _setup_facing_swinger(SHIELD_SWORD)
	await _tap("hand_x")
	_take_swing()
	_check("Deflect (shield hand button) parries (took %.0f)" % _last_taken, _last_taken == 0.0)
	await _idle()

	# Dodge i-frames.
	await _setup_facing_swinger(SWORD_PISTOL)
	await _tap("dash")
	_take_swing()
	_check("a hit during the dash's i-frames is dodged", _last_taken == 0.0 and "Dodged" in _feedback)
	await _frames(30)

	# Heavy Shield shove knocks enemies back.
	_combat.loadout_set.loadouts[EMPTY_SLOT] = Loadout.make(w.call("heavy_shield"), w.call("sword"))
	_combat.select_loadout(EMPTY_SLOT)
	await _reset(Vector3(0, 0.1, -6.3))
	var before := _dummy.global_position
	await _tap("hand_x")
	await _frames(30)
	_check("Heavy Shield shove knocks the dummy back (%.1f m)" % before.distance_to(_dummy.global_position),
		before.distance_to(_dummy.global_position) > 1.0)
	_combat.loadout_set.loadouts[EMPTY_SLOT] = Loadout.new()

	# Integration: block a real bolt from the Shooter.
	var shooter: TargetDummy = _main.get_node("Dummies/Shooter")
	shooter.attack_mode = TargetDummy.AttackMode.SHOOT
	shooter._attack_cooldown = 0.2
	_combat.select_loadout(SHIELD_SWORD)
	await _reset(Vector3(24, 0.1, 6))
	Input.action_press("block")
	await _frames(30)
	var hp := _player.health.hp
	for i in 150:
		await physics_frame
		if _player.health.hp < hp:
			break
	Input.action_release("block")
	shooter.attack_mode = TargetDummy.AttackMode.NONE
	_check("shield blocks a real Shooter bolt (took %.0f)" % (hp - _player.health.hp), is_equal_approx(hp - _player.health.hp, 8.0))

	# --- Powerstance: a same-type pair always attacks with both hands ---
	var sword_hit := 20.0 * 1.3
	_combat.select_loadout(TWIN_SWORDS)
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	await _idle()
	_check("X with twin swords: both hit, 75%% each (%s)" % [_hits], _hits.size() == 2
		and is_equal_approx(_hits[0], sword_hit * 0.75) and is_equal_approx(_hits[1], sword_hit * 0.75))
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_y")
	await _idle()
	_check("Y with twin swords also hits with both (%d hits)" % _hits.size(), _hits.size() == 2)
	await _reset(Vector3(0, 0.1, -5.5))
	await _tap("hand_x")
	for i in 2:
		await _until_window()
		await _tap("hand_y" if i == 0 else "hand_x")
	await _idle()
	_check("twin attacks chain their own 3 steps on either button (%s)" % [_started],
		_started == ["Slash", "Return Slash", "Cleave"] and "Twin finisher!" in _feedback)

	# LT still blocks with a powerstanced pair.
	await _hit_after(TWIN_SWORDS, true, 30)
	_check("LT blocks with twin swords instead of twin-attacking (took %.0f)" % _last_taken, is_equal_approx(_last_taken, 15.0))

	# RT + a hand: that hand's special, the other hand swings normally.
	var sword: WeaponData = _combat.current_weapon(CombatController.Hand.LEFT)
	var special := AttackData.new()
	special.display_name = "Test Special"
	special.damage_mult = 2.0
	special.lp_cost = 5.0
	special.duration = 0.8
	special.active_start = 0.3
	special.active_end = 0.4
	sword.special_attack = special
	await _reset(Vector3(0, 0.1, -5.5))
	var lp_start := _combat.lp
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	var spent := lp_start - _combat.lp  # before LP starts regenerating
	await _idle()
	_check("RT + X uses the X-hand weapon's special with both swinging (%s, %s, %.0f LP)" % [_started, _hits, spent],
		_started == ["Test Special"] and _hits.size() == 2
		and is_equal_approx(_hits.max(), sword_hit * 2.0 * 0.75) and is_equal_approx(_hits.min(), sword_hit * 0.75)
		and spent >= 5.0)
	await _reset(Vector3(0, 0.1, -5.5))
	Input.action_press("shift")
	await _tap("hand_y")
	Input.action_release("shift")
	await _idle()
	_check("RT + Y uses the Y-hand weapon's special; Frost Sword has none, so a normal twin (%s)" % [_started],
		_started == ["Slash"] and _hits.size() == 2)
	sword.special_attack = null

	_combat.select_loadout(TWIN_PISTOLS)
	await _reset(Vector3(0, 0.1, -5.5))
	var lp_before := _combat.lp
	await _tap("hand_y")
	await _frames(10)
	var lp_spent := lp_before - _combat.lp
	await _idle()
	_check("twin pistols fire both guns (%d hits, %.0f LP)" % [_hits.size(), lp_spent], _hits.size() == 2 and is_equal_approx(lp_spent, 2.0))

	# --- Menu ---
	var press := InputEventAction.new()
	press.action = &"menu"
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	await process_frame
	_check("Start/Tab opens the loadout menu and pauses the game", menu.is_open() and paused)
	menu.close()
	_check("closing the menu unpauses", not menu.is_open() and not paused)

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


var _last_taken := 0.0


## Stands in front of the Swinger with the given loadout, optionally holds LT
## for block_frames, then takes one 20-damage swing. Returns damage taken.
func _hit_after(loadout: int, block: bool, block_frames: int, from_behind := false) -> float:
	await _setup_facing_swinger(loadout)
	if from_behind:
		_player.rotation.y = PI
	if block:
		Input.action_press("block")
		await _frames(block_frames)
	_take_swing()
	Input.action_release("block")
	await _frames(5)
	return _last_taken


func _setup_facing_swinger(loadout: int) -> void:
	_combat.select_loadout(loadout)
	_swinger._stagger = 0.0
	await _reset(Vector3(20, 0.1, 10.0))  # Swinger at (20, 0, 8): straight ahead
	_player.health.restore_full()


func _take_swing() -> void:
	var info := DamageInfo.new()
	info.amount = 20.0
	var hp := _player.health.hp
	_player.receive_hit(info, _swinger)
	_last_taken = hp - _player.health.hp


func _reset(at: Vector3) -> void:
	_combat.cancel()
	_combat.lp = _combat.stats.max_lp
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_dummy.health.restore_full()
	_dummy.global_position = Vector3(0, 0, -8)  # undo any shove
	_dummy.reset_physics_interpolation()
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
	await physics_frame
	await physics_frame
