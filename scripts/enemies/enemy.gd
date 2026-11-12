class_name Enemy
extends CharacterBody3D
## A real enemy, driven by an EnemyData resource. Built entirely in code, so
## spawn one with Enemy.create(data).
##
## AI (navmesh, North Star requirement): idle until the Seeker comes within
## aggro_range (or it gets hit), then paths toward them with a NavigationAgent3D.
## Melee enemies close to attack_range; ranged and spell enemies hold their
## distance, backing off inside min_range. Every attack is telegraphed: the
## enemy glows in its element's color for `windup`, then strikes, then
## recovers. Big hits and parries stagger it; statuses slow, freeze, stun or
## confuse it (a confused enemy attacks whoever is closest, friend or foe).
##
## Level editor settings (Part 13a, Grayson 2026-11-12; see configure()):
## stats and attacks never change, but a placed enemy can
## - wander within wander_radius of where it spawned (otherwise it stands
##   still until it notices someone);
## - give up a chase once its target is more than chase_radius from where
##   it spawned (limited chase), walk back home without healing, and be
##   pulled again once it's there;
## - notice Seekers at a shorter or longer aggro range (aggro_scale).

signal defeated(enemy: Enemy)

enum State { IDLE, CHASE, WINDUP, RECOVER, STAGGER, DEAD, RETURN }

const ENEMY_DIR := "res://data/enemies/"
## Wandering: walks at this share of its speed and pauses between walks.
const WANDER_SPEED := 0.45
const WANDER_PAUSE := Vector2(1.2, 3.0)

const ENEMY_LAYER := 4
## Hit reactions (Part 6).
const HARD_FLINCH_CHANCE := 0.9
const HARD_FLINCH_CHANCE_BOSS := 0.25
const HARD_FLINCH_SECONDS := 0.35
const HARD_PUSH_SPEED := 4.5  # about 0.6 m of push-back
const LIGHT_STAGGER_FRACTION := 0.5
const WORLD_MASK := 1

var data: EnemyData
var state: State = State.IDLE
var health: Health
var status: StatusEffects

var _agent: NavigationAgent3D
var _label: Label3D
var _material: StandardMaterial3D
var _glow_tween: Tween
## Debug view of the melee hit area (melee enemies only).
var hit_area: HitAreaView
var _timer := 0.0
var _cooldown := 0.6
var _aggro := false
var _knockback := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

## Level editor placement (Part 13a). Home is where it spawned.
var placement_id := ""
var home := Vector3.ZERO
var wander := false
var wander_radius := 0.0
var limited_chase := false
var chase_radius := 0.0
var aggro_scale := 1.0
var _home_set := false
var _wander_target := Vector3.INF
var _wander_wait := 0.0


static func create(enemy_data: EnemyData) -> Enemy:
	var e := Enemy.new()
	e.data = enemy_data
	e.name = enemy_data.display_name.replace(" ", "")
	return e


## The EnemyData for an id ("grub_hound"): only files in data/enemies/, so a
## level can't point anywhere else. Null if there's no such enemy.
static func data_for(id: String) -> EnemyData:
	if id == "" or not id.is_valid_filename() or id.contains("/") or id.contains("."):
		return null
	var path := ENEMY_DIR + id + ".tres"
	return load(path) as EnemyData if ResourceLoader.exists(path) else null


## Every enemy id the game has (for checking levels).
static func known_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(ENEMY_DIR):
		var f := file.trim_suffix(".remap")
		if f.ends_with(".tres"):
			out.append(f.get_basename())
	return out


## Applies a level placement (docs/level_format.md, combat.json). `alert`
## enemies come straight for the Seekers (wave enemies, like PSO).
func configure(p: Dictionary) -> void:
	placement_id = String(p.get("id", ""))
	wander = bool(p.get("wander", false))
	wander_radius = maxf(float(p.get("wander_radius", 0.0)), 0.0)
	limited_chase = bool(p.get("limited_chase", false))
	chase_radius = maxf(float(p.get("chase_radius", 0.0)), 0.0)
	if wander and limited_chase and chase_radius < wander_radius:
		push_warning("Enemy %s: chase radius below wander radius; using the wander radius" % placement_id)
		chase_radius = wander_radius
	aggro_scale = float(LevelData.AGGRO.get(String(p.get("aggro", "normal")), 1.0))
	_aggro = bool(p.get("alert", false))


