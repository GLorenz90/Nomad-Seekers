class_name HazardTrap
extends Area3D
## A hidden floor trap in a level (PSO-style, Part 6). It springs once when a
## Seeker steps on it: damage, a status, or both. Goluman see every hazard
## (PSO androids' trap vision); everyone else only sees one once it's sprung.

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

var sprung := false
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
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	# Trap vision: visible to Goluman Seekers, hidden from everyone else.
	_mesh.visible = sprung or is_visible_to(get_tree().get_first_node_in_group("player") as Player)


static func goluman(seeker: Player) -> bool:
	return seeker != null and seeker.save != null and seeker.save.character.race == CharacterData.Race.GOLUMAN


func is_visible_to(seeker: Player) -> bool:
	return goluman(seeker)


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
