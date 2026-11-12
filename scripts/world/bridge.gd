class_name Bridge
extends StaticBody3D
## A bridge that slides out when told to (Part 13a, level editor Layer 2).
## It extends from this node along its forward axis (-Z) for `length`.
##
## Navigation: the bridge isn't part of the baked navmesh (keep it outside
## the Navigation region). Instead a NavigationLink3D joins its two ends and
## is switched on only while the bridge is fully out, so enemies chase
## across once it exists and never path over a gap.
## Wiring actions: "extend", "retract", "toggle".

signal changed(bridge: Bridge, extended: bool)

@export var bridge_id := ""
@export var length := 8.0
@export var width := 4.0
@export var thickness := 0.4
@export var extended := false
## Metres a second.
@export var speed := 4.0
@export var color := Color(0.55, 0.45, 0.35)

## 0 = in, 1 = all the way out.
var progress := 0.0
var link: NavigationLink3D
var _shape: CollisionShape3D
var _box: BoxShape3D
var _mesh: MeshInstance3D
var _bm: BoxMesh


func _ready() -> void:
	add_to_group("bridges")
	collision_layer = 1
	collision_mask = 0
	speed = clampf(speed, 0.5, 12.0)
	_box = BoxShape3D.new()
	_shape = CollisionShape3D.new()
	_shape.shape = _box
	add_child(_shape)
	_bm = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_bm.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _bm
	add_child(_mesh)
	link = NavigationLink3D.new()
	link.bidirectional = true
	# Ends a little past the bridge, so each snaps onto the navmesh beside it.
	link.start_position = Vector3(0.0, 0.0, 0.75)
	link.end_position = Vector3(0.0, 0.0, -length - 0.75)
	add_child(link)
	progress = 1.0 if extended else 0.0
	_apply()


func _physics_process(delta: float) -> void:
	var goal := 1.0 if extended else 0.0
	if progress == goal:
		return
	progress = move_toward(progress, goal, speed / maxf(length, 0.1) * delta)
	if absf(progress - goal) < 0.001:
		progress = goal
	_apply()
	if progress == goal:
		changed.emit(self, extended)


func switch_action(action: String) -> void:
	match action:
		"extend", "open", "start", "enable":
			extended = true
		"retract", "close", "stop", "disable":
			extended = false
		"toggle":
			extended = not extended


func is_open() -> bool:
	return progress >= 1.0


func _apply() -> void:
	var out := maxf(length * progress, 0.01)
	var size := Vector3(width, thickness, out)
	_box.size = size
	_bm.size = size
	var center := Vector3(0.0, -thickness * 0.5, -out * 0.5)
	_shape.position = center
	_mesh.position = center
	_shape.disabled = progress <= 0.0
	_mesh.visible = progress > 0.0
	link.enabled = progress >= 1.0
