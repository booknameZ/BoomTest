extends Node
## Sfx - 程序化音效（无外部资源）。生成 16bit PCM 单声道波形并播放。
##
## 音频稳定性策略（针对小米 HyperOS / Android 16 的 OpenSL 崩溃）：
## 官方 Godot 4.7 Android 音频后端只有 OpenSL ES，无 AAudio。崩溃栈
## `libwilhelm.so AudioTrackCallback::onMoreData` 是 OpenSL 音频回调里
## 访问了已释放的短生命周期 stream（use-after-free）所致。
## 因此本类采用「常驻预生成播放器池」：所有音效在启动时一次性生成 stream，
## 每个 stream 绑定固定播放器，播放时仅轮询复用，**永不替换 stream、永不释放播放器**，
## 从根上消除 OpenSL 层 use-after-free 的可能。

const RATE := 44100
const DISTORT := 0.55  # 全局失真强度（软削波 + 位深压缩）
const MUTE := false    # 诊断开关：true 时完全不创建/播放任何音频（真静音，用于定位崩溃根因）

enum Wave { SINE, SQUARE, SAW, TRIANGLE, NOISE }

var _bgm_player: AudioStreamPlayer
var _bgm_volume := 0.6
var _sfx_volume := 1.0

# 常驻音效池：name -> Array[AudioStreamPlayer]（每个播放器固定绑定一个预生成 stream）
var _sfx_players: Dictionary = {}
# 每个音效名对应的轮询指针
var _sfx_idx: Dictionary = {}


func _ready() -> void:
	if MUTE:
		# 真静音诊断：不创建 BGM 播放器、不注册音效池，彻底不触碰音频播放。
		return
	# 程序化 BGM（暗黑氛围循环，常驻播放器，永不释放）
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)
	_bgm_player.stream = _make_bgm()
	_bgm_player.finished.connect(_bgm_finished)
	_bgm_player.play()
	set_bgm_volume(_bgm_volume)
	set_sfx_volume(_sfx_volume)
	_build_pool()


## BGM 播完后手动重播（避免 OpenSL 对 LOOP_FORWARD 循环 mix 的潜在崩溃）。
func _bgm_finished() -> void:
	if _bgm_player != null:
		_bgm_player.play()


## 设置音量（线性 0..1）。BGM 预留 6dB 余量避免过响。
func set_bgm_volume(v: float) -> void:
	_bgm_volume = clampf(v, 0.0, 1.0)
	if _bgm_player != null:
		_bgm_player.volume_db = _to_db(_bgm_volume, 6.0)


func set_sfx_volume(v: float) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)


func _to_db(v: float, headroom: float) -> float:
	if v <= 0.0001:
		return -80.0
	return linear_to_db(v) - headroom


# ==================== 常驻播放器池 ====================
## 注册一个音效：共享同一个预生成 stream，绑定 copies 个常驻播放器。
func _reg(name: String, stream: AudioStreamWAV, copies: int = 2) -> void:
	var players: Array[AudioStreamPlayer] = []
	for i in copies:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.stream = stream
		add_child(p)
		players.append(p)
	_sfx_players[name] = players
	_sfx_idx[name] = 0


## 播放指定音效（轮询复用常驻播放器，不替换 stream、不释放）。
func _play(name: String) -> void:
	if MUTE:
		return
	if _sfx_volume <= 0.0001:
		return
	if not _sfx_players.has(name):
		return
	var players: Array = _sfx_players[name]
	var n: int = players.size()
	var idx: int = int(_sfx_idx[name])
	var p: AudioStreamPlayer = players[idx]
	_sfx_idx[name] = (idx + 1) % n
	p.volume_db = _to_db(_sfx_volume, 0.0)
	p.play()


