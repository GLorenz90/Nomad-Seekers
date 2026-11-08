class_name TargetDummy
extends CharacterBody3D
## Stand-in enemy for testing lock-on and orbiting. It can patrol between its
## start position and start + patrol_offset. Gets replaced by real enemies in Part 4.

## Leave at zero to stand still.
@export var patrol_offset := Vector3.ZERO
@export var patrol_speed := 2.0
@export var lock_height := 1.1

var _start := Vector3.ZERO
var _heading_out := true
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var _label: Label3D = $Label3D


func _ready() -> void:
	add_to_group("lockable")
	_start = global_position
	_label.text = name


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * lock_height


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if patrol_offset != Vector3.ZERO:
		var goal := _start + (patrol_offset if _heading_out else Vector3.ZERO)
		var to := goal - global_position
		to.y = 0.0
		if to.length() < 0.2:
			_heading_out = not _heading_out
		else:
			var step := to.normalized() * patrol_speed
			velocity.x = step.x
			velocity.z = step.z

	move_and_slide()
