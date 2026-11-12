class_name InvisibleWall
extends StaticBody3D
## An invisible wall (Part 13a, level editor Layer 1). Two kinds:
## - blocks everyone: on the world layer, so the navmesh treats it as a wall;
## - blocks only Seekers: on the seeker_walls layer (5), which only Seekers
##   collide with, so enemies walk through (keeping players in an arena
##   while enemies can still come in).

const SEEKER_WALL_LAYER := 16  # layer 5

@export var size := Vector3(4.0, 4.0, 0.4)
@export var seekers_only := false


func _ready() -> void:
	add_to_group("invisible_walls")
	collision_layer = SEEKER_WALL_LAYER if seekers_only else 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	add_child(shape)
