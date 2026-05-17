extends Sprite2D

var black_tex = preload("res://art/black_piece.png")
var white_tex = preload("res://art/white_piece.png")
var player_id = 0  # 記錄此棋子屬於哪方（1=黑，2=白）

func set_piece_type(pid):
	player_id = pid
	if pid == 1:
		texture = black_tex
	else:
		texture = white_tex

func start_glow():
	# 勝利時呼叫：
	var glow_color = Color(2.05, 2.146, 0.53, 1.0) if player_id == 1 else Color(0.953, 0.671, 0.224, 1.0)
	# Color(0.3, 0.85, 1.0, 1.0)
	var tween = create_tween().set_loops()
	tween.tween_property(self, "modulate", glow_color, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
