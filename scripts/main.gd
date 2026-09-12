class_name Main
extends Node3D
## 主控：砖块消除关卡制 + 球物理 + 连锁 + 输入 + HUD。
## 玩法：球从顶部向下发射，弹跳消除下方砖块；收回后砖块整体上移，
## 越过顶部斩杀线则震动扣血；全消除或达标 → 清屏特效进入下一关。

const W := 1280.0
const H := 720.0
# 横版三栏拼接：左栏蓄力 / 中栏打击区(占屏宽 3/5) / 右栏连击，三块独立面板。
# 打击区几何保持竖版一致比例，矿石视觉大小不变（仅随整屏等比缩放）。
# 中栏打击区占屏宽 3/5：在 1280x720 下中栏约 258~1022px。
# 相机 z=692、fov=55 时 1 世界单位 ≈ 1 屏幕像素，所以中栏边缘对应世界 x≈±382。
const FIELD_LEFT := -382.0
const FIELD_RIGHT := 382.0
# 中栏高度 642px，相机 1px≈1unit，让 3D 内容撑满中栏、不留上下黑边
const FIELD_TOP := 321.0
const FIELD_BOTTOM := -321.0
const BOUNDS := Rect2(FIELD_LEFT, FIELD_BOTTOM, FIELD_RIGHT - FIELD_LEFT, FIELD_TOP - FIELD_BOTTOM)
const BALL_START := Vector2(0.0, 250.0)

# 底部 V 形漏斗：两侧斜坡从左右墙向内下方倾斜，汇聚到中央唯一的漏斗口（弹板）。
# 矿石粒子沿斜坡滚落进中央料池（真实物理堆积），池满即能量满；
# 小球永远不会掉进漏斗：口部是一块"弹板"，撞上去会被大力弹回场上。
const FUNNEL_MOUTH_Y := -250.0   # 漏斗口（弹板）所在高度
const FUNNEL_HALF := 70.0        # 漏斗口半宽
const SLOPE_OUTER_Y := -140.0    # 斜坡外侧起点高度（更靠下 → 漏斗更缓）
# 弹板：小球撞上后保证的最小上抛速度 / 弹性（>1 表示越弹越高）
const FUNNEL_KICK := 1020.0
const FUNNEL_BOUNCE_REST := 1.08
# 粒子/小球与斜坡的弹性与摩擦
const SLOPE_RESTITUTION := 0.52
const SLOPE_FRICTION := 0.14
const GEM_RESTITUTION := 0.42
const GEM_FRICTION := 0.10

# 能量满阈值：矿石粒子池填满即视为能量满（比例 1.0）。
const ENERGY_FULL := 1.0

# 矿石粒子池（真实物理堆积）：底部料池，粒子落底后按列堆叠成"池"。
const POOL_FLOOR_Y := -285.0     # 料池底面高度
const POOL_LEFT := -340.0        # 料池左缘（随打击区拉宽）
const POOL_RIGHT := 340.0        # 料池右缘
const POOL_COLS := 24            # 堆叠列数
const POOL_COL_W := (POOL_RIGHT - POOL_LEFT) / float(POOL_COLS)
const POOL_SPACING := 12.0       # 每列每颗往上堆的高度
const POOL_CAPACITY := 48        # 堆满这么多颗即能量满

# 双击回收演出：先闪烁停顿，再动态飞回起始点
const RETRACT_FLASH_TIME := 0.30
const RETRACT_FLY_TIME := 0.62
# 换关清场：斩杀线下扫速度
const SWEEP_SPEED := 1150.0
# 斜坡弹跳计数的冷却（防止滚动时每帧计数）
var slope_bounce_cd: float = 0.0
# 漏斗弹板命中冷却 + 弹板压扁回弹动画进度
var funnel_bounce_cd: float = 0.0
var bouncer_punch: float = 0.0
# 延迟连锁破碎队列：[矿石, 连锁层级, 剩余延迟]
var pending_breaks: Array = []

# 斩杀线（砖块上移越过此线即扣血，位于球起始位置下方）
const KILL_LINE_Y := 250.0
# 砖块 grid 布局（居中铺开，横版下更宽更疏）
const GRID_TOP_Y := 90.0
const GRID_BOTTOM_Y := -200.0
const ROW_STEP := 56.0
const COL_STEP := 52.0
const COLS := 9
# 每次收球后砖块上移量
const ADVANCE := 44.0
# 矿石与斜坡表面的最小间隙（防止矿石埋进斜坡）
const ORE_CLEARANCE := 34.0

enum State { IDLE, FLYING, WARNING, RETURNING, EXPLODED, CLEAR, GAMEOVER, RETRACT, SWEEP, SLOT }
# 双击回收演出的两个阶段
enum RetractPhase { FLASH, FLY }
# 球种：NORMAL 常规弹球；SAFE 自动回收、不爆炸的安全球；BIG 超大球（更大半径/爆炸范围）。
enum BallKind { NORMAL, SAFE, BIG }
# 老虎机奖励：能量池满时自动抽奖，应用一次性或持续效果。
enum Reward { EXTRA_HEART, LAST_STAND, SAFE_BALL, BIG_BALL }
const REWARD_NAMES: Dictionary = {
	Reward.EXTRA_HEART: "MAX HEART",
	Reward.LAST_STAND: "LAST STAND",
	Reward.SAFE_BALL: "SAFE BALL",
	Reward.BIG_BALL: "BIG BALL",
}
const REWARD_COLORS: Dictionary = {
	Reward.EXTRA_HEART: Color("#ff3a3a"),
	Reward.LAST_STAND: Color("#ffd27a"),
	Reward.SAFE_BALL: Color("#3ac060"),
	Reward.BIG_BALL: Color("#ff6622"),
}

var state: int = State.IDLE
var hearts: int = 3
var max_hearts: int = 3
var level: int = 1
var total_score: int = 0
var level_score: int = 0
var target_score: int = 0
var energy: float = 0.0
var pool_counts: PackedInt32Array = []
var pool_count: int = 0
var _pool_full_announced: bool = false
var current_ball_kind: int = BallKind.NORMAL
var combo: int = 0
var current_multiplier: float = 1.0
var bounce_count: int = 0
var max_bounces: int = 15
var return_timer: float = 0.0
var shake_amount: float = 0.0
var heartbeat_timer: float = 0.0
var kill_line_time: float = 0.0

var aim: Vector2 = Vector2(0, 0)
var drag_world: Vector2 = Vector2.ZERO  # 蓄力时当前鼠标位置（未钳制），用于计算方向
var charging: bool = false
var press_world: Vector2 = Vector2.ZERO
var last_aim_dir: Vector2 = Vector2(0.0, -1.0)  # 最近一次有效拖拽方向，防止短拖拽时方向乱跳/强制向上
var power: float = 0.0
var last_tap_time: int = 0

var detonate_timer: float = 0.0
var danger_timer: float = 0.0
var trail_timer: float = 0.0

# 双击回收演出
var retract_phase: int = RetractPhase.FLASH
var retract_timer: float = 0.0
var retract_from: Vector2 = Vector2.ZERO
# 双击回收：光标贴合小球一起归位
var recall_snapping: bool = false
# 换关清场（斩杀线下扫）
var sweep_y: float = 0.0
# 蓄力音效计时器
var charge_sound_timer: float = 0.0
# 老虎机演出
var _slot_timer: float = 0.0
var _slot_index: int = 0
var _slot_reward: int = -1
var _slot_power: float = 0.0
# 奖励状态
var last_stand_charges: int = 0
var next_ball_kind: int = BallKind.NORMAL

var ball: Ball
var ores: Array[Ore] = []
var gems: Array[Gem] = []
var aim_line: AimLine
var crosshair: Crosshair

# 底部斜坡线段（世界 2D 坐标）
var slope_l_a := Vector2(FIELD_LEFT, SLOPE_OUTER_Y)
var slope_l_b := Vector2(-FUNNEL_HALF, FUNNEL_MOUTH_Y)
var slope_r_a := Vector2(FIELD_RIGHT, SLOPE_OUTER_Y)
var slope_r_b := Vector2(FUNNEL_HALF, FUNNEL_MOUTH_Y)

# 菜单 / 设置状态
var in_menu := true
var game_started := false
var screen_shake := true
var glow_enabled := true

@onready var camera: Camera3D = $Camera3D
@onready var ores_container: Node3D = $Ores
@onready var gems_container: Node3D = $Gems
@onready var fx: FX = $FX
@onready var hud: HUD = $HUD
@onready var celebrate: Celebrate = $Celebrate
@onready var menu: Menu = $Menu

var _kill_line_node: MeshInstance3D
var _kill_line_mat: StandardMaterial3D
var _kill_line_glow: MeshInstance3D
var _kill_line_glow_mat: StandardMaterial3D
var _funnel_mouth_mat: StandardMaterial3D
var _funnel_pad: MeshInstance3D
var _funnel_pad_mat: StandardMaterial3D
var _pool_floor_mat: StandardMaterial3D
var _env: Environment
var _funnel: Node3D
# 暗黑老虎机氛围：暗角层 / 熔池炉光 / 背板暖光材质
var _vignette: CanvasLayer
var _pixelate: CanvasLayer
var slot_machine: SlotMachine
var _furnace_light: OmniLight3D
var _furnace_base_energy: float = 1.1
var _backdrop_glow_mat: StandardMaterial3D
# 指针（鼠标/触摸）是否出现过：决定准星是否显示
var pointer_active: bool = false
# 强制显示瞄准虚线（用于截图/演示，不影响正常输入）
var aim_forced: bool = false
var _cursor_hidden: bool = false


func _ready() -> void:
	_build_world()
	_build_kill_line()
	_build_funnel()
	_build_ball()
	_build_aim_marker()
	_build_crosshair()
	# 全屏暖色暗角：参考暗黑老虎机质感（layer 0，位于 HUD 之下）
	_vignette = preload("res://scripts/vignette.gd").new()
	add_child(_vignette)
	# 全屏低像素化：粗颗粒像素质感（layer 10，盖在 HUD 之上）
	_pixelate = preload("res://scripts/pixelate.gd").new()
	add_child(_pixelate)
	# 底部实体老虎机：折叠待机，池满全屏弹出
	slot_machine = SlotMachine.new()
	add_child(slot_machine)
	slot_machine.build(REWARD_NAMES, REWARD_COLORS)
	hud.restart_pressed.connect(_restart)
	hud.menu_requested.connect(_to_menu_fresh)
	hud.pause_requested.connect(_pause_to_menu)
	menu.configure(self)
	menu.start_requested.connect(_on_start_game)
	# 桌面端默认就有指针，准星直接可见；移动端等首次触摸后再显示
	pointer_active = OS.has_feature("pc") or OS.has_feature("web")
	_apply_settings_from_menu()
	hud.set_hearts(hearts, max_hearts)
	# 开局先停在主菜单，等待“开始”
	hud.visible = false
	menu.set_start_label(false)
	menu.show_menu()


## Android 物理返回键 / 桌面关闭请求处理。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()


