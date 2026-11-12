extends SceneTree
## Persistent maps and the Teleportal (Grayson, 2026-11-12: "very faithful to
## the PSO way"):
## - The game never pauses: with the menu open the world runs and enemies
##   still hit you.
## - A session starts in Nomad-2. Every map you visit stays as you left it
##   until you quit to the title: killed enemies stay dead, items stay on the
##   floor, rooms stay cleared. A map nobody is on is parked (no processing,
##   physics or navigation) and wakes when someone comes back. Shops restock
##   on each visit.
## - Teleportal: one per Seeker; a field end back to Nomad-2 and a Nomad-2 end
##   back to the spot. Using the Nomad-2 end closes both; coming back the
##   normal way keeps them; casting again moves it; quitting closes it.
## Uses its own folder for character slots.
##   godot --headless --path . --script res://tests/session_test.gd

const DIR := "user://session_test/"
const ARENA := "res://scenes/arena.tscn"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_wipe()
	Session.slot_dir = DIR + "characters/"
	Session.legacy_save = DIR + "save.tres"
	Session.settings_path = DIR + "session.cfg"
	Party.clear()
	Session.write_slot(0, SaveData.create("Seeker", CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
		CharacterData.Job.STRIKER, 1))
	Session.play(0)
	await _frames(30)
	var hub := current_scene
	var seeker := _seeker(hub)
	_check("a session starts in Nomad-2", Maps.id_of(hub) == Session.HUB_SCENE and seeker != null)
	var shop := _shop(hub)
	shop.roll_stock(1)

	# --- To the arena: Nomad-2 is kept and parked ----------------------------------------------------
	CoopDirector.travel(seeker, ARENA)
	await _frames(30)
	var director := CoopDirector.find(self)
	var arena: Node = director.level_for(ARENA) if director else null
	seeker = _seeker(arena)
	_check("the first trip keeps Nomad-2 (the window's level) and opens the arena beside it",
		arena != null and current_scene == hub and seeker != null)
	_check("Nomad-2 is parked: no processing, physics or navigation",
		CoopDirector.is_parked(hub) and not PhysicsServer3D.space_is_active(hub.get_world_3d().space)
		and not NavigationServer3D.map_is_active(hub.get_world_3d().navigation_map))
	_check("alone, you play in one full-window pane", director.split.panes.size() == 1
		and director.split.panes[0].player == seeker)

	# --- Leave a mark on the arena ------------------------------------------------------------------
	for room in Scope.group(arena, "wave_rooms"):
		(room as WaveRoom).state = WaveRoom.RoomState.CLEARED
	var rooms := Scope.group(arena, "wave_rooms").size()
	var dead := _enemy(arena, seeker.global_position + Vector3(4, 0, -6))
	var alive := _enemy(arena, seeker.global_position + Vector3(-12, 0, -12))
	var item := (arena as Node).call("spawn_drop", {"oro": 55}, seeker.global_position + Vector3(9, 0.5, 6)) as ItemPickup
	await _frames(5)
	dead.health.take_damage(_hit(9999.0))
	await _frames(10)
	_check("an enemy dies here", not is_instance_valid(dead) or dead.is_dead())

	# --- The game never pauses ----------------------------------------------------------------------------
	var menu: LoadoutMenu = (arena as Node).kit_for(seeker).menu
	alive.global_position = seeker.global_position + Vector3(0, 0, -1.5)
	alive.data.attack_range = 2.5
	alive.data.accuracy = 999.0
	var hp := seeker.health.hp
	menu.open()
	await _frames(240)
	_check("with the menu open the game keeps running and enemies still hit (%.0f -> %.0f HP)" % [hp, seeker.health.hp],
		not paused and menu.visible and seeker.input_locked and seeker.health.hp < hp)
	menu.close()
	seeker.health.restore_full()
	alive.global_position = seeker.global_position + Vector3(-12, 0, -12)
	alive.data.attack_range = 0.1
	await _frames(5)

	# --- Teleportal ----------------------------------------------------------------------------------------
	var spot := seeker.global_position + Vector3(1.5, 0, 1.5)
	var field := Teleportals.open(seeker, spot)
	await _frames(2)
	var hub_pad := _return_pad(Party.LEADER)
	_check("Teleportal: a pad here back to Nomad-2, and a return pad on (parked) Nomad-2",
		field != null and field.get_parent() == arena and field.destination == Session.HUB_SCENE
		and hub_pad != null and hub_pad.get_parent() == hub and hub_pad.destination == ARENA)
	var alive_at := alive.global_position
	field.travel(seeker)
	await _frames(30)
	seeker = _seeker(hub)
	_check("its field end takes you to Nomad-2, and both ends stay",
		seeker != null and is_instance_valid(field) and is_instance_valid(hub_pad))
	_check("the arena is parked now; Nomad-2 is awake", CoopDirector.is_parked(arena) and not CoopDirector.is_parked(hub))
	_check("Nomad-2 woke for a new visit: its shops restock", not shop._rolled)
	await _frames(30)
	_check("nothing moves on a parked map", is_instance_valid(alive) and alive.global_position.is_equal_approx(alive_at))

	hub_pad.travel(seeker)
	await _frames(30)
	seeker = _seeker(arena)
	_check("the Nomad-2 end takes you back to the spot (%s)" % seeker.global_position,
		seeker != null and Vector2(seeker.global_position.x, seeker.global_position.z).distance_to(Vector2(spot.x, spot.z)) < 1.0)
	_check("and then both ends close", not is_instance_valid(field) or field.is_queued_for_deletion()
		and Teleportals.pads_of(Party.LEADER, self).is_empty() and not Teleportals.has_portal(Party.LEADER))
	_check("the arena is as you left it: the dead enemy stays dead", not is_instance_valid(dead) or dead.is_dead())
	_check("the other is still there", is_instance_valid(alive) and not alive.is_dead())
	_check("the item is still on the floor", is_instance_valid(item))
	_check("the rooms are still cleared", Scope.group(arena, "wave_rooms").size() == rooms
		and Scope.group(arena, "wave_rooms").all(func(r): return (r as WaveRoom).state == WaveRoom.RoomState.CLEARED))

	# --- Coming back the normal way keeps it; casting again moves it ------------------------------------
	Teleportals.open(seeker, seeker.global_position + Vector3(0, 0, 2))
	CoopDirector.travel(seeker, Session.HUB_SCENE)
	await _frames(20)
	seeker = _seeker(hub)
	CoopDirector.travel(seeker, ARENA)
	await _frames(20)
	seeker = _seeker(arena)
	_check("back by the normal teleporter: the Teleportal stays open (2 ends)", Teleportals.pads_of(Party.LEADER, self).size() == 2)
	var moved_to := seeker.global_position + Vector3(-3, 0, 0)
	Teleportals.open(seeker, moved_to)
	await _frames(2)
	var pads := Teleportals.pads_of(Party.LEADER, self)
	var field_now: Teleporter = null
	for p in pads:
		if not p.portal_return:
			field_now = p
	_check("casting again moves it: still one pair, at the new spot", pads.size() == 2 and field_now != null
		and field_now.global_position.is_equal_approx(moved_to))

	# --- Quitting ends the session -----------------------------------------------------------------------
	Session.quit_to_title()
	await _frames(20)
	_check("quitting to the title closes every map and Teleportal",
		CoopDirector.find(self) == null and not Teleportals.has_portal(Party.LEADER) and current_scene is TitleScreen)

	Party.clear()
	Session.slot = -1
	Session.save = null
	_wipe()
	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------------------------------

func _seeker(level: Node) -> Player:
	if level == null or level.kits.is_empty():
		return null
	var p: Player = level.kits[0].player
	p.autosave = false
	return p


func _shop(level: Node) -> ServiceCounter:
	for c in Scope.group(level, "service_counters"):
		if (c as ServiceCounter).service != ServiceCounter.Service.BANK and (c as ServiceCounter).service != ServiceCounter.Service.GUILD:
			return c
	return null


func _return_pad(who: int) -> Teleporter:
	for p in Teleportals.pads_of(who, self):
		if p.portal_return:
			return p
	return null


func _enemy(level: Node, at: Vector3) -> Enemy:
	var data := (load("res://data/enemies/grub_hound.tres") as EnemyData).duplicate() as EnemyData
	var e := Enemy.create(data)
	level.add_child(e)
	e.global_position = at
	return e


func _hit(amount: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	return info


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _wipe() -> void:
	var abs := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(abs):
		_rm(abs)


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_rm(path.path_join(sub))
	DirAccess.remove_absolute(path)
