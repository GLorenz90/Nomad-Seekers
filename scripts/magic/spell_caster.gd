class_name SpellCaster
extends RefCounted
## Turns a learned spell into an attack and makes it happen (Part 6).
##
## make_attack() builds the AttackData the CombatController plays (cast time,
## LP, moving or rooted); cast() runs at the cast frame; channel_tick() runs
## for held Sustained spells. Damage uses PSO's technique formula:
##   (SOL + technique base power) / 5 x casting item power x Hard bonus,
## then the target's RES and weaknesses. Spells never miss.

## Hard (held) casts: stronger, cost more, take longer and root you.
const HARD_POWER := 1.6
const HARD_LP := 1.6
const HARD_EXTRA_CAST := 9
const HARD_EXTRA_TOTAL := 10
const HARD_AREA := 1.25
const MOBILE_SPEED := 0.5
const CHANNEL_TICK := 0.25
const MAX_TRAPS := 4
const PARTY_RADIUS := 10.0
const NO_TARGET_REACH := 0.6  # area spells with no target land this far out

static var _cache := {}


## The attack for one cast. Cached per spell, level, Hard and casting item.
static func make_attack(spell: SpellDef, level: int, hard: bool, item: WeaponData) -> AttackData:
	var key := "%s|%d|%s|%s" % [spell.id, level, hard, item.resource_path if item else ""]
	if _cache.has(key):
		return _cache[key]
	var speed := item.cast_speed if item else 1.0
	var cast := (spell.cast_frames + (HARD_EXTRA_CAST if hard else 0)) * speed
	var total := (spell.total_frames + (HARD_EXTRA_TOTAL if hard else 0)) * speed
	var a := AttackData.new()
	a.display_name = spell.display_name + (" (Hard)" if hard else "")
	a.swing = AttackData.Swing.CAST
	a.damage_mult = 0.0
	a.active_start = cast / 30.0
	a.active_end = a.active_start
	a.duration = total / 30.0
	a.window_open = a.duration
	a.window_close = a.duration
	a.lunge_distance = 0.0
	a.lp_cost = spell.lp_cost(level) * (HARD_LP if hard else 1.0)
	a.move_speed_scale = 0.0 if hard else MOBILE_SPEED
	a.override_damage_type = true
	a.damage_type = spell.element
	a.spell = spell
	a.spell_level = level
	if spell.kind == SpellDef.Kind.SUSTAINED and hard:
		a.channel = true
		a.sustained_tick = CHANNEL_TICK  # held: channel until released or out of LP
		a.move_speed_scale = 0.3
	_cache[key] = a
	return a


static func clear_cache() -> void:
	_cache.clear()


# --- Casting ------------------------------------------------------------------------

