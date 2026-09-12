class_name Crosshair
extends CanvasLayer
## 双态光标：
##  - 对局态（scope）：干净的双层描边方形瞄准镜 + 四角对焦托架 + 中心点；蓄力时方框张开、命中时斜向弹开。
##  - 菜单/结算态（pointer）：金色菱形设计指针（带暗色描边），替换系统箭头，整体更协调。

class Reticle extends Control:
	var spread: float = 0.0
	var heat: float = 0.0
	var hit: float = 0.0
	var pt: Vector2 = Vector2.ZERO
	var mode: String = "scope"   # "scope" | "pointer"

	func _snap(v: float) -> float:
		return roundf(v)

	## 实心填充矩形（像素对齐）
	func _fill(x: float, y: float, w: float, h: float, c: Color) -> void:
		draw_rect(Rect2(Vector2(_snap(x), _snap(y)), Vector2(_snap(w), _snap(h))), c, true)

	## 描边矩形（空心框）
	func _stroke(x: float, y: float, w: float, h: float, c: Color, lw: float) -> void:
		draw_rect(Rect2(Vector2(_snap(x), _snap(y)), Vector2(_snap(w), _snap(h))), c, false, lw)

	## 水平/垂直粗线段（端点像素对齐）
	func _seg(x1: float, y1: float, x2: float, y2: float, c: Color) -> void:
		var rx := minf(x1, x2)
		var ry := minf(y1, y2)
		var rw := absf(x2 - x1)
		var rh := absf(y2 - y1)
		if rw < 1.0:
			rw = 1.0
		if rh < 1.0:
			rh = 1.0
		_fill(rx, ry, rw, rh, c)

	## 菱形（实心多边形）
	func _diamond(cx: float, cy: float, r: float, c: Color) -> void:
		var pts := PackedVector2Array([
			Vector2(cx, cy - r), Vector2(cx + r, cy),
			Vector2(cx, cy + r), Vector2(cx - r, cy)
		])
		draw_colored_polygon(pts, c)

	func _draw() -> void:
		if not visible or modulate.a <= 0.01:
			return
		# 进入对局但尚未移动鼠标时，光标先落在屏幕中心，避免卡在左上角
		if pt == Vector2.ZERO:
			pt = get_viewport().get_visible_rect().get_center()
		var cx := _snap(pt.x)
		var cy := _snap(pt.y)
		if mode == "pointer":
			_draw_pointer(cx, cy)
		else:
			_draw_scope(cx, cy)

	## 菜单/结算态：金色菱形设计指针
	func _draw_pointer(cx: float, cy: float) -> void:
		var gold := Color("#ffcc5c")
		var dark := Color(0.02, 0.0, 0.0, 0.85)
		var r := 7.0
		_diamond(cx, cy, r + 2.0, dark)   # 暗色描边
		_diamond(cx, cy, r, gold)          # 金色实心
		_fill(cx - 1.0, cy - 1.0, 2.0, 2.0, Color(0.1, 0.02, 0.0, 1.0))  # 中心点

	## 对局态：方形瞄准镜
	func _draw_scope(cx: float, cy: float) -> void:
		var col := Color("#ffcc5c").lerp(Color("#ff4422"), clampf(heat, 0.0, 1.0))
		var s := _snap(15.0 + spread * 0.45)
		var lw := 2.0
		# 暗色对比光晕（细描边，确保压在亮矿石上也清晰）
		_stroke(cx - s - 3.0, cy - s - 3.0, (s + 3.0) * 2.0, (s + 3.0) * 2.0, Color(0.02, 0.0, 0.0, 0.7), 1.0)
		# 主方形瞄准镜轮廓（亮金）
		_stroke(cx - s, cy - s, s * 2.0, s * 2.0, col, lw)
		# 四角对焦托架（向外短亮线，相机对焦风格）
		var arm := 7.0
		_seg(cx - s - arm, cy - s, cx - s, cy - s, col)
		_seg(cx - s, cy - s - arm, cx - s, cy - s, col)
		_seg(cx + s, cy - s, cx + s + arm, cy - s, col)
		_seg(cx + s, cy - s - arm, cx + s, cy - s, col)
		_seg(cx - s - arm, cy + s, cx - s, cy + s, col)
		_seg(cx - s, cy + s, cx - s, cy + s + arm, col)
		_seg(cx + s, cy + s, cx + s + arm, cy + s, col)
		_seg(cx + s, cy + s, cx + s, cy + s + arm, col)
		# 中心点
		_fill(cx - 1.0, cy - 1.0, 2.0, 2.0, col)
		# 命中标记：四道短划线沿对角线向外弹开
		if hit > 0.01:
			var hc := Color(1.0, 1.0, 1.0, clampf(hit, 0.0, 1.0))
			var hd := _snap(13.0 + (1.0 - hit) * 9.0)
			_seg(cx + hd, cy - hd, cx + hd + 5.0, cy - hd, hc)
			_seg(cx + hd, cy + hd - 1.0, cx + hd + 5.0, cy + hd - 1.0, hc)
			_seg(cx - hd - 5.0, cy + hd - 1.0, cx - hd, cy + hd - 1.0, hc)
			_seg(cx - hd - 5.0, cy - hd, cx - hd, cy - hd, hc)


var _ret: Reticle
var _spread: float = 0.0
var _target_spread: float = 0.0
var _heat: float = 0.0
var _target_heat: float = 0.0
var _hit: float = 0.0
var _pt: Vector2 = Vector2.ZERO
var _mode: String = "scope"


func _ready() -> void:
	layer = 60
	_ret = Reticle.new()
	_ret.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ret)
	_ret.visible = false


func set_target(p: Vector2, spread: float, heat: float) -> void:
	_pt = p
	_target_spread = spread
	_target_heat = heat


func set_mode(m: String) -> void:
	_mode = m
	if _ret != null:
		_ret.mode = m
		_ret.queue_redraw()


func hit_mark() -> void:
	_hit = 1.0


func set_reticle_visible(v: bool) -> void:
	_ret.visible = v


func _process(delta: float) -> void:
	if not _ret.visible:
		return
	_spread = lerpf(_spread, _target_spread, clampf(14.0 * delta, 0.0, 1.0))
	_heat = lerpf(_heat, _target_heat, clampf(12.0 * delta, 0.0, 1.0))
	_hit = maxf(0.0, _hit - delta * 4.5)
	_ret.spread = _spread
	_ret.heat = _heat
	_ret.hit = _hit
	_ret.pt = _pt
	_ret.queue_redraw()
