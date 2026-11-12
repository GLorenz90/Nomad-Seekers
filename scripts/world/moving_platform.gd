class_name MovingPlatform
extends AnimatableBody3D
## A platform that moves between points (Part 13a, level editor Layer 2), for
## puzzles and boss fights. Seekers ride it (Godot carries a CharacterBody3D
## standing on an AnimatableBody3D). Enemies don't ride platforms yet
## (working assumption): keep it outside the Navigation region.
##
## Modes:
##   loop       1 → 2 → ... → last → 1 ...
##   ping_pong  1 → ... → last → ... → 1 ...
##   step       moves to the next point each time it's told to ("step"),
##              then waits there.
## Wiring actions: "start", "stop", "toggle", "step".

signal arrived(platform: MovingPlatform, index: int)

@export var platform_id := ""
@export var size := Vector3(4.0, 0.5, 4.0)
@export var color := Color(0.45, 0.5, 0.6)
## World positions; the platform starts on the first.
@export var points: PackedVector3Array = []
@export_enum("loop", "ping_pong", "step") var mode := "ping_pong"
@export var speed := 2.0
## Seconds it waits at each point.
@export var wait := 1.0
@export var running := true

var index := 0
var _dir := 1
var _target := 0
var _waiting := 0.0


func _ready() -> void:
	add_to_group("moving_platforms")
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	speed = clampf(speed, 0.5, 8.0)
	wait = clampf(wait, 0.0, 30.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = -size.y * 0.5
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mesh.mesh = bm
	mesh.position.y = -size.y * 0.5
	add_child(mesh)
	if not points.is_empty():
		global_position = points[0]
	_target = _next(0)
	if mode == "step":
		running = false


func _physics_process(delta: float) -> void:
	if not running or points.size() < 2:
		return
	if _waiting > 0.0:
		_waiting -= delta
		return
	var goal := points[_target]
	var to := goal - global_position
	var step := speed * delta
	if to.length() <= step:
		global_position = goal
		index = _target
		arrived.emit(self, index)
		_waiting = wait
		if mode == "step":
			running = false
		_target = _next(index)
	else:
		global_position += to.normalized() * step


func _next(from: int) -> int:
	if points.size() < 2:
		return 0
	match mode:
		"ping_pong":
			if from + _dir >= points.size() or from + _dir < 0:
				_dir = -_dir
			return from + _dir
	return (from + 1) % points.size()


func switch_action(action: String) -> void:
	match action:
		"start", "enable":
			running = true
		"stop", "disable":
			running = false
		"toggle":
			running = not running
		"step":
			running = true
			_waiting = 0.0
