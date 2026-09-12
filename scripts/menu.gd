class_name Menu
extends CanvasLayer
## 主菜单 + 设置界面。layer=30 盖在场景之上。
## 字体只使用 Press Start 2P（像素字体无中文覆盖），
## 中文文本一律改用英文 / 拉丁字符 + 像素图形，确保全 UI 100% 像素。
## 设置：BGM / SFX / GLOW / SHAKE，持久化到 user://settings.cfg。

signal start_requested

const SETTINGS_PATH := "user://settings.cfg"

var bgm_volume := 0.6
var sfx_volume := 1.0
var glow_enabled := true
var screen_shake := true

var main: Main

var _font: Font
var _root: Control
var _menu_panel: Control
var _settings_panel: Control
var _start_btn: Button

var _bgm_slider: HSlider
var _sfx_slider: HSlider
var _glow_btn: Button
var _shake_btn: Button
var _bgm_val: Label
var _sfx_val: Label


func _ready() -> void:
	layer = 30
	_font = _load_pixel_font()
	_load_settings()
	_build()
	_sync_widgets()
	_apply_audio()


## 加载 Press Start 2P 像素字体：禁用抗锯齿 / 子像素定位 / hinting。
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


func configure(m: Main) -> void:
	main = m


# ==================== 构建 ====================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_menu_panel()
	_build_settings_panel()


func _build_menu_panel() -> void:
	_menu_panel = Control.new()
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.01, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_panel.add_child(dim)

	# 整屏细边框（琥珀描边，强化"拼接面板"质感）
	var frame := _panel(_menu_panel, Color(0, 0, 0, 0), Color("#b8882f"), 0, 2.0, false)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 8
	frame.offset_right = -8
	frame.offset_top = 8
	frame.offset_bottom = -8

	# 标题
	var title := _label("BOOM ORE", 66, Color("#ffd27a"), 6)
	title.position = Vector2(0, 86)
	title.size = Vector2(1280, 84)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_panel.add_child(title)

	var subtitle := _label("MINE  ROULETTE", 18, Color("#c89a58"), 2)
	subtitle.position = Vector2(0, 184)
	subtitle.size = Vector2(1280, 26)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_panel.add_child(subtitle)

	# 分隔线
	var div := ColorRect.new()
	div.color = Color(0.6, 0.4, 0.2, 0.5)
	div.position = Vector2(540, 228)
	div.size = Vector2(200, 3)
	_menu_panel.add_child(div)

	# 玩法说明面板（居中卡片）
	var how := _panel(_menu_panel, Color(0.06, 0.03, 0.02, 0.9), Color(0.4, 0.3, 0.18, 0.8), 0, 2.0, false)
	how.position = Vector2(330, 268)
	how.size = Vector2(620, 300)

	var lines := [
		"> DRAG TO AIM, RELEASE TO FIRE",
		"> BALL BREAKS ORES & BRICKS",
		"> BROKEN ORES DROP GEMS",
		"> GEMS FILL THE ORE POOL",
		"> 2-TAP BALL TO RECALL IT",
		"> DON'T CROSS THE RED LINE!",
	]
	var y0 := 286
	for i in lines.size():
		var t := _label(lines[i], 12, Color("#e8d8b8"), 1)
		t.position = Vector2(352, y0 + i * 38)
		t.size = Vector2(576, 26)
		_menu_panel.add_child(t)

	# 开始按钮
	_start_btn = _button("START", 24)
	_start_btn.position = Vector2(510, 600)
	_start_btn.size = Vector2(260, 66)
	_start_btn.pressed.connect(_on_start_pressed)
	_menu_panel.add_child(_start_btn)

	# 设置按钮
	var settings_btn := _button("SETUP", 18)
	settings_btn.position = Vector2(540, 676)
	settings_btn.size = Vector2(200, 42)
	settings_btn.pressed.connect(_on_open_settings)
	_menu_panel.add_child(settings_btn)


