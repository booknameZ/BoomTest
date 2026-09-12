extends Node
## 无头冒烟测试：完整跑通「开局 → 老虎机抽奖 → 收回 → 手动发射 → 回收」循环 N 轮，
## 校验状态机与球种消耗逻辑，检测运行时错误。Godot headless 运行：
##   Godot --path . res://scenes/_smoke.tscn --quit-after 600

const CYCLES := 5

var main: Node3D
var _fails: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._on_start_game()
	_check(main.state == 0, "开局后应处于 IDLE")
	for i in CYCLES:
		_cycle(i)
	# 结算断言
	if _fails.is_empty():
		print("SMOKE PASS (%d cycles)" % CYCLES)
	else:
		for f in _fails:
			print("SMOKE FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _cycle(i: int) -> void:
	# 1. 强制池满触发老虎机
	main.energy = main.ENERGY_FULL
	main._launch(0.6)
	_check(main.state == 9, "cycle %d: 池满后应进入 SLOT(9)，实际 %d" % [i, main.state])
	# 2. 快进到展示结束 → 收回 + 球回原点
	main._slot_timer = 4.3
	main._update_slot(0.016)
	_check(main.state == 0, "cycle %d: 抽完后应回到 IDLE，实际 %d" % [i, main.state])
	_check(main.ball.pos == main.BALL_START, "cycle %d: 球应回原点" % i)
	_check(main.energy == 0.0, "cycle %d: 能量池应清空" % i)
	# 3. 玩家手动发射 → 奖励球种在此刻消耗
	var kind_before: int = main.current_ball_kind
	main._launch(0.5)
	_check(main.state == 1, "cycle %d: 手动发射后应 FLYING，实际 %d" % [i, main.state])
	if kind_before != 0:
		_check(main.next_ball_kind == 0,
			"cycle %d: 发射后奖励球种应消耗为 NORMAL，实际 %d" % [i, main.next_ball_kind])
	# 4. 飞行若干帧（锻炼碰撞/矿石破碎/粒子路径）
	for f in 30:
		main._update_ball(0.016)
	# 5. 收球结束本轮
	main._reset_ball()
	_check(main.state == 0, "cycle %d: 收球后应 IDLE" % i)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)
