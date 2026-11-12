class_name StatusEffects
extends Node
## Elemental status effects (North Star §4.5). Attach as a child named
## "StatusEffects" next to a Health node.
##
## Every elemental hit adds buildup for its element (damage x status_power).
## When buildup passes `threshold`, that element's status starts. Rules set by
## Grayson 2026-11-12:
##   Fire      Burn     damage over time, 5 s; wiggling the stick burns it off
##                      faster ("rolling on the ground")
##   Ice       Freeze   can't move or act, 5 s; mash buttons and wiggle the
##                      stick to break out sooner
##   (traps)   Slow     half speed, 7 s; only Slow traps cause it
##   Lightning Shock    Seekers (not Goluman) can move but not attack, until
##                      cured. Goluman and enemies are stopped in place for
##                      5 s (shock_stuns), which mashing shortens
##   Nature    Poison   damage over time until cured, or until it brings you
##                      to 1 HP (it never kills)
##   Light     Confuse  enemies attack whoever is closest, friend or foe;
##                      Seekers hit and heal friend and foe alike and see
##                      everyone as the same ghost (ConfusionView)
##   Dark      Drain    damage over time that heals whoever applied it
##   (Bind)    Stun     can't move or act, 5 s; on Seekers any hit ends it
## Cure (spell, Cure Salt, Mending Bloom) clears any of them. Burn and Poison
## damage on Seekers scales with difficulty (DIFFICULTY_DOT).
## Buildup decays over time. Generic damage builds nothing.

signal status_started(status: Status)
signal status_ended(status: Status)

## STUN was Paralyze (renamed by Grayson, 2026-11-09). CONFUSE was Blind
## (2026-11-12).
enum Status { BURN, SLOW, FREEZE, SHOCK, POISON, CONFUSE, DRAIN, STUN }

## Seconds. INF lasts until cured (Shock on Seekers; Poison, which also ends
## at 1 HP). Confuse and Drain kept their old lengths (Claude's pick).
const DURATIONS := {
	Status.BURN: 5.0, Status.SLOW: 7.0, Status.FREEZE: 5.0, Status.SHOCK: 5.0,
	Status.POISON: INF, Status.CONFUSE: 4.0, Status.DRAIN: 4.0, Status.STUN: 5.0,
}
## Struggling (Seekers): each button press or stick swing takes this many
## seconds off Freeze, Burn (stick only) or a Goluman's Shock (Claude's number:
## steady mashing about halves a 5 s Freeze).
const STRUGGLE_STEP := 0.25
## Burn and Poison damage on Seekers by difficulty tier (Claude's numbers).
const DIFFICULTY_DOT := {"normal": 1.0, "hard": 1.5, "very_hard": 2.0, "ultimate": 3.0}
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
## Seekers: Burn and Poison damage follows the difficulty tier.
var difficulty_scaled := false


static func find(node: Node) -> StatusEffects:
	if node == null:
		return null
	return node.get_node_or_null("StatusEffects") as StatusEffects


static func for_element(element: Element.Type) -> int:
	match element:
		Element.Type.FIRE:
			return Status.BURN
		Element.Type.ICE:
			return Status.FREEZE  # Slow only comes from traps (Grayson 2026-11-12)
		Element.Type.LIGHTNING:
			return Status.SHOCK
		Element.Type.NATURE:
			return Status.POISON
		Element.Type.LIGHT:
			return Status.CONFUSE
		Element.Type.DARK:
			return Status.DRAIN
	return -1


## Buildup key for a status that comes without an element (Bind's Stun).
const _STATUS_KEY_BASE := 100


func add_buildup(info: DamageInfo, source: Node = null) -> void:
	if info.amount <= 0.0:
		return
	var key := int(info.damage_type)
	if info.inflicts_status >= 0:
		key = _STATUS_KEY_BASE + info.inflicts_status
	elif info.damage_type == Element.Type.GENERIC:
		return
	var value: float = buildup.get(key, 0.0) + info.amount * info.status_power * buildup_scale
	if value < threshold:
		buildup[key] = value
		return
	buildup[key] = 0.0
	var status := info.inflicts_status if info.inflicts_status >= 0 else for_element(info.damage_type)
	if status == Status.DRAIN:
		_drain_source = source
	apply(status)


