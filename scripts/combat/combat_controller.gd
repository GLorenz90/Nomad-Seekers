class_name CombatController
extends Node3D
## The Seeker's hands: input, loadouts, timing combos, blocking, powerstance,
## LP and attack execution (North Star §4, §5).
##
## Input: each face button is one hand. By default X is the right hand and Y the
## left (x_is_left swaps them). Tap = Normal
## attack (fires on release), hold past hold_threshold = Hard attack. Holding
## Shift (RT) uses that hand's special (WeaponData.special_attack; none exist
## until Part 5, so it's a normal attack) or, on a casting item, its second spell.
##
## Combo rules:
## - A chain has 3 steps. Any attack from either hand can fill the next step.
## - PSO windows: the chain window opens when the swing ends (PSO's "combo"
##   frame, just after the hit) and closes when the recovery ends (PSO's "full"
##   frame). Chaining cancels the rest of the recovery, exactly like PSO.
## - Timing is judged when the button goes DOWN, so a Hard hold that starts in
##   the window still chains even though it fires hold_threshold later.
## - early_tolerance is an input buffer: a press up to that long before the
##   window opens counts, and the next attack starts the moment the window
##   opens (it never cuts the current swing short). Earlier than that breaks
##   the combo; later than window_close starts a new chain.
## - Each weapon's animation step counts its own consecutive uses: Sword, Pistol,
##   Sword plays the sword's step 1 both times. Committing to one weapon gives its
##   step 2 and 3 attacks and their bonus damage.
## - No-combo weapons and casting items are standalone and end any chain.
##
## Movement (PSU-style): each attack's move_speed_scale decides whether the
## Seeker is rooted (0) or keeps moving at a reduced speed.
##
## Sustained weapons (Dervish Blades): holding the button runs the weapon's
## sustained_attack, hitting every sustained_tick until released.
##
## Loadouts (LB/RB): see Loadout for the one-Heavy and two-handed rules. LT
## depends on the loadout:
## - Shield equipped: full block at the shield's strength, with a parry window
##   when the block starts. The shield's hand button deflects (light, opens a
##   parry) or shoves (heavy, knocks back).
## - Two-handed weapon: weak block (the weapon's block_strength).
## - Anything else: arms-up block (Loadout.ARMS_UP_BLOCK).
## Blocks only stop hits from the front (block_arc_deg). With a shield you can
## keep blocking while you attack, at shield_attack_damage_scale damage.
##
## Target preview (PSU): predict_targets(hand) returns every enemy that hand's
## next attack would hit; TargetMarkers draws both hands at once.
##
## Powerstance: a matching pair (same weapon_type, e.g. Sword + Frost Sword)
## always attacks with both hands, each at TWIN_DAMAGE_SCALE. RT + a hand's
## button uses the special of the weapon in THAT hand while the other hand swings
## normally. Twin casting items cast both spells at once (RT switches the
## pressed hand's spell).
##
## Must be a direct child of the Player.

signal attack_started(hand: int, weapon: WeaponData, attack: AttackData, chain_step: int, hard: bool)
signal combo_feedback(text: String)
signal loadout_changed(index: int)
signal hit_landed(target: Node, info: DamageInfo, amount: float)

enum Hand { LEFT, RIGHT }

const ENEMY_MASK := 4
const MAX_CHAIN := 3
## Streak id for twin (powerstance) attacks, so twins chain into their own steps.
const TWIN := 2
## Each weapon's share of a twin melee/gun attack (two hits = 1.5x total).
## Casting twins cast both spells at full power and full LP.
const TWIN_DAMAGE_SCALE := 0.75
const WEAPON_DIR := "res://data/weapons/"
## Default loadouts as [left hand, right hand]; "" is empty. Two-handed weapons
## go in the right hand, and both buttons use them.
const DEFAULT_LOADOUTS := [
  ["sword", "pistol"], ["shield", "sword"], ["sword", "frost_sword"], ["pistol", "pistol"],
  ["wand", "sword"], ["", "great_sword"], ["", "dervish_blades"], ["", ""]]

@export var stats: Stats
## North Star: the player chooses which face button is which hand.
## Default: X = right hand, Y = left hand.
@export var x_is_left := false
@export var hold_threshold := 0.22
@export var soft_aim_angle_deg := 25.0
@export var soft_aim_range := 25.0
## Melee attacks snap to face an enemy this close (PSO-style auto-turn).
@export var melee_turn_range := 4.0
@export var show_hitboxes := true
## Input buffer: a press up to this long before the chain window opens still
## counts and fires the moment the window opens. 0.15 s is about 4.5 PSO frames.
@export var early_tolerance := 0.15
## Load the player's saved loadouts from user:// on start.
@export var use_saved_loadouts := true

