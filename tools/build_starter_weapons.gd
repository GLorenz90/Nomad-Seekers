extends SceneTree
## Writes every base weapon (North Star §5.3) to res://data/weapons/*.tres and
## the rare weapons to res://data/weapons/rare/*.tres.
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
	for w in _full_list():
		_save(w, String(w.weapon_type))
	DirAccess.make_dir_recursive_absolute("res://data/weapons/rare")
	for w in _rares():
		var err := ResourceSaver.save(w, "res://data/weapons/rare/%s.tres" % w.display_name.to_snake_case())
		print("rare %s -> %s" % [w.display_name, error_string(err)])
	quit()


## Job locks (North Star §5.3 Jobs column): S = Striker, R = Ranger, I = Invoker.
const JOBS := {
	&"sword": "SRI", &"great_sword": "S", &"bladestaff": "S", &"dagger": "SRI", &"spear": "S",
	&"halberd": "S", &"mace": "SI", &"maul": "S", &"flail": "S", &"axe": "S", &"great_axe": "S",
	&"glove": "S", &"dervish_blades": "S", &"shield": "SRI", &"heavy_shield": "S",
	&"pistol": "SRI", &"machine_pistol": "R", &"hand_shotgun": "R", &"rifle": "R",
	&"assault_rifle": "R", &"shotgun": "R", &"bazooka": "R", &"grenade": "RS",
	&"grenade_launcher": "R", &"thrown_daggers": "RS", &"boomerang": "SR", &"gigarang": "S",
	&"bow": "R", &"crossbow": "R", &"arbalest": "R", &"wand": "SRI", &"cane": "I",
	&"staff": "I", &"cards": "IR", &"talisman": "I", &"totem": "I", &"ward": "IS", &"barrier": "I",
}


func _save(weapon: WeaponData, file: String) -> void:
	if JOBS.has(weapon.weapon_type):
		var codes := PackedStringArray()
		for c in String(JOBS[weapon.weapon_type]):
			codes.append(c)
		weapon.jobs = codes
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



# --- Full weapon list (Part 5) ------------------------------------------------
# PSO frame tables as [[S1 full, S1 combo], [S2 full, S2 combo], [S3 full]].
# Where PSO has no equivalent, the closest table is scaled (noted per weapon).

const SABER_N := [[29, 13], [24, 10], [31]]
const SABER_H := [[37, 21], [29, 15], [34]]
const PARTISAN_N := [[39, 17], [30, 14], [33]]
const PARTISAN_H := [[46, 24], [35, 19], [35]]
const SWORD_N := [[39, 17], [31, 15], [43]]
const SWORD_H := [[46, 24], [35, 19], [43]]
const HANDGUN_N := [[27, 14], [25, 11], [19]]
const HANDGUN_H := [[34, 22], [30, 16], [25]]
const RIFLE_N := [[29, 15], [25, 12], [20]]
const RIFLE_H := [[37, 23], [30, 17], [26]]
const MECHGUN_N := [[49, 12], [45, 10], [42]]
const SHOT_N := [[50, 25], [43, 21], [34]]
const SHOT_H := [[56, 31], [46, 24], [38]]
const CANE_N := [[29, 13], [27, 13], [39]]
const CANE_H := [[37, 21], [32, 18], [40]]


## Three steps from a PSO table. The hit lands 2 frames before the window
## opens (the saber's pattern); step 3 hits about a third of the way in.
func _steps(names: Array, swings: Array, mults: Array, table: Array, scale: float) -> Array[AttackData]:
	var out: Array[AttackData] = []
	for i in 3:
		var full: float = table[i][0] * scale
		var combo: float = (table[i][1] if table[i].size() > 1 else table[i][0]) * scale
		var hit := maxf(combo - 2.0, 3.0) if i < 2 else maxf(full * 0.35, 3.0)
		out.append(_attack(names[i], swings[i], mults[i], hit, combo, full))
	return out


