class_name Player
extends CharacterBody3D
## The Seeker controller: ground movement, jump and dash/dodge.
##
## Movement is camera-relative. While the camera is locked on, the Seeker always
## faces the target, and stick input becomes forward/back toward the target and
## strafing around it (Dark Souls-style orbit).
##
## Feel goals, borrowed from Spiral Knights: snappy acceleration, no slippery
## stops, a forgiving jump (coyote time + input buffer), and a dash you can
## chain into a jump.
##
## While an attack plays (see CombatController) the Seeker is either rooted
## (apart from the attack's lunge) or keeps moving at the attack's reduced
## move_speed_scale, without jumping. Dashing cancels an attack once its hit is out.

signal jumped
signal landed
signal dash_started(direction: Vector3)
signal dash_ended
signal exp_gained(amount: int)
signal item_collected(text: String)
## Part 11: a level-up, with what each stat gained.
signal leveled_up(level: int, gains: Dictionary)

enum State { GROUND, AIR, DASH }

## The d-pad palette (Grayson, 2026-11-09): item_1-4 are d-pad left / up /
## right / down; holding RT shifts to slots 5-8. What's in them is the save's
## (SaveData.quick_slots): consumables, and traps for Goluman.

@export_group("Ground")
@export var move_speed := 7.0
@export var acceleration := 55.0
@export var deceleration := 65.0
@export var turn_speed := 16.0
## Speed multiplier while locked on (strafing is a little slower).
@export var lock_on_speed_scale := 0.85

@export_group("Jump")
@export var jump_height := 1.6
@export var time_to_peak := 0.34
@export var time_to_land := 0.28
## Extra gravity while rising after jump is released, for short hops.
@export var jump_cut_gravity_scale := 2.5
@export_range(0.0, 1.0) var air_control := 0.65
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var max_fall_speed := 30.0

@export_group("Dash")
@export var dash_distance := 4.5
@export var dash_duration := 0.18
## Delay between dashes (Grayson, 2026-11-08: dashing was far too strong).
@export var dash_cooldown := 5.0
## Invulnerability window at the start of a dash (used by combat in Part 2).
@export var dash_invuln_time := 0.15
@export var air_dash_count := 1
## How much dash speed is kept when the dash ends (or turns into a jump).
@export_range(0.0, 1.0) var dash_exit_speed_scale := 0.55

var camera_rig: CameraRig
var state: State = State.AIR
## Everything the Seeker keeps (character, loadouts, inventory). See use_save().
var save: SaveData
## Lumidium picked up but not yet deposited at a teleporter. Lost on death.
var carried_lumidium: Dictionary = {}
## Writes user://save.tres on deposits and menu closes. Tests turn this off.
var autosave := true
## The paired SyncAIDa following the Seeker (Part 6).
var syncaida: SyncAIDaCompanion

## Part 12: this Seeker's controls. Shared (every device) when playing alone;
## its own controller in a party (see PlayerInput, Party).
var input: PlayerInput = PlayerInput.shared()
## Party guests: the controller that plays this Seeker (set before it enters
## the tree; it then plays that guest's character). -1 = the leader.
var guest_device := -1
## Part 12: down in co-op, waiting for a partner's Revive (or A to go back
## to the start).
var downed := false
## Where this Seeker's menus go: its split-screen pane, or the window.
var ui_parent: Node = null

var _jump_velocity := 0.0
var _gravity_up := 0.0
var _gravity_down := 0.0

var _coyote_timer := 0.0
var _jump_buffer := 0.0
var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _invuln_timer := 0.0
var _dash_direction := Vector3.FORWARD
var _air_dashes_left := 0
var _squash_tween: Tween

@onready var _visual: Node3D = $Visual
@onready var combat: CombatController = $Combat
@onready var health: Health = $Health
@onready var status: StatusEffects = $StatusEffects


