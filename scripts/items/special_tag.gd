class_name SpecialTag
extends Resource
## A weapon special tag line (North Star §5.2). Each line has tiers; later
## names are stronger versions of the same effect. The tag gives the weapon
## its RT special. Reworked 2026-11-12 (Grayson): our own names, and three
## kinds of line:
## - STATUS (one per element): the weapon deals that element; the special
##   hits for half damage but builds the element's status hard.
## - BURST (one per element): the weapon deals that element; the special hits
##   x1.3 and bursts on the target, hitting a couple of enemies nearby, for
##   more LP.
## - Element-less lines (instant kill, HP / LP / EXP steal, HP cut, Charge):
##   the weapon keeps its own damage type.

enum Effect { STATUS, BURST, INSTANT_KILL, DRAIN_HP, STEAL_LP, STEAL_EXP, CUT_HP, CHARGE }

@export var line_name := ""
@export var tier_names := PackedStringArray()
@export var effect: Effect = Effect.STATUS
## STATUS and BURST lines: their element (the weapon's damage type).
@export var element: Element.Type = Element.Type.GENERIC
## Left from the Bind line (2026-11-12, morning); unused now.
@export var status := -1

## Per-tier strengths (index = tier).
## STATUS specials hit for half damage, so their buildup power is doubled.
const STATUS_SPECIAL_DAMAGE := 0.5
const STATUS_POWER := [6.0, 10.0, 14.0, 18.0]
const BURST_SPECIAL_DAMAGE := 1.3
## The burst: radius (m) and how many other enemies it reaches, at the
## damage dealt to the target.
const BURST_RADIUS := 3.0
const BURST_EXTRA_TARGETS := 2
const KILL_CHANCE := [0.05, 0.1, 0.15, 0.2]
const DRAIN_FRACTION := [0.1, 0.15, 0.2, 0.25]
const LP_FRACTION := [0.1, 0.15, 0.2, 0.25]
const EXP_FRACTION := [0.05, 0.1, 0.15]
const CUT_FRACTION := [0.25, 0.4]
## Charge line tiers: what each spends for its x3 hit.
const CHARGE_COSTS := ["oro", "lp", "hp"]
const CHARGE_ORO := 100
const CHARGE_LP := 30.0
const CHARGE_HP_FRACTION := 0.15

## Each element's status, for descriptions.
const ELEMENT_STATUS := {Element.Type.FIRE: "Burn", Element.Type.ICE: "Freeze",
	Element.Type.LIGHTNING: "Shock", Element.Type.NATURE: "Poison", Element.Type.LIGHT: "Confuse",
	Element.Type.DARK: "Drain"}

## Lines renamed on 2026-11-12, old name -> new, so weapons in older saves
## (and the rares) pick up the new line. "Heat" kept its name.
const RENAMED := {"Ice": "Chill", "Shock": "Spark", "Bind": "Static", "Panic": "Dazzle",
	"Dim": "Grim", "Draw": "Leech", "Mind": "Lucid", "Master's": "Mentor's",
	"Devil's": "Rending", "Charge": "Tithe"}


static func all_lines() -> Array[SpecialTag]:
	var lines: Array[SpecialTag] = []
	# Status lines: half-damage special, strong status.
	lines.append(_line("Smolder", ["Smolder", "Scorch", "Sear", "Immolate"], Effect.STATUS, Element.Type.FIRE))
	lines.append(_line("Chill", ["Chill", "Frost", "Rime", "Glacial"], Effect.STATUS, Element.Type.ICE))
	lines.append(_line("Static", ["Static", "Jolt", "Shock", "Overload"], Effect.STATUS, Element.Type.LIGHTNING))
	lines.append(_line("Toxic", ["Toxic", "Venom", "Blight", "Plague"], Effect.STATUS, Element.Type.NATURE))
	lines.append(_line("Dazzle", ["Dazzle", "Daze", "Bewilder", "Delirium"], Effect.STATUS, Element.Type.LIGHT))
	lines.append(_line("Gloom", ["Gloom", "Wither", "Decay", "Entropy"], Effect.STATUS, Element.Type.DARK))
	# Burst lines: x1.3 special that bursts onto nearby enemies.
	lines.append(_line("Heat", ["Heat", "Fire", "Flame", "Inferno"], Effect.BURST, Element.Type.FIRE))
	lines.append(_line("Shard", ["Shard", "Hail", "Shatter", "Avalanche"], Effect.BURST, Element.Type.ICE))
	lines.append(_line("Spark", ["Spark", "Bolt", "Thunder", "Skyfall"], Effect.BURST, Element.Type.LIGHTNING))
	lines.append(_line("Thorn", ["Thorn", "Bramble", "Briar", "Overgrowth"], Effect.BURST, Element.Type.NATURE))
	lines.append(_line("Glint", ["Glint", "Gleam", "Radiant", "Sunburst"], Effect.BURST, Element.Type.LIGHT))
	lines.append(_line("Shade", ["Shade", "Dusk", "Void", "Abyss"], Effect.BURST, Element.Type.DARK))
	# Element-less lines.
	lines.append(_line("Grim", ["Grim", "Doom", "Reaper", "Oblivion"], Effect.INSTANT_KILL))
	lines.append(_line("Leech", ["Leech", "Siphon", "Vampire", "Sanguine"], Effect.DRAIN_HP))
	lines.append(_line("Lucid", ["Lucid", "Focus", "Insight", "Epiphany"], Effect.STEAL_LP))
	lines.append(_line("Mentor's", ["Mentor's", "Sage's", "Oracle's"], Effect.STEAL_EXP))
	lines.append(_line("Rending", ["Rending", "Sundering"], Effect.CUT_HP))
	lines.append(_line("Tithe", ["Tithe", "Zeal", "Frenzy"], Effect.CHARGE))
	return lines


