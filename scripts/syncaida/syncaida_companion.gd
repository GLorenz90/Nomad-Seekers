class_name SyncAIDaCompanion
extends Node3D
## The paired SyncAIDa in the field: floats over the Seeker's shoulder, adds
## its stats to the Seeker's, fills its Sync Burst gauge from damage dealt and
## taken, and fires the active burst on L3 (sync_burst) when full.
##
## Created by the Player. Data lives in SaveData.syncaida (SyncAIDaData).

signal burst_fired(burst: int)
signal fed(events: Array[String])

const GAUGE_MAX := 100.0
## Gauge per point of damage dealt / taken.
const GAUGE_PER_DEALT := 0.1
const GAUGE_PER_TAKEN := 0.35
const NOVA_RADIUS := 8.0
const PARTY_RADIUS := 10.0
const AEGIS_SECONDS := 15.0
## Hover point relative to the Seeker (x right, y up, +z behind).
const SHOULDER_OFFSET := Vector3(0.6, 1.7, 0.35)

var player: Player
var data: SyncAIDaData
## Seeker stat points currently added by this SyncAIDa ({&"def": n, ...}).
var _applied := {&"def": 0.0, &"str": 0.0, &"dex": 0.0, &"sol": 0.0}
var _body: MeshInstance3D
var _material: StandardMaterial3D
var _age := 0.0
var _shown_stage := -1


func _ready() -> void:
	top_level = true
	_body = MeshInstance3D.new()
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 0.9
	_material.roughness = 0.3
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)


func setup(seeker: Player) -> void:
	player = seeker
	player.combat.hit_landed.connect(_on_hit_landed)
	player.health.damaged.connect(_on_damaged)


## Pairs with a SyncAIDa (null = none).
func pair(new_data: SyncAIDaData) -> void:
	data = new_data
	apply_stats()
	visible = data != null
	_shown_stage = -1
	_refresh_look()


## Debug: resets the paired SyncAIDa to its base and re-applies its bonus.
func reset_to_base() -> void:
	if data == null:
		return
	data.reset_to_base()
	apply_stats()
	_shown_stage = -1
	_refresh_look()


## Moves the stat bonus to the current data's values.
func apply_stats() -> void:
	var target := data.bonuses() if data else {&"def": 0.0, &"str": 0.0, &"dex": 0.0, &"sol": 0.0}
	var s := player.combat.stats
	s.defense += float(target[&"def"]) - float(_applied[&"def"])
	s.strength += float(target[&"str"]) - float(_applied[&"str"])
	s.dexterity += float(target[&"dex"]) - float(_applied[&"dex"])
	s.soul += float(target[&"sol"]) - float(_applied[&"sol"])
	_applied = target


func gauge() -> float:
	return data.gauge if data else 0.0


func is_ready() -> bool:
	return data != null and data.gauge >= GAUGE_MAX and data.active() >= 0


func add_gauge(amount: float) -> void:
	if data:
		data.gauge = clampf(data.gauge + amount, 0.0, GAUGE_MAX)


## Feeds an item from the Seeker's inventory (consumable) or bank (Lumidium).
## free: debug feeding that doesn't use anything up.
func feed(item: StringName, free: bool = false) -> Array[String]:
	var none: Array[String] = []
	if data == null or not SyncAIDaData.can_eat(item):
		return none
	if not free:
		var inv := player.save.inventory
		if Inventory.CONSUMABLES.has(item):
			if not inv.use_consumable(item):
				return none
		elif int(inv.lumidium.get(item, 0)) > 0:
			inv.lumidium[item] = int(inv.lumidium[item]) - 1
		else:
			return none
	var events := data.feed(item)
	if events.is_empty():
		events.append("fed")
	apply_stats()
	_refresh_look()
	fed.emit(events)
	return events


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if Input.is_action_just_pressed("sync_burst"):
		fire()
	_age += delta
	# Hover just over and slightly behind the right shoulder, low enough to keep
	# the view clear. (Twin SyncAIDa will mirror this on the left: x -> -x.)
	var goal := player.global_transform * Vector3(SHOULDER_OFFSET.x, SHOULDER_OFFSET.y + sin(_age * 2.4) * 0.08,
		SHOULDER_OFFSET.z)
	global_position = global_position.lerp(goal, 1.0 - exp(-8.0 * delta))
	_body.rotation.y += delta * 1.5
	if is_ready():
		_material.emission_energy_multiplier = 0.9 + (sin(_age * 8.0) * 0.5 + 0.5) * 2.0
	else:
		_material.emission_energy_multiplier = 0.9


