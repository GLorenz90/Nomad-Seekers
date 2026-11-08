class_name WaveRoom
extends Node3D
## A PSO-style locked room. Walking in closes the doors and spawns the first
## wave; each wave starts when the last enemy of the previous one falls; after
## the final wave the doors open.
##
## Children it expects:
##   Doors       CSG shapes that block the exits while the room is active
##               (keep them outside the Navigation region so the navmesh is
##               baked with the doorways open)
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
	_set_doors(false)


func start() -> void:
	if state != RoomState.WAITING or waves.is_empty():
		return
	state = RoomState.ACTIVE
	_set_doors(true)
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
		_set_doors(false)
		room_cleared.emit(self)


func _set_doors(closed: bool) -> void:
	for door in _doors.get_children():
		if door is CSGShape3D:
			door.visible = closed
			door.use_collision = closed
