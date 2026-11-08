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


static func kind_for(weapon_class: WeaponData.WeaponClass) -> Kind:
	match weapon_class:
		WeaponData.WeaponClass.RANGED:
			return Kind.RANGED
		WeaponData.WeaponClass.MAGIC:
			return Kind.MAGIC
	return Kind.MELEE