## Where it gives up (limited chase): the target is too far from home.
func is_beyond_leash(point: Vector3) -> bool:
	if not limited_chase:
		return false
	var d := point - home
	d.y = 0.0
	return d.length() > chase_radius


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_MASK | ENEMY_LAYER
	add_to_group("lockable")
	add_to_group("enemies")
	_build()


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * (data.size.y * 0.6 + data.hover_height)


func is_dead() -> bool:
	return state == State.DEAD


# --- Taking hits ----------------------------------------------------------------

func receive_hit(info: DamageInfo, attacker: Node3D, _projectile: Node = null) -> float:
	if state == State.DEAD:
		return 0.0
	var dodge := RoomHazard.dark_dodge(attacker, self)
	if not Accuracy.roll(info, data.evasion * status.stat_scale(&"evasion"), self, status, dodge):
		return 0.0
	info.amount *= Defense.scale_for(info.kind, data.defense * status.stat_scale(&"defense"), data.resolve)
	# PSO-style monster-type bonus on the weapon (e.g. +20% vs Beast).
	if info.weapon and info.weapon.type_bonus.has(data.enemy_type):
		info.amount *= 1.0 + float(info.weapon.type_bonus[data.enemy_type])
	var amount := health.take_damage(info)
	status.add_buildup(info, attacker)
	_aggro = true
	_react(info, attacker, amount)
	return amount


## Part 6 (PSO feel): light and sustained hits almost never interrupt; only a
## single huge hit (LIGHT_STAGGER_FRACTION of max HP) does. Hard hits almost
## always push the enemy back a little and cut its windup short.
func _react(info: DamageInfo, attacker: Node3D, amount: float) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	if info.is_hard:
		if randf() < (HARD_FLINCH_CHANCE_BOSS if data.boss else HARD_FLINCH_CHANCE):
			var away := global_position - (attacker.global_position if attacker else global_position)
			away.y = 0.0
			if away.length_squared() < 0.001:
				away = global_basis.z
			_knockback = away.normalized() * HARD_PUSH_SPEED
			_stagger(HARD_FLINCH_SECONDS)
	elif amount >= health.max_hp * LIGHT_STAGGER_FRACTION:
		_stagger(HARD_FLINCH_SECONDS)


func on_parried() -> void:
	_stagger(1.5)
	_glow(Color(0.3, 0.6, 1.0), 1.5)


## Gravity pull (Granmalbo): moves it without interrupting.
func apply_pull(velocity_add: Vector3) -> void:
	velocity_add.y = 0.0
	_knockback = velocity_add


func apply_knockback(push: Vector3) -> void:
	push.y = 0.0
	_knockback = push
	_stagger(0.6)


func _stagger(seconds: float) -> void:
	if state == State.DEAD:
		return
	var already := state == State.STAGGER
	state = State.STAGGER
	_timer = maxf(_timer, seconds) if already else seconds
	_cooldown = maxf(_cooldown, 0.5)


# --- AI -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if data.hover_height <= 0.0 and not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if not _home_set:
		_home_set = true
		home = global_position
	var seeker: Node3D = Player.nearest(self, global_position)
	if status.is_confused():
		seeker = _nearest_anyone()
		if seeker and state in [State.IDLE, State.RETURN]:
			state = State.CHASE  # confused: forgets its aggro and goes for whoever's closest
	var move := Vector3.ZERO
	var acting := status.can_act()
	if not acting and state == State.WINDUP:
		state = State.CHASE  # frozen or shocked mid-windup: the attack is lost
		if hit_area:
			hit_area.stop()
	if seeker and acting:
		move = _think(seeker, delta)

	_knockback = _knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = move.x + _knockback.x
	velocity.z = move.z + _knockback.z
	move_and_slide()


