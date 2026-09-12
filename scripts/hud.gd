class_name HUD
extends CanvasLayer
## 顶部 HUD + 结算界面。layer=30 盖在场景之上。
## 参考图：暗酒红底 + 鎏金骷髅边框 + 左侧 CHARGE 竖条 + 右侧 COMBO 面板。

signal restart_pressed
signal menu_requested
signal pause_requested

var pause_btn: Button
var hearts_box: HBoxContainer
var level_label: Label
var score_label: Label
var target_hint_label: Label
var lives_label: Label
var combo_top_label: Label
var combo_sub_label: Label
var mult_disp: Label
var power_track: Panel
var power_fill: ColorRect
var power_segs: Array[ColorRect] = []
var pool_label: Label
var flash: ColorRect
var red_flash: ColorRect
var danger_overlay: ColorRect
var game_over: Control
var final_score_label: Label
var final_level_label: Label
var title_label: Label
var slot_label: Label
var slot_panel: Panel

var _font: Font

# 参考图配色
const BG := Color("#0d0202")
const CRIM := Color("#1a0505")
const CRIM_PANEL := Color("#5a0d08")
const GOLD := Color("#ffcc5c")
const GOLD_DK := Color("#b88a2a")
const GOLD_BRIGHT := Color("#ffe680")
const RED_GLOW := Color("#ff2a2a")
const ORANGE_GLOW := Color("#ff8800")

# 像素骷髅 9x9
const _SKULL_PIXELS := [
	"001111100",
	"011111110",
	"111111111",
	"111001111",
	"111001111",
	"111111111",
	"011111110",
	"010110010",
	"001001100",
]

# 像素皇冠 9x7
const _CROWN_PIXELS := [
	"001000100",
	"001101100",
	"011111110",
	"111111111",
	"101111101",
	"100000001",
	"111111111",
]

# 像素星星 9x9
const _STAR_PIXELS := [
	"000010000",
	"000111000",
	"001111100",
	"011111110",
	"111111111",
	"011111110",
	"001111100",
	"000111000",
	"000010000",
]

# 像素筹码 11x11（红底白纹）
const _CHIP_PIXELS := [
	"00111111100",
	"01111111110",
	"11100110011",
	"11001100111",
	"11011111101",
	"11011111101",
	"11011111101",
	"11100110011",
	"11001100111",
	"01111111110",
	"00111111100",
]

var _skull_tex: Texture2D
var _crown_tex: Texture2D
var _star_tex: Texture2D
var _chip_tex: Texture2D


func _ready() -> void:
	layer = 30
	_font = _load_pixel_font()
	_skull_tex = _pixel_tex(_SKULL_PIXELS, Color("#e8dcc0"))
	_crown_tex = _pixel_tex(_CROWN_PIXELS, GOLD_BRIGHT)
	_star_tex = _pixel_tex(_STAR_PIXELS, GOLD_BRIGHT)
	_chip_tex = _pixel_tex(_CHIP_PIXELS, Color("#ff3a3a"))
	build()


func _load_pixel_font() -> Font:
	var path := "res://fonts/PressStart2P-Regular.ttf"
	if ResourceLoader.exists(path):
		var f := load(path) as FontFile
		if f != null:
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			f.hinting = TextServer.HINTING_NONE
			return f
	return ThemeDB.fallback_font


func _style(l: Label, size: int, color: Color, outline: int = 2) -> void:
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)


func _pixel_tex(pixels: Array, color: Color) -> Texture2D:
	var w: int = pixels[0].length()
	var h: int = pixels.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = pixels[y]
		for x in row.length():
			img.set_pixel(x, y, color if row[x] == "1" else Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta("w", w)
	tex.set_meta("h", h)
	return tex


func build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_ambiance(root)
	_build_panels(root)
	_build_top_bar(root)
	_build_charge(root)
	_build_combo(root)
	_build_pool_label(root)
	_build_flashes(root)
	_build_slot(root)
	_build_game_over(root)


# ==================== 整体暗红氛围罩 ====================
## 整体暗红氛围罩：让近黑的背景透出血色，向参考图的暗红基调靠拢（统一协调，不喧宾夺主）。
## 置于最底层，框体/文字/矿石绘制在其之上。
func _build_ambiance(root: Control) -> void:
	# 均匀暗红罩：压低纯黑、整体染血色
	var wash := ColorRect.new()
	wash.color = Color(0.15, 0.03, 0.025, 0.22)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wash)

	# 中心径向血光：强化 ARENA 纵深，避免中心空洞
	var grad := Gradient.new()
	grad.set_color(0, Color(0.45, 0.08, 0.06, 0.18))
	grad.set_color(1, Color(0.10, 0.02, 0.02, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	var glow := TextureRect.new()
	glow.texture = tex
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)


# ==================== 装饰边框 ====================
func _panel(parent: Control, bg: Color, border: Color, border_w: float = 2.0) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(border_w))
	sb.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


