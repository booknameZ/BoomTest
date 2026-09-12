class_name FX
extends Node3D
## 粒子 + 飘字：由 Main 调用，自更新并回收。

class Particle:
	var mesh: MeshInstance3D
	var vel: Vector3
	var life: float
	var max_life: float
	var grav: float = 0.0

	func _init(m: MeshInstance3D, v: Vector3, l: float, g: float = 0.0) -> void:
		mesh = m
		vel = v
		life = l
		max_life = l
		grav = g


class FloatText:
	var label: Label3D
	var life: float
	var max_life: float

	func _init(l: Label3D, t: float) -> void:
		label = l
		life = t
		max_life = t


var _particles: Array[Particle] = []
var _texts: Array[FloatText] = []
# 环境余烬：炉火灰烬自下而上飘浮（循环重生，营造暗黑老虎机的烛房空气感）
var _embers: Array = []
const EMBER_COUNT := 26
const EMBER_MIN_Y := -320.0
const EMBER_MAX_Y := 330.0
const EMBER_HALF_W := 370.0


func _ready() -> void:
	for i in EMBER_COUNT:
		_embers.append(_spawn_ember(randf_range(EMBER_MIN_Y, EMBER_MAX_Y)))


func _spawn_ember(y: float) -> Dictionary:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	var s := 2.0 + randf() * 2.6
	box.size = Vector3(s, s, s)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# 火色渐层：亮黄橙 → 暗红，随机取中间调
	var heat := randf()
	var c := Color(1.0, 0.55 + 0.3 * heat, 0.12 + 0.18 * heat)
	mat.albedo_color = Color(c.r, c.g, c.b, 0.0)
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 1.4
	m.material_override = mat
	m.position = Vector3(randf_range(-EMBER_HALF_W, EMBER_HALF_W), y, randf_range(-16.0, 14.0))
	add_child(m)
	return {
		"mesh": m,
		"vy": randf_range(16.0, 42.0),
		"sway": randf_range(8.0, 22.0),
		"phase": randf() * TAU,
		"alpha": randf_range(0.35, 0.8),
	}


func burst(p: Vector3, color: Color, count: int, speed: float, life: float, size: float = 1.8) -> void:
	for i in count:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * (size + randf() * 1.4)
		m.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# 半透明实心碎屑：多片叠加仍保留矿石色调，不会糊成白屏
		mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.material_override = mat
		m.position = p
		add_child(m)
		var ang := randf() * TAU
		var spd := speed * (0.3 + randf() * 0.7)
		var l := life * (0.5 + randf() * 0.5)
		_particles.append(Particle.new(m, Vector3(cos(ang) * spd, sin(ang) * spd + 60.0, (randf() - 0.5) * 40.0), l))


func sparkle(p: Vector3, color: Color) -> void:
	burst(p, color, 6, 90.0, 0.5, 1.5)


## 下落碎屑：矿物被清掉时，对应颜色粒子向下飘落（受重力）。
func fall(p: Vector3, color: Color, count: int, size: float = 2.0) -> void:
	for i in count:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * (size + randf() * 1.4)
		m.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.material_override = mat
		m.position = p + Vector3((randf() - 0.5) * 28.0, (randf() - 0.5) * 18.0, (randf() - 0.5) * 10.0)
		add_child(m)
		var vel := Vector3((randf() - 0.5) * 80.0, randf() * 40.0 - 30.0, (randf() - 0.5) * 20.0)
		var l := 0.9 + randf() * 0.8
		_particles.append(Particle.new(m, vel, l, -380.0))


func float_text(p: Vector3, text: String, color: Color, size: int = 22) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.font_size = size
	label.modulate = color
	label.outline_size = 3
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.position = p
	label.pixel_size = 0.007
	add_child(label)
	_texts.append(FloatText.new(label, 0.9))


func _process(delta: float) -> void:
	# 余烬上飘 + 水平摇摆，越靠近顶部越透明，到顶后从底部重生
	for e in _embers:
		var m: MeshInstance3D = e.mesh
		m.position.y += e.vy * delta
		e.phase += delta * 1.7
		m.position.x += sin(e.phase) * e.sway * delta
		var edge := 1.0 - clampf((m.position.y - EMBER_MIN_Y) / (EMBER_MAX_Y - EMBER_MIN_Y), 0.0, 1.0)
		var tw := 0.65 + 0.35 * sin(e.phase * 2.3)
		var pm := m.material_override as StandardMaterial3D
		if pm != null:
			pm.albedo_color.a = e.alpha * edge * tw
		if m.position.y >= EMBER_MAX_Y:
			m.position.y = EMBER_MIN_Y
			m.position.x = randf_range(-EMBER_HALF_W, EMBER_HALF_W)

	for i in range(_particles.size() - 1, -1, -1):
		var pt := _particles[i]
		pt.life -= delta
		if pt.life <= 0.0:
			pt.mesh.queue_free()
			_particles.remove_at(i)
			continue
		pt.mesh.position += pt.vel * delta
		if pt.grav != 0.0:
			pt.vel.y += pt.grav * delta
		var k := pt.life / pt.max_life
		pt.mesh.scale = Vector3.ONE * k
		var pm := pt.mesh.material_override as StandardMaterial3D
		if pm != null:
			pm.albedo_color.a = k

	for i in range(_texts.size() - 1, -1, -1):
		var t := _texts[i]
		t.life -= delta
		if t.life <= 0.0:
			t.label.queue_free()
			_texts.remove_at(i)
			continue
		var k := t.life / t.max_life
		t.label.position.y += 60.0 * delta
		t.label.modulate.a = k