## 返回键统一逻辑：设置面板 → 关面板；游戏内 → 暂停回菜单；主菜单 → 退出。
func _handle_back() -> void:
	if in_menu:
		if menu.settings_visible():
			menu.close_settings()
		else:
			get_tree().quit()
	elif state == State.GAMEOVER:
		_to_menu_fresh()
	else:
		_pause_to_menu()


# ==================== 世界 ====================
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#360b07")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#2a0d0d")
	env.ambient_light_energy = 0.74
	# 雾：极淡酒红烟雾，压低远景但不糊住矿石
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#260909")
	env.fog_density = 0.002
	env.fog_sky_affect = 0.0
	# 辉光（bloom）：让自发光材质产生光晕，但不过曝
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_strength = 0.95
	env.glow_hdr_threshold = 0.90
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffd9a0")
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)

	# 补光：暗红弱光，统一色调
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#5a3030")
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-30.0, 140.0, 0.0)
	add_child(fill)

	# 熔池炉光：底部暗红色点光源，随池满增强
	_furnace_light = OmniLight3D.new()
	_furnace_light.light_color = Color("#ff4a2a")
	_furnace_light.light_energy = _furnace_base_energy
	_furnace_light.omni_range = 420.0
	_furnace_light.omni_attenuation = 0.9
	_furnace_light.position = Vector3(0.0, POOL_FLOOR_Y + 60.0, 60.0)
	_furnace_light.shadow_enabled = false
	add_child(_furnace_light)

	# 背景岩壁：压到接近纯黑，只保留一点点体积感
	_make_box(Vector3(0, 0, -220.0), Vector3(W + 400.0, H + 400.0, 8.0), Color("#0a0202"))
	var wall_thick := 12.0
	var field_w := FIELD_RIGHT - FIELD_LEFT
	# 顶墙：只覆盖中栏宽度
	_make_boundary(Vector3(0.0, FIELD_TOP + wall_thick * 0.5, 0.0),
		Vector3(field_w + wall_thick, wall_thick, 36))
	# 左右墙：贴中栏两侧
	_make_boundary(Vector3(FIELD_LEFT - wall_thick * 0.5, 0.0, 0.0),
		Vector3(wall_thick, H + 90, 36))
	_make_boundary(Vector3(FIELD_RIGHT + wall_thick * 0.5, 0.0, 0.0),
		Vector3(wall_thick, H + 90, 36))

	_build_backdrop_glow()
	_build_arena_grid()
	_build_arena_rig()
	_build_blood_basin()
	_build_blood_backdrop()

	# 背景装饰岩块：极暗，几乎只留剪影
	for i in 10:
		var p := Vector3(randf_range(BOUNDS.position.x, BOUNDS.position.x + BOUNDS.size.x),
			randf_range(BOUNDS.position.y, BOUNDS.position.y + BOUNDS.size.y), randf_range(-24.0, -12.0))
		var rock := MeshInstance3D.new()
		rock.mesh = MeshFactory.prism(randi_range(4, 7), randf_range(14.0, 30.0), randf_range(8.0, 16.0))
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color("#140404")
		rm.roughness = 0.95
		if i % 5 == 0:
			rm.emission_enabled = true
		rm.emission = Color("#6a1a0e")
		rm.emission_energy_multiplier = 0.6
		rock.material_override = rm
		rock.position = p
		rock.rotation_degrees.z = randf_range(0.0, 360.0)
		add_child(rock)


## 场地背板微光：暗红色径向辉光，模拟机器内部透出的火光。
func _build_backdrop_glow() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.16, 0.10, 0.6))
	grad.set_color(1, Color(0.35, 0.04, 0.03, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.55)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	_backdrop_glow_mat = StandardMaterial3D.new()
	_backdrop_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_backdrop_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_backdrop_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_backdrop_glow_mat.albedo_texture = tex
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(FIELD_RIGHT - FIELD_LEFT + 60.0, 560.0)
	quad.mesh = qm
	quad.material_override = _backdrop_glow_mat
	quad.position = Vector3(0.0, -20.0, -26.0)
	add_child(quad)


## 参考图 ARENA 内的 faint grid：暗红色细线，帮助对齐矿石阵列。
func _build_arena_grid() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#3a1818")
	mat.emission_enabled = true
	mat.emission = Color("#a8382a")
	mat.emission_energy_multiplier = 2.3

	var cols := 18
	var rows := 14
	var x0 := FIELD_LEFT + 24.0
	var x1 := FIELD_RIGHT - 24.0
	var y0 := FIELD_TOP - 24.0
	var y1 := FIELD_BOTTOM + 80.0
	for i in cols + 1:
		var t := float(i) / float(cols)
		var x := lerpf(x0, x1, t)
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(2.5, y0 - y1, 2.0)
		m.mesh = b
		m.material_override = mat
		m.position = Vector3(x, (y0 + y1) * 0.5, -24.0)
		add_child(m)
	for i in rows + 1:
		var t := float(i) / float(rows)
		var y := lerpf(y0, y1, t)
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(x1 - x0, 2.5, 2.0)
		m.mesh = b
		m.material_override = mat
		m.position = Vector3((x0 + x1) * 0.5, y, -24.0)
		add_child(m)


## 用 SurfaceTool 生成真正的圆环（annulus）网格：XY 平面，中心在原点。
## 规避 TorusMesh 在本版本几何生成异常的问题。
func _make_ring_mesh(radius: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 72
	for i in seg:
		var a0 := float(i) / float(seg) * TAU
		var a1 := float(i + 1) / float(seg) * TAU
		var ri := radius - thickness * 0.5
		var ro := radius + thickness * 0.5
		var p_i0 := Vector3(cos(a0) * ri, sin(a0) * ri, 0.0)
		var p_o0 := Vector3(cos(a0) * ro, sin(a0) * ro, 0.0)
		var p_i1 := Vector3(cos(a1) * ri, sin(a1) * ri, 0.0)
		var p_o1 := Vector3(cos(a1) * ro, sin(a1) * ro, 0.0)
		st.add_vertex(p_i0); st.add_vertex(p_o0); st.add_vertex(p_o1)
		st.add_vertex(p_i0); st.add_vertex(p_o1); st.add_vertex(p_i1)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## ARENA 中央轮盘机构：密集同心环 + 辐射辐条，呼应"矿坑轮盘"主题，填补中央空洞。
## 属于场地结构（非矿石密度、非红调、非边框装饰），呼应参考图中央密集结构。
func _build_arena_rig() -> void:
	var cx := (FIELD_LEFT + FIELD_RIGHT) * 0.5
	var cy := (FIELD_TOP + FIELD_BOTTOM) * 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#3a0e0e")
	mat.emission_enabled = true
	mat.emission = Color("#cc2a22")
	mat.emission_energy_multiplier = 0.5

	# 同心环（9 环，由内到外渐密，环管加粗以保证可见）
	var ring_radii := [18.0, 44.0, 76.0, 110.0, 146.0, 184.0, 224.0, 266.0, 310.0]
	for r in ring_radii:
		var m := MeshInstance3D.new()
		m.mesh = _make_ring_mesh(r, 8.0)
		m.material_override = mat
		m.position = Vector3(cx, cy, -20.0)
		add_child(m)

	# 辐射辐条（16 根，每 22.5°，加粗）
	for i in 16:
		var a := float(i) * 22.5
		var spoke := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(320.0, 6.0, 2.0)
		spoke.mesh = b
		spoke.material_override = mat
		spoke.position = Vector3(cx, cy, -20.0)
		spoke.rotation_degrees = Vector3(0.0, 0.0, a)
		add_child(spoke)

	# 中央轮毂：实心圆盘 + 外环，强调轮盘轴心
	var hub := MeshInstance3D.new()
	hub.mesh = _make_ring_mesh(22.0, 44.0)
	hub.material_override = mat
	hub.position = Vector3(cx, cy, -20.0)
	add_child(hub)




## 血色背景层：底部暗红渐变 + 轮盘核心血色圆盘。
## 仅叠加在场地结构之后，呼应参考图下半区密集血色；不影响矿石(gem)/小球(ball)。
func _build_blood_basin() -> void:
	# 底部血池渐变：屏幕底部亮血色，向上淡出（叠在轮盘与地面之后、在 rig 之前）
	var basin_mat := StandardMaterial3D.new()
	basin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	basin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	basin_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var bg := Gradient.new()
	bg.set_color(0, Color(0.85, 0.14, 0.06, 0.97))
	bg.set_color(0.35, Color(0.60, 0.10, 0.05, 0.92))
	bg.set_color(1.0, Color(0.30, 0.05, 0.025, 0.75))
	var btex := GradientTexture2D.new()
	btex.gradient = bg
	btex.fill = GradientTexture2D.FILL_LINEAR
	btex.fill_from = Vector2(0.5, 1.0)
	btex.fill_to = Vector2(0.5, 0.0)
	btex.width = 64
	btex.height = 256
	basin_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	basin_mat.albedo_texture = btex
	var bq := MeshInstance3D.new()
	var bqm := QuadMesh.new()
	bqm.size = Vector2(FIELD_RIGHT - FIELD_LEFT + 40.0, 360.0)
	bq.mesh = bqm
	bq.material_override = basin_mat
	bq.position = Vector3(0.0, FIELD_BOTTOM + 150.0, -26.0)
	add_child(bq)

	# 下半区暗红背板：填补轮盘/漏斗之间的暗隙，统一下半区血色基调（不触碰矿石/小球）
	var back_mat := StandardMaterial3D.new()
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var backg := Gradient.new()
	backg.set_color(0, Color(0.82, 0.14, 0.06, 0.98))
	backg.set_color(0.6, Color(0.55, 0.09, 0.045, 0.92))
	backg.set_color(1.0, Color(0.25, 0.04, 0.02, 0.70))
	var btex2 := GradientTexture2D.new()
	btex2.gradient = backg
	btex2.fill = GradientTexture2D.FILL_LINEAR
	btex2.fill_from = Vector2(0.5, 1.0)
	btex2.fill_to = Vector2(0.5, 0.0)
	btex2.width = 64
	btex2.height = 256
	back_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	back_mat.albedo_texture = btex2
	var backq := MeshInstance3D.new()
	var backm := QuadMesh.new()
	backm.size = Vector2(FIELD_RIGHT - FIELD_LEFT + 80.0, 420.0)
	backq.mesh = backm
	backq.material_override = back_mat
	backq.position = Vector3(0.0, FIELD_BOTTOM + 180.0, -28.0)
	add_child(backq)

	# 轮盘核心血色圆盘：径向渐变，填充中央空洞（位于 rig 环之后）
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var cg := Gradient.new()
	cg.set_color(0, Color(0.85, 0.13, 0.06, 0.12))
	cg.set_color(1, Color(0.15, 0.03, 0.02, 0.0))
	var ctex := GradientTexture2D.new()
	ctex.gradient = cg
	ctex.fill = GradientTexture2D.FILL_RADIAL
	ctex.fill_from = Vector2(0.5, 0.5)
	ctex.fill_to = Vector2(0.5, 0.0)
	ctex.width = 256
	ctex.height = 256
	core_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	core_mat.albedo_texture = ctex
	var cq := MeshInstance3D.new()
	var cqm := QuadMesh.new()
	cqm.size = Vector2(220.0, 220.0)
	cq.mesh = cqm
	cq.material_override = core_mat
	cq.position = Vector3(0.0, 0.0, -22.0)
	add_child(cq)

## 全屏血色背板：在所有场地结构之后铺一层近乎不透明的暗红渐变，
## 把左/右/底部整体拉进"血色"基调（参考图下半区与两侧大片血红）。
## 仅环境层，绝不触碰宝石(gem)/小球(ball)。
func _build_blood_backdrop() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.10, 0.05, 0.92))
	grad.set_color(0.45, Color(0.40, 0.07, 0.035, 0.85))
	grad.set_color(1.0, Color(0.30, 0.05, 0.025, 0.80))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 1.0)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 512
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.albedo_texture = tex
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(W + 40.0, 820.0)
	quad.mesh = qm
	quad.material_override = mat
	quad.position = Vector3(0.0, -40.0, -29.0)
	add_child(quad)

