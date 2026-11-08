extends SceneTree
## Writes the starter weapons to res://data/weapons/*.tres.
##
## The .tres files are the source of truth: edit them in the Inspector. Rerun
## this only to reset them to these defaults:
##   godot --headless --path . --script res://tools/build_starter_weapons.gd


func _initialize() -> void:
	_save(_sword(), "sword")
	_save(_pistol(), "pistol")
	_save(_wand(), "wand")
	quit()


func _save(weapon: WeaponData, file: String) -> void:
	var path := "res://data/weapons/%s.tres" % file
	var err := ResourceSaver.save(weapon, path)
	print("%s -> %s" % [path, error_string(err)])


## PSO Blue Burst runs at 30 fps. Timings below are PSO frame counts from the
## Ephinea wiki (wiki.pioneer2.net/w/Game_mechanics/Frame_data), converted here.
const PSO_FPS := 30.0


func _f(frames: float) -> float:
	return frames / PSO_FPS


## hit = frame the attack comes out; combo = earliest frame the next step can
## start (window opens); full = whole animation if the combo ends here (window
## closes and the Seeker is free).
func _attack(name: String, swing: AttackData.Swing, mult: float, hit: float,
		combo: float, full: float) -> AttackData:
	var a := AttackData.new()
	a.display_name = name
	a.swing = swing
	a.damage_mult = mult
	a.active_start = _f(hit)
	a.active_end = _f(hit + 3.0)
	a.window_open = _f(combo)
	a.window_close = _f(full)
	a.duration = _f(full)
	return a


## Saber frame data (PSO male, comes-out / min / max frames):
##   N1 11/13/29  N2 10/10/24  N3 8/31/31
##   H1 20/21/37  H2 15/15/29  H3 14/34/34
func _sword() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Sword"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.base_damage = 20.0
	w.mesh_size = Vector3(0.08, 0.08, 1.0)
	w.mesh_color = Color(0.82, 0.85, 0.9)

	var n1 := _attack("Slash", AttackData.Swing.SLASH_RIGHT, 1.0, 11, 13, 29)
	var n2 := _attack("Return Slash", AttackData.Swing.SLASH_LEFT, 1.1, 10, 10, 24)
	var n3 := _attack("Cleave", AttackData.Swing.OVERHEAD, 1.3, 8, 31, 31)
	n3.lunge_distance = 0.8
	w.normal_attacks = [n1, n2, n3]

	var h1 := _attack("Heavy Slash", AttackData.Swing.SLASH_RIGHT, 1.8, 20, 21, 37)
	var h2 := _attack("Heavy Return", AttackData.Swing.SLASH_LEFT, 1.95, 15, 15, 29)
	var h3 := _attack("Piercing Thrust", AttackData.Swing.THRUST, 2.3, 14, 34, 34)
	for h in [h1, h2]:
		h.lunge_distance = 0.8
	h3.lunge_distance = 1.4
	h3.reach = 1.6
	h3.hitbox_size = Vector3(1.2, 1.4, 2.6)
	w.hard_attacks = [h1, h2, h3]
	return w


## Handgun frame data (PSO, step combo / full):
##   Normal 14/27, 11/25, -/19    Heavy 22/34, 16/30, -/25
## PSO doesn't list when the bullet leaves, so it fires a couple of frames
## before the window opens, matching the saber's pattern.
func _shot(name: String, mult: float, hard: bool, fire: float, combo: float, full: float) -> AttackData:
	var a := _attack(name, AttackData.Swing.SHOT, mult, fire, combo, full)
	a.lp_cost = 3.0 if hard else 1.0
	a.projectile_radius = 0.14 if hard else 0.08
	a.lunge_distance = 0.0
	a.is_projectile = true
	a.projectile_speed = 28.0
	a.projectile_range = 30.0
	return a


func _pistol() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Pistol"
	w.weapon_class = WeaponData.WeaponClass.RANGED
	w.base_damage = 12.0
	w.mesh_size = Vector3(0.08, 0.16, 0.38)
	w.mesh_color = Color(0.25, 0.27, 0.32)
	w.normal_attacks = [
		_shot("Shot", 1.0, false, 12, 14, 27),
		_shot("Shot", 1.05, false, 9, 11, 25),
		_shot("Shot", 1.15, false, 9, 19, 19)]
	w.hard_attacks = [
		_shot("Charged Shot", 2.0, true, 20, 22, 34),
		_shot("Charged Shot", 2.1, true, 14, 16, 30),
		_shot("Charged Shot", 2.4, true, 12, 25, 25)]
	return w


## Technique casting (PSO): startup 6 frames, then charge and cast; the effect
## happens at "time to cast" and the caster is locked for "total". Foie, Zonde
## and Barta with an armed caster: 15 frames to cast, 35 frames total (30 at
## Lv16+). PSO has no charged techs, so the Hard cast is a deliberately slower,
## stronger version (PSO2 charges Foie for about 1 second).
func _spell_attack(name: String, element: Element.Type, mult: float, lp: float,
		cast: float, total: float, speed: float, radius: float, pierce: bool) -> AttackData:
	var a := _attack(name, AttackData.Swing.CAST, mult, cast, total, total)
	a.override_damage_type = true
	a.damage_type = element
	a.lp_cost = lp
	a.lunge_distance = 0.0
	a.is_projectile = true
	a.projectile_speed = speed
	a.projectile_radius = radius
	a.projectile_range = 28.0
	a.projectile_pierce = pierce
	return a


func _wand() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Wand"
	w.weapon_class = WeaponData.WeaponClass.MAGIC
	w.casting = true
	w.no_combo = true
	w.base_damage = 18.0
	w.mesh_size = Vector3(0.05, 0.05, 0.45)
	w.mesh_color = Color(0.95, 0.78, 0.3)

	var fire := SpellData.new()
	fire.display_name = "Fire Bolt"
	fire.normal = _spell_attack("Fire Bolt", Element.Type.FIRE, 1.0, 6.0, 15, 35, 16.0, 0.18, false)
	fire.hard = _spell_attack("Fire Bolt (Hard)", Element.Type.FIRE, 2.2, 14.0, 24, 45, 15.0, 0.32, false)

	var frost := SpellData.new()
	frost.display_name = "Frost Lance"
	frost.normal = _spell_attack("Frost Lance", Element.Type.ICE, 0.85, 8.0, 15, 35, 24.0, 0.12, true)
	frost.hard = _spell_attack("Frost Lance (Hard)", Element.Type.ICE, 1.9, 18.0, 24, 45, 24.0, 0.2, true)

	w.spells = [fire, frost]
	return w
