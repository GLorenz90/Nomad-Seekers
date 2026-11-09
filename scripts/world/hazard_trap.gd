class_name HazardTrap
extends Area3D
## A hidden floor trap in a level (PSO-style, Part 6). It springs once when a
## Seeker steps on it: damage, a status, or both.
##
## Each trap has a small device (Grayson, 2026-11-09) that can be attacked to
## destroy the trap, but only while the trap is visible: after a Trap Scanner
## reveals the room, or always for Goluman (PSO androids' trap vision). A
## hidden trap's device can't be locked on to or hit by anything, area spells
## included. Everyone sees a trap once it has sprung.

const PLAYER_MASK := 2

enum Kind { DAMAGE, FREEZE, SLOW, SHOCK, POISON, CONFUSE, PARALYZE }

const KIND_ELEMENT := {
	Kind.DAMAGE: Element.Type.FIRE, Kind.FREEZE: Element.Type.ICE, Kind.SLOW: Element.Type.ICE,
	Kind.SHOCK: Element.Type.LIGHTNING, Kind.POISON: Element.Type.NATURE,
	Kind.CONFUSE: Element.Type.LIGHT, Kind.PARALYZE: Element.Type.GENERIC,
}
const KIND_STATUS := {
	Kind.FREEZE: StatusEffects.Status.FREEZE, Kind.SLOW: StatusEffects.Status.SLOW,
	Kind.SHOCK: StatusEffects.Status.SHOCK, Kind.POISON: StatusEffects.Status.POISON,
	Kind.CONFUSE: StatusEffects.Status.BLIND, Kind.PARALYZE: StatusEffects.Status.PARALYZE,
}

@export var kind: Kind = Kind.DAMAGE
@export var damage := 30.0
@export var status_seconds := 3.0
@export var radius := 1.2

## Shown by a Trap Scanner (stays shown).
var revealed := false
var destroyed := false
var sprung := false
var device: TrapDevice
var _mesh: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("hazards")
	collision_layer = 0
	collision_mask = PLAYER_MASK
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = 0.5
	add_child(shape)
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color := Element.color_of(KIND_ELEMENT[kind]) if kind != Kind.PARALYZE else Color(0.9, 0.5, 1.0)
	_material.albedo_color = Color(color, 0.45)
	disc.material = _material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = disc
	_mesh.position.y = 0.03
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	device = TrapDevice.new()
	device.name = "Device"
	device.trap = self
	add_child(device)
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	# Hidden unless scanned, sprung, or seen through Goluman trap vision.
	var seen := is_visible_to(get_tree().get_first_node_in_group("player") as Player)
	_mesh.visible = sprung or seen
	if device:
		device.set_shown(seen and not sprung)


static func goluman(seeker: Player) -> bool:
	return seeker != null and seeker.save != null and seeker.save.character.race == CharacterData.Race.GOLUMAN


## Buttons (Part 11): "disable" turns the trap off for good.
func switch_action(action: String) -> void:
	if action == "disable" and not sprung:
		destroy()


func is_visible_to(seeker: Player) -> bool:
	return not destroyed and (revealed or goluman(seeker))


## Trap Scanner: reveals every trap in the room the Seeker is in (or within
## SCAN_RADIUS when they aren't in a room). Returns how many it found.
const SCAN_RADIUS := 15.0


static func scan(seeker: Player) -> int:
	var tree := seeker.get_tree()
	var room: WaveRoom = null
	for r in tree.get_nodes_in_group("wave_rooms"):
		if (r as WaveRoom).contains(seeker.global_position):
			room = r
			break
	var found := 0
	for node in tree.get_nodes_in_group("hazards"):
		var trap := node as HazardTrap
		if trap.sprung or trap.destroyed:
			continue
		var inside := room.contains(trap.global_position) if room \
			else trap.global_position.distance_to(seeker.global_position) <= SCAN_RADIUS
		if inside:
			trap.revealed = true
			found += 1
	return found


## Attacking a visible trap's device destroys it.
func destroy() -> void:
	if destroyed or sprung:
		return
	destroyed = true
	SpellFx.burst(get_parent(), global_position + Vector3.UP * 0.4, radius, Color(0.8, 0.8, 0.8, 0.6))
	DamageNumber.spawn_text(get_parent(), global_position + Vector3.UP * 1.6, "Trap destroyed")
	queue_free()


func _on_body_entered(body: Node) -> void:
	var seeker := body as Player
	if seeker == null or sprung:
		return
	spring(seeker)


func spring(seeker: Player) -> void:
	sprung = true
	SpellFx.burst(get_parent(), global_position + Vector3.UP * 0.5, radius + 0.5, _material.albedo_color)
	if damage > 0.0 and kind == Kind.DAMAGE:
		var info := DamageInfo.new()
		info.amount = damage
		info.damage_type = KIND_ELEMENT[kind]
		info.kind = DamageInfo.Kind.MAGIC
		info.accuracy = -1.0  # hazards never miss
		seeker.receive_hit(info, null)
	if KIND_STATUS.has(kind):
		seeker.status.apply(KIND_STATUS[kind], status_seconds)
		DamageNumber.spawn_text(get_parent(), seeker.global_position + Vector3.UP * 2.2,
			StatusEffects.Status.keys()[KIND_STATUS[kind]].capitalize())
	_material.albedo_color.a = 0.2
	if device:
		device.set_shown(false)
