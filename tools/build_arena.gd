extends SceneTree
## Builds scenes/arena.tscn: a start corridor and two PSO-style wave rooms,
## so Godot writes the scene file itself. After generating, edit the scene in
## the editor (rerunning this overwrites it):
##   godot --headless --path . --script res://tools/build_arena.gd
##
## Layout (looking north, -Z):
##   Start (z 24..12) -> Room A (z 11..-11, three waves) -> corridor ->
##   Room B (z -19..-41, two waves)

const ENEMY_DIR := "res://data/enemies/"
const WALL_H := 4.0

var _root: Node3D
var _level: Node3D
var _mats := {}


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "Arena"
	_root.set_script(load("res://scripts/main.gd"))

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.3, 0.45)
	sky_mat.sky_horizon_color = Color(0.55, 0.5, 0.5)
	sky_mat.ground_horizon_color = Color(0.55, 0.5, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	_add(_root, env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	_add(_root, sun)

	var nav := NavigationRegion3D.new()
	nav.name = "Navigation"
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1
	navmesh.agent_height = 2.0
	navmesh.agent_radius = 0.5
	navmesh.agent_max_climb = 0.25
	nav.navigation_mesh = navmesh
	_add(_root, nav)
	_level = Node3D.new()
	_level.name = "Level"
	_add(nav, _level)

	_build_level()

	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	player.name = "Player"
	_add(_root, player)
	player.position = Vector3(0.0, 0.1, 20.0)
	var rig := (load("res://scenes/camera/camera_rig.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	rig.name = "CameraRig"
	_add(_root, rig)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	hud.name = "HUD"
	_add(_root, hud)

	var rooms := Node3D.new()
	rooms.name = "Rooms"
	_add(_root, rooms)
	_room(rooms, "RoomA", "Room A", Vector3(0, 0, 0), [Vector3(0, 0, 11), Vector3(0, 0, -11)], [
		["grub_hound", "grub_hound", "grub_hound"],
		["mutated_crawler", "mutated_crawler", "sentry_drone"],
		["caustic_ooze", "lumen_sprite", "lumen_sprite"]])
	_room(rooms, "RoomB", "Room B", Vector3(0, 0, -30), [Vector3(0, 0, 11)], [
		["umbral_eye", "umbral_eye", "grub_hound", "grub_hound"],
		["grub_hound", "mutated_crawler", "sentry_drone", "umbral_eye", "caustic_ooze", "lumen_sprite"]])

	# Part 5: Lumidium deposits and teleporters (deposit pads).
	var gather := Node3D.new()
	gather.name = "Gathering"
	_add(_root, gather)
	for spec in [["NodeStart", &"fire", Vector3(-1.8, 0, 13)], ["NodeA1", &"ice", Vector3(-8.5, 0, 8.5)],
			["NodeA2", &"lightning", Vector3(8.5, 0, -8.5)], ["NodeB1", &"dark", Vector3(-8.5, 0, -38.5)],
			["NodeB2", &"raw", Vector3(8.5, 0, -21.5)]]:
		var node := StaticBody3D.new()
		node.name = spec[0]
		node.set_script(load("res://scripts/world/lumidium_node.gd"))
		node.set("color", spec[1])
		node.position = spec[2]
		_add(gather, node)
	for spec in [["TeleporterStart", Vector3(0, 0, 16.5)], ["TeleporterB", Vector3(-8, 0, -24)]]:
		var pad := Area3D.new()
		pad.name = spec[0]
		pad.set_script(load("res://scripts/world/teleporter.gd"))
		pad.position = spec[1]
		_add(gather, pad)
	# Part 6: hidden PSO-style floor traps (Goluman see them).
	var hazards := Node3D.new()
	hazards.name = "Hazards"
	_add(_root, hazards)
	for spec in [["HazardConfuse", 5, Vector3(1.6, 0, 9.5)], ["HazardSlow", 2, Vector3(5.0, 0, 3.0)],
			["HazardDamage", 0, Vector3(1.2, 0, -15.0)], ["HazardParalyze", 6, Vector3(-1.2, 0, -17.0)],
			["HazardPoison", 4, Vector3(-4.0, 0, -29.0)], ["HazardFreeze", 1, Vector3(4.0, 0, -34.0)]]:
		var hazard := Area3D.new()
		hazard.name = spec[0]
		hazard.set_script(load("res://scripts/world/hazard_trap.gd"))
		hazard.set("kind", spec[1])
		hazard.position = spec[2]
		_add(hazards, hazard)

	# The end of the arena: back to Nomad-2 once every room is cleared.
	var exit := Area3D.new()
	exit.name = "TeleporterExit"
	exit.set_script(load("res://scripts/world/teleporter.gd"))
	exit.set("destination", "res://scenes/hub.tscn")
	exit.set("destination_name", "Back to Nomad-2")
	exit.set("requires_rooms_cleared", true)
	exit.position = Vector3(0, 0, -37)
	_add(gather, exit)

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, "res://scenes/arena.tscn")
	print("res://scenes/arena.tscn -> %s" % error_string(err))
	_root.free()
	quit()


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root
	for c in child.get_children():
		if c.owner == null:
			c.owner = _root


func _mat(key: String, base: Color, line: Color) -> ShaderMaterial:
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/blockout_grid.gdshader")
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("line_color", line)
		_mats[key] = m
	return _mats[key]


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material, collide := true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = name
	b.size = size
	b.position = pos
	b.use_collision = collide
	b.material = mat
	_add(parent, b)
	return b


func _build_level() -> void:
	var floor_mat := _mat("floor", Color(0.4, 0.4, 0.44), Color(0.3, 0.3, 0.34))
	var wall_mat := _mat("wall", Color(0.33, 0.36, 0.48), Color(0.24, 0.26, 0.36))
	_box(_level, "Floor", Vector3(30, 1, 72), Vector3(0, -0.5, -9), floor_mat)

	# Start corridor
	_box(_level, "StartWallW", Vector3(1, WALL_H, 13), Vector3(-3, WALL_H / 2, 18), wall_mat)
	_box(_level, "StartWallE", Vector3(1, WALL_H, 13), Vector3(3, WALL_H / 2, 18), wall_mat)
	_box(_level, "StartBack", Vector3(7, WALL_H, 1), Vector3(0, WALL_H / 2, 24.5), wall_mat)

	# Rooms: 22 x 22 interiors with 4 m doorways
	for spec in [["A", 0.0, true, true], ["B", -30.0, true, false]]:
		var z: float = spec[1]
		var tag: String = spec[0]
		_box(_level, "Room%sWallW" % tag, Vector3(1, WALL_H, 23), Vector3(-11.5, WALL_H / 2, z), wall_mat)
		_box(_level, "Room%sWallE" % tag, Vector3(1, WALL_H, 23), Vector3(11.5, WALL_H / 2, z), wall_mat)
		for side in [[11.0, spec[2], "S"], [-11.0, spec[3], "N"]]:
			var wz: float = z + side[0]
			if side[1]:  # doorway
				_box(_level, "Room%sWall%sL" % [tag, side[2]], Vector3(10, WALL_H, 1), Vector3(-7, WALL_H / 2, wz), wall_mat)
				_box(_level, "Room%sWall%sR" % [tag, side[2]], Vector3(10, WALL_H, 1), Vector3(7, WALL_H / 2, wz), wall_mat)
			else:
				_box(_level, "Room%sWall%s" % [tag, side[2]], Vector3(24, WALL_H, 1), Vector3(0, WALL_H / 2, wz), wall_mat)
		# A couple of pillars to fight around (and to block line of sight)
		_box(_level, "Room%sPillarL" % tag, Vector3(1.5, WALL_H, 1.5), Vector3(-5, WALL_H / 2, z + 2), wall_mat)
		_box(_level, "Room%sPillarR" % tag, Vector3(1.5, WALL_H, 1.5), Vector3(5, WALL_H / 2, z - 2), wall_mat)

	# Corridor between the rooms
	_box(_level, "CorridorW", Vector3(1, WALL_H, 8), Vector3(-2.5, WALL_H / 2, -15), wall_mat)
	_box(_level, "CorridorE", Vector3(1, WALL_H, 8), Vector3(2.5, WALL_H / 2, -15), wall_mat)


func _room(parent: Node, node_name: String, title: String, center: Vector3,
		door_offsets: Array, wave_specs: Array) -> void:
	var room := Node3D.new()
	room.name = node_name
	room.set_script(load("res://scripts/rooms/wave_room.gd"))
	room.set("room_name", title)
	room.set("trigger_size", Vector3(20.0, 4.0, 19.0))
	var waves: Array[WaveData] = []
	for spec in wave_specs:
		var w := WaveData.new()
		for file in spec:
			w.enemies.append(load(ENEMY_DIR + file + ".tres"))
		waves.append(w)
	room.set("waves", waves)
	room.position = center
	_add(parent, room)

	var doors := Node3D.new()
	doors.name = "Doors"
	_add(room, doors)
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.9, 0.35, 0.2, 0.75)
	door_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	door_mat.emission_enabled = true
	door_mat.emission = Color(0.9, 0.3, 0.15)
	for i in door_offsets.size():
		_box(doors, "Door%d" % i, Vector3(4.2, WALL_H, 0.6), door_offsets[i] + Vector3(0, WALL_H / 2, 0), door_mat)

	var points := Node3D.new()
	points.name = "SpawnPoints"
	_add(room, points)
	for p in [Vector3(-7, 0, -6), Vector3(7, 0, -6), Vector3(0, 0, -8), Vector3(-8, 0, 1), Vector3(8, 0, 1), Vector3(0, 0, -3)]:
		var m := Marker3D.new()
		m.name = "Spawn%d" % points.get_child_count()
		m.position = p
		_add(points, m)
