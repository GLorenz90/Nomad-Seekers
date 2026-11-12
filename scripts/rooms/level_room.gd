class_name LevelRoom
extends Node3D
## A room or corridor of a data level (Part 13a, level editor Layer 1): the
## box its room area covers. The Trap Scanner reveals traps in the room
## you're in; a room with combat also gets a WaveRoom on the same spot.
## This node sits at the bottom centre of the box.

@export var room_id := ""
@export_enum("room", "corridor") var kind := "room"
@export var size := Vector3(16.0, 6.0, 16.0)


func _ready() -> void:
	add_to_group("level_rooms")


func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5 \
		and local.y >= -1.0 and local.y <= size.y + 2.0
