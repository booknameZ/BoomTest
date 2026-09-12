extends CanvasLayer
## 全屏氛围层：暖色暗角 vignette + 轻微噪点颗粒。
## 参考暗黑老虎机质感：四角沉沉压暗，中心留出暖光，模拟烛光照明的视野衰减。
## layer=0（位于 HUD 之下），不拦截鼠标，纯视觉。

const SHADER_CODE := "
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.68;
uniform vec3 warm_tint = vec3(1.0, 0.35, 0.22);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	// 横向略扁的椭圆距离场：匹配 16:9 的暗角形状
	float d = length(uv * vec2(1.25, 1.05));
	// 暗角：从中心向外平滑压暗
	float vig = smoothstep(0.30, 0.82, d);
	// 中心暗红余晖：极淡的酒红色提亮画面中腹
	float glow = smoothstep(0.62, 0.10, d) * 0.04;
	vec3 col = warm_tint * glow;
	// 轻微噪点颗粒：给暗部一点像素呼吸感（随时间缓动）
	float n = fract(sin(dot(UV + vec2(TIME * 0.13, TIME * 0.07), vec2(12.9898, 78.233))) * 43758.5453);
	col += vec3((n - 0.5) * 0.03);
	float a = vig * strength + (n - 0.5) * 0.012 * vig;
	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
"

var _rect: ColorRect

func _ready() -> void:
	layer = 0
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_CODE
	mat.shader = sh
	_rect = ColorRect.new()
	_rect.material = mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func set_strength(v: float) -> void:
	if _rect != null and _rect.material != null:
		(_rect.material as ShaderMaterial).set_shader_parameter("strength", v)
