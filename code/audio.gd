extends Node

const SAMPLE_RATE := 44100.0

# 高頻音效的波形快取：即時生成一次後重複使用，避免每次播放都在主執行緒重算上萬個樣本
var _drop_bufs:     Array               = []  # 3 個隨機變體，保留落子聲的細微變化
var _hover_buf:     PackedVector2Array  = PackedVector2Array()
var _reverse_buf:   PackedVector2Array  = PackedVector2Array()
var _rotation_bufs: Dictionary          = {}  # dur → buffer（play_rotation 有多種時長）

# 落子 / 旋轉後重力落地：敲木門聲（阻尼振盪器）
# 原理：衰減正弦波模擬門板振動，極短雜訊模擬指節衝擊
# Karplus-Strong 是撥弦算法，所以改成這種做法
func _make_drop_buf() -> PackedVector2Array:
	var n   := int(SAMPLE_RATE * 0.40)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in range(n):
		var t     := float(i) / SAMPLE_RATE
		var noise := randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.50
		var click := sin(TAU * 100.0 * t) * exp(-t * 60.0)  * 0.28
		var thud1 := sin(TAU * 100.0 * t) * exp(-t * 20.0)  * 0.68
		var thud2 := sin(TAU * 100.0 * t) * exp(-t * 28.0)  * 0.38
		var s     := (noise + click + thud1 + thud2) * 0.38
		buf[i]     = Vector2(s, s)
	return buf

func play_drop() -> void:
	if _drop_bufs.is_empty():
		for _i in range(3):
			_drop_bufs.append(_make_drop_buf())
	_spawn_player(_drop_bufs[randi() % _drop_bufs.size()], 0.40)

# 滑鼠 hover 選項：輕版落子聲（振幅較小、衰減較快）
func play_hover() -> void:
	var dur := 0.20
	if _hover_buf.is_empty():
		var n   := int(SAMPLE_RATE * dur)
		var buf := PackedVector2Array()
		buf.resize(n)
		for i in range(n):
			var t     := float(i) / SAMPLE_RATE
			var noise := randf_range(-1.0, 1.0) * exp(-t * 350.0) * 0.35
			var click := sin(TAU * 200.0 * t) * exp(-t * 90.0)   * 0.20
			var thud  := sin(TAU * 140.0 * t) * exp(-t * 35.0)   * 0.45
			var s     := (noise + click + thud) * 0.40
			buf[i]     = Vector2(s, s)
		_hover_buf = buf
	_spawn_player(_hover_buf, dur)

# 縮回音效：較輕、音調稍高，有立即衝擊感
func play_drop_reverse() -> void:
	var dur := 0.30
	if _reverse_buf.is_empty():
		var n   := int(SAMPLE_RATE * dur)
		var buf := PackedVector2Array()
		buf.resize(n)
		for i in range(n):
			var t     := float(i) / SAMPLE_RATE
			var noise := randf_range(-1.0, 1.0) * exp(-t * 380.0) * 0.38
			var click := sin(TAU * 130.0 * t) * exp(-t * 75.0)   * 0.22
			var thud  := sin(TAU * 120.0 * t) * exp(-t * 26.0)   * 0.50
			var s     := (noise + click + thud) * 0.42
			buf[i]    = Vector2(s, s)
		_reverse_buf = buf
	_spawn_player(_reverse_buf, dur)

# 旋轉：木頭滾動聲
# 用阻尼振盪器生成單個叩擊 impulse，再依 ease-in-out 速度散佈
func play_rotation(dur: float = 0.88) -> void:
	if not _rotation_bufs.has(dur):
		_rotation_bufs[dur] = _make_rotation_buf(dur)
	_spawn_player(_rotation_bufs[dur], dur)

func _make_rotation_buf(dur: float) -> PackedVector2Array:
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

	return buf

# 勝利：兩記短促撞擊音「登－登」
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

# 平手：兩聲下行，衰減較慢，音量較輕——「就這樣結束了」的感覺
func play_draw() -> void:
	var FREQS  : Array = [440.0,  440.0 ]  # A4, A4
	var STARTS : Array = [0.0,    0.22  ]
	var DECAY  : Array = [5.5,    4.0   ]  # 比勝利衰減慢，帶拖尾
	var total  : float = STARTS[1] + 0.65
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
				s += randf_range(-1.0, 1.0) * exp(-nt * 120.0) * 0.08
				s += sin(TAU * freq * nt) * env * 0.45
				s += sin(TAU * freq * 2.0 * nt) * env * 0.20
				s += sin(TAU * freq * 3.0 * nt) * env * 0.07
				s += sin(TAU * freq * 4.0 * nt) * env * 0.02
		buf[i] = Vector2(s * 0.35, s * 0.35)

	_spawn_player(buf, total)

func _spawn_player(buf: PackedVector2Array, dur: float) -> void:
	var stream          := AudioStreamGenerator.new()
	stream.mix_rate      = SAMPLE_RATE
	stream.buffer_length = dur + 0.2
	var player          := AudioStreamPlayer.new()
	player.stream        = stream
	player.bus           = "SFX"
	add_child(player)
	player.play()
	await get_tree().process_frame
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb:
		pb.push_buffer(buf)
	await get_tree().create_timer(dur + 0.15).timeout
	if is_instance_valid(player):
		player.queue_free()