@export_group("Blocking")
## Seconds at the start of a shield block that count as a parry.
@export var parry_window := 0.2
## Blocks only stop hits from inside this arc in front of the Seeker.
@export var block_arc_deg := 140.0
@export_range(0.0, 1.0) var block_move_scale := 0.4
## With a shield you can attack without dropping the block, at this much damage.
@export_range(0.0, 1.0) var shield_attack_damage_scale := 0.66


var lp := 0.0
var loadout_set: LoadoutSet
var loadout_index := 0
## Steps used in the current chain (0 = no chain).
var chain_step := 0


class ActiveAttack:
  var hand := 0
  var weapon: WeaponData
  var attack: AttackData
  var hard := false
  var elapsed := 0.0
  var fired := false
  var hit: Array[Node] = []
  var direction := Vector3.FORWARD
  var target: Node3D
  var sustained := false
  var tick := 0.0
  var releasing := false
  var release_timer := 0.0
  ## Powerstance: the other hand attacks at the same time.
  var twin := false
  var other_weapon: WeaponData
  var other_attack: AttackData


var _current: ActiveAttack
var _chain_expire := 0.0
var _chain_locked := false
var _last_hand := -1
var _last_weapon: WeaponData
var _weapon_streak := 0
var _time := 0.0
var _lp_regen_delay := 0.0
var _held: Array[float] = [-1.0, -1.0]
var _hard_fired: Array[bool] = [false, false]
## Whether each hand's current press landed in the chain window (judged at press).
var _press_chains: Array[bool] = [false, false]
## A buffered chain press waiting for the window to open: [hand, hard, slot, twin, special].
var _queued: Array = []
var _blocking := false
var _block_time := 0.0
var _parry_until := -1.0
var _lt_was_down := false

var _player: Player
var _pivots: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var _tweens: Array[Tween] = [null, null]
var _hitbox_debug: MeshInstance3D
var _hitbox_flash := 0.0
var _spin_tweening := false


func _ready() -> void:
  _player = get_parent() as Player
  if stats == null:
    stats = Stats.new()
  lp = stats.max_lp
  _build_hand(Vector3(-0.5, 1.05, -0.1))
  _build_hand(Vector3(0.5, 1.05, -0.1))
  _build_hitbox_debug()
  if use_saved_loadouts:
    apply_loadout_set(LoadoutSet.load_or_default(make_default_loadouts()))
  else:
    apply_loadout_set(make_default_loadouts())


func _process(delta: float) -> void:
  # Spin the hands around the Seeker while a sustained spin is running.
  if _current and _current.sustained and not _current.releasing:
    rotation.y -= TAU * 2.5 * delta
  elif not _spin_tweening and rotation.y != 0.0:
    rotation.y = 0.0


func _physics_process(delta: float) -> void:
  _time += delta
  _regen_lp(delta)
  _handle_loadout_input()
  for hand in [Hand.LEFT, Hand.RIGHT]:
    _read_hand(hand, delta)
  if _current:
    _update_attack(delta)
  elif chain_step > 0 and _time > _chain_expire:
    chain_step = 0
    _chain_locked = false
  _update_block(delta)
  _update_hitbox_debug()


# --- Loadouts ---------------------------------------------------------------

static func load_weapon(file: String) -> WeaponData:
  if file.is_empty():
    return null
  return load(WEAPON_DIR + file + ".tres")


static func make_default_loadouts() -> LoadoutSet:
  var defaults := LoadoutSet.new()
  for pair in DEFAULT_LOADOUTS:
    defaults.loadouts.append(Loadout.make(load_weapon(pair[0]), load_weapon(pair[1])))
  defaults.ensure_slots()
  return defaults


func apply_loadout_set(new_set: LoadoutSet) -> void:
  loadout_set = new_set
  loadout_set.ensure_slots()
  if not is_usable(loadout_index):
    loadout_index = 0
    for i in loadout_set.loadouts.size():
      if is_usable(i):
        loadout_index = i
        break
  cancel()
  _equip_visuals()
  loadout_changed.emit(loadout_index)


func get_loadout() -> Loadout:
  if loadout_set == null or loadout_set.loadouts.is_empty():
    return null
  return loadout_set.loadouts[loadout_index]


func is_usable(index: int) -> bool:
  var l := loadout_set.loadouts[index]
  return not l.is_empty() and l.validate(loadout_set.double_heavy_augment) == ""


func select_loadout(index: int) -> bool:
  if not is_usable(index):
    return false
  loadout_index = index
  cancel()
  _equip_visuals()
  loadout_changed.emit(loadout_index)
  return true


## LB/RB: next usable loadout, skipping empty ones and ones that break the rules.
func cycle_loadout(step: int) -> void:
  var count := loadout_set.loadouts.size()
  for i in range(1, count + 1):
    var index := posmod(loadout_index + step * i, count)
    if is_usable(index):
      select_loadout(index)
      return


