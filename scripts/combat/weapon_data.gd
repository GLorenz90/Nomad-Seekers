class_name WeaponData
extends Resource
## A weapon or casting item (North Star §5).
##
## normal_attacks / hard_attacks hold steps 1-3. Which step plays depends on how
## many times in a row THIS weapon has been used in the current chain, so mixing
## weapons restarts each weapon's animation at step 1.

enum WeaponClass { MELEE, RANGED, MAGIC }
enum Weight { LIGHT, HEAVY }

@export var display_name := ""
## Weapons of the same type powerstance together, even different items
## (a Sword and a Frost Sword).
@export var weapon_type: StringName = &""
@export var weapon_class: WeaponClass = WeaponClass.MELEE
@export var weight: Weight = Weight.LIGHT
@export var two_handed := false
## Single standalone attack, never part of a chain.
@export var no_combo := false
## Exists only to cast spells. Spells never build a chain.
@export var casting := false
## Holding the button runs sustained_attack for as long as it's held, in place
## of a Hard attack (North Star "Sustained" tag).
@export var sustained := false
## Shields block with LT; their hand button deflects (light) or shoves (heavy).
@export var is_shield := false
## Fraction of damage stopped when blocking with LT. Shields set their own;
## two-handed weapons default to about half a light shield.
@export_range(0.0, 1.0) var block_strength := 0.3
@export var base_damage := 10.0
@export var damage_type: Element.Type = Element.Type.GENERIC

@export var normal_attacks: Array[AttackData] = []
@export var hard_attacks: Array[AttackData] = []
## Casting items only: slot 0 on the hand button, slot 1 with Shift (RT) held.
@export var spells: Array[SpellData] = []
## Sustained weapons only. Its duration is the wind-down after release.
@export var sustained_attack: AttackData
## RT (Shift) + this hand's button uses this instead of the normal step
## (North Star §5.2 special tags, filled in by Part 5). Null = no special, so
## RT + the button is just a normal attack. There is no Hard special.
@export var special_attack: AttackData

@export_group("Placeholder visual")
@export var mesh_size := Vector3(0.08, 0.08, 1.0)
@export var mesh_color := Color(0.8, 0.8, 0.85)


func get_attack(step: int, hard: bool, spell_slot: int = 0, special: bool = false) -> AttackData:
	if special and special_attack and not casting:
		return special_attack
	if casting:
		if spells.is_empty():
			return null
		var spell := spells[clampi(spell_slot, 0, spells.size() - 1)]
		return spell.hard if hard else spell.normal
	if hard and sustained:
		return sustained_attack
	var list := hard_attacks if hard else normal_attacks
	if list.is_empty():
		return null
	return list[clampi(step - 1, 0, list.size() - 1)]


func is_heavy() -> bool:
	return weight == Weight.HEAVY


func get_spell_name(spell_slot: int) -> String:
	if not casting or spells.is_empty():
		return ""
	return spells[clampi(spell_slot, 0, spells.size() - 1)].display_name