func _ready() -> void:
	add_to_group("player")
	health.max_hp = combat.stats.max_hp
	health.hp = health.max_hp
	syncaida = SyncAIDaCompanion.new()
	syncaida.name = "SyncAIDa"
	add_child(syncaida)
	syncaida.setup(self)
	var defaults := CombatController.make_default_loadouts()
	var guest := Party.guest_for(guest_device) if guest_device >= 0 else {}
	if not guest.is_empty():
		use_save(guest.save as SaveData)
	elif combat.use_saved_loadouts:
		use_save(Session.current_save(defaults))
	else:
		use_save(SaveData.fresh(defaults))
		autosave = false


## Switches to a save: its loadouts, job and inventory.
func use_save(data: SaveData) -> void:
	save = data
	# The satchel's Lumidium lives in the save so it crosses maps (Grayson,
	# 2026-11-10); carried_lumidium is the same Dictionary.
	carried_lumidium = save.satchel_lumidium
	combat.inventory = save.inventory
	combat.job_code = save.character.job_code()
	combat.set_left_handed(save.character.left_handed)
	combat.apply_loadout_set(save.loadouts)
	if syncaida:
		syncaida.pair(save.paired_syncaida())
	apply_materials()


# --- Materials (PSO) --------------------------------------------------------------------

var _material_applied := {}


## Moves the material stat bonus to the current save's counts (like the
## SyncAIDa bonus, only the difference is applied).
func apply_materials() -> void:
	apply_bonuses()


## Moves every flat bonus from the save (materials, race, armor and its
## augments) onto the stats; only the difference from last time is applied.
## Also turns the Double-Heavy rule on when an augment for it is worn.
func apply_bonuses() -> void:
	var target := Materials.bonuses(save.character) if save else {}
	if save:
		for extra in [save.character.race_bonuses(), ArmorBook.bonuses(save.character),
				Leveling.bonuses(save.character)]:
			for stat in extra:
				target[stat] = float(target.get(stat, 0.0)) + float(extra[stat])
		if save.loadouts:
			save.loadouts.double_heavy_augment = ArmorBook.has_double_heavy(save.character)
	var s := combat.stats
	var stats_touched: Array = target.keys()
	for stat in _material_applied:
		if not stat in stats_touched:
			stats_touched.append(stat)
	for stat in stats_touched:
		var delta := float(target.get(stat, 0.0)) - float(_material_applied.get(stat, 0.0))
		if delta != 0.0:
			s.set(stat, float(s.get(stat)) + delta)
	_material_applied = target
	combat.lp_regen_fraction = save.character.lp_regen_fraction() if save else 0.0
	status.immune = save.character.status_immunities() if save else []
	status.shock_stuns = save.character.shock_stuns() if save else false
	status.stun_breaks_on_hit = true
	for gone in status.immune:
		if status.is_active(gone):
			status.active.erase(gone)
	if health.max_hp != s.max_hp:
		var gained := s.max_hp - health.max_hp
		health.max_hp = s.max_hp
		health.hp = clampf(health.hp + maxf(gained, 0.0), 0.0, health.max_hp)
	combat.lp = minf(combat.lp, s.max_lp)


# --- Interaction (A) ------------------------------------------------------------------

var _input_hold := 0.0
## Part 11: the menu no longer pauses (PSO). While it's open the Seeker
## stands still and takes no game input, but the world keeps going.
var input_locked := false
## On a peaceful map (Nomad-2): no attacks, spells, traps or Sync Bursts
## (Grayson, 2026-11-10). Read from the level each physics frame.
var peaceful := false


## Ignore jump / dash / interact for a moment (called when a menu closes).
func hold_input(seconds: float = 0.15) -> void:
	_input_hold = seconds

## What A would use right now (a teleporter or an item in reach), or null.
var interact_target: Node3D = null


## The closest interactable in reach. Interactables are in the
## "interactables" group and have interact_point(), interact_range(),
## can_interact(seeker), interact_prompt() and interact(seeker).
func _find_interactable() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in Scope.group(self, "interactables"):
		if not node.is_inside_tree() or not node.can_interact(self):
			continue
		var to: Vector3 = node.interact_point() - global_position
		var dist := Vector2(to.x, to.z).length()
		if dist <= node.interact_range() and absf(to.y) < 2.0 and dist < best_dist:
			best_dist = dist
			best = node
	return best