func current_weapon(hand: int) -> WeaponData:
  var l := get_loadout()
  if l == null:
    return null
  var w := l.get_hand(hand)
  if w == null:
    # A two-handed weapon in the other hand covers this button too.
    var other := l.get_hand(1 - hand)
    if other and other.two_handed:
      return other
  return w


func get_lt_mode() -> Loadout.LTMode:
  var l := get_loadout()
  return l.get_lt_mode() if l else Loadout.LTMode.NONE


func is_powerstance() -> bool:
  var l := get_loadout()
  return l != null and l.is_powerstance()


# --- Public state ------------------------------------------------------------

func is_attacking() -> bool:
  return _current != null


func is_blocking() -> bool:
  return _blocking


## 0 while rooted; otherwise the fraction of normal speed the Seeker may move at.
func get_move_scale() -> float:
  if _current:
    return _current.attack.move_speed_scale
  if _blocking:
    return block_move_scale
  return 1.0


## True when combat decides which way the Seeker faces.
func controls_facing() -> bool:
  return _blocking or (_current != null and not _current.attack.face_movement)


## Dashing can cancel an attack once its hit is out.
func can_dash_cancel() -> bool:
  return _current == null or _current.elapsed >= _current.attack.active_end


func cancel() -> void:
  _current = null
  _queued = []
  chain_step = 0
  _chain_locked = false
  _blocking = false
  for hand in [Hand.LEFT, Hand.RIGHT]:
    if hand < _pivots.size():
      _return_to_rest(hand)


## Lunge velocity for the Seeker while a melee attack winds up.
func get_lunge_velocity() -> Vector3:
  if _current == null or _current.attack.is_projectile or _current.attack.move_speed_scale > 0.0:
    return Vector3.ZERO
  var a := _current.attack
  if _current.elapsed >= a.active_end or a.lunge_distance <= 0.0:
    return Vector3.ZERO
  return _current.direction * (a.lunge_distance / maxf(a.active_end, 0.05))


## Called by Player for every incoming hit. Returns the damage multiplier after
## blocking (0 when parried). Blocks and parries only work from the front.
func resolve_incoming(attacker: Node3D, projectile: Node = null) -> float:
  var frontal := true
  if attacker:
    var to := attacker.global_position - _player.global_position
    to.y = 0.0
    var facing := -_player.global_basis.z
    facing.y = 0.0
    if to.length_squared() > 0.0001:
      frontal = facing.angle_to(to.normalized()) <= deg_to_rad(block_arc_deg * 0.5)
  if not frontal:
    return 1.0
  var shield_parry := _blocking and get_lt_mode() == Loadout.LTMode.SHIELD and _block_time <= parry_window
  var magic_shield := _has_reflecting_shield()
  # Magic shields (Ward, Barrier) can't parry melee; they only block it.
  var can_parry := projectile != null or not magic_shield
  if can_parry and (shield_parry or _time < _parry_until):
    if projectile and magic_shield and projectile.has_method("reflect"):
      projectile.reflect(_player, self)
      combo_feedback.emit("Reflected!")
      return 0.0
    combo_feedback.emit("Parry!")
    if projectile == null and attacker and attacker.has_method("on_parried"):
      attacker.on_parried()
    return 0.0
  if _blocking:
    combo_feedback.emit("Blocked")
    return 1.0 - get_loadout().block_strength()
  return 1.0


func _has_reflecting_shield() -> bool:
  var l := get_loadout()
  if l == null:
    return false
  for w in [l.left, l.right]:
    if w and w.is_shield and w.reflects:
      return true
  return false


func button_for(hand: int) -> String:
  return "X" if (hand == Hand.LEFT) == x_is_left else "Y"


func report_hit(target: Node, info: DamageInfo, amount: float) -> void:
  hit_landed.emit(target, info, amount)


func get_lt_text() -> String:
  var l := get_loadout()
  match get_lt_mode():
    Loadout.LTMode.SHIELD:
      return "LT: Shield block %d%% (parry on press)" % roundi(l.block_strength() * 100.0)
    Loadout.LTMode.TWO_HAND:
      return "LT: Two-handed block %d%%" % roundi(l.block_strength() * 100.0)
    Loadout.LTMode.ARMS_UP:
      var text := "LT: Arms-up block %d%%" % roundi(l.block_strength() * 100.0)
      if l.is_powerstance():
        text += "   Powerstance: both hands attack"
      return text
  return "LT: -"


func get_debug_text() -> String:
  var lines := PackedStringArray()
  lines.append("Loadout %d (LB/RB): %s" % [loadout_index + 1, get_loadout().describe()])
  var two_hand := get_loadout().two_handed_weapon()
  if two_hand:
    lines.append("X / Y (both hands): %s" % two_hand.display_name)
  else:
    for hand in [Hand.LEFT, Hand.RIGHT]:
      var w := current_weapon(hand)
      var label := w.display_name if w else "-"
      if w and w.casting:
        label += " [%s / Shift: %s]" % [w.get_spell_name(0), w.get_spell_name(1)]
      lines.append("%s (%s hand): %s" % [button_for(hand), "left" if hand == Hand.LEFT else "right", label])
  lines.append(get_lt_text() + ("  [BLOCKING]" if _blocking else ""))
  if _current:
    lines.append("Attack: %s%s%s  %.2fs  window %.2f-%.2f" % [
      _current.attack.display_name, " (Twin)" if _current.twin else "",
      " (Hard)" if _current.hard else "", _current.elapsed,
      _current.attack.window_open, _current.attack.window_close])
  return "\n".join(lines)


