extends Node2D

# --- 常數與設定 ---
const BOARD_SIZE = 6 # 棋盤
const PIECE_SCENE = preload("res://Piece.tscn") 
const GRID_STEP = 56.5 # 棋子位置
@onready var CENTER_POS = get_viewport_rect().size / 2

# --- 遊戲變數 ---
var board = [] 
var current_player = 1 # 1: 黑色 (先手) 
var turn_in_round = 0  # 2: 白色 (後手)
var is_animating = false
var game_over = false 

# --- 新增：勝利計數變數 ---
var black_win_count = 0 # 黑方達成四子的次數 讓白色在黑色四子後還能再下一子

# 之後放勝利ui用
@onready var board_container = $BoardContainer
@onready var piece_container = $PieceContainer

func _ready():
	# 初始化棋盤位置與資料
	board_container.position = CENTER_POS
	piece_container.position = CENTER_POS
	setup_board_data()

# 初始化/重置陣列資料：建立 6x6 的二維陣列
func setup_board_data():
	board = []
	for x in range(BOARD_SIZE):
		var col = []
		for y in range(BOARD_SIZE):
			col.append(0)
		board.append(col)

func _input(event):
	# 動畫中不接受輸入
	if is_animating: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 如果遊戲結束，點擊後重置
		if game_over:
			reset_game()
			return
			
		# 計算點擊的欄位
		var local_pos = piece_container.to_local(event.global_position)
		var col = int(floor((local_pos.x + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
		
		if col >= 0 and col < BOARD_SIZE:
			drop_piece(col)

# 放置棋子邏輯
func drop_piece(col):
	for row in range(BOARD_SIZE - 1, -1, -1):
		if board[col][row] == 0:
			board[col][row] = current_player
			play_drop_animation(col, row, current_player)
			
			# 每一步下子後都檢查一次勝負（包含黑方的第一次得分）
			if check_winner():
				return 
				
			next_turn()
			return

# 播放棋子下落動畫
func play_drop_animation(col, row, player, start_y_offset = -400):
	var p = PIECE_SCENE.instantiate()
	piece_container.add_child(p)
	p.set_piece_type(player)
	var target_x = (col - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var target_y = (row - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	p.position = Vector2(target_x, start_y_offset)
	var tween = create_tween()
	tween.tween_property(p, "position:y", target_y, 0.4).set_trans(Tween.TRANS_BOUNCE)

# 切換回合與處理旋轉時機
func next_turn():
	turn_in_round += 1
	current_player = 2 if current_player == 1 else 1
	
	# 雙方都下一子後進行旋轉
	if turn_in_round >= 2:
		turn_in_round = 0
		start_rotation_sequence()

# 旋轉流程：計算新陣列並執行旋轉動畫
func start_rotation_sequence():
	is_animating = true
	await get_tree().create_timer(0.5).timeout
	
	# 旋轉矩陣資料 (順時針 90 度)
	var new_board = []
	for i in range(BOARD_SIZE):
		new_board.append([])
		for j in range(BOARD_SIZE): new_board[i].append(0)
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			new_board[BOARD_SIZE - 1 - y][x] = board[x][y]
	board = new_board

	# 執行視覺旋轉動畫
	var tween = create_tween().set_parallel(true)
	var target_rot = board_container.rotation + deg_to_rad(90)
	tween.tween_property(board_container, "rotation", target_rot, 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	for child in piece_container.get_children():
		var old_pos = child.position
		var new_pos = Vector2(-old_pos.y, old_pos.x) 
		tween.tween_property(child, "position", new_pos, 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	
	await tween.finished
	await get_tree().create_timer(0.5).timeout
	apply_gravity_and_animate()

# 重力下落：旋轉後讓棋子掉到底部
func apply_gravity_and_animate():
	var pre_gravity_board = []
	for x in range(BOARD_SIZE):
		pre_gravity_board.append(board[x].duplicate())

	# 計算下落後的數據
	for x in range(BOARD_SIZE):
		var pieces = []
		for y in range(BOARD_SIZE):
			if board[x][y] != 0:
				pieces.append(board[x][y])
				board[x][y] = 0
		for i in range(pieces.size()):
			board[x][BOARD_SIZE - 1 - i] = pieces[pieces.size() - 1 - i]
	
	# 重繪棋子節點以對齊重力
	for child in piece_container.get_children():
		child.queue_free()
	await get_tree().process_frame
	
	var final_tween = create_tween().set_parallel(true)
	for x in range(BOARD_SIZE):
		var original_y_positions = []
		for y in range(BOARD_SIZE):
			if pre_gravity_board[x][y] != 0:
				original_y_positions.append((y - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP)

		var current_p_count = 0
		for y in range(BOARD_SIZE):
			if board[x][y] != 0:
				var p = PIECE_SCENE.instantiate()
				piece_container.add_child(p)
				p.set_piece_type(board[x][y])
				var final_x = (x - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
				var final_y = (y - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
				p.position = Vector2(final_x, original_y_positions[current_p_count])
				final_tween.tween_property(p, "position:y", final_y, 0.5).set_trans(Tween.TRANS_BOUNCE)
				current_p_count += 1
	
	await final_tween.finished
	
	# 旋轉且掉落後，再次檢查勝負（黑方若此時也達成四子，會算第二次）
	check_winner()
	is_animating = false

# 核心邏輯：檢查勝負
func check_winner() -> bool:
	var b_reached_four = check_logic(1) # 檢查黑方目前是否達成四子
	var w_reached_four = check_logic(2) # 檢查白方目前是否達成四子
	
	# 白方勝利條件：達成一次四子即獲勝
	if w_reached_four:
		game_over = true
		show_result("WHITE WINS!")
		return true

	# 黑方勝利條件：需達成兩次四子
	if b_reached_four:
		black_win_count += 1
		# print("Black reached 4-in-a-row! Current count: ", black_win_count) 顯示黑色還差幾條線
		
		if black_win_count >= 2:
			game_over = true
			show_result("BLACK WINS!")
			return true
		else:
			# 提示白色剩一次機會（可加入特效）
			print("last chance!")

	# 檢查平局 (棋盤最頂端是否已滿)
	var is_full = true
	for x in range(BOARD_SIZE):
		if board[x][0] == 0: is_full = false
	if is_full:
		game_over = true
		show_result("DRAW")
		return true
		
	return false

# 顯示勝負結果
func show_result(text):
	print(text)

# 重製遊戲：恢復所有變數與視覺狀態
func reset_game():
	print("Resetting game...")
	game_over = false
	current_player = 1
	turn_in_round = 0
	is_animating = false
	black_win_count = 0 # 重置黑方得分
	
	setup_board_data()
	for child in piece_container.get_children():
		child.queue_free()
		
	var tween = create_tween()
	tween.tween_property(board_container, "rotation", 0, 0.5).set_trans(Tween.TRANS_SINE)

# 掃描整個棋盤檢查特定玩家是否連線
func check_logic(p_id):
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			if board[x][y] == p_id:
				# 檢查四個方向：水平、垂直、兩條斜線
				if check_dir(x,y,1,0,p_id) or check_dir(x,y,0,1,p_id) or check_dir(x,y,1,1,p_id) or check_dir(x,y,1,-1,p_id):
					return true
	return false

# 檢查單一方向是否連續四顆
func check_dir(x, y, dx, dy, p_id):
	var count = 0
	for i in range(4):
		var nx = x + dx * i
		var ny = y + dy * i
		if nx >= 0 and nx < BOARD_SIZE and ny >= 0 and ny < BOARD_SIZE:
			if board[nx][ny] == p_id: count += 1
			else: break
		else: break
	return count == 4