## "A: Pick up Sword" and the like, for the HUD ("" when nothing is in reach).
func interact_prompt() -> String:
	if interact_target and is_instance_valid(interact_target):
		return "A: " + interact_target.interact_prompt()
	return ""


## Goluman slowly regenerate HP (quietly: no heal numbers every frame).
func _regen_hp(delta: float) -> void:
	if save == null or health.is_dead() or health.hp >= health.max_hp:
		return
	var rate := save.character.hp_regen_fraction()
	if rate > 0.0:
		health.hp = minf(health.hp + health.max_hp * rate * delta, health.max_hp)


## Uses one material from the inventory. Returns the message to show.
func use_material(id: StringName) -> String:
	if save == null:
		return ""
	if save.inventory.count(id) <= 0:
		return "No %s left" % Materials.display_name(id)
	var error := Materials.use_error(save.character, id)
	if error != "":
		return error
	save.inventory.use_consumable(id)
	save.character.materials[id] = int(save.character.materials.get(id, 0)) + 1
	apply_materials()
	var stat := Materials.stat_of(id)
	return "%s +%d (now %d)" % [Materials.stat_label(id), int(Materials.PER_USE), roundi(float(combat.stats.get(stat)))]


## Debug: forgets every material used.
func reset_materials() -> void:
	if save:
		save.character.materials.clear()
		apply_materials()


## Takes one of the four starter SyncAIDa (SyncAIDaData.STARTERS) and pairs it.
func choose_starter(index: int) -> void:
	if save == null:
		return
	save.choose_starter(index)
	syncaida.pair(save.paired_syncaida())
	save_game()


## Pairs a different owned SyncAIDa.
func pair_syncaida(index: int) -> void:
	if save == null or index < 0 or index >= save.syncaida.size():
		return
	save.paired = index
	syncaida.pair(save.paired_syncaida())


# --- Spell discs (Part 6) -------------------------------------------------------------

## SOL (or DEX for traps) counted for learning: base stats plus SyncAIDa.
func learning_stat(spell: SpellDef) -> float:
	return combat.stats.dexterity if spell.is_trap() else combat.stats.soul


## Reads a disc. Learns it when allowed; otherwise, from a pickup, it's stored
## to read later, or sold for Oro if it can never be useful (already known
## at that level or higher). Returns a message for the player.
func read_disc(id: StringName, level: int, from_pickup: bool) -> String:
	var spell := SpellBook.get_spell(id)
	if spell == null or save == null:
		return "Unknown disc"
	var c := save.character
	var error := c.learn_error(spell, level, learning_stat(spell))
	if error == "":
		c.spells[id] = level
		SpellCaster.clear_cache()
		return "Learned %s %d" % [spell.display_name, level]
	if not from_pickup:
		return error
	if c.spell_level(id) >= level or c.level_cap_for(spell) == 0:
		var oro := 20 * level
		save.inventory.add_oro(oro)
		return "%s %d: %s Sold for %d Oro." % [spell.display_name, level, error, oro]
	if not save.take_disc({"id": id, "level": level}):
		return "Your pack is full."
	return "%s %d stored: %s" % [spell.display_name, level, error]


## Picking up a disc (Grayson, 2026-11-09): it always goes into the pack, to
## be read from the Inventory tab (or sold at a shop). Nothing is learned or
## sold on the spot.
func pick_up_disc(id: StringName, level: int) -> String:
	var spell := SpellBook.get_spell(id)
	if spell == null or save == null:
		return "Unknown disc"
	if not save.take_disc({"id": id, "level": level}):
		return "Your pack is full."
	return "Found disc: %s %d (read it from the Inventory tab)" % [spell.display_name, level]


## Discs always take a pack slot now (see pick_up_disc).
func disc_needs_slot(_id: StringName, _level: int) -> bool:
	return true