## Confused (Grayson 2026-11-12): the closest living thing, Seeker or enemy.
func _nearest_anyone() -> Node3D:
	var best: Node3D = Player.nearest(self, global_position)
	var best_dist := best.global_position.distance_squared_to(global_position) if best else INF
	for node in Scope.group(self, "enemies"):
		var other := node as Enemy
		if other == null or other == self or other.is_dead():
			continue
		var d := other.global_position.distance_squared_to(global_position)
		if d < best_dist:
			best_dist = d
			best = other
	return best


func _think(seeker: Node3D, delta: float) -> Vector3:
	var to := seeker.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_cooldown -= delta
	match state:
		State.IDLE:
			if _aggro or (dist <= data.aggro_range * aggro_scale \
					and not is_beyond_leash(seeker.global_position)):
				_aggro = true
				state = State.CHASE
			elif wander and wander_radius > 0.0:
				return _wander_step(delta)
		State.RETURN:
			var back := home - global_position
			back.y = 0.0
			if back.length() <= 0.8:
				state = State.IDLE
				_aggro = false
				return Vector3.ZERO
			var step_home := _move_toward(home, data.move_speed * status.move_scale(), delta)
			if step_home == Vector3.ZERO and _agent.is_navigation_finished():
				state = State.IDLE  # can't path any closer
				_aggro = false
			return step_home
		State.CHASE:
			if is_beyond_leash(seeker.global_position) and not status.is_confused():
				state = State.RETURN  # limited chase: gives up and walks home
				_aggro = false
				return Vector3.ZERO
			if _can_attack_from_here(seeker, dist):
				_face(to, delta, 20.0)
				if _cooldown <= 0.0:
					state = State.WINDUP
					_timer = data.windup
					_glow(_element_color(), data.windup)
				return Vector3.ZERO
			return _approach(seeker, to, dist, delta)
		State.WINDUP:
			_face(to, delta, 6.0 if data.attack_style == EnemyData.AttackStyle.MELEE else 12.0)
			_timer -= delta * (0.5 if status.is_active(StatusEffects.Status.SLOW) else 1.0)
			if hit_area:
				hit_area.telegraph(1.0 - _timer / maxf(data.windup, 0.01))
			if _timer <= 0.0:
				_attack(seeker)
				state = State.RECOVER
				_timer = data.recovery
				_cooldown = data.attack_interval
		State.RECOVER, State.STAGGER:
			_timer -= delta
			if _timer <= 0.0:
				state = State.CHASE
	return Vector3.ZERO


func _can_attack_from_here(seeker: Node3D, dist: float) -> bool:
	if data.attack_style == EnemyData.AttackStyle.MELEE:
		return dist <= data.attack_range
	return dist <= data.attack_range and _has_line_of_sight(seeker)


func _approach(seeker: Node3D, to: Vector3, dist: float, delta: float) -> Vector3:
	var speed := data.move_speed * status.move_scale()
	var goal := seeker.global_position
	if data.attack_style != EnemyData.AttackStyle.MELEE and dist < data.min_range and dist > 0.01:
		goal = global_position - to.normalized() * 4.0  # too close: back off
	_agent.target_desired_distance = 0.4
	_agent.target_position = goal
	if NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) == 0 or _agent.is_navigation_finished():
		_face(to, delta, 8.0)
		return Vector3.ZERO
	_agent.get_next_path_position()  # keeps the agent's path up to date
	var step := _flat_step()
	if step == Vector3.ZERO:
		return Vector3.ZERO
	_face(step, delta, 8.0)
	return step.normalized() * speed


## Walks toward a point on the navmesh (wandering, going home).
func _move_toward(goal: Vector3, speed: float, delta: float) -> Vector3:
	_agent.target_desired_distance = 0.4
	_agent.target_position = goal
	if NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) == 0 \
			or _agent.is_navigation_finished():
		return Vector3.ZERO
	_agent.get_next_path_position()
	var step := _flat_step()
	if step == Vector3.ZERO:
		return Vector3.ZERO
	_face(step, delta, 8.0)
	return step.normalized() * speed


