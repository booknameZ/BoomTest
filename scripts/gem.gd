class_name Gem
extends Node3D
## 矿石掉落实体：击碎时崩出的能量碎屑，具备真实物理
## （重力 / 空气阻力 / 与边墙和底部斜坡反弹 / 沿斜面滚落）。
## 物理与收集由 Main 统一驱动，本类只负责外观与自转。
## 外观：矿石本体色 + 自发光核心 + 一层加色辉光 + 一层彩色软晕。
## 多粒子叠加时仍是有色块而不是亮白屏（外晕用普通混合，内辉用加色但很小）。

var pos2d: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var value: float = 1.0          # 掉入漏斗后累计的能量值
var life: float = 9.0
var radius: float = 6.0         # 物理碰撞半径
var color: Color = Color("#d8b050")
var spin: float = 0.0
# 真实物理料池：粒子落底后标记 settled，并归位到堆叠点（按列堆积）。
var settled: bool = false
var rest_x: float = 0.0
var rest_y: float = 0.0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _glow: MeshInstance3D          # 加色内辉光（贴合本体）
var _glow_mat: StandardMaterial3D
var _halo: MeshInstance3D          # 彩色软外晕（普通混合，多个叠加不会爆白）
var _halo_mat: StandardMaterial3D
var _t: float = 0.0
var _pulse_seed: float = 0.0


func setup(c: Color, v: float) -> void:
	value = v
	color = c
	# 粒子大小：较小但轮廓清晰，像像素水晶碎片
	radius = 2.8 + v * 0.10

	# 本体：强自发光，保证在雾/暗背景下绝对可读
	var core := c.lerp(Color.WHITE, 0.18)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = core
	_mat.emission_enabled = true
	_mat.emission = c
	_mat.emission_energy_multiplier = 1.6

	# 扁平像素水晶片，多边形边在自发光下清晰可见
	var sides := 3 + int(v) % 4
	_mesh = MeshInstance3D.new()
	_mesh.mesh = MeshFactory.prism(sides, radius, radius * 0.35)
	_mesh.material_override = _mat
	_mesh.rotation_degrees = Vector3(randf_range(0.0, 360.0), randf_range(0.0, 360.0), randf_range(0.0, 360.0))
	add_child(_mesh)

	# 内辉光：加色混合，自发光核心
	var gs := SphereMesh.new()
	gs.radius = radius * 1.1
	gs.height = radius * 2.2
	gs.radial_segments = 8
	gs.rings = 4
	_glow = MeshInstance3D.new()
	_glow.mesh = gs
	_glow_mat = _make_add_mat(c, 0.65, 1.8)
	_glow.material_override = _glow_mat
	add_child(_glow)

	# 外晕：普通混合的彩色软球，多个叠加仍是有色实体，不会爆白屏
	var hs := SphereMesh.new()
	hs.radius = radius * 1.7
	hs.height = radius * 3.4
	hs.radial_segments = 8
	hs.rings = 4
	_halo = MeshInstance3D.new()
	_halo.mesh = hs
	_halo_mat = _make_alpha_mat(c.lerp(Color.WHITE, 0.10), 0.35, 0.75)
	_halo.material_override = _halo_mat
	add_child(_halo)

	spin = randf_range(-7.0, 7.0)
	_pulse_seed = randf() * TAU
	sync()


## 加色混合：HDR 辉光来源，bloom 会把它变成光晕。
func _make_add_mat(c: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## 普通透明：多个粒子叠加 → 有色实体，保留可读的彩色而不是亮白。
func _make_alpha_mat(c: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func sync() -> void:
	position = Vector3(pos2d.x, pos2d.y, 2.0)


func _process(delta: float) -> void:
	_t += delta
	# 滚动感：自转与水平速度挂钩，慢下来时也慢慢停转
	rotation.z -= vel.x * delta * 0.014
	_mesh.rotation.x += spin * delta
	# 辉光呼吸：掉落中持续脉动；已 settled 的池内粒子保持长亮，增强"积攒"感
	var pulse := 0.88 + 0.12 * sin(_t * 9.0 + _pulse_seed)
	var fade := 1.0 if (life > 1.2 or settled) else maxf(life / 1.2, 0.0)
	var settled_boost := 1.25 if settled else 1.0
	if _glow != null:
		_glow.scale = Vector3.ONE * pulse
		_glow_mat.albedo_color.a = 0.65 * fade
		_glow_mat.emission_energy_multiplier = 1.8 * fade * settled_boost
	if _halo != null:
		_halo.scale = Vector3.ONE * (0.95 + (1.0 - pulse) * 0.4)
		_halo_mat.albedo_color.a = 0.35 * fade
		_halo_mat.emission_energy_multiplier = 0.75 * fade * settled_boost