## Reads a disc from the stash (menu). Removes it once learned.
func read_stored_disc(index: int) -> String:
	if save == null or index < 0 or index >= save.inventory.discs.size():
		return ""
	var disc: Dictionary = save.inventory.discs[index]
	var result := read_disc(StringName(disc.id), int(disc.level), false)
	if result.begins_with("Learned"):
		save.inventory.discs.remove_at(index)
	return result


## Revive spell: back on its feet with this fraction of max HP.
func revive(fraction: float) -> void:
	health.hp = maxf(health.max_hp * fraction, 1.0)
	status.clear_all()
	set_downed(false)


## The d-pad page: 1 while RT is held, else 0.
func quick_page() -> int:
	return 1 if input.pressed("shift") else 0


## Uses whatever is in a d-pad slot: a consumable, or sets a trap.
func use_quick(index: int) -> bool:
	if save == null:
		return false
	var id := save.quick(index)
	if id == &"":
		combat.combo_feedback.emit("Nothing on %s (Equip tab)" % SaveData.QUICK_NAMES[index])
		return false
	var spell := SpellBook.get_spell(id)
	if spell and spell.is_trap():
		return set_trap(id)
	return use_consumable(id)


## Sets a trap at the Seeker's feet from the d-pad, paying its LP.
func set_trap(id: StringName) -> bool:
	var spell := SpellBook.get_spell(id)
	var c := save.character if save else null
	if spell == null or c == null or not spell.is_trap():
		return false
	if not c.can_use_traps():
		combat.combo_feedback.emit("Only Goluman can set traps")
		return false
	if peaceful:
		combat.combo_feedback.emit("No traps here")
		return false
	var level := c.spell_level(id)
	if level <= 0:
		combat.combo_feedback.emit("%s isn't learned" % spell.display_name)
		return false
	if not status.can_act() or health.is_dead():
		return false
	if not combat.spend_lp(spell.lp_cost(level)):
		combat.combo_feedback.emit("Not enough LP")
		return false
	Trap.place(combat, null, spell, level, false, global_position)
	return true


## Co-op (Part 12): a fallen Seeker stays down where they fell until a partner
## casts Revive (or they press A to go back to the start).
func set_downed(on: bool) -> void:
	downed = on
	input_locked = on
	combat.cancel()
	_visual.rotation.z = PI / 2.0 if on else 0.0
	_visual.position.y = 0.4 if on else 0.0


## The closest Seeker to a point (Part 12: there can be several). Skips
## fallen ones unless `include_down`. null when there's none.
static func nearest(tree_node: Node, at: Vector3, include_down: bool = false) -> Player:
	var best: Player = null
	var best_dist := INF
	for node in Scope.group(tree_node, "player"):
		var seeker := node as Player
		if seeker == null or (not include_down and (seeker.downed or seeker.health.is_dead())):
			continue
		var dist := seeker.global_position.distance_squared_to(at)
		if dist < best_dist:
			best_dist = dist
			best = seeker
	return best


## The node this Seeker's menus are added to.
func ui_root() -> Node:
	if ui_parent and is_instance_valid(ui_parent):
		return ui_parent
	return get_tree().root


## Menus capture or free the mouse only for the keyboard-and-mouse Seeker.
func set_mouse_captured(on: bool) -> void:
	if input.uses_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func grant_invulnerability(seconds: float) -> void:
	_invuln_timer = maxf(_invuln_timer, seconds)


## Closing the game window saves (Part 8).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> void:
	if autosave and save:
		save.loadouts = combat.loadout_set
		save.save()


func gain_exp(amount: int) -> void:
	if save == null or amount <= 0:
		return
	var before := save.character.level()
	save.character.experience += amount
	exp_gained.emit(amount)
	var after := save.character.level()
	if after > before:
		_level_up(before, after)


## Level-up (Part 11): stats grow (apply_bonuses), HP and LP refill like
## Grayson asked, and the HUD shows the gains.
func _level_up(from_level: int, to_level: int) -> void:
	var gains := Leveling.level_up_gains(save.character, from_level, to_level)
	apply_bonuses()
	health.restore_full()
	combat.lp = combat.stats.max_lp
	leveled_up.emit(to_level, gains)