func _build_pool() -> void:
	# 固定音效
	_reg("bounce", _tone(560.0, 0.09, 0.16, 400.0, Wave.SINE))
	_reg("brick", _tone(250.0, 0.12, 0.12, 180.0, Wave.SQUARE))
	_reg("heartbeat", _tone(70.0, 0.12, 0.26, 40.0, Wave.SINE))
	_reg("detonate_warn", _tone(400.0, 0.7, 0.2, 1600.0, Wave.SQUARE))
	_reg("detonate_tick", _tone(1200.0, 0.06, 0.16, 900.0, Wave.SQUARE))
	_reg("retract", _tone(380.0, 0.1, 0.10, 250.0, Wave.SINE))
	_reg("charge", _tone(120.0, 0.25, 0.28, 720.0, Wave.TRIANGLE))
	# 爆炸（两层）
	_reg("explosion_noise", _tone(0.0, 0.55, 0.55, 0.0, Wave.NOISE))
	_reg("explosion_sine", _tone(100.0, 0.5, 0.35, 25.0, Wave.SINE))
	# 发射（四层）
	_reg("launch_boom", _tone(110.0, 0.42, 0.55, 32.0, Wave.SINE))
	_reg("launch_noise", _tone(0.0, 0.22, 0.42, 0.0, Wave.NOISE))
	_reg("launch_swish", _tone(280.0, 0.32, 0.24, 1500.0, Wave.SAW))
	_reg("launch_whistle", _tone(900.0, 0.24, 0.13, 2600.0, Wave.TRIANGLE))
	# 斩杀线（两层）
	_reg("kill_line_sq", _tone(220.0, 0.3, 0.22, 160.0, Wave.SQUARE))
	_reg("kill_line_saw", _tone(180.0, 0.25, 0.18, 120.0, Wave.SAW))
	# 破碎（连击 0..3 档）
	for c in 4:
		var f := 900.0 + c * 150.0
		_reg("break_ore_%d" % c, _tone(f, 0.12, 0.18, f * 1.7, Wave.TRIANGLE))
	# 宝石（数量 1..3 档）
	for cnt in range(1, 4):
		var f := 800.0 + cnt * 60.0
		_reg("gem_%d" % cnt, _tone(f, 0.08, 0.10, f * 1.8, Wave.SINE))
	# 能量满（漏斗攒满，下一发触发老虎机抽奖）
	_reg("energy_full", _tone(660.0, 0.35, 0.3, 1320.0, Wave.TRIANGLE))
	# 过关清屏（四个上升音）
	var clear_freqs := [523.0, 659.0, 784.0, 1046.0]
	for i in clear_freqs.size():
		var f: float = clear_freqs[i]
		_reg("clear_%d" % i, _tone(f, 0.18, 0.16, f * 1.05, Wave.TRIANGLE))


# ==================== 公开音效接口（对外签名不变） ====================
func bounce() -> void:
	_play("bounce")


func brick() -> void:
	_play("brick")


func break_ore(chain: int = 0) -> void:
	_play("break_ore_%d" % clampi(chain, 0, 3))


func gem(count: int = 1) -> void:
	_play("gem_%d" % clampi(count, 1, 3))


func energy_full() -> void:
	_play("energy_full")


func explosion() -> void:
	_play("explosion_noise")
	_play("explosion_sine")


func heartbeat() -> void:
	_play("heartbeat")


func launch() -> void:
	_play("launch_boom")
	_play("launch_noise")
	_play("launch_swish")
	_play("launch_whistle")


func detonate_warn() -> void:
	_play("detonate_warn")


func detonate_tick() -> void:
	_play("detonate_tick")


func retract() -> void:
	_play("retract")


func charge() -> void:
	_play("charge")


func kill_line() -> void:
	_play("kill_line_sq")
	_play("kill_line_saw")


func level_clear() -> void:
	for i in 4:
		get_tree().create_timer(i * 0.08).timeout.connect(func() -> void:
			_play("clear_%d" % i))


