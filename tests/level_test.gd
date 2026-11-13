extends SceneTree
## Automated test for Part 13a: the runtime the level editor needs.
##
## - LevelData (addons/seeker_data): sizes, the publish check, the leash rule
##   (chase radius below wander radius is invalid), save and load.
## - Maps: area folders, one pick per area per session, data level map ids.
## - The demo data level (res://levels/test_1/demo, tools/build_demo_level.gd)
##   built and played: lighting, rooms, a dialogue zone, a button-opened gate,
##   a corridor enemy that wanders and gives up its chase, a wave room whose
##   way in shuts during the fight and whose way on opens when it's cleared
##   (spawn delays included), floor plates extending a bridge (with its
##   navigation link), a moving platform, a hazard button, a whole-party zone
##   starting a dialogue whose end starts the boss fight, a boss HP threshold,
##   and a dormant exit pad woken at the end, completing an "event" quest.
## - Imported models: a glTF written at runtime loads back with collision;
##   files outside the level folder are refused.
## Runs on its own:
##   godot --headless --path . --script res://tests/level_test.gd

const DEMO := "res://levels/test_1/demo"

var _level: DataLevel
var _player: Player
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_data_checks()
	_map_checks()
	_asset_checks()
	_shape_checks()
	await _play_demo()
	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- LevelData ----------------------------------------------------------------------------

func _data_checks() -> void:
	var demo := LevelData.load_dir(DEMO)
	_check("the demo level loads", demo != null)
	if demo == null:
		return
	_check("it's Small (from its 5 rooms) with 4 corridors", demo.size() == "small"
		and demo.room_count() == 5 and demo.corridor_count() == 4)
	_check("its rooms are found from the navmesh", demo.area_at(Vector3(0, 0, -26)) == "room_2"
		and demo.area_at(Vector3(0, 0, -12)) == "hall_1" and demo.area_at(Vector3(0, 0, -54)) == "room_3"
		and demo.area_at(Vector3(40, 0, 0)) == "")
	var problems := demo.validate(Enemy.known_ids())
	_check("it passes the publish check (%s)" % ", ".join(problems), problems.is_empty())

	var arena := LevelData.create("Pit")
	var poly := [[[-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1]]]
	arena.map.areas = [{"id": "r", "kind": "room", "polys": poly}, {"id": "c", "kind": "corridor", "polys": poly}]
	var p := "\n".join(arena.validate())
	_check("one room makes an Arena", arena.size() == "arena")
	_check("an Arena with a corridor fails", p.contains("no corridors"))
	_check("a level without an exit fails", p.contains("No exit"))
	arena.map.areas.append({"id": "r2", "kind": "room", "polys": poly})
	_check("two rooms fit no size", arena.size() == "" and "\n".join(arena.validate()).contains("fits no size"))
	for i in 3:
		arena.map.areas.append({"id": "r%d" % (i + 3), "kind": "room", "polys": poly})
	_check("five rooms make a Small level", arena.size() == "small")
	var piece := {"id": "x", "asset": "builtin:box", "surface": "obstacle", "animation": {"preset": "spin"}}
	arena.map.pieces = [piece]
	_check("solid pieces can't be animated", "\n".join(arena.validate()).contains("Only intangible pieces can move"))

	var ok := {"id": "e", "enemy": "grub_hound", "wander": true, "wander_radius": 4.0,
		"limited_chase": true, "chase_radius": 6.0}
	_check("chase radius above wander radius is fine", LevelData.placement_problem(ok) == "")
	var bad := ok.duplicate()
	bad.chase_radius = 3.0
	_check("chase radius below wander radius is invalid",
		LevelData.placement_problem(bad).contains("smaller than wander radius"))
	bad.limited_chase = false
	_check("but only when both leashes are on", LevelData.placement_problem(bad) == "")
	var lit := LevelData.clamp_lighting({"preset": "nope", "ambient_energy": 0.0, "sun_energy": 9.0})
	_check("lighting is kept to safe ranges", lit.preset == "day" and lit.ambient_energy == 0.5
		and lit.sun_energy == 1.6)

	var dir := "user://test_levels/roundtrip"
	demo.meta.name = "Copy"
	_check("a level saves", demo.save_dir(dir) == OK)
	var back := LevelData.load_dir(dir)
	_check("and loads back the same", back != null and back.meta.name == "Copy"
		and back.placements().size() == demo.placements().size()
		and back.interaction.rules.size() == demo.interaction.rules.size())