## 绘制装饰边框：外粗金线 + 双内细金线 + 四角骷髅饰钉 + 边角托架 + 边框铆钉
func _ornate_frame(parent: Control, rect: Rect2, bg: Color = CRIM_PANEL) -> Panel:
	var outer := _panel(parent, bg, GOLD, 3.0)
	outer.position = rect.position
	outer.size = rect.size

	# 双内框线：贴近外框 + 内部装饰线（保留繁复装饰感）
	var inner1 := _panel(parent, Color(0, 0, 0, 0), GOLD_DK, 1.0)
	inner1.position = rect.position + Vector2(4, 4)
	inner1.size = rect.size - Vector2(8, 8)

	var inner2 := _panel(parent, Color(0, 0, 0, 0), Color(GOLD, 0.35), 1.0)
	inner2.position = rect.position + Vector2(8, 8)
	inner2.size = rect.size - Vector2(16, 16)

	# 四角骷髅饰钉
	var skull_size := 24
	var corners := [
		rect.position + Vector2(4, 4),
		rect.position + Vector2(rect.size.x - skull_size - 4, 4),
		rect.position + Vector2(4, rect.size.y - skull_size - 4),
		rect.position + Vector2(rect.size.x - skull_size - 4, rect.size.y - skull_size - 4),
	]
	for c in corners:
		var s := TextureRect.new()
		s.texture = _skull_tex
		s.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.custom_minimum_size = Vector2(skull_size, skull_size)
		s.position = c
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(s)

	# L 型金属托架
	var tl := rect.position
	var br := rect.position + rect.size
	var brackets := [
		[tl + Vector2(30, 7), tl + Vector2(62, 7), 3, 3],   # 左上横
		[tl + Vector2(7, 30), tl + Vector2(7, 62), 3, 3],   # 左上竖
		[Vector2(br.x - 62, tl.y + 7), Vector2(br.x - 30, tl.y + 7), 3, 3],   # 右上横
		[Vector2(br.x - 10, tl.y + 30), Vector2(br.x - 10, tl.y + 62), 3, 3], # 右上竖
		[tl + Vector2(30, br.y - 10), tl + Vector2(62, br.y - 10), 3, 3],      # 左下横
		[tl + Vector2(7, br.y - 62), tl + Vector2(7, br.y - 30), 3, 3],        # 左下竖
		[Vector2(br.x - 62, br.y - 10), Vector2(br.x - 30, br.y - 10), 3, 3],  # 右下横
		[Vector2(br.x - 10, br.y - 62), Vector2(br.x - 10, br.y - 30), 3, 3],  # 右下竖
	]
	for b in brackets:
		var r := ColorRect.new()
		r.color = GOLD_DK
		r.position = b[0]
		r.size = b[1] - b[0]
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(r)

	# 上下边框铆钉（小菱形），参考图侧栏顶部/底部有一排装饰钉
	var stud_w := 5.0
	for y_off: float in [10.0, rect.size.y - 15.0]:
		var x := rect.position.x + 20.0
		while x < rect.position.x + rect.size.x - 20.0:
			var stud := Polygon2D.new()
			stud.color = GOLD_BRIGHT
			var sx := x
			var sy := rect.position.y + y_off
			stud.polygon = PackedVector2Array([
				Vector2(sx, sy - stud_w * 0.5),
				Vector2(sx + stud_w * 0.5, sy),
				Vector2(sx, sy + stud_w * 0.5),
				Vector2(sx - stud_w * 0.5, sy),
			])
			parent.add_child(stud)
			x += 22.0

	return outer


