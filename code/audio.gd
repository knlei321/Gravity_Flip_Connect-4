extends Node

const SAMPLE_RATE := 44100.0

# 落子 / 旋轉後重力落地：敲木門聲（阻尼振盪器）
# 原理：衰減正弦波模擬門板振動，極短雜訊模擬指節衝擊
# Karplus-Strong 是撥弦算法，所以改成這種做法
func play_drop() -> void:
	var dur := 0.40
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedVector2Array()
	buf.resize(n)

	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		# 指節撞擊：極短雜訊爆衝
		var noise := randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.50 # 300
		# 高頻敲擊感（150ms 內消失）
		var click := sin(TAU * 100.0 * t) * exp(-t * 60.0) * 0.28 # 820
		# 低頻主體共鳴：門板振動（約 0.15s 衰減）
		var thud1 := sin(TAU * 100.0 * t) * exp(-t * 20.0) * 0.68 # 100
		# 次諧波（增加厚度）
		var thud2 := sin(TAU * 100.0 * t) * exp(-t * 28.0) * 0.38 # 235.0 
		var s     := (noise + click + thud1 + thud2) * 0.38
		buf[i]     = Vector2(s, s)

	_spawn_player(buf, dur)

# 落子倒放：棋子上升音效
func play_drop_reverse() -> void:
	var dur := 0.40
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedVector2Array()
	buf.resize(n)

	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var noise := randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.50
		var click := sin(TAU * 100.0 * t) * exp(-t * 60.0) * 0.28
		var thud1 := sin(TAU * 100.0 * t) * exp(-t * 20.0) * 0.68
		var thud2 := sin(TAU * 100.0 * t) * exp(-t * 28.0) * 0.38
		buf[i]     = Vector2((noise + click + thud1 + thud2) * 0.38, (noise + click + thud1 + thud2) * 0.38)

	buf.reverse()
	_spawn_player(buf, dur)

# 旋轉：木頭滾動聲
# 用阻尼振盪器生成單個叩擊 impulse，再依 ease-in-out 速度散佈
func play_rotation(dur: float = 0.88) -> void:
	var n := int(SAMPLE_RATE * dur)
	var buf := PackedVector2Array()
	buf.resize(n)

	# 單個短叩擊 impulse（阻尼振盪器版本）
	var imp_dur  := 0.07
	var imp_n    := int(SAMPLE_RATE * imp_dur)
	var imp_data := PackedFloat32Array()
	imp_data.resize(imp_n)
	for i in range(imp_n):
		var t        := float(i) / SAMPLE_RATE
		var noise    := randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.45
		var click    := sin(TAU * 750.0 * t) * exp(-t * 75.0) * 0.25
		var thud     := sin(TAU * 160.0 * t) * exp(-t * 30.0) * 0.60
		imp_data[i]  = (noise + click + thud) * 0.42

	# 以 ease-in-out 速度剖面散佈敲擊事件
	var t_cur := 0.02
	while t_cur < dur - 0.06:
		var speed     := sin(PI * t_cur / dur)
		var amp       := 0.25 + 0.38 * speed
		var start_idx := int(t_cur * SAMPLE_RATE)
		for j in range(imp_n):
			var idx := start_idx + j
			if idx < n:
				var s := imp_data[j] * amp
				buf[idx] = Vector2(buf[idx].x + s, buf[idx].y + s)
		t_cur += lerp(0.19, 0.055, speed)

	_spawn_player(buf, dur)

# 長按空白鍵震動音效：低頻雜訊 + 低頻正弦，振幅隨時間漸增
var _rumble_player: AudioStreamPlayer = null

func start_rumble() -> void:
	stop_rumble()
	var dur := 2.5
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedVector2Array()
	buf.resize(n)

	# 與旋轉相似的短木頭叩擊 impulse
	var imp_dur  := 0.07
	var imp_n    := int(SAMPLE_RATE * imp_dur)
	var imp_data := PackedFloat32Array()
	imp_data.resize(imp_n)
	for i in range(imp_n):
		var t        := float(i) / SAMPLE_RATE
		var noise    := randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.45
		var click    := sin(TAU * 750.0 * t) * exp(-t * 75.0) * 0.25
		var thud     := sin(TAU * 160.0 * t) * exp(-t * 30.0) * 0.60
		imp_data[i]  = (noise + click + thud) * 0.42

	# 叩擊間距從 0.28s 縮短到 0.05s，振幅同步增大
	var t_cur := 0.0
	while t_cur < dur - 0.06:
		var progress  := minf(t_cur / 2.0, 1.0)
		var amp       := 0.15 + 0.45 * progress
		var start_idx := int(t_cur * SAMPLE_RATE)
		for j in range(imp_n):
			var idx := start_idx + j
			if idx < n:
				var s := imp_data[j] * amp
				buf[idx] = Vector2(buf[idx].x + s, buf[idx].y + s)
		t_cur += lerp(0.10, 0.05, progress)

	var stream          := AudioStreamGenerator.new()
	stream.mix_rate      = SAMPLE_RATE
	stream.buffer_length = dur + 0.2
	_rumble_player        = AudioStreamPlayer.new()
	_rumble_player.stream = stream
	add_child(_rumble_player)
	_rumble_player.play()
	await get_tree().process_frame
	if not is_instance_valid(_rumble_player):
		return
	var pb := _rumble_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb:
		pb.push_buffer(buf)

func stop_rumble() -> void:
	if is_instance_valid(_rumble_player):
		_rumble_player.queue_free()
	_rumble_player = null

# 勝利琶音：C5 E5 G5 C6
func play_win() -> void:
	# 兩記短促有力的撞擊音「登－登」
	# 調整點：FREQS 換音高，STARTS[1] 調兩音間距，DECAY 調衰減速度
	var FREQS  : Array = [392.0,  523.25]  # G4, C5（可換音高）
	var STARTS : Array = [0.0,    0.26 ]   # 第二音起點（秒），越小越緊湊
	var DECAY  : Array = [8.0,    5.5  ]   # 衰減速率，越大越短促
	var total  : float = STARTS[1] + 0.55
	var n      := int(SAMPLE_RATE * total)
	var buf    := PackedVector2Array()
	buf.resize(n)

	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		for ni in range(2):
			var t0   : float = STARTS[ni]
			var freq : float = FREQS[ni]
			var dc   : float = DECAY[ni]
			if t >= t0:
				var nt  := t - t0
				var env := exp(-nt * dc)
				# 打擊瞬態
				s += randf_range(-1.0, 1.0) * exp(-nt * 120.0) * 0.10
				# 主音 + 泛音（brass 質感）
				s += sin(TAU * freq * nt) * env * 0.50
				s += sin(TAU * freq * 2.0 * nt) * env * 0.26
				s += sin(TAU * freq * 3.0 * nt) * env * 0.10
				s += sin(TAU * freq * 4.0 * nt) * env * 0.04
		buf[i] = Vector2(s * 0.38, s * 0.38)

	_spawn_player(buf, total)

func _spawn_player(buf: PackedVector2Array, dur: float) -> void:
	var stream          := AudioStreamGenerator.new()
	stream.mix_rate      = SAMPLE_RATE
	stream.buffer_length = dur + 0.2
	var player          := AudioStreamPlayer.new()
	player.stream        = stream
	add_child(player)
	player.play()
	await get_tree().process_frame
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb:
		pb.push_buffer(buf)
	await get_tree().create_timer(dur + 0.15).timeout
	if is_instance_valid(player):
		player.queue_free()