# --- Input ------------------------------------------------------------------

func _action_for(hand: int) -> StringName:
  return &"hand_x" if (hand == Hand.LEFT) == x_is_left else &"hand_y"


func _read_hand(hand: int, delta: float) -> void:
  var action := _action_for(hand)
  if Input.is_action_just_pressed(action):
    _held[hand] = 0.0
    _hard_fired[hand] = false
    _press_chains[hand] = _judge_press()
  elif _held[hand] >= 0.0:
    if Input.is_action_pressed(action):
      _held[hand] += delta
      if not _hard_fired[hand] and _held[hand] >= hold_threshold:
        _hard_fired[hand] = true
        _request_attack(hand, true)
    else:
      if not _hard_fired[hand]:
        _request_attack(hand, false)
      _held[hand] = -1.0


func _handle_loadout_input() -> void:
  if _current:
    return
  if Input.is_action_just_pressed("loadout_next"):
    cycle_loadout(1)
  elif Input.is_action_just_pressed("loadout_prev"):
    cycle_loadout(-1)


# --- Blocking ---------------------------------------------------------------

func _update_block(delta: float) -> void:
  var mode := get_lt_mode()
  var can_block := mode == Loadout.LTMode.SHIELD or mode == Loadout.LTMode.TWO_HAND \
    or mode == Loadout.LTMode.ARMS_UP
  var lt_down := Input.is_action_pressed("block")
  var fresh_press := lt_down and not _lt_was_down
  _lt_was_down = lt_down
  # Shields stay up while you attack; other blocks drop for the attack.
  var keeps_block := mode == Loadout.LTMode.SHIELD
  var wants := can_block and (_current == null or keeps_block) and lt_down
  if wants and not _blocking:
    _blocking = true
    # Only a fresh LT press gets the parry window; resuming after an attack doesn't.
    _block_time = 0.0 if fresh_press else parry_window + 0.01
    _block_pose()
  elif wants:
    _block_time += delta
  elif _blocking:
    _blocking = false
    for hand in [Hand.LEFT, Hand.RIGHT]:
      _return_to_rest(hand)


# --- Combo logic ------------------------------------------------------------

## Called when a hand button goes down: is this press on time for the chain?
## Pressing while an attack is still playing breaks the combo.
func _judge_press() -> bool:
  var chain_open := chain_step > 0 and chain_step < MAX_CHAIN and not _chain_locked
  if _current:
    var cur := _current
    if cur.weapon.no_combo or cur.weapon.casting or cur.sustained:
      return false
    if cur.elapsed < cur.attack.window_open - early_tolerance:
      if chain_open:
        _chain_locked = true
        combo_feedback.emit("Too early!")
      return false
    return chain_open  # in the window, or buffered just before it
  return chain_open and _time <= _chain_expire


func _request_attack(hand: int, hard: bool) -> void:
  var weapon := current_weapon(hand)
  if weapon == null:
    return
  if not _player.status.can_act():
    return  # frozen or shocked
  var twin := is_powerstance()
  var standalone := weapon.no_combo or weapon.casting or (hard and weapon.sustained)
  var special := Input.is_action_pressed("shift")
  var slot := 1 if special else 0
  var on_time := _press_chains[hand] and not _chain_locked and not standalone

  if _current:
    if not on_time:
      return
    if _current.elapsed < _current.attack.window_open:
      # Buffered: start the next step the moment the window opens.
      _queued = [hand, hard, slot, twin, special]
      return
    _resolve_pending_hit(_current)
  _begin(hand, weapon, hard, slot, on_time, twin, special)


