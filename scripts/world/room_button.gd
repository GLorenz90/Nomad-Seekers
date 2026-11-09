class_name RoomButton
extends Area3D
## A button (Part 11, PSO-style). Buttons belong to a SwitchGroup, which does
## something when enough of them are pressed (open a door, turn off a
## hazard or traps, start waves...).
##
## - PRESS: a pedestal; A presses it once and it stays pressed.
## - FLOOR: a plate you stand on. In a group of several, the group decides
##   which plates stay down (SwitchGroup: with fewer Seekers than plates, the
##   first ones latch; the rest need someone standing on them).

enum Mode { PRESS, FLOOR }

const COLOR_UP := Color(1.0, 0.35, 0.25)
const COLOR_DOWN := Color(0.35, 1.0, 0.45)
const INTERACT_RANGE := 1.8

@export var mode: Mode = Mode.PRESS

var group: SwitchGroup
## Stays pressed (PRESS buttons, and latched floor plates).
var latched := false
var _occupants := {}
var _mat: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	add_to_group("room_buttons")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.0, 1.4) if mode == Mode.FLOOR else Vector3(0.8, 1.6, 0.8)
	shape.shape = box
	shape.position.y = 0.5
	add_child(shape)
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	if mode == Mode.FLOOR:
		bm.size = Vector3(1.3, 0.08, 1.3)
		mesh.position.y = 0.04
	else:
		bm.size = Vector3(0.5, 1.0, 0.5)
		mesh.position.y = 0.5
	bm.material = _mat
	mesh.mesh = bm
	add_child(mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.outline_size = 8
	_label.position.y = 1.6 if mode == Mode.PRESS else 0.7
	add_child(_label)
	if mode == Mode.PRESS:
		add_to_group("interactables")
	else:
		body_entered.connect(_on_entered)
		body_exited.connect(_on_exited)
	refresh()


func is_pressed() -> bool:
	return latched or not _occupants.is_empty()


func refresh() -> void:
	var done := group != null and group.done
	var down := is_pressed() or done
	_mat.albedo_color = COLOR_DOWN if down else COLOR_UP
	_mat.emission = (COLOR_DOWN if down else COLOR_UP) * 0.6
	if mode == Mode.PRESS:
		_label.text = "" if down else "Button"
	else:
		_label.text = "" if done else ("held" if latched else "")


func _on_entered(body: Node) -> void:
	if body is Player:
		_occupants[body] = true
		if group:
			group.button_down(self)
		refresh()


func _on_exited(body: Node) -> void:
	if body is Player:
		_occupants.erase(body)
		if group:
			group.button_up(self)
		refresh()


# --- Interaction (PRESS buttons) ---------------------------------------------------

func interact_point() -> Vector3:
	return global_position


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact(_seeker: Player) -> bool:
	return mode == Mode.PRESS and not latched


func interact_prompt() -> String:
	return "Press the button"


func interact(_seeker: Player) -> void:
	press()


func press() -> void:
	if latched:
		return
	latched = true
	if group:
		group.button_down(self)
	refresh()
