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
	# A fresh save (Striker, default loadouts) that is never written to disk.
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_player.autosave = false
	_markers = _main.target_markers
	_a = _main.get_node("Dummies/DummyA")  # at (0, 0, -8)
	_b = load("res://scenes/enemies/target_dummy.tscn").instantiate()
	_b.name = "DummyExtra"
	_main.get_node("Dummies").add_child(_b)
	await _frames(30)

	_check("default buttons: X is the right hand, Y the left",
		_combat.button_for(CombatController.Hand.RIGHT) == "X" and _combat.button_for(CombatController.Hand.LEFT) == "Y")
	var LEFT := CombatController.Hand.LEFT
	var RIGHT := CombatController.Hand.RIGHT

	# --- Melee: the Sword (single-target saber) vs the Great Sword sweep ---
	_place(_b, Vector3(1.6, 0, -8))  # side by side with DummyA
	await _stand(Vector3(0.8, 0.1, -5.6), SWORD_PISTOL)  # left Sword, right Pistol
	var sword_targets := _combat.predict_targets(LEFT)
	_check("Sword marks one of two side-by-side enemies (%s)" % _names(sword_targets), sword_targets.size() == 1)
	_check("the real swing hits exactly what was marked (%s)" % _names(await _swing_hits("hand_y")),
		_last_hit_targets.size() == 1 and _last_hit_targets[0] == sword_targets[0])
	await _stand(Vector3(0.8, 0.1, -5.6), GREAT_SWORD)
	var great := _combat.predict_targets(RIGHT)
	_check("Great Sword marks both enemies it would sweep (%s)" % _names(great), great.size() == 2)
	_check("two markers show, green (both buttons use the Great Sword)", _marked_bits() == [3, 3])
	await _stand(Vector3(0.8, 0.1, -5.6), GREAT_SWORD)
	_check("the real Great Sword swing hits both (%s)" % _names(await _swing_hits("hand_x")), _last_hit_targets.size() == 2)
	await _stand(Vector3(0.8, 0.1, 2.0), GREAT_SWORD)
	_check("nothing in reach, nothing marked", _combat.predict_targets(RIGHT).is_empty() and _markers.get_marked().is_empty())

	# --- Both hands at once: no more "last weapon used" ---
	_place(_b, Vector3(0, 0, -11))  # directly behind DummyA
	await _stand(Vector3(0, 0.1, -5.6), SWORD_PISTOL)
	_check("Sword (left) and Pistol (right) on the same enemy: green", _markers.get_marked().get(_a, 0) == 3)
	await _stand(Vector3(0, 0.1, -2), SWORD_PISTOL)
	_check("out of Sword reach, only the Pistol (right) marks it: blue", _markers.get_marked().get(_a, 0) == TargetMarkers.RIGHT_BIT)
	await _stand(Vector3(0, 0.1, -2), WAND_SWORD)  # left Wand, right Sword
	_check("only the Wand (left) reaches: yellow", _markers.get_marked().get(_a, 0) == TargetMarkers.LEFT_BIT)
	var before_swing: int = _markers.get_marked().get(_a, 0)
	await _swing_hits("hand_x")  # use the Sword; the Wand's marker must stay
	await _frames(2)
	_check("using the Sword doesn't hide the Wand's marker (before %d, after %d)" % [before_swing, _markers.get_marked().get(_a, 0)],
		_markers.get_marked().get(_a, 0) & TargetMarkers.LEFT_BIT != 0)

	# --- Projectiles: first enemy on the line; piercing spells mark the whole line ---
	await _stand(Vector3(0, 0.1, -2), SWORD_PISTOL)
	var shot := _combat.predict_targets(RIGHT)
	_check("Pistol marks only the first enemy in line (%s)" % _names(shot), shot.size() == 1 and shot[0] == _a)
	await _stand(Vector3(0, 0.1, -2), WAND_SWORD)
	var bolt := _combat.predict_targets(LEFT)
	_check("Fire Bolt (no pierce) marks one (%s)" % _names(bolt), bolt.size() == 1)
	Input.action_press("shift")
	await _frames(2)
	var lance := _combat.predict_targets(LEFT)
	Input.action_release("shift")
	_check("Frost Lance (pierce) marks both enemies on the line (%s)" % _names(lance), lance.size() == 2)

	# --- Lock-on: a large ring on the locked enemy, plus its hand colors ---
	await _stand(Vector3(0, 0.1, -5.5), SWORD_PISTOL)
	Input.action_press("lock_on")
	await _frames(2)
	Input.action_release("lock_on")
	await _frames(3)
	var rig: CameraRig = _main.get_node("CameraRig")
	_check("lock-on shows the large ring (locked: %s)" % (rig.lock_target.name if rig.lock_target else "none"),
		rig.lock_target == _a and _markers.is_lock_marker_visible())
	_check("the locked enemy still shows which hands would hit it", _markers.get_marked().get(_a, 0) == 3)
	# When the locked target dies, the lock jumps to the next closest one.
	_a.remove_from_group("lockable")  # what an enemy does when it dies
	await _frames(3)
	_check("killing the locked target re-locks the next closest (%s)" % (rig.lock_target.name if rig.lock_target else "none"),
		rig.lock_target == _b and _markers.is_lock_marker_visible())
	var everyone := get_nodes_in_group("lockable")
	for node in everyone:
		node.remove_from_group("lockable")
	await _frames(3)
	_check("with nothing left in range the lock drops", rig.lock_target == null and not _markers.is_lock_marker_visible())
	for node in everyone:
		node.add_to_group("lockable")
	_a.add_to_group("lockable")
	rig._set_lock(_a)
	await _frames(2)
	Input.action_press("lock_on")
	await _frames(2)
	Input.action_release("lock_on")
	await _frames(3)
	_check("unlocking hides the large ring", not _markers.is_lock_marker_visible())

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


var _last_hit_targets: Array[Node] = []


## Taps a hand button and returns the distinct enemies the attack actually hit.
func _swing_hits(action: StringName) -> Array[Node]:
	_last_hit_targets.clear()
	var record := func(target, _info, _amount):
		if not target in _last_hit_targets:
			_last_hit_targets.append(target)
	_combat.hit_landed.connect(record)
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
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


func _marked_bits() -> Array:
	var bits := _markers.get_marked().values()
	bits.sort()
	return bits


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
