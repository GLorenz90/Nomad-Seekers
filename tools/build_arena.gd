extends SceneTree
## Builds scenes/arena.tscn: a start corridor and two PSO-style wave rooms,
## so Godot writes the scene file itself. After generating, edit the scene in
## the editor (rerunning this overwrites it):
##   godot --headless --path . --script res://tools/build_arena.gd
##
## Layout (looking north, -Z):
##   Start (z 24..12) -> Room A (z 11..-11, three waves) -> corridor ->
##   Room B (z -19..-41, two waves)
## Part 11 east wing (Grayson 2026-11-09: PSO hazards and buttons), through
## Room B's east doorway:
##   Poison room (x 19..41): poison mist (spans the corridor too); a button
##     opens its east door and clears the mist.
##   Its north doorway branches to the switch hall: four floor plates open the
##     door to a Lumidium alcove.
##   Dark room (x 49..71, two waves): darkness; the button in the far corner
##     turns it off; its north door opens when every enemy is dead, to the
##     end room's teleporter.

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
	# PSO-style doors: the way in stays open; the way on is locked until the
	# room is cleared. Room B is the last room: clearing it wakes the exit pad.
	_room(rooms, "RoomA", "Room A", Vector3(0, 0, 0), [Vector3(0, 0, -11)], [
		["grub_hound", "grub_hound", "grub_hound"],
		["mutated_crawler", "mutated_crawler", "sentry_drone"],
		["caustic_ooze", "lumen_sprite", "lumen_sprite"]])
	_room(rooms, "RoomB", "Room B", Vector3(0, 0, -30), [], [
		["umbral_eye", "umbral_eye", "grub_hound", "grub_hound"],
		["grub_hound", "mutated_crawler", "sentry_drone", "umbral_eye", "caustic_ooze", "lumen_sprite"]])
	_room(rooms, "RoomD", "Dark Room", Vector3(60, 0, -30), [Vector3(0, 0, -11)], [
		["grub_hound", "grub_hound", "umbral_eye"],
		["mutated_crawler", "lumen_sprite", "grub_hound"]])

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
	# Lumidium depots (Grayson, 2026-11-10): at the start and at each exit.
	for spec in [["DepotStart", Vector3(0, 0, 16.5)], ["DepotExit", Vector3(3.5, 0, -36)],
			["DepotEnd", Vector3(63.5, 0, -48)]]:
		var depot := Node3D.new()
		depot.name = spec[0]
		depot.set_script(load("res://scripts/world/lumidium_depot.gd"))
		depot.position = spec[1]
		_add(gather, depot)
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

	_build_east_wing(gather)

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
		if tag == "B":  # Part 11: a doorway east to the poison room
			_wall_x("RoomBWallE", 11.5, z - 11.5, z + 11.5, z, wall_mat)
		else:
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


## A wall along Z at `x` from z0 to z1, with a 4 m doorway centred on door_z
## (NAN = solid).
func _wall_x(node_name: String, x: float, z0: float, z1: float, door_z: float, mat: Material) -> void:
	var lo := minf(z0, z1)
	var hi := maxf(z0, z1)
	if is_nan(door_z):
		_box(_level, node_name, Vector3(1, WALL_H, hi - lo), Vector3(x, WALL_H / 2, (lo + hi) / 2.0), mat)
		return
	var a := door_z - 2.0
	var b := door_z + 2.0
	_box(_level, node_name + "A", Vector3(1, WALL_H, a - lo), Vector3(x, WALL_H / 2, (lo + a) / 2.0), mat)
	_box(_level, node_name + "B", Vector3(1, WALL_H, hi - b), Vector3(x, WALL_H / 2, (b + hi) / 2.0), mat)


## A wall along X at `z` from x0 to x1, with a 4 m doorway centred on door_x.
func _wall_z(node_name: String, z: float, x0: float, x1: float, door_x: float, mat: Material) -> void:
	var lo := minf(x0, x1)
	var hi := maxf(x0, x1)
	if is_nan(door_x):
		_box(_level, node_name, Vector3(hi - lo, WALL_H, 1), Vector3((lo + hi) / 2.0, WALL_H / 2, z), mat)
		return
	var a := door_x - 2.0
	var b := door_x + 2.0
	_box(_level, node_name + "A", Vector3(a - lo, WALL_H, 1), Vector3((lo + a) / 2.0, WALL_H / 2, z), mat)
	_box(_level, node_name + "B", Vector3(hi - b, WALL_H, 1), Vector3((b + hi) / 2.0, WALL_H / 2, z), mat)