## 顶部拱形装饰：哥特尖拱 + 中央皇冠 + 侧边小尖刺，贴近参考图侧栏顶饰
func _arch_top(parent: Control, x_center: float, y_top: float, width: float, height: float) -> void:
	var hw := width * 0.5
	var peak := Vector2(x_center, y_top)
	var base_l := Vector2(x_center - hw, y_top + height)
	var base_r := Vector2(x_center + hw, y_top + height)

	# 实心三角楣
	var poly := Polygon2D.new()
	poly.color = CRIM_PANEL
	poly.polygon = PackedVector2Array([base_l, base_r, peak])
	poly.position = Vector2.ZERO
	parent.add_child(poly)

	# 两侧斜边金线（加粗，更醒目）
	for pts in [[base_l, peak], [base_r, peak]]:
		var ln := Line2D.new()
		ln.points = PackedVector2Array(pts)
		ln.width = 3.0
		ln.default_color = GOLD
		ln.joint_mode = Line2D.LINE_JOINT_SHARP
		ln.begin_cap_mode = Line2D.LINE_CAP_NONE
		ln.end_cap_mode = Line2D.LINE_CAP_NONE
		ln.antialiased = false
		parent.add_child(ln)

	# 底部横杠
	var bar := ColorRect.new()
	bar.color = GOLD
	bar.position = Vector2(x_center - hw - 2, y_top + height - 2)
	bar.size = Vector2(width + 4, 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)

	# 顶部尖顶：小皇冠图标
	var crown := TextureRect.new()
	crown.texture = _crown_tex
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.custom_minimum_size = Vector2(18, 14)
	crown.position = Vector2(x_center - 9, y_top - 7)
	crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(crown)

	# 两侧小尖刺
	for off: float in [-1.0, 1.0]:
		var sp := Polygon2D.new()
		sp.color = GOLD_BRIGHT
		var sx: float = x_center + off * (hw + 6)
		sp.polygon = PackedVector2Array([
			Vector2(sx, y_top + height - 4),
			Vector2(sx - off * 5, y_top + height * 0.35),
			Vector2(sx - off * 2, y_top + height - 6),
		])
		parent.add_child(sp)

	# 底部两角小饰钉
	for off in [-1.0, 1.0]:
		var stud := ColorRect.new()
		stud.color = GOLD_DK
		stud.position = Vector2(x_center + off * hw - 2, y_top + height - 4)
		stud.size = Vector2(4, 4)
		stud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(stud)


# ==================== 三栏面板 ====================
func _build_panels(root: Control) -> void:
	var top := 78
	var bot := -10
	var gap := 8
	var side_w := 152
	# 左面板
	_ornate_frame(root, Rect2(Vector2(14, top), Vector2(side_w, 720 - top + bot)), CRIM_PANEL)
	_arch_top(root, 14 + side_w * 0.5, top - 32, 64, 32)
	# 右面板
	_ornate_frame(root, Rect2(Vector2(1280 - 14 - side_w, top), Vector2(side_w, 720 - top + bot)), CRIM_PANEL)
	_arch_top(root, 1280 - 14 - side_w * 0.5, top - 32, 64, 32)
	# 中面板（极暗酒红半透明底，参考图 ARENA 有暗色衬底）
	var mid_x := 14 + side_w + gap
	var mid_w := 1280 - mid_x * 2
	var mid_h := 720 - top + bot
	# 中面板背景必须完全透明：本渲染器下 StyleBoxFlat 的半透明填充会被当不透明处理，
	# 任何 alpha>0 都会把 3D 竞技场（轮盘/矿石）整个盖住。只保留金色边框与装饰，竞技场透出。
	_ornate_frame(root, Rect2(Vector2(mid_x, top), Vector2(mid_w, mid_h)), Color(0.0, 0.0, 0.0, 0.0))
	# 中栏顶部装饰：左右小骷髅 + 中央小皇冠
	for off in [-1.0, 1.0]:
		var sk := TextureRect.new()
		sk.texture = _skull_tex
		sk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sk.custom_minimum_size = Vector2(18, 18)
		sk.position = Vector2(mid_x + (mid_w - 18) * (off * 0.5 + 0.5), top - 14)
		sk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(sk)
	var top_crown := TextureRect.new()
	top_crown.texture = _crown_tex
	top_crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_crown.custom_minimum_size = Vector2(18, 14)
	top_crown.position = Vector2(mid_x + mid_w * 0.5 - 9, top - 12)
	top_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_crown)
	# 中栏底部装饰横条
	var bot_bar := ColorRect.new()
	bot_bar.color = Color(GOLD, 0.35)
	bot_bar.position = Vector2(mid_x + 20, top + mid_h - 16)
	bot_bar.size = Vector2(mid_w - 40, 3)
	bot_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bot_bar)
	for off in [-1.0, 1.0]:
		var stud := ColorRect.new()
		stud.color = GOLD_BRIGHT
		stud.position = Vector2(mid_x + 20 + (mid_w - 40 - 4) * (off * 0.5 + 0.5), top + mid_h - 18)
		stud.size = Vector2(4, 6)
		stud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(stud)