# ==================== 波形生成 ====================
func _tone(freq: float, dur: float, vol: float, slide_to: float, wave: int) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := freq
		if slide_to > 0.0:
			f = lerpf(freq, slide_to, t / dur)
		var v := _sample(wave, phase, t)
		v = _distort(v, DISTORT)
		var env := 1.0 - t / dur
		var s := int(clampf(v * vol * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
		phase += f / RATE
		if phase > 1.0:
			phase -= 1.0
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


func _sample(wave: int, phase: float, _t: float) -> float:
	match wave:
		Wave.SQUARE:
			return 1.0 if phase < 0.5 else -1.0
		Wave.SAW:
			return phase * 2.0 - 1.0
		Wave.TRIANGLE:
			return 1.0 - abs(phase * 4.0 - 2.0)
		Wave.NOISE:
			return randf() * 2.0 - 1.0
		_:
			return sin(phase * TAU)


func _distort(v: float, amount: float) -> float:
	if amount <= 0.0:
		return v
	# 软削波（tanh 过载）+ 位深压缩（lo-fi 失真）
	var drive := 1.0 + amount * 6.0
	v = tanh(v * drive) / tanh(drive)
	var levels := int(lerpf(64.0, 12.0, amount))
	return roundf(v * levels) / levels


# ==================== 程序化 BGM ====================
func _make_bgm() -> AudioStreamWAV:
	var dur := 4.0
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := _bgm_sample(t)
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	# 不使用 LOOP_FORWARD，改由 finished 信号手动重播（规避 OpenSL 循环 mix 崩溃）
	return wav


func _hash_noise(x: int) -> float:
	# 确定性伪随机（xorshift32），保证 4s 循环内噪声无缝重复
	var v := x & 0xffffffff
	v ^= v << 13
	v ^= v >> 17
	v ^= v << 5
	v &= 0xffffffff
	return float(v) / 4294967295.0 * 2.0 - 1.0


func _bgm_sample(t: float) -> float:
	# 180 BPM 快节奏 + 诡异（失谐 drone + 三全音 + 半音下行 bass）
	var bpm := 180.0
	var beat := 60.0 / bpm        # 0.333s 一拍
	var bt := fmod(t, beat)       # 拍内时间
	var s8 := beat * 0.5          # 八分音符
	var s8t := fmod(t, s8)
	var s8_i := int(fmod(t, 4.0) / s8)  # 0..23

	var out := 0.0

	# 快 kick：每拍低频脉冲
	var kick_env := exp(-bt * 48.0)
	out += sin(t * TAU * 50.0) * kick_env * 0.5

	# 快 hi-hat：每八分高频噪声
	var hat_env := exp(-s8t * 90.0)
	out += _hash_noise(int(t * RATE)) * hat_env * 0.13

	# 诡异 bass：半音下行八分音符方波（A2 → A1，混入三全音）
	var bass_notes: Array[float] = [
		110.0, 103.83, 110.0, 98.0, 92.5, 98.0, 87.31, 92.5,
		82.41, 87.31, 77.78, 82.41, 73.42, 77.78, 69.30, 73.42,
		65.41, 69.30, 61.74, 65.41, 58.27, 61.74, 55.0, 58.27,
	]
	var bf: float = bass_notes[s8_i]
	var sq := 1.0 if fmod(s8t * bf, 1.0) < 0.5 else -1.0
	var benv := (1.0 - exp(-s8t * 60.0)) * exp(-s8t * 9.0)
	out += sq * benv * 0.16

	# 诡异 drone：失谐低音 + LFO（55/55.5Hz 均 4s 整数周期）
	var drone := sin(t * TAU * 55.0) * 0.10 + sin(t * TAU * 55.5) * 0.08
	var lfo := 0.7 + 0.3 * sin(t * TAU * 0.25)
	out += drone * lfo

	# 三全音 lead：每两拍一个短促高音（魔鬼音程）
	var lead_t := fmod(t, beat * 2.0)
	var lead_env := (1.0 - exp(-lead_t * 80.0)) * exp(-lead_t * 6.0)
	out += sin(t * TAU * 155.5) * lead_env * 0.06

	return _distort(out, 0.6)
