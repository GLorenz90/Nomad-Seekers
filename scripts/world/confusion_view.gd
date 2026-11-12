class_name ConfusionView
extends Node3D
## What a confused Seeker sees (Grayson 2026-11-12): every enemy and every
## partner is drawn as the same drifting ghost, so friend and foe can't be told
## apart. The HUD adds a haze (DebugHud).
##
## How: enemies and Seekers put their meshes on their own visual layers
## (ENEMY_BIT, seeker_bit), the confused Seeker's camera stops drawing those
## layers (CameraRig.hidden_layers, copied by split-screen panes), and ghosts
## are drawn on that Seeker's marker layer, which only their camera sees.
## Lives under TargetMarkers, like DarkVision.

## Visual layer bits: 15 for enemies, 16-19 for Seekers by controller slot.
## (11-14 are the per-Seeker marker layers; SeekerPane.)
const ENEMY_BIT := 1 << 14
const SEEKER_BIT_BASE := 15
## Every ghost looks the same, whatever it stands for.
const GHOST_HEIGHT := 1.7
const GHOST_RADIUS := 0.55
const GHOST_COLOR := Color(0.78, 0.74, 0.92, 0.55)

var seeker: Player
var _ghosts := {}  # creature -> MeshInstance3D
var _material: StandardMaterial3D
var _mesh: CapsuleMesh
var _time := 0.0


static func seeker_bit(slot: int) -> int:
	return 1 << (SEEKER_BIT_BASE + clampi(slot, 0, 3))


## Every visual under a creature goes on its layer bit, so a confused camera
## can drop it.
static func tag_layers(node: Node, bits: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = bits
	for child in node.get_children():
		tag_layers(child, bits)


func _init() -> void:
	top_level = true
	_mesh = CapsuleMesh.new()
	_mesh.radius = GHOST_RADIUS
	_mesh.height = GHOST_HEIGHT
	_material = StandardMaterial3D.new()
	_material.albedo_color = GHOST_COLOR
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.rim_enabled = false
	_material.render_priority = 0
	_mesh.material = _material


func setup(who: Player) -> void:
	seeker = who


func is_active() -> bool:
	return seeker != null and is_instance_valid(seeker) and seeker.status != null \
		and seeker.status.is_confused() and not seeker.health.is_dead()


func ghost_count() -> int:
	return _ghosts.size()


func _process(delta: float) -> void:
	_time += delta
	var rig := seeker.camera_rig if seeker and is_instance_valid(seeker) else null
	if not is_active():
		if rig:
			rig.hidden_layers = 0
		_clear()
		return
	var own := seeker_bit(maxi(seeker.input.slot, 0))
	var hidden := ENEMY_BIT
	for slot in 4:
		if seeker_bit(slot) != own:
			hidden |= seeker_bit(slot)
	if rig:
		rig.hidden_layers = hidden
	var layer := (get_parent() as TargetMarkers).render_layers if get_parent() is TargetMarkers else 1
	var seen := {}
	for node in Scope.group(seeker, "enemies"):
		var enemy := node as Enemy
		if enemy and not enemy.is_dead():
			tag_layers(enemy, ENEMY_BIT)
			seen[enemy] = true
	for node in Scope.group(seeker, "player"):
		var other := node as Player
		if other == null:
			continue
		tag_layers(other, seeker_bit(maxi(other.input.slot, 0)))
		if other != seeker and not other.health.is_dead():
			seen[other] = true
	for creature in _ghosts.keys():
		if not seen.has(creature) or not is_instance_valid(creature):
			(_ghosts[creature] as Node).queue_free()
			_ghosts.erase(creature)
	for creature in seen:
		var ghost: MeshInstance3D = _ghosts.get(creature)
		if ghost == null:
			ghost = MeshInstance3D.new()
			ghost.mesh = _mesh
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.top_level = true
			add_child(ghost)
			_ghosts[creature] = ghost
		ghost.layers = layer
		var phase := float(creature.get_instance_id() % 97)
		var wobble := 1.0 + 0.08 * sin(_time * 3.1 + phase)
		ghost.scale = Vector3(wobble, 2.0 - wobble, wobble)
		ghost.global_position = (creature as Node3D).global_position + Vector3.UP * (GHOST_HEIGHT * 0.5 + 0.15 * sin(_time * 1.7 + phase))


func _clear() -> void:
	for ghost in _ghosts.values():
		(ghost as Node).queue_free()
	_ghosts.clear()
