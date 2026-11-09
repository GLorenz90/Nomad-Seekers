class_name SwitchDoor
extends StaticBody3D
## A door a button opens (Part 11). Solid and marked while closed; gone
## while open. Kept outside the Navigation region, so the navmesh is baked
## with its doorway open.

@export var size := Vector3(4.2, 4.0, 0.6)
@export var label := "LOCKED"
@export var is_open := false

var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	add_to_group("switch_doors")
	collision_layer = 1
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	_shape.position.y = size.y / 2.0
	add_child(_shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.55, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.45, 1.0)
	bm.material = mat
	_mesh.mesh = bm
	_mesh.position.y = size.y / 2.0
	add_child(_mesh)
	_label = Label3D.new()
	_label.text = label
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 44
	_label.outline_size = 10
	_label.position = Vector3(0, size.y / 2.0, 0)
	add_child(_label)
	_apply()


func open() -> void:
	is_open = true
	_apply()


func close() -> void:
	is_open = false
	_apply()


## Buttons: "open", "close" or "toggle".
func switch_action(action: String) -> void:
	match action:
		"open":
			open()
		"close":
			close()
		"toggle":
			is_open = not is_open
			_apply()


func _apply() -> void:
	if _shape == null:
		return
	_shape.set_deferred("disabled", is_open)
	_mesh.visible = not is_open
	_label.visible = not is_open
