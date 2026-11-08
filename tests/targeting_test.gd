extends SceneTree
## Automated test for the PSU-style target markers: small rings on every enemy
## the next attack would hit, a large ring on the locked target.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/targeting_test.gd

const SWORD_PISTOL := 0
const WAND_SWORD := 4
const GREAT_SWORD := 5

var _main: Node
var _player: Player
var _combat: CombatController
var _markers: TargetMarkers
var _a: TargetDummy
var _b: TargetDummy
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_combat = _player.combat
	_combat.apply_loadout_set(CombatController.make_default_loadouts())
	_markers = _main.target_markers
	_a = _main.get_node("Dummies/DummyA")  # at (0, 0, -8)
	_b = load("res://scenes/enemies/target_dummy.tscn").instantiate()
	_b.name = "DummyExtra"
	_main.get_node("Dummies").add_child(_b)
	await _frames(30)

	# --- Melee: the Sword (single-target saber) vs the Great Sword sweep ---
	_place(_b, Vector3(1.6, 0, -8))  # side by side with DummyA
	await _stand(Vector3(0.8, 0.1, -5.6), SWORD_PISTOL)
	var sword_targets := _combat.predict_targets()
	_check("Sword marks one of two side-by-side enemies (%s)" % _names(sword_targets), sword_targets.size() == 1)
	_check("a small marker sits on it", _markers.get_marked().size() == 1)
	_check("the real swing hits exactly what was marked (%s)" % _names(await _swing_hits()),
		_last_hit_targets.size() == 1 and _last_hit_targets[0] == sword_targets[0])
	await _stand(Vector3(0.8, 0.1, -5.6), GREAT_SWORD)
	var great := _combat.predict_targets()
	_check("Great Sword marks both enemies it would sweep (%s)" % _names(great), great.size() == 2)
	_check("two small markers show", _markers.get_marked().size() == 2)
	await _stand(Vector3(0.8, 0.1, -5.6), GREAT_SWORD)
	_check("the real Great Sword swing hits both (%s)" % _names(await _swing_hits()), _last_hit_targets.size() == 2)
	await _stand(Vector3(0.8, 0.1, 2.0), GREAT_SWORD)
	_check("nothing in reach, nothing marked (%s)" % _names(_combat.predict_targets()),
		_combat.predict_targets().is_empty() and _markers.get_marked().is_empty())

	# --- Projectiles: first enemy on the line; piercing spells mark the whole line ---
	_place(_b, Vector3(0, 0, -11))  # directly behind DummyA
	await _stand(Vector3(0, 0.1, -2), SWORD_PISTOL)
	_combat.preview_hand = CombatController.Hand.RIGHT  # Pistol
	await _frames(2)
	var shot := _combat.predict_targets()
	_check("Pistol marks only the first enemy in line (%s)" % _names(shot), shot.size() == 1 and shot[0] == _a)
	await _stand(Vector3(0, 0.1, -2), WAND_SWORD)
	_combat.preview_hand = CombatController.Hand.LEFT  # Wand
	await _frames(2)
	var bolt := _combat.predict_targets()
	_check("Fire Bolt (no pierce) marks one (%s)" % _names(bolt), bolt.size() == 1)
	Input.action_press("shift")
	await _frames(2)
	var lance := _combat.predict_targets()
	Input.action_release("shift")
	_check("Frost Lance (pierce) marks both enemies on the line (%s)" % _names(lance), lance.size() == 2)

	# --- Lock-on: a large marker on the locked enemy ---
	await _stand(Vector3(0, 0.1, -5.5), SWORD_PISTOL)
	_combat.preview_hand = CombatController.Hand.LEFT
	Input.action_press("lock_on")
	await _frames(2)
	Input.action_release("lock_on")
	await _frames(3)
	var rig: CameraRig = _main.get_node("CameraRig")
	_check("lock-on shows the large marker (locked: %s)" % (rig.lock_target.name if rig.lock_target else "none"),
		rig.lock_target == _a and _markers.is_lock_marker_visible())
	_check("the locked enemy doesn't also get a small marker", not _a in _markers.get_marked())
	Input.action_press("lock_on")
	await _frames(2)
	Input.action_release("lock_on")
	await _frames(3)
	_check("unlocking hides the large marker", not _markers.is_lock_marker_visible())

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


var _last_hit_targets: Array[Node] = []


## Taps X and returns the distinct enemies the swing actually hit.
func _swing_hits() -> Array[Node]:
	_last_hit_targets.clear()
	var record := func(target, _info, _amount):
		if not target in _last_hit_targets:
			_last_hit_targets.append(target)
	_combat.hit_landed.connect(record)
	Input.action_press("hand_x")
	await _frames(2)
	Input.action_release("hand_x")
	for i in 120:
		await physics_frame
		if not _combat.is_attacking():
			break
	_combat.hit_landed.disconnect(record)
	_a.health.restore_full()
	_b.health.restore_full()
	_place(_a, Vector3(0, 0, -8))
	_place(_b, _b._start)
	await _frames(10)
	return _last_hit_targets


func _place(dummy: TargetDummy, at: Vector3) -> void:
	dummy.global_position = at
	dummy._start = at
	dummy.reset_physics_interpolation()


func _stand(at: Vector3, loadout: int) -> void:
	_combat.select_loadout(loadout)
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(10)


func _names(nodes: Array) -> String:
	var names := PackedStringArray()
	for n in nodes:
		names.append(n.name)
	return "[%s]" % ", ".join(names)


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