# ==================== 顶部栏 ====================
func _build_top_bar(root: Control) -> void:
	# 背景条
	var bar := ColorRect.new()
	bar.color = Color("#0f0202")
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 66
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	# 暂停按钮
	pause_btn = Button.new()
	pause_btn.add_theme_font_override("font", _font)
	pause_btn.add_theme_font_size_override("font_size", 18)
	pause_btn.add_theme_color_override("font_color", GOLD_BRIGHT)
	pause_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.1, 0.02, 0.02, 0.95)
	psb.border_color = GOLD_DK
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(0)
	pause_btn.add_theme_stylebox_override("normal", psb)
	pause_btn.add_theme_stylebox_override("hover", psb)
	pause_btn.add_theme_stylebox_override("pressed", psb)
	pause_btn.position = Vector2(18, 14)
	pause_btn.size = Vector2(40, 40)
	var pi := Control.new()
	pi.name = "PauseIcon"
	pi.position = Vector2(0, 0)
	pi.size = Vector2(40, 40)
	pause_btn.add_child(pi)
	var lbar := ColorRect.new()
	lbar.color = GOLD_BRIGHT
	lbar.position = Vector2(13, 11)
	lbar.size = Vector2(5, 18)
	pi.add_child(lbar)
	var rbar := ColorRect.new()
	rbar.color = GOLD_BRIGHT
	rbar.position = Vector2(22, 11)
	rbar.size = Vector2(5, 18)
	pi.add_child(rbar)
	pause_btn.pressed.connect(func() -> void: pause_requested.emit())
	root.add_child(pause_btn)

	# 心形
	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 5)
	hearts_box.position = Vector2(66, 18)
	hearts_box.size = Vector2(200, 32)
	hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hearts_box)
	for i in 8:
		var r := TextureRect.new()
		r.texture = _heart_tex(Color("#ff3a3a"))
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(24, 24)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.name = "h%d" % i
		r.visible = i < 3
		hearts_box.add_child(r)

	# 关卡徽章（中）
	var level_panel := _panel(root, Color("#180303"), GOLD, 2.0)
	level_panel.position = Vector2(520, 12)
	level_panel.size = Vector2(240, 44)
	# 徽章上方小皇冠
	var lvl_crown := TextureRect.new()
	lvl_crown.texture = _crown_tex
	lvl_crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lvl_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lvl_crown.custom_minimum_size = Vector2(22, 18)
	lvl_crown.position = Vector2(629, -2)
	lvl_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lvl_crown)
	level_label = Label.new()
	_style(level_label, 16, GOLD_BRIGHT, 2)
	level_label.text = "第 1 关"
	level_label.position = Vector2(520, 18)
	level_label.size = Vector2(240, 36)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(level_label)

	# 分数徽章（右上）
	var score_panel := _panel(root, Color("#180303"), GOLD, 2.0)
	score_panel.position = Vector2(830, 12)
	score_panel.size = Vector2(200, 44)
	score_label = Label.new()
	_style(score_label, 14, GOLD_BRIGHT, 2)
	score_label.text = "0 / 50分"
	score_label.position = Vector2(830, 18)
	score_label.size = Vector2(200, 36)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(score_label)

	# 生命值（右）
	var lives_panel := _panel(root, Color("#180303"), GOLD, 2.0)
	lives_panel.position = Vector2(1050, 12)
	lives_panel.size = Vector2(120, 44)
	lives_label = Label.new()
	_style(lives_label, 14, GOLD_BRIGHT, 2)
	lives_label.text = "0 / 3"
	lives_label.position = Vector2(1050, 18)
	lives_label.size = Vector2(120, 24)
	lives_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lives_label)

	target_hint_label = Label.new()
	_style(target_hint_label, 9, GOLD_DK, 1)
	target_hint_label.text = "LIVES 3"
	target_hint_label.position = Vector2(1050, 42)
	target_hint_label.size = Vector2(120, 18)
	target_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(target_hint_label)


