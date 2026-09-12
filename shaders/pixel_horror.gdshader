shader_type canvas_item;

// 恶魔轮盘赌式低像素微恐后处理：
// 像素化 + 颜色分层(posterize) + 颗粒噪点 + 暗角 + 微偏色

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// 逻辑像素网格（越低越像素化）
uniform vec2 pixel_grid = vec2(320.0, 285.0);
// 颜色分层级数（越低越"低像素"色阶）
uniform float posterize_levels : hint_range(2.0, 64.0) = 12.0;
// 颗粒强度
uniform float grain_amount : hint_range(0.0, 0.5) = 0.07;
// 暗角强度
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.65;
// 扫描线
uniform float scanline_amount : hint_range(0.0, 0.5) = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// 像素化：把采样坐标吸附到低分辨率网格
	vec2 px = floor(uv * pixel_grid) / pixel_grid;
	vec3 col = texture(screen_texture, px).rgb;

	// 颜色分层（色阶量化）
	col = floor(col * posterize_levels) / posterize_levels;

	// 微偏色：整体压暗并向冷棕/灰偏移，制造压抑感
	col = vec3(dot(col, vec3(0.85, 0.06, 0.05)),
	           dot(col, vec3(0.05, 0.85, 0.08)),
	           dot(col, vec3(0.04, 0.08, 0.78)));
	col *= 0.92;

	// 颗粒噪点（随时间闪烁）
	float n = hash(uv * pixel_grid + vec2(TIME * 23.0, TIME * 17.0));
	col += (n - 0.5) * grain_amount;

	// 扫描线
	float sl = sin(uv.y * pixel_grid.y * 3.14159 * 2.0) * 0.5 + 0.5;
	col *= 1.0 - scanline_amount * sl;

	// 暗角
	float d = distance(uv, vec2(0.5, 0.5));
	col *= 1.0 - vignette_strength * d * d * 1.6;

	COLOR = vec4(col, 1.0);
}
