class_name RoomHazard
extends Node3D
## A room hazard (Part 11, Grayson 2026-11-09: "hazards and buttons like
## PSO"). It covers one or more boxes (`zones`, so one hazard can span
## several rooms or a room and its corridor) and is switched off or on by a
## button (SwitchGroup -> switch_action).
##
## - POISON_MIST: drains 2% of max HP a second from anyone inside, Goluman
##   included (Grayson 2026-11-09: it isn't the Poisoned status). Like PSO's
##   poison it never takes you below 1 HP (Claude's pick); enemies do the rest.
## - DARKNESS: the screen goes dark around you (HUD vignette) while you're
##   inside, and the room's own volume reads black from outside.

enum Kind { POISON_MIST, DARKNESS }

const COLORS := {Kind.POISON_MIST: Color(0.45, 0.85, 0.25, 0.16), Kind.DARKNESS: Color(0.0, 0.0, 0.02, 0.6)}
## Drain per second as a fraction of max HP, applied every POISON_TICK.
const POISON_DRAIN := 0.02
const POISON_TICK := 0.5

@export var kind: Kind = Kind.POISON_MIST
@export var active := true
## Local boxes the hazard covers.
@export var zones: Array[AABB] = []

var _inside := {}  # Player -> number of zones it's in
var _visuals: Array[MeshInstance3D] = []
var _tick := 0.0


func _ready() -> void:
	add_to_group("room_hazards")
	for zone in zones:
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2  # Seekers
		area.monitoring = true
		area.position = zone.get_center()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = zone.size
		shape.shape = box
		area.add_child(shape)
		area.body_entered.connect(_on_entered)
		area.body_exited.connect(_on_exited)
		add_child(area)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = zone.size - Vector3(0.05, 0.05, 0.05)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS[kind]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.material = mat
		mesh.mesh = bm
		mesh.position = zone.get_center()
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		_visuals.append(mesh)
	set_active(active)


func set_active(on: bool) -> void:
	active = on
	for v in _visuals:
		v.visible = on


## Buttons: "disable", "enable" or "toggle".
func switch_action(action: String) -> void:
	match action:
		"disable":
			set_active(false)
		"enable":
			set_active(true)
		"toggle":
			set_active(not active)


func is_inside(seeker: Player) -> bool:
	return _inside.has(seeker)


## True when an active darkness hazard covers this Seeker (the HUD asks).
static func dark_for(seeker: Player) -> bool:
	for node in seeker.get_tree().get_nodes_in_group("room_hazards"):
		var h := node as RoomHazard
		if h.active and h.kind == Kind.DARKNESS and h.is_inside(seeker):
			return true
	return false


func _on_entered(body: Node) -> void:
	if body is Player:
		_inside[body] = int(_inside.get(body, 0)) + 1
		if kind == Kind.POISON_MIST and active:
			_poison(body as Player)


func _on_exited(body: Node) -> void:
	if body is Player and _inside.has(body):
		_inside[body] = int(_inside[body]) - 1
		if int(_inside[body]) <= 0:
			_inside.erase(body)


func _physics_process(delta: float) -> void:
	if not active or kind != Kind.POISON_MIST or _inside.is_empty():
		return
	_tick += delta
	if _tick < POISON_TICK:
		return
	_tick = 0.0
	for seeker in _inside.keys():
		if is_instance_valid(seeker):
			_poison(seeker)


func _poison(seeker: Player) -> void:
	var health := seeker.health
	if health.is_dead() or health.hp <= 1.0:
		return
	var info := DamageInfo.new()
	info.amount = minf(health.max_hp * POISON_DRAIN * POISON_TICK, health.hp - 1.0)
	info.accuracy = -1.0
	info.hit_position = seeker.global_position + Vector3.UP * 1.6
	health.take_damage(info)