## Runs the spell at its cast frame.
static func cast(ctrl: CombatController, item: WeaponData, attack: AttackData, hard: bool,
		target: Node3D, direction: Vector3) -> void:
	var spell := attack.spell
	var level := attack.spell_level
	var player := ctrl.get_parent() as Player
	var world := player.get_parent()
	var color := _color(spell)
	var origin := player.global_position + Vector3.UP * 1.2 + direction * 0.6
	var area_scale := HARD_AREA if hard else 1.0
	var r := (spell.radius + spell.radius_growth * (level - 1)) * area_scale
	var target_alive := target if _alive(target) else null
	match spell.shape:
		SpellDef.Shape.PROJECTILE, SpellDef.Shape.PIERCE_LINE, SpellDef.Shape.HOMING_ORB, SpellDef.Shape.BIG_ORB:
			var aim := direction
			if target_alive:
				aim = (CameraRig.get_lock_point(target_alive) - origin).normalized()
			if spell.shape == SpellDef.Shape.BIG_ORB:
				aim = Vector3(aim.x, 0.0, aim.z).normalized()  # rolls level, through the whole pack
			var p := _projectile(ctrl, item, attack, hard, origin, aim, spell.radius * (1.4 if spell.shape == SpellDef.Shape.BIG_ORB and hard else 1.0))
			if spell.shape == SpellDef.Shape.HOMING_ORB and target_alive:
				p.chain.append(target_alive)
		SpellDef.Shape.GROUND_LINE:
			var flat := Vector3(direction.x, 0.0, direction.z).normalized()
			var p := _projectile(ctrl, item, attack, hard, player.global_position + Vector3.UP * 0.5 + flat * 0.6, flat, 0.6)
			p.pierce = true
		SpellDef.Shape.SPEAR_FAN:
			var count := spell.max_targets + (2 if hard else 0)
			for i in count:
				var t := 0.5 if count == 1 else float(i) / float(count - 1)
				var dir := direction.rotated(Vector3.UP, deg_to_rad(lerpf(-0.5, 0.5, t) * spell.cone_deg))
				_projectile(ctrl, item, attack, hard, origin, dir, spell.radius)
		SpellDef.Shape.SKY_STRIKE:
			var victim := target_alive if target_alive else _nearest_ahead(player, direction, spell.reach, 60.0)
			if victim == null:
				ctrl.combo_feedback.emit("No target")
				return
			var delay := 0.35 if spell.element == Element.Type.LIGHT else 0.0
			_later(player, delay, func():
				if _alive(victim):
					SpellFx.beam(world, victim.global_position, color, 0.5 if delay > 0.0 else 0.25)
					_damage(ctrl, item, spell, level, hard, victim, 1.0))
		SpellDef.Shape.RING_OUT:
			SpellFx.ring(world, player.global_position, r, color, 0.5)
			var hits := _in_radius(player.global_position, r, spell.max_targets, player)
			for v in hits:
				var d := v.global_position.distance_to(player.global_position)
				_later(player, 0.5 * d / maxf(r, 0.1), func():
					if _alive(v):
						_damage(ctrl, item, spell, level, hard, v, 1.0))
		SpellDef.Shape.CHAIN:
			var first := target_alive if target_alive else _nearest_ahead(player, direction, spell.reach, 60.0)
			if first == null:
				ctrl.combo_feedback.emit("No target")
				return
			var chain: Array[Node3D] = [first]
			while chain.size() < spell.max_targets:
				var next := _nearest_to(chain[-1].global_position, r, chain, player)
				if next == null:
					break
				chain.append(next)
			var from := origin
			for i in chain.size():
				var v := chain[i]
				var start := from
				_later(player, 0.07 * i, func():
					if _alive(v):
						SpellFx.line(world, start, CameraRig.get_lock_point(v), color)
						_damage(ctrl, item, spell, level, hard, v, 1.0))
				from = CameraRig.get_lock_point(v)
		SpellDef.Shape.CONE_STRIKE:
			var reach := spell.reach * area_scale
			SpellFx.cone(world, player.global_position, direction, reach, spell.cone_deg, color, 0.3)
			for v in _in_cone(player.global_position, direction, reach, spell.cone_deg, spell.max_targets, player):
				if spell.element == Element.Type.LIGHT:
					SpellFx.beam(world, v.global_position, color, 0.3)
				else:
					SpellFx.spike(world, v.global_position, color)
				_damage(ctrl, item, spell, level, hard, v, 1.0)
		SpellDef.Shape.TARGET_AREA:
			var center := _area_center(player, target_alive, direction, spell.reach)
			if spell.element == Element.Type.FIRE:
				SpellFx.burst(world, center + Vector3.UP * 0.5, r, color)
			else:
				SpellFx.ring(world, center, r, color, 0.4)
			for v in _in_radius(center, r, spell.max_targets, player):
				if spell.element != Element.Type.FIRE:
					SpellFx.beam(world, v.global_position, color, 0.25)
				_damage(ctrl, item, spell, level, hard, v, 1.0)
		SpellDef.Shape.AROUND_CASTER:
			SpellFx.ring(world, player.global_position, r, color, 0.4)
			if spell.kind == SpellDef.Kind.DEBUFF:
				var n := 0
				for v in _in_radius(player.global_position, r, 99, player):
					var st := StatusEffects.find(v)
					if st:
						st.apply_modifier(spell.stat, SpellBook.debuff_fraction(level) * (1.25 if hard else 1.0),
							SpellBook.debuff_seconds(level))
						DamageNumber.spawn_text(world, v.global_position + Vector3.UP * 2.2,
							"%s down" % String(spell.stat).capitalize())
						n += 1
				ctrl.combo_feedback.emit("%s: %d enem%s" % [spell.display_name, n, "y" if n == 1 else "ies"])
			else:
				for v in _in_radius(player.global_position, r, spell.max_targets, player):
					SpellFx.spike(world, v.global_position, color, 0.3)
					_damage(ctrl, item, spell, level, hard, v, 1.0)
		SpellDef.Shape.GRAVITY_PIT:
			var center := _area_center(player, target_alive, direction, spell.reach)
			SpellFx.burst(world, center + Vector3.UP * 0.3, r, color, 2.0)
			for i in 8:
				_later(player, 0.25 * i, func():
					for v in _in_radius(center, r * 1.3, spell.max_targets, player):
						var enemy := v as Enemy
						if enemy:
							var pull := center - enemy.global_position
							pull.y = 0.0
							enemy.apply_pull(pull.limit_length(1.0) * 6.0)
						_damage(ctrl, item, spell, level, hard, v, 1.0 / 8.0))
		SpellDef.Shape.CHANNEL:
			channel_tick(ctrl, item, attack, hard, direction)
		SpellDef.Shape.SELF:
			_self_spell(ctrl, item, spell, level, hard, direction)


