class_name ItemPickup
extends Area3D
## A dropped item. Oro and Lumidium are picked up by walking over them (and
## drift to a Seeker close by); everything else waits for A, since the pack
## has a limit (Grayson, 2026-11-09). Drops are instanced per player (North
## Star §7.2), so this one is only for the Seeker that rolled it.
##
## Stacks (Part 9): consumables, materials and Lumidium can lie in a stack
## ("count"); picking one up takes only as many as fit and leaves the rest.
## Items a Seeker drops (for trading or to make room) always wait for A, Oro
## and Lumidium included, so walking over them doesn't take them back.

const PLAYER_MASK := 2
## Spiral Knights-style magnet: pickups drift to a Seeker this close.
const MAGNET_RANGE := 3.0
const MAGNET_SPEED := 9.0

## {"oro": int} / {"consumable": StringName, "count": int} / {"material": ...}
## / {"weapon": WeaponData} / {"armor": ArmorData} / {"unit": StringName}
## / {"lumidium": StringName, "count": int} / {"disc": {"id", "level"}}
var contents: Dictionary = {}
## Dropped from a Seeker's pack or satchel: never collected on touch.
var dropped := false
var _label: Label3D
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
	elif contents.has("armor"):
		var plate := BoxMesh.new()
		plate.size = Vector3(0.45, 0.45, 0.15)
		shape_mesh = plate
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
	_label = Label3D.new()
	_label.text = describe()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 26
	_label.outline_size = 8
	_label.modulate = color().lightened(0.3)
	_label.position.y = 1.3
	add_child(_label)
	body_entered.connect(_on_body_entered)
	if not is_automatic():
		add_to_group("interactables")


## Oro and Lumidium are collected on touch; other items (and anything a
## Seeker dropped) need A.
func is_automatic() -> bool:
	return not dropped and (contents.has("oro") or contents.has("lumidium"))


## Puts a stack or item from a Seeker's pack or satchel on the ground in
## front of them (PSO-style trading and making room).
static func drop_from(seeker: Player, drop: Dictionary) -> ItemPickup:
	var p := create(drop)
	p.dropped = true
	seeker.get_parent().add_child(p)
	var ahead := -seeker.global_transform.basis.z
	ahead.y = 0.0
	var spot := seeker.global_position + ahead.normalized() * 1.3
	spot += Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	p.global_position = spot
	return p


## How many are in this stack (1 for single items; Oro uses its own amount).
func amount() -> int:
	return int(contents.get("count", 1))


## Stackable pickups: the consumable or material id ("" otherwise).
func stack_id() -> StringName:
	if contents.has("consumable"):
		return StringName(contents.consumable)
	if contents.has("material"):
		return StringName(contents.material)
	return &""


## How many of this the Seeker could take right now.
func room_for(seeker: Player) -> int:
	if seeker.save == null:
		return 0
	if contents.has("oro"):
		return mini(int(contents.oro), Inventory.ORO_MAX - seeker.save.inventory.oro)
	if contents.has("lumidium"):
		return mini(amount(), seeker.satchel_room())
	if stack_id() != &"":
		return mini(amount(), seeker.save.stack_room(stack_id()))
	if contents.has("disc") and not seeker.disc_needs_slot(StringName(contents.disc.id), int(contents.disc.level)):
		return 1  # learned or sold on the spot
	return 1 if seeker.save.pack_free() > 0 else 0


func _process(delta: float) -> void:
	_age += delta
	var seeker := Player.nearest(self, global_position) as Node3D
	if seeker and _age > 0.4 and is_automatic() and seeker is Player and room_for(seeker as Player) > 0:
		var to := seeker.global_position - global_position
		if to.length() < MAGNET_RANGE:
			global_position += to.normalized() * minf(MAGNET_SPEED * delta, to.length())
	_spin.rotation.y += delta * 2.0
	_spin.position.y = 0.6 + sin(_age * 3.0) * 0.08


func describe() -> String:
	if contents.has("oro"):
		return "%d Oro" % int(contents.oro)
	if stack_id() != &"":
		var n := Inventory.item_name(stack_id())
		return n if amount() == 1 else "%s x%d" % [n, amount()]
	if contents.has("weapon"):
		return (contents.weapon as WeaponData).display_name
	if contents.has("armor"):
		return (contents.armor as ArmorData).display_name
	if contents.has("unit"):
		return UnitBook.display_name(StringName(contents.unit))
	if contents.has("lumidium"):
		return "%s%s Lumidium" % ["" if amount() == 1 else "%d " % amount(), String(contents.lumidium).capitalize()]
	if contents.has("disc"):
		var spell := SpellBook.get_spell(StringName(contents.disc.id))
		return "Disc: %s %d" % [spell.display_name if spell else "?", int(contents.disc.level)]
	return "?"


