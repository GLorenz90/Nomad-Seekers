class_name CombatController
extends Node3D
## The Seeker's hands: input, loadouts, timing combos, blocking, powerstance,
## LP and attack execution (North Star §4, §5).
##
## Input: each face button is one hand. X is the **primary hand** and Y the
## **off hand** (Grayson, 2026-11-09): Hand.PRIMARY / Hand.OFF, and
## Loadout.primary / .off_hand. Which side of the body the primary hand is on
## comes from the character's handedness (left_handed); it only changes where
## weapons are drawn. (swap_hand_buttons puts X on the off hand; only older
## tests use it.) Tap = Normal
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
## Jobs (Part 5): job_code ("S", "R" or "I") is the Seeker's job; loadouts
## holding a weapon the job can't use are skipped like broken ones.
##
## Weapon tags (Part 5): RT + a hand fires the weapon's special, built from its
## tag (SpecialTag). Tag effects (instant kill, drain, LP/EXP steal, HP cut)
## apply in report_hit; Charge-line costs are paid when the special starts.
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

enum Hand { OFF, PRIMARY }

const ENEMY_MASK := 4
const PLAYER_MASK := 2
const MAX_CHAIN := 3
## Streak id for twin (powerstance) attacks, so twins chain into their own steps.
const TWIN := 2
## Each weapon's share of a twin melee/gun attack (two hits = 1.5x total).
## Casting twins cast both spells at full power and full LP.
const TWIN_DAMAGE_SCALE := 0.75
## Homing throws hop to the next enemy within this distance of the last one.
const LOCK_CHAIN_HOP := 9.0
## Aegis Pulse (Sync Burst): damage dealt x AEGIS_POWER, taken x AEGIS_GUARD.
const AEGIS_POWER := 1.3
const AEGIS_GUARD := 0.7
## Shots start this high on the Seeker, and this fraction of the way out
## toward the firing hand (0 = dead centre).
const MUZZLE_HEIGHT := 1.1
const MUZZLE_SIDE_SCALE := 0.3
## A straight shot never leaves more than this many degrees (left or right)
## from the direction the Seeker faces.
const MAX_AIM_YAW := 8.0
## PSO-shotgun targeting picks enemies within this half-angle of the aim.
const MULTI_TARGET_CONE := 50.0
## Heal and Cure reach every Seeker this close to the caster.
const SUPPORT_RANGE := 10.0
const STAT_FOR_CLASS := {
  WeaponData.WeaponClass.MELEE: &"strength",
  WeaponData.WeaponClass.RANGED: &"dexterity",
  WeaponData.WeaponClass.MAGIC: &"soul",
}
const WEAPON_DIR := "res://data/weapons/"
## Default loadouts as [primary hand, off hand]; "" is empty. Two-handed
## weapons go in the primary hand, and both buttons use them.
const DEFAULT_LOADOUTS := [
  ["pistol", "sword"], ["sword", "shield"], ["frost_sword", "sword"], ["pistol", "pistol"],
  ["sword", "wand"], ["great_sword", ""], ["dervish_blades", ""], ["", ""]]

@export var stats: Stats
## X = primary hand, Y = off hand. On: X = off hand (older tests).
@export var swap_hand_buttons := false
## Left-handed characters hold the primary weapon on their left side.
var left_handed := false

## "Primary" / "Off hand" for menus and messages.
static func hand_name(hand: int) -> String:
  return "Primary" if hand == Hand.PRIMARY else "Off hand"


## Puts the primary hand on the character's left or right (visual only).
func set_left_handed(on: bool) -> void:
  left_handed = on
  if _pivots.size() == 2:
    var side := -1.0 if on else 1.0
    _pivots[Hand.PRIMARY].position.x = 0.5 * side
    _pivots[Hand.OFF].position.x = -0.5 * side
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
## The Seeker's job letter: "S" Striker, "R" Ranger, "I" Invoker.
var job_code := "S"
## Pays Charge-line specials in Oro. Set by the Player.
var inventory: Inventory
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
  ## The pressed hand used its RT special (tag effects apply).
  var special := false


var _current: ActiveAttack
var _chain_expire := 0.0
var _chain_locked := false
var _last_hand := -1
var _last_weapon: WeaponData
var _weapon_streak := 0
var _time := 0.0
var _lp_regen_delay := 0.0
## Testing (Levels tab): LP never runs out.
var infinite_lp := false
## Racial LP regen: this fraction of max LP per second (Player.apply_bonuses
## sets it from CharacterData.lp_regen_fraction()).
var lp_regen_fraction := 0.0
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
var _aegis_until := -1.0
## Weapon hits landed in the current combo (Accuracy streak bonus).
var _hit_streak := 0

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
  # The Player swaps in the saved loadouts (SaveData) when use_saved_loadouts is on.
  apply_loadout_set(make_default_loadouts())


func _process(delta: float) -> void:
  # Spin the hands around the Seeker while a sustained spin is running.
  if _current and _current.sustained and not _current.releasing and not _current.attack.is_projectile:
    rotation.y -= TAU * 2.5 * delta
  elif not _spin_tweening and rotation.y != 0.0:
    rotation.y = 0.0


func _physics_process(delta: float) -> void:
  _time += delta
  _regen_lp(delta)
  _handle_loadout_input()
  for hand in [Hand.OFF, Hand.PRIMARY]:
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
  # The starter Wand (loadout 5, off hand) holds a new Seeker's first spells.
  defaults.loadouts[4].set_spell(0, 0, &"fajro")
  defaults.loadouts[4].set_spell(0, 1, &"glacio")
  return defaults


