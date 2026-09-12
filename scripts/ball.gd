class_name Ball
extends Node3D
## 弹球：低多边形球体 + 头灯。由 Main 驱动物理与颜色。

var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var active: bool = false
var radius: float = 16.0
var bounce_count: int = 0
var max_bounces: int = 15
var danger: float = 0.0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _glow: MeshInstance3D


func setup(r: float) -> void:
	radius = r
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color("#3080c8")
	_mat.roughness = 0.35
	_mat.metallic = 0.4
	_mat.emission_enabled = true
	_mat.emission = Color("#104070")
	_mat.emission_energy_multiplier = 0.8

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 7

	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = _mat
	add_child(_mesh)

	# 外层光晕（半透明）
	_glow = MeshInstance3D.new()
	var gsphere := SphereMesh.new()
	gsphere.radius = radius * 1.9
	gsphere.height = radius * 3.8
	gsphere.radial_segments = 12
	gsphere.rings = 7
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.25, 0.55, 0.9, 0.14)
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow.mesh = gsphere
	_glow.material_override = gmat
	add_child(_glow)

	# 头灯：跟随弹球的点光源，飞行时照亮附近矿石，打出多边形明暗。
	_light = OmniLight3D.new()
	_light.omni_range = 240.0
	_light.light_color = Color("#3080c8")
	_light.light_energy = 0.0
	_light.omni_attenuation = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func set_state(base: Color, emissive: Color, energy: float) -> void:
	_mat.albedo_color = base
	_mat.emission = emissive
	_mat.emission_energy_multiplier = energy
	_light.light_color = emissive
	_light.light_energy = energy
	if _glow.material_override is StandardMaterial3D:
		var gm := _glow.material_override as StandardMaterial3D
		gm.albedo_color = Color(emissive.r, emissive.g, emissive.b, 0.12)


## 危险度 0..1：驱动外层光晕脉冲。
func set_danger(v: float) -> void:
	danger = clampf(v, 0.0, 1.0)


func _process(_delta: float) -> void:
	if danger > 0.0:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.02) * 0.28 * danger
		_glow.scale = Vector3.ONE * (1.0 + danger * 0.5) * pulse
	else:
		_glow.scale = Vector3.ONE


func sync_transform() -> void:
	position = Vector3(pos.x, pos.y, 0.0)
	rotation.z += 0.15