func _weapon(name: String, type: StringName, cls: WeaponData.WeaponClass, heavy: bool,
		two_hand: bool, base: float, mesh: Vector3, color: Color) -> WeaponData:
	var w := WeaponData.new()
	w.display_name = name
	w.weapon_type = type
	w.weapon_class = cls
	w.weight = WeaponData.Weight.HEAVY if heavy else WeaponData.Weight.LIGHT
	w.two_handed = two_hand
	w.base_damage = base
	w.mesh_size = mesh
	w.mesh_color = color
	if two_hand:
		w.block_strength = 0.3
	return w


const SLASHES := [AttackData.Swing.SLASH_RIGHT, AttackData.Swing.SLASH_LEFT, AttackData.Swing.OVERHEAD]
const THRUSTS := [AttackData.Swing.THRUST, AttackData.Swing.THRUST, AttackData.Swing.THRUST]
const SHOTS := [AttackData.Swing.SHOT, AttackData.Swing.SHOT, AttackData.Swing.SHOT]
const N_MULT := [1.0, 1.1, 1.3]
const H_MULT := [1.8, 1.95, 2.3]


func _melee(w: WeaponData, n_table: Array, h_table: Array, scale: float, swings: Array,
		reach: float, hitbox: Vector3, lunge: float) -> WeaponData:
	var n := _steps(["Strike", "Strike", "Finisher"], swings, N_MULT, n_table, scale)
	var h := _steps(["Heavy Strike", "Heavy Strike", "Heavy Finisher"], swings, H_MULT, h_table, scale)
	for a in n + h:
		a.reach = reach
		a.hitbox_size = hitbox
		a.lunge_distance = lunge
	w.normal_attacks = n
	w.hard_attacks = h
	return w


## Ranged steps. mobile: Normal shots let you walk at half speed, Hard shots root.
func _gun(w: WeaponData, n_table: Array, h_table: Array, scale: float, speed: float,
		range_m: float, mobile: bool, lp_n: float, lp_h: float) -> WeaponData:
	var n := _steps(["Shot", "Shot", "Shot"], SHOTS, [1.0, 1.05, 1.15], n_table, scale)
	var h := _steps(["Charged Shot", "Charged Shot", "Charged Shot"], SHOTS, [2.0, 2.1, 2.4], h_table, scale)
	for a in n + h:
		a.is_projectile = true
		a.projectile_speed = speed
		a.projectile_range = range_m
		a.lunge_distance = 0.0
		a.active_end = a.active_start
	for a in n:
		a.lp_cost = lp_n
		a.move_speed_scale = MOBILE_SPEED if mobile else 0.0
	for a in h:
		a.lp_cost = lp_h
		a.projectile_radius = 0.16
	w.normal_attacks = n
	w.hard_attacks = h
	return w


## A single standalone attack (no combo): all three steps are the same.
func _single(w: WeaponData, name: String, hit: float, full: float, hard_mult: float) -> AttackData:
	w.no_combo = true
	var a := _attack(name, AttackData.Swing.SHOT, 1.0, hit, full, full)
	a.lunge_distance = 0.0
	var h := a.duplicate() as AttackData
	h.display_name = "Heavy " + name
	h.damage_mult = hard_mult
	w.normal_attacks = [a]
	w.hard_attacks = [h]
	return a


