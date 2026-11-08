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


func _attack(name: String, swing: AttackData.Swing, mult: float, duration: float,
		active: Vector2, window: Vector2) -> AttackData:
	var a := AttackData.new()
	a.display_name = name
	a.swing = swing
	a.damage_mult = mult
	a.duration = duration
	a.active_start = active.x
	a.active_end = active.y
	a.window_open = window.x
	a.window_close = window.y
	return a


func _sword() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Sword"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.base_damage = 20.0
	w.mesh_size = Vector3(0.08, 0.08, 1.0)
	w.mesh_color = Color(0.82, 0.85, 0.9)

	var n1 := _attack("Slash", AttackData.Swing.SLASH_RIGHT, 1.0, 0.42, Vector2(0.1, 0.22), Vector2(0.24, 0.58))
	var n2 := _attack("Return Slash", AttackData.Swing.SLASH_LEFT, 1.1, 0.42, Vector2(0.1, 0.22), Vector2(0.24, 0.58))
	var n3 := _attack("Cleave", AttackData.Swing.OVERHEAD, 1.3, 0.6, Vector2(0.16, 0.3), Vector2(0.36, 0.8))
	n3.lunge_distance = 0.8
	w.normal_attacks = [n1, n2, n3]

	var h1 := _attack("Heavy Slash", AttackData.Swing.SLASH_RIGHT, 1.8, 0.62, Vector2(0.22, 0.36), Vector2(0.4, 0.82))
	var h2 := _attack("Heavy Return", AttackData.Swing.SLASH_LEFT, 1.95, 0.62, Vector2(0.22, 0.36), Vector2(0.4, 0.82))
	var h3 := _attack("Piercing Thrust", AttackData.Swing.THRUST, 2.3, 0.8, Vector2(0.28, 0.42), Vector2(0.5, 1.0))
	for h in [h1, h2]:
		h.lunge_distance = 0.8
	h3.lunge_distance = 1.4
	h3.reach = 1.6
	h3.hitbox_size = Vector3(1.2, 1.4, 2.6)
	w.hard_attacks = [h1, h2, h3]
	return w


func _shot(name: String, mult: float, hard: bool) -> AttackData:
	var a: AttackData
	if hard:
		a = _attack(name, AttackData.Swing.SHOT, mult, 0.5, Vector2(0.14, 0.14), Vector2(0.3, 0.7))
		a.lp_cost = 3.0
		a.projectile_radius = 0.14
	else:
		a = _attack(name, AttackData.Swing.SHOT, mult, 0.3, Vector2(0.06, 0.06), Vector2(0.14, 0.45))
		a.lp_cost = 1.0
		a.projectile_radius = 0.08
	a.lunge_distance = 0.0
	a.is_projectile = true
	a.projectile_speed = 40.0
	a.projectile_range = 30.0
	return a


func _pistol() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Pistol"
	w.weapon_class = WeaponData.WeaponClass.RANGED
	w.base_damage = 12.0
	w.mesh_size = Vector3(0.08, 0.16, 0.38)
	w.mesh_color = Color(0.25, 0.27, 0.32)
	w.normal_attacks = [_shot("Shot", 1.0, false), _shot("Shot", 1.05, false), _shot("Shot", 1.15, false)]
	w.hard_attacks = [_shot("Charged Shot", 2.0, true), _shot("Charged Shot", 2.1, true), _shot("Charged Shot", 2.4, true)]
	return w


func _spell_attack(name: String, element: Element.Type, mult: float, lp: float,
		duration: float, fire_at: float, speed: float, radius: float, pierce: bool) -> AttackData:
	var a := _attack(name, AttackData.Swing.CAST, mult, duration, Vector2(fire_at, fire_at), Vector2(duration, duration))
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
	fire.normal = _spell_attack("Fire Bolt", Element.Type.FIRE, 1.0, 6.0, 0.4, 0.2, 26.0, 0.18, false)
	fire.hard = _spell_attack("Fire Bolt (Hard)", Element.Type.FIRE, 2.2, 14.0, 0.55, 0.25, 24.0, 0.32, false)

	var frost := SpellData.new()
	frost.display_name = "Frost Lance"
	frost.normal = _spell_attack("Frost Lance", Element.Type.ICE, 0.85, 8.0, 0.4, 0.2, 38.0, 0.12, true)
	frost.hard = _spell_attack("Frost Lance (Hard)", Element.Type.ICE, 1.9, 18.0, 0.55, 0.25, 38.0, 0.2, true)

	w.spells = [fire, frost]
	return w
