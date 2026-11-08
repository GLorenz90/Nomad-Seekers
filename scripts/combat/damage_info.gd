class_name DamageInfo
extends RefCounted
## One hit's worth of damage, built by the attacker and resolved by Health.

var amount := 0.0
var damage_type: Element.Type = Element.Type.GENERIC
var is_hard := false
var is_crit := false
var source: Node = null
var hit_position := Vector3.ZERO