## Puts Lumidium in the satchel, up to satchel_size() carried
## (all colors together). Returns how many fit.
func add_lumidium(color: StringName, amount: int = 1) -> int:
	var n := mini(amount, satchel_room())
	if n > 0:
		carried_lumidium[color] = int(carried_lumidium.get(color, 0)) + n
		item_collected.emit("+%d %s Lumidium" % [n, String(color).capitalize()])
	return n


## Removes carried Lumidium (dropping it). Returns how many were removed.
func remove_lumidium(color: StringName, amount: int) -> int:
	var n := mini(amount, int(carried_lumidium.get(color, 0)))
	if n > 0:
		carried_lumidium[color] = int(carried_lumidium[color]) - n
		if int(carried_lumidium[color]) <= 0:
			carried_lumidium.erase(color)
	return n


## Room left in the satchel for Lumidium.
func satchel_room() -> int:
	return maxi(satchel_size() - carried_lumidium_total(), 0)


## How much Lumidium the satchel holds (15 to start; quests will add more).
func satchel_size() -> int:
	return save.satchel_size if save else Inventory.SATCHEL_LUMIDIUM


func carried_lumidium_total() -> int:
	var total := 0
	for color in carried_lumidium:
		total += int(carried_lumidium[color])
	return total


## Lumidium depot: banks everything carried (up to the bank's limit). Returns
## how much was deposited; anything that didn't fit stays in the satchel.
func deposit_lumidium() -> int:
	var total := save.inventory.bank_lumidium(carried_lumidium)
	if total > 0 and QuestBook.record(save, "bank_lumidium", "", total):
		var level := Scope.level(self)
		if level:
			level.call("quest_done")
	if total > 0:
		save_game()
	return total


## Death: carried Lumidium is lost (North Star §7.1).
func lose_carried() -> int:
	var lost := carried_lumidium_total()
	carried_lumidium.clear()
	return lost


## Quick-use consumables (D-pad / 1-3).
func use_consumable(id: StringName) -> bool:
	if save == null or health.is_dead():
		return false
	if not save.inventory.use_consumable(id):
		combat.combo_feedback.emit("No %s left" % Inventory.CONSUMABLES.get(id, id))
		return false
	match id:
		&"hp_gel":
			health.heal(health.max_hp * 0.3)
		&"lp_cell":
			combat.lp = minf(combat.lp + combat.stats.max_lp * 0.5, combat.stats.max_lp)
		&"cure_salt":
			status.clear_all()
		&"trap_scanner":
			var found := HazardTrap.scan(self)
			combat.combo_feedback.emit("Trap Scanner: %d trap%s found" % [found, "" if found == 1 else "s"])
			return true
	combat.combo_feedback.emit("Used %s" % Inventory.CONSUMABLES.get(id, id))
	return true


func _physics_process(delta: float) -> void:
	var level := Scope.level(self)
	peaceful = level != null and level.get("peaceful") == true
	_recalculate_jump()
	_tick_timers(delta)
	_regen_hp(delta)

	# A is the action button (Grayson, 2026-11-09): next to a teleporter or an
	# item it activates / picks up instead of jumping.
	interact_target = _find_interactable()
	if _input_hold > 0.0:
		# A menu just closed: the button that closed it (B, A) mustn't also
		# dash or jump.
		_input_hold -= delta
	elif input_locked:
		pass
	elif input.just_pressed("jump"):
		if interact_target and is_on_floor() and status.can_move() and not health.is_dead():
			interact_target.interact(self)
			interact_target = null
		else:
			_jump_buffer = jump_buffer_time
	for i in 4:
		if not input_locked and input.just_pressed(&"item_%d" % (i + 1)):
			use_quick(quick_page() * 4 + i)

	var move_dir := _get_move_direction()

	if not input_locked and input.just_pressed("dash") and _can_dash() and status.can_move() and _input_hold <= 0.0:
		combat.cancel()
		_start_dash(move_dir)

	if state == State.DASH:
		_process_dash(delta)
	elif combat.is_attacking() or combat.is_blocking():
		_process_attacking(delta, move_dir)
	else:
		_process_movement(delta, move_dir)

	move_and_slide()
	_update_ground_state()
	_update_facing(delta, move_dir)


