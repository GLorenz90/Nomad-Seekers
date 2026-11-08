class_name DamageInfo
extends RefCounted
## One hit's worth of damage, built by the attacker and resolved by HitResolver.

## Which defense stat applies: DEF vs melee, EVA vs ranged, RES vs magic.
enum Kind { MELEE, RANGED, MAGIC }

var amount := 0.0
var damage_type: Element.Type = Element.Type.GENERIC
var kind: Kind = Kind.MELEE
## Multiplies how much status buildup this hit adds (amount x status_power).
var status_power := 1.0
var is_hard := false
var is_crit := false
var source: Node = null
var hit_position := Vector3.ZERO
## Set by HitResolver when the target's EVA made it miss.
var missed := false
## The weapon this hit came from (null for enemy hits). Enemies read its
## monster-type bonus (WeaponData.type_bonus).
var weapon: WeaponData
## True for an RT special: the weapon's tag effect applies on hit.
var special := false


static func kind_for(weapon_class: WeaponData.WeaponClass) -> Kind:
	match weapon_class:
		WeaponData.WeaponClass.RANGED:
			return Kind.RANGED
		WeaponData.WeaponClass.MAGIC:
			return Kind.MAGIC
	return Kind.MELEE


## A copy for one more target (explosions hit several bodies).
func duplicate_info() -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount
	d.damage_type = damage_type
	d.kind = kind
	d.status_power = status_power
	d.is_hard = is_hard
	d.is_crit = is_crit
	d.source = source
	d.hit_position = hit_position
	d.weapon = weapon
	d.special = special
	return d
