class_name SpecialTag
extends Resource
## A weapon special tag line (North Star §5.2, PSO's special list). Each line
## has tiers; later names in the line are stronger versions of the same effect.
## The tag unlocks the weapon's RT special. Elemental lines also give the
## weapon that damage type. Tag names stay PSO's (they're generic words).

enum Effect { ELEMENT, INSTANT_KILL, DRAIN_HP, STEAL_LP, STEAL_EXP, CUT_HP, CHARGE }

@export var line_name := ""
@export var tier_names := PackedStringArray()
@export var effect: Effect = Effect.ELEMENT
## ELEMENT lines: the element (and status) they bring.
@export var element: Element.Type = Element.Type.GENERIC

## Per-tier strengths (index = tier).
const STATUS_POWER := [3.0, 5.0, 7.0, 9.0]
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


static func all_lines() -> Array[SpecialTag]:
	var lines: Array[SpecialTag] = []
	lines.append(_line("Heat", ["Heat", "Fire", "Flame", "Burning"], Effect.ELEMENT, Element.Type.FIRE))
	lines.append(_line("Ice", ["Ice", "Frost", "Freeze", "Blizzard"], Effect.ELEMENT, Element.Type.ICE))
	lines.append(_line("Shock", ["Shock", "Thunder", "Storm", "Tempest"], Effect.ELEMENT, Element.Type.LIGHTNING))
	# North Star SP2 (open): the Bind line maps to Nature until decided.
	lines.append(_line("Bind", ["Bind", "Hold", "Seize", "Arrest"], Effect.ELEMENT, Element.Type.NATURE))
	lines.append(_line("Panic", ["Panic", "Riot", "Havoc", "Chaos"], Effect.ELEMENT, Element.Type.LIGHT))
	lines.append(_line("Dim", ["Dim", "Shadow", "Dark", "Hell"], Effect.INSTANT_KILL, Element.Type.DARK))
	lines.append(_line("Draw", ["Draw", "Drain", "Fill", "Gush"], Effect.DRAIN_HP, Element.Type.DARK))
	lines.append(_line("Mind", ["Mind", "Soul", "Psyche", "Geist"], Effect.STEAL_LP))
	lines.append(_line("Master's", ["Master's", "Lord's", "King's"], Effect.STEAL_EXP))
	lines.append(_line("Devil's", ["Devil's", "Demon's"], Effect.CUT_HP))
	lines.append(_line("Charge", ["Charge", "Spirit", "Berserk"], Effect.CHARGE))
	return lines


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


## Only elemental lines change the weapon's damage type. Dim and Draw are
## listed as Dark in North Star but only their special carries Dark.
func sets_weapon_element() -> bool:
	return effect == Effect.ELEMENT


## Short player-facing description of what the RT special does at this tier.
func describe(tier: int) -> String:
	tier = clampi(tier, 0, tier_count() - 1)
	match effect:
		Effect.ELEMENT:
			return "%s damage, strong %s" % [Element.name_of(element),
				["Burn", "Freeze", "Shock", "Poison", "Blind", "Drain"][int(element) - 1]]
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
## a bit stronger, costing LP (special attacks always cost some LP).
func make_special(weapon: WeaponData) -> AttackData:
	var a := (weapon.normal_attacks[0] as AttackData).duplicate() as AttackData
	var tier := clampi(weapon.tag_tier, 0, tier_count() - 1)
	a.display_name = "%s Special" % name_for(tier)
	a.damage_mult *= 1.3
	a.lp_cost += 4.0 + tier * 2.0
	if effect == Effect.ELEMENT or effect == Effect.INSTANT_KILL or effect == Effect.DRAIN_HP:
		if element != Element.Type.GENERIC:
			a.override_damage_type = true
			a.damage_type = element
		a.status_power = STATUS_POWER[mini(tier, 3)]
	if effect == Effect.CHARGE:
		a.damage_mult *= 3.0 / 1.3
		a.lp_cost = 4.0
	return a
