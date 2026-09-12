extends CanvasLayer
## 全屏低像素化：对已渲染画面做方块降采样 + 轻度色阶量化，
## 得到 Buckshot Roulette 式的粗颗粒像素质感。layer=10（盖在 HUD 之上）。
## pixel_size=2 时 1280x720 → 有效 640x360 的像素颗粒。

const SHADER_CODE := "
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 6.0) = 2.0;

void fragment() {
	vec2 res = vec2(textureSize(screen_tex, 0));
	vec2 grid = max(res / max(pixel_size, 1.0), vec2(2.0));
	vec2 uv = (floor(SCREEN_UV * grid) + vec2(0.5)) / grid;
	vec3 c = texture(screen_tex, uv).rgb;
	// 色阶量化：24 级/通道，强化复古低色深观感，暗部不会被量化出脏色
	c = floor(c * 24.0 + vec3(0.5)) / 24.0;
	COLOR = vec4(c, 1.0);
}
"

var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	layer = 10
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func set_pixel_size(v: float) -> void:
	_mat.set_shader_parameter("pixel_size", v)