## A new character's palette (Grayson, 2026-11-09): only loadout 1 is
## filled, with the Pistol (X) and Sword (Y); the rest start empty.
static func make_starter_loadouts() -> LoadoutSet:
  var starter := LoadoutSet.new()
  starter.loadouts.append(Loadout.make(load_weapon(DEFAULT_LOADOUTS[0][0]), load_weapon(DEFAULT_LOADOUTS[0][1])))
  starter.ensure_slots()
  return starter


func apply_loadout_set(new_set: LoadoutSet) -> void:
  loadout_set = new_set
  loadout_set.ensure_slots()
  loadout_index = clampi(loadout_set.current, 0, loadout_set.loadouts.size() - 1)
  if not is_usable(loadout_index):
    loadout_index = 0
    for i in loadout_set.loadouts.size():
      if is_usable(i):
        loadout_index = i
        break
  loadout_set.current = loadout_index
  cancel()
  _equip_visuals()
  loadout_changed.emit(loadout_index)


func get_loadout() -> Loadout:
  if loadout_set == null or loadout_set.loadouts.is_empty():
    return null
  return loadout_set.loadouts[loadout_index]


func is_usable(index: int) -> bool:
  var l := loadout_set.loadouts[index]
  return not l.is_empty() and l.validate(loadout_set.double_heavy_augment) == "" \
    and job_error(l) == ""


## "" when the current job can use every weapon in the loadout.
func job_error(l: Loadout) -> String:
  for w: WeaponData in [l.off_hand, l.primary]:
    if w and not w.can_be_used_by(job_code):
      return "%s needs %s" % [w.display_name, w.jobs_text()]
  return ""


func set_job(code: String) -> void:
  job_code = code
  if loadout_set:
    apply_loadout_set(loadout_set)


## The attack for the spell in this hand's slot (Part 6), or null with a
## message when the slot is empty, the spell isn't learned, or the Seeker
## can't use it (Goluman can't cast; only Goluman set traps).
func _spell_attack(hand: int, slot: int, hard: bool, speak: bool) -> AttackData:
  var holder := _holding_hand(hand)
  var item := get_loadout().get_hand(holder)
  var id := get_loadout().get_spell(holder, slot)
  var character := _player.save.character if _player and _player.save else null
  var spell := SpellBook.get_spell(id) if id != &"" else null
  var problem := ""
  if spell == null:
    problem = "No spell in this slot (menu > Spells)"
  elif character == null or character.spell_level(id) <= 0:
    problem = "%s isn't learned" % spell.display_name
  elif spell.is_trap() and not character.can_use_traps():
    problem = "Only Goluman can set traps"
  elif not spell.is_trap() and not character.can_use_magic():
    problem = "Goluman can't use magic"
  if problem != "":
    if speak:
      combo_feedback.emit(problem)
    return null
  return SpellCaster.make_attack(spell, character.spell_level(id), hard, item)


## Which spell a casting item uses: slot 0/1 with two spells (RT = the second);
## a 4-spell item (Staff) gives X and Y one each, and RT + X / RT + Y two more.
func spell_slot(weapon: WeaponData, hand: int, special: bool) -> int:
  if weapon and weapon.casting and weapon.two_handed:
    var button := 0 if button_for(hand) == "X" else 1
    return button + (2 if special else 0)
  return 1 if special else 0


func select_loadout(index: int) -> bool:
  if not is_usable(index):
    return false
  loadout_index = index
  loadout_set.current = index  # remembered across maps
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
  for hand in [Hand.OFF, Hand.PRIMARY]:
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
  for w in [l.off_hand, l.primary]:
    if w and w.is_shield and w.reflects:
      return true
  return false


func button_for(hand: int) -> String:
  return "X" if (hand == Hand.OFF) == swap_hand_buttons else "Y"


func apply_aegis(seconds: float) -> void:
  _aegis_until = maxf(_aegis_until, _time + seconds)


func aegis_active() -> bool:
  return _time < _aegis_until


func aegis_time_left() -> float:
  return maxf(_aegis_until - _time, 0.0)


## Buff / debuff multiplier on one of the Seeker's stats.
func _stat_scale(stat: StringName) -> float:
  return _player.status.stat_scale(stat) if _player and _player.status else 1.0


func report_hit(target: Node, info: DamageInfo, amount: float) -> void:
  if amount > 0.0 and not info.missed and info.accuracy >= 0.0:
    _hit_streak += 1  # Chrono Cross ramp: each landed hit helps the next
  if info.special and info.weapon and info.weapon.tag and amount > 0.0 and not info.missed:
    _apply_tag_effect(target, info, amount)
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
    for hand in [Hand.OFF, Hand.PRIMARY]:
      var w := current_weapon(hand)
      var label := w.display_name if w else "-"
      if w and w.casting:
        label += " [%s / Shift: %s]" % [spell_name_in(hand, spell_slot(w, hand, false)),
          spell_name_in(hand, spell_slot(w, hand, true))]
      lines.append("%s (%s): %s" % [button_for(hand), hand_name(hand).to_lower(), label])
  lines.append(get_lt_text() + ("  [BLOCKING]" if _blocking else ""))
  if _current:
    lines.append("Attack: %s%s%s  %.2fs  window %.2f-%.2f" % [
      _current.attack.display_name, " (Twin)" if _current.twin else "",
      " (Hard)" if _current.hard else "", _current.elapsed,
      _current.attack.window_open, _current.attack.window_close])
  return "\n".join(lines)


