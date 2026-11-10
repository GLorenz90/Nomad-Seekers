class_name Accuracy
extends RefCounted
## Hit chance (Part 6). PSO's accuracy, made a little kinder, plus Chrono
## Cross's ramp where every landed hit makes the next one more likely.
##
## Attacker: effective ATA = ATA x attack type x combo step (PSO).
##   Attack type: Normal 1.0, Hard 0.9 (0.7 when it opens a combo), RT special
##   0.8, sustained ticks 1.0.
##   Combo step: 1.0, 1.3, 1.69 for steps 1, 2, 3 (PSO).
## Defender: effective EVA = EVA x status (Frozen 0.7, Shocked / Stunned 0.85).
## Hit % = BASE + effective ATA - effective EVA x 0.2 + streak bonus, 5..100.
##   BASE (60) is the kindness: PSO has none, and needs ATA in the hundreds.
##   Streak bonus: +4 per hit already landed in this combo, up to +12.
## Spells never miss (DamageInfo.accuracy < 0).

const BASE := 60.0
const EVA_WEIGHT := 0.2
const COMBO := [1.0, 1.3, 1.69]
const TYPE_NORMAL := 1.0
const TYPE_HARD := 0.9
const TYPE_HARD_OPENER := 0.7
const TYPE_SPECIAL := 0.8
const STREAK_STEP := 4.0
const STREAK_MAX := 12.0
const MIN_CHANCE := 5.0
const MAX_CHANCE := 100.0
## Frozen enemies are easier to hit; Shocked / Stunned a little (PSO).
const FROZEN_EVA := 0.7
const STUNNED_EVA := 0.85


## Effective ATA for one attack.
static func effective_ata(ata: float, hard: bool, special: bool, sustained: bool, chain_step: int) -> float:
	var type := TYPE_NORMAL
	if special:
		type = TYPE_SPECIAL
	elif hard and not sustained:
		type = TYPE_HARD_OPENER if chain_step <= 1 else TYPE_HARD
	return ata * type * COMBO[clampi(chain_step - 1, 0, COMBO.size() - 1)]


static func streak_bonus(hits_landed: int) -> float:
	return minf(hits_landed * STREAK_STEP, STREAK_MAX)


## Hit chance in percent for a hit against a defender with this EVA.
static func hit_percent(info: DamageInfo, eva: float, defender_status: StatusEffects = null) -> float:
	if info.accuracy < 0.0:
		return 100.0
	var eff_eva := eva
	if defender_status:
		if defender_status.is_active(StatusEffects.Status.FREEZE):
			eff_eva *= FROZEN_EVA
		elif defender_status.is_active(StatusEffects.Status.SHOCK) \
				or defender_status.is_active(StatusEffects.Status.STUN):
			eff_eva *= STUNNED_EVA
	var chance := BASE + info.accuracy - eff_eva * EVA_WEIGHT + info.hit_bonus
	return clampf(chance, MIN_CHANCE, MAX_CHANCE)


## Rolls the hit. On a miss, marks the info and shows "Miss" at the target.
static func roll(info: DamageInfo, eva: float, defender: Node3D, defender_status: StatusEffects = null) -> bool:
	if randf() * 100.0 < hit_percent(info, eva, defender_status):
		return true
	info.missed = true
	if defender and defender.is_inside_tree():
		DamageNumber.spawn_text(defender.get_parent(), defender.global_position + Vector3.UP * 1.9, "Miss")
	return false