func apply(status: int, seconds: float = -1.0) -> void:
	if status in immune:
		return
	var fresh := not active.has(status)
	active[status] = seconds if seconds > 0.0 else duration_of(status)
	if fresh:
		status_started.emit(status)


## How long a status lasts on this target (INF = until cured).
func duration_of(status: int) -> float:
	if status == Status.SHOCK and not shock_stuns:
		return INF  # Seekers who aren't Goluman: until cured
	return float(DURATIONS[status])


## Statuses the target can struggle out of: Freeze, Shock where it stops you
## (Goluman), and Burn (stick only).
func struggle_targets(button: bool) -> Array[int]:
	var list: Array[int] = []
	if button:
		list.append(Status.FREEZE)
		if shock_stuns:
			list.append(Status.SHOCK)
	else:
		list.append_array([Status.FREEZE, Status.BURN])
		if shock_stuns:
			list.append(Status.SHOCK)
	return list


## A button press (button = true) or a stick swing: shortens what it can.
## Returns true if anything was shortened.
func struggle(button: bool) -> bool:
	var any := false
	for status in struggle_targets(button):
		if active.has(status) and is_finite(float(active[status])):
			active[status] = float(active[status]) - STRUGGLE_STEP
			any = true
	return any


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
		buildup.erase(_STATUS_KEY_BASE + status)
	if count > CURE_ORDER.size():
		clear_debuffs()


## Statuses in order of annoyance, least first (Cure level 1 clears the first).
const CURE_ORDER: Array[int] = [Status.SLOW, Status.BURN, Status.POISON, Status.CONFUSE,
	Status.DRAIN, Status.SHOCK, Status.STUN, Status.FREEZE]


func _element_for(status: int) -> int:
	match status:
		Status.BURN:
			return Element.Type.FIRE
		Status.FREEZE:
			return Element.Type.ICE
		Status.SHOCK:
			return Element.Type.LIGHTNING
		Status.POISON:
			return Element.Type.NATURE
		Status.CONFUSE:
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


func is_confused() -> bool:
	return is_active(Status.CONFUSE)


func describe() -> String:
	var parts := PackedStringArray()
	for status in active:
		var left := float(active[status])
		parts.append(Status.keys()[status].capitalize() + (" %.1fs" % left if is_finite(left) else ""))
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
		if not active.has(status):
			continue  # ended by its own tick (Poison at 1 HP)
		if active[status] <= 0.0:
			active.erase(status)
			status_ended.emit(status)


func _damage_over_time(status: int) -> void:
	var health := Health.find(get_parent())
	if health == null or health.is_dead():
		return
	var info := DamageInfo.new()
	info.amount = health.max_hp * float(DOT_FRACTION[status]) * TICK
	if difficulty_scaled and (status == Status.BURN or status == Status.POISON):
		info.amount *= float(DIFFICULTY_DOT.get(Session.difficulty, 1.0))
	if status == Status.POISON:
		# Poison never kills: it ends when it brings you to 1 HP.
		info.amount = minf(info.amount, health.hp - 1.0)
		if info.amount <= 0.0:
			active.erase(status)
			status_ended.emit(status)
			return
	info.damage_type = DOT_ELEMENT[status]
	var parent := get_parent() as Node3D
	if parent:
		info.hit_position = parent.global_position + Vector3.UP * 1.6
	var dealt := health.take_damage(info)
	if status == Status.POISON and health.hp <= 1.0 and active.has(status):
		active.erase(status)
		status_ended.emit(status)
	if status == Status.DRAIN and is_instance_valid(_drain_source):
		var source_health := Health.find(_drain_source)
		if source_health and not source_health.is_dead():
			source_health.hp = minf(source_health.hp + dealt, source_health.max_hp)