## Part 11: the east wing's walls, hazards, doors, buttons and switch groups.
func _build_east_wing(gather: Node) -> void:
	var floor_mat := _mat("floor", Color(0.4, 0.4, 0.44), Color(0.3, 0.3, 0.34))
	var wall_mat := _mat("wall", Color(0.33, 0.36, 0.48), Color(0.24, 0.26, 0.36))
	_box(_level, "FloorEast", Vector3(64, 1, 66), Vector3(44, -0.5, -46), floor_mat)
	# Corridor Room B -> poison room.
	_box(_level, "CorridorPS", Vector3(7, WALL_H, 1), Vector3(15.5, WALL_H / 2, -27.5), wall_mat)
	_box(_level, "CorridorPN", Vector3(7, WALL_H, 1), Vector3(15.5, WALL_H / 2, -32.5), wall_mat)
	# Poison room, interior x 19..41, z -41..-19.
	_wall_x("PoisonWallW", 18.5, -41.5, -18.5, -30.0, wall_mat)
	_wall_x("PoisonWallE", 41.5, -41.5, -18.5, -30.0, wall_mat)
	_wall_z("PoisonWallS", -18.5, 18.0, 42.0, NAN, wall_mat)
	_wall_z("PoisonWallN", -41.5, 18.0, 42.0, 30.0, wall_mat)
	# Branch north: corridor, then the switch hall (x 19..41, z -69..-47).
	_box(_level, "BranchW", Vector3(1, WALL_H, 5), Vector3(27.5, WALL_H / 2, -44.5), wall_mat)
	_box(_level, "BranchE", Vector3(1, WALL_H, 5), Vector3(32.5, WALL_H / 2, -44.5), wall_mat)
	_wall_z("HallWallS", -46.5, 18.0, 42.0, 30.0, wall_mat)
	_wall_z("HallWallN", -69.5, 18.0, 42.0, 30.0, wall_mat)
	_wall_x("HallWallW", 18.5, -70.0, -46.0, NAN, wall_mat)
	_wall_x("HallWallE", 41.5, -70.0, -46.0, NAN, wall_mat)
	# The alcove behind the hall's north door.
	_box(_level, "AlcoveW", Vector3(1, WALL_H, 8), Vector3(25.5, WALL_H / 2, -74), wall_mat)
	_box(_level, "AlcoveE", Vector3(1, WALL_H, 8), Vector3(34.5, WALL_H / 2, -74), wall_mat)
	_box(_level, "AlcoveN", Vector3(10, WALL_H, 1), Vector3(30, WALL_H / 2, -78.5), wall_mat)
	# Corridor poison room -> dark room.
	_box(_level, "CorridorDS", Vector3(7, WALL_H, 1), Vector3(45.5, WALL_H / 2, -27.5), wall_mat)
	_box(_level, "CorridorDN", Vector3(7, WALL_H, 1), Vector3(45.5, WALL_H / 2, -32.5), wall_mat)
	# Dark room, interior x 49..71, z -41..-19; its north doorway is the
	# wave room's exit door.
	_wall_x("DarkWallW", 48.5, -41.5, -18.5, -30.0, wall_mat)
	_wall_x("DarkWallE", 71.5, -41.5, -18.5, NAN, wall_mat)
	_wall_z("DarkWallS", -18.5, 48.0, 72.0, NAN, wall_mat)
	_wall_z("DarkWallN", -41.5, 48.0, 72.0, 60.0, wall_mat)
	_box(_level, "DarkPillar", Vector3(1.5, WALL_H, 1.5), Vector3(56, WALL_H / 2, -26), wall_mat)
	# The end room beyond it.
	_box(_level, "EndW", Vector3(1, WALL_H, 10), Vector3(53.5, WALL_H / 2, -47), wall_mat)
	_box(_level, "EndE", Vector3(1, WALL_H, 10), Vector3(66.5, WALL_H / 2, -47), wall_mat)
	_box(_level, "EndN", Vector3(14, WALL_H, 1), Vector3(60, WALL_H / 2, -52.5), wall_mat)

	# Hazards: poison mist over the poison room and its corridor (one hazard,
	# two boxes); darkness over the dark room.
	var hazards := Node3D.new()
	hazards.name = "RoomHazards"
	_add(_root, hazards)
	var mist := Node3D.new()
	mist.name = "PoisonMist"
	mist.set_script(load("res://scripts/world/room_hazard.gd"))
	mist.set("kind", 0)
	var mist_zones: Array[AABB] = [AABB(Vector3(19, 0, -41), Vector3(22, WALL_H, 22)), AABB(Vector3(12, 0, -32), Vector3(7, WALL_H, 4))]
	mist.set("zones", mist_zones)
	_add(hazards, mist)
	var dark := Node3D.new()
	dark.name = "Darkness"
	dark.set_script(load("res://scripts/world/room_hazard.gd"))
	dark.set("kind", 1)
	var dark_zones: Array[AABB] = [AABB(Vector3(49, 0, -41), Vector3(22, WALL_H, 22))]
	dark.set("zones", dark_zones)
	_add(hazards, dark)

	# Doors buttons open (outside the Navigation region).
	var doors := Node3D.new()
	doors.name = "SwitchDoors"
	_add(_root, doors)
	var poison_door := StaticBody3D.new()
	poison_door.name = "PoisonDoor"
	poison_door.set_script(load("res://scripts/world/switch_door.gd"))
	poison_door.set("size", Vector3(0.6, WALL_H, 4.2))
	poison_door.set("label", "LOCKED\npress the button")
	poison_door.position = Vector3(41.5, 0, -30)
	_add(doors, poison_door)
	var hall_door := StaticBody3D.new()
	hall_door.name = "HallDoor"
	hall_door.set_script(load("res://scripts/world/switch_door.gd"))
	hall_door.set("label", "LOCKED\nfour plates")
	hall_door.position = Vector3(30, 0, -69.5)
	_add(doors, hall_door)

	# Buttons.
	var buttons := Node3D.new()
	buttons.name = "Buttons"
	_add(_root, buttons)
	for spec in [["PoisonButton", 0, Vector3(38, 0, -22)], ["DarkButton", 0, Vector3(69.2, 0, -38.8)],
			["Plate1", 1, Vector3(22, 0, -50)], ["Plate2", 1, Vector3(38, 0, -50)],
			["Plate3", 1, Vector3(22, 0, -66)], ["Plate4", 1, Vector3(38, 0, -66)]]:
		var b := Area3D.new()
		b.name = spec[0]
		b.set_script(load("res://scripts/world/room_button.gd"))
		b.set("mode", spec[1])
		b.position = spec[2]
		_add(buttons, b)

	# What each button set does (paths from Switches/<group>).
	var switches := Node3D.new()
	switches.name = "Switches"
	_add(_root, switches)
	_switch(switches, "PoisonSwitch", ["../../Buttons/PoisonButton"],
		["../../SwitchDoors/PoisonDoor", "../../RoomHazards/PoisonMist"], ["open", "disable"])
	_switch(switches, "HallSwitch", ["../../Buttons/Plate1", "../../Buttons/Plate2", "../../Buttons/Plate3", "../../Buttons/Plate4"],
		["../../SwitchDoors/HallDoor"], ["open"])
	_switch(switches, "DarkSwitch", ["../../Buttons/DarkButton"], ["../../RoomHazards/Darkness"], ["disable"])

	# The alcove's reward and the end room's way home.
	for spec in [["NodeAlcove1", &"light", Vector3(28, 0, -75)], ["NodeAlcove2", &"nature", Vector3(32, 0, -75)]]:
		var node := StaticBody3D.new()
		node.name = spec[0]
		node.set_script(load("res://scripts/world/lumidium_node.gd"))
		node.set("color", spec[1])
		node.position = spec[2]
		_add(gather, node)
	var end := Area3D.new()
	end.name = "TeleporterEnd"
	end.set_script(load("res://scripts/world/teleporter.gd"))
	end.set("destination", "res://scenes/hub.tscn")
	end.set("destination_name", "Back to Nomad-2")
	end.set("requires_rooms_cleared", true)
	end.position = Vector3(60, 0, -49)
	_add(gather, end)


