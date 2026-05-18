extends Sprite2D

var black_tex = preload("res://art/black_piece.png")
var white_tex = preload("res://art/white_piece.png")
var player_id = 0  # 記錄此棋子屬於哪方（1=黑，2=白）
var _glow_tween: Tween = null  # 儲存勝利閃爍的 tween，方便 undo 時停止

func set_piece_type(pid):
	player_id = pid
	if pid == 1:
		texture = black_tex
	else:
		texture = white_tex

func start_glow():
	# 勝利時呼叫：
	var glow_color = Color(2.048, 1.982, 0.526, 1.0) if player_id == 1 else Color(1.461, 0.568, 0.0, 1.0)
	# Color(2.048, 0.531, 0.041, 1.0) 白色方
	# Color(1.579, 0.617, 0.0, 1.0) 白色方
	# Color(2.048, 1.982, 0.526, 1.0) 黑色方
	# Color(0.3, 0.85, 1.0, 1.0)      黑色方
	_glow_tween = create_tween().set_loops()  # 改用 _glow_tween 追蹤，方便外部停止
	_glow_tween.tween_property(self, "modulate", glow_color, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(self, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func stop_glow():  # undo 時呼叫，停止勝利閃爍並還原顏色
	if _glow_tween:
		_glow_tween.kill()  # 強制停止 tween
		_glow_tween = null
	modulate = Color.WHITE  # 還原為正常顏色
