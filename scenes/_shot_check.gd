extends Node
## 交付图校验：读取 preview/ 下的截图，采样关键区域颜色，确认奖励配色一致。
## 校验逻辑：老虎机转轮宝石颜色 应与 HUD 奖励名文字颜色 一致（同为 REWARD_COLORS）。

const FILES := [
	"res://preview/game_collapsed.png",
	"res://preview/slot_rolling.png",
	"res://preview/slot_deployed.png",
]

# 中栏转轮宝石世界坐标 (-200/0/+200, y=20) → 屏幕 (440/640/840, 340)
const GEM_PTS := [Vector2i(440, 340), Vector2i(640, 340), Vector2i(840, 340)]
# 奖励名标签条带：屏幕 (500..780, 64..112)
const LABEL_RECT := Rect2i(500, 64, 280, 48)


func _ready() -> void:
	for f in FILES:
		var img := Image.new()
		if img.load(f) != OK:
			print("MISSING ", f)
			continue
		print("== ", f.get_file(), " size=", img.get_size())
		# 宝石采样：取 5x5 区域最亮像素（避开暗边）
		for i in GEM_PTS.size():
			var p: Vector2i = GEM_PTS[i]
			var best := Color(0, 0, 0)
			var best_l := -1.0
			for dy in range(-6, 7):
				for dx in range(-6, 7):
					var c := img.get_pixel(clampi(p.x + dx, 0, 1279), clampi(p.y + dy, 0, 719))
					var l := c.r + c.g + c.b
					if l > best_l:
						best_l = l
						best = c
			print("  gem", i, " = ", _hex(best))
		# 标签采样：区域内最饱和/最亮的像素
		var lb := Color(0, 0, 0)
		var ll := -1.0
		for y in range(LABEL_RECT.position.y, LABEL_RECT.position.y + LABEL_RECT.size.y, 2):
			for x in range(LABEL_RECT.position.x, LABEL_RECT.position.x + LABEL_RECT.size.x, 2):
				var c := img.get_pixel(x, y)
				var l := c.r + c.g + c.b
				if l > ll:
					ll = l
					lb = c
		print("  label  = ", _hex(lb))
	get_tree().quit()


func _hex(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
