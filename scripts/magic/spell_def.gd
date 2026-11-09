class_name SpellDef
extends RefCounted
## One spell (or Goluman trap) from Grayson's spell grid (Part 6). Built in
## SpellBook; never saved. Learned spells live on CharacterData.spells as
## {id: level}; casting items hold spell ids per loadout hand (Loadout).
##
## Power follows PSO's technique math (Ephinea wiki):
##   technique base power (TBP) = base + growth x (level - 1), with a second
##   base / growth for levels 16-30;
##   damage = (SOL + TBP) / 5 x casting-item power x Hard bonus.
## Learning needs SOL (Seeker + SyncAIDa): base at level 1, then +20 a level
## through level 15 and +40 a level after that (Cure +25 a level; Revive +30
## a level for its first half, +60 after). Traps use DEX the same way.

enum Kind { BOLT, BURST, AREA, SUSTAINED, BUFF, DEBUFF, AURA, HEAL, CURE, TELEPORTAL, REVIVE, TRAP }

## How the spell reaches its targets (SpellCaster).
enum Shape {
	PROJECTILE,      ## a ball that flies straight (Foie)
	PIERCE_LINE,     ## a fast spear through everything in a line
	SKY_STRIKE,      ## strikes the target from above (Zonde, Grants)
	GROUND_LINE,     ## a wave along the ground through a line (Barta)
	HOMING_ORB,      ## a slow orb that follows its target (Megid)
	RING_OUT,        ## a ring spreading out from the caster (Gifoie, Rabarta)
	SPEAR_FAN,       ## a fan of piercing spears (shotgun)
	CHAIN,           ## jumps from target to target (Gizonde)
	CONE_STRIKE,     ## hits everything in a cone in front
	BIG_ORB,         ## a large slow ball through everything ahead
	TARGET_AREA,     ## everything around the target point (Rafoie, Razonde)
	AROUND_CASTER,   ## everything around the caster
	GRAVITY_PIT,     ## pulls enemies to a point while damaging them
	CHANNEL,         ## held: a cone in front, ticking (PSU Dam- techniques)
	SELF,            ## buffs, auras, heals, cures, portals
}

const REQ_STANDARD := [20, 40]
const REQ_CURE := [25, 25]
const REQ_REVIVE := [30, 60]
const REQ_NONE := [0, 0]

var id: StringName
var display_name := ""
var element: Element.Type = Element.Type.GENERIC
var kind: Kind = Kind.BOLT
var shape: Shape = Shape.PROJECTILE
## SOL (DEX for traps) needed for level 1, and how it rises per level.
var req_base := 40
var req_steps: Array = REQ_STANDARD
var max_level := 30
## PSO technique base power: [base, growth] for levels 1-15 and 16-30.
var power_low := Vector2(110, 50)
var power_high := Vector2(-85, 65)
## LP cost: base + growth x (level - 1) (PSO TP formulas).
var lp_base := 5.0
var lp_growth := 1.3
## Cast timing in frames at 30 fps (Foie: effect at 15 of 35).
var cast_frames := 15
var total_frames := 35
## Single-target spells can't inflict status (Grayson's grid).
var status_ok := true
## Shape parameters.
var speed := 14.0
var speed_growth := 0.8
var radius := 3.0
var radius_growth := 0.08
var reach := 14.0
var cone_deg := 30.0
var max_targets := 10
var pierce := false
## Buff / debuff stat (StatusEffects.MODIFIED_STATS).
var stat: StringName = &""
## Trap status (StatusEffects.Status) or -1.
var trap_status := -1
var notes := ""


## Damage-per-level and everything else derived from the tables above.
func power(level: int) -> float:
	level = clampi(level, 1, max_level)
	if level <= 15:
		return power_low.x + power_low.y * (level - 1)
	return power_high.x + power_high.y * (level - 1)


func lp_cost(level: int) -> float:
	return snappedf(lp_base + lp_growth * (clampi(level, 1, max_level) - 1), 0.1)


## SOL (or DEX for traps) needed to learn this level.
func requirement(level: int) -> int:
	level = clampi(level, 1, max_level)
	var half := ceili(max_level / 2.0)
	var low := mini(level, half) - 1
	var high := maxi(level - half, 0)
	return req_base + int(req_steps[0]) * low + int(req_steps[1]) * high


func requirement_stat() -> String:
	return "DEX" if kind == Kind.TRAP else "SOL"


func is_trap() -> bool:
	return kind == Kind.TRAP


func is_support() -> bool:
	return kind in [Kind.BUFF, Kind.DEBUFF, Kind.HEAL, Kind.CURE, Kind.TELEPORTAL, Kind.REVIVE]


func kind_name() -> String:
	return ["Single target", "Small burst", "Large area", "Sustained", "Buff", "Debuff", "Aura",
		"Heal", "Cure", "Teleportal", "Revive", "Trap"][kind]


func element_name() -> String:
	if is_trap():
		return "Trap"
	if element == Element.Type.GENERIC:
		return "Typeless"
	return Element.name_of(element)
