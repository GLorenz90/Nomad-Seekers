class_name Person
extends CharacterBody3D
## Someone to talk to (Grayson 2026-11-13): a Layer 2 object, placed on
## Nomad-2 by a quest or in any level. A on them starts their dialogue.
##
## interaction.json object:
##   {"type": "person", "id": "brandt", "name": "Commander Brandt",
##    "pos": [...], "yaw": 0,
##    "look": {"color": [0.3, 0.4, 0.8], "model": "brandt_model", "height": 1.8},
##    "talk": [{"dialogue": "brandt_hello"},
##             {"dialogue": "brandt_thanks", "from_step": "find_part"},
##             {"dialogue": "brandt_miners", "flag": "sided_with_miners"},
##             {"dialogue": "brandt_cold", "flag": "met_brandt", "story": true, "flag_is": false}],
##    "show_from": "", "show_until": "",
##    "route": {"points": [[...], ...], "mode": "loop", "speed": 1.6, "wait": 2.0},
##    "walking": true}
##
## - talk: the last entry that holds is what they say. An entry holds when
##   its `from_step` is done (if it has one) and its `flag` (a quest flag, or
##   a story flag with "story") is `flag_is` (default true). The wiring can
##   change it (set_talk).
## - show_from / show_until (step ids): they're only around from that step
##   being completed until that step is completed. Outside a quest they're
##   around only if neither is set.
## - route: walks between the points on the navmesh (loop or back_and_forth,
##   `wait` seconds at each); `walking` starts it at once.
## Wiring actions they take: show, hide, walk, stop, set_talk, escort,
## stop_escort. Events: talked (when A is pressed on them).
## Escorts follow the nearest Seeker and come along to the quest's other
## maps (QuestSession.escorts); enemies ignore them and they can't be hurt.

signal talked(person: Person, seeker: Player)

const INTERACT_RANGE := 2.4
const FOLLOW_DISTANCE := 2.6

var person_id := ""
var display_name := ""
var look := {}
var talk: Array = []
var show_from := ""
var show_until := ""
var route_points: Array[Vector3] = []
var route_mode := "loop"
var speed := 1.6
var wait := 2.0
var walking := false
var escorting := false
## Set by the wiring (set_talk / show / hide): overrides the step rules.
var talk_override := ""
var shown_override: Variant = null
## The model when the level has one for `look.model` (made by the builder).
var model: Node3D

var _agent: NavigationAgent3D
var _label: Label3D
var _target := 0
var _dir := 1
var _pause := 0.0
var _home := Vector3.ZERO


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("people")
	collision_layer = 1
	collision_mask = 1
	_home = global_position
	var height := clampf(float(look.get("height", 1.8)), 0.5, 4.0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	add_child(shape)
	if model:
		add_child(model)
	else:
		add_child(_body(height))
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = height + 0.35
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.5
	_agent.target_desired_distance = 0.6
	_agent.radius = 0.35
	add_child(_agent)
	# Standing on the first point already: head for the next one.
	if route_points.size() >= 2 and Vector2(route_points[0].x - _home.x, route_points[0].z - _home.z).length() < 0.5:
		_target = 1
	refresh()


## A plain figure in their colour (until a model is given).
func _body(height: float) -> Node3D:
	var color := LevelData.vec3(look.get("color"), Vector3(0.45, 0.55, 0.75))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.x, color.y, color.z)
	var root := Node3D.new()
	root.name = "Body"
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = height * 0.78
	body.mesh = capsule
	body.position.y = height * 0.39
	body.material_override = mat
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = height * 0.11
	sphere.height = height * 0.22
	head.mesh = sphere
	head.position.y = height * 0.88
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.72, 0.6)
	head.material_override = skin
	root.add_child(head)
	return root


# --- Who's around and what they say --------------------------------------------------------

## Shows or hides them for the quest's progress (and the wiring's word).
func refresh() -> void:
	var shown := should_show()
	visible = shown
	process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not shown


