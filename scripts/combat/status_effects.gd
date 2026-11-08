class_name StatusEffects
extends Node
## Elemental status effects (North Star §4.5). Attach as a child named
## "StatusEffects" next to a Health node.
##
## Every elemental hit adds buildup for its element (damage x status_power).
## When buildup passes `threshold`, that element's status starts:
##   Fire      Burn    damage over time
##   Ice       Slow    half speed; Ice buildup while already slowed = Freeze
##   Freeze            can't move or act
##   Lightning Shock   stunned: can't move or act (short)
##   Nature    Poison  damage over time (longer, weaker than Burn)
##   Light     Blind   own attacks miss half the time
##   Dark      Drain   damage over time that heals whoever applied it
## Buildup decays over time. Generic damage builds nothing.

signal status_started(status: Status)
signal status_ended(status: Status)

enum Status { BURN, SLOW, FREEZE, SHOCK, POISON, BLIND, DRAIN }

const DURATIONS := {
	Status.BURN: 4.0, Status.SLOW: 3.0, Status.FREEZE: 1.5, Status.SHOCK: 1.0,
	Status.POISON: 6.0, Status.BLIND: 4.0, Status.DRAIN: 4.0,
}
## Damage per second as a fraction of max HP.
const DOT_FRACTION := {Status.BURN: 0.03, Status.POISON: 0.015, Status.DRAIN: 0.02}
const DOT_ELEMENT := {Status.BURN: Element.Type.FIRE, Status.POISON: Element.Type.NATURE, Status.DRAIN: Element.Type.DARK}
const TICK := 0.5

@export var threshold := 40.0
@export var decay_per_second := 8.0
## Multiplies all incoming buildup (bosses can resist statuses).
@export var buildup_scale := 1.0

var buildup: Dictionary = {}  # Element.Type -> float
var active: Dictionary = {}  # Status -> seconds left
var _drain_source: Node
var _tick := 0.0


static func find(node: Node) -> StatusEffects:
	if node == null:
		return null
	return node.get_node_or_null("StatusEffects") as StatusEffects


static func for_element(element: Element.Type) -> int:
	match element:
		Element.Type.FIRE:
			return Status.BURN
		Element.Type.ICE:
			return Status.SLOW
		Element.Type.LIGHTNING:
			return Status.SHOCK
		Element.Type.NATURE:
			return Status.POISON
		Element.Type.LIGHT:
			return Status.BLIND
		Element.Type.DARK:
			return Status.DRAIN
	return -1


func add_buildup(info: DamageInfo, source: Node = null) -> void:
	if info.damage_type == Element.Type.GENERIC or info.amount <= 0.0:
		return
	var element := info.damage_type
	var value: float = buildup.get(element, 0.0) + info.amount * info.status_power * buildup_scale
	if value < threshold:
		buildup[element] = value
		return
	buildup[element] = 0.0
	var status := for_element(element)
	if status == Status.SLOW and is_active(Status.SLOW):
		status = Status.FREEZE
	if status == Status.DRAIN:
		_drain_source = source
	apply(status)


func apply(status: int, seconds: float = -1.0) -> void:
	var fresh := not active.has(status)
	active[status] = seconds if seconds > 0.0 else float(DURATIONS[status])
	if fresh:
		status_started.emit(status)


func clear_all() -> void:
	for status in active.keys():
		status_ended.emit(status)
	active.clear()
	buildup.clear()


func is_active(status: int) -> bool:
	return active.has(status)


## Movement speed multiplier from statuses.
func move_scale() -> float:
	if is_active(Status.FREEZE) or is_active(Status.SHOCK):
		return 0.0
	return 0.5 if is_active(Status.SLOW) else 1.0


## Frozen or shocked targets can't attack.
func can_act() -> bool:
	return not (is_active(Status.FREEZE) or is_active(Status.SHOCK))


## Chance that this target's own attacks land (Blind halves it).
func hit_chance() -> float:
	return 0.5 if is_active(Status.BLIND) else 1.0


func describe() -> String:
	var parts := PackedStringArray()
	for status in active:
		parts.append("%s %.1fs" % [Status.keys()[status].capitalize(), active[status]])
	return ", ".join(parts)


func _physics_process(delta: float) -> void:
	for element in buildup.keys():
		buildup[element] = maxf(buildup[element] - decay_per_second * delta, 0.0)
	if active.is_empty():
		return
	_tick += delta
	var do_tick := _tick >= TICK
	if do_tick:
		_tick -= TICK
	for status in active.keys():
		active[status] -= delta
		if do_tick and DOT_FRACTION.has(status):
			_damage_over_time(status)
		if active[status] <= 0.0:
			active.erase(status)
			status_ended.emit(status)


func _damage_over_time(status: int) -> void:
	var health := Health.find(get_parent())
	if health == null or health.is_dead():
		return
	var info := DamageInfo.new()
	info.amount = health.max_hp * float(DOT_FRACTION[status]) * TICK
	info.damage_type = DOT_ELEMENT[status]
	var parent := get_parent() as Node3D
	if parent:
		info.hit_position = parent.global_position + Vector3.UP * 1.6
	var dealt := health.take_damage(info)
	if status == Status.DRAIN and is_instance_valid(_drain_source):
		var source_health := Health.find(_drain_source)
		if source_health and not source_health.is_dead():
			source_health.hp = minf(source_health.hp + dealt, source_health.max_hp)