# --- Input ------------------------------------------------------------------

func _action_for(hand: int) -> StringName:
  return &"hand_x" if (hand == Hand.OFF) == swap_hand_buttons else &"hand_y"


func _read_hand(hand: int, delta: float) -> void:
  # Menu open (Part 11: it doesn't pause), or a peaceful map like Nomad-2
  # (Grayson, 2026-11-10: no attacks, spells or traps in the hub).
  if _player and (_player.input_locked or _player.peaceful):
    _held[hand] = -1.0
    return
  var action := _action_for(hand)
  if _in().just_pressed(action):
    _held[hand] = 0.0
    _hard_fired[hand] = false
    _press_chains[hand] = _judge_press()
  elif _held[hand] >= 0.0:
    if _in().pressed(action):
      _held[hand] += delta
      if not _hard_fired[hand] and _held[hand] >= hold_threshold:
        _hard_fired[hand] = true
        _request_attack(hand, true)
    else:
      if not _hard_fired[hand]:
        _request_attack(hand, false)
      _held[hand] = -1.0


func _handle_loadout_input() -> void:
  if _current or (_player and _player.input_locked):
    return
  if _in().just_pressed("loadout_next"):
    cycle_loadout(1)
  elif _in().just_pressed("loadout_prev"):
    cycle_loadout(-1)


# --- Blocking ---------------------------------------------------------------

func _update_block(delta: float) -> void:
  var mode := get_lt_mode()
  var can_block := mode == Loadout.LTMode.SHIELD or mode == Loadout.LTMode.TWO_HAND \
    or mode == Loadout.LTMode.ARMS_UP
  var lt_down := _in().pressed("block") and not (_player and _player.input_locked)
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
    for hand in [Hand.OFF, Hand.PRIMARY]:
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
  var special := _in().pressed("shift")
  var slot := spell_slot(weapon, hand, special)
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
  if weapon.no_combo or weapon.casting or (hard and weapon.sustained):
    next_step = 0
    next_streak = 1

  # The pressed hand may use its special; the other twin hand swings normally.
  var locked := _player.get_lock_target() != null  # Gunblade: gun while locked on
  var attack: AttackData
  if weapon.casting:
    attack = _spell_attack(hand, slot, hard, true)
  else:
    attack = weapon.get_attack(next_streak, hard, slot, special, locked)
  if attack == null:
    return
  # Held: sustained weapons, and Sustained spells, keep going while the button is down.
  # Twin sustained works too (two Machine Pistols both fire while held).
  var sustained := hard and (weapon.sustained or attack.channel)
  var other_weapon: WeaponData = null
  var other_attack: AttackData = null
  var cost := attack.lp_cost
  if twin:
    other_weapon = current_weapon(1 - hand)
    if other_weapon.casting:
      other_attack = _spell_attack(1 - hand, slot, hard, false)
    else:
      other_attack = other_weapon.get_attack(next_streak, hard, 0, false, locked)
    if other_attack:
      cost += other_attack.lp_cost
  var uses_special := special and not weapon.casting and weapon.get_special() != null
  var charge := _charge_cost(weapon) if uses_special else ""
  if charge == "lp":
    cost += SpecialTag.CHARGE_LP
  if lp < cost:
    combo_feedback.emit("Not enough LP")
    return
  if charge == "oro":
    if inventory == null or inventory.oro < SpecialTag.CHARGE_ORO:
      combo_feedback.emit("Not enough Oro")
      return
    inventory.oro -= SpecialTag.CHARGE_ORO
  elif charge == "hp":
    var hp_cost := _player.health.max_hp * SpecialTag.CHARGE_HP_FRACTION
    if _player.health.hp <= hp_cost:
      combo_feedback.emit("Not enough HP")
      return
    _player.health.hp -= hp_cost

  if not continuing:
    _chain_locked = false
  if get_lt_mode() != Loadout.LTMode.SHIELD:
    _blocking = false
  if next_step == 1:
    _hit_streak = 0  # a new combo starts its accuracy ramp over
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
  a.special = uses_special
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
  if a.spell:
    if not cur.fired and cur.elapsed >= a.active_start:
      cur.fired = true
      for strike in _strikes(cur):
        var strike_attack: AttackData = strike[1]
        if strike_attack and strike_attack.spell:
          SpellCaster.cast(self, strike[0], strike_attack, cur.hard, cur.target, cur.direction)
  elif a.support != AttackData.Support.NONE:
    if not cur.fired and cur.elapsed >= a.active_start:
      cur.fired = true
      _cast_support(cur)
  elif a.is_projectile:
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
  if not cur.releasing and _in().pressed(_action_for(cur.hand)):
    cur.tick -= delta
    if cur.tick <= 0.0:
      var tick_cost := a.lp_cost + (cur.other_attack.lp_cost if cur.twin and cur.other_attack else 0.0)
      if tick_cost > 0.0 and lp < tick_cost:
        combo_feedback.emit("Not enough LP")
        cur.releasing = true
      else:
        lp -= tick_cost
        cur.tick = a.sustained_tick
        if a.lp_cost > 0.0:
          _lp_regen_delay = 0.75
        if a.spell:
          _aim(cur)
          for strike in _strikes(cur):
            var strike_attack: AttackData = strike[1]
            if strike_attack and strike_attack.spell:
              SpellCaster.channel_tick(self, strike[0], strike_attack, true, cur.direction)
        elif a.is_projectile:
          _aim(cur)  # automatic fire tracks the target while held
          _fire_projectiles(cur)
        else:
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
  if cur.elapsed < cur.attack.active_start or cur.attack.support != AttackData.Support.NONE:
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
  var special := _in().pressed("shift")
  var attack: AttackData
  if _current and _current.sustained:
    attack = _current.attack
  elif weapon.casting:
    attack = _spell_attack(hand, spell_slot(weapon, hand, special), false, false)
  else:
    attack = weapon.get_attack(_predicted_step(hand), false, spell_slot(weapon, hand, special), special,
      _player.get_lock_target() != null)
  if attack == null or attack.support != AttackData.Support.NONE:
    return []
  if attack.spell:
    return _predict_spell(attack, hand)
  var aim := _choose_aim(attack)
  var hits: Array[Node3D]
  if attack.is_projectile:
    hits = _predict_projectile(attack, aim[0], aim[1])
  else:
    hits = _predict_melee(attack, aim[1])
  # A burst special also marks who the burst would reach.
  if special and weapon.tag and weapon.tag.effect == SpecialTag.Effect.BURST:
    for t in hits.duplicate():
      for extra in burst_targets(t):
        if not extra in hits:
          hits.append(extra)
  return hits


