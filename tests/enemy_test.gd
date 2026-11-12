extends SceneTree
## Automated test for Part 4: enemy roster, defense stats and misses, status
## effects, enemy AI (melee and ranged on the navmesh), staggers, Ward reflect,
## and PSO-style wave rooms. Runs in scenes/arena.tscn.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/enemy_test.gd

const ENEMY_DIR := "res://data/enemies/"

var _main: Node
var _player: Player
var _combat: CombatController
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_combat = _player.combat
	# A fresh save (Striker, default loadouts) that is never written to disk.
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_player.autosave = false
	_combat.stats.luck = 0.0
	# Keep the rooms dormant while other checks use the space; Room A is
	# switched back on for the wave test at the end.
	var room_a: WaveRoom = _main.get_node("Rooms/RoomA")
	var room_b: WaveRoom = _main.get_node("Rooms/RoomB")
	room_a.state = WaveRoom.RoomState.CLEARED
	room_b.state = WaveRoom.RoomState.CLEARED
	await _frames(30)

	# --- Roster: one enemy per monster type ---
	var types := {}
	for file in DirAccess.get_files_at(ENEMY_DIR):
		if file.ends_with(".tres"):
			var data := load(ENEMY_DIR + file) as EnemyData
			types[data.enemy_type] = data.display_name
	_check("all six monster types have an enemy (%s)" % [types.values()], types.size() == 6)

	# --- Defense: DEF covers melee and ranged, RES magic ---
	_check("DEF 20 takes 83%% of a melee hit", is_equal_approx(Defense.scale_for(DamageInfo.Kind.MELEE, 20, 0), 100.0 / 120.0))
	_check("RES applies to magic, DEF to ranged (EVA no longer reduces damage)",
		is_equal_approx(Defense.scale_for(DamageInfo.Kind.MAGIC, 0, 50), 100.0 / 150.0)
		and is_equal_approx(Defense.scale_for(DamageInfo.Kind.RANGED, 100, 0), 0.5))

	# --- Hit chance (Accuracy): PSO-based, kinder, with a combo ramp ---
	var ata := 40.0
	var pct := func(hard: bool, step: int, eva: float, streak: int = 0, special := false) -> float:
		var info := DamageInfo.new()
		info.accuracy = Accuracy.effective_ata(ata, hard, special, false, step)
		info.hit_bonus = Accuracy.streak_bonus(streak)
		return Accuracy.hit_percent(info, eva)
	var n1: float = pct.call(false, 1, 60.0)
	var n2: float = pct.call(false, 2, 60.0)
	var h1: float = pct.call(true, 1, 60.0)
	var h2: float = pct.call(true, 2, 60.0)
	_check("normal hits land often (88%%) and the combo raises it (step 2: %.0f%%)" % n2, is_equal_approx(n1, 88.0) and n2 > n1)
	_check("opening with a Hard hit is penalised (%.0f%%), Hard later in a combo much less (%.0f%%)" % [h1, h2],
		is_equal_approx(h1, 76.0) and h2 > n1)
	var sprite_eva := 140.0
	var s1: float = pct.call(false, 1, sprite_eva)
	var s1_streak: float = pct.call(false, 1, sprite_eva, 2)
	_check("evasive enemies are harder (Lumen Sprite: %.0f%%) and each landed hit helps the next (+%.0f)" % [s1, s1_streak - s1],
		s1 < n1 and is_equal_approx(s1_streak - s1, 8.0) and is_equal_approx(pct.call(false, 1, sprite_eva, 9) - s1, 12.0))
	var spell := DamageInfo.new()
	_check("spells never miss", Accuracy.hit_percent(spell, 999.0) == 100.0)
	var frozen := StatusEffects.new()
	frozen.apply(StatusEffects.Status.FREEZE)
	var frozen_info := DamageInfo.new()
	frozen_info.accuracy = Accuracy.effective_ata(ata, false, false, false, 1)
	_check("Frozen targets are easier to hit (EVA x0.7)", Accuracy.hit_percent(frozen_info, sprite_eva, frozen) > s1)
	frozen.free()
	_combat.stats.evasion = 400.0  # 60 + 50 - 80 = 30% for a typical enemy ATA of 50
	var lands := 0
	for i in 400:
		var info := _hit(10.0, DamageInfo.Kind.MELEE)
		info.accuracy = 50.0
		if _player.receive_hit(info, null) > 0.0:
			lands += 1
		_player.health.restore_full()
	_check("a very evasive Seeker gets hit ~30%% of the time (%d / 400)" % lands, lands > 85 and lands < 155)
	_combat.stats.evasion = 0.0
	_combat.stats.defense = 20.0
	var taken := _player.receive_hit(_hit(18.0, DamageInfo.Kind.MELEE), null)
	_check("a Hound swipe (18) on DEF 20 deals 15 (%.1f)" % taken, is_equal_approx(taken, 15.0))
	_player.health.restore_full()

	# --- Status effects ---
	var probe := _spawn("grub_hound", Vector3(10, 0, -5))
	await _frames(2)
	probe.data.evasion = 0.0
	var st := probe.status
	st.add_buildup(_hit(st.threshold, DamageInfo.Kind.MAGIC, Element.Type.FIRE))
	var hp := probe.health.hp
	await _frames(70)
	_check("Fire buildup starts Burn, which ticks damage (%.0f -> %.0f)" % [hp, probe.health.hp],
		st.is_active(StatusEffects.Status.BURN) and probe.health.hp < hp)
	st.clear_all()
	st.add_buildup(_hit(st.threshold, DamageInfo.Kind.MAGIC, Element.Type.ICE))
	_check("Ice buildup Freezes (can't act), with no Slow", st.is_active(StatusEffects.Status.FREEZE) and not st.can_act()
		and not st.is_active(StatusEffects.Status.SLOW))
	st.clear_all()
	st.apply(StatusEffects.Status.SLOW)
	_check("Slow (from traps) halves move speed", st.move_scale() == 0.5)
	st.clear_all()
	st.add_buildup(_hit(st.threshold, DamageInfo.Kind.MAGIC, Element.Type.LIGHTNING))
	_check("Lightning Shocks (stunned)", st.is_active(StatusEffects.Status.SHOCK) and not st.can_act())
	st.clear_all()
	st.add_buildup(_hit(st.threshold, DamageInfo.Kind.MAGIC, Element.Type.LIGHT))
	_check("Light Confuses", st.is_confused())
	st.clear_all()
	_player.health.hp = 100.0
	st.add_buildup(_hit(st.threshold, DamageInfo.Kind.MAGIC, Element.Type.DARK), _player)
	await _frames(70)
	_check("Dark Drains and heals whoever applied it (Seeker HP %.0f)" % _player.health.hp,
		st.is_active(StatusEffects.Status.DRAIN) and _player.health.hp > 100.0)
	st.clear_all()
	st.add_buildup(_hit(st.threshold * 0.5, DamageInfo.Kind.MAGIC, Element.Type.FIRE))
	_check("Generic damage builds nothing; half a threshold starts nothing",
		st.active.is_empty() and st.buildup.get(Element.Type.FIRE, 0.0) > 0.0)
	probe.queue_free()
	_player.health.restore_full()

	# --- Melee AI: a Hound paths to the Seeker and hits them ---
	_combat.stats.defense = 0.0
	_place_player(Vector3(0, 0.1, 18))
	var hound := _spawn("grub_hound", Vector3(0, 0, 13))
	hound.data.evasion = 0.0
	var d0 := hound.global_position.distance_to(_player.global_position)
	hp = _player.health.hp
	var area_during_windup := false
	var area_on_strike := false
	for i in 240:
		await physics_frame
		if hound.state == Enemy.State.WINDUP and hound.hit_area.visible:
			area_during_windup = true
		if _player.health.hp < hp:
			await process_frame
			area_on_strike = hound.hit_area.visible
			break
	_check("its hit area shows during the windup and flashes on the strike",
		hound.hit_area != null and area_during_windup and area_on_strike)
	_check("Grub Hound closes in (%.1f m -> %.1f m) and hits for its damage (took %.0f)" % [
		d0, hound.global_position.distance_to(_player.global_position), hp - _player.health.hp],
		hound.global_position.distance_to(_player.global_position) < d0 and is_equal_approx(hp - _player.health.hp, 18.0))
	# Hit reactions: Hard hits almost always push back; light hits don't interrupt.
	var flinches := 0
	var pushed := false
	for i in 20:
		hound.state = Enemy.State.CHASE
		hound._knockback = Vector3.ZERO
		var info := _hit(5.0, DamageInfo.Kind.MELEE)
		info.is_hard = true
		hound.receive_hit(info, _player)
		if hound.state == Enemy.State.STAGGER:
			flinches += 1
			pushed = pushed or hound._knockback.length() > 1.0
		hound.health.restore_full()
	_check("Hard hits almost always push it back and flinch it (%d / 20)" % flinches, flinches >= 14 and pushed)
	hound.state = Enemy.State.WINDUP
	hound._timer = 5.0
	var interrupted := false
	for i in 20:
		hound.receive_hit(_hit(10.0, DamageInfo.Kind.MELEE), _player)
		interrupted = interrupted or hound.state != Enemy.State.WINDUP
		hound.health.restore_full()
	_check("light hits never interrupt a windup (20 hits)", not interrupted)
	hound.state = Enemy.State.CHASE
	hound._knockback = Vector3.ZERO
	await _frames(2)
	hound.status.apply(StatusEffects.Status.FREEZE, 2.0)
	var frozen_at := hound.global_position
	hp = _player.health.hp
	await _frames(90)
	_check("a Frozen enemy neither moves nor attacks",
		hound.global_position.distance_to(frozen_at) < 0.2 and _player.health.hp == hp)
	hound.queue_free()
	_player.health.restore_full()

	# --- Ranged AI and Ward reflect ---
	_place_player(Vector3(0, 0.1, 0))
	var drone := _spawn("sentry_drone", Vector3(0, 0, -7))
	drone.data.evasion = 0.0
	hp = _player.health.hp
	for i in 300:
		await physics_frame
		if _player.health.hp < hp:
			break
	var drone_dist := drone.global_position.distance_to(_player.global_position)
	_check("Sentry Drone keeps its distance (%.1f m) and shoots (took %.0f)" % [drone_dist, hp - _player.health.hp],
		drone_dist > 4.5 and _player.health.hp < hp)
	_player.health.restore_full()

	var ward_loadout := Loadout.make(CombatController.load_weapon("pistol"), CombatController.load_weapon("ward"))
	_combat.loadout_set.loadouts[7] = ward_loadout
	_combat.select_loadout(7)
	_player.face_direction(drone.global_position - _player.global_position)
	await _frames(5)
	var drone_hp := drone.health.hp
	hp = _player.health.hp
	var reflected := false
	for i in 360:
		await physics_frame
		var incoming := _incoming_shot()
		if incoming and incoming.global_position.distance_to(_player.global_position) < 3.5:
			_player.face_direction(drone.global_position - _player.global_position)
			await _tap(_combat._action_for(CombatController.Hand.OFF))  # Ward's Reflect
			for j in 60:
				await physics_frame
				if drone.health.hp < drone_hp:
					reflected = true
					break
			break
	_check("Ward's Reflect sends a Drone bolt back into the Drone (Drone %.0f -> %.0f, Seeker took %.0f)" % [
		drone_hp, drone.health.hp, hp - _player.health.hp], reflected and _player.health.hp == hp)
	drone.queue_free()
	_combat.loadout_set.loadouts[7] = Loadout.new()
	_combat.select_loadout(0)
	await _frames(5)

	# --- Wave room ---
	var room := room_a
	room.state = WaveRoom.RoomState.WAITING
	_place_player(Vector3(0, 0.1, 18))
	await _frames(5)
	var waves_seen: Array[int] = []
	var cleared := [false]
	room.wave_started.connect(func(_r, index, _total): waves_seen.append(index))
	room.room_cleared.connect(func(_r): cleared[0] = true)
	_check("PSO doors: before the fight, the way on (exit door) is already locked",
		room.state == WaveRoom.RoomState.WAITING and _door_closed(room))
	_check("and there's no door shutting the way in behind you", room.get_node("Doors").get_child_count() == 1)
	_place_player(Vector3(0, 0.1, 6))
	await _frames(10)
	_check("walking in starts the fight, exit still locked", room.state == WaveRoom.RoomState.ACTIVE and _door_closed(room))
	await create_timer(1.2).timeout
	_check("wave 1 spawns 3 Grub Hounds (%d alive)" % room.alive.size(), room.alive.size() == 3 and waves_seen == [0])
	for wave in 3:
		while room.alive.is_empty():
			await physics_frame
		await _frames(5)
		for enemy in room.alive.duplicate():
			enemy.health.take_damage(_hit(9999.0, DamageInfo.Kind.MELEE))
		for i in 150:
			await physics_frame
			if waves_seen.size() > wave + 1 or cleared[0]:
				break
	_check("clearing each wave starts the next (waves %s)" % [waves_seen], waves_seen == [0, 1, 2])
	await _frames(10)
	_check("after the last wave the room is clear and the exit unlocks",
		cleared[0] and room.state == WaveRoom.RoomState.CLEARED and not _door_closed(room))

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _hit(amount: float, kind: DamageInfo.Kind, element: Element.Type = Element.Type.GENERIC) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	info.kind = kind
	info.damage_type = element
	return info


func _spawn(file: String, at: Vector3) -> Enemy:
	var data := (load(ENEMY_DIR + file + ".tres") as EnemyData).duplicate() as EnemyData
	var enemy := Enemy.create(data)
	_main.add_child(enemy)
	enemy.global_position = at
	enemy._aggro = true
	return enemy


func _place_player(at: Vector3) -> void:
	_combat.cancel()
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _incoming_shot() -> Projectile:
	for child in _main.get_children():
		if child is Projectile and child.target_mask == Projectile.PLAYER_MASK:
			return child
	return null


func _door_closed(room: WaveRoom) -> bool:
	var door := room.get_node("Doors").get_child(0) as CSGShape3D
	return door.visible and door.use_collision


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
