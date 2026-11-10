class_name HitAreaView
extends MeshInstance3D
## Debug view of an enemy's melee hit area: a flat sector on the ground in
## front of it (radius and arc exactly as the hit check uses). It fades in
## during the windup and flashes when the strike lands. Shown while the
## Seeker's show_hitboxes is on (menu > Levels > Show hitboxes).

const COLOR := Color(1.0, 0.15, 0.1)
const SEGMENTS := 28

var _material: StandardMaterial3D
var _flash := 0.0
var _windup := -1.0  # 0..1 while telegraphing, -1 when idle


static func create(radius: float, arc_deg: float) -> HitAreaView:
	var view := HitAreaView.new()
	view.mesh = _sector(radius, minf(arc_deg, 360.0))
	view.position.y = 0.06
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view


## Flat fan facing -Z (the enemy's forward).
static func _sector(radius: float, arc_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(arc_deg) * 0.5
	for i in SEGMENTS:
		var a0 := -half + (2.0 * half) * float(i) / SEGMENTS
		var a1 := -half + (2.0 * half) * float(i + 1) / SEGMENTS
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a1), 0.0, -cos(a1)) * radius)
		st.add_vertex(Vector3(sin(a0), 0.0, -cos(a0)) * radius)
	return st.commit()


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	material_override = _material
	visible = false


## progress 0..1 through the windup.
func telegraph(progress: float) -> void:
	_windup = clampf(progress, 0.0, 1.0)


func strike() -> void:
	_windup = -1.0
	_flash = 0.2


func stop() -> void:
	_windup = -1.0


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	var alpha := 0.0
	if _flash > 0.0:
		alpha = 0.55
	elif _windup >= 0.0:
		alpha = 0.12 + 0.2 * _windup
	visible = alpha > 0.0 and _enabled()
	if visible:
		_material.albedo_color = Color(COLOR, alpha)


func _enabled() -> bool:
	for node in Scope.group(self, "player"):
		if (node as Player).combat.show_hitboxes:
			return true
	return false