func _full_list() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	var steel := Color(0.78, 0.8, 0.86)
	var wood := Color(0.55, 0.4, 0.28)
	var gun := Color(0.25, 0.27, 0.32)

	# --- Melee ---
	# Bladestaff: PSO double saber isn't in the data; saber frames, a little quicker.
	var bladestaff := _melee(_weapon("Bladestaff", &"bladestaff", WeaponData.WeaponClass.MELEE, false, true, 17.0,
		Vector3(0.08, 0.08, 1.8), Color(0.6, 0.9, 1.0)), SABER_N, SABER_H, 0.9,
		[AttackData.Swing.SLASH_RIGHT, AttackData.Swing.SLASH_LEFT, AttackData.Swing.SPIN],
		1.0, Vector3(2.8, 1.6, 2.0), 0.4)
	list.append(bladestaff)
	# Dagger: fast single-target; saber frames x0.75 (PSO's dagger table isn't in the data).
	list.append(_melee(_weapon("Dagger", &"dagger", WeaponData.WeaponClass.MELEE, false, false, 12.0,
		Vector3(0.06, 0.06, 0.5), steel), SABER_N, SABER_H, 0.75, SLASHES,
		0.9, Vector3(1.0, 1.4, 1.5), 0.4))
	# Spear: long thrusts with reach; partisan frames x0.9. Works with a shield.
	list.append(_melee(_weapon("Spear", &"spear", WeaponData.WeaponClass.MELEE, false, false, 20.0,
		Vector3(0.06, 0.06, 2.0), wood), PARTISAN_N, PARTISAN_H, 0.9, THRUSTS,
		1.9, Vector3(0.9, 1.4, 2.8), 0.5))
	# Halberd: a light great sword, like PSO partisans and glaives.
	list.append(_melee(_weapon("Halberd", &"halberd", WeaponData.WeaponClass.MELEE, false, true, 26.0,
		Vector3(0.12, 0.3, 2.0), steel), PARTISAN_N, PARTISAN_H, 1.0, SLASHES,
		1.6, Vector3(3.0, 1.6, 2.4), 0.5))
	# Mace: a blunt caster's sidearm, PSO cane frames.
	list.append(_melee(_weapon("Mace", &"mace", WeaponData.WeaponClass.MELEE, false, false, 20.0,
		Vector3(0.14, 0.14, 0.8), Color(0.6, 0.55, 0.5)), CANE_N, CANE_H, 1.0, SLASHES,
		1.1, Vector3(1.3, 1.6, 1.8), 0.5))
	# Maul: slow and crushing; PSO sword frames x1.15; the finisher knocks back.
	var maul := _melee(_weapon("Maul", &"maul", WeaponData.WeaponClass.MELEE, true, true, 40.0,
		Vector3(0.3, 0.3, 1.5), Color(0.5, 0.5, 0.55)), SWORD_N, SWORD_H, 1.15,
		[AttackData.Swing.OVERHEAD, AttackData.Swing.SLASH_LEFT, AttackData.Swing.OVERHEAD],
		1.3, Vector3(2.4, 1.8, 2.2), 0.6)
	maul.normal_attacks[2].knockback = 6.0
	maul.hard_attacks[2].knockback = 8.0
	maul.block_strength = 0.4
	list.append(maul)
	# Flail: heavy one-handed sweep; PSO cane frames x1.1.
	list.append(_melee(_weapon("Flail", &"flail", WeaponData.WeaponClass.MELEE, true, false, 30.0,
		Vector3(0.25, 0.25, 1.2), Color(0.45, 0.45, 0.5)), CANE_N, CANE_H, 1.1, SLASHES,
		1.3, Vector3(2.6, 1.6, 2.0), 0.4))
	# Great Axe: PSO sword frames x1.1, very wide.
	var great_axe := _melee(_weapon("Great Axe", &"great_axe", WeaponData.WeaponClass.MELEE, true, true, 42.0,
		Vector3(0.12, 0.5, 1.6), Color(0.6, 0.5, 0.45)), SWORD_N, SWORD_H, 1.1, SLASHES,
		1.4, Vector3(3.2, 1.6, 2.2), 0.6)
	great_axe.block_strength = 0.35
	list.append(great_axe)
	# Glove: fists, PSU-style; saber frames x0.85, short reach.
	list.append(_melee(_weapon("Glove", &"glove", WeaponData.WeaponClass.MELEE, false, false, 14.0,
		Vector3(0.2, 0.2, 0.25), Color(0.7, 0.3, 0.25)), SABER_N, SABER_H, 0.85,
		[AttackData.Swing.THRUST, AttackData.Swing.THRUST, AttackData.Swing.OVERHEAD],
		0.9, Vector3(1.1, 1.4, 1.4), 0.5))

	# --- Ranged ---
	# Machine Pistol: an automatic pistol (Grayson, 2026-11-08). Hold fires at the
	# Assault Rifle's original rate (0.11 s); taps are single quick pistol shots
	# (PSO handgun frames x0.7). Half the damage it had (base 6 -> 3).
	var mp := _gun(_weapon("Machine Pistol", &"machine_pistol", WeaponData.WeaponClass.RANGED, false, false, 3.0,
		Vector3(0.08, 0.16, 0.42), gun), HANDGUN_N, HANDGUN_H, 0.7, 38.0, 25.0, true, 0.5, 1.5)
	mp.sustained = true
	mp.sustained_attack = _auto_fire("Automatic Fire", 0.11, 38.0, 25.0, 0.5, 0.4)
	list.append(mp)
	# Hand Shotgun: close-range spread; PSO shot frames x0.8.
	var hs := _gun(_weapon("Hand Shotgun", &"hand_shotgun", WeaponData.WeaponClass.RANGED, true, false, 7.0,
		Vector3(0.1, 0.18, 0.45), gun), SHOT_N, SHOT_H, 0.8, 34.0, 10.0, true, 1.5, 3.0)
	for a in hs.normal_attacks + hs.hard_attacks:
		a.projectile_count = 5
		a.spread_deg = 22.0
	list.append(hs)
	# Rifle: one-shot sniper rounds that pierce; PSO rifle frames with the long
	# "slow combo" window (15 extra frames after each shot).
	var rifle := _gun(_weapon("Rifle", &"rifle", WeaponData.WeaponClass.RANGED, true, true, 22.0,
		Vector3(0.08, 0.14, 1.3), gun), RIFLE_N, RIFLE_H, 1.0, 60.0, 45.0, false, 2.0, 4.0)
	for a in rifle.normal_attacks + rifle.hard_attacks:
		a.projectile_pierce = true
		a.window_close += _f(15)
	list.append(rifle)
	# Assault Rifle: heavy repeater; taps are rifle shots, hold = automatic fire at a
	# slow walk. Tuned by feel (Grayson, 2026-11-08): 33% slower (tick 0.11 -> 0.146,
	# taps x0.8 -> x1.065) and 25% more damage (base 9 -> 11.25).
	var ar := _gun(_weapon("Assault Rifle", &"assault_rifle", WeaponData.WeaponClass.RANGED, true, true, 11.25,
		Vector3(0.1, 0.18, 1.1), gun), RIFLE_N, RIFLE_H, 1.065, 50.0, 35.0, false, 1.0, 2.0)
	ar.sustained = true
	ar.sustained_attack = _auto_fire("Automatic Fire", 0.146, 50.0, 35.0, 0.3, 0.6)
	list.append(ar)
	# Shotgun: wide spread; PSO shot frames.
	var sg := _gun(_weapon("Shotgun", &"shotgun", WeaponData.WeaponClass.RANGED, true, true, 8.0,
		Vector3(0.12, 0.2, 1.1), gun), SHOT_N, SHOT_H, 1.0, 34.0, 12.0, false, 2.0, 4.0)
	for a in sg.normal_attacks + sg.hard_attacks:
		a.projectile_count = 7
		a.spread_deg = 30.0
	list.append(sg)
	# Bazooka: straight rocket, big blast radius.
	var bz := _weapon("Bazooka", &"bazooka", WeaponData.WeaponClass.RANGED, true, true, 45.0,
		Vector3(0.25, 0.25, 1.3), Color(0.35, 0.4, 0.3))
	_single(bz, "Rocket", 18, 60, 1.6)
	for a in bz.normal_attacks + bz.hard_attacks:
		a.is_projectile = true
		a.projectile_speed = 20.0
		a.projectile_radius = 0.25
		a.projectile_range = 40.0
		a.explosion_radius = 3.5
		a.lp_cost = 6.0
	list.append(bz)
	# Grenade: thrown in an arc (PSU-style); three in a row ends with a throw of two.
	var gr := _gun(_weapon("Grenade", &"grenade", WeaponData.WeaponClass.RANGED, false, false, 18.0,
		Vector3(0.2, 0.2, 0.2), Color(0.35, 0.45, 0.3)), HANDGUN_N, HANDGUN_H, 1.2, 14.0, 18.0, true, 2.0, 4.0)
	for a in gr.normal_attacks + gr.hard_attacks:
		a.projectile_gravity = 15.0
		a.explosion_radius = 2.5
		a.projectile_radius = 0.18
		a.move_speed_scale = 0.4 if a.move_speed_scale > 0.0 else 0.0
	gr.normal_attacks[2].finisher_volley = 2
	gr.normal_attacks[2].spread_deg = 30.0
	list.append(gr)
	# Grenade Launcher: lobbed, smaller blast, built for statuses (tags).
	var gl := _weapon("Grenade Launcher", &"grenade_launcher", WeaponData.WeaponClass.RANGED, true, true, 22.0,
		Vector3(0.2, 0.22, 1.0), Color(0.3, 0.35, 0.3))
	_single(gl, "Lob", 12, 40, 1.6)
	for a in gl.normal_attacks + gl.hard_attacks:
		a.is_projectile = true
		a.projectile_speed = 16.0
		a.projectile_radius = 0.2
		a.projectile_range = 26.0
		a.projectile_gravity = 12.0
		a.explosion_radius = 2.0
		a.status_power = 3.0
		a.lp_cost = 3.0
	list.append(gl)
	# Thrown Daggers: DEX throws; three in a row ends with a fan of extra knives.
	var td := _gun(_weapon("Thrown Daggers", &"thrown_daggers", WeaponData.WeaponClass.RANGED, false, false, 10.0,
		Vector3(0.05, 0.05, 0.35), steel), HANDGUN_N, HANDGUN_H, 1.0, 30.0, 22.0, true, 0.0, 0.0)
	td.normal_attacks[2].finisher_volley = 3
	td.normal_attacks[2].spread_deg = 25.0
	list.append(td)
	# Boomerang: PSO slicer; homes in on up to 5 enemies, one after another.
	var bm := _gun(_weapon("Boomerang", &"boomerang", WeaponData.WeaponClass.RANGED, false, false, 12.0,
		Vector3(0.5, 0.05, 0.15), Color(0.75, 0.6, 0.3)), HANDGUN_N, HANDGUN_H, 1.3, 16.0, 18.0, false, 1.0, 2.0)
	for a in bm.normal_attacks + bm.hard_attacks:
		a.lock_targets = 5
		a.projectile_radius = 0.25
	list.append(bm)
	# Gigarang: locks one enemy, hits everything in its path out and back.
	var gg := _weapon("Gigarang", &"gigarang", WeaponData.WeaponClass.RANGED, true, true, 30.0,
		Vector3(0.9, 0.08, 0.25), Color(0.7, 0.55, 0.3))
	_single(gg, "Gigarang Throw", 12, 36, 1.6)
	for a in gg.normal_attacks + gg.hard_attacks:
		a.is_projectile = true
		a.projectile_speed = 18.0
		a.projectile_radius = 0.4
		a.projectile_range = 14.0
		a.projectile_pierce = true
		a.returns = true
		a.lp_cost = 2.0
	list.append(gg)
	# Bow: rifle frames x0.9; Normal shots walk, Charged shots pierce.
	var bow := _gun(_weapon("Bow", &"bow", WeaponData.WeaponClass.RANGED, false, true, 16.0,
		Vector3(0.05, 1.2, 0.1), wood), RIFLE_N, RIFLE_H, 0.9, 45.0, 40.0, true, 1.0, 2.0)
	for a in bow.hard_attacks:
		a.projectile_pierce = true
	list.append(bow)
	# Crossbow: PSU style one-hander; handgun frames x1.1, fast bolts.
	list.append(_gun(_weapon("Crossbow", &"crossbow", WeaponData.WeaponClass.RANGED, false, false, 14.0,
		Vector3(0.4, 0.1, 0.5), wood), HANDGUN_N, HANDGUN_H, 1.1, 50.0, 35.0, true, 1.0, 3.0))
	# Arbalest: heavy siege bolt that pierces.
	var arb := _weapon("Arbalest", &"arbalest", WeaponData.WeaponClass.RANGED, true, true, 60.0,
		Vector3(0.6, 0.15, 1.2), wood)
	_single(arb, "Siege Bolt", 20, 45, 1.5)
	for a in arb.normal_attacks + arb.hard_attacks:
		a.is_projectile = true
		a.projectile_speed = 55.0
		a.projectile_range = 45.0
		a.projectile_radius = 0.15
		a.projectile_pierce = true
		a.lp_cost = 4.0
	list.append(arb)

	# --- Magic ---
	# Cane: damage-spell bonus, slower and stronger (x1.25 power, x1.2 cast time).
	list.append(_caster("Cane", &"cane", true, false, 1.25, 1.2,
		[_fire_bolt(), _frost_lance()], Vector3(0.06, 0.06, 0.9), Color(0.75, 0.6, 0.35)))
	# Staff: 4 spells (X, Y, RT+X, RT+Y); a balanced mix.
	list.append(_caster("Staff", &"staff", false, true, 1.1, 1.1,
		[_fire_bolt(), _frost_lance(), _spark(), _heal(0.25)], Vector3(0.07, 0.07, 1.7), Color(0.6, 0.45, 0.3)))
	# Talisman: support-spell bonus, quick.
	list.append(_caster("Talisman", &"talisman", false, false, 1.25, 1.0,
		[_heal(0.25), _cure()], Vector3(0.3, 0.4, 0.04), Color(0.95, 0.9, 0.7)))
	# Totem: support-spell bonus, slower with stronger effects.
	list.append(_caster("Totem", &"totem", true, false, 1.6, 1.3,
		[_heal(0.25), _cure()], Vector3(0.18, 0.5, 0.18), Color(0.55, 0.35, 0.25)))
	# Cards: thrown, SOL-scaling; three in a row ends with extra cards.
	var cards := _gun(_weapon("Cards", &"cards", WeaponData.WeaponClass.MAGIC, false, false, 14.0,
		Vector3(0.2, 0.3, 0.02), Color(0.9, 0.9, 0.95)), HANDGUN_N, HANDGUN_H, 1.0, 28.0, 22.0, true, 1.0, 2.0)
	for a in cards.normal_attacks + cards.hard_attacks:
		a.ranged_hit = true
	cards.normal_attacks[2].finisher_volley = 2
	cards.normal_attacks[2].spread_deg = 20.0
	list.append(cards)
	return list