## One tick of a Sustained spell: everything in the cone in front.
static func channel_tick(ctrl: CombatController, item: WeaponData, attack: AttackData, hard: bool,
		direction: Vector3) -> void:
	var spell := attack.spell
	var player := ctrl.get_parent() as Player
	SpellFx.cone(player.get_parent(), player.global_position, direction, spell.reach, spell.cone_deg,
		_color(spell), CHANNEL_TICK)
	for v in _in_cone(player.global_position, direction, spell.reach, spell.cone_deg, 10, player):
		_damage(ctrl, item, spell, attack.spell_level, false, v, 1.0, 0.5)


static func _self_spell(ctrl: CombatController, item: WeaponData, spell: SpellDef, level: int, hard: bool,
		direction: Vector3) -> void:
	var player := ctrl.get_parent() as Player
	var world := player.get_parent()
	var color := _color(spell)
	var support := item.support_power if item else 1.0
	var boost := (1.25 if hard else 1.0) * support
	match spell.kind:
		SpellDef.Kind.BUFF:
			SpellFx.ring(world, player.global_position, PARTY_RADIUS * 0.5, color)
			for seeker in _party(player, spell.radius):
				seeker.status.apply_modifier(spell.stat, SpellBook.buff_fraction(level) * boost, SpellBook.buff_seconds(level))
				DamageNumber.spawn_text(world, seeker.global_position + Vector3.UP * 2.3,
					"%s +%d%%" % [String(spell.stat).capitalize(), roundi(SpellBook.buff_fraction(level) * boost * 100.0)])
		SpellDef.Kind.AURA:
			var aura := SpellAura.create(ctrl, item, spell, level, hard)
			player.add_child(aura)
			ctrl.combo_feedback.emit(spell.display_name)
		SpellDef.Kind.HEAL:
			var r := spell.radius + spell.radius_growth * (level - 1)
			SpellFx.ring(world, player.global_position, r, Color(0.5, 1.0, 0.6))
			var amount := (ctrl.stats.soul * player.status.stat_scale(&"soul") + spell.power(level) * 4.0) / 5.0 * boost
			for seeker in _party(player, r):
				var restored: float = seeker.health.heal(amount)
				if restored > 0.0:
					DamageNumber.spawn_text(world, seeker.global_position + Vector3.UP * 2.0, "+%d" % roundi(restored))
		SpellDef.Kind.CURE:
			var r := spell.radius + spell.radius_growth * (level - 1)
			SpellFx.ring(world, player.global_position, r, Color(0.7, 1.0, 1.0))
			for seeker in _party(player, r):
				seeker.status.cure(level)
				DamageNumber.spawn_text(world, seeker.global_position + Vector3.UP * 2.2, "Cured")
		SpellDef.Kind.TELEPORTAL:
			var map_level := Scope.level(player)
			var here := Maps.id_of(map_level) if map_level else ""
			if here == SHIP_SCENE:
				ctrl.combo_feedback.emit("Already on Nomad-2")
				return
			# PSO's telepipe: one per Seeker, both ends stay open until someone
			# comes back through the Nomad-2 end (Teleportals).
			var flat := Vector3(direction.x, 0.0, direction.z).normalized()
			Teleportals.open(player, player.global_position + flat * 2.5)
			ctrl.combo_feedback.emit("Teleportal open")
		SpellDef.Kind.REVIVE:
			var revived := 0
			for node in Scope.group(player, "player"):
				var seeker := node as Player
				if seeker and seeker != player and seeker.health.is_dead() \
						and seeker.global_position.distance_to(player.global_position) <= spell.radius:
					seeker.revive(SpellBook.revive_fraction(level))
					revived += 1
			ctrl.combo_feedback.emit("Revived %d" % revived if revived > 0 else "No one to revive")
		SpellDef.Kind.TRAP:
			var flat := Vector3(direction.x, 0.0, direction.z).normalized()
			var at := player.global_position + (flat * 4.0 if hard else Vector3.ZERO)
			Trap.place(ctrl, item, spell, level, hard, at)