## Spells: who the cast would hit, using the same target rules as SpellCaster.
func _predict_spell(attack: AttackData, _hand: int) -> Array[Node3D]:
  var spell := attack.spell
  var aim := _choose_aim(attack)
  var target: Node3D = aim[0]
  var dir: Vector3 = aim[1]
  var level := attack.spell_level
  var r := spell.radius + spell.radius_growth * (level - 1)
  match spell.shape:
    SpellDef.Shape.SKY_STRIKE, SpellDef.Shape.HOMING_ORB:
      var t := target if target else SpellCaster._nearest_ahead(_player, dir, spell.reach, 60.0)
      return [t] if t else []
    SpellDef.Shape.CHAIN:
      var first := target if target else SpellCaster._nearest_ahead(_player, dir, spell.reach, 60.0)
      if first == null:
        return []
      var chain: Array[Node3D] = [first]
      while chain.size() < spell.max_targets:
        var next := SpellCaster._nearest_to(chain[-1].global_position, r, chain, _player)
        if next == null:
          break
        chain.append(next)
      return chain
    SpellDef.Shape.CONE_STRIKE, SpellDef.Shape.CHANNEL:
      return SpellCaster._in_cone(_player.global_position, dir, spell.reach, spell.cone_deg, spell.max_targets, _player)
    SpellDef.Shape.TARGET_AREA, SpellDef.Shape.GRAVITY_PIT:
      return SpellCaster._in_radius(SpellCaster._area_center(_player, target, dir, spell.reach), r, spell.max_targets, _player)
    SpellDef.Shape.RING_OUT, SpellDef.Shape.AROUND_CASTER:
      if spell.kind == SpellDef.Kind.DEBUFF:
        return SpellCaster._in_radius(_player.global_position, r, 99, _player)
      return SpellCaster._in_radius(_player.global_position, r, spell.max_targets, _player)
    SpellDef.Shape.PROJECTILE, SpellDef.Shape.PIERCE_LINE, SpellDef.Shape.BIG_ORB, SpellDef.Shape.GROUND_LINE:
      var shot := AttackData.new()
      shot.is_projectile = true
      shot.projectile_speed = spell.speed
      shot.projectile_radius = maxf(spell.radius, 0.6 if spell.shape == SpellDef.Shape.GROUND_LINE else 0.0)
      shot.projectile_range = spell.reach + 6.0
      shot.projectile_pierce = spell.pierce or spell.shape == SpellDef.Shape.GROUND_LINE
      return _predict_projectile(shot, target, dir)
    SpellDef.Shape.SPEAR_FAN:
      var fan := AttackData.new()
      fan.is_projectile = true
      fan.projectile_count = spell.max_targets
      fan.spread_deg = spell.cone_deg
      fan.projectile_radius = spell.radius
      fan.projectile_range = spell.reach + 6.0
      fan.projectile_pierce = true
      return _predict_projectile(fan, target, dir)
  return []