# --- Maps ---------------------------------------------------------------------------------

## Curved walls, stairs and materials (Grayson, 2026-11-13).
func _shape_checks() -> void:
	# Stairs: 2 m up over 6 m. Three steps (0.67 m each) are too tall to walk;
	# eight (0.25 m) make a path from the bottom to the top.
	for spec in [[3, false], [8, true]]:
		var lv := LevelData.create("Stairs")
		lv.map.pieces = [
			{"id": "ground", "asset": "builtin:box", "size": [6, 0.5, 20], "pos": [0, -0.5, 0], "surface": "floor"},
			{"id": "stairs", "asset": "builtin:stairs", "size": [4, 2, 6], "steps": spec[0], "pos": [0, 0, 0], "surface": "floor"},
			{"id": "deck", "asset": "builtin:box", "size": [6, 0.5, 6], "pos": [0, 1.5, -6], "surface": "floor"}]
		var nm := LevelNav.bake(lv, Callable())
		var bottom := -1
		var top := -1
		var isl := LevelNav.islands(nm)
		for i in isl.size():
			if LevelNav._island_has(isl[i], Vector3(0, 0, 7)):
				bottom = i
			if LevelNav._island_has(isl[i], Vector3(0, 2, -6)):
				top = i
		_check("stairs with %d steps %s" % [spec[0], "connect the two floors" if spec[1] else "are too steep to walk"],
			bottom >= 0 and top >= 0 and (bottom == top) == spec[1])
	var stairs := LevelNav.builtin_meshes("builtin:stairs", Vector3(4, 2, 6), {"steps": 8})
	_check("stairs are one box per step", stairs.size() == 8 and is_equal_approx((stairs[7][0] as BoxMesh).size.y, 2.0))
	# Curved walls: 90 degrees over 8 m of length.
	var wall: Array = LevelNav.builtin_meshes("builtin:curved_wall", Vector3(8, 3, 0.5), {"bend": 90.0})
	var mesh: ArrayMesh = wall[0][0]
	var box := mesh.get_aabb()
	var radius := 8.0 / (PI * 0.5)
	_check("a 90° curved wall spans its arc (%s)" % box, is_equal_approx(box.size.y, 3.0)
		and absf(box.size.x - (2.0 * (radius + 0.25) * sin(PI * 0.25))) < 0.05)
	var faces := mesh.get_faces()
	var outward := 0
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0, verts.size(), 3):
		var face_n := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i])  # Godot faces are clockwise
		if face_n.dot(normals[i] + normals[i + 1] + normals[i + 2]) > 0.0:
			outward += 1
	_check("its faces all face outward (%d of %d)" % [outward, verts.size() / 3], outward == verts.size() / 3 and faces.size() > 0)
	_check("no bend makes a straight wall", LevelNav.builtin_meshes("builtin:curved_wall", Vector3(8, 3, 0.5), {"bend": 0.0})[0][0] is BoxMesh)
	var lv := LevelData.create("Curve")
	lv.map.pieces = [{"id": "c", "asset": "builtin:curved_wall", "size": [8, 3, 0.5], "bend": 90.0, "pos": [0, 0, 0], "surface": "obstacle"}]
	var hit := LevelNav.hitbox(lv.map.pieces[0], lv, Callable())
	_check("a curved wall gets an exact (concave) hitbox", hit.shapes.size() == 1 and hit.shapes[0][0] is ConcavePolygonShape3D)
	lv.map.pieces[0].bend = 400.0
	lv.map.pieces.append({"id": "s", "asset": "builtin:stairs", "steps": 0})
	var problems := "\n".join(lv.validate())
	_check("bends over 360° and stairs with no steps are refused", problems.contains("bends at most") and problems.contains("need 1-"))

	# Materials: an image in the level folder, tiled in world space.
	var dir := "user://material_test"
	DirAccess.make_dir_recursive_absolute(dir + "/assets")
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.3))
	img.save_png(dir + "/assets/moss.png")
	var level := LevelData.create("Mats")
	level.dir = ProjectSettings.globalize_path(dir)
	level.map.materials = [{"id": "moss", "albedo": "assets/moss.png", "tile": 2.0, "roughness": 0.7},
		{"id": "sneaky", "albedo": "../../secret.png"}]
	var mat := LevelMaterials.build(level, "moss")
	_check("a material loads its image from the level folder", mat != null and mat.albedo_texture != null
		and mat.uv1_world_triplanar and is_equal_approx(mat.uv1_scale.x, 0.5) and is_equal_approx(mat.roughness, 0.7))
	var sneaky := LevelMaterials.build(level, "sneaky")
	_check("but never from outside it", sneaky != null and sneaky.albedo_texture == null)
	var shape := LevelAssets.builtin("builtin:box", Vector3(2, 2, 2), Color.WHITE, {}, mat)
	_check("shapes wear a material", (shape.get_child(0) as MeshInstance3D).material_override == mat)
	shape.free()
	level.map.pieces = [{"id": "p", "asset": "builtin:box", "material": "nope"}]
	problems = "\n".join(level.validate())
	_check("the check catches missing materials and unsafe images",
		problems.contains("isn't in the level (nope)") and problems.contains("Material sneaky: its albedo image"))
	level.map.materials[0].erase("license")
	level.map.materials[0].erase("author")
	_check("licenses aren't required", not "\n".join(level.validate()).contains("license"))
	# Every map: a glTF-style packed image (occlusion, roughness, metallic), glow,
	# cut-out transparency, and a height map on UV mapping.
	level.map.materials.append({"id": "full", "albedo": "assets/moss.png", "normal": "assets/moss.png", "normal_strength": 2.0,
		"roughness": 1.0, "roughness_map": "assets/moss.png", "roughness_channel": "green",
		"metallic": 1.0, "metallic_map": "assets/moss.png", "metallic_channel": "blue",
		"ao_map": "assets/moss.png", "ao_channel": "red", "ao_strength": 0.5,
		"emission": [1, 0.5, 0], "emission_energy": 3.0, "emission_map": "assets/moss.png",
		"transparency": "cutout", "alpha_cutoff": 0.4, "opacity": 0.9,
		"mapping": "uv", "uv_repeat": 2.0, "height_map": "assets/moss.png", "height_scale": 3.0})
	var full := LevelMaterials.build(level, "full")
	_check("roughness and metallic maps read their channel", full.roughness_texture != null and full.metallic_texture != null
		and full.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN and full.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE)
	_check("ambient occlusion", full.ao_enabled and full.ao_texture != null and full.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
		and is_equal_approx(full.ao_light_affect, 0.5))
	_check("glow", full.emission_enabled and full.emission_texture != null and is_equal_approx(full.emission_energy_multiplier, 3.0)
		and full.emission.is_equal_approx(Color(1, 0.5, 0)))
	_check("cut-out transparency", full.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(full.alpha_scissor_threshold, 0.4)
		and is_equal_approx(full.albedo_color.a, 0.9) and is_equal_approx(full.normal_scale, 2.0))
	_check("UV mapping with a height map", not full.uv1_triplanar and is_equal_approx(full.uv1_scale.x, 2.0)
		and full.heightmap_enabled and is_equal_approx(full.heightmap_scale, 3.0))
	level.map.materials[2].mapping = "world"
	_check("height maps need UV mapping (Godot can't do them triplanar)", not LevelMaterials.build(level, "full").heightmap_enabled)
	level.map.materials[2].merge({"transparency": "glass", "ao_channel": "purple", "emission_map": "../x.png"}, true)
	problems = "\n".join(level.validate())
	_check("and the check catches bad settings", problems.contains("transparency must be") and problems.contains("ao_channel must be")
		and problems.contains("emission_map image"))