func _heart_tex(color: Color) -> Texture2D:
	var pixels := [
		"00110110",
		"11111111",
		"11111111",
		"11111111",
		"00111100",
		"00011000",
		"00000000",
	]
	var w: int = pixels[0].length()
	var h: int = pixels.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = pixels[y]
		for x in row.length():
			img.set_pixel(x, y, color if row[x] == "1" else Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	return tex


# ==================== 左侧 CHARGE 分段竖条 ====================
func _build_charge(root: Control) -> void:
	# 标题
	var title := Label.new()
	_style(title, 12, GOLD_BRIGHT, 2)
	title.text = "CHARGE"
	title.position = Vector2(14, 90)
	title.size = Vector2(152, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# 外框
	var frame := _panel(root, Color("#0d0202"), GOLD, 2.0)
	frame.position = Vector2(42, 124)
	frame.size = Vector2(96, 512)

	# 发光条背景
	power_track = _panel(root, Color("#1a0505"), GOLD_DK, 1.0)
	power_track.position = Vector2(54, 136)
	power_track.size = Vector2(72, 488)

	# 分段格：从底向上
	power_segs = []
	var seg_n := 16
	var h := 488.0 / seg_n
	for i in seg_n:
		var s := ColorRect.new()
		s.color = Color("#3a1010")
		s.position = Vector2(58, 136 + i * h + 1)
		s.size = Vector2(64, h - 2)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(s)
		power_segs.append(s)

	# 竖条两侧金线（参考图 CHARGE 内框）
	for off: float in [56.0, 124.0]:
		var ln := ColorRect.new()
		ln.color = GOLD_DK
		ln.position = Vector2(off, 138)
		ln.size = Vector2(2, 484)
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ln)

	# 左侧圆形按钮/指示灯：外金环 + 内发光红点
	var btn := Panel.new()
	btn.position = Vector2(26, 360)
	btn.size = Vector2(28, 28)
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#1a0505")
	bsb.border_color = GOLD
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("panel", bsb)
	root.add_child(btn)

	# 内红点
	var btn_dot := Panel.new()
	btn_dot.position = Vector2(32, 366)
	btn_dot.size = Vector2(16, 16)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color("#ff3a3a")
	dsb.set_corner_radius_all(8)
	btn_dot.add_theme_stylebox_override("panel", dsb)
	root.add_child(btn_dot)


# ==================== 右侧 COMBO 面板 ====================
func _build_combo(root: Control) -> void:
	var rx := 1280 - 14 - 152

	# COMBO 大标题
	combo_top_label = Label.new()
	_style(combo_top_label, 24, GOLD_BRIGHT, 3)
	combo_top_label.text = "COMBO"
	combo_top_label.position = Vector2(rx, 110)
	combo_top_label.size = Vector2(152, 36)
	combo_top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(combo_top_label)

	# 小 COMBO 副标题
	combo_sub_label = Label.new()
	_style(combo_sub_label, 12, GOLD, 2)
	combo_sub_label.text = "COMBO"
	combo_sub_label.position = Vector2(rx, 148)
	combo_sub_label.size = Vector2(152, 20)
	combo_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(combo_sub_label)

	# 皇冠 + 星星装饰
	var crown := TextureRect.new()
	crown.texture = _crown_tex
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.custom_minimum_size = Vector2(22, 18)
	crown.position = Vector2(rx + 36, 176)
	crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crown)

	var star := TextureRect.new()
	star.texture = _star_tex
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.custom_minimum_size = Vector2(18, 18)
	star.position = Vector2(rx + 94, 176)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(star)

	# 大倍率数字
	mult_disp = Label.new()
	_style(mult_disp, 42, GOLD_BRIGHT, 4)
	mult_disp.text = "00"
	mult_disp.position = Vector2(rx, 210)
	mult_disp.size = Vector2(152, 60)
	mult_disp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(mult_disp)

	# 骷髅 + 筹码
	var skull := TextureRect.new()
	skull.texture = _skull_tex
	skull.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skull.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skull.custom_minimum_size = Vector2(48, 48)
	skull.position = Vector2(rx + 52, 540)
	skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(skull)

	var chip_l := TextureRect.new()
	chip_l.texture = _chip_tex
	chip_l.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip_l.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip_l.custom_minimum_size = Vector2(32, 32)
	chip_l.position = Vector2(rx + 18, 548)
	chip_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chip_l)

	var chip_r := TextureRect.new()
	chip_r.texture = _chip_tex
	chip_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip_r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip_r.custom_minimum_size = Vector2(32, 32)
	chip_r.position = Vector2(rx + 102, 548)
	chip_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chip_r)

	# 小星星点缀
	for off in [Vector2(rx + 30, 520), Vector2(rx + 110, 520)]:
		var s := TextureRect.new()
		s.texture = _star_tex
		s.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.custom_minimum_size = Vector2(10, 10)
		s.position = off
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(s)


