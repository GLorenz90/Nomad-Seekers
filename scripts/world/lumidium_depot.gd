class_name LumidiumDepot
extends Node3D
## Lumidium depot (Grayson, 2026-11-10): where a Seeker chooses to bank the
## Lumidium in their satchel. Separate from teleporters, which no longer bank
## anything. Every area has one at its start and its exit, and Nomad-2 has one
## by the bank. A deposits everything carried into the bank (up to
## Inventory.BANK_LUMIDIUM_MAX), where it's safe from death and can be
## withdrawn at the bank's Resources counter to trade.

signal deposited(seeker: Player, amount: int)

const COLOR := Color(0.65, 0.5, 1.0)
const INTERACT_RANGE := 1.8

var _crystal: MeshInstance3D
var _age := 0.0


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("lumidium_depots")
	var base := MeshInstance3D.new()
	var plinth := CylinderMesh.new()
	plinth.top_radius = 0.45
	plinth.bottom_radius = 0.6
	plinth.height = 0.9
	plinth.radial_segments = 6
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.3, 0.3, 0.38)
	plinth.material = stone
	base.mesh = plinth
	base.position.y = 0.45
	add_child(base)
	_crystal = MeshInstance3D.new()
	var gem := PrismMesh.new()
	gem.size = Vector3(0.45, 0.7, 0.45)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = COLOR
	glow.emission_enabled = true
	glow.emission = COLOR
	glow.emission_energy_multiplier = 1.4
	gem.material = glow
	_crystal.mesh = gem
	_crystal.position.y = 1.35
	add_child(_crystal)
	var label := Label3D.new()
	label.text = "Lumidium Depot"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 8
	label.modulate = Color(0.85, 0.75, 1.0)
	label.position.y = 2.2
	add_child(label)


func _process(delta: float) -> void:
	_age += delta
	_crystal.rotation.y = _age * 0.8
	_crystal.position.y = 1.35 + sin(_age * 2.0) * 0.06


# --- Interaction (A) ---------------------------------------------------------------

func interact_point() -> Vector3:
	return global_position


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact(_seeker: Player) -> bool:
	return true


func interact_prompt() -> String:
	return "Deposit Lumidium in the bank"


func interact(seeker: Player) -> void:
	if seeker.carried_lumidium_total() <= 0:
		seeker.combat.combo_feedback.emit("No Lumidium to deposit")
		return
	var amount := seeker.deposit_lumidium()
	if amount > 0:
		deposited.emit(seeker, amount)
	elif seeker.carried_lumidium_total() > 0:
		seeker.combat.combo_feedback.emit("The bank can't hold more Lumidium (%d)" % Inventory.BANK_LUMIDIUM_MAX)
