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
##   Lightning Shock   stunned: can't move or act (short). Seekers who aren't
##                     Goluman can still move while shocked, they just can't
##                     attack (shock_stuns = false; Grayson 2026-11-09)
##   Nature    Poison  damage over time (longer, weaker than Burn)
##   Light     Blind   own attacks miss half the time
##   Dark      Drain   damage over time that heals whoever applied it
## Buildup decays over time. Generic damage builds nothing.

signal status_started(status: Status)
signal status_ended(status: Status)

## STUN was Paralyze (renamed by Grayson, 2026-11-09).
enum Status { BURN, SLOW, FREEZE, SHOCK, POISON, BLIND, DRAIN, STUN }

const DURATIONS := {
	Status.BURN: 4.0, Status.SLOW: 3.0, Status.FREEZE: 1.5, Status.SHOCK: 1.0,
	Status.POISON: 6.0, Status.BLIND: 4.0, Status.DRAIN: 4.0, Status.STUN: 2.5,
}
## Stats that buffs / debuffs scale (Part 6 spells): percent changes over time.
const MODIFIED_STATS: Array[StringName] = [&"strength", &"dexterity", &"soul", &"defense", &"accuracy", &"evasion"]
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
## Stat modifiers from buffs and debuffs: stat -> {"fraction": f, "seconds": s}.
## One per stat; a stronger or longer cast replaces a weaker one.
var modifiers: Dictionary = {}
var _tick := 0.0
## Statuses that never take hold (Goluman: Poison and Stun, like PSO's
## androids and paralysis).
var immune: Array[int] = []
## Shock stops movement too. True for enemies and Goluman (who are weak to it:
## it's a short stun for them); other Seekers can still move.
var shock_stuns := true
## Stun ends when a hit lands (Seekers; Grayson 2026-11-09: so it isn't as
## punishing as Freeze). Damage over time and hazard drains don't break it.
## Off for enemies, so a stun trap still holds them while you hit them.
var stun_breaks_on_hit := false


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
	if status in immune:
		return
	var fresh := not active.has(status)
	active[status] = seconds if seconds > 0.0 else float(DURATIONS[status])
	if fresh:
		status_started.emit(status)


## Called when a hit lands on whoever this belongs to.
func on_hit() -> void:
	if stun_breaks_on_hit and active.has(Status.STUN):
		active.erase(Status.STUN)
		status_ended.emit(Status.STUN)


func clear_all() -> void:
	for status in active.keys():
		status_ended.emit(status)
	active.clear()
	buildup.clear()
	clear_debuffs()


## Cure at a level: clears statuses in CURE_ORDER up to `count` of them
## (least annoying first); with every status covered it also clears debuffs.
func cure(count: int) -> void:
	for i in mini(count, CURE_ORDER.size()):
		var status: int = CURE_ORDER[i]
		if active.has(status):
			active.erase(status)
			status_ended.emit(status)
		var element := _element_for(status)
		if element >= 0:
			buildup.erase(element)
	if count > CURE_ORDER.size():
		clear_debuffs()


## Statuses in order of annoyance, least first (Cure level 1 clears the first).
const CURE_ORDER: Array[int] = [Status.SLOW, Status.BURN, Status.POISON, Status.BLIND,
	Status.DRAIN, Status.SHOCK, Status.STUN, Status.FREEZE]


func _element_for(status: int) -> int:
	match status:
		Status.BURN:
			return Element.Type.FIRE
		Status.SLOW, Status.FREEZE:
			return Element.Type.ICE
		Status.SHOCK:
			return Element.Type.LIGHTNING
		Status.POISON:
			return Element.Type.NATURE
		Status.BLIND:
			return Element.Type.LIGHT
		Status.DRAIN:
			return Element.Type.DARK
	return -1


func is_active(status: int) -> bool:
	return active.has(status)


## Buff (fraction > 0) or debuff (fraction < 0) on a stat for some seconds.
func apply_modifier(stat: StringName, fraction: float, seconds: float) -> void:
	var old: Dictionary = modifiers.get(stat, {})
	if not old.is_empty() and signf(float(old.fraction)) == signf(fraction) \
			and absf(float(old.fraction)) > absf(fraction):
		old.seconds = maxf(float(old.seconds), seconds)  # keep the stronger one, refresh time
		return
	modifiers[stat] = {"fraction": fraction, "seconds": seconds}


## Multiplier for a stat from active buffs / debuffs (1.0 = unchanged).
func stat_scale(stat: StringName) -> float:
	var m: Dictionary = modifiers.get(stat, {})
	return 1.0 + float(m.get("fraction", 0.0))


func clear_debuffs() -> void:
	for stat in modifiers.keys():
		if float(modifiers[stat].fraction) < 0.0:
			modifiers.erase(stat)


## Movement speed multiplier from statuses.
func move_scale() -> float:
	if not can_move():
		return 0.0
	return 0.5 if is_active(Status.SLOW) else 1.0


## Frozen, stunned and (for anyone shock stuns) shocked targets can't move,
## jump or dodge.
func can_move() -> bool:
	return not (is_active(Status.FREEZE) or is_active(Status.STUN)
		or (shock_stuns and is_active(Status.SHOCK)))


## Frozen, stunned or shocked targets can't attack.
func can_act() -> bool:
	return not (is_active(Status.FREEZE) or is_active(Status.SHOCK) or is_active(Status.STUN))


## Chance that this target's own attacks land (Blind halves it).
func hit_chance() -> float:
	return 0.5 if is_active(Status.BLIND) else 1.0


func describe() -> String:
	var parts := PackedStringArray()
	for status in active:
		parts.append("%s %.1fs" % [Status.keys()[status].capitalize(), active[status]])
	for stat in modifiers:
		var m: Dictionary = modifiers[stat]
		parts.append("%s %+d%% %.0fs" % [String(stat).capitalize(), roundi(float(m.fraction) * 100.0), float(m.seconds)])
	return ", ".join(parts)


func _physics_process(delta: float) -> void:
	for element in buildup.keys():
		buildup[element] = maxf(buildup[element] - decay_per_second * delta, 0.0)
	for stat in modifiers.keys():
		modifiers[stat].seconds = float(modifiers[stat].seconds) - delta
		if float(modifiers[stat].seconds) <= 0.0:
			modifiers.erase(stat)
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
