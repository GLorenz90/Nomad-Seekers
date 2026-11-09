class_name Stats
extends Resource
## Character stats (North Star §3). Placeholder values until stat growth tables exist.

@export var strength := 30.0   ## Melee damage
@export var dexterity := 30.0  ## Ranged damage
@export var soul := 40.0       ## Magic damage, and what spells need to be learned
@export var defense := 20.0    ## Melee defense
@export var resolve := 20.0    ## Magic defense
@export var evasion := 20.0    ## EVA: how often enemy attacks miss you (Accuracy)
@export var accuracy := 40.0   ## ATA: how often your weapon attacks land (Accuracy)
@export var luck := 10.0       ## Crit chance (0.5% per point)

@export var max_hp := 300.0
@export var max_lp := 100.0
## Flat LP regen per second (0: nobody regenerates LP by default, like PSO's
## TP; Goluman and Lumera regen a share of max LP, CombatController
## lp_regen_fraction). Kept for gear or buffs later. Was 6 as a prototype
## convenience until 2026-11-09; the Debug tab has Infinite LP for testing.
@export var lp_regen_per_second := 0.0


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