## 熔池炉光闪烁：烛光式随机抖动，池越满光越旺；背板暖光随之轻微呼吸。
func _update_furnace(delta: float) -> void:
	if _furnace_light == null:
		return
	var r := clampf(energy / ENERGY_FULL, 0.0, 1.0)
	var flicker := 1.0 + 0.10 * sin(Time.get_ticks_msec() * 0.013) \
		+ 0.06 * sin(Time.get_ticks_msec() * 0.037) + randf_range(-0.03, 0.03)
	_furnace_light.light_energy = _furnace_base_energy * flicker * (0.55 + 0.85 * r)
	# 背板暖光随炉光呼吸（albedo_color 与纹理 RGBA 相乘，调 alpha 即调亮度）
	if _backdrop_glow_mat != null:
		_backdrop_glow_mat.albedo_color = Color(1.0, 1.0, 1.0, clampf(0.55 + 0.45 * r, 0.0, 1.0))


func _make_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	m.material_override = mat
	m.position = pos
	add_child(m)


## 边界墙：厚重暗青铜机框（unshaded 保持可见），内缘已由 _build_ornate_trim 的金线勾边。
func _make_boundary(pos: Vector3, size: Vector3) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#2a180a")
	mat.emission_enabled = true
	mat.emission = Color("#4a2c10")
	mat.emission_energy_multiplier = 0.5
	m.material_override = mat
	m.position = pos
	add_child(m)


## 斩杀线：细亮核心 + 宽辉光带（两层叠加，bloom 下形成光晕），
## 亮度与闪烁频率由"最近砖块的逼近程度"驱动（见 _update_kill_line）。
func _build_kill_line() -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(FIELD_RIGHT - FIELD_LEFT + 20.0, 3.0, 4.0)
	m.mesh = box
	_kill_line_mat = StandardMaterial3D.new()
	_kill_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_kill_line_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.12)
	_kill_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_kill_line_mat.emission_enabled = true
	_kill_line_mat.emission = Color("#ff2200")
	_kill_line_mat.emission_energy_multiplier = 0.40
	m.material_override = _kill_line_mat
	m.position = Vector3(0, KILL_LINE_Y, 1.0)
	add_child(m)
	_kill_line_node = m

	# 辉光带：更宽、更透明，负责"光晕 + 呼吸"
	var g := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(FIELD_RIGHT - FIELD_LEFT + 20.0, 22.0, 2.0)
	g.mesh = gbox
	_kill_line_glow_mat = StandardMaterial3D.new()
	_kill_line_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_kill_line_glow_mat.albedo_color = Color(1.0, 0.12, 0.05, 0.03)
	_kill_line_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_kill_line_glow_mat.emission_enabled = true
	_kill_line_glow_mat.emission = Color("#ff1a00")
	_kill_line_glow_mat.emission_energy_multiplier = 0.20
	g.material_override = _kill_line_glow_mat
	g.position = Vector3(0, KILL_LINE_Y, 0.5)
	add_child(g)
	_kill_line_glow = g


## 底部漏斗：两侧倾斜斜坡 + 中央唯一漏斗口（无平底、无独立圆柱漏斗）。
## 斜坡同时参与物理：小球反弹、矿石粒子滚落。
func _build_funnel() -> void:
	_funnel = Node3D.new()
	add_child(_funnel)

	# 两侧斜坡
	_make_slope(slope_l_a, slope_l_b)
	_make_slope(slope_r_a, slope_r_b)

	# 漏斗口发光带：粒子被吸收时脉冲
	var mouth := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(FUNNEL_HALF * 2.0 + 4.0, 64.0, 44.0)
	mouth.mesh = mb
	_funnel_mouth_mat = StandardMaterial3D.new()
	_funnel_mouth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_funnel_mouth_mat.albedo_color = Color(0.6, 0.08, 0.04, 1.0)
	_funnel_mouth_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_funnel_mouth_mat.emission_enabled = true
	_funnel_mouth_mat.emission = Color("#aa2410")
	_funnel_mouth_mat.emission_energy_multiplier = 1.0
	mouth.material_override = _funnel_mouth_mat
	mouth.position = Vector3(0.0, FUNNEL_MOUTH_Y - 4.0, 0.0)
	_funnel.add_child(mouth)

	# 弹板：封住漏斗口，小球撞上被大力弹回（顶面正好在 FUNNEL_MOUTH_Y）
	var pad := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(FUNNEL_HALF * 2.0 + 12.0, 10.0, 46.0)
	pad.mesh = pbox
	_funnel_pad_mat = StandardMaterial3D.new()
	_funnel_pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_funnel_pad_mat.albedo_color = Color("#3a0805")
	_funnel_pad_mat.emission_enabled = true
	_funnel_pad_mat.emission = Color("#aa2410")
	_funnel_pad_mat.emission_energy_multiplier = 0.35
	pad.material_override = _funnel_pad_mat
	pad.position = Vector3(0.0, FUNNEL_MOUTH_Y - 5.0, 0.0)
	_funnel.add_child(pad)
	_funnel_pad = pad

	# 弹板两侧的细支柱
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(6.0, 22.0, 40.0)
		post.mesh = pb
		post.material_override = _slope_mat(Color("#2a0805"), Color("#7a1a0e"), 0.6)
		post.position = Vector3(side * (FUNNEL_HALF + 10.0), FUNNEL_MOUTH_Y - 24.0, 0.0)
		_funnel.add_child(post)

	# 底部料池：发光底面 + 两侧矮栏
	var floor_w := POOL_RIGHT - POOL_LEFT
	var pf := MeshInstance3D.new()
	var pfb := BoxMesh.new()
	pfb.size = Vector3(floor_w, 70.0, 46.0)
	pf.mesh = pfb
	_pool_floor_mat = StandardMaterial3D.new()
	_pool_floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_floor_mat.albedo_color = Color("#180403")
	_pool_floor_mat.emission_enabled = true
	_pool_floor_mat.emission = Color(1.4, 0.25, 0.12)
	_pool_floor_mat.emission_energy_multiplier = 0.45
	pf.material_override = _pool_floor_mat
	pf.position = Vector3((POOL_LEFT + POOL_RIGHT) * 0.5, POOL_FLOOR_Y - 34.0, 0.0)
	_funnel.add_child(pf)

	# 料池两侧矮栏
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(8.0, 48.0, 46.0)
		rail.mesh = rb
		rail.material_override = _slope_mat(Color("#3a0a05"), Color("#8a1a0c"), 0.9)
		rail.position = Vector3(side * (POOL_LEFT - 4.0), POOL_FLOOR_Y + 20.0, 0.0)
		_funnel.add_child(rail)


func _slope_mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	return mat


