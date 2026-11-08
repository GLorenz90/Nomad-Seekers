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
	_save(_dervish_blades(), "dervish_blades")
	_save(_frost_sword(), "frost_sword")
	_save(_great_sword(), "great_sword")
	_save(_axe(), "axe")
	_save(_shield(), "shield")
	_save(_heavy_shield(), "heavy_shield")
	_save(_ward(), "ward")
	_save(_barrier(), "barrier")
	quit()


func _save(weapon: WeaponData, file: String) -> void:
	var path := "res://data/weapons/%s.tres" % file
	var err := ResourceSaver.save(weapon, path)
	print("%s -> %s" % [path, error_string(err)])


## PSO Blue Burst runs at 30 fps. Timings below are PSO frame counts from the
## Ephinea wiki (wiki.pioneer2.net/w/Game_mechanics/Frame_data), converted here.
const PSO_FPS := 30.0
## Movement speed while attacking with a mobile attack (fraction of run speed).
const MOBILE_SPEED := 0.5


func _f(frames: float) -> float:
	return frames / PSO_FPS


## hit = frame the attack comes out; combo = PSO's earliest frame the next
## step can start (the swing is over, recovery begins); full = the whole
## animation. The chain window is combo..full, exactly PSO's window: chaining
## cancels the remaining recovery. If the combo ends here, the Seeker is locked
## until full.
func _attack(name: String, swing: AttackData.Swing, mult: float, hit: float,
		combo: float, full: float) -> AttackData:
	var a := AttackData.new()
	a.display_name = name
	a.swing = swing
	a.damage_mult = mult
	a.active_start = _f(hit)
	a.active_end = _f(hit + 3.0)
	a.duration = _f(full)
	a.window_open = _f(combo)
	a.window_close = _f(full)
	return a


## Saber frame data (PSO male, comes-out / min / max frames):
##   N1 11/13/29  N2 10/10/24  N3 8/31/31
##   H1 20/21/37  H2 15/15/29  H3 14/34/34
func _sword() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Sword"
	w.weapon_type = &"sword"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.base_damage = 20.0
	w.mesh_size = Vector3(0.08, 0.08, 1.0)
	w.mesh_color = Color(0.82, 0.85, 0.9)

	var n1 := _attack("Slash", AttackData.Swing.SLASH_RIGHT, 1.0, 11, 13, 29)
	var n2 := _attack("Return Slash", AttackData.Swing.SLASH_LEFT, 1.1, 10, 10, 24)
	var n3 := _attack("Cleave", AttackData.Swing.OVERHEAD, 1.3, 8, 31, 31)
	n3.lunge_distance = 0.8
	w.normal_attacks = [n1, n2, n3]
	# PSO's saber "attacks 1 enemy": a narrow hitbox, so it rarely catches two.
	# (The Great Sword is the wide, multi-target sweep.)

	var h1 := _attack("Heavy Slash", AttackData.Swing.SLASH_RIGHT, 1.8, 20, 21, 37)
	var h2 := _attack("Heavy Return", AttackData.Swing.SLASH_LEFT, 1.95, 15, 15, 29)
	var h3 := _attack("Piercing Thrust", AttackData.Swing.THRUST, 2.3, 14, 34, 34)
	for h in [h1, h2]:
		h.lunge_distance = 0.8
	h3.lunge_distance = 1.4
	h3.reach = 1.6
	h3.hitbox_size = Vector3(1.2, 1.4, 2.6)
	w.hard_attacks = [h1, h2, h3]
	for a in [n1, n2, n3, h1, h2]:
		a.hitbox_size = Vector3(1.2, 1.6, 1.8)
	return w


## Handgun frame data (PSO, step combo / full):
##   Normal 14/27, 11/25, -/19    Heavy 22/34, 16/30, -/25
## PSO doesn't list when the bullet leaves, so it fires a couple of frames
## before the window opens, matching the saber's pattern.
func _shot(name: String, mult: float, hard: bool, fire: float, combo: float, full: float) -> AttackData:
	var a := _attack(name, AttackData.Swing.SHOT, mult, fire, combo, full)
	a.lp_cost = 3.0 if hard else 1.0
	# PSU-style: walk while firing Normal shots; Charged shots plant your feet.
	a.move_speed_scale = 0.0 if hard else MOBILE_SPEED
	a.projectile_radius = 0.14 if hard else 0.08
	a.lunge_distance = 0.0
	a.is_projectile = true
	a.projectile_speed = 28.0
	a.projectile_range = 30.0
	return a


