class_name Teleporter
extends Area3D
## Teleporter pad (North Star §7.1). Since 2026-11-10 (Grayson) it no longer
## banks Lumidium: Lumidium depots do that (LumidiumDepot), and the satchel's
## Lumidium travels with the Seeker.
##
## With a destination it also travels there (saving first). Maps persist for
## the session (2026-11-12), so a trip back finds the level as it was left.
## requires_rooms_cleared keeps the pad dark until every WaveRoom is cleared
## (the arena's exit back to the gym).

signal travelling(destination: String)

const PLAYER_MASK := 2
const COLOR_ACTIVE := Color(0.3, 0.9, 1.0)
const COLOR_TRAVEL := Color(0.55, 1.0, 0.55)
const COLOR_LOCKED := Color(0.25, 0.3, 0.35)

## Where it goes ("" = nowhere): a scene, a data level folder, "area:<area>"
## (this session's pick for that area) or "hub" (see Maps).
@export var destination := ""
## Label shown above the pad for travel pads, e.g. "To the arena".
@export var destination_name := ""
@export var requires_rooms_cleared := false
## Asleep until something wakes it (a level's wiring, Part 13a).
@export var dormant := false
## Seconds until it closes on its own; 0 = permanent.
@export var lifetime := 0.0
## Teleportal pads (Teleportals): whose they are, and whether this is the
## Nomad-2 end (which goes back to `arrive_at` and then closes both ends).
var portal_owner := Teleportals.NO_OWNER
var portal_return := false
var arrive_at := Vector3.INF
## Part 8: a pad with several destinations (Nomad-2's) asks where to go.
## Scene paths and the names shown for them, in the same order.
@export var destinations: PackedStringArray = []
@export var destination_names: PackedStringArray = []

var picker: DestinationPicker

var _material: StandardMaterial3D
var _label: Label3D
var _active := true


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
	if requires_rooms_cleared or dormant:
		if is_active() != _active:
			_refresh()


func is_active() -> bool:
	return not dormant and (not requires_rooms_cleared or _rooms_cleared())


## Level wiring (Part 13a): "wake" / "enable" turn it on, "disable" puts it
## back to sleep.
func switch_action(action: String) -> void:
	match action:
		"wake", "enable", "open":
			dormant = false
		"disable", "close":
			dormant = true
		"toggle":
			dormant = not dormant
	_refresh()


func _rooms_cleared() -> bool:
	for room in Scope.group(self, "wave_rooms"):
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
		_label.text = "Teleporter"
	elif _active:
		_label.text = "Teleporter\n%s" % (destination_name if destination_name != "" else Maps.display_name(destination))
	elif dormant:
		_label.text = "Teleporter\n(inactive)"
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
	return picker == null


func interact_prompt() -> String:
	if not destinations.is_empty():
		return "Teleport..."
	if destination == "":
		return "Teleporter (goes nowhere)"
	if dormant:
		return "Teleporter (inactive)"
	if not is_active():
		return "Teleporter locked (clear every room first)"
	return destination_name if destination_name != "" else "Teleport"


## A on the pad: asks where to go, or travels.
func interact(seeker: Player) -> void:
	if not destinations.is_empty():
		_open_picker(seeker)
	elif destination != "" and is_active():
		travel(seeker)


func _on_body_exited(body: Node) -> void:
	if body is Player and picker and picker.player == body:
		picker._finish(-1)
		picker = null


## Lists the destinations; picking one takes the party there.
func _open_picker(seeker: Player) -> void:
	if picker:
		return
	var names := destination_names.duplicate()
	var scenes := destinations.duplicate()
	# A quest session (Grayson 2026-11-13, like PSO): Nomad-2's teleporter
	# goes only to the quest's areas.
	var quest := QuestBook.active(seeker.save)
	if not quest.is_empty() and Maps.id_of(Scope.level(self)) == Session.HUB_SCENE:
		names = PackedStringArray()
		scenes = PackedStringArray()
		for a in quest.areas:
			names.append("Quest: %s" % String(a.name))
			scenes.append(String(a.destination))
	picker = DestinationPicker.new()
	seeker.ui_root().add_child(picker)
	picker.open(names, func(index: int):
		picker = null
		if index >= 0 and index < scenes.size():
			destination = scenes[index]
			travel(seeker), seeker)


## Takes the Seeker to the destination. Only they go (Grayson, 2026-11-09);
## see CoopDirector.travel. A Teleportal's Nomad-2 end sends them back to its
## spot, then the Teleportal closes.
func travel(seeker: Player) -> void:
	travelling.emit(destination)
	if portal_return:
		var owner_was := portal_owner
		var tree := get_tree()
		CoopDirector.travel(seeker, destination, arrive_at)
		Teleportals.close(owner_was, tree)
		return
	CoopDirector.travel(seeker, destination)