# ==================== 底部料池标签 ====================
func _build_pool_label(root: Control) -> void:
	pool_label = Label.new()
	pool_label.text = "ORE POOL 0%"
	_style(pool_label, 11, GOLD_DK, 2)
	pool_label.anchor_left = 0.5
	pool_label.anchor_right = 0.5
	pool_label.anchor_top = 1.0
	pool_label.anchor_bottom = 1.0
	pool_label.offset_left = -170
	pool_label.offset_right = 170
	pool_label.offset_top = -42
	pool_label.offset_bottom = -22
	pool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(pool_label)

	# 底部操作提示（参考图：按住蓄力 · 松开发射）
	var hint := Label.new()
	_style(hint, 11, GOLD, 2)
	hint.text = "HOLD TO CHARGE · RELEASE TO FIRE"
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -240
	hint.offset_right = 240
	hint.offset_top = -22
	hint.offset_bottom = -4
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)


# ==================== 闪屏 + 警示层 ====================
func _build_flashes(root: Control) -> void:
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0.7)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.visible = false
	root.add_child(flash)

	red_flash = ColorRect.new()
	red_flash.color = Color(0.8, 0.05, 0.05, 0.5)
	red_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	red_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_flash.visible = false
	root.add_child(red_flash)

	danger_overlay = ColorRect.new()
	danger_overlay.color = Color(1.0, 0.05, 0.02, 0.0)
	danger_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	danger_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(danger_overlay)


# ==================== 老虎机滚动奖励名 ====================
func _build_slot(root: Control) -> void:
	slot_panel = _panel(root, Color(0.05, 0.02, 0.02, 0.92), GOLD, 3.0)
	slot_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	slot_panel.offset_left = -180
	slot_panel.offset_right = 180
	slot_panel.offset_top = -300
	slot_panel.offset_bottom = -244
	slot_panel.visible = false

	slot_label = Label.new()
	slot_label.add_theme_font_override("font", _font)
	slot_label.add_theme_font_size_override("font_size", 24)
	slot_label.add_theme_color_override("font_color", GOLD_BRIGHT)
	slot_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	slot_label.add_theme_constant_override("outline_size", 3)
	slot_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	slot_label.offset_left = -170
	slot_label.offset_right = 170
	slot_label.offset_top = -296
	slot_label.offset_bottom = -248
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(slot_label)


func show_slot_name(text: String, color: Color) -> void:
	slot_label.text = text
	slot_label.add_theme_color_override("font_color", color)
	slot_panel.visible = true
	slot_label.visible = true


func hide_slot() -> void:
	slot_panel.visible = false
	slot_label.visible = false


