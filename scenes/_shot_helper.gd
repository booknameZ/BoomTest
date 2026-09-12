extends Node
## 可靠截屏辅助：实例化主场景 → 自动开始游戏 → 在指定帧 viewport 同步 readback 存 PNG。
## 与 _smoke.gd 保持一致：全部逻辑写在 _ready() 里，用 await process_frame 推进帧，
## 避免依赖 _process() 在 headless 下的不确定性。

@export var start_frame := 5
@export var slot_frame := -1
@export var shots: Dictionary = {}
@export var cursor_pos := Vector2(640, 360)


func _ready() -> void:
	await get_tree().process_frame
	var main: Main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# 让 main._ready() 完整执行完
	await get_tree().process_frame
	await get_tree().process_frame

	# 固定 RNG，让矿石阵列、颜色分布截图可复现，便于与参考图逐元素对比
	seed(2026_09_11)

	# 进入游戏并摆成参考图的“待机/初始”状态
	main._on_start_game()
	# 让 HUD 显示参考图同款数值（_update_hud 每帧会覆盖 set_score，所以直接改 target_score）
	main.target_score = 50
	main.hud.set_level(1)
	main.hud.set_hearts(3, 3)
	main.hud.set_power(1.0, true)
	main.hud.hide_multiplier()
	main.hud.set_combo(0)
	main.hud.set_energy(0.0, 1.0)
	# 隐藏准星：pointer_active=false 让 _update_crosshair 不会重新打开它
	main.pointer_active = false
	if main.crosshair != null:
		main.crosshair.set_reticle_visible(false)

	# 显示参考图同款虚线弹道（不进入 charging，保持蓝球颜色）
	main.aim_forced = true
	var ball_screen := main._world_to_screen(main.BALL_START)
	var aim_pts := PackedVector2Array()
	for i in range(14):
		var t := float(i) / 13.0
		aim_pts.append(ball_screen + Vector2(0, t * 360))
	main.aim_line.show_aim(aim_pts)

	# 隐藏斩杀线（参考图未显示这条线）
	main._kill_line_node.visible = false
	main._kill_line_glow.visible = false

	# 推进若干帧，确保 3D 场景与 HUD 都渲染完成
	for i in range(8):
		await get_tree().process_frame

	var max_frame := start_frame
	for k in shots.keys():
		max_frame = maxi(max_frame, int(k))

	for i in range(1, max_frame + 1):
		await get_tree().process_frame
		if shots.has(i):
			_before_shot(main, shots[i])
			await get_tree().process_frame
			await get_tree().process_frame
			await _shoot(shots[i])

	print("SHOT_DONE")
	get_tree().quit(0)


## 根据截图文件名切换场景状态：collapsed / charging（显示方形瞄准镜） / slot（老虎机弹出）
func _before_shot(main: Main, fname: String) -> void:
	if fname.contains("charge") or fname.contains("scope") or fname.contains("cursor"):
		# 让系统光标指向固定位置，主场景 _update_crosshair 会据此绘制方形瞄准镜
		Input.warp_mouse(cursor_pos)
		main.pointer_active = true
		main._cursor_hidden = true
		main._set_cursor_hidden(true)
		main.aim_forced = true
		main.state = main.State.IDLE
		main.charging = true
		main.power = 0.65
	elif fname.contains("slot"):
		main.pointer_active = false
		if main.crosshair != null:
			main.crosshair.set_reticle_visible(false)
		main._set_cursor_hidden(true)
		main._start_slot(0.6)
	elif fname.contains("arena"):
		# 已铺满矿石的对局画面：显示方形瞄准镜 + 蓄力弹道，呈现参考图同款局内状态
		Input.warp_mouse(cursor_pos)
		main.pointer_active = true
		main._cursor_hidden = true
		main._set_cursor_hidden(true)
		main.aim_forced = true
		main.state = main.State.IDLE
	else:
		# 默认：隐藏准星，显示待机弹道
		main.pointer_active = false
		if main.crosshair != null:
			main.crosshair.set_reticle_visible(false)
		main._set_cursor_hidden(true)
		main.aim_forced = true


func _shoot(fname: String) -> void:
	# headless 下 RenderingServer.frame_post_draw 不会触发，所以用 process_frame 推进
	await get_tree().process_frame
	await get_tree().process_frame
	# slot 截图：等白闪结束、机匣弹出并滚动到中段再 capture
	if fname.contains("slot"):
		for i in range(45):
			await get_tree().process_frame
	var vp := get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("ERROR: viewport texture null for ", fname)
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		print("ERROR: viewport image empty for ", fname)
		return
	var dir := DirAccess.open("res://")
	if dir == null:
		print("ERROR: cannot open res://")
		return
	if not dir.dir_exists("preview"):
		var mkerr := dir.make_dir("preview")
		if mkerr != OK:
			print("ERROR: cannot create preview dir: ", mkerr)
			return
	var err := img.save_png("res://preview/" + fname)
	if err != OK:
		print("ERROR saving ", fname, " code ", err)
	else:
		print("saved preview/", fname)
