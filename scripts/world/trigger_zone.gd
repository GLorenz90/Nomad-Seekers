class_name TriggerZone
extends Area3D
## An invisible box that tells the level's wiring when a Seeker walks in
## (Part 13a, level editor Layer 2): start a dialogue, start a room's fight,
## open a door...
##
## whole_party: waits until every Seeker on the map is inside (PSO's boss
## doors), then reports "party_present" instead of "entered".

signal entered(zone: TriggerZone, seeker: Player)
signal party_present(zone: TriggerZone)

@export var zone_id := ""
@export var size := Vector3(4.0, 4.0, 4.0)
## Reports only the first time.
@export var once := true
@export var whole_party := false
@export var enabled := true

var _inside := {}
var _done := false


func _ready() -> void:
	add_to_group("trigger_zones")
	collision_layer = 0
	collision_mask = 2  # Seekers
	monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	add_child(shape)
	body_entered.connect(_on_entered)
	body_exited.connect(func(body: Node): _inside.erase(body))


func switch_action(action: String) -> void:
	match action:
		"enable", "start":
			enabled = true
			_done = false
			for body in get_overlapping_bodies():
				_on_entered(body)
		"disable", "stop":
			enabled = false
		"toggle":
			switch_action("disable" if enabled else "enable")


func _on_entered(body: Node) -> void:
	if not body is Player:
		return
	_inside[body] = true
	if not enabled or (once and _done):
		return
	if whole_party:
		for seeker in Scope.group(self, "player"):
			if not _inside.has(seeker):
				return
		_done = true
		party_present.emit(self)
	else:
		_done = true
		entered.emit(self, body as Player)