func _begin(hand: int, weapon: WeaponData, hard: bool, slot: int, continuing: bool,
    twin: bool, special: bool = false) -> void:
  var streak_id := TWIN if twin else hand
  var next_step := chain_step + 1 if continuing else 1
  var next_streak := 1
  # Same weapon = same hand (or twin again), or one two-handed weapon on either button.
  var same_weapon := streak_id == _last_hand or (weapon.two_handed and weapon == _last_weapon)
  if continuing and same_weapon:
    next_streak = _weapon_streak + 1
  var sustained := hard and weapon.sustained and not twin
  if weapon.no_combo or weapon.casting or sustained:
    next_step = 0
    next_streak = 1

  # The pressed hand may use its special; the other twin hand swings normally.
  var attack := weapon.get_attack(next_streak, hard, slot, special)
  if attack == null:
    return
  var other_weapon: WeaponData = null
  var other_attack: AttackData = null
  var cost := attack.lp_cost
  if twin:
    other_weapon = current_weapon(1 - hand)
    other_attack = other_weapon.get_attack(next_streak, hard, 0, false)
    if other_attack:
      cost += other_attack.lp_cost
  if lp < cost:
    combo_feedback.emit("Not enough LP")
    return

  if not continuing:
    _chain_locked = false
  if get_lt_mode() != Loadout.LTMode.SHIELD:
    _blocking = false
  chain_step = next_step
  _weapon_streak = next_streak
  _last_hand = streak_id
  _last_weapon = weapon
  lp -= cost
  if cost > 0.0:
    _lp_regen_delay = 0.75

  var a := ActiveAttack.new()
  a.hand = hand
  a.weapon = weapon
  a.attack = attack
  a.hard = hard
  a.sustained = sustained
  a.twin = twin and other_attack != null
  a.other_weapon = other_weapon
  a.other_attack = other_attack
  _aim(a)
  _current = a
  _chain_expire = 0.0
  if attack.opens_parry > 0.0:
    _parry_until = _time + attack.opens_parry
  _animate(_holding_hand(hand), attack, sustained)
  if a.twin:
    _animate(1 - hand, other_attack, false)
  if chain_step == MAX_CHAIN and _weapon_streak == MAX_CHAIN:
    combo_feedback.emit("Twin finisher!" if a.twin else "Finisher!")
  attack_started.emit(hand, weapon, attack, chain_step, hard)


func _update_attack(delta: float) -> void:
  var cur := _current
  cur.elapsed += delta
  var a := cur.attack
  if cur.sustained:
    _update_sustained(cur, delta)
    return
  if not _queued.is_empty() and cur.elapsed >= a.window_open:
    var q := _queued
    _queued = []
    _resolve_pending_hit(cur)
    var weapon := current_weapon(q[0])
    if weapon:
      _begin(q[0], weapon, q[1], q[2], true, q[3], q[4])
      return
  if a.is_projectile:
    if not cur.fired and cur.elapsed >= a.active_start:
      cur.fired = true
      _fire_projectiles(cur)
  elif cur.elapsed >= a.active_start and cur.elapsed <= a.active_end:
    _melee_hits(cur)

  if cur.elapsed >= a.duration:
    var standalone := cur.weapon.no_combo or cur.weapon.casting
    if standalone or _chain_locked or chain_step >= MAX_CHAIN:
      chain_step = 0
      _chain_locked = false
      _chain_expire = 0.0
    else:
      # Grace period: the window can stay open a little after the attack ends.
      _chain_expire = _time + maxf(a.window_close - a.duration, 0.0)
    _current = null


## Hits every sustained_tick while the button is held, then winds down for the
## attack's duration after release.
func _update_sustained(cur: ActiveAttack, delta: float) -> void:
  var a := cur.attack
  if not cur.releasing and Input.is_action_pressed(_action_for(cur.hand)):
    cur.tick -= delta
    if cur.tick <= 0.0:
      if a.lp_cost > 0.0 and lp < a.lp_cost:
        combo_feedback.emit("Not enough LP")
        cur.releasing = true
      else:
        lp -= a.lp_cost
        cur.tick = a.sustained_tick
        cur.hit.clear()
        _melee_hits(cur)
        _hitbox_flash = 0.08
    return
  if not cur.releasing:
    cur.releasing = true
    cur.release_timer = a.duration
    _return_to_rest(_holding_hand(cur.hand))
  cur.release_timer -= delta
  if cur.release_timer <= 0.0:
    chain_step = 0
    _current = null


# --- Aim, hits, damage ------------------------------------------------------

## PSO windows can open on the same frame the hit comes out. Make sure an
## attack that's being chained out of still lands its hit or fires its shot.
func _resolve_pending_hit(cur: ActiveAttack) -> void:
  if cur.elapsed < cur.attack.active_start:
    return
  if cur.attack.is_projectile:
    if not cur.fired:
      cur.fired = true
      _fire_projectiles(cur)
  else:
    _melee_hits(cur)


func _aim(a: ActiveAttack) -> void:
  var aim := _choose_aim(a.attack)
  a.target = aim[0]
  a.direction = aim[1]
  _player.face_direction(a.direction)


## [target or null, flat direction] an attack would aim at right now.
func _choose_aim(attack: AttackData) -> Array:
  var target := _player.get_lock_target()
  if target == null:
    if attack.is_projectile:
      target = _find_soft_target(soft_aim_range, soft_aim_angle_deg)
    else:
      target = _find_soft_target(melee_turn_range, 80.0)

  var dir := -_player.global_basis.z
  if target:
    dir = target.global_position - _player.global_position
  elif attack.move_speed_scale > 0.0:
    # Mobile attack with nothing to aim at: fire where the stick points.
    var move := _player.get_move_input_direction()
    if move.length_squared() > 0.04:
      dir = move
  dir.y = 0.0
  if dir.length_squared() < 0.0001:
    dir = -_player.global_basis.z
    dir.y = 0.0
  return [target, dir.normalized()]


