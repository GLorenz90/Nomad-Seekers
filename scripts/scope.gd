class_name Scope
extends RefCounted
## Part 12 (Grayson, 2026-11-09): party members can be on different maps at
## once. Each map beyond the window's own runs inside its own SubViewport with
## its own World3D (CoopDirector), so the same groups ("player", "lockable",
## "wave_rooms"...) hold nodes from several maps. Scope keeps every lookup to
## the map the asking node is on: same viewport, same map.


## The nodes in a group on the same map as `from`.
static func group(from: Node, group_name: StringName) -> Array[Node]:
	var out: Array[Node] = []
	if from == null or not from.is_inside_tree():
		return out
	var here := from.get_viewport()
	for node in from.get_tree().get_nodes_in_group(group_name):
		if node.is_inside_tree() and node.get_viewport() == here:
			out.append(node)
	return out


static func first(from: Node, group_name: StringName) -> Node:
	var nodes := group(from, group_name)
	return nodes[0] if not nodes.is_empty() else null


## The level (main.gd, group "respawner") that `from` is on.
static func level(from: Node) -> Node:
	return first(from, &"respawner")
