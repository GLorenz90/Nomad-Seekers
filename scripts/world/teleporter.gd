class_name Teleporter
extends Area3D
## Teleporter pad (North Star §7.1). Standing on it deposits every carried
## Lumidium into the Seeker's bank, where it's safe from death.
##
## With a destination it also travels there (saving first). Loading a level
## always builds it fresh, so a trip back into the arena resets it.
## requires_rooms_cleared keeps the pad dark until every WaveRoom is cleared
## (the arena's exit back to the gym).

signal deposited(seeker: Player, amount: int)
signal travelling(destination: String)

const PLAYER_MASK := 2
const COLOR_ACTIVE := Color(0.3, 0.9, 1.0)
const COLOR_TRAVEL := Color(0.55, 1.0, 0.55)
const COLOR_LOCKED := Color(0.25, 0.3, 0.35)

## Scene to travel to ("" = deposit only).
@export_file("*.tscn") var destination := ""
## Label shown above the pad for travel pads, e.g. "To the arena".
@export var destination_name := ""
@export var requires_rooms_cleared := false
## Seconds until it closes on its own (Teleportal spell); 0 = permanent.
@export var lifetime := 0.0
## Part 8: a pad with several destinations (Nomad-2's) asks where to go.
## Scene paths and the names shown for them, in the same order.
@export var destinations: PackedStringArray = []
@export var destination_names: PackedStringArray = []

var picker: DestinationPicker

var _material: StandardMaterial3D
var _label: Label3D
var _active := true
var _leaving := false


func _ready() -> void:
	add_to_group("teleporters")
	collision_layer = 0
	collision_mask = PLAYER_MASK
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
	cyl.height = 1.5
	shape.shape = cyl
	shape.position.y = 0.75
	add_child(shape)
	var pad := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.4
	mesh.bottom_radius = 1.5
	mesh.height = 0.12
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 1.2
	mesh.material = _material
	pad.mesh = mesh
	pad.position.y = 0.06
	add_child(pad)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.outline_size = 8
	_label.position.y = 2.2
	add_child(_label)
	add_to_group("interactables")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh()


func _process(delta: float) -> void:
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			queue_free()
			return
	if requires_rooms_cleared:
		var cleared := _rooms_cleared()
		if cleared != _active:
			_refresh()


func is_active() -> bool:
	return not requires_rooms_cleared or _rooms_cleared()


func _rooms_cleared() -> bool:
	for room in get_tree().get_nodes_in_group("wave_rooms"):
		if (room as WaveRoom).state != WaveRoom.RoomState.CLEARED:
			return false
	return true


func _refresh() -> void:
	_active = is_active()
	var color := COLOR_ACTIVE
	if destination != "":
		color = COLOR_TRAVEL if _active else COLOR_LOCKED
	_material.albedo_color = color
	_material.emission = color
	if not destinations.is_empty():
		color = COLOR_TRAVEL
		_label.text = "Teleporter\n(choose a destination)"
	elif destination == "":
		_label.text = "Teleporter\n(deposit Lumidium)"
	elif _active:
		_label.text = "Teleporter\n%s" % (destination_name if destination_name != "" else destination.get_file().get_basename())
	else:
		_label.text = "Teleporter\n(clear every room first)"


## Standing on the pad no longer does anything by itself (Grayson,
## 2026-11-09): A activates it (see Player interaction).
func _on_body_entered(_body: Node) -> void:
	pass


# --- Interaction (A) ---------------------------------------------------------------

const INTERACT_RANGE := 1.6


func interact_point() -> Vector3:
	return global_position


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact(_seeker: Player) -> bool:
	return not _leaving and picker == null


func interact_prompt() -> String:
	if not destinations.is_empty():
		return "Teleport..."
	if destination == "":
		return "Deposit Lumidium"
	if not is_active():
		return "Teleporter locked (clear every room first)"
	return destination_name if destination_name != "" else "Teleport"


## A on the pad: banks carried Lumidium, then asks where to go or travels.
func interact(seeker: Player) -> void:
	var amount := seeker.deposit_lumidium()
	if amount > 0:
		deposited.emit(seeker, amount)
	if not destinations.is_empty():
		_open_picker(seeker)
	elif destination != "" and is_active():
		travel(seeker)


func _on_body_exited(body: Node) -> void:
	if body is Player and picker:
		picker.queue_free()
		picker = null


## Pauses and lists the destinations; picking one travels there.
func _open_picker(seeker: Player) -> void:
	if picker:
		return
	picker = DestinationPicker.new()
	get_tree().root.add_child(picker)
	picker.open(destination_names, func(index: int):
		picker = null
		if index >= 0 and index < destinations.size():
			destination = destinations[index]
			travel(seeker))


## Saves and loads the destination scene (fresh every time).
func travel(seeker: Player) -> void:
	_leaving = true
	seeker.save_game()
	travelling.emit(destination)
	get_tree().change_scene_to_file.call_deferred(destination)
