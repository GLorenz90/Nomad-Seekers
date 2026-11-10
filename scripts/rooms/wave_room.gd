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

signal wave_started(room: WaveRoom, index: int, total: int)
signal room_cleared(room: WaveRoom)

enum RoomState { WAITING, ACTIVE, CLEARED }

@export var room_name := "Room"
@export var waves: Array[WaveData] = []
## Size of the box that starts the room when the Seeker steps inside it.
@export var trigger_size := Vector3(18.0, 4.0, 18.0)
@export var start_delay := 0.8
@export var wave_delay := 1.0
## Old behaviour: shut every door while the room is active.
@export var lock_all_while_active := false

var state: RoomState = RoomState.WAITING
var current_wave := -1
var alive: Array[Enemy] = []

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
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = trigger_size
	shape.shape = box
	shape.position.y = trigger_size.y * 0.5
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	_update_doors()


func start() -> void:
	if state != RoomState.WAITING or waves.is_empty():
		return
	state = RoomState.ACTIVE
	_update_doors()
	await get_tree().create_timer(start_delay).timeout
	_spawn_wave(0)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		start()


func _spawn_wave(index: int) -> void:
	current_wave = index
	var points := _spawn_points.get_children()
	var wave := waves[index]
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
	wave_started.emit(self, index, waves.size())


func _on_enemy_defeated(enemy: Enemy) -> void:
	alive.erase(enemy)
	if not alive.is_empty() or state != RoomState.ACTIVE:
		return
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
	if action == "start" and state == RoomState.WAITING:
		start()


func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= trigger_size.x * 0.5 and absf(local.z) <= trigger_size.z * 0.5 \
		and local.y >= -1.0 and local.y <= trigger_size.y + 2.0


func is_door_locked(door_name: StringName) -> bool:
	var door := _doors.get_node_or_null(NodePath(door_name)) as CSGShape3D
	return door != null and door.use_collision
