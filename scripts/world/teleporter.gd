class_name Teleporter
extends Area3D
## Teleporter pad (North Star §7.1). Standing on it deposits every carried
## Lumidium into the Seeker's bank, where it's safe from death. The trip back
## to town arrives with the hub (later part).

signal deposited(seeker: Player, amount: int)

const PLAYER_MASK := 2


func _ready() -> void:
	add_to_group("teleporters")
	collision_layer = 0
	collision_mask = PLAYER_MASK
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
	cyl.height = 1.5
	shape.shape = cyl
	shape.position.y = 0.75
	add_child(shape)
	var pad := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.4
	mesh.bottom_radius = 1.5
	mesh.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.2
	mesh.material = mat
	pad.mesh = mesh
	pad.position.y = 0.06
	add_child(pad)
	var label := Label3D.new()
	label.text = "Teleporter\n(deposit Lumidium)"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 8
	label.position.y = 2.2
	add_child(label)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var seeker := body as Player
	if seeker == null:
		return
	var amount := seeker.deposit_lumidium()
	if amount > 0:
		deposited.emit(seeker, amount)
