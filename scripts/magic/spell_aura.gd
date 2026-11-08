class_name SpellAura
extends Node3D
## An aura (pas- spells): rides on the caster and hurts enemies close by twice
## a second for a while. One aura at a time; a new one replaces the old.

const TICK := 0.5

var ctrl: CombatController
var item: WeaponData
var spell: SpellDef
var level := 1
var hard := false
var seconds_left := 30.0
var _tick := 0.0
var _ring: MeshInstance3D


static func create(controller: CombatController, casting_item: WeaponData, aura_spell: SpellDef,
		aura_level: int, is_hard: bool) -> SpellAura:
	var aura := SpellAura.new()
	aura.name = "Aura"
	aura.ctrl = controller
	aura.item = casting_item
	aura.spell = aura_spell
	aura.level = aura_level
	aura.hard = is_hard
	aura.seconds_left = SpellBook.aura_seconds(aura_level) * (1.25 if is_hard else 1.0)
	return aura


func radius() -> float:
	return spell.radius + spell.radius_growth * (level - 1)


func _ready() -> void:
	add_to_group("spell_auras")
	# Replace any aura already on this Seeker.
	for other in get_parent().get_children():
		if other is SpellAura and other != self:
			other.queue_free()
	var torus := TorusMesh.new()
	torus.inner_radius = radius() - 0.12
	torus.outer_radius = radius()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(Element.color_of(spell.element), 0.5)
	torus.material = mat
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position.y = 0.12
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _physics_process(delta: float) -> void:
	seconds_left -= delta
	if seconds_left <= 0.0 or not is_instance_valid(ctrl):
		queue_free()
		return
	_ring.rotation.y += delta
	_tick += delta
	if _tick < TICK:
		return
	_tick -= TICK
	var center := (get_parent() as Node3D).global_position
	for v in SpellCaster._in_radius(center, radius(), 10):
		# Small damage: a fifth of the spell's power per tick.
		SpellCaster._damage(ctrl, item, spell, level, hard, v, 0.2)