# ==================== 结算界面 ====================
func _build_game_over(root: Control) -> void:
	game_over = Control.new()
	game_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over.visible = false
	root.add_child(game_over)

	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.01, 0.0, 0.94)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over.add_child(overlay)

	var panel := _panel(game_over, Color(0.08, 0.02, 0.02, 0.95), Color("#a02828"), 2.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -250
	panel.offset_bottom = 180

	title_label = Label.new()
	title_label.add_theme_font_override("font", _font)
	title_label.add_theme_font_size_override("font_size", 40)
	title_label.add_theme_color_override("font_color", Color("#ff4040"))
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title_label.add_theme_constant_override("outline_size", 5)
	title_label.text = "GAME OVER"
	title_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title_label.offset_left = -170
	title_label.offset_right = 170
	title_label.offset_top = -232
	title_label.offset_bottom = -176
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over.add_child(title_label)

	var sub := Label.new()
	sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color("#ffaa66"))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 2)
	sub.text = "THE MINE COLLAPSED!"
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.offset_left = -170
	sub.offset_right = 170
	sub.offset_top = -170
	sub.offset_bottom = -148
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over.add_child(sub)

	var div := ColorRect.new()
	div.color = Color(0.6, 0.25, 0.2, 0.6)
	div.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	div.offset_left = -100
	div.offset_right = 100
	div.offset_top = -130
	div.offset_bottom = -128
	game_over.add_child(div)

	var score_lab := Label.new()
	score_lab.add_theme_font_override("font", _font)
	score_lab.add_theme_font_size_override("font_size", 12)
	score_lab.add_theme_color_override("font_color", Color("#c8a86a"))
	score_lab.text = "SCORE"
	score_lab.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	score_lab.offset_left = -170
	score_lab.offset_right = 170
	score_lab.offset_top = -108
	score_lab.offset_bottom = -90
	score_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over.add_child(score_lab)

	final_score_label = Label.new()
	final_score_label.add_theme_font_override("font", _font)
	final_score_label.add_theme_font_size_override("font_size", 28)
	final_score_label.add_theme_color_override("font_color", Color("#ffd27a"))
	final_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	final_score_label.add_theme_constant_override("outline_size", 4)
	final_score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	final_score_label.offset_left = -170
	final_score_label.offset_right = 170
	final_score_label.offset_top = -86
	final_score_label.offset_bottom = -54
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over.add_child(final_score_label)

	var lvl_lab := Label.new()
	lvl_lab.add_theme_font_override("font", _font)
	lvl_lab.add_theme_font_size_override("font_size", 12)
	lvl_lab.add_theme_color_override("font_color", Color("#c8a86a"))
	lvl_lab.text = "REACHED"
	lvl_lab.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lvl_lab.offset_left = -170
	lvl_lab.offset_right = 170
	lvl_lab.offset_top = -40
	lvl_lab.offset_bottom = -22
	lvl_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over.add_child(lvl_lab)

	final_level_label = Label.new()
	final_level_label.add_theme_font_override("font", _font)
	final_level_label.add_theme_font_size_override("font_size", 22)
	final_level_label.add_theme_color_override("font_color", Color("#ffd27a"))
	final_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	final_level_label.add_theme_constant_override("outline_size", 3)
	final_level_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	final_level_label.offset_left = -170
	final_level_label.offset_right = 170
	final_level_label.offset_top = -20
	final_level_label.offset_bottom = 8
	final_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over.add_child(final_level_label)

	var btn := _styled_button("RETRY", 18)
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	btn.offset_left = -94
	btn.offset_right = 94
	btn.offset_top = 28
	btn.offset_bottom = 76
	btn.pressed.connect(func() -> void: restart_pressed.emit())
	game_over.add_child(btn)

	var menu_btn := _styled_button("MENU", 16)
	menu_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_btn.offset_left = -94
	menu_btn.offset_right = 94
	menu_btn.offset_top = 92
	menu_btn.offset_bottom = 140
	menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	game_over.add_child(menu_btn)