# --- Target preview (PSU target cursor) ---------------------------------------

## Every enemy the given hand's next attack would hit, as things stand now.
func predict_targets(hand: int) -> Array[Node3D]:
  var weapon := current_weapon(hand)
  if weapon == null or weapon.is_shield:
    return []
  var special := Input.is_action_pressed("shift")
  var attack: AttackData
  if _current and _current.sustained:
    attack = _current.attack
  else:
    attack = weapon.get_attack(_predicted_step(hand), false, 1 if special else 0, special)
  if attack == null:
    return []
  var aim := _choose_aim(attack)
  if attack.is_projectile:
    return _predict_projectile(attack, aim[0], aim[1])
  return _predict_melee(attack, aim[1])


func _predicted_step(hand: int) -> int:
  var streak_id := TWIN if is_powerstance() else hand
  var chaining := chain_step > 0 and chain_step < MAX_CHAIN and not _chain_locked \
    and (_current != null or _time <= _chain_expire)
  if chaining and streak_id == _last_hand:
    return mini(_weapon_streak + 1, MAX_CHAIN)
  return 1


func _predict_melee(attack: AttackData, dir: Vector3) -> Array[Node3D]:
  var found: Array[Node3D] = []
  var shape := BoxShape3D.new()
  shape.size = attack.hitbox_size
  var params := PhysicsShapeQueryParameters3D.new()
  params.shape = shape
  var xform := _hitbox_transform_for(attack, dir)
  if attack.move_speed_scale <= 0.0:
    xform.origin += dir * attack.lunge_distance  # rooted swings lunge forward first
  params.transform = xform
  params.collision_mask = ENEMY_MASK
  for result in get_world_3d().direct_space_state.intersect_shape(params, 16):
    var body := result.collider as Node3D
    var health := Health.find(body)
    if body and health and not health.is_dead() and not body in found:
      found.append(body)
  return found


## Shots hit the first enemy along the aim line; piercing shots hit every one.
func _predict_projectile(attack: AttackData, target: Node3D, dir: Vector3) -> Array[Node3D]:
  var origin := _player.global_position + Vector3.UP * 1.1
  var aim := dir
  if target:
    aim = (CameraRig.get_lock_point(target) - origin).normalized()
  var found: Array[Node3D] = []
  var first: Node3D = null
  var first_distance := INF
  var space := get_world_3d().direct_space_state
  for node in get_tree().get_nodes_in_group("lockable"):
    var n := node as Node3D
    if n == null or not n.is_visible_in_tree():
      continue
    var rel := CameraRig.get_lock_point(n) - origin
    var along := rel.dot(aim)
    if along < 0.0 or along > attack.projectile_range:
      continue
    if (rel - aim * along).length() > attack.projectile_radius + 0.5:
      continue
    var los := PhysicsRayQueryParameters3D.create(origin, origin + rel, 1, [_player.get_rid()])
    if not space.intersect_ray(los).is_empty():
      continue
    if attack.projectile_pierce:
      found.append(n)
    elif along < first_distance:
      first_distance = along
      first = n
  if first:
    found.append(first)
  return found


func _find_soft_target(max_range: float, max_angle_deg: float) -> Node3D:
  var origin := _player.global_position
  var forward := -_player.global_basis.z
  forward.y = 0.0
  forward = forward.normalized()
  var best: Node3D = null
  var best_score := INF
  for node in get_tree().get_nodes_in_group("lockable"):
    var n := node as Node3D
    if n == null or not n.is_visible_in_tree():
      continue
    var to := n.global_position - origin
    to.y = 0.0
    var dist := to.length()
    if dist > max_range or dist < 0.01:
      continue
    var angle := rad_to_deg(forward.angle_to(to / dist))
    if angle > max_angle_deg:
      continue
    var score := angle / max_angle_deg + dist / max_range
    if score < best_score:
      best_score = score
      best = n
  return best


func _make_damage(weapon: WeaponData, attack: AttackData, hard: bool, scale: float) -> DamageInfo:
  var info := DamageInfo.new()
  var stat := stats.attack_stat(weapon.weapon_class)
  info.amount = weapon.base_damage * attack.damage_mult * (1.0 + stat / 100.0) * scale
  if _blocking:
    info.amount *= shield_attack_damage_scale
  info.damage_type = attack.damage_type if attack.override_damage_type else weapon.damage_type
  info.kind = DamageInfo.kind_for(weapon.weapon_class)
  info.status_power = attack.status_power
  info.is_hard = hard
  if randf() < stats.crit_chance():
    info.is_crit = true
    info.amount *= 1.5
  info.source = _player
  return info


