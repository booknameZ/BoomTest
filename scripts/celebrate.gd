class_name Celebrate
extends CanvasLayer
## 过关清屏特效：围绕中间打击区的老虎机式边框跑马灯 + 彩带飘落。
## 由 Main 触发 set_active(true) 播放，数秒后自动停止。

# 中栏打击区在 1280x720 下的范围（与 HUD 中栏对齐）
const MID_X := 258.0
const MID_Y := 68.0
const MID_W := 764.0
const MID_H := 642.0

# 暖色系庆祝调色板：火红 / 琥珀 / 金 / 象牙 / 铜橙，呼应暗黑老虎机的烛光质感
const BULB_COLORS := [
	Color("#c02030"), Color("#ffb43a"), Color("#ffd27a"),
	Color("#ff7a20"), Color("#a03828"), Color("#e8d8a8"),
]
const RIBBON_COLORS := [
	Color("#d03040"), Color("#ffc040"), Color("#ffd88a"),
	Color("#ff8030"), Color("#a83828"), Color("#e8d8b0"),
	Color("#ffb45a"), Color("#c89a58"),
]

class Ribbon:
	var rect: ColorRect
	var pos: Vector2
	var vel: Vector2
	var rot: float
	var rot_speed: float
	var phase: float
	var sway_amp: float

	func _init(r: ColorRect) -> void:
		rect = r
		pos = Vector2.ZERO
		vel = Vector2.ZERO
		rot = 0.0
		rot_speed = 0.0
		phase = 0.0
		sway_amp = 0.0


var _root: Control
var _bulbs: Array[ColorRect] = []
var _ribbons: Array[Ribbon] = []
var _active: bool = false
var _bulb_head: int = 0
var _bulb_timer: float = 0.0
var _auto_stop_timer: float = 0.0
var _auto_stop: bool = false


func _ready() -> void:
	layer = 30
	_build()
	set_active(false)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_bulbs()
	_build_ribbons()


func _build_bulbs() -> void:
	var sz := 14.0
	var gap := 26.0
	var inset := 4.0
	# 沿中栏四边顺时针排布：上 → 右 → 下 → 左
	var x := MID_X + inset
	while x < MID_X + MID_W - sz - inset:
		_bulbs.append(_bulb_rect(Vector2(x, MID_Y + inset), sz))
		x += gap
	var y := MID_Y + inset
	while y < MID_Y + MID_H - sz - inset:
		_bulbs.append(_bulb_rect(Vector2(MID_X + MID_W - sz - inset, y), sz))
		y += gap
	x = MID_X + MID_W - sz - inset
	while x > MID_X + inset:
		_bulbs.append(_bulb_rect(Vector2(x, MID_Y + MID_H - sz - inset), sz))
		x -= gap
	y = MID_Y + MID_H - sz - inset
	while y > MID_Y + inset:
		_bulbs.append(_bulb_rect(Vector2(MID_X + inset, y), sz))
		y -= gap


func _bulb_rect(pos: Vector2, sz: float) -> ColorRect:
	var c := ColorRect.new()
	c.size = Vector2(sz, sz)
	c.position = pos
	c.color = Color(0.12, 0.10, 0.08)
	_root.add_child(c)
	return c


func _build_ribbons() -> void:
	for i in 220:
		var c := ColorRect.new()
		var w := randf_range(3.0, 6.0)
		var h := randf_range(8.0, 20.0)
		c.size = Vector2(w, h)
		c.color = RIBBON_COLORS[i % RIBBON_COLORS.size()]
		c.pivot_offset = Vector2(w * 0.5, h * 0.5)
		_root.add_child(c)
		var r := Ribbon.new(c)
		_reset_ribbon(r, true)
		_ribbons.append(r)


func _reset_ribbon(r: Ribbon, initial: bool) -> void:
	r.pos = Vector2(randf_range(MID_X, MID_X + MID_W), -80.0 if initial else randf_range(-MID_H * 0.6, -40.0))
	r.vel = Vector2(0.0, randf_range(160.0, 360.0))
	r.rot = randf_range(0.0, TAU)
	r.rot_speed = randf_range(-5.0, 5.0)
	r.phase = randf_range(0.0, TAU)
	r.sway_amp = randf_range(24.0, 60.0)


func set_active(a: bool) -> void:
	_active = a
	_root.visible = a
	_auto_stop = false
	_auto_stop_timer = 0.0
	if a:
		Sfx.level_clear()


## 触发清屏特效，持续 duration 秒后自动停止。
func play(duration: float = 4.0) -> void:
	set_active(true)
	_auto_stop = true
	_auto_stop_timer = duration


func _process(delta: float) -> void:
	if not _active:
		return

	# 跑马灯：亮灯沿四边循环移动
	_bulb_timer -= delta
	if _bulb_timer <= 0.0:
		_bulb_timer = 0.04
		for i in _bulbs.size():
			var b := _bulbs[i]
			var d := int(abs(i - _bulb_head)) % _bulbs.size()
			var ci := (i / 2) % BULB_COLORS.size()
			if d <= 2:
				b.color = BULB_COLORS[ci].lightened(0.5)
				b.size = Vector2.ONE * 16.0
			elif d <= 5:
				b.color = BULB_COLORS[ci]
				b.size = Vector2.ONE * 13.0
			else:
				b.color = Color(0.10, 0.08, 0.06)
				b.size = Vector2.ONE * 11.0
		_bulb_head = (_bulb_head + 1) % _bulbs.size()

	# 彩带飘落：只在中栏范围内，横向摆动更明显
	for r in _ribbons:
		r.phase += delta
		r.pos.y += r.vel.y * delta
		r.pos.x += sin(r.phase * 2.5) * r.sway_amp * delta
		r.rot += r.rot_speed * delta
		if r.pos.y > MID_Y + MID_H + 90.0:
			_reset_ribbon(r, false)
		r.rect.position = r.pos
		r.rect.rotation = r.rot

	if _auto_stop:
		_auto_stop_timer -= delta
		if _auto_stop_timer <= 0.0:
			set_active(false)
