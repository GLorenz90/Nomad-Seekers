class_name Trap
extends Node3D
## A Goluman trap (Part 6): set at the feet (tap) or tossed ahead (hold). It
## arms after ARM_TIME (3 s, like PSO: placing traps takes some planning;
## Grayson 2026-11-10), then springs when an enemy steps close. Any Seeker can
## hit it (TrapTrigger) to set it off early, armed or not. Damage Traps
## explode (PSO technique power), status traps put everything in the blast in
## their status. A Seeker can have MAX_TRAPS set at once (oldest goes first).

const ARM_TIME := 3.0
const TRIGGER_RADIUS := 1.4
const LIFETIME := 45.0

var ctrl: CombatController
var item: WeaponData
var spell: SpellDef
var level := 1
var hard := false
var _age := 0.0
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _trigger: TrapTrigger
var _sprung := false


static func place(controller: CombatController, casting_item: WeaponData, trap_spell: SpellDef,
		trap_level: int, is_hard: bool, at: Vector3) -> Trap:
	var player := controller.get_parent() as Player
	var mine: Array[Trap] = []
	for node in Scope.group(player, "traps"):
		if (node as Trap).ctrl == controller:
			mine.append(node)
	while mine.size() >= SpellCaster.MAX_TRAPS:
		mine.pop_front().queue_free()
	var trap := Trap.new()
	trap.ctrl = controller
	trap.item = casting_item
	trap.spell = trap_spell
	trap.level = trap_level
	trap.hard = is_hard
	player.get_parent().add_child(trap)
	trap.global_position = Vector3(at.x, player.global_position.y, at.z)
	controller.combo_feedback.emit("%s set" % trap_spell.display_name)
	return trap


func radius() -> float:
	return spell.radius + spell.radius_growth * (level - 1)


func _ready() -> void:
	add_to_group("traps")
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.55
	cyl.height = 0.18
	_material = StandardMaterial3D.new()
	_material.albedo_color = SpellCaster._color(spell)
	_material.emission_enabled = true
	_material.emission = SpellCaster._color(spell)
	_material.emission_energy_multiplier = 0.3
	cyl.material = _material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cyl
	_mesh.position.y = 0.09
	add_child(_mesh)
	_trigger = TrapTrigger.new()
	_trigger.trap = self
	add_child(_trigger)


func is_armed() -> bool:
	return _age >= ARM_TIME


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME or not is_instance_valid(ctrl):
		queue_free()
		return
	if not is_armed():
		# Arming: a slow, dim blink that quickens as it gets close.
		_material.emission_energy_multiplier = 0.15 + 0.25 * absf(sin(_age * (2.0 + 4.0 * _age / ARM_TIME)))
		return
	_material.emission_energy_multiplier = 0.6 + 0.5 * sin(_age * 8.0)
	for v in SpellCaster._in_radius(global_position, TRIGGER_RADIUS, 4, self):
		if not v is TrapTrigger and not v is TrapDevice:
			spring()
			return


## Goes off: damage or status on everything in the blast.
func spring() -> void:
	if _sprung or not is_inside_tree():
		return
	_sprung = true
	var world := get_parent()
	var r := radius()
	SpellFx.burst(world, global_position + Vector3.UP * 0.4, r, SpellCaster._color(spell))
	for v in SpellCaster._in_radius(global_position, r, 12, self):
		if v is TrapTrigger:
			continue  # other traps don't chain off this one
		if spell.trap_status < 0:
			SpellCaster._damage(ctrl, item, spell, level, hard, v, 1.0)
		else:
			SpellCaster._damage(ctrl, item, spell, level, hard, v, 0.25, 0.0)
			var st := StatusEffects.find(v)
			if st:
				st.apply(spell.trap_status, SpellBook.trap_status_seconds(level) * (1.25 if hard else 1.0))
	queue_free()