## 用一条线段生成倾斜的墙体（视觉与碰撞使用同一组端点，保证一致）。
## 墙体沿法线下沉半个厚度，使"可见表面"正好落在碰撞线段上。
func _make_slope(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var mid := (a + b) * 0.5
	var dirv := d.normalized()
	# 法线：取垂直于斜面且朝上的那一侧
	var nrm := Vector2(-dirv.y, dirv.x)
	if nrm.y < 0.0:
		nrm = -nrm

	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(d.length(), 12.0, 44.0)
	m.mesh = box
	m.material_override = _slope_mat(Color("#2a0604"), Color("#6a1408"), 0.55)
	m.position = Vector3(mid.x - nrm.x * 6.0, mid.y - nrm.y * 6.0, 0.0)
	m.rotation.z = d.angle()
	_funnel.add_child(m)

	# 斜坡上沿的细高光描边
	var edge := MeshInstance3D.new()
	var ebox := BoxMesh.new()
	ebox.size = Vector3(d.length(), 2.0, 46.0)
	edge.mesh = ebox
	edge.material_override = _slope_mat(Color("#4a0c06"), Color("#aa2a14"), 0.8)
	edge.position = Vector3(mid.x + nrm.x * 2.0, mid.y + nrm.y * 2.0, 0.0)
	edge.rotation.z = d.angle()
	_funnel.add_child(edge)


func _build_ball() -> void:
	ball = Ball.new()
	ball.setup(16.0)
	ball.pos = BALL_START
	ball.max_bounces = 15
	ball.sync_transform()
	add_child(ball)
	_apply_ball_color()


func _build_aim_marker() -> void:
	aim_line = AimLine.new()
	add_child(aim_line)


func _build_crosshair() -> void:
	crosshair = Crosshair.new()
	add_child(crosshair)
	crosshair.set_reticle_visible(false)


## 游戏中隐藏系统光标，改用 FPS 瞄准镜准星；回菜单时恢复。
func _set_cursor_hidden(hidden: bool) -> void:
	if hidden:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# ==================== 输入 ====================
## 鼠标 / 触摸：用 _input 处理，确保不会被装饰性 UI 面板吞掉。
func _input(event: InputEvent) -> void:
	if in_menu:
		return
	if state == State.GAMEOVER or state == State.CLEAR or state == State.SWEEP or state == State.RETRACT or state == State.SLOT:
		return

	# 如果指针悬停在可交互按钮上，把点击留给 GUI，只保留准星跟随
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered is Button:
		if event is InputEventMouseMotion:
			pointer_active = true
		return

	if event is InputEventMouseMotion:
		pointer_active = true
		if state == State.IDLE:
			var w := _screen_to_world(event.position)
			drag_world = w
			_update_aim(w)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_at(mb.position)
			else:
				_release()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if state == State.IDLE and charging:
				_cancel_charge()
			else:
				_return_ball()
	elif event is InputEventScreenTouch:
		pointer_active = true
		var st := event as InputEventScreenTouch
		if st.pressed:
			_press_at(st.position)
		else:
			_release()
	elif event is InputEventScreenDrag and state == State.IDLE:
		var sd := event as InputEventScreenDrag
		var w := _screen_to_world(sd.position)
		drag_world = w
		_update_aim(w)


func _unhandled_input(event: InputEvent) -> void:
	if in_menu:
		return
	if state == State.GAMEOVER or state == State.CLEAR or state == State.SWEEP:
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if state == State.FLYING:
				_return_ball()
			elif state == State.IDLE and game_started:
				_pause_to_menu()
		elif k.keycode == KEY_SPACE:
			if state == State.FLYING:
				_return_ball()
			elif state == State.IDLE:
				_launch(0.5)


func _press_at(screen_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if state == State.FLYING or state == State.WARNING:
		# 飞行/濒死中必须双击到球上才收回（屏幕距离 ≤ 60px 视为"点到球"）。
		# 点到球外的位置不打断双击计时，让玩家能在球移动时从容瞄准。
		var ball_screen := _world_to_screen(ball.pos)
		var on_ball := screen_pos.distance_to(ball_screen) <= 60.0
		if on_ball and last_tap_time > 0 and now - last_tap_time < 320:
			_begin_retract()
			# 双击收回：屏幕微微震动作为触觉反馈
			if screen_shake:
				shake_amount = maxf(shake_amount, 7.0)
			last_tap_time = 0  # 收回成功后重置，避免三连击误触发
		elif on_ball:
			last_tap_time = now
			crosshair.hit_mark()
		return
	if state != State.IDLE:
		return
	charging = true
	press_world = _screen_to_world(screen_pos)
	drag_world = press_world
	power = 0.0
	charge_sound_timer = 0.0
	last_tap_time = now
	Sfx.charge()


func _release() -> void:
	if charging and state == State.IDLE:
		charging = false
		charge_sound_timer = 0.0
		ball.scale = Vector3.ONE
		ball.set_state(Color("#3080c8"), Color("#104070"), 0.8)
		if power > 0.12:
			_launch(power)
		power = 0.0
		hud.set_power(0.0, false)


## 蓄力中按右键：取消本次蓄力，不发射，球回到待机状态。
func _cancel_charge() -> void:
	charging = false
	charge_sound_timer = 0.0
	power = 0.0
	ball.scale = Vector3.ONE
	ball.set_state(Color("#3080c8"), Color("#104070"), 0.8)
	hud.set_power(0.0, false)


func _update_aim(w: Vector2) -> void:
	aim = Vector2(
		clampf(w.x, BOUNDS.position.x + ball.radius, BOUNDS.position.x + BOUNDS.size.x - ball.radius),
		clampf(w.y, BOUNDS.position.y + ball.radius, BOUNDS.position.y + BOUNDS.size.y - ball.radius))
	if charging:
		power = clampf(press_world.distance_to(aim) / 200.0, 0.0, 1.0)
		hud.set_power(power, true)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.z) < 0.0001:
		return Vector2.ZERO
	var t := -from.z / dir.z
	var p := from + dir * t
	return Vector2(p.x, p.y)


# ==================== 主循环 ====================
func _process(delta: float) -> void:
	delta = clampf(delta, 0.0, 0.05)
	slope_bounce_cd = maxf(0.0, slope_bounce_cd - delta)
	funnel_bounce_cd = maxf(0.0, funnel_bounce_cd - delta)
	_update_funnel_pad(delta)
	_update_kill_line(delta)
	_update_camera(delta)
	_update_furnace(delta)
	if in_menu:
		return
	if state == State.FLYING or state == State.RETURNING:
		_update_ball(delta)
	elif state == State.WARNING:
		_update_warning(delta)
	elif state == State.RETRACT:
		_update_retract(delta)
	elif state == State.SWEEP:
		_update_sweep(delta)
	elif state == State.SLOT:
		_update_slot(delta)
	_update_pending(delta)
	_update_gems(delta)
	_update_pool()
	_update_aim_marker()
	_update_heartbeat(delta)
	_update_danger(delta)
	_update_crosshair()
	_update_hud()
	# 蓄力动效 + 连续蓄力音效：球随 power 脉动 + 发红 + 变亮，音效节奏随 power 加快
	if state == State.IDLE and charging:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.02) * 0.08 * (0.3 + power * 0.7)
		ball.scale = Vector3.ONE * pulse
		var base := Color("#3080c8").lerp(Color("#ff4422"), power)
		ball.set_state(base, Color("#60c0ff"), 0.8 + power * 1.8)
		ball.sync_transform()
		charge_sound_timer -= delta
		var interval := 0.22 - power * 0.16
		if charge_sound_timer <= 0.0:
			charge_sound_timer = maxf(interval, 0.05)
			Sfx.charge()


func _update_ball(delta: float) -> void:
	if state == State.FLYING:
		_fly(delta)
	elif state == State.RETURNING:
		_returning(delta)


func _fly(delta: float) -> void:
	# 分子步进：高速时也保证不会穿过斜坡/砖块
	var steps := clampi(int(ceilf(ball.vel.length() * delta / 22.0)), 1, 8)
	var sdt := delta / float(steps)
	var snapshot := ores.duplicate()
	for i in steps:
		ball.vel.y -= 650.0 * sdt
		ball.vel *= 1.0 - 0.06 * sdt
		# 速度上限，避免高速位移穿透边界墙
		var spd := ball.vel.length()
		if spd > 2200.0:
			ball.vel = ball.vel.normalized() * 2200.0
		ball.pos += ball.vel * sdt

		_clamp_ball_to_bounds()

		for ore in snapshot:
			if ore.broken or not is_instance_valid(ore):
				continue
			_collide_ore(ore)

		# 底部 V 形斜坡：真实反射（视觉与碰撞共用同一组端点）
		if _collide_ball_slopes():
			fx.sparkle(_ball_pos(), Color("#ffd27a"))

		# 漏斗口弹板：撞上被大力弹回，小球绝不会掉进漏斗
		_collide_ball_funnel()

	if bounce_count >= max_bounces:
		# 普通爆炸球必须双击收回，否则弹尽即爆；特殊球（SAFE/BIG 等奖励球）自动返回。
		if current_ball_kind == BallKind.NORMAL:
			_begin_detonate()
		else:
			_return_ball()
		return

	# 濒死拖尾：剩余弹跳少时喷出火花
	if max_bounces - bounce_count <= 5:
		trail_timer += delta
		if trail_timer > 0.06:
			trail_timer = 0.0
			fx.sparkle(_ball_pos(), Color("#ff6600"))

	_apply_ball_color()
	ball.sync_transform()


## 把球位置钳制在 BOUNDS 内（含半径），触碰边界则反弹。
## count_bounce=false 时只钳制位置/反弹，不累计弹跳、不播 bounce 音效
## （用于炸膛 WARNING 阶段，避免已经"弹跳耗尽"后仍触发计弹跳）。
func _clamp_ball_to_bounds(count_bounce: bool = true, restitution: float = 0.95) -> void:
	var r := ball.radius
	var minx := BOUNDS.position.x + r
	var maxx := BOUNDS.position.x + BOUNDS.size.x - r
	var miny := BOUNDS.position.y + r
	var maxy := BOUNDS.position.y + BOUNDS.size.y - r

	if ball.pos.x < minx:
		ball.pos.x = minx
		ball.vel.x = absf(ball.vel.x) * restitution
		if count_bounce:
			_bounce()
	elif ball.pos.x > maxx:
		ball.pos.x = maxx
		ball.vel.x = -absf(ball.vel.x) * restitution
		if count_bounce:
			_bounce()
	# 底部不做平边界钳制：由 V 形斜坡（_collide_ball_slopes）接管
	if ball.pos.y > maxy:
		ball.pos.y = maxy
		ball.vel.y = -absf(ball.vel.y) * restitution
		if count_bounce:
			_bounce()


## 圆 vs 线段碰撞解算（斜坡通用）。返回 [位置, 速度, 是否命中, 法向撞击强度]。
## 低速接触不再施加弹性（避免静止/滚动时抖动），只做位置修正 + 切向摩擦。
func _resolve_segment(a: Vector2, b: Vector2, pos: Vector2, vel: Vector2, r: float,
		restitution: float, friction: float) -> Array:
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 < 0.0001:
		return [pos, vel, false, 0.0]
	var t := clampf((pos - a).dot(ab) / ab_len2, 0.0, 1.0)
	var c := a + ab * t
	var delta_v := pos - c
	var d := delta_v.length()
	if d >= r:
		return [pos, vel, false, 0.0]
	var n := (delta_v / d) if d > 0.001 else Vector2(0.0, 1.0)
	var new_pos := c + n * r
	var vn := vel.dot(n)
	var new_vel := vel
	if vn < 0.0:
		var rest := restitution if vn < -55.0 else 0.0
		new_vel = vel - (1.0 + rest) * vn * n
		# 切向摩擦：让球/粒子沿斜面"滚"而不是打滑
		var n_comp := new_vel.dot(n) * n
		var tangent := new_vel - n_comp
		new_vel = n_comp + tangent * (1.0 - friction)
	return [new_pos, new_vel, true, absf(vn)]


## 小球与底部两侧斜坡的碰撞。
## 只有"真正的撞击"（法向速度足够大）才计一次弹跳并带冷却，
## 否则沿斜面滚动时每帧接触会把弹跳数瞬间刷爆。
func _collide_ball_slopes() -> bool:
	if ball.pos.y > SLOPE_OUTER_Y + ball.radius:
		return false  # 高于斜坡，跳过
	var hit := false
	var res := _resolve_segment(slope_l_a, slope_l_b, ball.pos, ball.vel, ball.radius,
		SLOPE_RESTITUTION, SLOPE_FRICTION)
	ball.pos = res[0]
	ball.vel = res[1]
	if res[2]:
		hit = true
		if res[3] > 150.0 and slope_bounce_cd <= 0.0:
			slope_bounce_cd = 0.09
			_bounce()
	res = _resolve_segment(slope_r_a, slope_r_b, ball.pos, ball.vel, ball.radius,
		SLOPE_RESTITUTION, SLOPE_FRICTION)
	ball.pos = res[0]
	ball.vel = res[1]
	if res[2]:
		hit = true
		if res[3] > 150.0 and slope_bounce_cd <= 0.0:
			slope_bounce_cd = 0.09
			_bounce()
	return hit


## 漏斗口弹板：小球撞上会被大力弹上去，永远不会掉进漏斗被吞掉。
## 碰撞线段横跨整个漏斗口，任何情况下都把球心顶到弹板之上。
func _collide_ball_funnel() -> bool:
	if ball.pos.y > FUNNEL_MOUTH_Y + ball.radius:
		return false
	var plug_a := Vector2(-FUNNEL_HALF - 10.0, FUNNEL_MOUTH_Y)
	var plug_b := Vector2(FUNNEL_HALF + 10.0, FUNNEL_MOUTH_Y)
	var res := _resolve_segment(plug_a, plug_b, ball.pos, ball.vel, ball.radius,
		FUNNEL_BOUNCE_REST, 0.06)
	ball.pos = res[0]
	ball.vel = res[1]
	# 兜底：球心不允许低于弹板（例如高速穿入或掉进喉管）
	if ball.pos.y < FUNNEL_MOUTH_Y + ball.radius:
		ball.pos.y = FUNNEL_MOUTH_Y + ball.radius
	# 大力弹上去：保证最小上抛速度，并给一点横向散射避免垂直死循环
	if ball.vel.y < FUNNEL_KICK:
		ball.vel.y = FUNNEL_KICK
	ball.vel.x += randf_range(-140.0, 140.0)
	_bounce_funnel()
	return true