func _build_settings_panel() -> void:
	_settings_panel = Control.new()
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	_root.add_child(_settings_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.01, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(dim)

	var title := _label("SETUP", 40, Color("#ffd27a"), 5)
	title.position = Vector2(40, 88)
	title.size = Vector2(400, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_panel.add_child(title)

	var panel := _panel(_settings_panel, Color(0.06, 0.03, 0.02, 0.94), Color(0.4, 0.3, 0.18, 0.8), 0, 2.0, false)
	panel.position = Vector2(38, 168)
	panel.size = Vector2(404, 480)

	# BGM 音量
	var bgm_lab := _label("BGM", 16, Color("#e8d8b8"), 2)
	bgm_lab.position = Vector2(58, 188)
	bgm_lab.size = Vector2(120, 28)
	_settings_panel.add_child(bgm_lab)

	_bgm_val = _label("60%", 14, Color("#ffd27a"), 2)
	_bgm_val.position = Vector2(326, 188)
	_bgm_val.size = Vector2(98, 28)
	_bgm_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_settings_panel.add_child(_bgm_val)

	_bgm_slider = HSlider.new()
	_bgm_slider.min_value = 0.0
	_bgm_slider.max_value = 100.0
	_bgm_slider.step = 1.0
	_bgm_slider.position = Vector2(58, 222)
	_bgm_slider.size = Vector2(366, 28)
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	_settings_panel.add_child(_bgm_slider)

	# 音效音量
	var sfx_lab := _label("SFX", 16, Color("#e8d8b8"), 2)
	sfx_lab.position = Vector2(58, 278)
	sfx_lab.size = Vector2(120, 28)
	_settings_panel.add_child(sfx_lab)

	_sfx_val = _label("100%", 14, Color("#ffd27a"), 2)
	_sfx_val.position = Vector2(326, 278)
	_sfx_val.size = Vector2(98, 28)
	_sfx_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_settings_panel.add_child(_sfx_val)

	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 100.0
	_sfx_slider.step = 1.0
	_sfx_slider.position = Vector2(58, 312)
	_sfx_slider.size = Vector2(366, 28)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_settings_panel.add_child(_sfx_slider)

	# 分隔线
	var div := ColorRect.new()
	div.color = Color(0.6, 0.4, 0.2, 0.4)
	div.position = Vector2(58, 366)
	div.size = Vector2(366, 2)
	_settings_panel.add_child(div)

	# 辉光
	var glow_lab := _label("GLOW", 16, Color("#e8d8b8"), 2)
	glow_lab.position = Vector2(58, 392)
	glow_lab.size = Vector2(180, 30)
	_settings_panel.add_child(glow_lab)

	_glow_btn = _toggle_button()
	_glow_btn.position = Vector2(304, 386)
	_glow_btn.size = Vector2(120, 42)
	_glow_btn.pressed.connect(_toggle_glow)
	_settings_panel.add_child(_glow_btn)

	# 震动
	var shake_lab := _label("SHAKE", 16, Color("#e8d8b8"), 2)
	shake_lab.position = Vector2(58, 452)
	shake_lab.size = Vector2(180, 30)
	_settings_panel.add_child(shake_lab)

	_shake_btn = _toggle_button()
	_shake_btn.position = Vector2(304, 446)
	_shake_btn.size = Vector2(120, 42)
	_shake_btn.pressed.connect(_toggle_shake)
	_settings_panel.add_child(_shake_btn)

	# 返回
	var back_btn := _button("BACK", 18)
	back_btn.position = Vector2(140, 666)
	back_btn.size = Vector2(200, 56)
	back_btn.pressed.connect(_on_close_settings)
	_settings_panel.add_child(back_btn)


# ==================== 样式 ====================
func _style(l: Label, size: int, color: Color, outline: int = 2) -> void:
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)


func _label(text: String, size: int, color: Color, outline: int = 2) -> Label:
	var l := Label.new()
	l.text = text
	_style(l, size, color, outline)
	return l


func _panel(parent: Control, bg: Color, border: Color, radius: int = 0, border_w: float = 2.0,
		shadow: bool = false) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(border_w))
	sb.set_corner_radius_all(radius)
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _button(text: String, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color("#ffd27a"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("#ffe0a0"))
	b.add_theme_color_override("font_focus_color", Color("#ffd27a"))
	var nb := StyleBoxFlat.new()
	nb.bg_color = Color("#3a1c10")
	nb.border_color = Color("#d0a050")
	nb.set_border_width_all(2)
	nb.set_corner_radius_all(0)
	nb.content_margin_left = 20
	nb.content_margin_right = 20
	nb.content_margin_top = 8
	nb.content_margin_bottom = 8
	var hb := nb.duplicate() as StyleBoxFlat
	hb.bg_color = Color("#5a2a14")
	hb.border_color = Color("#ffd27a")
	var pb := nb.duplicate() as StyleBoxFlat
	pb.bg_color = Color("#241008")
	b.add_theme_stylebox_override("normal", nb)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", pb)
	b.add_theme_stylebox_override("focus", nb)
	return b


## 移动端友好的开关按钮：显示 ON / OFF。
func _toggle_button() -> Button:
	var b := _button("ON", 16)
	b.add_theme_constant_override("icon_max_width", 0)
	return b


## 根据 on 状态刷新开关按钮的文字与配色。
func _set_toggle(b: Button, on: bool) -> void:
	b.text = "ON" if on else "OFF"
	var on_bg := Color("#1d5a20")
	var off_bg := Color("#3a1410")
	var sb := b.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	sb.bg_color = on_bg if on else off_bg
	sb.border_color = Color("#66dd66") if on else Color("#804040")
	var hb := sb.duplicate() as StyleBoxFlat
	hb.bg_color = on_bg.lightened(0.12) if on else off_bg.lightened(0.12)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)