## Display name of the spell in a hand's slot ("-" when empty).
func spell_name_in(hand: int, slot: int) -> String:
  var id := get_loadout().get_spell(_holding_hand(hand), slot)
  var spell := SpellBook.get_spell(id) if id != &"" else null
  if spell == null:
    return "-"
  var level := _player.save.character.spell_level(id) if _player and _player.save else 0
  return "%s %d" % [spell.display_name, level] if level > 0 else spell.display_name + " (not learned)"


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
## Spreads (shotguns, volleys) hit everything in their cone, lobs reach their
## target over cover, homing throws (Boomerang) follow their lock chain, and
## explosions add everything inside the blast around the first hit.
func _predict_projectile(attack: AttackData, target: Node3D, dir: Vector3) -> Array[Node3D]:
  if attack.lock_targets > 0:
    return _lock_chain(attack, target, dir)
  if attack.multi_target > 0:
    var picked := _multi_targets(attack, target, dir)
    if not picked.is_empty():
      return picked
  var origin := _player.global_position + Vector3.UP * 1.1
  var aim := dir
  if target:
    aim = (CameraRig.get_lock_point(target) - origin).normalized()
  var found: Array[Node3D] = []
  var count := maxi(attack.projectile_count, 1) + attack.finisher_volley
  var cone := attack.spread_deg * 0.5 if count > 1 else 0.0
  if attack.projectile_gravity > 0.0:
    # Lobbed: it lands on the target (or nowhere we can predict).
    if target and target.global_position.distance_to(_player.global_position) <= attack.projectile_range:
      found.append(target)
  else:
    var first: Node3D = null
    var first_distance := INF
    var space := get_world_3d().direct_space_state
    var flat_aim := Vector3(aim.x, 0.0, aim.z).normalized()
    for node in Scope.group(self, "lockable"):
      var n := node as Node3D
      if n == null or not n.is_visible_in_tree():
        continue
      var rel := CameraRig.get_lock_point(n) - origin
      var along := rel.dot(aim)
      if along < 0.0 or along > attack.projectile_range:
        continue
      var lateral := (rel - aim * along).length()
      var in_cone := cone > 0.0 and rad_to_deg(flat_aim.angle_to(Vector3(rel.x, 0.0, rel.z).normalized())) <= cone + 3.0
      if lateral > attack.projectile_radius + 0.5 and not in_cone:
        continue
      var los := PhysicsRayQueryParameters3D.create(origin, origin + rel, 1, [_player.get_rid()])
      if not space.intersect_ray(los).is_empty():
        continue
      if attack.projectile_pierce or cone > 0.0:
        found.append(n)
      elif along < first_distance:
        first_distance = along
        first = n
    if first:
      found.append(first)
  if attack.explosion_radius > 0.0 and not found.is_empty():
    var center := found[0].global_position
    for node in Scope.group(self, "lockable"):
      var n := node as Node3D
      if n and not n in found and n.global_position.distance_to(center) <= attack.explosion_radius:
        found.append(n)
  return found


## PSO-shotgun targeting: the aimed target first, then the nearest other enemies
## within the attack's cone (MULTI_TARGET_CONE each side by default) of the aim and in range with a clear line,
## up to attack.multi_target. Each gets its own projectile.
func _multi_targets(attack: AttackData, first: Node3D, dir: Vector3) -> Array[Node3D]:
  var origin := _player.global_position + Vector3.UP * 1.1
  var space := get_world_3d().direct_space_state
  var pool: Array[Node3D] = []
  var half_cone := attack.multi_target_cone * 0.5 if attack.multi_target_cone > 0.0 else MULTI_TARGET_CONE
  for node in Scope.group(self, "lockable"):
    var n := node as Node3D
    if n == null or not n.is_visible_in_tree() or n == first:
      continue
    var to := n.global_position - _player.global_position
    to.y = 0.0
    if to.length() > attack.projectile_range or to.length() < 0.01:
      continue
    if rad_to_deg(dir.angle_to(to.normalized())) > half_cone:
      continue
    var los := PhysicsRayQueryParameters3D.create(origin, CameraRig.get_lock_point(n), 1, [_player.get_rid()])
    if not space.intersect_ray(los).is_empty():
      continue
    pool.append(n)
  pool.sort_custom(func(a: Node3D, b: Node3D) -> bool:
    return a.global_position.distance_squared_to(_player.global_position) \
      < b.global_position.distance_squared_to(_player.global_position))
  var picked: Array[Node3D] = []
  if first and first.global_position.distance_to(_player.global_position) <= attack.projectile_range:
    picked.append(first)
  for n in pool:
    if picked.size() >= attack.multi_target:
      break
    picked.append(n)
  return picked


## Homing chain for lock_targets throws: the aimed target (or the nearest enemy
## ahead), then each next-nearest enemy to the last one, up to lock_targets.
func _lock_chain(attack: AttackData, first: Node3D, dir: Vector3) -> Array[Node3D]:
  var chain: Array[Node3D] = []
  var pool: Array[Node3D] = []
  var half_cone := attack.multi_target_cone * 0.5 if attack.multi_target_cone > 0.0 else MULTI_TARGET_CONE
  for node in Scope.group(self, "lockable"):
    var n := node as Node3D
    if n and n.is_visible_in_tree() \
        and n.global_position.distance_to(_player.global_position) <= attack.projectile_range:
      pool.append(n)
  if first == null or not first in pool:
    first = null
    var best := INF
    for n in pool:
      var to := n.global_position - _player.global_position
      to.y = 0.0
      if to.length() < 0.01 or rad_to_deg(dir.angle_to(to.normalized())) > 60.0:
        continue
      if to.length() < best:
        best = to.length()
        first = n
  if first == null:
    return chain
  chain.append(first)
  pool.erase(first)
  while chain.size() < attack.lock_targets and not pool.is_empty():
    var last := chain[-1]
    var next: Node3D = null
    var best := LOCK_CHAIN_HOP
    for n in pool:
      var d := n.global_position.distance_to(last.global_position)
      if d < best:
        best = d
        next = n
    if next == null:
      break
    chain.append(next)
    pool.erase(next)
  return chain


func _find_soft_target(max_range: float, max_angle_deg: float) -> Node3D:
  var origin := _player.global_position
  var forward := -_player.global_basis.z
  forward.y = 0.0
  forward = forward.normalized()
  var best: Node3D = null
  var best_score := INF
  for node in Scope.group(self, "lockable"):
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
    if n is TrapTrigger:
      score += 3.0  # aim at enemies before a Seeker's trap
    if score < best_score:
      best_score = score
      best = n
  return best