## The ship, for Teleportal. The gym stands in until the hub exists.
const SHIP_SCENE := "res://scenes/hub.tscn"  # Nomad-2 (Part 8)


# --- Damage ---------------------------------------------------------------------------

## PSO technique damage for one target, with the casting item's power.
static func damage_amount(ctrl: CombatController, item: WeaponData, spell: SpellDef, level: int, hard: bool) -> float:
	var player := ctrl.get_parent() as Player
	var sol := ctrl.stats.soul * (player.status.stat_scale(&"soul") if player and player.status else 1.0)
	var power := item.spell_power if item else 1.0
	return (sol + spell.power(level)) / 5.0 * power * (HARD_POWER if hard else 1.0)


static func _damage(ctrl: CombatController, item: WeaponData, spell: SpellDef, level: int, hard: bool,
		target: Node3D, fraction: float, status_scale: float = 1.0) -> float:
	if not _alive(target):
		return 0.0
	var info := DamageInfo.new()
	info.amount = damage_amount(ctrl, item, spell, level, hard) * fraction
	info.damage_type = spell.element
	info.kind = DamageInfo.Kind.MAGIC
	info.status_power = (1.0 if spell.status_ok else 0.0) * status_scale
	info.is_hard = hard
	info.accuracy = -1.0  # spells never miss
	info.weapon = item
	info.source = ctrl.get_parent()
	info.hit_position = CameraRig.get_lock_point(target)
	var dealt := HitResolver.apply(target, info, ctrl.get_parent() as Node3D)
	ctrl.report_hit(target, info, dealt)
	return dealt


static func _projectile(ctrl: CombatController, item: WeaponData, attack: AttackData, hard: bool,
		from: Vector3, direction: Vector3, radius: float) -> Projectile:
	var spell := attack.spell
	var level := attack.spell_level
	var shot := AttackData.new()
	shot.projectile_speed = spell.speed + spell.speed_growth * (level - 1)
	shot.projectile_radius = radius * (1.25 if hard else 1.0)
	shot.projectile_range = spell.reach + 6.0
	shot.projectile_pierce = spell.pierce
	var info := DamageInfo.new()
	info.amount = damage_amount(ctrl, item, spell, level, hard)
	info.damage_type = spell.element
	info.kind = DamageInfo.Kind.MAGIC
	info.status_power = 1.0 if spell.status_ok else 0.0
	info.is_hard = hard
	info.accuracy = -1.0
	info.weapon = item
	info.source = ctrl.get_parent()
	var player := ctrl.get_parent() as Player
	return Projectile.spawn(player.get_parent(), from, direction, shot, info, _color(spell), player, ctrl)


