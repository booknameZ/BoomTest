class_name SlotMachine
extends Node3D
## 底部实体老虎机：默认折叠成底座内的暗铜机匣；料池积满后全屏弹出（升起 + 开盖 + 三转轮旋转）。
## 由 Main 驱动：deploy() 弹出 → set_result() 落定 → fold() 收回。

const CAB_W := 700.0
const CAB_H := 460.0
const REEL_X := [-200.0, 0.0, 200.0]
const FOLDED_Y := -300.0
const DEPLOY_Y := -20.0

var deployed := false
var _cabinet: Node3D
var _base: Node3D
var _lid_l: MeshInstance3D
var _lid_r: MeshInstance3D
var _gems: Array[MeshInstance3D] = []
var _glow_mat: StandardMaterial3D
var _spinning := false
var _spin_index := 0
var _result: int = -1
var _result_names: Dictionary = {}
var _result_colors: Dictionary = {}


## 构建机匣与底座。names/colors 由 Main 传入（复用 REWARD_NAMES / REWARD_COLORS）。
func build(names: Dictionary, colors: Dictionary) -> void:
	_result_names = names
	_result_colors = colors
	_build_base()
	_build_cabinet()
	_cabinet.scale = Vector3(0.02, 0.02, 1.0)
	_cabinet.position = Vector3(0.0, FOLDED_Y, 8.0)
	_cabinet.visible = false


# ==================== 构建 ====================
func _build_base() -> void:
	_base = Node3D.new()
	add_child(_base)
	# 机座：暗铜机身，折叠时唯一可见的部分
	var slab := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(620.0, 36.0, 34.0)
	slab.mesh = sb
	slab.material_override = _mat(Color("#241408"), Color("#5a3410"), 0.6)
	slab.position = Vector3(0.0, FOLDED_Y, 6.0)
	_base.add_child(slab)
	# 机座顶面金线
	var trim := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(620.0, 4.0, 36.0)
	trim.mesh = tb
	trim.material_override = _mat(Color("#c8902f"), Color("#ffb84a"), 0.9)
	trim.position = Vector3(0.0, FOLDED_Y + 18.0, 6.0)
	_base.add_child(trim)
	# 两侧开合盖板
	for side in [-1.0, 1.0]:
		var lid := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(300.0, 12.0, 30.0)
		lid.mesh = lb
		lid.material_override = _mat(Color("#3a220c"), Color("#8a5418"), 0.8)
		lid.position = Vector3(side * 155.0, FOLDED_Y + 22.0, 6.0)
		_base.add_child(lid)
		if side < 0.0:
			_lid_l = lid
		else:
			_lid_r = lid


func _build_cabinet() -> void:
	_cabinet = Node3D.new()
	add_child(_cabinet)

	# 外框（暗褐）与内衬（更暗），中间留出金色描边
	var outer := MeshInstance3D.new()
	var ob := BoxMesh.new()
	ob.size = Vector3(CAB_W, CAB_H, 32.0)
	outer.mesh = ob
	outer.material_override = _mat(Color("#1c1006"), Color("#3a2008"), 0.5)
	_cabinet.add_child(outer)

	# 金色描边：四条边框
	for d in [
		[Vector3(0.0, CAB_H * 0.5 - 6.0, 18.0), Vector3(CAB_W, 12.0, 12.0)],
		[Vector3(0.0, -CAB_H * 0.5 + 6.0, 18.0), Vector3(CAB_W, 12.0, 12.0)],
		[Vector3(-CAB_W * 0.5 + 6.0, 0.0, 18.0), Vector3(12.0, CAB_H, 12.0)],
		[Vector3(CAB_W * 0.5 - 6.0, 0.0, 18.0), Vector3(12.0, CAB_H, 12.0)],
	]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = d[1]
		m.mesh = b
		m.material_override = _mat(Color("#c8902f"), Color("#ffb84a"), 1.0)
		m.position = d[0]
		_cabinet.add_child(m)

	# 顶部纹章：叠层 + 主石
	var crest := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(120.0, 16.0, 20.0)
	crest.mesh = cb
	crest.material_override = _mat(Color("#3a220c"), Color("#8a5418"), 0.8)
	crest.position = Vector3(0.0, CAB_H * 0.5 + 10.0, 18.0)
	_cabinet.add_child(crest)
	var gem := MeshInstance3D.new()
	gem.mesh = MeshFactory.octahedron(14.0)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.emission_enabled = true
	gm.emission = Color("#ffb84a")
	gm.emission_energy_multiplier = 1.8
	gem.material_override = gm
	gem.position = Vector3(0.0, CAB_H * 0.5 + 30.0, 18.0)
	_cabinet.add_child(gem)

	# 三个转轮窗口 + 内部宝石
	for i in 3:
		var win := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(168.0, 210.0, 8.0)
		win.mesh = wb
		win.material_override = _mat(Color("#080604"), Color("#1a0c04"), 0.7)
		win.position = Vector3(REEL_X[i], 30.0, 20.0)
		_cabinet.add_child(win)

		var rim := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(180.0, 222.0, 4.0)
		rim.mesh = rb
		rim.material_override = _mat(Color("#8a5418"), Color("#c8902f"), 0.7)
		rim.position = Vector3(REEL_X[i], 30.0, 16.0)
		_cabinet.add_child(rim)

		var g := MeshInstance3D.new()
		g.mesh = MeshFactory.prism(6, 34.0, 16.0)
		var gmat := StandardMaterial3D.new()
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gmat.albedo_color = Color("#ffd27a")
		gmat.emission_enabled = true
		gmat.emission = Color("#b8862a")
		gmat.emission_energy_multiplier = 1.2
		g.material_override = gmat
		g.position = Vector3(REEL_X[i], 40.0, 26.0)
		_cabinet.add_child(g)
		_gems.append(g)

	# 中奖线：横贯三转轮的金线
	var pay := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(CAB_W - 60.0, 5.0, 6.0)
	pay.mesh = pb
	pay.material_override = _mat(Color("#ffd27a"), Color("#ffd27a"), 1.4)
	pay.position = Vector3(0.0, 40.0, 28.0)
	_cabinet.add_child(pay)

	# 整体辉光片：落定时脉冲
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(1.0, 0.78, 0.35, 0.0)
	var glow := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(CAB_W + 60.0, CAB_H + 60.0, 4.0)
	glow.mesh = gb
	glow.material_override = _glow_mat
	glow.position = Vector3(0.0, 0.0, 32.0)
	_cabinet.add_child(glow)


