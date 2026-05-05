extends Node2D

# --- 常數與設定 ---
const BOARD_SIZE = 6 # 棋盤
const PIECE_SCENE = preload("res://Piece.tscn") 
const GRID_STEP = 56.5 # 棋子位置
@onready var CENTER_POS = get_viewport_rect().size / 2

# --- 遊戲變數 ---
var board = [] 
var current_player = 1 # 1: 黑色 (先手), 2: 白色 (後手) 
var turn_in_round = 0 # 紀錄目前是這一輪的第幾手 (0或1)
var is_animating = false
var game_over = false 

# --- 勝利計數變數 ---
var black_win_count = 0 # 黑方達成連線的計數

@onready var board_container = $BoardContainer
@onready var piece_container = $PieceContainer

func _ready():
	# 初始化棋盤
	board_container.position = CENTER_POS
	piece_container.position = CENTER_POS
	setup_board_data()

# 初始化/重置陣列資料
func setup_board_data():
	board = []
	for x in range(BOARD_SIZE):
		var col = []
		for y in range(BOARD_SIZE):
			col.append(0)
		board.append(col)

func _input(event):
	if is_animating: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if game_over:
			reset_game()
			return
			
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
			
			# 每一步下子後檢查勝負
			# 傳入當前是誰下子，用來判斷白方是否有「反超獲勝」的機會
			if check_winner_logic(false):
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

# 切換回合
func next_turn():
	turn_in_round += 1
	current_player = 2 if current_player == 1 else 1
	
	# 雙方都下一子後進行旋轉
	if turn_in_round >= 2:
		turn_in_round = 0
		start_rotation_sequence()

# 旋轉流程
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

	# 視覺旋轉動畫
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

# 處理重力掉落
func apply_gravity_and_animate():
	var pre_gravity_board = []
	for x in range(BOARD_SIZE):
		pre_gravity_board.append(board[x].duplicate())

	for x in range(BOARD_SIZE):
		var pieces = []
		for y in range(BOARD_SIZE):
			if board[x][y] != 0:
				pieces.append(board[x][y])
				board[x][y] = 0
		for i in range(pieces.size()):
			board[x][BOARD_SIZE - 1 - i] = pieces[pieces.size() - 1 - i]
	
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
	
	# 旋轉後檢查勝負
	check_winner_logic(true)
	is_animating = false

# 核心勝負判斷 (整合你的最新規則)
func check_winner_logic(after_rotation: bool) -> bool:
	var b_reached = check_logic(1) # 黑色連成四子
	var w_reached = check_logic(2) # 白色連成四子
	
	# 規則 A: 翻轉後同時達成四子 = 平手
	if after_rotation and b_reached and w_reached:
		game_over = true
		show_result("DRAW!")
		return true

	# 規則 B: 白色獲勝判定 (在落子階段或翻轉階段，白色只要達成即獲勝)
	# 這也包含了「黑色落子連四，但白色隨後落子也連四」的情況，因為白色在此處優先判定
	if w_reached:
		game_over = true
		show_result("WHITE WINS!")
		return true

	# 規則 C: 黑色獲勝判定
	if b_reached:
		if after_rotation:
			# 翻轉後黑色單獨達成直接贏
			game_over = true
			show_result("BLACK WINS!")
			return true
		else:
			# 落子階段黑色達成，需要累積計數 (等待白色最後一子)
			black_win_count += 1
			if black_win_count >= 2:
				game_over = true
				show_result("BLACK WINS!")
				return true
			else:
				print("last chance!")

	# 規則 D: 棋盤滿格判定
	var is_full = true
	for x in range(BOARD_SIZE):
		if board[x][0] == 0: is_full = false
	if is_full:
		game_over = true
		show_result("DRAW!")
		return true
		
	return false

func show_result(text):
	print(text)

func reset_game():
	print("Resetting game...")
	game_over = false
	current_player = 1
	turn_in_round = 0
	is_animating = false
	black_win_count = 0
	
	setup_board_data()
	for child in piece_container.get_children():
		child.queue_free()
		
	var tween = create_tween()
	tween.tween_property(board_container, "rotation", 0, 0.5).set_trans(Tween.TRANS_SINE)

# 掃描邏輯
func check_logic(p_id):
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			if board[x][y] == p_id:
				if check_dir(x,y,1,0,p_id) or check_dir(x,y,0,1,p_id) or check_dir(x,y,1,1,p_id) or check_dir(x,y,1,-1,p_id):
					return true
	return false

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