func color() -> Color:
	if contents.has("oro"):
		return Color(1.0, 0.8, 0.2)
	if contents.has("consumable"):
		return Color(0.4, 1.0, 0.6)
	if contents.has("material"):
		return Color(1.0, 0.6, 0.3)
	if contents.has("weapon"):
		var w := contents.weapon as WeaponData
		return Color(1.0, 0.35, 0.9) if w.rare else Color(0.6, 0.8, 1.0)
	if contents.has("armor"):
		return Color(1.0, 0.35, 0.9) if (contents.armor as ArmorData).rare else Color(0.75, 0.75, 0.9)
	if contents.has("unit"):
		return Color(0.9, 0.9, 0.5)
	if contents.has("lumidium"):
		return Inventory.LUMIDIUM_COLORS.get(contents.lumidium, Color.WHITE)
	if contents.has("disc"):
		return Color(0.6, 0.95, 1.0)
	return Color.WHITE


func _on_body_entered(body: Node) -> void:
	var seeker := body as Player
	if seeker == null or seeker.save == null or seeker.health.is_dead() or not is_automatic():
		return
	collect(seeker)


# --- Interaction (A) ---------------------------------------------------------------

const INTERACT_RANGE := 1.8


func interact_point() -> Vector3:
	return global_position


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact(seeker: Player) -> bool:
	return seeker.save != null and not is_queued_for_deletion()


func interact_prompt() -> String:
	if room_for(seeker_in_reach()) <= 0:
		return "Pick up %s (%s)" % [describe(), _no_room_reason(seeker_in_reach())]
	return "Pick up %s" % describe()


func seeker_in_reach() -> Player:
	return Player.nearest(self, global_position)


func _no_room_reason(seeker: Player) -> String:
	if seeker == null:
		return ""
	if contents.has("lumidium"):
		return "satchel full"
	if stack_id() != &"" and seeker.save and seeker.save.inventory.count(stack_id()) > 0:
		return "%d max" % Inventory.STACK_MAX
	if contents.has("oro"):
		return "Oro full"
	return "pack full"


func interact(seeker: Player) -> void:
	collect(seeker)


## Gives the contents to the Seeker, as much as fits: the pickup goes away
## when all of it was taken, otherwise the rest stays on the ground.
func collect(seeker: Player) -> void:
	var save := seeker.save
	var room := room_for(seeker)
	if room <= 0:
		seeker.item_collected.emit("Can't take %s: %s" % [describe(), _no_room_reason(seeker)])
		return
	var text := describe()
	var taken := 1
	if contents.has("oro"):
		taken = save.inventory.add_oro(int(contents.oro))
		text = "+%d Oro" % taken
		contents.oro = int(contents.oro) - taken
		if int(contents.oro) > 0:
			_label.text = describe()
			seeker.item_collected.emit(text)
			return
	elif stack_id() != &"":
		taken = save.take_stack(stack_id(), amount())
		text = "+%d %s" % [taken, Inventory.item_name(stack_id())]
	elif contents.has("lumidium"):
		taken = seeker.add_lumidium(contents.lumidium, amount())  # emits its own message
		text = ""
	elif contents.has("weapon"):
		var w := contents.weapon as WeaponData
		save.take_weapon(w)
		text = "Found %s%s" % [w.display_name, "  (RARE)" if w.rare else ""]
	elif contents.has("armor"):
		var a := contents.armor as ArmorData
		save.take_armor(a)
		text = "Found %s (%d slot%s)%s" % [a.display_name, a.slots, "" if a.slots == 1 else "s", "  (RARE)" if a.rare else ""]
	elif contents.has("unit"):
		save.take_unit(StringName(contents.unit))
		text = "+1 " + text
	elif contents.has("disc"):
		text = seeker.read_disc(StringName(contents.disc.id), int(contents.disc.level), true)
	if taken < amount():
		contents.count = amount() - taken
		_label.text = describe()
		if text != "":
			text += "  (%d left: %s)" % [amount(), _no_room_reason(seeker)]
	else:
		queue_free()
	if text != "":
		seeker.item_collected.emit(text)
