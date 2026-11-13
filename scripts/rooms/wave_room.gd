class_name WaveRoom
extends Node3D
## A PSO-style room. Walking in spawns the first wave; each wave starts when
## the last enemy of the previous one falls. Doors work like PSO's (Grayson,
## 2026-11-09): the way in stays open, and the way on (doors named "Exit...")
## is locked until the final wave is beaten.
##
## Children it expects:
##   Doors       CSG shapes. "Exit..." doors are locked until the room is
##               cleared; any other door only closes while the room is active
##               if lock_all_while_active is on (the old behaviour). Keep them
##               outside the Navigation region so the navmesh is baked with the
##               doorways open.
##   SpawnPoints Marker3D nodes; enemies take them in order
## The trigger volume is built from trigger_size, centered on this node.
##
## Part 13a (level editor): a room can wait for its level's wiring instead of
## starting when walked into (start_on_enter off, then "start_combat"), waves
## can place each enemy themselves (WaveData.placements, with spawn delays),
## and it reports combat_started / wave_cleared / room_cleared (combat
## ended) for the wiring.

signal wave_started(room: WaveRoom, index: int, total: int)
signal room_cleared(room: WaveRoom)
signal combat_started(room: WaveRoom)
signal wave_cleared(room: WaveRoom, index: int)
## Every enemy a wave spawns (the level hooks up its events).
signal enemy_spawned(room: WaveRoom, enemy: Enemy)

enum RoomState { WAITING, ACTIVE, CLEARED }

@export var room_name := "Room"
@export var waves: Array[WaveData] = []
## Size of the box that starts the room when the Seeker steps inside it.
@export var trigger_size := Vector3(18.0, 4.0, 18.0)
## A data level's room (format 2): its navmesh polygons in world space. When
## set, the trigger is one prism per polygon instead of the trigger_size box.
var trigger_area := {}
@export var start_delay := 0.8
@export var wave_delay := 1.0
## Old behaviour: shut every door while the room is active.
@export var lock_all_while_active := false
## The room's id in a data level ("" in hand-built scenes).
@export var room_id := ""
## Off: only the level's wiring (or a button) starts the fight.
@export var start_on_enter := true

var state: RoomState = RoomState.WAITING
var current_wave := -1
var alive: Array[Enemy] = []
## Enemies of the current wave still waiting out their spawn delay.
var _pending := 0

@onready var _doors: Node3D = $Doors
@onready var _spawn_points: Node3D = $SpawnPoints
var _enemies: Node3D


func _ready() -> void:
	add_to_group("wave_rooms")
	_enemies = Node3D.new()
	_enemies.name = "Enemies"
	add_child(_enemies)
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = 2  # the Seeker
	if trigger_area.is_empty():
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = trigger_size
		shape.shape = box
		shape.position.y = trigger_size.y * 0.5
		area.add_child(shape)
	else:
		for poly in trigger_area.get("polys", []):
			var points := PackedVector3Array()
			for v in poly:
				var p := LevelData.vec3(v) - position
				points.append(p + Vector3(0, -0.5, 0))
				points.append(p + Vector3(0, 3.0, 0))
			var prism := ConvexPolygonShape3D.new()
			prism.points = points
			var shape := CollisionShape3D.new()
			shape.shape = prism
			area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	_update_doors()


func start() -> void:
	if state != RoomState.WAITING or waves.is_empty():
		return
	state = RoomState.ACTIVE
	_update_doors()
	combat_started.emit(self)
	await get_tree().create_timer(start_delay).timeout
	_spawn_wave(0)


func _on_body_entered(body: Node) -> void:
	if body is Player and start_on_enter:
		start()


func _spawn_wave(index: int) -> void:
	current_wave = index
	var wave := waves[index]
	if not wave.placements.is_empty():
		_spawn_placements(wave)
		wave_started.emit(self, index, waves.size())
		return
	var points := _spawn_points.get_children()
	for i in wave.enemies.size():
		var enemy := Enemy.create(wave.enemies[i])
		_enemies.add_child(enemy)
		var point := points[i % points.size()] as Node3D
		enemy.global_position = point.global_position
		enemy.look_at(global_position, Vector3.UP)
		enemy.rotation.x = 0.0
		enemy.rotation.z = 0.0
		enemy._aggro = true  # wave enemies come straight for you
		enemy.defeated.connect(_on_enemy_defeated)
		alive.append(enemy)
		enemy_spawned.emit(self, enemy)
	wave_started.emit(self, index, waves.size())


## Level editor waves: each enemy where it was placed, after its delay.
func _spawn_placements(wave: WaveData) -> void:
	for p in wave.placements:
		var delay := maxf(float(p.get("spawn_delay", 0.0)), 0.0)
		if delay <= 0.0:
			_spawn_placed(p)
		else:
			_pending += 1
			get_tree().create_timer(delay).timeout.connect(func():
				_pending -= 1
				if state == RoomState.ACTIVE and is_inside_tree():
					_spawn_placed(p))


func _spawn_placed(p: Dictionary) -> void:
	var data := Enemy.data_for(String(p.get("enemy", "")))
	if data == null:
		push_warning("Room %s: unknown enemy %s" % [room_id, p.get("enemy", "")])
		_check_wave_done.call_deferred()
		return
	var enemy := Enemy.create(data)
	var settings := {"alert": true}  # wave enemies come straight for you (PSO)
	settings.merge(p, true)
	enemy.configure(settings)
	_enemies.add_child(enemy)
	enemy.global_position = LevelData.vec3(p.get("pos"), global_position)
	enemy.rotation = Vector3(0.0, deg_to_rad(float(p.get("yaw", 0.0))), 0.0)
	enemy.defeated.connect(_on_enemy_defeated)
	alive.append(enemy)
	enemy_spawned.emit(self, enemy)


func _on_enemy_defeated(enemy: Enemy) -> void:
	alive.erase(enemy)
	_check_wave_done()


func _check_wave_done() -> void:
	if not alive.is_empty() or _pending > 0 or state != RoomState.ACTIVE:
		return
	wave_cleared.emit(self, current_wave)
	if current_wave + 1 < waves.size():
		await get_tree().create_timer(wave_delay).timeout
		_spawn_wave(current_wave + 1)
	else:
		state = RoomState.CLEARED
		_update_doors()
		room_cleared.emit(self)


## Exit doors: locked until cleared. Other doors: open, unless
## lock_all_while_active shuts them during the fight.
func _update_doors() -> void:
	for door in _doors.get_children():
		if not door is CSGShape3D:
			continue
		var closed := false
		if String(door.name).begins_with("Exit"):
			closed = state != RoomState.CLEARED
		elif lock_all_while_active:
			closed = state == RoomState.ACTIVE
		door.visible = closed
		door.use_collision = closed


## True when a point is inside this room (its trigger box).
## Buttons (Part 11): "start" starts the waves.
func switch_action(action: String) -> void:
	if action in ["start", "start_combat"] and state == RoomState.WAITING:
		start()


func contains(point: Vector3) -> bool:
	if not trigger_area.is_empty():
		return LevelData.area_contains(trigger_area, point)
	var local := to_local(point)
	return absf(local.x) <= trigger_size.x * 0.5 and absf(local.z) <= trigger_size.z * 0.5 \
		and local.y >= -1.0 and local.y <= trigger_size.y + 2.0


func is_door_locked(door_name: StringName) -> bool:
	var door := _doors.get_node_or_null(NodePath(door_name)) as CSGShape3D
	return door != null and door.use_collision