## Idle wandering: a short walk to a random spot near home, then a pause.
func _wander_step(delta: float) -> Vector3:
	if _wander_wait > 0.0:
		_wander_wait -= delta
		return Vector3.ZERO
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if _wander_target == Vector3.INF or to_target.length() < 0.6:
		if _wander_target != Vector3.INF:
			_wander_wait = randf_range(WANDER_PAUSE.x, WANDER_PAUSE.y)
		var angle := randf() * TAU
		var r := sqrt(randf()) * wander_radius
		_wander_target = home + Vector3(cos(angle), 0.0, sin(angle)) * r
		return Vector3.ZERO
	var step := _move_toward(_wander_target, data.move_speed * WANDER_SPEED * status.move_scale(), delta)
	if step == Vector3.ZERO:
		_wander_target = Vector3.INF  # unreachable or there: pick another spot
		_wander_wait = randf_range(WANDER_PAUSE.x, WANDER_PAUSE.y)
	return step


## First waypoint that's actually ahead horizontally. The navmesh sits above
## the enemy's origin (and hovering enemies float higher still), so the agent's
## own "next point" can stay on top of us; compare flat distance instead.
func _flat_step() -> Vector3:
	var path := _agent.get_current_navigation_path()
	for i in range(_agent.get_current_navigation_path_index(), path.size()):
		var d := path[i] - global_position
		d.y = 0.0
		if d.length() > 0.3:
			return d
	return Vector3.ZERO


func _attack(seeker: Node3D) -> void:
	var info := DamageInfo.new()
	info.amount = data.attack_damage * status.stat_scale(_attack_stat())
	info.damage_type = data.attack_element
	info.status_power = data.status_power
	info.source = self
	info.accuracy = data.accuracy * status.stat_scale(&"accuracy")
	match data.attack_style:
		EnemyData.AttackStyle.MELEE:
			info.kind = DamageInfo.Kind.MELEE
			var to := seeker.global_position - global_position
			to.y = 0.0
			var facing := -global_basis.z
			var in_arc := data.melee_arc_deg >= 360.0 \
				or facing.angle_to(to.normalized()) <= deg_to_rad(data.melee_arc_deg * 0.5)
			if hit_area:
				hit_area.strike()
			if to.length() <= data.attack_range + 0.4 and in_arc:
				HitResolver.apply(seeker, info, self)
		_:
			info.kind = DamageInfo.Kind.RANGED if data.attack_style == EnemyData.AttackStyle.RANGED \
				else DamageInfo.Kind.MAGIC
			var shot := AttackData.new()
			shot.projectile_speed = data.projectile_speed
			shot.projectile_radius = 0.22
			shot.projectile_range = data.attack_range + 6.0
			var from := get_lock_point()
			var aim := (seeker.global_position + Vector3.UP * 1.1 - from).normalized()
			var mask := Projectile.PLAYER_MASK
			if status.is_confused():
				mask |= Projectile.ENEMY_MASK  # its shots hit friend and foe
			Projectile.spawn(get_parent(), from, aim, shot, info, _element_color(), self, null, mask)


## Which of its stats a debuff lowers: melee STR, ranged DEX, casters SOL.
func _attack_stat() -> StringName:
	match data.attack_style:
		EnemyData.AttackStyle.MELEE:
			return &"strength"
		EnemyData.AttackStyle.RANGED:
			return &"dexterity"
	return &"soul"


func _has_line_of_sight(seeker: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(get_lock_point(),
		seeker.global_position + Vector3.UP * 1.1, WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-rate * delta))


# --- Damage feedback and death ----------------------------------------------------

func _on_damaged(info: DamageInfo, amount: float) -> void:
	var at := info.hit_position if info.hit_position != Vector3.ZERO else get_lock_point()
	DamageNumber.spawn(get_parent(), at, amount, info.damage_type, info.is_crit)
	_update_label()
	if state != State.WINDUP:
		_glow(Color.WHITE, 0.15)


