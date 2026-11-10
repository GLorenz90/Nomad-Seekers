extends SceneTree
## Automated test for Part 11's hazards and buttons (Grayson, 2026-11-09:
## "hazards and buttons like PSO") and the menu that no longer pauses.
##
## - Poison mist: drains HP from anyone inside, Goluman too (the room and its
##   corridor: one hazard, two boxes); the button opens the door and clears it.
## - Goluman: immune to Poison and Paralysis; Shock stops them in place, while
##   anyone else can still move while shocked.
## - Four floor plates: alone, three stay down and the fourth needs you on
##   it; then the alcove door opens. With two Seekers, two latch and the last
##   two need someone on each.
## - Darkness: dark around you while inside; the corner button turns it off;
##   the room's exit still waits for every enemy.
## - Buttons that start waves and turn traps off.
## - The menu: the game keeps running, the Seeker takes no game input.
## Runs in scenes/arena.tscn.
##   godot --headless --path . --script res://tests/hazards_test.gd

var _main: Node
var _player: Player
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_player.use_save(SaveData.create("Tester", CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
		CharacterData.Job.STRIKER, 1))
	_player.autosave = false
	await _frames(30)
	var mist: RoomHazard = _main.get_node("RoomHazards/PoisonMist")
	var dark: RoomHazard = _main.get_node("RoomHazards/Darkness")
	var poison_door: SwitchDoor = _main.get_node("SwitchDoors/PoisonDoor")
	var hall_door: SwitchDoor = _main.get_node("SwitchDoors/HallDoor")

	# --- Poison mist --------------------------------------------------------------------
	_player.health.restore_full()
	await _place(Vector3(30, 0.1, -30))
	await _frames(62)  # ~1 s
	var drained := _player.health.max_hp - _player.health.hp
	_check("the poison mist drains about 2%% of max HP a second (%.1f of %.0f)" % [drained, _player.health.max_hp],
		drained > _player.health.max_hp * 0.01 and drained < _player.health.max_hp * 0.035)
	_check("it isn't the Poisoned status", not _poisoned())
	_player.health.hp = 2.0
	await _frames(70)
	_check("it never takes you below 1 HP (%.1f)" % _player.health.hp, _player.health.hp >= 1.0 and not _player.health.is_dead())
	_player.health.restore_full()
	await _place(Vector3(15, 0.1, -30))
	await _frames(40)
	_check("the mist spans the corridor too (one hazard, two boxes)", _player.health.hp < _player.health.max_hp)
	var human_save := _player.save
	_player.use_save(SaveData.create("Gol", CharacterData.Race.GOLUMAN, CharacterData.Gender.MALE,
		CharacterData.Job.RANGER, 1))
	_player.autosave = false
	_player.health.restore_full()
	await _frames(40)
	_check("it drains Goluman too", _player.health.hp < _player.health.max_hp)

	# --- Goluman statuses (Grayson: like PSO's androids) ---------------------------------------
	_player.status.apply(StatusEffects.Status.POISON)
	_player.status.apply(StatusEffects.Status.PARALYZE)
	_check("Goluman are immune to Poison and Paralysis", _player.status.active.is_empty())
	_player.status.apply(StatusEffects.Status.SHOCK, 2.0)
	_check("Shock stops a Goluman in place (no moving, no attacking)",
		not _player.status.can_move() and not _player.status.can_act())
	_player.status.clear_all()
	_player.use_save(human_save)
	_player.status.apply(StatusEffects.Status.SHOCK, 2.0)
	_check("anyone else can still move while shocked, but can't attack",
		_player.status.can_move() and not _player.status.can_act() and _player.status.move_scale() > 0.0)
	_player.status.apply(StatusEffects.Status.POISON)
	_check("and can be poisoned", _poisoned())
	_player.status.clear_all()
	_player.health.restore_full()

	_check("the east door starts locked", not poison_door.is_open)
	await _place(Vector3(38, 0.1, -23.4))
	_check("A at the button (%s)" % _player.interact_prompt(), _player.interact_prompt() == "A: Press the button")
	_player.hold_input(0.0)
	await _tap("jump")
	await _frames(5)
	_check("pressing it opens the door and clears the mist", poison_door.is_open and not mist.active)
	_player.health.restore_full()
	await _place(Vector3(30, 0.1, -30))
	await _frames(80)
	_check("no more drain in the room", _player.health.hp == _player.health.max_hp)

	# --- Four floor plates ------------------------------------------------------------------
	var plates: Array[RoomButton] = []
	for i in 4:
		plates.append(_main.get_node("Buttons/Plate%d" % (i + 1)))
	var hall: SwitchGroup = _main.get_node("Switches/HallSwitch")
	_check("alone, 3 of the 4 plates can stay down", hall.max_latched() == 3)
	for i in 3:
		await _place(plates[i].global_position + Vector3(0, 0.1, 0))
		await _frames(5)
		await _place(Vector3(30, 0.1, -58))
		await _frames(5)
		_check("plate %d stays down after you step off" % (i + 1), plates[i].is_pressed())
	_check("three plates don't open the door", not hall_door.is_open)
	await _place(plates[3].global_position + Vector3(0, 0.1, 0))
	await _frames(5)
	_check("standing on the fourth opens it", hall_door.is_open and hall.done)

	# Two Seekers (co-op rule): two plates latch, the last two need someone each.
	var g := SwitchGroup.new()
	var test_plates: Array[RoomButton] = []
	var holder := Node3D.new()
	_main.add_child(holder)
	for i in 4:
		var b := RoomButton.new()
		b.mode = RoomButton.Mode.FLOOR
		holder.add_child(b)
		test_plates.append(b)
	holder.add_child(g)
	for b in test_plates:
		g.buttons.append(g.get_path_to(b))
	g._ready()
	var second := Node3D.new()
	second.add_to_group("player")
	_main.add_child(second)
	_check("with two Seekers, 2 of 4 plates can stay down", g.max_latched() == 2)
	var someone := Object.new()
	for i in 2:
		test_plates[i]._occupants[someone] = true
		g.button_down(test_plates[i])
		test_plates[i]._occupants.erase(someone)
	test_plates[2]._occupants[someone] = true
	g.button_down(test_plates[2])
	_check("two latched plates plus one Seeker on the third isn't enough",
		test_plates[0].is_pressed() and test_plates[1].is_pressed() and not g.done)
	test_plates[2]._occupants.erase(someone)
	g.button_up(test_plates[2])
	_check("stepping off the third: it pops back up", not test_plates[2].is_pressed())
	var other := Object.new()
	test_plates[2]._occupants[someone] = true
	g.button_down(test_plates[2])
	test_plates[3]._occupants[other] = true
	g.button_down(test_plates[3])
	_check("one Seeker on each of the last two fires it", g.done)
	second.queue_free()
	someone.free()
	other.free()

	# --- Darkness ------------------------------------------------------------------------------
	var room_d: WaveRoom = _main.get_node("Rooms/RoomD")
	await _place(Vector3(52, 0.1, -22))
	await _frames(40)
	var hud: DebugHud = _main.hud
	_check("inside the dark room it's dark around you (%.2f)" % hud._dark.modulate.a, RoomHazard.dark_for(_player) and hud._dark.modulate.a > 0.5)
	_check("its waves started", room_d.state == WaveRoom.RoomState.ACTIVE)
	_check("its exit is locked while enemies live", room_d.is_door_locked(&"ExitDoor0"))
	await _place(Vector3(69.2, 0.1, -37.4))
	_player.hold_input(0.0)
	await _tap("jump")
	await _frames(40)
	_check("the corner button turns the darkness off (%.2f)" % hud._dark.modulate.a, not dark.active and not RoomHazard.dark_for(_player)
		and hud._dark.modulate.a < 0.5)
	_check("but the exit still waits for the enemies", room_d.is_door_locked(&"ExitDoor0"))
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			(e as Enemy).health.take_damage(_big_hit())
	for i in 300:
		if room_d.state == WaveRoom.RoomState.CLEARED:
			break
		await _frames(2)
		for e in get_nodes_in_group("enemies"):
			if is_instance_valid(e) and not e.is_queued_for_deletion() and not (e as Enemy).health.is_dead():
				(e as Enemy).health.take_damage(_big_hit())
	_check("once every enemy is dead the exit opens", room_d.state == WaveRoom.RoomState.CLEARED
		and not room_d.is_door_locked(&"ExitDoor0"))

	# --- Other button actions -------------------------------------------------------------------
	var room_a: WaveRoom = _main.get_node("Rooms/RoomA")
	room_a.switch_action("start")
	_check("a button can start a room's waves", room_a.state == WaveRoom.RoomState.ACTIVE)
	var trap: HazardTrap = _main.get_node("Hazards/HazardDamage")
	trap.switch_action("disable")
	_check("a button can turn a trap off", trap.destroyed)

	# --- The menu doesn't pause ----------------------------------------------------------------
	var menu: LoadoutMenu = _main.loadout_menu
	menu.save_on_close = false
	await _place(Vector3(0, 0.1, 20))
	await _pad(JOY_BUTTON_START)
	await _frames(3)
	_check("Start opens the menu and the game keeps running", menu.visible and not paused and _player.input_locked)
	var at := _player.global_position
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	_check("the Seeker doesn't move while it's open (%.2f m)" % _player.global_position.distance_to(at),
		_player.global_position.distance_to(at) < 0.05)
	var hp := _player.health.hp
	_player.status.apply(StatusEffects.Status.POISON, 3.0)
	await _frames(90)
	_check("the world keeps going: poison still ticks (%.0f -> %.0f)" % [hp, _player.health.hp], _player.health.hp < hp)
	await _pad(JOY_BUTTON_START)
	await _frames(3)
	_check("closing it gives control back", not menu.visible and not _player.input_locked)

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------------------------

func _poisoned() -> bool:
	return _player.status.active.has(StatusEffects.Status.POISON)


func _big_hit() -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = 99999.0
	info.accuracy = -1.0
	return info


func _place(at: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(6)


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		await process_frame
		await process_frame


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame
	await physics_frame


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