func _auto_fire(name: String, tick: float, speed: float, range_m: float, mobile: float, lp: float) -> AttackData:
	var a := AttackData.new()
	a.display_name = name
	a.swing = AttackData.Swing.SHOT
	a.damage_mult = 0.7
	a.is_projectile = true
	a.projectile_speed = speed
	a.projectile_range = range_m
	a.projectile_radius = 0.08
	a.spread_deg = 4.0
	a.sustained_tick = tick
	a.move_speed_scale = mobile
	a.lp_cost = lp
	a.duration = _f(8)
	a.lunge_distance = 0.0
	return a


func _caster(name: String, type: StringName, heavy: bool, two_hand: bool, power: float,
		cast_scale: float, spells: Array, mesh: Vector3, color: Color) -> WeaponData:
	var w := _weapon(name, type, WeaponData.WeaponClass.MAGIC, heavy, two_hand, 18.0, mesh, color)
	w.casting = true
	w.no_combo = true
	var list: Array[SpellData] = []
	for spell in spells:
		var sp := (spell as SpellData)
		for a: AttackData in [sp.normal, sp.hard]:
			var support: bool = a.support != AttackData.Support.NONE
			# Damage items boost damage spells; support items boost support spells.
			var boosts: bool = (type == &"talisman" or type == &"totem") == support or type == &"staff"
			if boosts:
				a.damage_mult *= power
				a.support_amount *= power
			for field in ["duration", "active_start", "active_end", "window_open", "window_close"]:
				a.set(field, float(a.get(field)) * cast_scale)
		list.append(sp)
	w.spells = list
	return w


