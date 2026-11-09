class_name Loadout
extends Resource
## One primary / off-hand setup (a "palette"). LB/RB cycles between them.
##
## Rules (North Star §5.1):
## - A two-handed weapon uses both hands; the other hand stays empty.
## - At most one Heavy item per loadout. The Double-Heavy augment allows two
##   Heavy one-handed items (any pair, including a Heavy Shield with an Axe).
##
## What LT does depends on what's equipped (North Star §4.1); see get_lt_mode().
## A matching pair (same weapon_type, not shields) is powerstanced: every attack
## uses both hands. LT still blocks (arms-up) with a pair.

enum Hand { OFF, PRIMARY }
enum LTMode { NONE, SHIELD, TWO_HAND, ARMS_UP }

## Arms-up block: "slightly weaker than a 2h block".
const ARMS_UP_BLOCK := 0.25

## The primary hand (X) and the off hand (Y). Which side of the body the
## primary hand is on comes from the character's handedness.
@export var primary: WeaponData
@export var off_hand: WeaponData
## Spells (or Goluman traps) on each hand's casting item (Part 6), by slot:
## slot 0 = the hand's button, 1 = RT + it; a two-handed casting item (in the
## primary hand) has 4: X, Y, RT + X, RT + Y. "" = empty.
@export var primary_spells: PackedStringArray = PackedStringArray()
@export var off_spells: PackedStringArray = PackedStringArray()


static func make(primary_weapon: WeaponData, off_weapon: WeaponData) -> Loadout:
	var l := Loadout.new()
	l.primary = primary_weapon
	l.off_hand = off_weapon
	return l


func get_hand(hand: int) -> WeaponData:
	return off_hand if hand == Hand.OFF else primary


func set_hand(hand: int, weapon: WeaponData) -> void:
	if hand == Hand.OFF:
		off_hand = weapon
	else:
		primary = weapon


## How many spell slots the casting item in this hand has (0 if none).
func spell_slot_count(hand: int) -> int:
	var w := get_hand(hand)
	if w == null or not w.casting:
		return 0
	return 4 if w.two_handed else 2


func get_spell(hand: int, slot: int) -> StringName:
	var list := off_spells if hand == Hand.OFF else primary_spells
	if slot < 0 or slot >= list.size():
		return &""
	return StringName(list[slot])


func set_spell(hand: int, slot: int, id: StringName) -> void:
	var list := off_spells if hand == Hand.OFF else primary_spells
	while list.size() <= slot:
		list.append("")
	list[slot] = String(id)
	if hand == Hand.OFF:
		off_spells = list
	else:
		primary_spells = list


func is_empty() -> bool:
	return off_hand == null and primary == null


func two_handed_weapon() -> WeaponData:
	if off_hand and off_hand.two_handed:
		return off_hand
	if primary and primary.two_handed:
		return primary
	return null


## Empty string when valid, otherwise a player-facing reason.
func validate(double_heavy: bool) -> String:
	var two_hand := two_handed_weapon()
	if two_hand and (off_hand != null and primary != null):
		return "%s needs both hands." % two_hand.display_name
	var heavy := 0
	for w in [off_hand, primary]:
		if w and w.is_heavy():
			heavy += 1
	if heavy > 1 and not double_heavy:
		return "Only one Heavy item per loadout. The Double-Heavy augment allows two."
	return ""


func get_lt_mode() -> LTMode:
	if is_empty():
		return LTMode.NONE
	if (off_hand and off_hand.is_shield) or (primary and primary.is_shield):
		return LTMode.SHIELD
	if two_handed_weapon():
		return LTMode.TWO_HAND
	return LTMode.ARMS_UP


## Two one-handed weapons of the same type (Sword + Frost Sword): always twin.
func is_powerstance() -> bool:
	return off_hand != null and primary != null and not off_hand.is_shield \
		and off_hand.weapon_type != &"" and off_hand.weapon_type == primary.weapon_type


func block_strength() -> float:
	match get_lt_mode():
		LTMode.SHIELD:
			var best := 0.0
			for w in [off_hand, primary]:
				if w and w.is_shield:
					best = maxf(best, w.block_strength)
			return best
		LTMode.TWO_HAND:
			return two_handed_weapon().block_strength
		LTMode.ARMS_UP:
			return ARMS_UP_BLOCK
	return 0.0


func describe() -> String:
	var two_hand := two_handed_weapon()
	if two_hand:
		return two_hand.display_name + " (both hands)"
	var text := "%s / %s" % [primary.display_name if primary else "-", off_hand.display_name if off_hand else "-"]
	return text + (" (powerstance)" if is_powerstance() else "")