func _make_damage(weapon: WeaponData, attack: AttackData, hard: bool, scale: float,
    special: bool = false) -> DamageInfo:
  var info := DamageInfo.new()
  info.weapon = weapon
  info.special = special
  # Gunblade shots are ranged (DEX, EVA) even though the weapon is melee.
  var cls := weapon.weapon_class
  if attack.is_projectile and cls == WeaponData.WeaponClass.MELEE:
    cls = WeaponData.WeaponClass.RANGED
  var stat := stats.attack_stat(cls) * _stat_scale(STAT_FOR_CLASS[cls])
  info.amount = weapon.base_damage * attack.damage_mult * (1.0 + stat / 100.0) * scale
  if _blocking:
    info.amount *= shield_attack_damage_scale
  if aegis_active():
    info.amount *= AEGIS_POWER
  info.damage_type = attack.damage_type if attack.override_damage_type else weapon.damage_type
  info.kind = DamageInfo.Kind.RANGED if attack.ranged_hit else DamageInfo.kind_for(cls)
  info.status_power = attack.status_power
  info.inflicts_status = attack.inflicts_status
  # Sustained ticks count as light hits (no push-back), whatever the button.
  var sustained := hard and weapon.sustained
  info.is_hard = hard and not sustained
  # Hit chance (Accuracy): spells never miss; weapons roll ATA vs EVA.
  if weapon.casting:
    info.accuracy = -1.0
  else:
    info.accuracy = Accuracy.effective_ata(stats.accuracy * _stat_scale(&"accuracy"), hard, special,
      sustained, maxi(chain_step, 1))
    info.hit_bonus = Accuracy.streak_bonus(_hit_streak)
  if randf() < stats.crit_chance():
    info.is_crit = true
    info.amount *= 1.5
  info.source = _player
  return info


## [weapon, attack, damage scale, hand, special] for each hand in this attack.
func _strikes(cur: ActiveAttack) -> Array:
  if not cur.twin:
    return [[cur.weapon, cur.attack, 1.0, cur.hand, cur.special]]
  var scale := 1.0 if cur.weapon.casting else TWIN_DAMAGE_SCALE
  return [[cur.weapon, cur.attack, scale, cur.hand, cur.special],
    [cur.other_weapon, cur.other_attack, scale, 1 - cur.hand, false]]


func _hitbox_transform(cur: ActiveAttack) -> Transform3D:
  return _hitbox_transform_for(cur.attack, cur.direction)


func _hitbox_transform_for(attack: AttackData, dir: Vector3) -> Transform3D:
  var origin := _player.global_position + Vector3.UP * 1.0 + dir * attack.reach
  return Transform3D(Basis.looking_at(dir), origin)


## What this Seeker's attacks hit: enemies, plus other Seekers while confused
## (Grayson 2026-11-12: confused Seekers can hurt their friends).
func hit_mask() -> int:
  if _player and _player.status and _player.status.is_confused():
    return ENEMY_MASK | PLAYER_MASK
  return ENEMY_MASK


func _melee_hits(cur: ActiveAttack) -> void:
  var shape := BoxShape3D.new()
  shape.size = cur.attack.hitbox_size
  var params := PhysicsShapeQueryParameters3D.new()
  params.shape = shape
  params.transform = _hitbox_transform(cur)
  params.collision_mask = hit_mask()
  params.exclude = [_player.get_rid()]
  for result in get_world_3d().direct_space_state.intersect_shape(params, 16):
    var body: Node = result.collider
    if body in cur.hit:
      continue
    cur.hit.append(body)
    var health := Health.find(body)
    if health == null or health.is_dead():
      continue
    for strike in _strikes(cur):
      var info := _make_damage(strike[0], strike[1], cur.hard, strike[2], strike[4])
      info.hit_position = (body as Node3D).global_position + Vector3.UP * 1.2
      report_hit(body, info, HitResolver.apply(body, info, _player))
    if cur.attack.knockback > 0.0 and body.has_method("apply_knockback"):
      body.apply_knockback(cur.direction * cur.attack.knockback)


func _fire_projectiles(cur: ActiveAttack) -> void:
  for strike in _strikes(cur):
    var attack: AttackData = strike[1]
    if not attack.is_projectile:
      continue
    # Shots leave from near the Seeker's centre line (a little toward the firing
    # hand), so a close target straight ahead doesn't pull the shot sideways.
    var hand_side := _pivots[_holding_hand(strike[3])].global_position - _player.global_position
    hand_side = hand_side.project(_player.global_basis.x) * MUZZLE_SIDE_SCALE
    var muzzle := _player.global_position + Vector3.UP * MUZZLE_HEIGHT + hand_side + cur.direction * 0.6
    var target: Node3D = cur.target if is_instance_valid(cur.target) else null
    var aim := cur.direction
    if target:
      aim = _clamp_aim((CameraRig.get_lock_point(target) - muzzle).normalized(), cur.direction)
    # PSO-shotgun targeting: one projectile per picked enemy, each only able to
    # hit its own target.
    if attack.multi_target > 0:
      var picked := _multi_targets(attack, target, cur.direction)
      if not picked.is_empty():
        for t in picked:
          var tinfo := _make_damage(strike[0], attack, cur.hard, strike[2], strike[4])
          var tcolor := Element.color_of(tinfo.damage_type)
          if tinfo.damage_type == Element.Type.GENERIC:
            tcolor = Color(1.0, 0.85, 0.5)
          var tdir := (CameraRig.get_lock_point(t) - muzzle).normalized()
          var tp := Projectile.spawn(_player.get_parent(), muzzle, tdir, attack, tinfo, tcolor, _player, self, hit_mask())
          tp.chain.append(t)
          tp.exclusive = true
        continue
    # Volleys: pellets / extra throws fan out evenly; finishers add finisher_volley.
    var count := maxi(attack.projectile_count, 1) + attack.finisher_volley
    var chain: Array[Node3D] = []
    if attack.lock_targets > 0:
      chain = _lock_chain(attack, target, cur.direction)
    for i in count:
      var info := _make_damage(strike[0], attack, cur.hard, strike[2], strike[4])
      var color := Element.color_of(info.damage_type)
      if info.damage_type == Element.Type.GENERIC:
        color = Color(1.0, 0.85, 0.5)
      var dir := aim
      if attack.spread_deg > 0.0:
        var offset := randf_range(-0.5, 0.5) * attack.spread_deg  # automatic fire jitter
        if count > 1:
          offset = lerpf(-0.5, 0.5, float(i) / float(count - 1)) * attack.spread_deg
        dir = aim.rotated(Vector3.UP, deg_to_rad(offset))
      var p := Projectile.spawn(_player.get_parent(), muzzle, dir, attack, info, color, _player, self, hit_mask())
      if attack.projectile_gravity > 0.0:
        p.velocity = _lob_velocity(muzzle, dir, target, attack)  # a fan lands as far out as the target
      if not chain.is_empty():
        p.chain = chain.duplicate()
      if attack.lock_targets > 0:
        p.return_when_done = true  # Boomerang: comes back to you