func _fire_bolt() -> SpellData:
	var s := SpellData.new()
	s.display_name = "Fire Bolt"
	s.normal = _spell_attack("Fire Bolt", Element.Type.FIRE, 1.0, 6.0, 15, 35, 16.0, 0.18, false, false)
	s.hard = _spell_attack("Fire Bolt (Hard)", Element.Type.FIRE, 2.2, 14.0, 24, 45, 15.0, 0.32, false, true)
	return s


func _frost_lance() -> SpellData:
	var s := SpellData.new()
	s.display_name = "Frost Lance"
	s.normal = _spell_attack("Frost Lance", Element.Type.ICE, 0.85, 8.0, 15, 35, 24.0, 0.12, true, false)
	s.hard = _spell_attack("Frost Lance (Hard)", Element.Type.ICE, 1.9, 18.0, 24, 45, 24.0, 0.2, true, true)
	return s


## Lightning burst: a fast bolt that bursts at the target (small area).
func _spark() -> SpellData:
	var s := SpellData.new()
	s.display_name = "Spark"
	s.normal = _spell_attack("Spark", Element.Type.LIGHTNING, 0.8, 8.0, 15, 35, 30.0, 0.14, false, false)
	s.hard = _spell_attack("Spark (Hard)", Element.Type.LIGHTNING, 1.7, 18.0, 24, 45, 30.0, 0.2, false, true)
	s.normal.explosion_radius = 2.0
	s.hard.explosion_radius = 3.0
	return s