func should_show() -> bool:
	if shown_override != null:
		return bool(shown_override)
	var save := Session.save
	if QuestBook.active(save).is_empty():
		return show_from == "" and show_until == ""
	if show_from != "" and not QuestBook.step_done(save, show_from):
		return false
	if show_until != "" and QuestBook.step_done(save, show_until):
		return false
	return true


## The dialogue they'd start now ("" when they've nothing to say).
func current_dialogue() -> String:
	if talk_override != "":
		return talk_override
	var pick := ""
	for t in talk:
		var from := String(t.get("from_step", ""))
		if from != "" and not QuestBook.step_done(Session.save, from):
			continue
		var name := String(t.get("flag", ""))
		if name != "":
			var value: Variant = QuestBook.story_flag(Session.save, name) if bool(t.get("story", false)) \
				else QuestBook.flag(Session.save, name)
			if bool(value) != bool(t.get("flag_is", true)):
				continue
		pick = String(t.get("dialogue", ""))
	return pick


# --- Interacting ------------------------------------------------------------------------------

func interact_point() -> Vector3:
	return global_position


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact(_seeker: Player) -> bool:
	return visible


func interact_prompt() -> String:
	return "Talk to %s" % display_name if display_name != "" else "Talk"


func interact(seeker: Player) -> void:
	var to := seeker.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		look_at(global_position + to, Vector3.UP, true)
	talked.emit(self, seeker)


## Wiring actions (LevelEvents).
func switch_action(action: String) -> void:
	match action:
		"show":
			shown_override = true
			refresh()
		"hide":
			shown_override = false
			refresh()
		"walk":
			walking = true
		"stop":
			walking = false
			velocity = Vector3.ZERO


# --- Moving -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var goal := Vector3.INF
	if escorting:
		var seeker := Player.nearest(self, global_position, true)
		if seeker and seeker.global_position.distance_to(global_position) > FOLLOW_DISTANCE:
			goal = seeker.global_position
	elif walking and route_points.size() >= 2:
		if _pause > 0.0:
			_pause -= delta
		else:
			goal = route_points[_target]
			var flat := Vector2(goal.x - global_position.x, goal.z - global_position.z)
			if flat.length() < 0.5:
				_next_point()
				goal = Vector3.INF
	if goal == Vector3.INF:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_agent.target_position = goal
		var next := _agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0.0
		if dir.length() < 0.05:
			dir = goal - global_position
			dir.y = 0.0
		dir = dir.normalized()
		var pace := speed * (1.6 if escorting else 1.0)
		velocity.x = dir.x * pace
		velocity.z = dir.z * pace
		if dir.length() > 0.1:
			look_at(global_position + dir, Vector3.UP, true)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _next_point() -> void:
	_pause = wait
	if route_mode == "back_and_forth":
		if _target + _dir >= route_points.size() or _target + _dir < 0:
			_dir = -_dir
		_target += _dir
	else:
		_target = (_target + 1) % route_points.size()


## Built from interaction.json (DataLevel) or from an escort record.
static func from_spec(o: Dictionary) -> Person:
	var p := Person.new()
	p.person_id = String(o.get("id", ""))
	p.display_name = String(o.get("name", ""))
	p.look = o.get("look", {}) if o.get("look") is Dictionary else {}
	p.talk = (o.get("talk", []) as Array).filter(func(t): return t is Dictionary) if o.get("talk") is Array else []
	p.show_from = String(o.get("show_from", ""))
	p.show_until = String(o.get("show_until", ""))
	var r: Dictionary = o.get("route", {}) if o.get("route") is Dictionary else {}
	for pt in (r.get("points", []) as Array).slice(0, 32):
		p.route_points.append(LevelData.vec3(pt))
	p.route_mode = "back_and_forth" if String(r.get("mode", "loop")) == "back_and_forth" else "loop"
	p.speed = clampf(float(r.get("speed", 1.6)), 0.2, 6.0)
	p.wait = clampf(float(r.get("wait", 2.0)), 0.0, 60.0)
	p.walking = bool(o.get("walking", false))
	return p
