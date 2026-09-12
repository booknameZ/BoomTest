class_name MeshFactory
extends Object
## 程序化低多边形网格工厂（无外部资源，平面着色）。

## 多边形棱柱（N 边），用于矿石/砖块晶体。
static func prism(sides: int, radius: float, depth: float) -> ArrayMesh:
	sides = maxi(sides, 3)
	var h := depth * 0.5
	var pts: Array[Vector2] = []
	for i in sides:
		var a := TAU * i / sides
		pts.append(Vector2(cos(a), sin(a)) * radius)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()

	# 侧面（每面独立顶点 → 平面着色）
	for i in sides:
		var j := (i + 1) % sides
		var a := pts[i]
		var b := pts[j]
		var mid := Vector2(cos(TAU * (i + 0.5) / sides), sin(TAU * (i + 0.5) / sides))
		var n := Vector3(mid.x, mid.y, 0.0)
		var base := verts.size()
		verts.append(Vector3(a.x, a.y, -h)); norms.append(n)
		verts.append(Vector3(b.x, b.y, -h)); norms.append(n)
		verts.append(Vector3(a.x, a.y, h)); norms.append(n)
		idx.append(base); idx.append(base + 1); idx.append(base + 2)
		verts.append(Vector3(b.x, b.y, -h)); norms.append(n)
		verts.append(Vector3(b.x, b.y, h)); norms.append(n)
		verts.append(Vector3(a.x, a.y, h)); norms.append(n)
		idx.append(base + 3); idx.append(base + 4); idx.append(base + 5)

	# 顶盖 (+Z)
	var ntop := Vector3(0, 0, 1)
	for i in sides:
		var j := (i + 1) % sides
		var base := verts.size()
		verts.append(Vector3(0, 0, h)); norms.append(ntop)
		verts.append(Vector3(pts[i].x, pts[i].y, h)); norms.append(ntop)
		verts.append(Vector3(pts[j].x, pts[j].y, h)); norms.append(ntop)
		idx.append(base); idx.append(base + 1); idx.append(base + 2)

	# 底盖 (-Z)
	var nbot := Vector3(0, 0, -1)
	for i in sides:
		var j := (i + 1) % sides
		var base := verts.size()
		verts.append(Vector3(0, 0, -h)); norms.append(nbot)
		verts.append(Vector3(pts[j].x, pts[j].y, -h)); norms.append(nbot)
		verts.append(Vector3(pts[i].x, pts[i].y, -h)); norms.append(nbot)
		idx.append(base); idx.append(base + 1); idx.append(base + 2)

	return _build(verts, norms, idx)


## 扇形楔形切片：从中心轴到外沿，覆盖角度 [from_angle, to_angle]。
## 用于把矿石"均分"成多个独立发光区域（撞击一次顺时针暗掉一格）。
static func pie_slice(radius: float, depth: float, from_angle: float, to_angle: float) -> ArrayMesh:
	var h := depth * 0.5
	var a := Vector2(cos(from_angle), sin(from_angle)) * radius
	var b := Vector2(cos(to_angle), sin(to_angle)) * radius
	var mid_ang := (from_angle + to_angle) * 0.5
	var mid := Vector2(cos(mid_ang), sin(mid_ang))

	var c_top := Vector3(0, 0, h)
	var c_bot := Vector3(0, 0, -h)
	var a_top := Vector3(a.x, a.y, h)
	var a_bot := Vector3(a.x, a.y, -h)
	var b_top := Vector3(b.x, b.y, h)
	var b_bot := Vector3(b.x, b.y, -h)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()

	# 顶面扇形 (+Z)
	_tri(verts, norms, idx, c_top, a_top, b_top, Vector3(0, 0, 1))
	# 底面扇形 (-Z)
	_tri(verts, norms, idx, c_bot, b_bot, a_bot, Vector3(0, 0, -1))
	# 侧面 A（from 半径切面）
	_quad(verts, norms, idx, c_top, a_top, c_bot, a_bot, Vector3(-sin(from_angle), cos(from_angle), 0.0))
	# 侧面 B（to 半径切面）
	_quad(verts, norms, idx, c_top, b_top, c_bot, b_bot, Vector3(-sin(to_angle), cos(to_angle), 0.0))
	# 外沿面（A-B 弦面）
	_quad(verts, norms, idx, a_top, b_top, a_bot, b_bot, Vector3(mid.x, mid.y, 0.0))

	return _build(verts, norms, idx)


static func _tri(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var base := verts.size()
	verts.append(a); verts.append(b); verts.append(c)
	norms.append(n); norms.append(n); norms.append(n)
	idx.append(base); idx.append(base + 1); idx.append(base + 2)


static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(verts, norms, idx, a, b, c, n)
	_tri(verts, norms, idx, b, d, c, n)


## 八面体（宝石）。
static func octahedron(size: float) -> ArrayMesh:
	var p: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	for i in p.size():
		p[i] = p[i] * size

	var faces := [
		[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
		[0, 3, 5], [3, 1, 5], [1, 2, 5], [2, 0, 5],
	]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for f in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var n := (b - a).cross(c - a).normalized()
		var base := verts.size()
		verts.append(a); verts.append(b); verts.append(c)
		norms.append(n); norms.append(n); norms.append(n)
		idx.append(base); idx.append(base + 1); idx.append(base + 2)
	return _build(verts, norms, idx)


static func _build(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	# Godot 4 约定：正面 = 顺时针绕序。工厂里按逆时针习惯生成，
	# 这里统一翻转为 CW，否则正面被背面剔除（矿石一直显示的是"底盖"，
	# 被遮挡时（如老虎机转轮窗口内）就会只剩侧面碎弧）。
	var flipped := PackedInt32Array()
	flipped.resize(idx.size())
	for i in range(0, idx.size(), 3):
		flipped[i] = idx[i]
		flipped[i + 1] = idx[i + 2]
		flipped[i + 2] = idx[i + 1]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = flipped
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