## Typeless support (North Star §6): Heal restores HP, Cure clears statuses.
func _heal(amount: float) -> SpellData:
	var s := SpellData.new()
	s.display_name = "Heal"
	s.normal = _support_attack("Heal", AttackData.Support.HEAL, amount, 10.0, false)
	s.hard = _support_attack("Heal (Hard)", AttackData.Support.HEAL, amount * 1.8, 22.0, true)
	return s


func _cure() -> SpellData:
	var s := SpellData.new()
	s.display_name = "Cure"
	s.normal = _support_attack("Cure", AttackData.Support.CURE, 0.0, 8.0, false)
	s.hard = _support_attack("Cure (Hard)", AttackData.Support.CURE, 0.1, 14.0, true)
	return s


func _support_attack(name: String, kind: AttackData.Support, amount: float, lp: float, hard: bool) -> AttackData:
	var a := _attack(name, AttackData.Swing.CAST, 0.0, 15 if not hard else 24, 35 if not hard else 45,
		35 if not hard else 45)
	a.support = kind
	a.support_amount = amount
	a.lp_cost = lp
	a.lunge_distance = 0.0
	a.move_speed_scale = 0.0 if hard else MOBILE_SPEED
	return a


# --- Rares ------------------------------------------------------------------
# Unique names (originals), a fixed tag and bonus, +30% base damage, and the
# emblems whose drop pools carry them.

