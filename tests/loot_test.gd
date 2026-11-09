extends SceneTree
## Automated test for Part 5: the full weapon list, jobs, special tags and
## their RT specials, monster-type bonuses, drops and emblem pools, projectile
## patterns (spreads, lobs, explosions, homing, out-and-back, finisher volleys,
## automatic fire), the Staff's four spells, Heal and Cure, Lumidium nodes,
## teleporter deposits and the save file. Runs in scenes/arena.tscn.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/loot_test.gd

const WEAPON_DIR := "res://data/weapons/"
const TEST_SAVE := "user://loot_test_save.tres"
## Room A's centre: empty while the rooms are switched off.
const ARENA := Vector3(0.0, 0.1, 4.0)

var _main: Node
var _player: Player
var _combat: CombatController
var _failures := 0
var _started: Array[String] = []
var _hits: Array = []  # [target, amount]
var _feedback: Array[String] = []


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_combat = _player.combat
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_player.autosave = false
	_combat.stats.luck = 0.0
	_combat.stats.defense = 0.0
	_combat.stats.resolve = 0.0
	_combat.stats.evasion = 0.0
	for room in ["Rooms/RoomA", "Rooms/RoomB"]:
		(_main.get_node(room) as WaveRoom).state = WaveRoom.RoomState.CLEARED
	_combat.attack_started.connect(func(_h, _w, attack, _c, _hd): _started.append(attack.display_name))
	_combat.hit_landed.connect(func(t, _i, amount): _hits.append([t, amount]))
	_combat.combo_feedback.connect(func(text): _feedback.append(text))
	await _frames(30)

	# --- Weapon data -------------------------------------------------------
	var all := Loot.base_weapons()
	_check("the full weapon list is built (%d weapons)" % all.size(), all.size() >= 38)
	var missing := []
	for families in Loot.FAVORED:
		for type in families:
			if not ResourceLoader.exists(WEAPON_DIR + String(type) + ".tres"):
				missing.append(type)
	_check("every emblem's favored families exist (%s missing)" % [missing], missing.is_empty())
	var rifle := _w("rifle")
	_check("Rifle is Ranger-only (%s)" % rifle.jobs_text(), not rifle.can_be_used_by("S") and rifle.can_be_used_by("R"))
	_check("Pistol, Sword, Dagger and Wand are for every job",
		_w("pistol").jobs.size() == 3 and _w("sword").jobs.size() == 3 and _w("dagger").jobs.size() == 3 and _w("wand").jobs.size() == 3)
	_check("Bow, Crossbow and Bladestaff are open to Invokers (%s / %s / %s)" % [_w("bow").jobs_text(), _w("crossbow").jobs_text(), _w("bladestaff").jobs_text()],
		_w("bow").can_be_used_by("I") and _w("crossbow").can_be_used_by("I") and _w("bladestaff").can_be_used_by("I")
		and not _w("burstbow").can_be_used_by("I"))
	_check("Staff is a 2h Invoker casting item with 4 spell slots",
		_w("staff").two_handed and _w("staff").casting and Loadout.make(null, _w("staff")).spell_slot_count(1) == 4
		and _w("staff").jobs_text() == "I")
	var rare_emblems := {}
	for r in Loot.rare_weapons():
		for e in r.get_meta("emblems", []):
			rare_emblems[e] = true
	_check("7 rares, and every emblem pool has one (%d emblems)" % rare_emblems.size(),
		Loot.rare_weapons().size() == 7 and rare_emblems.size() == CharacterData.EMBLEMS.size())
	var who := CharacterData.new()
	var emblems := []
	for job in 3:
		who.job = job as CharacterData.Job
		emblems.append(who.emblem_name())
	_check("12 emblems, and the job changes the emblem (Striker / Ranger / Invoker: %s)" % [emblems],
		CharacterData.EMBLEMS.size() == 12 and Loot.FAVORED.size() == 12
		and emblems[0] != emblems[1] and emblems[1] != emblems[2] and emblems[0] != emblems[2])
	_check("the job can't be changed in the Character tab", (_main.loadout_menu as LoadoutMenu)._job.disabled)
	var ember := _rare("Emberfang")
	_check("Emberfang: rare, Burning (Heat tier 4), Fire, +30%% base",
		ember != null and ember.rare and ember.tag.line_name == "Heat" and ember.tag_tier == 3
		and ember.damage_type == Element.Type.FIRE and is_equal_approx(ember.base_damage, _w("sword").base_damage * 1.3))

	# --- Jobs --------------------------------------------------------------
	_combat.loadout_set.loadouts[7] = Loadout.make(null, rifle)
	_check("a Striker can't use a Rifle loadout", not _combat.is_usable(7))
	_combat.set_job("R")
	_check("a Ranger can", _combat.is_usable(7))
	_combat.set_job("S")
	_combat.loadout_set.loadouts[7] = Loadout.new()

	# --- Loot rolls --------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var grub := load("res://data/enemies/grub_hound.tres") as EnemyData
	var drops := 0
	var weapons := 0
	var favored := 0
	var tagged := 0
	var bonus := 0
	for i in 3000:
		var drop := Loot.roll_drop(grub, 0, rng)
		if drop.is_empty():
			continue
		drops += 1
		if drop.has("weapon"):
			weapons += 1
			var w := drop.weapon as WeaponData
			if w.weapon_type in Loot.FAVORED[0]:
				favored += 1
			if w.tag:
				tagged += 1
			if not w.type_bonus.is_empty():
				bonus += 1
	_check("about 60%% of kills drop something (%d / 3000)" % drops, drops > 1650 and drops < 1950)
	# Two favored families of ~38 at 3x weight = about 14% of weapon drops.
	_check("the Crimson emblem favors Sword / Great Sword (%d of %d weapons)" % [favored, weapons],
		float(favored) / weapons > 0.09 and float(favored) / weapons < 0.22)
	_check("some drops carry a tag (%d) and a monster-type bonus (%d)" % [tagged, bonus], tagged > 50 and bonus > 100)
	var tiers := [0, 0, 0, 0]
	for i in 3000:
		tiers[Loot.roll_tier(4, rng)] += 1
	_check("low tag tiers are more common (%s)" % [tiers], tiers[0] > tiers[1] and tiers[1] > tiers[2] and tiers[2] > tiers[3])

	# --- Tags and specials -------------------------------------------------
	var heat := _line("Heat")
	var flame_sword := Loot.make_item(_w("sword"), rng)
	Loot.apply_tag(flame_sword, heat, 2)
	var special := flame_sword.get_attack(1, false, 0, true)
	_check("a Heat-line sword is named \"Flame Sword\" and deals Fire (%s)" % flame_sword.display_name,
		flame_sword.display_name == "Flame Sword" and flame_sword.damage_type == Element.Type.FIRE)
	_check("its RT special is stronger, costs LP and builds status faster",
		special != null and special.damage_mult > flame_sword.normal_attacks[0].damage_mult
		and special.lp_cost > 0.0 and special.status_power > 1.0)

	# Monster-type bonus: +30% vs Beast.
	var hound := _spawn("grub_hound", ARENA + Vector3(0, 0, -6))
	hound.data.evasion = 0.0
	hound.data.defense = 0.0
	var plain := _w("sword")
	var slayer := plain.duplicate() as WeaponData
	slayer.type_bonus = {EnemyData.EnemyType.BEAST: 0.3}
	var a := hound.receive_hit(_info(10.0, plain), _player)
	var b := hound.receive_hit(_info(10.0, slayer), _player)
	_check("+30%% vs Beast bonus applies (%.1f -> %.1f)" % [a, b], is_equal_approx(b, a * 1.3))
	hound.queue_free()

	# Tag effects through report_hit.
	var drain := _tagged("sword", "Draw", 3)
	_player.health.hp = 100.0
	var dummy := _spawn("grub_hound", ARENA + Vector3(0, 0, -6))
	_combat.report_hit(dummy, _info(100.0, drain, true), 100.0)
	_check("Gush heals 25%% of damage dealt (hp %.0f)" % _player.health.hp, is_equal_approx(_player.health.hp, 125.0))
	_combat.lp = 10.0
	_combat.report_hit(dummy, _info(100.0, _tagged("sword", "Mind", 0), true), 100.0)
	_check("Mind restores LP (10 -> %.0f)" % _combat.lp, is_equal_approx(_combat.lp, 20.0))
	var exp_before := _player.save.character.experience
	_combat.report_hit(dummy, _info(10.0, _tagged("sword", "Master's", 2), true), 10.0)
	_check("King's steals EXP (+%d)" % (_player.save.character.experience - exp_before), _player.save.character.experience > exp_before)
	_combat.report_hit(dummy, _info(10.0, drain, false), 10.0)
	_check("a normal (non-RT) hit has no tag effect", is_equal_approx(_player.health.hp, 125.0))
	var dim := _tagged("sword", "Dim", 3)
	dummy.data.boss = true
	for i in 200:
		_combat.report_hit(dummy, _info(1.0, dim, true), 1.0)
	_check("Hell never instant-kills a boss", not dummy.health.is_dead())
	dummy.data.boss = false
	var kills_after := -1
	for i in 200:
		_combat.report_hit(dummy, _info(1.0, dim, true), 1.0)
		if dummy.health.is_dead():
			kills_after = i + 1
			break
	_check("Hell instant-kills a normal enemy (after %d hits at 20%%)" % kills_after, kills_after > 0)
	await _frames(30)

	# Charge-line special pays Oro.
	var charged := _tagged("sword", "Charge", 0)
	_equip(null, charged)
	_player.save.inventory.oro = 150
	await _place(ARENA)
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	await _idle()
	_check("Charge special costs 100 Oro (150 -> %d)" % _player.save.inventory.oro, _player.save.inventory.oro == 50)
	_feedback.clear()
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	await _idle()
	_check("without the Oro it refuses (%s)" % [_feedback], "Not enough Oro" in _feedback)

	# --- Projectile patterns ------------------------------------------------
	_combat.set_job("R")
	_equip(null, _w("shotgun"))
	await _place(ARENA)
	_count_new()
	await _tap("hand_x")
	await _until_fired()
	var pellets := _count_new()
	_check("Shotgun fires 7 pellets (%d)" % pellets, pellets == 7)
	await _idle()

	# Grenade: lobbed, explodes on two clustered enemies.
	_equip(null, _w("grenade"))
	var e1 := _spawn("grub_hound", ARENA + Vector3(0, 0, -7))
	var e2 := _spawn("grub_hound", ARENA + Vector3(1.2, 0, -7.5))
	await _place(ARENA)
	_player.camera_rig.lock_target = e1
	var predicted := _combat.predict_targets(CombatController.Hand.RIGHT)
	_check("Grenade prediction includes the blast (%d targets)" % predicted.size(), e1 in predicted and e2 in predicted)
	_hits.clear()
	await _tap("hand_x")
	var lobbed := false
	for i in 40:
		await physics_frame
		for p in _projectiles():
			if p.gravity > 0.0 and p.velocity.y > 0.5:
				lobbed = true
	await _frames(60)
	_check("Grenade is thrown in an arc", lobbed)
	_check("its explosion hits both enemies", _hit(e1) and _hit(e2))
	_player.camera_rig.lock_target = null
	await _idle()
	e1.queue_free()
	e2.queue_free()

	# Boomerang: homes in on up to 5 enemies one after another.
	_combat.set_job("S")
	_equip(null, _w("boomerang"))
	var ring: Array[Enemy] = []
	for x in [-4.0, 0.0, 4.0]:
		ring.append(_spawn("grub_hound", ARENA + Vector3(x, 0, -8)))
	await _place(ARENA)
	_player.camera_rig.lock_target = ring[1]
	predicted = _combat.predict_targets(CombatController.Hand.RIGHT)
	_check("Boomerang predicts its lock chain (%d)" % predicted.size(), predicted.size() == 3)
	_hits.clear()
	await _tap("hand_x")
	await _frames(150)
	_check("Boomerang hits all three in turn", _hit(ring[0]) and _hit(ring[1]) and _hit(ring[2]))
	_player.camera_rig.lock_target = null
	await _idle()
	for e in ring:
		e.queue_free()

	# Gigarang: out and back through the same enemy.
	_equip(null, _w("gigarang"))
	var target := _spawn("grub_hound", ARENA + Vector3(0, 0, -4))
	target.health.max_hp = 5000.0
	target.health.hp = 5000.0
	await _place(ARENA)
	_hits.clear()
	await _tap("hand_x")
	await _frames(120)
	var gig_hits := 0
	for h in _hits:
		if h[0] == target:
			gig_hits += 1
	_check("Gigarang hits on the way out and back (%d hits)" % gig_hits, gig_hits == 2)
	await _idle()
	target.queue_free()

	# PSO-shotgun targeting: one projectile per enemy, each enemy hit once.
	var crowd: Array[Enemy] = []
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0]:
		var e := _spawn("grub_hound", ARENA + Vector3(x, 0, -9))
		e.health.max_hp = 9000.0
		e.health.hp = 9000.0
		crowd.append(e)
	await _frames(5)
	var expected := {"thrown_daggers": [1, 3, 5], "cards": [1, 2, 4], "burstbow": [3, 3, 5]}
	for type in expected:
		_combat.set_job("R" if type != "cards" else "I")
		_equip(null, _w(type))
		await _place(ARENA)
		var counts: Array[int] = []
		var once := true
		for i in 3:
			_count_new()
			await _tap("hand_x")
			await _until_fired()
			var targets := {}
			for p in _projectiles():
				if not p.has_meta("counted"):
					if p.exclusive and p.chain.size() == 1:
						targets[p.chain[0]] = true
			var n := _count_new()
			counts.append(n)
			once = once and targets.size() == n  # one projectile per enemy, all different
			if i < 2:
				await _until_window()
		_check("%s targets %s enemies, one projectile each (%s), never the same enemy twice" % [type, expected[type], counts],
			counts == expected[type] and once)
		await _idle()
	for e in crowd:
		e.queue_free()
	await _frames(5)

	# A targeted knife flies past enemies that aren't its target.
	_combat.set_job("R")
	_equip(null, _w("thrown_daggers"))
	var front := _spawn("grub_hound", ARENA + Vector3(0, 0, -3))
	var back := _spawn("grub_hound", ARENA + Vector3(0, 0, -8))
	await _place(ARENA)
	_player.camera_rig.lock_target = back
	await _frames(3)
	_hits.clear()
	await _tap("hand_x")
	await _frames(70)
	_player.camera_rig.lock_target = null
	_check("a targeted knife passes the enemy in front and hits the locked one", _hit(back) and not _hit(front))
	await _idle()
	front.queue_free()
	back.queue_free()

	# Point-blank: Arbalest and Gigarang fire straight ahead and still hit.
	for type in ["arbalest", "gigarang"]:
		_combat.set_job("R" if type == "arbalest" else "S")
		_equip(null, _w(type))
		var close := _spawn("grub_hound", ARENA + Vector3(0.3, 0, -1.6))
		await _place(ARENA)
		_player.camera_rig.lock_target = close
		await _frames(3)
		_hits.clear()
		_count_new()
		await _tap("hand_x")
		await _until_fired()
		var worst := 0.0
		for p in _projectiles():
			if not p.has_meta("counted"):
				var flat := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
				worst = maxf(worst, rad_to_deg(flat.angle_to(-_player.global_basis.z)))
		_count_new()
		await _frames(60)
		_player.camera_rig.lock_target = null
		_check("%s at point blank flies straight (%.1f deg off facing) and hits" % [type, worst],
			worst <= CombatController.MAX_AIM_YAW + 0.5 and _hit(close))
		await _idle()
		close.queue_free()

	# Only Boomerang, Gigarang and Arbalest pass through enemies (and specific rares).
	var piercers := []
	for type in ["pistol", "rifle", "bow", "crossbow", "shotgun", "machine_pistol", "assault_rifle", "arbalest", "gigarang"]:
		var w := _w(type)
		if w.normal_attacks[0].projectile_pierce or w.hard_attacks[0].projectile_pierce:
			piercers.append(type)
	_check("only Arbalest and Gigarang pierce (Boomerang homes through) (%s)" % [piercers],
		piercers == ["arbalest", "gigarang"] and _w("boomerang").normal_attacks[0].lock_targets > 0)
	_check("the rare Stormcaller rifle pierces", _rare("Stormcaller").normal_attacks[0].projectile_pierce)

	# Gunblade: melee unlocked, a gun when locked on.
	_combat.set_job("S")
	var gb := _w("gunblade")
	_check("Gunblade is Heavy and two-handed (%s)" % gb.jobs_text(), gb.is_heavy() and gb.two_handed)
	_equip(null, gb)
	var gb_target := _spawn("grub_hound", ARENA + Vector3(0, 0, -6))
	await _place(ARENA)
	_started.clear()
	_count_new()
	await _tap("hand_x")
	await _until_fired()
	var unlocked_shots := _count_new()
	await _idle()
	_player.camera_rig.lock_target = gb_target
	await _frames(3)
	await _tap("hand_x")
	await _until_fired()
	var locked_shots := _count_new()
	await _idle()
	_player.camera_rig.lock_target = null
	_check("Gunblade swings unlocked and shoots when locked on (%d shots, then %d)" % [unlocked_shots, locked_shots],
		unlocked_shots == 0 and locked_shots == 1)
	var gb_shot := gb.locked_normal_attacks[0]
	var pistol_shot := _w("pistol").normal_attacks[0]
	var rifle_shot := _w("rifle").normal_attacks[0]
	_check("its gun is between Pistol and Rifle speed (%.2f s vs %.2f / %.2f)" % [gb_shot.duration, pistol_shot.duration, rifle_shot.duration],
		gb_shot.duration > pistol_shot.duration and gb_shot.duration < rifle_shot.duration)
	var gs := _w("great_sword").normal_attacks[0]
	_check("its blade is between Sword and Great Sword speed (%.2f s vs %.2f / %.2f)" % [gb.normal_attacks[0].duration, _w("sword").normal_attacks[0].duration, gs.duration],
		gb.normal_attacks[0].duration > _w("sword").normal_attacks[0].duration and gb.normal_attacks[0].duration < gs.duration)
	gb_target.queue_free()

	# Machine Pistol: hold for automatic fire.
	_equip(null, _w("machine_pistol"))
	await _place(ARENA)
	var fired := 0
	Input.action_press("hand_x")
	for i in 60:
		await physics_frame
		for p in _projectiles():
			if not p.has_meta("seen"):
				p.set_meta("seen", true)
				fired += 1
	Input.action_release("hand_x")
	await _idle()
	_check("Machine Pistol automatic fire (%d shots in 1 s)" % fired, fired >= 6)
	_equip(_w("machine_pistol"), _w("machine_pistol"))
	await _place(ARENA)
	fired = 0
	Input.action_press("hand_x")
	for i in 60:
		await physics_frame
		for p in _projectiles():
			if not p.has_meta("seen"):
				p.set_meta("seen", true)
				fired += 1
	Input.action_release("hand_x")
	await _idle()
	_check("two Machine Pistols (powerstance) keep firing while held (%d shots in 1 s)" % fired, fired >= 12)
	var mp := _w("machine_pistol")
	var ar := _w("assault_rifle")
	_check("Machine Pistol: single-shot taps, half its old damage, the AR's old rate (count %d, base %.1f, tick %.2f)" % [
		mp.normal_attacks[0].projectile_count, mp.base_damage, mp.sustained_attack.sustained_tick],
		mp.normal_attacks[0].projectile_count == 1 and is_equal_approx(mp.base_damage, 3.0)
		and is_equal_approx(mp.sustained_attack.sustained_tick, 0.11))
	_check("Assault Rifle: 33%% slower, +25%% damage (tick %.3f, base %.2f)" % [ar.sustained_attack.sustained_tick, ar.base_damage],
		is_equal_approx(ar.sustained_attack.sustained_tick, 0.146) and is_equal_approx(ar.base_damage, 11.25))

	# --- Staff, Heal and Cure ----------------------------------------------
	_combat.set_job("I")
	_equip(null, _w("staff"))
	for id in [&"heal", &"cure", &"mezfulmo"]:
		_player.save.character.spells[id] = 1
	var staff_slots := [&"fajro", &"glacio", &"mezfulmo", &"heal"]
	for i in 4:
		_combat.get_loadout().set_spell(1, i, staff_slots[i])
	await _place(ARENA)
	_started.clear()
	for press in [["hand_x", false], ["hand_y", false], ["hand_x", true], ["hand_y", true]]:
		if press[1]:
			Input.action_press("shift")
		await _tap(press[0])
		Input.action_release("shift")
		await _idle()
	_check("Staff: X, Y, RT+X, RT+Y cast four spells (%s)" % [_started],
		_started == ["Fajro", "Glacio", "Mezfulmo", "Heal"])
	_equip(null, _w("talisman"))
	_combat.get_loadout().set_spell(1, 0, &"heal")
	_combat.get_loadout().set_spell(1, 1, &"cure")
	_player.health.hp = 50.0
	await _tap("hand_x")
	await _idle()
	_check("Heal restores HP (50 -> %.0f)" % _player.health.hp, _player.health.hp > 100.0)
	# Cure levels go through statuses least annoying first: Slow, Burn, Poison...
	_player.status.apply(StatusEffects.Status.POISON, 10.0)
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	await _idle()
	var cure_1_left_poison := _player.status.is_active(StatusEffects.Status.POISON)
	_player.save.character.spells[&"cure"] = 3
	_combat.lp = _combat.stats.max_lp
	Input.action_press("shift")
	await _tap("hand_x")
	Input.action_release("shift")
	await _idle()
	_check("Cure 1 only clears Slow; Cure 3 clears Poison", cure_1_left_poison and _player.status.active.is_empty())
	_combat.set_job("S")
	_equip(_w("sword"), _w("pistol"))

	# --- Drops, EXP and pickups --------------------------------------------
	var exp0 := _player.save.character.experience
	var victim := _spawn("grub_hound", ARENA + Vector3(0, 0, -5))
	victim.health.take_damage(_info(9999.0, null))
	await _frames(5)
	_check("defeating an enemy gives its EXP (+%d)" % (_player.save.character.experience - exp0),
		_player.save.character.experience - exp0 == victim.data.exp_value())
	var found := _w("spear").duplicate() as WeaponData
	_main.spawn_drop({"weapon": found}, ARENA + Vector3(0, 0, -3))
	_main.spawn_drop({"oro": 25}, ARENA + Vector3(0.5, 0, -3))
	_main.spawn_drop({"consumable": &"hp_gel"}, ARENA + Vector3(-0.5, 0, -3))
	var oro := _player.save.inventory.oro
	var gels := _player.save.inventory.count(&"hp_gel")
	await _place(ARENA + Vector3(0, 0, -3))
	await _frames(10)
	_check("walking over drops collects them (weapon, Oro, HP Gel)",
		found in _player.save.inventory.weapons and _player.save.inventory.oro == oro + 25
		and _player.save.inventory.count(&"hp_gel") == gels + 1)
	_player.health.hp = 100.0
	await _tap("item_1")
	_check("D-pad left / 1 uses an HP Gel (100 -> %.0f)" % _player.health.hp, _player.health.hp > 100.0)

	# --- Lumidium ----------------------------------------------------------
	var node := _main.get_node("Gathering/NodeA1") as LumidiumNode
	await _place(node.global_position + Vector3(0, 0.1, 2.0))
	for i in 3:
		await _tap("hand_y")  # Y = left hand = Sword
		await _idle()
	await _frames(10)
	_check("a Lumidium node breaks after 3 hits", node == null or not is_instance_valid(node) or node.is_broken())
	await _place(Vector3(-8.5, 0.1, 8.5))
	await _frames(10)
	_check("its crystals are picked up (%d carried)" % _player.carried_lumidium_total(), _player.carried_lumidium_total() == 3)
	_player.health.take_damage(_info(99999.0, null))
	await _frames(5)
	_check("dying loses carried Lumidium", _player.carried_lumidium_total() == 0)
	_player.add_lumidium(&"ice", 4)
	var pad := _main.get_node("Gathering/TeleporterStart") as Teleporter
	await _place(pad.global_position + Vector3(0, 0.1, 0))
	await _frames(10)
	_check("a teleporter deposits it (banked %d, carried %d)" % [_player.save.inventory.lumidium_total(), _player.carried_lumidium_total()],
		_player.save.inventory.lumidium_total() == 4 and _player.carried_lumidium_total() == 0)

	# --- Save file ---------------------------------------------------------
	var data := _player.save
	data.loadouts.loadouts[7] = Loadout.make(null, found)
	ResourceSaver.save(data, TEST_SAVE)
	var loaded := ResourceLoader.load(TEST_SAVE, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	_check("save round-trip keeps inventory, Oro and banked Lumidium",
		loaded.inventory.weapons.size() == data.inventory.weapons.size()
		and loaded.inventory.oro == data.inventory.oro and loaded.inventory.lumidium_total() == 4)
	_check("a found weapon in a loadout is the same object as in the inventory",
		loaded.loadouts.loadouts[7].right in loaded.inventory.weapons)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ------------------------------------------------------------------

func _w(type: String) -> WeaponData:
	return load(WEAPON_DIR + type + ".tres") as WeaponData


func _rare(name: String) -> WeaponData:
	for r in Loot.rare_weapons():
		if r.display_name == name:
			return r
	return null


func _line(name: String) -> SpecialTag:
	for line in SpecialTag.all_lines():
		if line.line_name == name:
			return line
	return null


func _tagged(type: String, line: String, tier: int) -> WeaponData:
	var w := _w(type).duplicate() as WeaponData
	w.base_name = w.display_name
	Loot.apply_tag(w, _line(line), tier)
	return w


func _info(amount: float, weapon: WeaponData, special := false) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	info.weapon = weapon
	info.special = special
	info.kind = DamageInfo.Kind.MELEE
	info.source = _player
	return info


## A passive enemy (no aggro, no attacks) with plenty of HP.
func _spawn(file: String, at: Vector3) -> Enemy:
	var data := (load("res://data/enemies/" + file + ".tres") as EnemyData).duplicate() as EnemyData
	data.aggro_range = 0.0
	data.max_hp = 600.0
	data.evasion = 0.0
	var enemy := Enemy.create(data)
	_main.add_child(enemy)
	enemy.global_position = at
	return enemy


func _equip(left: WeaponData, right: WeaponData) -> void:
	_combat.loadout_set.loadouts[7] = Loadout.make(left, right)
	_combat.select_loadout(7)


func _place(at: Vector3) -> void:
	_combat.cancel()
	_combat.lp = _combat.stats.max_lp
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(10)


func _projectiles() -> Array[Projectile]:
	var list: Array[Projectile] = []
	for child in _main.get_children():
		if child is Projectile and child.target_mask == Projectile.ENEMY_MASK:
			list.append(child)
	return list


## Projectiles that appeared since the last call.
func _count_new() -> int:
	var n := 0
	for p in _projectiles():
		if not p.has_meta("counted"):
			p.set_meta("counted", true)
			n += 1
	return n


func _hit(target: Node) -> bool:
	for h in _hits:
		if h[0] == target and h[1] > 0.0:
			return true
	return false


func _until_fired() -> void:
	for i in 60:
		var cur = _combat._current
		if cur == null or cur.fired:
			return
		await physics_frame


func _until_window() -> void:
	for i in 180:
		var cur = _combat._current
		if cur == null or cur.elapsed >= cur.attack.window_open + 0.03:
			return
		await physics_frame


func _idle() -> void:
	for i in 240:
		if not _combat.is_attacking():
			break
		await physics_frame
	await _frames(10)


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame
	await physics_frame
