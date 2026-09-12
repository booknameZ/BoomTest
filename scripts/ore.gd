class_name Ore
extends Node3D
## 矿石/砖块：低多边形晶体，均分成多个独立自发光切片。
## 被球撞击一次就顺时针暗掉一格（关闭一格自发光），全部暗掉即击碎。

# 矿石类型：参考图用高饱和霓虹宝石色 + 暗底白描边，使多边形在暗红背景上清晰可读。
const ORE_TYPES: Array = [
	{ "color": Color("#c03030"), "emissive": Color("#ff4a4a"), "outline": Color("#ff8888"), "value": 1.0, "hp": 3, "radius": 18.0, "sides": 3 },
	{ "color": Color("#e07018"), "emissive": Color("#ffaa33"), "outline": Color("#ffd27a"), "value": 1.5, "hp": 4, "radius": 19.0, "sides": 4 },
	{ "color": Color("#a030a0"), "emissive": Color("#d050d0"), "outline": Color("#ff88ff"), "value": 2.0, "hp": 5, "radius": 20.0, "sides": 5 },
	{ "color": Color("#c8a020"), "emissive": Color("#ffe040"), "outline": Color("#fff0a0"), "value": 5.0, "hp": 6, "radius": 21.0, "sides": 6 },
	{ "color": Color("#7080a0"), "emissive": Color("#a0b8d8"), "outline": Color("#d0e0ff"), "value": 10.0, "hp": 8, "radius": 23.0, "sides": 7 },
]

## 砖块：骨白/象牙色像素片（暖白，不再冷银）+ 受光 SHADED + 自发光保证暗处可读。
const BRICK_TYPES: Array = [
	{ "color": Color("#c8b8a0"), "emissive": Color("#f0e4c8"), "outline": Color("#fff8e0"), "radius": 16.0, "sides": 4, "hp": 1 },
	{ "color": Color("#b0a088"), "emissive": Color("#e0d4b0"), "outline": Color("#fff0c0"), "radius": 17.0, "sides": 5, "hp": 2 },
	{ "color": Color("#988870"), "emissive": Color("#d0c0a0"), "outline": Color("#ffe8a0"), "radius": 19.0, "sides": 6, "hp": 3 },
]

var is_brick: bool = false
var kind: int = -1
var value: float = 1.0
var hp: int = 1
var max_hp: int = 1
var radius: float = 20.0
var sides: int = 4
var base_color: Color = Color.WHITE
var emissive: Color = Color.BLACK

var pos2d: Vector2 = Vector2.ZERO
var flash_timer: float = 0.0
var shake_timer: float = 0.0
var pulse_timer: float = 0.0
var broken: bool = false

var _slices: Array[MeshInstance3D] = []
var _slice_mats: Array[StandardMaterial3D] = []
var _dark_count: int = 0
var _depth: float = 0.0
var _outline: MeshInstance3D


func setup(data: Dictionary, as_brick: bool, ore_kind: int = -1) -> void:
	is_brick = as_brick
	kind = ore_kind
	value = data.get("value", 1.0)
	hp = data.get("hp", 1)
	max_hp = hp
	radius = data.get("radius", 20.0)
	sides = data.get("sides", 4)
	base_color = data.get("color", Color.WHITE)
	emissive = data.get("emissive", Color.BLACK)

	_depth = radius * 0.55
	_dark_count = 0
	_slices.clear()
	_slice_mats.clear()

	# 均分成 max_hp 个扇形切片，每个切片独立材质、独立自发光。
	# 顺时针排列：切片 0 从顶部(-PI/2)开始，角度递减（屏幕视角顺时针）。
	var step := TAU / float(max_hp)
	var start := -PI / 2.0
	for i in max_hp:
		var from := start - i * step
		var to := start - (i + 1) * step
		var mat := StandardMaterial3D.new()
		mat.albedo_color = base_color
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# 矿石用 UNSHADED 做出参考图里霓虹般的平面宝石感；砖块保留 SHADED 体现体积。
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if is_brick else BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = emissive
		mat.emission_energy_multiplier = 2.3 if is_brick else 2.0
		var m := MeshInstance3D.new()
		m.mesh = MeshFactory.pie_slice(radius, _depth, from, to)
		m.material_override = mat
		add_child(m)
		_slices.append(m)
		_slice_mats.append(mat)

	# 反向外壳描边：放大一圈的多边形棱柱，只渲染背面（CULL_FRONT），
	# 使用数据里的 outline 色做高亮白边/金边，让矿石在暗红背景上清晰可读。
	_outline = MeshInstance3D.new()
	var omat := StandardMaterial3D.new()
	omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	omat.albedo_color = data.get("outline", base_color * 0.35)
	omat.emission_enabled = true
	omat.emission = data.get("outline", base_color * 0.35)
	omat.emission_energy_multiplier = 3.8
	omat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.mesh = MeshFactory.prism(sides, radius * 1.28, _depth * 1.08)
	_outline.material_override = omat
	_outline.position.z = -0.6
	add_child(_outline)

	pulse_timer = randf() * 100.0
	# 随机旋转：让每个矿石以不同角度朝向相机，多边形边更明显
	rotation_degrees = Vector3(0.0, 0.0, randf_range(0.0, 360.0))
	sync()


func sync() -> void:
	position = Vector3(pos2d.x, pos2d.y, 0.0)


## 被球命中一次。返回是否被击碎。
func take_hit() -> bool:
	return damage(1)


## 受到 n 点伤害。返回是否被击碎。
func damage(n: int) -> bool:
	if broken:
		return false
	hp -= n
	flash_timer = 0.18
	shake_timer = 0.3
	_darken_slices(mini(max_hp - hp, max_hp))
	return hp <= 0


## 顺时针逐片暗掉，直到已暗格数达到 target_dark。
## 暗掉 = 只是"没那么亮"（保留色相 + 微弱自发光），而非完全变黑。
func _darken_slices(target_dark: int) -> void:
	while _dark_count < target_dark and _dark_count < max_hp:
		var m: StandardMaterial3D = _slice_mats[_dark_count]
		if m != null and is_instance_valid(m):
			m.albedo_color = base_color * 0.45
			m.emission_energy_multiplier = 0.25
		_dark_count += 1


## 标记击碎并移除自身。
func remove_self() -> void:
	broken = true
	queue_free()


func _process(delta: float) -> void:
	if broken:
		return
	pulse_timer += delta
	var pulse := 1.0 + sin(pulse_timer * 2.5) * 0.04

	var offset := Vector3.ZERO
	if shake_timer > 0.0:
		shake_timer -= delta
		var k := shake_timer / 0.3
		offset = Vector3(sin(shake_timer * 60.0) * 8.0 * k, cos(shake_timer * 50.0) * 8.0 * k, 0.0)

	# 命中白闪：只作用于仍亮着的切片
	var flashing := flash_timer > 0.0
	if flashing:
		flash_timer -= delta
	for i in range(_dark_count, max_hp):
		var m: StandardMaterial3D = _slice_mats[i]
		if m == null or not is_instance_valid(m):
			continue
		if flashing:
			m.albedo_color = Color.WHITE
			m.emission_energy_multiplier = 2.2
		else:
			m.albedo_color = base_color
			m.emission_energy_multiplier = 1.8 if is_brick else 1.4

	scale = Vector3.ONE * pulse
	position = Vector3(pos2d.x, pos2d.y, 0.0) + offset
