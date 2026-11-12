class_name Party
extends RefCounted
## Local co-op (Part 12): who else is playing on this machine.
##
## The leader is Session's character (keyboard, mouse and their controller).
## Guests join by pressing Start on another controller and picking a saved
## character that isn't already playing; each keeps their own SaveData, like
## the leader. Kept across scene changes (static), cleared on quit to title.

## Guests: [{"device": joypad id, "slot": character slot, "save": SaveData,
## "input": their input slot 1-3 (the leader is 0)}, ...]
static var guests: Array[Dictionary] = []
## The leader's controller (-1 until they press something on one).
static var leader_pad := -1
## Which map (scene path) the leader is on, once the party can split up
## (Grayson, 2026-11-09: one Seeker can go to town while another explores).
## Guests keep theirs in their entry ("map"). "" = the window's own level.
static var leader_map := ""
## Where a Seeker appears on their next arrival instead of the map's spawn
## point (a Teleportal's spot): who -> Vector3. Used once.
static var arrivals := {}

## Party members are named by `who`: LEADER, or a guest's controller.
const LEADER := -1


static func is_active() -> bool:
	return not guests.is_empty()


## Seekers playing, the leader included.
static func size() -> int:
	return 1 + guests.size()


static func has_device(device: int) -> bool:
	if device == leader_pad:
		return true
	for g in guests:
		if int(g.device) == device:
			return true
	return false


## Character slots being played (the leader's and every guest's).
static func slots_in_use() -> Array[int]:
	var out: Array[int] = []
	if Session.slot >= 0:
		out.append(Session.slot)
	for g in guests:
		out.append(int(g.slot))
	return out


## Adds a guest playing a character slot. Returns their entry, or {} when the
## party is full, the controller already plays, or the slot is taken or empty.
static func join(device: int, slot: int) -> Dictionary:
	if size() >= PlayerInput.MAX_PLAYERS or has_device(device) or slot in slots_in_use():
		return {}
	var data := Session.load_slot(slot)
	if data == null:
		return {}
	var used: Array[int] = []
	for g in guests:
		used.append(int(g.input))
	var free := 1
	while free in used:
		free += 1
	var guest := {"device": device, "slot": slot, "save": data, "input": free}
	guests.append(guest)
	return guest


static func guest_for(device: int) -> Dictionary:
	for g in guests:
		if int(g.device) == device:
			return g
	return {}


static func leave(device: int) -> void:
	for i in guests.size():
		if int(guests[i].device) == device:
			guests.remove_at(i)
			return


static func clear() -> void:
	guests.clear()
	leader_map = ""
	arrivals.clear()


static func who_of(seeker: Player) -> int:
	return seeker.guest_device if seeker.guest_device >= 0 else LEADER


static func map_of(who: int) -> String:
	if who == LEADER:
		return leader_map
	return String(guest_for(who).get("map", ""))


static func set_map(who: int, path: String) -> void:
	if who == LEADER:
		leader_map = path
		return
	var g := guest_for(who)
	if not g.is_empty():
		g["map"] = path


## Everyone on a map: LEADER and / or guests' controllers, leader first.
static func members_on(path: String) -> Array[int]:
	var out: Array[int] = []
	if leader_map == path:
		out.append(LEADER)
	for g in guests:
		if String(g.get("map", "")) == path:
			out.append(int(g.device))
	return out


## The input slot (action prefix): the leader 0, guests 1-3 (kept while they
## stay, so a guest leaving never renumbers the others).
static func slot_of(device: int) -> int:
	if device == leader_pad or device < 0:
		return 0
	var g := guest_for(device)
	return int(g.input) if not g.is_empty() else -1