func _map_checks() -> void:
	_check("res://levels/test_1 is an area", Maps.areas().has("test_1"))
	Maps.new_session()
	var first := Maps.resolve("area:test_1")
	_check("an area resolves to one of its levels (%s)" % first, first == DEMO)
	_check("and keeps that pick for the session", Maps.resolve("area:test_1") == first
		and Maps.picks.has("test_1"))
	Maps.new_session()
	_check("a new session picks again", not Maps.picks.has("test_1"))
	_check("\"hub\" is Nomad-2", Maps.resolve("hub") == Session.HUB_SCENE)
	_check("scenes and level folders are told apart", Maps.is_data(DEMO) and not Maps.is_data("res://scenes/arena.tscn"))
	_check("an unknown area resolves to nothing", Maps.resolve("area:nowhere") == "")
	QuestBook.reload()
	var quest := QuestBook.get_quest(&"demo_run")
	_check("quests load from res://quests (%s)" % quest.get("title", "none"), quest.get("objective") == "event")


# --- Imported assets --------------------------------------------------------------------------

func _asset_checks() -> void:
	var dir := "user://test_levels/assets_level"
	DirAccess.make_dir_recursive_absolute(dir.path_join("assets"))
	var scene := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 1, 3)
	mi.mesh = bm
	mi.position = Vector3(0, 0.5, 0)
	scene.add_child(mi)
	mi.owner = scene
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(scene, state)
	var written := doc.write_to_filesystem(state, dir.path_join("assets/crate.glb"))
	scene.free()
	_check("a glb can be written (%s)" % error_string(written), written == OK)
	var level := LevelData.create("Assets")
	level.dir = dir
	level.map.assets = [{"id": "crate", "file": "assets/crate.glb"},
		{"id": "sneaky", "file": "../../outside.glb"},
		{"id": "scene", "file": "assets/thing.tscn"}]
	LevelAssets.clear_cache()
	var model := LevelAssets.model(level, "crate")
	_check("an imported glb loads at runtime", model != null and model.find_children("*", "MeshInstance3D").size() == 1)
	if model:
		LevelAssets.add_collision(model, "concave")
		var body := model.get_node_or_null("Collision") as StaticBody3D
		var shape := body.get_child(0) as CollisionShape3D if body and body.get_child_count() > 0 else null
		_check("a concave hitbox follows the triangles", shape != null and shape.shape is ConcavePolygonShape3D
			and body.collision_layer == 1)
		model.free()
		model = LevelAssets.model(level, "crate")
		LevelAssets.add_collision(model, "convex")
		body = model.get_node_or_null("Collision") as StaticBody3D
		shape = body.get_child(0) as CollisionShape3D if body and body.get_child_count() > 0 else null
		_check("a convex hitbox is one hull", shape != null and shape.shape is ConvexPolygonShape3D)
		model.free()
		level.map.assets[0].surface = "obstacle"
		level.map.pieces = [{"id": "c1", "asset": "crate", "pos": [0, 0, 0]},
			{"id": "c2", "asset": "crate", "pos": [3, 0, 0], "surface": "floor"}]
		_check("a piece uses its model's surface unless it overrides it",
			level.surface_of(level.map.pieces[0]) == "obstacle" and level.surface_of(level.map.pieces[1]) == "floor")
	_check("files outside the level folder are refused", LevelAssets.model(level, "sneaky") == null)
	_check("only model files load (no scenes or scripts)", LevelAssets.model(level, "scene") == null)