## Keeps a shot within MAX_AIM_YAW degrees of the facing direction (left /
## right only; up and down are free), so a target very close to the muzzle
## can't send it off at a wild angle.
func _clamp_aim(aim: Vector3, facing: Vector3) -> Vector3:
  var flat := Vector3(aim.x, 0.0, aim.z)
  if flat.length_squared() < 0.0001:
    return aim
  var yaw := facing.signed_angle_to(flat.normalized(), Vector3.UP)
  var limit := deg_to_rad(MAX_AIM_YAW)
  if absf(yaw) <= limit:
    return aim
  var clamped := facing.rotated(Vector3.UP, clampf(yaw, -limit, limit))
  return (clamped * flat.length() + Vector3.UP * aim.y).normalized()


## Launch velocity for a lobbed shot: lands on the target (or, with no target,
## on the ground half its range away) at the attack's horizontal speed.
func _lob_velocity(from: Vector3, dir: Vector3, target: Node3D, attack: AttackData) -> Vector3:
  var flat := Vector3(dir.x, 0.0, dir.z).normalized()
  var distance := attack.projectile_range * 0.5
  var land_y := _player.global_position.y
  if target:
    var to := target.global_position - from
    distance = Vector2(to.x, to.z).length()
    land_y = target.global_position.y + 0.3
  distance = clampf(distance, 1.5, attack.projectile_range)
  var speed := attack.projectile_speed
  var t := distance / speed
  var vy := (land_y - from.y + 0.5 * attack.projectile_gravity * t * t) / t
  return flat * speed + Vector3.UP * vy


## Confused (Grayson 2026-11-12): heals and cures land on nearby enemies too.
func _support_enemies(attack: AttackData) -> void:
  for node in Scope.group(self, "enemies"):
    var enemy := node as Enemy
    if enemy == null or enemy.is_dead() or enemy.global_position.distance_to(_player.global_position) > SUPPORT_RANGE:
      continue
    if attack.support_amount > 0.0:
      enemy.health.heal(enemy.health.max_hp * attack.support_amount * (1.0 + stats.soul / 200.0))
    if attack.support == AttackData.Support.CURE:
      enemy.status.clear_all()


## Heal / Cure (North Star §6): typeless support spells that affect the caster
## and any other Seeker within SUPPORT_RANGE. Heal restores a fraction of max HP
## that grows with SOL; Cure clears every status (Hard Cure also heals a little).
func _cast_support(cur: ActiveAttack) -> void:
  for strike in _strikes(cur):
    var attack: AttackData = strike[1]
    if attack.support == AttackData.Support.NONE:
      continue
    if _player.status.is_confused():
      _support_enemies(attack)
    for node in Scope.group(self, "player"):
      var seeker := node as Player
      if seeker == null or seeker.global_position.distance_to(_player.global_position) > SUPPORT_RANGE:
        continue
      var restored := 0.0
      if attack.support_amount > 0.0:
        restored = seeker.health.heal(seeker.health.max_hp * attack.support_amount * (1.0 + stats.soul / 200.0))
      if attack.support == AttackData.Support.CURE:
        seeker.status.clear_all()
        DamageNumber.spawn_text(seeker.get_parent(), seeker.global_position + Vector3.UP * 2.2, "Cured")
      if restored > 0.0:
        DamageNumber.spawn_text(seeker.get_parent(), seeker.global_position + Vector3.UP * 2.0, "+%d" % roundi(restored))
  combo_feedback.emit("Cure" if cur.attack.support == AttackData.Support.CURE else "Heal")


## The Charge line's cost for this weapon's special: "oro", "lp", "hp" or "".
func _charge_cost(weapon: WeaponData) -> String:
  if weapon.tag == null or weapon.tag.effect != SpecialTag.Effect.CHARGE:
    return ""
  return SpecialTag.CHARGE_COSTS[clampi(weapon.tag_tier, 0, SpecialTag.CHARGE_COSTS.size() - 1)]