## Fires the active Sync Burst if the gauge is full. Returns true on success.
func fire() -> bool:
	if not is_ready():
		if data == null:
			player.combat.combo_feedback.emit("Choose a SyncAIDa in the menu")
		elif data.active() < 0:
			player.combat.combo_feedback.emit("No Sync Burst yet (level 10)")
		return false
	var burst := data.active()
	data.gauge = 0.0
	var lv_scale := 1.0 + data.level() / 50.0
	match burst:
		SyncAIDaData.Burst.LUMEN_NOVA:
			_lumen_nova(lv_scale)
		SyncAIDaData.Burst.AEGIS_PULSE:
			for seeker in _party():
				seeker.combat.apply_aegis(AEGIS_SECONDS)
		SyncAIDaData.Burst.MENDING_BLOOM:
			for seeker in _party():
				seeker.health.heal(seeker.health.max_hp * 0.5)
				seeker.combat.lp = minf(seeker.combat.lp + 30.0, seeker.combat.stats.max_lp)
				seeker.status.clear_all()
	player.grant_invulnerability(0.8)
	player.combat.combo_feedback.emit(SyncAIDaData.BURST_NAMES[burst] + "!")
	_flash(SyncAIDaData.BURST_NAMES[burst], NOVA_RADIUS if burst == SyncAIDaData.Burst.LUMEN_NOVA else PARTY_RADIUS)
	burst_fired.emit(burst)
	return true


func _lumen_nova(lv_scale: float) -> void:
	var stat := player.combat.stats.soul
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.global_position.distance_to(player.global_position) > NOVA_RADIUS:
			continue
		var info := DamageInfo.new()
		info.amount = 80.0 * lv_scale * (1.0 + stat / 100.0)
		info.damage_type = Element.Type.LIGHT
		info.kind = DamageInfo.Kind.MAGIC
		info.status_power = 2.0
		info.is_hard = true
		info.source = player
		info.hit_position = enemy.global_position + Vector3.UP * 1.2
		HitResolver.apply(enemy, info, player)


func _party() -> Array[Player]:
	var list: Array[Player] = []
	for node in get_tree().get_nodes_in_group("player"):
		var seeker := node as Player
		if seeker and seeker.global_position.distance_to(player.global_position) <= PARTY_RADIUS:
			list.append(seeker)
	return list


func _on_hit_landed(_target: Node, _info: DamageInfo, amount: float) -> void:
	add_gauge(amount * GAUGE_PER_DEALT)


func _on_damaged(_info: DamageInfo, amount: float) -> void:
	add_gauge(amount * GAUGE_PER_TAKEN)


## Shape grows with each evolution stage; color follows the strongest stat.
func _refresh_look() -> void:
	if data == null:
		return
	_material.albedo_color = data.color()
	_material.emission = data.color()
	if _shown_stage == data.stage:
		return
	_shown_stage = data.stage
	var mesh: PrimitiveMesh
	match data.stage:
		0:
			var sphere := SphereMesh.new()
			sphere.radius = 0.16
			sphere.height = 0.32
			mesh = sphere
		1:
			var prism := PrismMesh.new()
			prism.size = Vector3(0.32, 0.38, 0.32)
			mesh = prism
		2:
			var torus := TorusMesh.new()
			torus.inner_radius = 0.12
			torus.outer_radius = 0.26
			mesh = torus
		_:
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.16
			capsule.height = 0.6
			mesh = capsule
	mesh.material = _material
	_body.mesh = mesh
	if data.stage >= 2:
		_body.rotation.x = 0.6


func _flash(text: String, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.3
	torus.outer_radius = radius
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := data.color() if data else Color.WHITE
	c.a = 0.7
	mat.albedo_color = c
	torus.material = mat
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_parent().add_child(ring)
	ring.global_position = player.global_position + Vector3.UP * 0.3
	ring.scale = Vector3.ONE * 0.1
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.tween_callback(ring.queue_free)
	DamageNumber.spawn_text(player.get_parent(), player.global_position + Vector3.UP * 2.6, text)
