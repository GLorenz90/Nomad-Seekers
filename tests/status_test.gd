extends SceneTree
## Status effect rules (Grayson 2026-11-12):
## - Durations: Burn 5 s, Slow 7 s, Freeze 5 s, Stun 5 s; Shock until cured on
##   Seekers (5 s stop for Goluman and enemies); Poison until cured or 1 HP.
## - Struggling: buttons and stick swings shorten Freeze (and a Goluman's
##   Shock); only stick swings shorten Burn.
## - Burn and Poison on Seekers scale with difficulty.
## - Status-line tags build their element's status; Light confuses (Blind is gone).
## - Confused enemies attack whoever is closest; confused Seekers hit and heal
##   friend and foe, lock onto partners, lose their target rings, and see
##   everyone as ghosts behind a haze.
## Runs in scenes/arena.tscn.
##   godot --headless --path . --script res://tests/status_test.gd

const ENEMY_DIR := "res://data/enemies/"
const S := StatusEffects.Status

var _main: Node
var _player: Player
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_player.use_save(SaveData.create("Tester", CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
		CharacterData.Job.STRIKER, 1))
	_player.autosave = false
	for room in ["Rooms/RoomA", "Rooms/RoomB"]:
		(_main.get_node(room) as WaveRoom).state = WaveRoom.RoomState.CLEARED
	await _frames(30)
	var st := _player.status

	# --- Durations ------------------------------------------------------------------------------
	st.apply(S.BURN)
	st.apply(S.SLOW)
	_check("Burn lasts 5 s, Slow 7 s", is_equal_approx(st.active[S.BURN], 5.0) and is_equal_approx(st.active[S.SLOW], 7.0))
	st.clear_all()
	st.apply(S.FREEZE)
	_check("Freeze lasts 5 s", is_equal_approx(st.active[S.FREEZE], 5.0))
	st.clear_all()
	st.apply(S.STUN)
	_check("Stun lasts 5 s", is_equal_approx(st.active[S.STUN], 5.0))
	st.on_hit()
	_check("a hit ends a Seeker's Stun", not st.is_active(S.STUN))
	st.apply(S.SHOCK)
	await _frames(30)
	_check("Shock on a (non-Goluman) Seeker lasts until cured: can move, can't attack",
		is_inf(float(st.active[S.SHOCK])) and st.can_move() and not st.can_act())
	st.cure(99)
	_check("Cure ends it", not st.is_active(S.SHOCK))

	# --- Struggling ---------------------------------------------------------------------------------
	st.apply(S.FREEZE)
	var before := float(st.active[S.FREEZE])
	for i in 4:
		await _tap("jump")
	var after := float(st.active[S.FREEZE])
	_check("mashing buttons shortens Freeze (%.2f -> %.2f, beyond the time passed)" % [before, after],
		before - after > 4 * StatusEffects.STRUGGLE_STEP * 0.9)
	before = float(st.active[S.FREEZE])
	await _wiggle(4)
	after = float(st.active[S.FREEZE])
	_check("wiggling the stick shortens it too (%.2f -> %.2f)" % [before, after],
		before - after > 3 * StatusEffects.STRUGGLE_STEP)
	st.clear_all()
	st.apply(S.BURN)
	before = float(st.active[S.BURN])
	_check("buttons don't shorten Burn", not st.struggle(true) and is_equal_approx(float(st.active[S.BURN]), before))
	_check("but rolling around (stick swings) does", st.struggle(false) and float(st.active[S.BURN]) < before)
	st.clear_all()

	# --- Poison and difficulty -------------------------------------------------------------------
	_player.health.restore_full()
	st.apply(S.POISON)
	_check("Poison has no timer", is_inf(float(st.active[S.POISON])))
	_player.health.hp = 3.0
	await _frames(70)
	_check("it never kills: it ends when it brings you to 1 HP (%.1f HP)" % _player.health.hp,
		is_equal_approx(_player.health.hp, 1.0) and not st.is_active(S.POISON))
	_player.health.restore_full()
	st.apply(S.POISON)
	st.cure(99)
	_check("Cure ends Poison", not st.is_active(S.POISON))
	_player.health.restore_full()
	var hp := _player.health.hp
	st._damage_over_time(S.BURN)
	var normal_tick := hp - _player.health.hp
	_player.health.restore_full()
	Session.difficulty = "hard"
	st._damage_over_time(S.BURN)
	var hard_tick := hp - _player.health.hp
	Session.difficulty = "normal"
	_player.health.restore_full()
	_check("Burn on Seekers scales with difficulty (%.1f -> %.1f on Hard)" % [normal_tick, hard_tick],
		is_equal_approx(hard_tick, normal_tick * StatusEffects.DIFFICULTY_DOT["hard"]))

	# --- Goluman and enemies ------------------------------------------------------------------------
	var gol := StatusEffects.new()
	gol.shock_stuns = true
	gol.apply(S.SHOCK)
	_check("Goluman (and enemies) are stopped by Shock for 5 s, which mashing shortens",
		is_equal_approx(float(gol.active[S.SHOCK]), 5.0) and not gol.can_move() and gol.struggle(true)
		and float(gol.active[S.SHOCK]) < 5.0)
	gol.free()

	# --- Status lines, Light -> Confuse ------------------------------------------------------------
	var sword := (load("res://data/weapons/sword.tres") as WeaponData).duplicate() as WeaponData
	sword.base_name = sword.display_name
	Loot.apply_tag(sword, SpecialTag.find_line("Static"), 1)
	var special := sword.get_special()
	_check("a Static-line weapon deals Lightning (%s)" % sword.display_name,
		sword.damage_type == Element.Type.LIGHTNING and sword.tag.describe(1).contains("Shock"))
	_check("its special hits for half and builds Shock hard",
		is_equal_approx(special.damage_mult, sword.normal_attacks[0].damage_mult * 0.5) and special.status_power >= 10.0)
	var target := _spawn("grub_hound", Vector3(8, 0, -6))
	await _frames(2)
	var info := DamageInfo.new()
	info.amount = target.status.threshold
	info.inflicts_status = S.STUN
	target.status.add_buildup(info)
	_check("Stun buildup (traps) Stuns an enemy for 5 s",
		target.status.is_active(S.STUN) and is_equal_approx(float(target.status.active[S.STUN]), 5.0))
	target.status.clear_all()
	var light := DamageInfo.new()
	light.amount = target.status.threshold
	light.damage_type = Element.Type.LIGHT
	target.status.add_buildup(light)
	_check("Light builds Confuse (Blind is gone)", target.status.is_confused())

	# --- Confused enemies --------------------------------------------------------------------------
	_player.global_position = Vector3(30, 0.1, 10)
	var other := _spawn("grub_hound", Vector3(9.5, 0, -6))
	await _frames(2)
	_check("a confused enemy goes for whoever is closest, even another enemy",
		target._nearest_anyone() == other)
	var other_hp := other.health.hp
	other.data.evasion = 0.0
	target._attack(other)
	_check("and hurts it (%.0f -> %.0f)" % [other_hp, other.health.hp], other.health.hp < other_hp)
	target.status.clear_all()
	_check("cleared, it's back to Seekers only", Player.nearest(target, target.global_position) == _player)

	# --- Confused Seekers ---------------------------------------------------------------------------
	var partner := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	_main.add_child(partner)
	partner.input_locked = true
	partner.global_position = Vector3(2, 0.1, 6)
	_player.global_position = Vector3(0, 0.1, 8)
	other.global_position = Vector3(1, 0, 4)
	target.global_position = Vector3(-2, 0, 4)
	await _frames(10)
	var combat := _player.combat
	_check("normally attacks hit enemies only", combat.hit_mask() == CombatController.ENEMY_MASK)
	_check("and spells skip partners", not SpellCaster._targets(_player).has(partner))
	_player.status.apply(S.CONFUSE)
	await _frames(40)
	_check("confused, attacks hit partners too", combat.hit_mask() & CombatController.PLAYER_MASK != 0)
	_check("damage spells reach partners", SpellCaster._targets(_player).has(partner))
	var party := SpellCaster._party(_player, 20.0)
	_check("heals and buffs reach enemies (%d in range)" % party.size(), party.has(other) and party.has(partner))
	_check("lock-on can pick a partner", _player.camera_rig._lock_candidates().has(partner)
		and _player.camera_rig._is_lockable(partner))
	var markers: TargetMarkers = _main.target_markers
	_check("target rings are hidden", markers.get_marked().is_empty())
	var view := markers.confusion_view
	_check("everyone else is a ghost (%d ghosts)" % view.ghost_count(), view.ghost_count() >= 3)
	_check("the real enemies and partner are hidden from this Seeker's camera",
		_player.camera_rig.hidden_layers & ConfusionView.ENEMY_BIT != 0
		and _player.camera_rig.camera.cull_mask & ConfusionView.ENEMY_BIT == 0
		and other.get_children().any(func(c): return c is VisualInstance3D and (c as VisualInstance3D).layers == ConfusionView.ENEMY_BIT))
	_check("but not the Seeker's own model", _player.camera_rig.camera.cull_mask & ConfusionView.seeker_bit(0) != 0)
	var hud: DebugHud = _main.hud
	_check("a haze covers the screen (%.2f)" % hud._haze.modulate.a, hud._haze.modulate.a > 0.5)
	_player.status.cure(99)
	await _frames(40)
	_check("cured: ghosts and haze go, everything is visible again",
		view.ghost_count() == 0 and _player.camera_rig.hidden_layers == 0 and hud._haze.modulate.a < 0.5
		and combat.hit_mask() == CombatController.ENEMY_MASK)

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------------------------

func _spawn(file: String, at: Vector3) -> Enemy:
	var data := (load(ENEMY_DIR + file + ".tres") as EnemyData).duplicate() as EnemyData
	var enemy := Enemy.create(data)
	_main.add_child(enemy)
	enemy.global_position = at
	return enemy


func _wiggle(swings: int) -> void:
	for i in swings:
		var action := "move_left" if i % 2 == 0 else "move_right"
		Input.action_press(action)
		await _frames(2)
		Input.action_release(action)


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
	Input.action_release(action)
	await physics_frame