## Tag effects of an RT special that landed (SpecialTag.Effect).
func _apply_tag_effect(target: Node, info: DamageInfo, amount: float) -> void:
  var tag := info.weapon.tag
  var tier := clampi(info.weapon.tag_tier, 0, tag.tier_count() - 1)
  var enemy := target as Enemy
  var health := Health.find(target)
  var boss := enemy != null and enemy.data.boss
  match tag.effect:
    SpecialTag.Effect.BURST:
      _burst(target, info, amount)
    SpecialTag.Effect.INSTANT_KILL:
      if health and not health.is_dead() and not boss and randf() < SpecialTag.KILL_CHANCE[tier]:
        var kill := DamageInfo.new()
        kill.amount = health.hp * 4.0 + 1.0  # covers any resistance
        kill.damage_type = Element.Type.GENERIC
        kill.source = _player
        health.take_damage(kill)
        combo_feedback.emit("Instant kill!")
    SpecialTag.Effect.DRAIN_HP:
      _player.health.heal(amount * SpecialTag.DRAIN_FRACTION[tier])
    SpecialTag.Effect.STEAL_LP:
      lp = minf(lp + amount * SpecialTag.LP_FRACTION[tier], stats.max_lp)
    SpecialTag.Effect.STEAL_EXP:
      if enemy:
        _player.gain_exp(maxi(roundi(enemy.data.exp_value() * SpecialTag.EXP_FRACTION[mini(tier, 2)]), 1))
    SpecialTag.Effect.CUT_HP:
      if health and not health.is_dead() and not boss:
        var cut := DamageInfo.new()
        cut.amount = health.hp * SpecialTag.CUT_FRACTION[mini(tier, 1)]
        cut.source = _player
        health.take_damage(cut)
        _player.health.hp = maxf(_player.health.hp - _player.health.hp * 0.1, 1.0)


## Burst lines (2026-11-12): the special bursts on the target, hitting up to
## BURST_EXTRA_TARGETS more within BURST_RADIUS for the damage the target took.
func _burst(target: Node, info: DamageInfo, amount: float) -> void:
  var center := target as Node3D
  if center == null or not center.is_inside_tree():
    return
  var at := center.global_position
  SpellFx.burst(center.get_parent(), at + Vector3.UP * 0.8, SpecialTag.BURST_RADIUS,
    Element.color_of(info.damage_type), 0.35)
  for body in burst_targets(center):
    var blast := DamageInfo.new()
    blast.amount = amount
    blast.damage_type = info.damage_type
    blast.kind = info.kind
    blast.accuracy = -1.0  # a burst never misses, like any explosion
    blast.source = _player
    blast.weapon = info.weapon
    blast.hit_position = body.global_position + Vector3.UP * 1.0
    var dealt := HitResolver.apply(body, blast, _player)
    hit_landed.emit(body, blast, dealt)


## Who a burst on this target would also reach: the nearest others in range
## (other Seekers too while confused).
func burst_targets(center: Node3D) -> Array[Node3D]:
  var found: Array[Node3D] = []
  var pool: Array = Scope.group(self, "enemies")
  if _player.status and _player.status.is_confused():
    pool += Scope.group(self, "player").filter(func(p): return p != _player)
  pool.sort_custom(func(x, y): return (x as Node3D).global_position.distance_squared_to(center.global_position) \
    < (y as Node3D).global_position.distance_squared_to(center.global_position))
  for node in pool:
    var body := node as Node3D
    if body == null or body == center or found.size() >= SpecialTag.BURST_EXTRA_TARGETS:
      continue
    var health := Health.find(body)
    if health == null or health.is_dead():
      continue
    if body.global_position.distance_to(center.global_position) <= SpecialTag.BURST_RADIUS:
      found.append(body)
  return found


func _regen_lp(delta: float) -> void:
  if infinite_lp:
    lp = stats.max_lp
    return
  if _lp_regen_delay > 0.0:
    _lp_regen_delay -= delta
    return
  var rate := stats.lp_regen_per_second + stats.max_lp * lp_regen_fraction
  if rate > 0.0:
    lp = minf(lp + rate * delta, stats.max_lp)


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
## weapon is one item, always held in the primary hand; both buttons use it.
func _holding_hand(hand: int) -> int:
  var l := get_loadout()
  if l and l.two_handed_weapon():
    return Hand.PRIMARY
  return hand


## What each hand visibly holds (a two-handed weapon shows in the primary hand only).
func _held_weapon(hand: int) -> WeaponData:
  var l := get_loadout()
  if l == null:
    return null
  var two_hand := l.two_handed_weapon()
  if two_hand:
    return two_hand if hand == Hand.PRIMARY else null
  return l.get_hand(hand)


func _equip_visuals() -> void:
  rotation.y = 0.0
  for hand in [Hand.OFF, Hand.PRIMARY]:
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
    return Vector3(-0.3, 0.6 if hand == Hand.OFF else -0.6, 0.0)
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
  for hand in [Hand.OFF, Hand.PRIMARY]:
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
      _pivots[hand].rotation = Vector3(0.9, 0.5 if hand == Hand.OFF else -0.5, 0.0)


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


## The Seeker's controls (Part 12): its own controller in co-op.
func _in() -> PlayerInput:
  return _player.input if _player else _SHARED_INPUT


static var _SHARED_INPUT := PlayerInput.shared()


## Pays LP for something outside an attack (d-pad traps). False when short.
func spend_lp(cost: float) -> bool:
  if infinite_lp:
    return true
  if lp < cost:
    return false
  lp -= cost
  if cost > 0.0:
    _lp_regen_delay = 0.75
  return true
