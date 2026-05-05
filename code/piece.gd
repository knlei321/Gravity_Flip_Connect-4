extends Sprite2D

# 註解：預載入兩張圖片資源
var black_tex = preload("res://art/black_piece.png")
var white_tex = preload("res://art/white_piece.png")

# 註解：初始化棋子類型
func set_piece_type(player_id):
	if player_id == 1: # 假設 1 是黑方 (先手)
		texture = black_tex
	else: # 2 是白方
		texture = white_tex