## [weapon, attack, damage scale] for each hand taking part in this attack.
func _strikes(cur: ActiveAttack) -> Array:
  if not cur.twin:
    return [[cur.weapon, cur.attack, 1.0, cur.hand]]
  var scale := 1.0 if cur.weapon.casting else TWIN_DAMAGE_SCALE
  return [[cur.weapon, cur.attack, scale, cur.hand],
    [cur.other_weapon, cur.other_attack, scale, 1 - cur.hand]]


func _hitbox_transform(cur: ActiveAttack) -> Transform3D:
  return _hitbox_transform_for(cur.attack, cur.direction)


func _hitbox_transform_for(attack: AttackData, dir: Vector3) -> Transform3D:
  var origin := _player.global_position + Vector3.UP * 1.0 + dir * attack.reach
  return Transform3D(Basis.looking_at(dir), origin)


func _melee_hits(cur: ActiveAttack) -> void:
  var shape := BoxShape3D.new()
  shape.size = cur.attack.hitbox_size
  var params := PhysicsShapeQueryParameters3D.new()
  params.shape = shape
  params.transform = _hitbox_transform(cur)
  params.collision_mask = ENEMY_MASK
  for result in get_world_3d().direct_space_state.intersect_shape(params, 16):
    var body: Node = result.collider
    if body in cur.hit:
      continue
    cur.hit.append(body)
    var health := Health.find(body)
    if health == null or health.is_dead():
      continue
    for strike in _strikes(cur):
      var info := _make_damage(strike[0], strike[1], cur.hard, strike[2])
      info.hit_position = (body as Node3D).global_position + Vector3.UP * 1.2
      report_hit(body, info, HitResolver.apply(body, info, _player))
    if cur.attack.knockback > 0.0 and body.has_method("apply_knockback"):
      body.apply_knockback(cur.direction * cur.attack.knockback)


func _fire_projectiles(cur: ActiveAttack) -> void:
  for strike in _strikes(cur):
    var attack: AttackData = strike[1]
    if not attack.is_projectile:
      continue
    var muzzle := _pivots[_holding_hand(strike[3])].global_position + cur.direction * 0.6
    var aim := cur.direction
    if is_instance_valid(cur.target):
      aim = (CameraRig.get_lock_point(cur.target) - muzzle).normalized()
    var info := _make_damage(strike[0], attack, cur.hard, strike[2])
    var color := Element.color_of(info.damage_type)
    if info.damage_type == Element.Type.GENERIC:
      color = Color(1.0, 0.85, 0.5)
    Projectile.spawn(_player.get_parent(), muzzle, aim, attack, info, color, _player, self)


func _regen_lp(delta: float) -> void:
  if _lp_regen_delay > 0.0:
    _lp_regen_delay -= delta
    return
  lp = minf(lp + stats.lp_regen_per_second * delta, stats.max_lp)


# --- Placeholder visuals ----------------------------------------------------

func _build_hand(shoulder: Vector3) -> void:
  var pivot := Node3D.new()
  pivot.position = shoulder
  add_child(pivot)
  var mesh := MeshInstance3D.new()
  pivot.add_child(mesh)
  _pivots.append(pivot)
  _meshes.append(mesh)


## The hand that visibly holds the weapon used by this button. A two-handed
## weapon is one item, always held in the right hand; both buttons use it.
func _holding_hand(hand: int) -> int:
  var l := get_loadout()
  if l and l.two_handed_weapon():
    return Hand.RIGHT
  return hand


## What each hand visibly holds (a two-handed weapon shows in the right hand only).
func _held_weapon(hand: int) -> WeaponData:
  var l := get_loadout()
  if l == null:
    return null
  var two_hand := l.two_handed_weapon()
  if two_hand:
    return two_hand if hand == Hand.RIGHT else null
  return l.get_hand(hand)


func _equip_visuals() -> void:
  rotation.y = 0.0
  for hand in [Hand.LEFT, Hand.RIGHT]:
    var w := _held_weapon(hand)
    var mesh_instance := _meshes[hand]
    if w == null:
      mesh_instance.mesh = null
      continue
    var box := BoxMesh.new()
    box.size = w.mesh_size
    var mat := StandardMaterial3D.new()
    mat.albedo_color = w.mesh_color
    mat.metallic = 0.4
    mat.roughness = 0.4
    box.material = mat
    mesh_instance.mesh = box
    mesh_instance.position = Vector3(0.0, 0.0, -(w.mesh_size.z * 0.5 + 0.05))
    _return_to_rest(hand)


func _rest_pose(hand: int) -> Vector3:
  var w := current_weapon(hand)
  if w and w.is_shield:
    return Vector3(-0.3, 0.6 if hand == Hand.LEFT else -0.6, 0.0)
  if w and w.weapon_class == WeaponData.WeaponClass.MELEE:
    return Vector3(-0.6, 0.0, 0.0)
  return Vector3(-0.2, 0.0, 0.0)


