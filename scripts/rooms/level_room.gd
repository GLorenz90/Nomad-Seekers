class_name LevelRoom
extends Node3D
## A room or corridor of a data level (format 2): an area of the navmesh,
## found by the level editor and saved as its navmesh polygons. The Trap
## Scanner reveals traps in the room you're in; a room with combat also gets
## a WaveRoom with the same shape. The node sits at the area's seed point.

@export var room_id := ""
@export_enum("room", "corridor") var kind := "room"
## The area's spec from map.json (polys in world space).
var area := {}


func _ready() -> void:
	add_to_group("level_rooms")


func contains(point: Vector3) -> bool:
	return LevelData.area_contains(area, point)