## 弹板命中演出：爆闪 + 火花 + 震屏 + 弹板压扁回弹。
## 文案只在"首次接触"播一次，避免反复弹起时 3D Label 叠加糊屏。
func _bounce_funnel() -> void:
	bouncer_punch = 1.0
	if _funnel_pad_mat != null:
		_funnel_pad_mat.emission_energy_multiplier = 7.0
	if _funnel_mouth_mat != null:
		_funnel_mouth_mat.emission_energy_multiplier = 4.5
	if funnel_bounce_cd > 0.0:
		return
	funnel_bounce_cd = 0.22
	_bounce()
	Sfx.bounce()
	fx.burst(Vector3(ball.pos.x, FUNNEL_MOUTH_Y + 10.0, 0.0), Color("#ffd27a"), 26, 300.0, 0.5, 3.0)
	fx.sparkle(Vector3(ball.pos.x, FUNNEL_MOUTH_Y + 6.0, 0.0), Color("#fff0c0"))
	fx.float_text(Vector3(ball.pos.x, FUNNEL_MOUTH_Y + 34.0, 0.0), "BOUNCE!", Color("#ffd27a"), 11)
	if screen_shake:
		shake_amount = maxf(shake_amount, 11.0)


func _returning(delta: float) -> void:
	return_timer -= delta
	if return_timer <= 0.0:
		_on_ball_returned()
		return

	_apply_ball_color()
	ball.pos = ball.pos.lerp(BALL_START, 4.5 * delta)
	ball.sync_transform()


## 球回到起始点后的统一结算：重置连击/倍率 → 砖块上移 → 判定过关。
func _on_ball_returned() -> void:
	# 分数已在击碎矿石时即时结算，这里只重置本轮的连击与倍率。
	recall_snapping = false
	combo = 0
	current_multiplier = 1.0
	ball.scale = Vector3.ONE

	_advance_rows()
	_update_hud()

	if hearts <= 0:
		_game_over()
		return
	if level_score >= target_score or _all_ores_broken():
		_level_clear()
		return
	_reset_ball()


# ==================== 双击回收演出 ====================
## 双击到球：先闪烁停顿，再动态飞回原位。
func _begin_retract() -> void:
	if (state != State.FLYING and state != State.WARNING) or not ball.active:
		return
	state = State.RETRACT
	retract_phase = RetractPhase.FLASH
	retract_timer = RETRACT_FLASH_TIME
	ball.vel = Vector2.ZERO
	recall_snapping = true
	Sfx.retract()
	if crosshair != null:
		crosshair.hit_mark()
		crosshair.set_target(_world_to_screen(ball.pos), 0.0, 0.0)