func _return_to_rest(hand: int) -> void:
  if _tweens[hand]:
    _tweens[hand].kill()
  _pivots[hand].rotation = _rest_pose(hand)
  _pivots[hand].position.z = -0.1


## Shields come up square in front; other weapons are raised crosswise.
func _block_pose() -> void:
  for hand in [Hand.LEFT, Hand.RIGHT]:
    if _tweens[hand]:
      _tweens[hand].kill()
    var w := _held_weapon(hand)
    if w == null:
      continue
    if w.two_handed:
      _pivots[hand].rotation = Vector3(0.9, 0.0, 0.3)  # held across the body
    elif w.is_shield:
      _pivots[hand].rotation = Vector3.ZERO
      _pivots[hand].position.z = -0.25
    else:
      _pivots[hand].rotation = Vector3(0.9, 0.5 if hand == Hand.LEFT else -0.5, 0.0)


func _animate(hand: int, a: AttackData, sustained: bool = false) -> void:
  var pivot := _pivots[hand]
  if _tweens[hand]:
    _tweens[hand].kill()
  pivot.position.z = -0.1
  var start := Vector3.ZERO
  var finish := Vector3.ZERO
  match a.swing:
    AttackData.Swing.SLASH_RIGHT:
      start = Vector3(-0.1, -1.4, 0.0)
      finish = Vector3(-0.3, 1.4, 0.0)
    AttackData.Swing.SLASH_LEFT:
      start = Vector3(-0.1, 1.4, 0.0)
      finish = Vector3(-0.3, -1.4, 0.0)
    AttackData.Swing.OVERHEAD:
      start = Vector3(1.6, 0.0, 0.0)
      finish = Vector3(-0.9, 0.0, 0.0)
    AttackData.Swing.THRUST:
      start = Vector3(0.0, 0.0, 0.0)
      finish = Vector3(0.0, 0.0, 0.0)
    AttackData.Swing.SHOT:
      start = Vector3(0.0, 0.0, 0.0)
      finish = Vector3(0.4, 0.0, 0.0)
    AttackData.Swing.CAST:
      start = Vector3(0.3, 0.0, 0.0)
      finish = Vector3(0.1, 0.0, 0.0)
    AttackData.Swing.SPIN:
      # Arms out, then the whole Combat node spins once around the Seeker.
      start = Vector3(-0.1, 0.0, 0.0)
      finish = Vector3(-0.1, 0.0, 0.0)
      if not sustained:
        _spin_once(a)

  if sustained:
    pivot.rotation = start  # arms out for the whole spin
    return

  var windup := maxf(a.active_start, 0.03)
  var active := maxf(a.active_end - a.active_start, 0.05)
  var recover := maxf(a.duration - a.active_end, 0.05)
  var tween := create_tween()
  tween.tween_property(pivot, "rotation", start, windup)
  if a.swing == AttackData.Swing.THRUST:
    tween.tween_property(pivot, "position:z", -0.8, active)
    tween.tween_property(pivot, "position:z", -0.1, recover * 0.5)
  else:
    tween.tween_property(pivot, "rotation", finish, active)
  tween.tween_property(pivot, "rotation", _rest_pose(hand), recover)
  _tweens[hand] = tween


func _spin_once(a: AttackData) -> void:
  _spin_tweening = true
  rotation.y = 0.0
  var spin := create_tween()
  spin.tween_interval(maxf(a.active_start - 0.03, 0.0))
  spin.tween_property(self, "rotation:y", -TAU, maxf(a.active_end - a.active_start, 0.1) + 0.06)
  spin.tween_callback(func():
    rotation.y = 0.0
    _spin_tweening = false)


func _build_hitbox_debug() -> void:
  _hitbox_debug = MeshInstance3D.new()
  _hitbox_debug.top_level = true
  _hitbox_debug.visible = false
  _hitbox_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var mat := StandardMaterial3D.new()
  mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  mat.albedo_color = Color(1.0, 0.3, 0.2, 0.25)
  mat.cull_mode = BaseMaterial3D.CULL_DISABLED
  var box := BoxMesh.new()
  box.material = mat
  _hitbox_debug.mesh = box
  add_child(_hitbox_debug)


func _update_hitbox_debug() -> void:
  _hitbox_flash = maxf(_hitbox_flash - get_physics_process_delta_time(), 0.0)
  var live := show_hitboxes and _current != null and not _current.attack.is_projectile \
    and ((_current.sustained and _hitbox_flash > 0.0) or (not _current.sustained
      and _current.elapsed >= _current.attack.active_start
      and _current.elapsed <= _current.attack.active_end))
  _hitbox_debug.visible = live
  if live:
    (_hitbox_debug.mesh as BoxMesh).size = _current.attack.hitbox_size
    _hitbox_debug.global_transform = _hitbox_transform(_current)