# --- Targets ----------------------------------------------------------------------------

static func _alive(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	var health := Health.find(node)
	return health != null and not health.is_dead()


static func _targets(tree_node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in Scope.group(tree_node, "lockable"):
		var n := node as Node3D
		if n and n.is_visible_in_tree() and _alive(n):
			out.append(n)
	# Confused casters (Grayson 2026-11-12) hit the other Seekers too.
	var caster := tree_node as Player
	if caster and caster.status and caster.status.is_confused():
		for node in Scope.group(tree_node, "player"):
			var seeker := node as Player
			if seeker and seeker != caster and not seeker.downed and _alive(seeker):
				out.append(seeker)
	return out


## `from`: a node on the map to search (party members can be on different
## maps; see Scope). Defaults to the window's own level.
static func _in_radius(center: Vector3, radius: float, limit: int, from: Node = null) -> Array[Node3D]:
	var tree := Engine.get_main_loop() as SceneTree
	var found: Array[Node3D] = []
	for n in _targets(from if from and from.is_inside_tree() else tree.root):
		var d := n.global_position - center
		d.y = 0.0
		if d.length() <= radius:
			found.append(n)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	return found.slice(0, limit)


static func _in_cone(origin: Vector3, direction: Vector3, reach: float, cone_deg: float, limit: int, from: Node = null) -> Array[Node3D]:
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	var found: Array[Node3D] = []
	for n in _in_radius(origin, reach, 99, from):
		var to := n.global_position - origin
		to.y = 0.0
		if to.length() < 0.5 or rad_to_deg(flat.angle_to(to.normalized())) <= cone_deg * 0.5:
			found.append(n)
	return found.slice(0, limit)


static func _nearest_ahead(player: Node3D, direction: Vector3, reach: float, cone_deg: float) -> Node3D:
	var list := _in_cone(player.global_position, direction, reach, cone_deg, 1, player)
	return list[0] if not list.is_empty() else null


static func _nearest_to(point: Vector3, radius: float, exclude: Array[Node3D], from: Node = null) -> Node3D:
	for n in _in_radius(point, radius, 99, from):
		if not n in exclude:
			return n
	return null


static func _area_center(player: Node3D, target: Node3D, direction: Vector3, reach: float) -> Vector3:
	if target:
		return target.global_position
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	return player.global_position + flat * reach * NO_TARGET_REACH


## Seekers in range (each has .health and .status). A confused caster's
## buffs, heals and cures land on nearby enemies too (Grayson 2026-11-12).
static func _party(player: Player, radius: float) -> Array:
	var list: Array = []
	for node in Scope.group(player, "player"):
		var seeker := node as Player
		if seeker and not seeker.health.is_dead() \
				and seeker.global_position.distance_to(player.global_position) <= radius:
			list.append(seeker)
	if player.status.is_confused():
		for node in Scope.group(player, "enemies"):
			var enemy := node as Enemy
			if enemy and not enemy.is_dead() \
					and enemy.global_position.distance_to(player.global_position) <= radius:
				list.append(enemy)
	return list


static func _color(spell: SpellDef) -> Color:
	if spell.element == Element.Type.GENERIC:
		return Color(0.85, 0.85, 0.9)
	return Element.color_of(spell.element)


## Runs a callable after a delay (0 = now), tied to the caster's tree.
static func _later(owner: Node, seconds: float, fn: Callable) -> void:
	if seconds <= 0.0:
		fn.call()
		return
	owner.get_tree().create_timer(seconds, false).timeout.connect(fn)
