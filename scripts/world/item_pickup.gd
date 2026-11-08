class_name ItemPickup
extends Area3D
## A dropped item: Oro, a consumable, a weapon or Lumidium. Walk over it to
## collect. Drops are instanced per player (North Star §7.2), so this one is
## only for the Seeker that rolled it.

const PLAYER_MASK := 2
## Spiral Knights-style magnet: pickups drift to a Seeker this close.
const MAGNET_RANGE := 3.0
const MAGNET_SPEED := 9.0

## {"oro": int} / {"consumable": StringName} / {"weapon": WeaponData} / {"lumidium": StringName}
var contents: Dictionary = {}
var _spin: Node3D
var _age := 0.0


static func create(drop: Dictionary) -> ItemPickup:
	var p := ItemPickup.new()
	p.contents = drop
	return p


func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_MASK
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	shape.shape = sphere
	shape.position.y = 0.6
	add_child(shape)
	_spin = Node3D.new()
	_spin.position.y = 0.6
	add_child(_spin)
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color()
	mat.emission_enabled = true
	mat.emission = color()
	mat.emission_energy_multiplier = 0.8
	var shape_mesh: PrimitiveMesh
	if contents.has("weapon"):
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.12, 0.8)
		shape_mesh = box
	elif contents.has("lumidium"):
		var prism := PrismMesh.new()
		prism.size = Vector3(0.35, 0.5, 0.35)
		shape_mesh = prism
	else:
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.2
		sphere_mesh.height = 0.4
		shape_mesh = sphere_mesh
	shape_mesh.material = mat
	mesh.mesh = shape_mesh
	_spin.add_child(mesh)
	var label := Label3D.new()
	label.text = describe()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 26
	label.outline_size = 8
	label.modulate = color().lightened(0.3)
	label.position.y = 1.3
	add_child(label)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_age += delta
	var seeker := get_tree().get_first_node_in_group("player") as Node3D
	if seeker and _age > 0.4:
		var to := seeker.global_position - global_position
		if to.length() < MAGNET_RANGE:
			global_position += to.normalized() * minf(MAGNET_SPEED * delta, to.length())
	_spin.rotation.y += delta * 2.0
	_spin.position.y = 0.6 + sin(_age * 3.0) * 0.08


func describe() -> String:
	if contents.has("oro"):
		return "%d Oro" % int(contents.oro)
	if contents.has("consumable"):
		return String(Inventory.CONSUMABLES.get(contents.consumable, contents.consumable))
	if contents.has("weapon"):
		return (contents.weapon as WeaponData).display_name
	if contents.has("lumidium"):
		return "%s Lumidium" % String(contents.lumidium).capitalize()
	return "?"


func color() -> Color:
	if contents.has("oro"):
		return Color(1.0, 0.8, 0.2)
	if contents.has("consumable"):
		return Color(0.4, 1.0, 0.6)
	if contents.has("weapon"):
		var w := contents.weapon as WeaponData
		return Color(1.0, 0.35, 0.9) if w.rare else Color(0.6, 0.8, 1.0)
	if contents.has("lumidium"):
		return Inventory.LUMIDIUM_COLORS.get(contents.lumidium, Color.WHITE)
	return Color.WHITE


func _on_body_entered(body: Node) -> void:
	var seeker := body as Player
	if seeker == null or seeker.save == null or seeker.health.is_dead():
		return
	collect(seeker)


## Gives the contents to the Seeker and removes the pickup.
func collect(seeker: Player) -> void:
	var inv := seeker.save.inventory
	var text := describe()
	if contents.has("oro"):
		inv.oro += int(contents.oro)
		text = "+" + text
	elif contents.has("consumable"):
		inv.add_consumable(contents.consumable)
		text = "+1 " + text
	elif contents.has("weapon"):
		var w := contents.weapon as WeaponData
		inv.add_weapon(w)
		text = "Found %s%s" % [w.display_name, "  (RARE)" if w.rare else ""]
	elif contents.has("lumidium"):
		seeker.add_lumidium(contents.lumidium)
		queue_free()
		return
	seeker.item_collected.emit(text)
	queue_free()