func _on_died() -> void:
	state = State.DEAD
	remove_from_group("lockable")
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = WORLD_MASK
	_label.visible = false
	defeated.emit(self)
	# EXP for the Seeker and a loot roll (Main is in the loot_spawner group).
	var level := Scope.level(self)
	if level:
		level.call("on_enemy_defeated", self)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.2, 0.05, 1.2), 0.4).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _update_label() -> void:
	var text := "%s\n%d / %d" % [data.display_name, ceili(health.hp), roundi(health.max_hp)]
	if not status.active.is_empty():
		text += "\n" + status.describe()
	_label.text = text


func _process(_delta: float) -> void:
	if state != State.DEAD and not status.active.is_empty():
		_update_label()


func _element_color() -> Color:
	if data.attack_element == Element.Type.GENERIC:
		return Color(1.0, 0.55, 0.1)
	return Element.color_of(data.attack_element)


func _glow(color: Color, seconds: float) -> void:
	if _glow_tween:
		_glow_tween.kill()
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 1.4
	_glow_tween = create_tween()
	_glow_tween.tween_property(_material, "emission_energy_multiplier", 0.0, seconds)


# --- Construction -----------------------------------------------------------------

func _build() -> void:
	var lift := data.size.y * 0.5 + data.hover_height
	var shape: Shape3D
	var mesh: PrimitiveMesh
	match data.shape:
		EnemyData.Shape.BOX:
			var b := BoxShape3D.new()
			b.size = data.size
			shape = b
			var bm := BoxMesh.new()
			bm.size = data.size
			mesh = bm
		EnemyData.Shape.SPHERE:
			var sp := SphereShape3D.new()
			sp.radius = data.size.x * 0.5
			shape = sp
			var sm := SphereMesh.new()
			sm.radius = data.size.x * 0.5
			sm.height = data.size.y
			mesh = sm
		_:
			var c := CapsuleShape3D.new()
			c.radius = data.size.x * 0.5
			c.height = maxf(data.size.y, data.size.x)
			shape = c
			var cm := CapsuleMesh.new()
			cm.radius = data.size.x * 0.5
			cm.height = maxf(data.size.y, data.size.x)
			mesh = cm

	if data.attack_style == EnemyData.AttackStyle.MELEE:
		# Same reach and arc as the hit check in _attack().
		hit_area = HitAreaView.create(data.attack_range + 0.4, data.melee_arc_deg)
		add_child(hit_area)

	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = lift
	add_child(collider)

	_material = StandardMaterial3D.new()
	_material.albedo_color = data.color
	_material.roughness = 0.6
	mesh.material = _material
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.position.y = lift
	add_child(body)

	# Dark band across the front, so you can see which way it faces.
	var eye := MeshInstance3D.new()
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(data.size.x * 0.6, 0.12, 0.12)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.08)
	eye_mesh.material = eye_mat
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, lift + data.size.y * 0.2, -data.size.z * 0.5)
	add_child(eye)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 34
	_label.outline_size = 10
	_label.position.y = lift + data.size.y * 0.5 + 0.5
	add_child(_label)

	health = Health.new()
	health.name = "Health"
	health.max_hp = data.max_hp  # same in co-op, like PSO (Grayson, 2026-11-09)
	add_child(health)
	health.hp = health.max_hp
	if data.weak_to != Element.Type.GENERIC:
		health.multipliers[data.weak_to] = 2.0
	if data.resists != Element.Type.GENERIC:
		health.multipliers[data.resists] = 0.5
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	status = StatusEffects.new()
	status.name = "StatusEffects"
	status.threshold = maxf(30.0, data.max_hp * 0.25)
	add_child(status)

	_agent = NavigationAgent3D.new()
	_agent.radius = data.size.x * 0.5
	_agent.height = data.size.y
	_agent.path_desired_distance = 0.5
	add_child(_agent)
	_update_label()