# --- The demo level, played ------------------------------------------------------------------

func _play_demo() -> void:
	_level = Maps.instantiate(DEMO) as DataLevel
	root.add_child(_level)
	current_scene = _level
	_player = _level.player
	_player.use_save(SaveData.create("Tester", CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
		CharacterData.Job.STRIKER, 1))
	_player.autosave = false
	_check("its map id is its folder", Maps.id_of(_level) == DEMO)
	_check("the Seeker starts at map.json's start", _player.global_position.distance_to(Vector3(0, 0.1, 4)) < 0.5)
	_check("lighting was built", _level.get_node_or_null("WorldEnvironment") != null
		and _level.get_node_or_null("Sun") != null)
	_check("rooms and corridors have room areas", _level.rooms.size() == 9)
	await _frames(20)
	var ev := _level.events
	_check("level_started fired once the navmesh baked", ev.history.has("level_started:"))
	var nav_ok := NavigationServer3D.map_get_iteration_id(_player.get_world_3d().navigation_map) > 0
	_check("the navmesh baked from the pieces", nav_ok)

	# Dialogue zone: the Seeker starts inside it.
	var box := _dialogue()
	_check("walking into the zone started the hello dialogue", box != null and box.dialogue.id == "hello")
	_check("the reader takes no game input while it's open", _player.input_locked)
	if box:
		box._advance()
		box._advance()
	await _frames(2)
	_check("closing it reports dialogue_ended", ev.history.has("dialogue_ended:hello") and not _player.input_locked)

	# Button-opened gate.
	var gate := ev.objects["gate"] as SwitchDoor
	_check("the gate starts closed", not gate.is_open)
	(ev.objects["gate_button"] as RoomButton).press()
	await _frames(2)
	_check("its button opens it", gate.is_open)

	# Corridor enemy: wanders, then gives up a chase past its leash.
	var hound := ev.objects.get("hall_hound") as Enemy
	_check("the corridor hound is placed with its leashes", hound != null and hound.wander
		and hound.limited_chase and is_equal_approx(hound.chase_radius, 10.0))
	if hound:
		_check("it uses the short aggro range", is_equal_approx(hound.aggro_scale, 0.6))
		var home := hound.home
		await _frames(150)
		_check("it wanders near home (%.1f m away)" % hound.global_position.distance_to(home),
			hound.global_position.distance_to(home) <= hound.wander_radius + 1.0)
		hound._aggro = true
		hound.state = Enemy.State.CHASE
		await _place(Vector3(0, 0.1, -12 + 13))  # 13 m from its home: past the leash
		await _frames(4)
		_check("past its chase radius it gives up and heads home", hound.state == Enemy.State.RETURN
			or hound.state == Enemy.State.IDLE)
		await _place(Vector3(0, 0.1, 4))
		await _frames(240)
		_check("and is back home, idle (%.1f m)" % hound.global_position.distance_to(home),
			hound.state == Enemy.State.IDLE and hound.global_position.distance_to(home) < 2.0)
		hound.health.take_damage(_big_hit())

	# The arena: in-door shuts during the fight, out-door opens when cleared.
	var room_2 := ev.objects["room_2"] as WaveRoom
	var door_in := ev.objects["arena_in"] as SwitchDoor
	var door_out := ev.objects["arena_out"] as SwitchDoor
	await _place(Vector3(0, 0.1, -20))
	await _frames(10)
	_check("walking in starts the fight", room_2.state == WaveRoom.RoomState.ACTIVE
		and ev.history.has("combat_started:room_2"))
	_check("the way in shuts during it", not door_in.is_open)
	await _frames(60)
	_check("wave 1 has its two hounds", room_2.alive.size() == 2)
	await _kill_room(room_2)
	await _frames(100)  # 1 s between waves, then the drone at 0.5 s
	_check("wave 2 waits out its spawn delays (%d of 2 in)" % room_2.alive.size(), room_2.alive.size() == 1)
	await _frames(50)  # the ooze at 1.25 s
	_check("then both are in (%d)" % room_2.alive.size(), room_2.alive.size() == 2)
	await _kill_room(room_2)
	await _frames(4)
	_check("clearing it reports wave_cleared and combat_ended", ev.history.has("wave_cleared:room_2")
		and ev.history.has("combat_ended:room_2"))
	_check("and opens the way on and the way back", door_out.is_open and door_in.is_open)

	# Seeker-only wall.
	var pen := _level.find_child("Wall_arena_pen", true, false) as InvisibleWall
	_check("the Seeker-only wall stops Seekers, not enemies", pen != null
		and pen.collision_layer == InvisibleWall.SEEKER_WALL_LAYER
		and (_player.collision_mask & pen.collision_layer) != 0
		and (Enemy.WORLD_MASK | Enemy.ENEMY_LAYER) & pen.collision_layer == 0)

	# Floor plates extend the bridge.
	var bridge := ev.objects["bridge_1"] as Bridge
	_check("the bridge starts in, its nav link off", bridge.progress == 0.0 and not bridge.link.enabled)
	var nav_map := _player.get_world_3d().navigation_map
	var gap := NavigationServer3D.map_get_path(nav_map, Vector3(0, 0, -41.5), Vector3(0, 0, -54.5), true)
	_check("no path over the pit while it's in", gap.is_empty()
		or Vector2(gap[gap.size() - 1].x, gap[gap.size() - 1].z).distance_to(Vector2(0, -54.5)) > 3.0)
	var plate_a := ev.objects["plate_a"] as RoomButton
	var plate_b := ev.objects["plate_b"] as RoomButton
	plate_a._on_entered(_player)
	plate_a._on_exited(_player)
	plate_b._on_entered(_player)
	await _frames(2)
	_check("both plates fire the group (one latched alone)", ev.history.has("pressed:plates"))
	plate_b._on_exited(_player)
	await _frames(150)
	_check("the bridge is out and its nav link on", bridge.is_open() and bridge.link.enabled)
	await _frames(4)
	var map := _player.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, -41.5), Vector3(0, 0, -54.5), true)
	_check("enemies can path across it now (%d points, ends %.1f m off)" % [path.size(),
		path[path.size() - 1].distance_to(Vector3(0, 0, -54.5)) if not path.is_empty() else -1.0],
		not path.is_empty() and Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(Vector2(0, -54.5)) < 1.0)

	# The moving platform.
	var ferry := ev.objects["ferry"] as MovingPlatform
	var was := ferry.global_position
	await _frames(90)
	_check("the platform moves (%.2f m)" % ferry.global_position.distance_to(was),
		ferry.global_position.distance_to(was) > 0.5)

	# The mist button.
	var mist := ev.objects["mist"] as RoomHazard
	_check("the mist starts on", mist.active)
	(ev.objects["mist_button"] as RoomButton).press()
	await _frames(2)
	_check("its button turns it off", not mist.active)

	# The boss: whole party at the door -> holo-call -> fight.
	_player.save.quest = {}
	_check("the demo quest can be accepted", QuestBook.accept(_player.save, &"demo_run") == "")
	var room_5 := ev.objects["room_5"] as WaveRoom
	await _place(Vector3(0, 0.1, -90))
	await _frames(6)
	_check("the room doesn't start on entry (it waits for the call)", room_5.state == WaveRoom.RoomState.WAITING)
	box = _dialogue()
	_check("the whole party at the door starts the boss call", box != null and box.dialogue.id == "boss_intro")
	if box:
		box._advance()  # to the choices
		box._finish("ready")
	await _frames(70)
	_check("its end starts the fight", room_5.state == WaveRoom.RoomState.ACTIVE)
	var boss := ev.objects.get("boss") as Enemy
	_check("the boss is out", boss != null)
	if boss:
		var hit := _big_hit()
		hit.amount = boss.health.max_hp * 0.6
		boss.health.take_damage(hit)
		await _frames(2)
		_check("below 50% HP the enrage rule runs", ev.flags.get("enraged") == true)
	var exit := ev.objects["exit"] as Teleporter
	_check("the exit pad is asleep", exit.dormant and not exit.is_active())
	await _kill_room(room_5)
	await _frames(110)
	await _kill_room(room_5)
	await _frames(80)
	_check("beating the boss room wakes the exit", ev.history.has("combat_ended:room_5")
		and not exit.dormant and exit.is_active())
	_check("and completes the event quest", QuestBook.is_complete(_player.save))
	_check("the exit goes to Nomad-2", Maps.resolve(exit.destination) == Session.HUB_SCENE)


# --- Helpers ---------------------------------------------------------------------------------

func _dialogue() -> DialogueBox:
	var boxes := get_nodes_in_group("dialogue_boxes")
	return boxes[0] as DialogueBox if not boxes.is_empty() else null


func _kill_room(room: WaveRoom) -> void:
	for enemy in room.alive.duplicate():
		if is_instance_valid(enemy):
			enemy.health.take_damage(_big_hit())
	await _frames(2)


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


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