## The current line with this name (or its name before 2026-11-12).
static func find_line(name: String) -> SpecialTag:
	var wanted: String = RENAMED.get(name, name)
	for line in all_lines():
		if line.line_name == wanted:
			return line
	return null


static func _line(name: String, tiers: Array, effect_kind: Effect,
		element_type: Element.Type = Element.Type.GENERIC) -> SpecialTag:
	var t := SpecialTag.new()
	t.line_name = name
	t.tier_names = PackedStringArray(tiers)
	t.effect = effect_kind
	t.element = element_type
	return t


func tier_count() -> int:
	return tier_names.size()


func name_for(tier: int) -> String:
	return tier_names[clampi(tier, 0, tier_names.size() - 1)]


## Status and burst lines make the weapon deal their element.
func sets_weapon_element() -> bool:
	return effect == Effect.STATUS or effect == Effect.BURST


## Short player-facing description of what the RT special does at this tier.
func describe(tier: int) -> String:
	tier = clampi(tier, 0, tier_count() - 1)
	match effect:
		Effect.STATUS:
			return "half damage, strong %s" % ELEMENT_STATUS.get(element, "status")
		Effect.BURST:
			return "%s burst: x%.1f, hits %d nearby" % [Element.name_of(element), BURST_SPECIAL_DAMAGE, BURST_EXTRA_TARGETS]
		Effect.INSTANT_KILL:
			return "%d%% instant kill (not bosses)" % roundi(KILL_CHANCE[tier] * 100.0)
		Effect.DRAIN_HP:
			return "heals %d%% of damage" % roundi(DRAIN_FRACTION[tier] * 100.0)
		Effect.STEAL_LP:
			return "restores LP: %d%% of damage" % roundi(LP_FRACTION[tier] * 100.0)
		Effect.STEAL_EXP:
			return "steals EXP: +%d%% of the target's" % roundi(EXP_FRACTION[tier] * 100.0)
		Effect.CUT_HP:
			return "cuts %d%% of the target's HP, costs you 10%%" % roundi(CUT_FRACTION[tier] * 100.0)
		Effect.CHARGE:
			match CHARGE_COSTS[tier]:
				"oro":
					return "x3 hit for %d Oro" % CHARGE_ORO
				"lp":
					return "x3 hit for %d LP" % roundi(CHARGE_LP)
			return "x3 hit for 15% of your HP"
	return ""


## Builds the RT special for a weapon carrying this tag: its first attack,
## changed by the line, costing LP (special attacks always cost some LP).
func make_special(weapon: WeaponData) -> AttackData:
	var a := (weapon.normal_attacks[0] as AttackData).duplicate() as AttackData
	var tier := clampi(weapon.tag_tier, 0, tier_count() - 1)
	a.display_name = "%s Special" % name_for(tier)
	match effect:
		Effect.STATUS:
			a.damage_mult *= STATUS_SPECIAL_DAMAGE
			a.lp_cost += 4.0 + tier * 2.0
			a.override_damage_type = true
			a.damage_type = element
			a.status_power = STATUS_POWER[mini(tier, 3)]
		Effect.BURST:
			a.damage_mult *= BURST_SPECIAL_DAMAGE
			a.lp_cost += 8.0 + tier * 4.0  # a bigger chunk of LP than other specials
			a.override_damage_type = true
			a.damage_type = element
		Effect.CHARGE:
			a.damage_mult *= 3.0
			a.lp_cost = 4.0
		_:
			a.damage_mult *= 1.3
			a.lp_cost += 4.0 + tier * 2.0
	return a