func _pistol() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Pistol"
	w.weapon_type = &"pistol"
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
		cast: float, total: float, speed: float, radius: float, pierce: bool, hard: bool) -> AttackData:
	var a := _attack(name, AttackData.Swing.CAST, mult, cast, total, total)
	a.override_damage_type = true
	a.damage_type = element
	a.lp_cost = lp
	# Normal casts keep you moving; Hard casts stand in place.
	a.move_speed_scale = 0.0 if hard else MOBILE_SPEED
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
	w.weapon_type = &"wand"
	w.weapon_class = WeaponData.WeaponClass.MAGIC
	w.casting = true
	w.no_combo = true
	w.base_damage = 18.0
	w.mesh_size = Vector3(0.05, 0.05, 0.45)
	w.mesh_color = Color(0.95, 0.78, 0.3)

	var fire := SpellData.new()
	fire.display_name = "Fire Bolt"
	fire.normal = _spell_attack("Fire Bolt", Element.Type.FIRE, 1.0, 6.0, 15, 35, 16.0, 0.18, false, false)
	fire.hard = _spell_attack("Fire Bolt (Hard)", Element.Type.FIRE, 2.2, 14.0, 24, 45, 15.0, 0.32, false, true)

	var frost := SpellData.new()
	frost.display_name = "Frost Lance"
	frost.normal = _spell_attack("Frost Lance", Element.Type.ICE, 0.85, 8.0, 15, 35, 24.0, 0.12, true, false)
	frost.hard = _spell_attack("Frost Lance (Hard)", Element.Type.ICE, 1.9, 18.0, 24, 45, 24.0, 0.2, true, true)

	w.spells = [fire, frost]
	return w


## Dervish Blades: the machinegun of melee. Original timings (PSO has no
## equivalent): quick spinning slashes you can walk through, and holding the
## button spins continuously, hitting everything around you every 0.2 s.
func _dervish_blades() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Dervish Blades"
	w.weapon_type = &"dervish_blades"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.two_handed = true
	w.sustained = true
	w.base_damage = 11.0
	w.mesh_size = Vector3(0.06, 0.06, 0.6)
	w.mesh_color = Color(0.4, 0.9, 0.85)

	var steps: Array[AttackData] = []
	for spec in [["Whirl Cut", 1.0, 6, 10, 20], ["Whirl Cut", 1.0, 6, 10, 20], ["Cyclone", 1.4, 8, 24, 24]]:
		var a := _attack(spec[0], AttackData.Swing.SPIN, spec[1], spec[2], spec[3], spec[4])
		a.active_end = a.active_start + _f(6)
		a.move_speed_scale = MOBILE_SPEED
		a.lunge_distance = 0.0
		a.reach = 0.2
		a.hitbox_size = Vector3(3.2, 1.6, 3.2)
		steps.append(a)
	w.normal_attacks = steps

	var spin := AttackData.new()
	spin.display_name = "Whirlwind"
	spin.swing = AttackData.Swing.SPIN
	spin.damage_mult = 0.55
	spin.sustained_tick = 0.2  # 5 hits/s -> 3.75 hits/s (-25% damage rate)
	spin.duration = _f(9)  # wind-down after release
	spin.move_speed_scale = 0.6
	spin.face_movement = true
	spin.lunge_distance = 0.0
	spin.reach = 0.0
	spin.hitbox_size = Vector3(3.6, 1.6, 3.6)
	w.sustained_attack = spin
	return w


## Same type as the Sword (so the two powerstance), but deals Ice damage.
func _frost_sword() -> WeaponData:
	var w := _sword()
	w.display_name = "Frost Sword"
	w.damage_type = Element.Type.ICE
	w.mesh_color = Color(0.6, 0.85, 1.0)
	return w


## Great Sword = PSO "Sword" (two-handed). Comes-out frames aren't listed, so
## hits land two frames before the window opens, like the saber.
##   Normal combo/full 17/39, 15/31, -/43    Heavy 24/46, 19/35, -/43
func _great_sword() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Great Sword"
	w.weapon_type = &"great_sword"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.weight = WeaponData.Weight.HEAVY
	w.two_handed = true
	w.block_strength = 0.35
	w.base_damage = 34.0
	w.mesh_size = Vector3(0.14, 0.1, 1.6)
	w.mesh_color = Color(0.7, 0.72, 0.78)
	var specs := [
		["Sweep", AttackData.Swing.SLASH_RIGHT, 1.0, 15, 17, 39],
		["Return Sweep", AttackData.Swing.SLASH_LEFT, 1.1, 13, 15, 31],
		["Crushing Blow", AttackData.Swing.OVERHEAD, 1.4, 18, 43, 43],
		["Heavy Sweep", AttackData.Swing.SLASH_RIGHT, 1.8, 22, 24, 46],
		["Heavy Return", AttackData.Swing.SLASH_LEFT, 1.95, 17, 19, 35],
		["Earthsplitter", AttackData.Swing.OVERHEAD, 2.4, 20, 43, 43]]
	var attacks: Array[AttackData] = []
	for spec in specs:
		var a := _attack(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])
		a.reach = 1.4
		a.hitbox_size = Vector3(3.0, 1.6, 2.2)
		a.lunge_distance = 0.6
		attacks.append(a)
	w.normal_attacks = attacks.slice(0, 3)
	w.hard_attacks = attacks.slice(3, 6)
	return w