# --- Public -----------------------------------------------------------------

func get_lock_target() -> Node3D:
	if camera_rig and is_instance_valid(camera_rig.lock_target):
		return camera_rig.lock_target
	return null


func is_invulnerable() -> bool:
	return _invuln_timer > 0.0


## Every incoming enemy hit goes through here: dash i-frames, the hit roll
## (enemy ATA vs your EVA, Accuracy), blocking / parrying / reflecting
## (CombatController.resolve_incoming), then DEF / RES reduction, Health, and
## status buildup.
func receive_hit(info: DamageInfo, attacker: Node3D, projectile: Node = null) -> float:
	if is_invulnerable():
		combat.combo_feedback.emit("Dodged")
		return 0.0
	var s := combat.stats
	if not Accuracy.roll(info, s.evasion * status.stat_scale(&"evasion"), self, status):
		return 0.0
	var block_scale := combat.resolve_incoming(attacker, projectile)
	if block_scale <= 0.0:
		return 0.0
	info.amount *= block_scale * Defense.scale_for(info.kind, s.defense * status.stat_scale(&"defense"), s.resolve)
	if save:  # armor resistances: the hit's element, and the attacker's monster type
		info.amount *= 1.0 - ArmorBook.resist(save.character, info.damage_type)
		if attacker is Enemy:
			info.amount *= 1.0 - ArmorBook.monster_resist(save.character, (attacker as Enemy).data.enemy_type)
	if combat.aegis_active():
		info.amount *= CombatController.AEGIS_GUARD
	var amount := health.take_damage(info)
	if amount > 0.0:
		status.on_hit()  # a hit ends Stun (Grayson, 2026-11-09)
	status.add_buildup(info, attacker)
	DamageNumber.spawn(get_parent(), global_position + Vector3.UP * 1.9, amount, info.damage_type, false)
	return amount


## Camera-relative stick direction (zero when the stick is centered).
func get_move_input_direction() -> Vector3:
	return _get_move_direction()


## Snap to face a direction (used when an attack starts).
func face_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		rotation.y = atan2(-direction.x, -direction.z)


func get_debug_text() -> String:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	return "State: %s\nSpeed: %.1f m/s   Vertical: %.1f\nAir dashes: %d   Dash cooldown: %.2f\nInvulnerable: %s" % [
		State.keys()[state], horizontal, velocity.y,
		_air_dashes_left, _dash_cooldown_timer, is_invulnerable()]


# --- Movement ---------------------------------------------------------------

