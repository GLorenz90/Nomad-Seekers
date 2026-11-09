class_name Loadout
extends Resource
## One left-hand / right-hand setup (a "palette"). LB/RB cycles between them.
##
## Rules (North Star §5.1):
## - A two-handed weapon uses both hands; the other hand stays empty.
## - At most one Heavy item per loadout. The Double-Heavy augment allows two
##   Heavy one-handed items (any pair, including a Heavy Shield with an Axe).
##
## What LT does depends on what's equipped (North Star §4.1); see get_lt_mode().
## A matching pair (same weapon_type, not shields) is powerstanced: every attack
## uses both hands. LT still blocks (arms-up) with a pair.

enum Hand { LEFT, RIGHT }
enum LTMode { NONE, SHIELD, TWO_HAND, ARMS_UP }

## Arms-up block: "slightly weaker than a 2h block".
const ARMS_UP_BLOCK := 0.25

@export var left: WeaponData
@export var right: WeaponData
## Spells (or Goluman traps) on each hand's casting item (Part 6), by slot:
## slot 0 = the hand's button, 1 = RT + it; a two-handed casting item (in the
## right hand) has 4: X, Y, RT + X, RT + Y. "" = empty.
@export var left_spells: PackedStringArray = PackedStringArray()
@export var right_spells: PackedStringArray = PackedStringArray()


static func make(left_weapon: WeaponData, right_weapon: WeaponData) -> Loadout:
	var l := Loadout.new()
	l.left = left_weapon
	l.right = right_weapon
	return l


func get_hand(hand: int) -> WeaponData:
	return left if hand == Hand.LEFT else right


func set_hand(hand: int, weapon: WeaponData) -> void:
	if hand == Hand.LEFT:
		left = weapon
	else:
		right = weapon


## How many spell slots the casting item in this hand has (0 if none).
func spell_slot_count(hand: int) -> int:
	var w := get_hand(hand)
	if w == null or not w.casting:
		return 0
	return 4 if w.two_handed else 2


func get_spell(hand: int, slot: int) -> StringName:
	var list := left_spells if hand == 0 else right_spells
	if slot < 0 or slot >= list.size():
		return &""
	return StringName(list[slot])


func set_spell(hand: int, slot: int, id: StringName) -> void:
	var list := left_spells if hand == 0 else right_spells
	while list.size() <= slot:
		list.append("")
	list[slot] = String(id)
	if hand == 0:
		left_spells = list
	else:
		right_spells = list


func is_empty() -> bool:
	return left == null and right == null


func two_handed_weapon() -> WeaponData:
	if left and left.two_handed:
		return left
	if right and right.two_handed:
		return right
	return null


## Empty string when valid, otherwise a player-facing reason.
func validate(double_heavy: bool) -> String:
	var two_hand := two_handed_weapon()
	if two_hand and (left != null and right != null):
		return "%s needs both hands." % two_hand.display_name
	var heavy := 0
	for w in [left, right]:
		if w and w.is_heavy():
			heavy += 1
	if heavy > 1 and not double_heavy:
		return "Only one Heavy item per loadout. The Double-Heavy augment allows two."
	return ""


func get_lt_mode() -> LTMode:
	if is_empty():
		return LTMode.NONE
	if (left and left.is_shield) or (right and right.is_shield):
		return LTMode.SHIELD
	if two_handed_weapon():
		return LTMode.TWO_HAND
	return LTMode.ARMS_UP


## Two one-handed weapons of the same type (Sword + Frost Sword): always twin.
func is_powerstance() -> bool:
	return left != null and right != null and not left.is_shield \
		and left.weapon_type != &"" and left.weapon_type == right.weapon_type


func block_strength() -> float:
	match get_lt_mode():
		LTMode.SHIELD:
			var best := 0.0
			for w in [left, right]:
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
	var text := "%s / %s" % [left.display_name if left else "-", right.display_name if right else "-"]
	return text + (" (powerstance)" if is_powerstance() else "")
