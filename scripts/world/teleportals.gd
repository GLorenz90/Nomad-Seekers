class_name Teleportals
extends RefCounted
## The Teleportal spell, PSO's Ryuker / telepipe (Grayson 2026-11-12: "very
## faithful to the PSO way").
##
## - One per Seeker. Casting opens a pad where they stand, back to Nomad-2,
##   and a matching return pad on Nomad-2 that goes back to that spot. Casting
##   again moves it (the old pair closes).
## - Anyone can use either end. The field end takes you to Nomad-2 and stays.
## - The Nomad-2 end takes you back to the spot, and then both ends close.
## - Going back to the area some other way (the normal teleporter) leaves the
##   pair open. Neither end times out; quitting to the title closes them all.
## Maps persist for the session (CoopDirector), so the field end stays put
## while nobody's there.

## Seeker (Party who) -> {map, position, name}.
static var records := {}

const GROUP := "teleportals"
const NO_OWNER := -999


static func new_session() -> void:
	records.clear()


static func has_portal(who: int) -> bool:
	return records.has(who)


## The caster opens a Teleportal at `at`, on the map they're on.
static func open(caster: Player, at: Vector3) -> Teleporter:
	var who := Party.who_of(caster)
	close(who, caster.get_tree())
	var level := Scope.level(caster)
	var map := Maps.id_of(level)
	records[who] = {"map": map, "position": at, "name": caster.save.character.seeker_name if caster.save else "Seeker"}
	var field := _pad(who, Session.HUB_SCENE, "%s's Teleportal\nto Nomad-2" % records[who].name)
	level.add_child(field)
	field.global_position = at
	var hub := _hub_level(caster.get_tree())
	if hub:
		place_hub_pad(hub, who)
	return field


## The return end on Nomad-2 for one Seeker's Teleportal.
static func place_hub_pad(hub: Node, who: int) -> Teleporter:
	if not records.has(who):
		return null
	for pad in hub.get_tree().get_nodes_in_group(GROUP):
		if (pad as Teleporter).portal_owner == who and (pad as Teleporter).portal_return:
			return pad
	var rec: Dictionary = records[who]
	var pad := _pad(who, rec.map, "%s's Teleportal\nto %s" % [rec.name, Maps.display_name(rec.map)])
	pad.portal_return = true
	pad.arrive_at = rec.position
	hub.add_child(pad)
	var slot := 0 if who == Party.LEADER else maxi(Party.slot_of(who), 0)
	pad.global_position = hub.call("teleportal_spot", slot) if hub.has_method("teleportal_spot") else Vector3(slot * 3.0, 0, -5)
	return pad


## Nomad-2 opening (or opening again): its return pads.
static func place_hub_pads(hub: Node) -> void:
	for who in records:
		place_hub_pad(hub, who)


## Closes one Seeker's Teleportal: both ends go.
static func close(who: int, tree: SceneTree) -> void:
	records.erase(who)
	for pad in tree.get_nodes_in_group(GROUP):
		if (pad as Teleporter).portal_owner == who:
			pad.remove_from_group(GROUP)
			pad.queue_free()


static func pads_of(who: int, tree: SceneTree) -> Array[Teleporter]:
	var out: Array[Teleporter] = []
	for pad in tree.get_nodes_in_group(GROUP):
		if (pad as Teleporter).portal_owner == who and not (pad as Node).is_queued_for_deletion():
			out.append(pad)
	return out


static func _pad(who: int, destination: String, label: String) -> Teleporter:
	var pad := Teleporter.new()
	pad.destination = destination
	pad.destination_name = label
	pad.portal_owner = who
	pad.add_to_group(GROUP)
	return pad


static func _hub_level(tree: SceneTree) -> Node:
	var director := CoopDirector.find(tree)
	if director:
		return director.level_for(Session.HUB_SCENE)
	var scene := tree.current_scene
	return scene if scene and Maps.id_of(scene) == Session.HUB_SCENE else null