func _update_retract(delta: float) -> void:
	retract_timer -= delta
	if retract_phase == RetractPhase.FLASH:
		# 阶段一：原地闪烁停顿（球被"定住"，高频白闪 + 微抖）
		var k := clampf(retract_timer / RETRACT_FLASH_TIME, 0.0, 1.0)
		var flash := 0.5 + 0.5 * sin((1.0 - k) * 46.0)
		ball.set_state(Color.WHITE.lerp(Color("#ffd27a"), flash * 0.7), Color("#ffaa00"),
			6.0 + flash * 5.0)
		ball.pos += Vector2(randf() - 0.5, randf() - 0.5) * 4.0
		var s := 1.0 + flash * 0.18
		ball.scale = Vector3(s, 2.0 - s, 1.0)
		ball.sync_transform()
		if randf() < 0.5:
			fx.sparkle(_ball_pos() + Vector3((randf() - 0.5) * 30.0, (randf() - 0.5) * 30.0, 0.0),
				Color("#ffe08a"))
		if retract_timer <= 0.0:
			retract_phase = RetractPhase.FLY
			retract_timer = RETRACT_FLY_TIME
			retract_from = ball.pos
			fx.float_text(_ball_pos() + Vector3(0, 46, 0), "RECALL!", Color("#ffd27a"), 12)
			Sfx.retract()
		return

	# 阶段二：带回弹的动感回位（三次缓出 + 抛物弧线 + 拖尾 + squash&stretch）
	var k := clampf(1.0 - retract_timer / RETRACT_FLY_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var arc := sin(k * PI) * 46.0
	ball.pos = retract_from.lerp(BALL_START, e) + Vector2(0.0, arc)
	var stretch := 1.0 + sin(k * PI) * 0.22
	ball.scale = Vector3(1.0 / stretch, stretch, 1.0)
	ball.set_state(Color("#ffd27a").lerp(Color("#c8883a"), e * 0.7), Color("#ffaa00"), 3.0)
	ball.sync_transform()
	if crosshair != null:
		crosshair.set_target(_world_to_screen(ball.pos), 0.0, 0.0)
	trail_timer += delta
	if trail_timer > 0.028:
		trail_timer = 0.0
		fx.sparkle(_ball_pos(), Color("#ffd27a"))
	if retract_timer <= 0.0:
		ball.scale = Vector3.ONE
		ball.pos = BALL_START
		ball.sync_transform()
		_on_ball_returned()


func _bounce() -> void:
	bounce_count += 1
	Sfx.bounce()


func _collide_ore(ore: Ore) -> void:
	var d := ball.pos.distance_to(ore.pos2d)
	var min_dist := ball.radius + ore.radius
	if d >= min_dist or d < 0.01:
		return
	var n := (ball.pos - ore.pos2d) / d
	ball.pos += n * (min_dist - d)
	var dot := ball.vel.dot(n)
	ball.vel -= 2.0 * dot * n
	var ang := n.angle() + (randf() - 0.5) * (0.8 if not ore.is_brick else 1.2)
	var spd := ball.vel.length() * (0.95 + randf() * 0.2 if not ore.is_brick else 1.0)
	ball.vel = Vector2(cos(ang), sin(ang)) * spd
	if ball.vel.y > 0.0:
		ball.vel.y = -absf(ball.vel.y)

	_bounce()
	if ore.is_brick:
		Sfx.brick()
		fx.burst(_ball_pos(), Color("#8a7050"), 5, 80.0, 0.3, 2.0)
		if ore.take_hit():
			_break_ore(ore, 0)
	else:
		current_multiplier *= 1.12
		fx.sparkle(_ball_pos(), ore.base_color)
		if ore.take_hit():
			_break_ore(ore, 0)


func _break_ore(ore: Ore, chain: int) -> void:
	if ore.broken:
		return
	ore.broken = true
	ores.erase(ore)
	var p := _ore_pos3(ore)
	var color := ore.base_color

	# 分数即时结算：击碎即得分，杜绝"清了矿石却显示 0 分"。
	var gain := _score_for(ore, chain)
	if gain > 0:
		total_score += gain
		level_score += gain
		fx.float_text(p + Vector3(0, 30, 0), "+%d" % gain, Color("#ffd27a"), 10)

	fx.burst(p, color, 9 + chain * 3, 150.0 + chain * 30.0, 0.5, 1.8)
	fx.fall(p, color, 5 + chain * 2)
	if crosshair != null:
		crosshair.hit_mark()
	for s in 4 + chain * 1:
		fx.sparkle(p + Vector3((randf() - 0.5) * 32.0, (randf() - 0.5) * 32.0, 0.0), color)
	Sfx.break_ore(chain)

	if not ore.is_brick:
		# 矿石掉落对应颜色的能量粒子（掉入底部漏斗积攒能量）
		var count := clampi(int(ore.value * (1.0 + chain * 0.25)), 1, 5)
		for g in count:
			_spawn_particle(ore.pos2d + Vector2((randf() - 0.5) * 25.0, (randf() - 0.5) * 25.0), color, ore.value)
		current_multiplier *= 1.25 + chain * 0.08
		combo += 1
		if chain < 6:
			var radius := ore.radius * 3.5 + chain * 18.0
			for other in ores.duplicate():
				if other.broken:
					continue
				if other.pos2d.distance_to(ore.pos2d) < radius:
					if not other.is_brick and other.kind == ore.kind:
						_schedule_break(other, chain + 1, 0.05 + chain * 0.035)
					elif other.take_hit():
						_schedule_break(other, chain + 1, 0.09 + chain * 0.045)
		if chain >= 2:
			var cols := [Color("#ff8800"), Color("#ffcc00"), Color("#ff4400"), Color.WHITE]
			fx.float_text(p + Vector3(0, 35, 0), "x%d CHAIN!" % chain, cols[mini(chain, cols.size() - 1)], mini(10 + chain, 16))

	ore.remove_self()


## 延迟连锁破碎：用自建队列代替 Timer + lambda 捕获，
## 避免矿石被提前释放（换关/重开）时"Lambda capture was freed"的报错。
func _schedule_break(ore: Ore, chain: int, delay: float) -> void:
	ores.erase(ore)
	pending_breaks.append([ore, chain, delay])


func _update_pending(delta: float) -> void:
	for i in range(pending_breaks.size() - 1, -1, -1):
		var e: Array = pending_breaks[i]
		e[2] = (e[2] as float) - delta
		if (e[2] as float) > 0.0:
			continue
		pending_breaks.remove_at(i)
		var raw: Variant = e[0]
		if raw == null or not is_instance_valid(raw):
			continue  # 矿石已被释放（换关/重开）
		var o := raw as Ore
		if o != null and not o.broken:
			_break_ore(o, int(e[1]))


## 击碎得分 = 该矿石的边数（三角形 3 分 … 七边形 7 分）。
## 不乘倍率、不乘连锁加成：分数只取决于"打碎了什么"，进度条推进稳定可控。
## 倍率与连锁仍然演出（HUD 滚动数字），只是不再放大分数。
func _score_for(ore: Ore, _chain: int = 0) -> int:
	return maxi(1, ore.sides)


func _spawn_particle(p: Vector2, color: Color, value: float) -> void:
	var g := Gem.new()
	g.setup(color, value)
	g.pos2d = p
	# 实体爆散：向上向外崩开，之后完全交给重力与斜坡物理
	var ang := randf_range(-PI, PI)
	var spd := randf_range(140.0, 360.0)
	g.vel = Vector2(cos(ang) * spd, absf(sin(ang)) * spd * 0.75 + 140.0)
	gems_container.add_child(g)
	gems.append(g)


## 矿石粒子物理：重力 + 空气阻力 + 边墙/斜坡反弹 + 沿斜面滚落。
## 落到底部料池后按列真实堆叠成"池"；池满即能量满（不再有吸收消失的逻辑）。
func _update_gems(delta: float) -> void:
	for i in range(gems.size() - 1, -1, -1):
		var g := gems[i]
		# 已落入料池的粒子：缓缓归位到堆叠点（真实堆积的视觉收尾），不再受物理。
		if g.settled:
			g.pos2d.x = lerpf(g.pos2d.x, g.rest_x, minf(1.0, 10.0 * delta))
			g.pos2d.y = lerpf(g.pos2d.y, g.rest_y, minf(1.0, 10.0 * delta))
			g.vel = Vector2.ZERO
			g.sync()
			continue

		g.vel.y -= 900.0 * delta
		g.vel *= 1.0 - 0.5 * delta
		g.pos2d += g.vel * delta

		var r := g.radius
		# 左右墙反弹
		if g.pos2d.x < FIELD_LEFT + r:
			g.pos2d.x = FIELD_LEFT + r
			g.vel.x = absf(g.vel.x) * 0.55
		elif g.pos2d.x > FIELD_RIGHT - r:
			g.pos2d.x = FIELD_RIGHT - r
			g.vel.x = -absf(g.vel.x) * 0.55

		# 底部 V 形斜坡：真实反弹 + 摩擦滚动（只在此高度范围内检测）
		if g.pos2d.y < SLOPE_OUTER_Y + r + 60.0:
			var res := _resolve_segment(slope_l_a, slope_l_b, g.pos2d, g.vel, r,
				GEM_RESTITUTION, GEM_FRICTION)
			g.pos2d = res[0]
			g.vel = res[1]
			if res[2] and randf() < 0.06:
				fx.sparkle(Vector3(g.pos2d.x, g.pos2d.y, 0.0), g.color)
			res = _resolve_segment(slope_r_a, slope_r_b, g.pos2d, g.vel, r,
				GEM_RESTITUTION, GEM_FRICTION)
			g.pos2d = res[0]
			g.vel = res[1]

		# 触底：堆进料池（按列堆叠，找邻近最低列，使池面平整上涨）
		if g.pos2d.y <= POOL_FLOOR_Y + r:
			# 防御：若料池计数数组未初始化（理论上首局已开始时会初始化），先补齐再堆叠
			if pool_counts.size() != POOL_COLS:
				pool_counts = PackedInt32Array()
				pool_counts.resize(POOL_COLS)
			var c := clampi(int((g.pos2d.x - POOL_LEFT) / POOL_COL_W), 0, POOL_COLS - 1)
			var best := c
			for d in [-2, -1, 1, 2]:
				var nc: int = c + d
				if nc >= 0 and nc < POOL_COLS and pool_counts[nc] < pool_counts[best]:
					best = nc
			c = best
			var surf := POOL_FLOOR_Y + pool_counts[c] * POOL_SPACING + r
			g.settled = true
			g.rest_x = POOL_LEFT + (float(c) + 0.5) * POOL_COL_W + randf_range(-3.0, 3.0)
			g.rest_y = surf
			pool_counts[c] += 1
			pool_count += 1
			g.vel = Vector2.ZERO
			energy = minf(float(pool_count) / float(POOL_CAPACITY), 1.0)
			Sfx.gem(int(g.value))
			fx.sparkle(Vector3(g.rest_x, g.rest_y, 0.0), g.color)
			hud.set_energy(energy, ENERGY_FULL)
			if energy >= 1.0 and not _pool_full_announced:
				_pool_full_announced = true
				Sfx.energy_full()
				fx.float_text(Vector3(0.0, POOL_FLOOR_Y + 46.0, 0.0), "ENERGY FULL!", Color("#ffd27a"), 10)
			g.sync()
			continue

		# 兜底：异常跌出场地
		if g.pos2d.y < FIELD_BOTTOM - 60.0:
			g.queue_free()
			gems.remove_at(i)
			continue

		g.sync()
		g.life -= delta
		if g.life <= 0.0:
			g.queue_free()
			gems.remove_at(i)


# ==================== 矿石粒子池（真实物理堆积） ====================
## 重置料池：释放所有粒子、清空列计数与能量。
func _reset_pool() -> void:
	for g in gems:
		g.queue_free()
	gems.clear()
	pool_counts = PackedInt32Array()
	pool_counts.resize(POOL_COLS)
	pool_count = 0
	energy = 0.0
	_pool_full_announced = false


## 料池底面辉光：随填充度由暗琥珀渐亮，满池时呼吸脉动。
func _update_pool() -> void:
	if _pool_floor_mat == null:
		return
	var r := clampf(energy, 0.0, 1.0)
	var pulse := 1.0 + 0.18 * sin(Time.get_ticks_msec() * 0.004)
	_pool_floor_mat.emission_energy_multiplier = (0.5 + r * 2.2) * (1.0 if r < 1.0 else pulse)
	_pool_floor_mat.emission = Color(1.4, 0.25, 0.12).lerp(Color("#ffb43a"), r)


# ==================== 发射 / 回收 / 爆炸 ====================
func _launch(power_val: float) -> void:
	# 矿石粒子池满：先进入老虎机演出，抽完奖励再发射；否则直接发射。
	if energy >= ENERGY_FULL:
		_start_slot(power_val)
		return
	current_ball_kind = next_ball_kind
	next_ball_kind = BallKind.NORMAL
	_do_launch(power_val)


## 实际发射：应用 current_ball_kind（NORMAL / SAFE / BIG）。
func _do_launch(power_val: float) -> void:
	hud.set_energy(energy, ENERGY_FULL)

	state = State.FLYING
	ball.active = true
	bounce_count = 0
	max_bounces = 10 + randi() % 20
	current_multiplier = 1.0
	combo = 0
	return_timer = 0.0
	# 蓄力方向 = 按住起点 → 当前鼠标终点（完全跟随拖拽方向，不再强制向下/向上）；
	# 只有真实拖拽（>3px）才刷新 last_aim_dir，极短抖动保持上一帧方向，避免"接近时方向乱跳"。
	var dir := _aim_direction()
	var speed := 500.0 + power_val * 1000.0
	ball.vel = dir * speed
	ball.scale = Vector3.ONE * (1.55 if current_ball_kind == BallKind.BIG else 1.0)
	ball.set_state(Color("#c8883a"), Color("#5a3410"), 0.7)
	Sfx.launch()
	if current_ball_kind == BallKind.SAFE:
		fx.float_text(_ball_pos() + Vector3(0, 50, 0), "SAFE BALL!", Color("#3ac060"), 12)
	elif current_ball_kind == BallKind.BIG:
		fx.float_text(_ball_pos() + Vector3(0, 50, 0), "BIG BALL!", Color("#ff6622"), 12)
	_apply_ball_color()


## 启动老虎机：能量池满后自动抽奖，消耗整池。
## 底部实体机匣全屏弹出，暗角加深聚焦，庆祝特效叠加。
func _start_slot(power_val: float) -> void:
	state = State.SLOT
	_slot_timer = 0.0
	_slot_index = 0
	_slot_reward = -1
	_slot_power = power_val
	slot_machine.deploy()
	if _vignette != null:
		_vignette.set_strength(0.8)
	celebrate.play(4.6)
	Sfx.energy_full()
	fx.float_text(Vector3(0.0, 120.0, 0.0), "ORE POOL FULL!", Color("#ffd27a"), 14)
	hud.flash_white()


## 老虎机每帧：2.1s 滚动 → 0.6s 落定 → 1.5s 展示奖励 → 收回并发射。
func _update_slot(delta: float) -> void:
	_slot_timer += delta
	# 滚动阶段：每 0.08s 切换一个候选名，制造"滚动"感
	if _slot_timer < 2.1:
		if int(_slot_timer / 0.08) != _slot_index:
			_slot_index = int(_slot_timer / 0.08)
			var fake: int = randi() % Reward.size()
			hud.show_slot_name(REWARD_NAMES[fake], REWARD_COLORS[fake])
			Sfx.charge()
	elif _slot_timer < 2.7:
		# 落定阶段：只切换一次到真实奖励（立即生效，展示期间就能看到血量/球种变化）
		if _slot_reward == -1:
			_slot_reward = _roll_reward()
			_apply_reward(_slot_reward)
			slot_machine.set_result(_slot_reward)
			hud.show_slot_name(REWARD_NAMES[_slot_reward], REWARD_COLORS[_slot_reward])
			Sfx.launch()
	elif _slot_timer < 4.2:
		pass  # 展示阶段：机匣停轮 + 奖励名定格
	else:
		_finish_slot()


## 抽取一个奖励：均匀随机，后续可按权重调整。
func _roll_reward() -> int:
	return randi() % Reward.size()


## 老虎机结束：收回机匣、清空料池；球回到原点，由玩家手动蓄力发射。
## 奖励球种（SAFE/BIG）保留到真正发射时才消耗，待发射期间球体直接呈现奖励形态。
func _finish_slot() -> void:
	slot_machine.fold()
	if _vignette != null:
		_vignette.set_strength(0.62)
	energy = 0.0
	pool_count = 0
	_reset_pool()
	hud.hide_slot()
	current_ball_kind = next_ball_kind
	if current_ball_kind == BallKind.SAFE:
		fx.float_text(_ball_pos() + Vector3(0, 60, 0), "SAFE BALL READY", Color("#3ac060"), 12)
	elif current_ball_kind == BallKind.BIG:
		fx.float_text(_ball_pos() + Vector3(0, 60, 0), "BIG BALL READY", Color("#ff6622"), 12)
	_reset_ball()
	# BIG 奖励球待发射时保持 1.55x 体型，一眼看出手上的球不一样
	ball.scale = Vector3.ONE * (1.55 if current_ball_kind == BallKind.BIG else 1.0)
	ball.sync_transform()


## 强制中止老虎机（重开/回菜单时调用）：收回机匣、还原暗角，不发奖励不发射。
func _slot_abort() -> void:
	if state == State.SLOT:
		state = State.IDLE
	if slot_machine != null and slot_machine.deployed:
		slot_machine.fold()
	if _vignette != null:
		_vignette.set_strength(0.62)
	hud.hide_slot()


## 应用奖励效果。
func _apply_reward(r: int) -> void:
	match r:
		Reward.EXTRA_HEART:
			max_hearts += 1
			hearts = mini(hearts + 1, max_hearts)
			fx.float_text(Vector3(0.0, 80.0, 0.0), "MAX HEART +1", Color("#ff3a3a"), 12)
		Reward.LAST_STAND:
			last_stand_charges += 1
			fx.float_text(Vector3(0.0, 80.0, 0.0), "LAST STAND READY", Color("#ffd27a"), 12)
		Reward.SAFE_BALL:
			next_ball_kind = BallKind.SAFE
			fx.float_text(Vector3(0.0, 80.0, 0.0), "NEXT: SAFE BALL", Color("#3ac060"), 12)
		Reward.BIG_BALL:
			next_ball_kind = BallKind.BIG
			fx.float_text(Vector3(0.0, 80.0, 0.0), "NEXT: BIG BALL", Color("#ff6622"), 12)
	hud.set_hearts(hearts, max_hearts)


func _return_ball() -> void:
	if (state != State.FLYING and state != State.WARNING) or not ball.active:
		return
	state = State.RETURNING
	return_timer = 0.55
	Sfx.retract()


## 弹跳耗尽 → 进入延迟引爆警告阶段（约 0.9s 后真正爆炸）。
func _begin_detonate() -> void:
	state = State.WARNING
	detonate_timer = 0.9
	danger_timer = 0.0
	Sfx.detonate_warn()
	hud.flash_red()


func _update_warning(delta: float) -> void:
	detonate_timer -= delta
	# 球轻微下坠 + 快速衰减，营造悬停压迫感
	ball.vel.y -= 160.0 * delta
	ball.vel *= 1.0 - 2.5 * delta
	ball.pos += ball.vel * delta
	# 炸膛阶段同样钳制在边界内（软反弹、不计数不播音效），防止穿出左右/上边界
	_clamp_ball_to_bounds(false, 0.4)

	# 引爆阶段仍需斜坡/漏斗碰撞，否则小球会穿过漏斗掉下去
	if _collide_ball_slopes():
		fx.sparkle(_ball_pos(), Color("#ffd27a"))
	_collide_ball_funnel()

	# 濒死高频闪烁 + 火花拖尾 + 倒计时滴答
	danger_timer += delta
	if danger_timer > 0.07:
		danger_timer = 0.0
		Sfx.detonate_tick()
		fx.sparkle(_ball_pos() + Vector3((randf() - 0.5) * 30.0, (randf() - 0.5) * 30.0, 0.0), Color("#ff4400"))

	_apply_ball_color()
	ball.sync_transform()

	if detonate_timer <= 0.0:
		_explode()


## 危险度：驱动球光晕脉冲 + 屏幕红晕警示层。
func _update_danger(_delta: float) -> void:
	var remaining := max_bounces - bounce_count
	var danger := 0.0
	if state == State.WARNING:
		danger = 1.0
	elif ball.active and (state == State.FLYING or state == State.RETURNING) and remaining <= 4:
		danger = clampf(1.0 - float(remaining) / 4.0, 0.0, 1.0)
	ball.set_danger(danger)
	# 屏幕红晕同时反映"球快炸"和"砖块逼近斩杀线"
	hud.set_danger(maxf(danger, _kill_line_proximity() * 0.5))


## FPS 瞄准镜准星：跟随指针，蓄力时张开，游戏中隐藏系统光标。
func _update_crosshair() -> void:
	if crosshair == null:
		return
	var playing := state != State.GAMEOVER
	var show_custom := pointer_active
	# 自定义光标可见性：仅在需要时才显示
	crosshair.set_reticle_visible(show_custom)
	# 系统光标：只要显示自定义光标就隐藏，杜绝系统箭头露出
	if show_custom != _cursor_hidden:
		_cursor_hidden = show_custom
		_set_cursor_hidden(show_custom)
	if not show_custom:
		return
	# 对局态=方形瞄准镜；菜单/结算态=设计指针
	var is_scope := playing and not in_menu
	crosshair.set_mode("scope" if is_scope else "pointer")
	var mp := get_viewport().get_mouse_position()
	# 回收演出中：光标贴合小球，随球一起归位
	if is_scope and (recall_snapping or state == State.RETRACT):
		crosshair.set_target(_world_to_screen(ball.pos), 0.0, 0.0)
		return
	if is_scope and state == State.IDLE:
		# 蓄力时方框张开 + 颜色转红
		crosshair.set_target(mp, power * 18.0, power)
	elif is_scope:
		crosshair.set_target(mp, 2.0, 0.0)
	else:
		# 设计指针跟随鼠标
		crosshair.set_target(mp, 0.0, 0.0)


func _explode() -> void:
	state = State.EXPLODED
	Sfx.explosion()
	if screen_shake:
		shake_amount = 18.0
	_damage_heart("BOOM!")
	combo = 0
	current_multiplier = 1.0
	hud.flash_white()

	var p := _ball_pos()
	fx.burst(p, Color("#ff4400"), 60, 280.0, 1.0, 4.0)
	fx.burst(p, Color("#ffaa00"), 40, 200.0, 0.9, 3.0)
	fx.burst(p, Color.WHITE, 20, 120.0, 0.7, 2.0)
	for s in 25:
		fx.sparkle(p + Vector3((randf() - 0.5) * 80.0, (randf() - 0.5) * 80.0, 0.0), Color("#ff8800"))
	fx.float_text(p + Vector3(0, 40, 0), "BOOM!", Color("#ff2200"), 14)

	var radius := (110.0 + level * 4.0) * (1.55 if current_ball_kind == BallKind.BIG else 1.0)
	for ore in ores.duplicate():
		if ore.broken:
			continue
		if ore.pos2d.distance_to(ball.pos) < radius:
			if ore.is_brick:
				if ore.take_hit():
					_break_ore(ore, 1)
			else:
				ore.damage(2)
				if ore.hp <= 0:
					_schedule_break(ore, 1, 0.04 + randf() * 0.08)

	ball.active = false
	ball.visible = false
	ball.set_state(Color.BLACK, Color.BLACK, 0.0)

	if hearts <= 0:
		get_tree().create_timer(0.9).timeout.connect(_game_over)
	else:
		get_tree().create_timer(1.1).timeout.connect(_reset_ball)


func _reset_ball() -> void:
	state = State.IDLE
	ball.active = false
	ball.visible = true
	ball.scale = Vector3.ONE
	ball.pos = BALL_START
	ball.vel = Vector2.ZERO
	bounce_count = 0
	max_bounces = 15
	_apply_ball_color()
	ball.sync_transform()
	_update_hud()


func _game_over() -> void:
	state = State.GAMEOVER
	if crosshair != null:
		crosshair.set_reticle_visible(false)
	_cursor_hidden = false
	_set_cursor_hidden(false)
	hud.show_game_over(total_score, level)


func _restart() -> void:
	hud.hide_game_over()
	_slot_abort()
	hearts = 3
	max_hearts = 3
	level = 1
	total_score = 0
	level_score = 0
	current_ball_kind = BallKind.NORMAL
	next_ball_kind = BallKind.NORMAL
	last_stand_charges = 0
	combo = 0
	current_multiplier = 1.0
	_reset_pool()
	hud.set_hearts(hearts, max_hearts)
	hud.set_energy(energy, ENERGY_FULL)
	_start_level()


# ==================== 菜单 / 设置 ====================
## 从菜单读取设置并应用到世界与音频。
func _apply_settings_from_menu() -> void:
	apply_settings(menu.bgm_volume, menu.sfx_volume, menu.glow_enabled, menu.screen_shake)


## 设置面板实时回调：应用辉光/震动/音量。
func apply_settings(bgm: float, sfx: float, glow: bool, shake: bool) -> void:
	glow_enabled = glow
	screen_shake = shake
	if _env != null:
		_env.glow_enabled = glow
	Sfx.set_bgm_volume(bgm)
	Sfx.set_sfx_volume(sfx)


## 菜单“开始/继续”回调。
func _on_start_game() -> void:
	_apply_settings_from_menu()
	in_menu = false
	menu.hide_menu()
	hud.visible = true
	_cursor_hidden = true
	_set_cursor_hidden(true)
	if not game_started:
		game_started = true
		_reset_pool()      # 首局初始化料池计数，避免粒子落入空数组越界
		_start_level()


## 游戏中途暂停回菜单（保留当前进度）。
func _pause_to_menu() -> void:
	in_menu = true
	hud.visible = false
	crosshair.set_reticle_visible(false)
	_cursor_hidden = false
	_set_cursor_hidden(false)
	menu.set_start_label(true)
	menu.show_menu()


## 游戏结束返回主菜单（重置为全新一局）。
func _to_menu_fresh() -> void:
	hud.hide_game_over()
	_slot_abort()
	hearts = 3
	max_hearts = 3
	level = 1
	total_score = 0
	level_score = 0
	energy = 0.0
	current_ball_kind = BallKind.NORMAL
	next_ball_kind = BallKind.NORMAL
	last_stand_charges = 0
	combo = 0
	current_multiplier = 1.0
	game_started = false
	in_menu = true
	hud.visible = false
	crosshair.set_reticle_visible(false)
	_cursor_hidden = false
	_set_cursor_hidden(false)
	hud.set_hearts(hearts, max_hearts)
	hud.set_energy(energy, ENERGY_FULL)
	for o in ores:
		o.queue_free()
	ores.clear()
	for g in gems:
		g.queue_free()
	gems.clear()
	pending_breaks.clear()
	_reset_pool()
	_reset_ball()
	menu.set_start_label(false)
	menu.show_menu()


# ==================== 关卡 / 砖块 ====================
func _start_level() -> void:
	# 每次刷新关卡都把血条回满（支持 max_hearts 提升后）
	hearts = max_hearts
	hud.set_hearts(hearts, max_hearts)
	# 计分改为"边数"后单块分值只有 3~7，目标分同步下调；
	# 后期砖块行数封顶（10 行 ≈ 240 分上限），所以目标分也设上限，避免后期不可能达标。
	target_score = mini(70 + (level - 1) * 15, 190)
	level_score = 0
	combo = 0
	current_multiplier = 1.0
	for o in ores:
		o.queue_free()
	ores.clear()
	pending_breaks.clear()
	# 新关卡保留料池，不重置 pool（粒子继续积攒用于老虎机奖励）
	_spawn_grid()
	_reset_ball()
	_update_hud()
	hud.set_energy(energy, ENERGY_FULL)


## 给定 x 处底部斜坡/漏斗口的高度。用于避免把矿石埋进斜坡里（那样球永远打不到）。
func _slope_y_at(x: float) -> float:
	var ax := absf(x)
	if ax <= FUNNEL_HALF:
		return FUNNEL_MOUTH_Y
	if ax >= FIELD_RIGHT:
		return SLOPE_OUTER_Y
	var t := (ax - FUNNEL_HALF) / (FIELD_RIGHT - FUNNEL_HALF)
	return FUNNEL_MOUTH_Y + t * (SLOPE_OUTER_Y - FUNNEL_MOUTH_Y)


func _spawn_grid() -> void:
	var rows := mini(5 + (level - 1), 10)
	var half := (COLS - 1) / 2.0
	for r in rows:
		var y := GRID_TOP_Y - r * ROW_STEP
		if y < GRID_BOTTOM_Y:
			break
		for c in COLS:
			if randf() < 0.26:
				continue  # 留更多空隙，让球能穿过
			var x := -half * COL_STEP + c * COL_STEP
			# 低于斜坡表面的格子不生成：否则矿石会埋进斜坡，球永远够不到
			if y - ORE_CLEARANCE < _slope_y_at(x):
				continue
			var as_brick := randf() < 0.4
			var kind := -1
			var data: Dictionary
			if as_brick:
				data = Ore.BRICK_TYPES[_get_brick_type()]
			else:
				kind = _get_ore_type()
				data = Ore.ORE_TYPES[kind]
			var o := Ore.new()
			o.setup(data, as_brick, kind)
			o.pos2d = Vector2(x + randf_range(-3.0, 3.0), y + randf_range(-3.0, 3.0))
			ores_container.add_child(o)
			ores.append(o)


## 收回后砖块整体上移，检测越过斩杀线。
func _advance_rows() -> void:
	var hit := false
	for ore in ores.duplicate():
		if ore.broken:
			continue
		ore.pos2d.y += ADVANCE
		ore.sync()
		if ore.pos2d.y + ore.radius > KILL_LINE_Y:
			hit = true
			_kill_ore(ore)
	if hit:
		_on_kill_line()


func _kill_ore(ore: Ore) -> void:
	if ore.broken:
		return
	ore.broken = true
	ores.erase(ore)
	fx.burst(_ore_pos3(ore), Color("#ff2200"), 22, 180.0, 0.6, 2.5)
	fx.fall(_ore_pos3(ore), ore.base_color, 14)
	ore.remove_self()


## 统一扣血入口：若持有 LAST STAND 且只剩 1 心，优先消耗 LAST STAND 抵消伤害。
func _damage_heart(label: String = "") -> void:
	if hearts == 1 and last_stand_charges > 0:
		last_stand_charges -= 1
		Sfx.energy_full()
		fx.float_text(Vector3(0.0, 80.0, 0.0), "LAST STAND!", Color("#ffd27a"), 14)
		return
	hearts -= 1
	hud.set_hearts(hearts, max_hearts)
	if not label.is_empty():
		fx.float_text(Vector3(0.0, 100.0, 0.0), label, Color("#ff2200"), 14)


func _on_kill_line() -> void:
	_damage_heart("")
	if screen_shake:
		shake_amount = 16.0
	hud.flash_red()
	Sfx.kill_line()
	fx.float_text(Vector3(0, KILL_LINE_Y, 0), "OUT OF LINE!", Color("#ff2200"), 16)


func _all_ores_broken() -> bool:
	for ore in ores:
		if not ore.broken:
			return false
	return true


## 过关：斩杀线从屏幕顶部下扫，一路清空所有残余砖块（不计分、不推进进度条），
## 扫到底后归位并进入下一关。
func _level_clear() -> void:
	state = State.SWEEP
	level += 1
	sweep_y = FIELD_TOP + 60.0
	ball.visible = false
	celebrate.play(2.6)
	Sfx.level_clear()
	if screen_shake:
		shake_amount = maxf(shake_amount, 8.0)


func _update_sweep(delta: float) -> void:
	sweep_y -= SWEEP_SPEED * delta
	if screen_shake:
		shake_amount = maxf(shake_amount, 4.0)

	# 清掉所有"已经被扫过"的砖块（只做特效，不加分、不加进度）
	for ore in ores.duplicate():
		if ore.broken or not is_instance_valid(ore):
			continue
		if ore.pos2d.y >= sweep_y:
			_sweep_kill(ore)
			if randf() < 0.3:  # 稀疏播放，避免几十个砖块叠成噪音
				Sfx.break_ore(1)

	if sweep_y < FIELD_BOTTOM - 40.0:
		_end_sweep()


## 被清场线扫掉的砖块：只爆特效，不给分（避免清场白送分数与进度）。
func _sweep_kill(ore: Ore) -> void:
	ore.broken = true
	ores.erase(ore)
	var p := _ore_pos3(ore)
	fx.burst(p, ore.base_color, 22, 210.0, 0.7, 3.0)
	fx.burst(p, Color("#ff5533"), 10, 140.0, 0.5, 2.0)
	fx.fall(p, ore.base_color, 8)
	ore.remove_self()


func _end_sweep() -> void:
	state = State.CLEAR
	sweep_y = KILL_LINE_Y
	get_tree().create_timer(1.5).timeout.connect(_start_level)


func _get_ore_type() -> int:
	var r := randf()
	var db := minf(float(level) / 8.0, 0.4)
	if r < 0.25 + db * 0.5:
		return 0
	if r < 0.5 + db * 0.4:
		return 1
	if r < 0.7 + db * 0.3:
		return 2
	if r < 0.88 + db * 0.25:
		return 3
	return 4


func _get_brick_type() -> int:
	var r := randf()
	var db := minf(float(level) / 6.0, 0.3)
	if r < 0.5 - db:
		return 0
	if r < 0.85 - db * 0.5:
		return 1
	return 2


# ==================== 视觉辅助 ====================
func _apply_ball_color() -> void:
	var remaining := max_bounces - bounce_count
	var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
	if current_ball_kind == BallKind.SAFE:
		# 安全球：绿色发光，提示"自动回收、不爆炸"
		ball.set_state(Color("#3ac060"), Color("#1e7038"), 2.0)
		return
	if current_ball_kind == BallKind.BIG:
		# 超大球：橙红粗轮廓，提示大碰撞体积/大爆炸范围
		ball.set_state(Color("#ff6622"), Color("#803010"), 2.2)
		return
	if state == State.WARNING:
		# 濒死：红白高频爆闪 + 强辉光
		var c := Color("#ff2200").lerp(Color.WHITE, flash * 0.8)
		ball.set_state(c, Color("#ff0000"), 4.0 + flash * 2.5)
		return
	if remaining > 10:
		ball.set_state(Color("#3080c8"), Color("#104070"), 1.2)
	elif remaining > 6:
		ball.set_state(Color("#40a0e0"), Color("#1860a0"), 1.7)
	elif remaining > 3:
		ball.set_state(Color("#d07018"), Color("#804008"), 2.2)
	elif remaining > 1:
		ball.set_state(Color("#d02818"), Color("#801010"), 2.8 + flash * 0.8)
	else:
		ball.set_state(Color("#ff2200").lerp(Color("#ff6644"), flash * 0.5), Color("#ff0000"), 3.6 + flash * 1.6)


func _ball_pos() -> Vector3:
	return Vector3(ball.pos.x, ball.pos.y, 0.0)


func _ore_pos3(ore: Ore) -> Vector3:
	return Vector3(ore.pos2d.x, ore.pos2d.y, 0.0)


## 蓄力方向：实时拖拽向量（当前鼠标 - 按下点）。仅真实拖拽（>3px）刷新 last_aim_dir，
## 极短抖动保持上一帧方向，避免"接近时方向乱跳/被强制向上"。
func _aim_direction() -> Vector2:
	var drag := drag_world - press_world
	if drag.length_squared() > 9.0:
		last_aim_dir = drag.normalized()
	return last_aim_dir


func _update_aim_marker() -> void:
	if state == State.IDLE and charging and not aim_forced:
		var dir := _aim_direction()
		var dist := clampf((drag_world - press_world).length(), 28.0, 440.0)
		var pts := PackedVector2Array()
		var step := 20.0
		var d := 24.0
		while d < dist:
			var wp := ball.pos + dir * d
			pts.append(_world_to_screen(wp))
			d += step
		aim_line.show_aim(pts)
	elif not aim_forced:
		aim_line.hide_aim()


func _world_to_screen(w: Vector2) -> Vector2:
	return camera.unproject_position(Vector3(w.x, w.y, 0.0))


## 最近砖块到斩杀线的逼近程度 0..1（1 = 贴线，下一次推进就要越线）。
func _kill_line_proximity() -> float:
	if state == State.SWEEP:
		return 1.0
	var gap_min := 9999.0
	for ore in ores:
		if ore.broken:
			continue
		var gap := KILL_LINE_Y - (ore.pos2d.y + ore.radius)
		if gap < gap_min:
			gap_min = gap
	if gap_min > 9000.0:
		return 0.0
	return clampf(1.0 - gap_min / 150.0, 0.0, 1.0)


## 斩杀线：常驻呼吸闪烁；砖块越逼近 → 闪得越快、越亮，并持续震屏。
## 漏斗口弹板：被撞瞬间压扁并爆亮，随后回弹复位。
func _update_funnel_pad(delta: float) -> void:
	if bouncer_punch > 0.0:
		bouncer_punch = maxf(0.0, bouncer_punch - delta * 5.5)
		if _funnel_pad != null:
			_funnel_pad.scale = Vector3(1.0 + bouncer_punch * 0.14, 1.0 - bouncer_punch * 0.45, 1.0)
	if _funnel_pad_mat != null:
		_funnel_pad_mat.emission_energy_multiplier = maxf(2.6,
			_funnel_pad_mat.emission_energy_multiplier - delta * 14.0)
	if _funnel_mouth_mat != null:
		_funnel_mouth_mat.emission_energy_multiplier = maxf(2.0,
			_funnel_mouth_mat.emission_energy_multiplier - delta * 10.0)


func _update_kill_line(delta: float) -> void:
	kill_line_time += delta
	if _kill_line_mat == null:
		return

	# 换关清场时斩杀线本身下扫，位置由 sweep_y 驱动
	if state == State.SWEEP:
		_kill_line_node.position.y = sweep_y
		_kill_line_glow.position.y = sweep_y
	else:
		_kill_line_node.position.y = KILL_LINE_Y
		_kill_line_glow.position.y = KILL_LINE_Y

	var prox := _kill_line_proximity()
	# 频率：平静时慢呼吸，逼近时急剧加快（最多约 6Hz）
	var freq := 3.0 + prox * prox * 34.0
	var blink := 0.5 + 0.5 * sin(kill_line_time * freq)
	var pulse := blink * blink

	_kill_line_mat.emission_energy_multiplier = 1.0 + pulse * (1.8 + prox * 5.0)
	_kill_line_mat.albedo_color = Color(1.0, 0.10 + 0.45 * prox * blink, 0.05,
		0.32 + 0.6 * pulse)

	if _kill_line_glow_mat != null:
		_kill_line_glow_mat.emission_energy_multiplier = 0.5 + pulse * (1.4 + prox * 4.0)
		_kill_line_glow_mat.albedo_color = Color(1.0, 0.08, 0.04,
			0.05 + 0.26 * pulse * (0.35 + prox))
		_kill_line_glow.scale.y = 1.0 + prox * 0.9 + pulse * 0.35

	# 快逼近：持续震屏（越近越猛）
	if prox > 0.5 and screen_shake and state != State.SWEEP:
		shake_amount = maxf(shake_amount, (prox - 0.5) * 9.0)

	# 漏斗口发光带回落
	if _funnel_mouth_mat != null:
		var e: float = _funnel_mouth_mat.emission_energy_multiplier
		if e > 2.0:
			_funnel_mouth_mat.emission_energy_multiplier = maxf(2.0, e - delta * 9.0)
		else:
			_funnel_mouth_mat.emission_energy_multiplier = 1.6 + sin(kill_line_time * 3.0) * 0.5


func _update_camera(delta: float) -> void:
	# 横版：相机拉到 z≈692（fov55）使世界 1 单位≈1 像素，3D 打击区居中占屏宽约 3/5。
	var base := Vector3(0.0, 0.0, 692.0)
	var sway := Vector3(sin(Time.get_ticks_msec() * 0.0005) * 1.5, cos(Time.get_ticks_msec() * 0.0007) * 1.5, 0.0)
	var shake := Vector3.ZERO
	if shake_amount > 0.0:
		shake = Vector3((randf() - 0.5) * shake_amount, (randf() - 0.5) * shake_amount, 0.0)
		shake_amount *= 0.88
		if shake_amount < 0.15:
			shake_amount = 0.0
	camera.position = base + sway + shake
	camera.look_at(Vector3(0, 0, 0))


func _update_heartbeat(delta: float) -> void:
	var remaining := max_bounces - bounce_count
	if state == State.WARNING or (ball.active and remaining <= 5):
		heartbeat_timer += delta
		var thresh := 0.28 if state == State.WARNING else (1.2 - (5 - remaining) * 0.2)
		if heartbeat_timer > thresh:
			Sfx.heartbeat()
			heartbeat_timer = 0.0
	else:
		heartbeat_timer = 0.0


func _update_hud() -> void:
	hud.set_level(level)
	hud.set_score(level_score, target_score)
	hud.set_energy(energy, ENERGY_FULL)
	if ball.active and (state == State.FLYING or state == State.RETURNING):
		hud.set_multiplier(current_multiplier, max_bounces - bounce_count)
	else:
		hud.hide_multiplier()
	hud.set_combo(combo)
