extends SceneTree
## Writes the first enemy roster (one per monster type, North Star §2.6) to
## res://data/enemies/*.tres. The .tres files are the source of truth: edit
## them in the Inspector. Rerun this only to reset them to these defaults:
##   godot --headless --path . --script res://tools/build_enemies.gd


func _initialize() -> void:
	for e in [_hound(), _crawler(), _drone(), _umbral(), _ooze(), _sprite()]:
		var path := "res://data/enemies/%s.tres" % e.display_name.to_snake_case()
		print("%s -> %s" % [path, error_string(ResourceSaver.save(e, path))])
	quit()


## Part 6 hit chance: EVA (vs Seeker weapons) and ATA (its own attacks).
const HIT_STATS := {
	"Grub Hound": [60.0, 50.0], "Mutated Crawler": [90.0, 55.0], "Sentry Drone": [50.0, 60.0],
	"Umbral Eye": [70.0, 55.0], "Caustic Ooze": [30.0, 40.0], "Lumen Sprite": [140.0, 60.0],
}


func _base(name: String, type: EnemyData.EnemyType, notes: String) -> EnemyData:
	var e := EnemyData.new()
	e.display_name = name
	e.enemy_type = type
	e.notes = notes
	if HIT_STATS.has(name):
		e.evasion = HIT_STATS[name][0]
		e.accuracy = HIT_STATS[name][1]
	return e


## BEAST: the baseline brawler. Closes in and swipes.
func _hound() -> EnemyData:
	var e := _base("Grub Hound", EnemyData.EnemyType.BEAST,
		"Ordinary native predator. Charges in and swipes in front of it.")
	e.max_hp = 130.0
	e.defense = 15.0
	e.move_speed = 4.5
	e.attack_damage = 18.0
	e.attack_range = 2.0
	e.windup = 0.55
	e.recovery = 0.6
	e.attack_interval = 1.8
	e.weak_to = Element.Type.FIRE
	e.color = Color(0.55, 0.38, 0.25)
	e.size = Vector3(1.0, 1.4, 1.3)
	return e


## MUTATED: fast and fragile, poisons. Regressed by the Caves boss.
func _crawler() -> EnemyData:
	var e := _base("Mutated Crawler", EnemyData.EnemyType.MUTATED,
		"Underground native twisted by the corrupted Caves boss. Fast, quick bite, Poison.")
	e.max_hp = 90.0
	e.defense = 8.0
	e.move_speed = 6.0
	e.attack_damage = 12.0
	e.attack_element = Element.Type.NATURE
	e.status_power = 2.5
	e.attack_range = 1.8
	e.windup = 0.35
	e.recovery = 0.5
	e.attack_interval = 1.4
	e.weak_to = Element.Type.FIRE
	e.resists = Element.Type.NATURE
	e.color = Color(0.45, 0.7, 0.3)
	e.size = Vector3(0.8, 0.9, 1.2)
	e.shape = EnemyData.Shape.BOX
	return e


## SYNTHETIC: a robot gunner that keeps its distance. Lightning bolts stun.
func _drone() -> EnemyData:
	var e := _base("Sentry Drone", EnemyData.EnemyType.SYNTHETIC,
		"Malfunctioning security robot. Holds ~9 m and fires Lightning bolts (ranged, reflectable).")
	e.max_hp = 140.0
	e.defense = 30.0
	e.resolve = 5.0
	e.move_speed = 3.0
	e.attack_style = EnemyData.AttackStyle.RANGED
	e.attack_damage = 14.0
	e.attack_element = Element.Type.LIGHTNING
	e.status_power = 1.5
	e.attack_range = 10.0
	e.min_range = 5.0
	e.windup = 0.6
	e.recovery = 0.5
	e.attack_interval = 2.2
	e.projectile_speed = 14.0
	e.weak_to = Element.Type.LIGHTNING
	e.resists = Element.Type.ICE
	e.color = Color(0.55, 0.58, 0.62)
	e.size = Vector3(1.0, 1.2, 1.0)
	e.shape = EnemyData.Shape.BOX
	e.hover_height = 0.4
	return e


## DARK: Malbona Mallumo's spawn. Slow caster whose bolts Drain.
func _umbral() -> EnemyData:
	var e := _base("Umbral Eye", EnemyData.EnemyType.DARK,
		"Alien-eldritch spawn of Malbona Mallumo. Hangs back and casts Dark bolts that Drain (magic, reflectable).")
	e.max_hp = 110.0
	e.resolve = 35.0
	e.move_speed = 2.6
	e.attack_style = EnemyData.AttackStyle.SPELL
	e.attack_damage = 20.0
	e.attack_element = Element.Type.DARK
	e.status_power = 2.0
	e.attack_range = 12.0
	e.min_range = 6.0
	e.windup = 0.9
	e.recovery = 0.7
	e.attack_interval = 2.8
	e.projectile_speed = 9.0
	e.weak_to = Element.Type.LIGHT
	e.resists = Element.Type.DARK
	e.color = Color(0.35, 0.2, 0.5)
	e.size = Vector3(1.1, 1.1, 1.1)
	e.shape = EnemyData.Shape.SPHERE
	e.hover_height = 1.0
	return e


## ALCHEMIC: a tough, slow ooze that slams everything around it. Burns.
func _ooze() -> EnemyData:
	var e := _base("Caustic Ooze", EnemyData.EnemyType.ALCHEMIC,
		"Manufactured organic horror. Slow and tanky; a long telegraphed slam hits all around it and Burns.")
	e.max_hp = 240.0
	e.defense = 20.0
	e.resolve = 20.0
	e.move_speed = 2.0
	e.attack_damage = 24.0
	e.attack_element = Element.Type.FIRE
	e.status_power = 1.5
	e.attack_range = 2.6
	e.melee_arc_deg = 360.0
	e.windup = 1.0
	e.recovery = 0.9
	e.attack_interval = 2.6
	e.weak_to = Element.Type.ICE
	e.resists = Element.Type.FIRE
	e.color = Color(0.3, 0.75, 0.6)
	e.size = Vector3(1.8, 1.3, 1.8)
	e.shape = EnemyData.Shape.SPHERE
	return e


## LIGHT: Malbona Lumo's fey spawn. Evasive caster; Light bolts Blind.
func _sprite() -> EnemyData:
	var e := _base("Lumen Sprite", EnemyData.EnemyType.LIGHT,
		"Fey-alien spawn of Malbona Lumo, hostile to Lumin. Darts about, casts Light bolts that Blind (magic, reflectable).")
	e.max_hp = 80.0
	e.resolve = 25.0
	e.move_speed = 5.0
	e.attack_style = EnemyData.AttackStyle.SPELL
	e.attack_damage = 13.0
	e.attack_element = Element.Type.LIGHT
	e.status_power = 2.5
	e.attack_range = 11.0
	e.min_range = 7.0
	e.windup = 0.5
	e.recovery = 0.4
	e.attack_interval = 2.0
	e.projectile_speed = 13.0
	e.weak_to = Element.Type.DARK
	e.resists = Element.Type.LIGHT
	e.color = Color(1.0, 0.92, 0.55)
	e.size = Vector3(0.6, 0.6, 0.6)
	e.shape = EnemyData.Shape.SPHERE
	e.hover_height = 1.3
	return e