## Axe (heavy, one-handed). PSO has no axe; it borrows the partisan's frames.
##   Normal combo/full 17/39, 14/30, -/33    Heavy 24/46, 19/35, -/35
func _axe() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Axe"
	w.weapon_type = &"axe"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.weight = WeaponData.Weight.HEAVY
	w.base_damage = 28.0
	w.mesh_size = Vector3(0.1, 0.35, 0.8)
	w.mesh_color = Color(0.55, 0.45, 0.4)
	var specs := [
		["Chop", AttackData.Swing.OVERHEAD, 1.0, 15, 17, 39],
		["Hack", AttackData.Swing.SLASH_LEFT, 1.1, 12, 14, 30],
		["Cleaver", AttackData.Swing.OVERHEAD, 1.4, 14, 33, 33],
		["Heavy Chop", AttackData.Swing.OVERHEAD, 1.8, 22, 24, 46],
		["Heavy Hack", AttackData.Swing.SLASH_LEFT, 1.95, 17, 19, 35],
		["Executioner", AttackData.Swing.OVERHEAD, 2.4, 16, 35, 35]]
	var attacks: Array[AttackData] = []
	for spec in specs:
		attacks.append(_attack(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5]))
	w.normal_attacks = attacks.slice(0, 3)
	w.hard_attacks = attacks.slice(3, 6)
	return w


## Light shield: LT blocks 60% with a parry window when the block starts.
## The hand button deflects: a quick bash that opens a parry window.
func _shield() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Shield"
	w.weapon_type = &"shield"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.is_shield = true
	w.no_combo = true
	w.block_strength = 0.6
	w.base_damage = 8.0
	w.mesh_size = Vector3(0.6, 0.7, 0.08)
	w.mesh_color = Color(0.35, 0.55, 0.85)
	var deflect := _attack("Deflect", AttackData.Swing.THRUST, 0.5, 3, 12, 12)
	deflect.opens_parry = _f(8)
	deflect.lunge_distance = 0.0
	deflect.reach = 0.9
	deflect.hitbox_size = Vector3(1.6, 1.6, 1.2)
	w.normal_attacks = [deflect]
	w.hard_attacks = [deflect]
	return w


## Heavy shield: LT blocks 85%. The hand button shoves enemies back.
func _heavy_shield() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "Heavy Shield"
	w.weapon_type = &"heavy_shield"
	w.weapon_class = WeaponData.WeaponClass.MELEE
	w.weight = WeaponData.Weight.HEAVY
	w.is_shield = true
	w.no_combo = true
	w.block_strength = 0.85
	w.base_damage = 12.0
	w.mesh_size = Vector3(0.8, 1.0, 0.12)
	w.mesh_color = Color(0.45, 0.45, 0.55)
	var shove := _attack("Shove", AttackData.Swing.THRUST, 0.6, 8, 20, 20)
	shove.knockback = 9.0
	shove.lunge_distance = 0.4
	shove.reach = 1.0
	shove.hitbox_size = Vector3(2.0, 1.6, 1.4)
	w.normal_attacks = [shove]
	w.hard_attacks = [shove]
	return w


## Magic shields (North Star §5.1): a parry reflects enemy shots and spells
## back at the shooter. They can't parry melee, only block it. The hand button
## opens a reflect window.
func _magic_shield(name: String, type: StringName, heavy: bool, block: float,
		window_frames: float, color: Color, size: Vector3) -> WeaponData:
	var w := WeaponData.new()
	w.display_name = name
	w.weapon_type = type
	w.weapon_class = WeaponData.WeaponClass.MAGIC
	w.weight = WeaponData.Weight.HEAVY if heavy else WeaponData.Weight.LIGHT
	w.is_shield = true
	w.reflects = true
	w.no_combo = true
	w.block_strength = block
	w.base_damage = 6.0
	w.mesh_size = size
	w.mesh_color = color
	var reflect := _attack("Reflect", AttackData.Swing.THRUST, 0.3, 3, 12, 12)
	reflect.opens_parry = _f(window_frames)
	reflect.lunge_distance = 0.0
	reflect.reach = 0.9
	reflect.hitbox_size = Vector3(1.4, 1.6, 1.0)
	w.normal_attacks = [reflect]
	w.hard_attacks = [reflect]
	return w


func _ward() -> WeaponData:
	return _magic_shield("Ward", &"ward", false, 0.5, 9, Color(0.6, 0.45, 1.0), Vector3(0.55, 0.65, 0.06))


func _barrier() -> WeaponData:
	return _magic_shield("Barrier", &"barrier", true, 0.75, 12, Color(0.45, 0.3, 0.9), Vector3(0.75, 0.95, 0.1))