# ==================== 状态流转 ====================
func show_menu() -> void:
	visible = true
	_menu_panel.visible = true
	_settings_panel.visible = false


func hide_menu() -> void:
	visible = false


func set_start_label(_continued: bool) -> void:
	# 像素字下始终显示 START；按继续 / 新开局文本相同
	_start_btn.text = "START"


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_open_settings() -> void:
	_menu_panel.visible = false
	_settings_panel.visible = true


func _on_close_settings() -> void:
	_menu_panel.visible = true
	_settings_panel.visible = false


## 供主控查询 / 关闭设置面板（Android 返回键用）。
func settings_visible() -> bool:
	return _settings_panel.visible


func close_settings() -> void:
	if _settings_panel.visible:
		_on_close_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if (k.keycode == KEY_ESCAPE or k.keycode == KEY_BACK) and _settings_panel.visible:
			_on_close_settings()
			get_viewport().set_input_as_handled()


# ==================== 设置读写 ====================
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		bgm_volume = float(cfg.get_value("audio", "bgm_volume", 0.6))
		sfx_volume = float(cfg.get_value("audio", "sfx_volume", 1.0))
		glow_enabled = bool(cfg.get_value("video", "glow", true))
		screen_shake = bool(cfg.get_value("video", "shake", true))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("video", "glow", glow_enabled)
	cfg.set_value("video", "shake", screen_shake)
	cfg.save(SETTINGS_PATH)


func _apply_audio() -> void:
	Sfx.set_bgm_volume(bgm_volume)
	Sfx.set_sfx_volume(sfx_volume)


func _sync_widgets() -> void:
	_bgm_slider.set_value_no_signal(bgm_volume * 100.0)
	_sfx_slider.set_value_no_signal(sfx_volume * 100.0)
	_set_toggle(_glow_btn, glow_enabled)
	_set_toggle(_shake_btn, screen_shake)
	_bgm_val.text = "%d%%" % int(bgm_volume * 100.0)
	_sfx_val.text = "%d%%" % int(sfx_volume * 100.0)


func _on_bgm_changed(v: float) -> void:
	bgm_volume = v / 100.0
	_bgm_val.text = "%d%%" % int(v)
	_on_changed()


func _on_sfx_changed(v: float) -> void:
	sfx_volume = v / 100.0
	_sfx_val.text = "%d%%" % int(v)
	_on_changed()


func _toggle_glow() -> void:
	glow_enabled = not glow_enabled
	_set_toggle(_glow_btn, glow_enabled)
	_on_changed()


func _toggle_shake() -> void:
	screen_shake = not screen_shake
	_set_toggle(_shake_btn, screen_shake)
	_on_changed()


func _on_changed() -> void:
	_save_settings()
	_apply_audio()
	if main != null:
		main.apply_settings(bgm_volume, sfx_volume, glow_enabled, screen_shake)