func _switch(parent: Node, node_name: String, button_paths: Array, target_paths: Array, actions: Array) -> void:
	var g := Node.new()
	g.name = node_name
	g.set_script(load("res://scripts/world/switch_group.gd"))
	var bp: Array[NodePath] = []
	for p in button_paths:
		bp.append(NodePath(p))
	var tp: Array[NodePath] = []
	for p in target_paths:
		tp.append(NodePath(p))
	g.set("buttons", bp)
	g.set("targets", tp)
	g.set("actions", PackedStringArray(actions))
	_add(parent, g)


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
		var door := _box(doors, "ExitDoor%d" % i, Vector3(4.2, WALL_H, 0.6), door_offsets[i] + Vector3(0, WALL_H / 2, 0), door_mat)
		var sign := Label3D.new()
		sign.name = "Locked"
		sign.text = "LOCKED\nclear the room"
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.font_size = 48
		sign.outline_size = 10
		sign.position = Vector3(0, 0.2, 0.6)
		_add(door, sign)

	var points := Node3D.new()
	points.name = "SpawnPoints"
	_add(room, points)
	for p in [Vector3(-7, 0, -6), Vector3(7, 0, -6), Vector3(0, 0, -8), Vector3(-8, 0, 1), Vector3(8, 0, 1), Vector3(0, 0, -3)]:
		var m := Marker3D.new()
		m.name = "Spawn%d" % points.get_child_count()
		m.position = p
		_add(points, m)