func _mat(albedo: Color, emissive: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emissive
	m.emission_energy_multiplier = energy
	return m


# ==================== 状态 ====================
func deploy() -> void:
	deployed = true
	_result = -1
	_spinning = true
	_cabinet.visible = true
	_cabinet.position = Vector3(0.0, FOLDED_Y, 8.0)
	_cabinet.scale = Vector3(0.02, 0.02, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_cabinet, "scale", Vector3(1.0, 1.0, 1.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cabinet, "position", Vector3(0.0, DEPLOY_Y, 8.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_lid_l, "position:x", -300.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_lid_r, "position:x", 300.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func fold() -> void:
	_spinning = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_cabinet, "scale", Vector3(0.02, 0.02, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_cabinet, "position", Vector3(0.0, FOLDED_Y, 8.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_lid_l, "position:x", -155.0, 0.35).set_delay(0.2)
	tw.tween_property(_lid_r, "position:x", 155.0, 0.35).set_delay(0.2)
	tw.chain().tween_callback(func() -> void:
		_cabinet.visible = false
		deployed = false
	)


## 落定：三转轮对齐为同一个奖励色，机匣金色脉冲。
func set_result(reward: int) -> void:
	_result = reward
	_spinning = false
	var c: Color = _result_colors.get(reward, Color("#ffd27a"))
	# 深色版奖励色：直接用原色会被 bloom 推到过曝发白，压暗后保持色相可读
	var deep := c.darkened(0.35)
	for g in _gems:
		g.rotation.z = 0.0
		var m := g.material_override as StandardMaterial3D
		if m != null:
			m.albedo_color = c
			m.emission = deep
			m.emission_energy_multiplier = 1.3
	# 金色脉冲
	var tw := create_tween()
	tw.tween_property(_glow_mat, "albedo_color:a", 0.55, 0.12)
	tw.tween_property(_glow_mat, "albedo_color:a", 0.0, 0.7)
	tw.parallel().tween_property(_cabinet, "scale", Vector3(1.06, 1.06, 1.0), 0.1)
	tw.parallel().tween_property(_cabinet, "scale", Vector3(1.0, 1.0, 1.0), 0.25).set_delay(0.1)


func _process(delta: float) -> void:
	if not deployed:
		return
	if _spinning:
		# 三转轮同速旋转，制造"滚动"感
		for g in _gems:
			g.rotation.z += delta * 9.0
		_spin_index += delta
		if _spin_index >= 0.08:
			_spin_index = 0.0
			for g in _gems:
				var m := g.material_override as StandardMaterial3D
				if m != null and not _result_names.is_empty():
					var k := randi() % _result_names.size()
					var c: Color = _result_colors[k]
					m.albedo_color = c
					m.emission = c.darkened(0.35)
					m.emission_energy_multiplier = 1.2
	elif _result >= 0:
		# 落定后宝石缓缓自转，保持"通电"质感
		for g in _gems:
			g.rotation.z += delta * 1.2
