extends Node
## 截图辅助启动器：实例化主场景 → 自动开始游戏 →（可选）强制触发老虎机 → 到帧退出。
## 仅用于 headless/Movie Maker 模式自查画面，不进入版本流程。
## 参数通过场景文件里的 exported 变量配置。

var main: Node3D
var _frames := 0

## 进入对局的帧号
@export var start_frame := 5
## 强制触发老虎机的帧号（<0 表示不触发）
@export var slot_frame := -1
## 总帧数：到达后退出
@export var end_frame := 24


func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == start_frame and main != null:
		# 直接调用开始回调，跳过菜单（等价于点击 START）
		main._on_start_game()
	if _frames == slot_frame and main != null:
		main._start_slot(0.6)
	if _frames >= end_frame:
		get_tree().quit()
