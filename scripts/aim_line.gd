class_name AimLine
extends CanvasLayer
## 瞄准虚线：从球沿射击方向分布方块点，清晰指示发射方向。
## 放在 HUD 之上（layer=40），不受像素化后期影响。

class Dots extends Control:
	var pts: PackedVector2Array = PackedVector2Array()

	func _snap(v: float) -> float:
		return roundf(v)

	func _draw() -> void:
		for i in pts.size():
			var p := pts[i]
			var big := i % 3 == 0
			var s := 6.0 if big else 3.0
			var a := 0.95 if big else 0.55
			var c := Color(1.0, 0.85, 0.35, a)
			var x := _snap(p.x - s * 0.5)
			var y := _snap(p.y - s * 0.5)
			draw_rect(Rect2(Vector2(x, y), Vector2(s, s)), c, true)


var _dots: Dots


func _ready() -> void:
	layer = 40
	_dots = Dots.new()
	_dots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dots)
	_dots.visible = false


func show_aim(pts: PackedVector2Array) -> void:
	_dots.pts = pts
	_dots.queue_redraw()
	_dots.visible = true


func hide_aim() -> void:
	_dots.visible = false