func _styled_button(text: String, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", GOLD_BRIGHT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("#ffe0a0"))
	b.add_theme_color_override("font_focus_color", GOLD_BRIGHT)
	var nb := StyleBoxFlat.new()
	nb.bg_color = Color("#2a1008")
	nb.border_color = GOLD_DK
	nb.set_border_width_all(2)
	nb.set_corner_radius_all(0)
	nb.content_margin_left = 22
	nb.content_margin_right = 22
	nb.content_margin_top = 8
	nb.content_margin_bottom = 8
	var hb := nb.duplicate() as StyleBoxFlat
	hb.bg_color = Color("#4a1a0c")
	hb.border_color = GOLD_BRIGHT
	var pb := nb.duplicate() as StyleBoxFlat
	pb.bg_color = Color("#1a0804")
	b.add_theme_stylebox_override("normal", nb)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", pb)
	b.add_theme_stylebox_override("focus", nb)
	return b


# ==================== 外部 API ====================
func set_hearts(n: int, max_n: int = 3) -> void:
	for i in hearts_box.get_child_count():
		var r := hearts_box.get_child(i) as TextureRect
		r.visible = i < max_n
		r.texture = _heart_tex(Color("#ff3a3a")) if i < n else _heart_tex(Color(0.25, 0.08, 0.08, 0.65))


func set_level(n: int) -> void:
	level_label.text = "LV %d" % n


func set_score(cur: int, target: int) -> void:
	score_label.text = "%d / %d" % [cur, target]


func set_multiplier(v: float, remaining: int) -> void:
	var new_text := "x%.1f" % v
	if combo_sub_label.text != new_text:
		combo_sub_label.text = new_text
	var col := GOLD_BRIGHT
	if remaining <= 3:
		col = RED_GLOW
	elif remaining <= 6:
		col = ORANGE_GLOW
	combo_sub_label.add_theme_color_override("font_color", col)


func hide_multiplier() -> void:
	combo_sub_label.text = "COMBO"
	combo_sub_label.add_theme_color_override("font_color", GOLD)


func set_combo(n: int) -> void:
	var new_text := "%02d" % n
	if mult_disp.text != new_text:
		mult_disp.text = new_text
	mult_disp.add_theme_color_override("font_color", GOLD_BRIGHT)


func set_power(ratio: float, visible: bool) -> void:
	power_track.visible = true
	var r := clampf(ratio, 0.0, 1.0)
	var lit := int(r * float(power_segs.size()) + 0.5)
	for i in power_segs.size():
		# 数组 0 在顶，反转使底部先亮
		var seg: ColorRect = power_segs[power_segs.size() - 1 - i]
		if i < lit:
			var t := float(i) / float(maxi(power_segs.size() - 1, 1))
			# 底部炽金 → 中部炉橙 → 顶部暗红，饱和度拉高更贴近参考图
			var c := Color("#c02010").lerp(RED_GLOW, t)
			if t > 0.35:
				c = RED_GLOW.lerp(GOLD_BRIGHT, (t - 0.35) * 1.54)
			# 偶数格做棋盘高亮，模拟参考图里的格子纹理
			if i % 2 == 0:
				c = c.lightened(0.18)
			seg.color = c
		else:
			seg.color = Color("#2a0a0a")


func set_energy(cur: float, full: float) -> void:
	var ratio := clampf(cur / full, 0.0, 1.0) if full > 0.0 else 0.0
	if ratio >= 1.0:
		pool_label.text = "POOL FULL"
		pool_label.add_theme_color_override("font_color", GOLD_BRIGHT)
	else:
		pool_label.text = "ORE POOL %d%%" % int(ratio * 100.0)
		pool_label.add_theme_color_override("font_color", Color(GOLD_DK, 0.55))


func set_danger(v: float) -> void:
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.02)
	danger_overlay.color.a = clampf(v, 0.0, 1.0) * 0.34 * pulse


func flash_white() -> void:
	flash.visible = true
	await get_tree().create_timer(0.08).timeout
	flash.visible = false


func flash_red() -> void:
	red_flash.visible = true
	await get_tree().create_timer(0.2).timeout
	red_flash.visible = false


func show_game_over(score: int, level: int) -> void:
	final_score_label.text = "%d" % score
	final_level_label.text = "LV %d" % level
	game_over.visible = true
	title_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(title_label, "modulate:a", 1.0, 0.4)
	tw.tween_property(title_label, "scale", Vector2(1.06, 1.06), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func hide_game_over() -> void:
	game_over.visible = false