func _process_movement(delta: float, move_dir: Vector3, speed_scale: float = 1.0,
		can_jump: bool = true) -> void:
	var on_floor := is_on_floor()

	if can_jump and status.can_move() and _jump_buffer > 0.0 and (on_floor or _coyote_timer > 0.0):
		_do_jump()
		on_floor = false

	if not on_floor:
		var gravity := _gravity_up if velocity.y > 0.0 else _gravity_down
		if velocity.y > 0.0 and not input.pressed("jump"):
			gravity *= jump_cut_gravity_scale
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)

	var speed := move_speed * speed_scale * status.move_scale() \
		* (lock_on_speed_scale if get_lock_target() else 1.0)
	var desired := move_dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if move_dir.length_squared() > 0.0001 else deceleration
	if not on_floor:
		rate *= air_control
	horizontal = horizontal.move_toward(desired, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Mobile attacks and blocking keep walking at a reduced speed; rooted attacks
## only lunge.
func _process_attacking(delta: float, move_dir: Vector3) -> void:
	var scale := combat.get_move_scale()
	if scale > 0.0:
		_process_movement(delta, move_dir, scale, false)
		return
	if not is_on_floor():
		velocity.y = maxf(velocity.y - _gravity_down * delta, -max_fall_speed)
	var lunge := combat.get_lunge_velocity()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if lunge != Vector3.ZERO:
		horizontal = lunge
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, deceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _do_jump() -> void:
	velocity.y = _jump_velocity
	_jump_buffer = 0.0
	_coyote_timer = 0.0
	state = State.AIR
	jumped.emit()
	_squash(Vector3(0.85, 1.2, 0.85))


func _update_ground_state() -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
		_air_dashes_left = air_dash_count
		if state == State.AIR:
			state = State.GROUND
			landed.emit()
			_squash(Vector3(1.15, 0.85, 1.15))
	elif state == State.GROUND:
		state = State.AIR


func _get_move_direction() -> Vector3:
	var stick := input.vector("move_left", "move_right", "move_forward", "move_back")
	if stick == Vector2.ZERO or input_locked:
		return Vector3.ZERO

	var forward := _camera_forward()
	var target := get_lock_target()
	if target:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			forward = to_target.normalized()

	var right := forward.cross(Vector3.UP)
	return right * stick.x + forward * -stick.y


func _camera_forward() -> Vector3:
	if camera_rig:
		return camera_rig.get_flat_forward()
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


func _update_facing(delta: float, move_dir: Vector3) -> void:
	var target := get_lock_target()
	if combat.controls_facing() and target == null:
		return  # The attack aims us (strafe while firing).
	var face := Vector3.ZERO
	if target:
		face = target.global_position - global_position
	elif state == State.DASH:
		face = _dash_direction
	elif move_dir.length_squared() > 0.01:
		face = move_dir
	face.y = 0.0
	if face.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-face.x, -face.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


# --- Dash -------------------------------------------------------------------

## Seconds until the next dash is allowed (0 = ready).
func dash_cooldown_left() -> float:
	return _dash_cooldown_timer


func _can_dash() -> bool:
	if state == State.DASH or _dash_cooldown_timer > 0.0:
		return false
	if not combat.can_dash_cancel():
		return false
	return is_on_floor() or _coyote_timer > 0.0 or _air_dashes_left > 0


func _start_dash(move_dir: Vector3) -> void:
	var dir := move_dir.normalized() if move_dir.length_squared() > 0.01 else _neutral_dash_direction()
	if not (is_on_floor() or _coyote_timer > 0.0):
		_air_dashes_left -= 1
	_dash_direction = dir
	_dash_timer = dash_duration
	_invuln_timer = dash_invuln_time
	state = State.DASH
	dash_started.emit(dir)
	_squash(Vector3(0.9, 0.9, 1.25))


## No stick input: backstep away from a locked target, otherwise dash forward.
func _neutral_dash_direction() -> Vector3:
	var target := get_lock_target()
	if target:
		var away := global_position - target.global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			return away.normalized()
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _process_dash(delta: float) -> void:
	_dash_timer -= delta
	# Dashes ignore gravity, so an air dash holds its height.
	velocity = _dash_direction * (dash_distance / dash_duration)

	# Dash-jump: jumping out of a ground dash keeps some of its momentum.
	if _jump_buffer > 0.0 and is_on_floor():
		_end_dash()
		_do_jump()
		return

	if _dash_timer <= 0.0:
		_end_dash()


func _end_dash() -> void:
	velocity.x *= dash_exit_speed_scale
	velocity.z *= dash_exit_speed_scale
	_dash_cooldown_timer = dash_cooldown
	state = State.GROUND if is_on_floor() else State.AIR
	dash_ended.emit()


# --- Helpers ----------------------------------------------------------------

func _recalculate_jump() -> void:
	# Recomputed every frame so inspector tweaks apply while the game runs.
	_jump_velocity = 2.0 * jump_height / time_to_peak
	_gravity_up = 2.0 * jump_height / (time_to_peak * time_to_peak)
	_gravity_down = 2.0 * jump_height / (time_to_land * time_to_land)


func _tick_timers(delta: float) -> void:
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)


func _squash(amount: Vector3) -> void:
	if _squash_tween:
		_squash_tween.kill()
	_visual.scale = amount
	_squash_tween = create_tween()
	_squash_tween.tween_property(_visual, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