func _rares() -> Array[WeaponData]:
	var specs := [
		["Emberfang", "sword", "Heat", 3, EnemyData.EnemyType.BEAST, 0.2, [0, 1]],
		["Glacier Maw", "great_sword", "Ice", 3, EnemyData.EnemyType.ALCHEMIC, 0.2, [5, 10]],
		["Stormcaller", "rifle", "Shock", 3, EnemyData.EnemyType.SYNTHETIC, 0.25, [6, 2]],
		["Gravesong", "dagger", "Dim", 3, EnemyData.EnemyType.LIGHT, 0.2, [11, 7]],
		["Lifeleech Coil", "flail", "Draw", 3, EnemyData.EnemyType.MUTATED, 0.2, [3, 8]],
		["Lumen Edge", "bladestaff", "Panic", 3, EnemyData.EnemyType.DARK, 0.25, [9, 4]],
		["Kingmaker", "halberd", "Master's", 2, EnemyData.EnemyType.BEAST, 0.15, [2, 7, 11]],
	]
	var lines := {}
	for line in SpecialTag.all_lines():
		lines[line.line_name] = line
	var out: Array[WeaponData] = []
	for spec in specs:
		var base := load("res://data/weapons/%s.tres" % spec[1]) as WeaponData
		var w := base.duplicate(true) as WeaponData
		w.base_name = base.display_name
		w.display_name = spec[0]
		w.rare = true
		w.base_damage = base.base_damage * 1.3
		Loot.apply_tag(w, lines[spec[2]], spec[3])
		w.type_bonus = {spec[4]: spec[5]}
		w.set_meta("emblems", spec[6])
		out.append(w)
	return out
