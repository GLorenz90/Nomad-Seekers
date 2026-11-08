class_name Stats
extends Resource
## Character stats (North Star §3). Placeholder values until stat growth tables exist.

@export var strength := 30.0   ## Melee damage
@export var dexterity := 30.0  ## Ranged damage
@export var soul := 30.0       ## Magic damage
@export var defense := 20.0    ## Melee defense
@export var resolve := 20.0    ## Magic defense
@export var evasion := 20.0    ## Ranged defense + miss chance
@export var luck := 10.0       ## Crit chance (0.5% per point)

@export var max_hp := 300.0
@export var max_lp := 100.0
## Prototype convenience so testing never stalls. Tune or remove later.
@export var lp_regen_per_second := 6.0


func attack_stat(weapon_class: WeaponData.WeaponClass) -> float:
	match weapon_class:
		WeaponData.WeaponClass.RANGED:
			return dexterity
		WeaponData.WeaponClass.MAGIC:
			return soul
		_:
			return strength


func crit_chance() -> float:
	return luck * 0.005
