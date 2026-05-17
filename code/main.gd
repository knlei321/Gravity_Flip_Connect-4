extends Node2D

# --- 常數與設定 ---
const BOARD_SIZE = 6
const PIECE_SCENE = preload("res://Piece.tscn") 
const GRID_STEP = 111 # 棋子間距
@onready var CENTER_POS = get_viewport_rect().size / 2

# --- 遊戲變數 ---
var board = []
var pieces_grid = []  # pieces_grid[col][row] = Sprite2D node
var current_player = 1
var turn_in_round = 0
var is_animating = false
var game_over = false

# --- 勝負狀態旗標 ---
var black_pending_win = false  # 黑方已連四

@onready var background_container = $background # 背景節點
@onready var board_container = $BoardContainer  # 棋盤節點
@onready var piece_container = $PieceContainer  # 棋子節點
@onready var result_label = $ResultLabel/label  # 文字節點

func _ready():
	board_container.position = CENTER_POS       # 設定位置至中
	piece_container.position = CENTER_POS
	background_container.position = CENTER_POS
	result_label.visible = false  # 預設隱藏
	setup_board_data()

func setup_board_data():
	board = []
	pieces_grid = []
	for x in range(BOARD_SIZE):
		var col = []
		var piece_col = []
		for y in range(BOARD_SIZE):
			col.append(0)
			piece_col.append(null)
		board.append(col)
		pieces_grid.append(piece_col)

func _input(event):
	if is_animating: return

	var pressed_pos: Vector2 = Vector2.ZERO
	var is_pressed := false

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed_pos = event.global_position
		is_pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed_pos = event.position
		is_pressed = true

	if not is_pressed: return

	if game_over:
		reset_game()
		return

	var local_pos = piece_container.to_local(pressed_pos)
	var col = int(floor((local_pos.x + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))

	if col >= 0 and col < BOARD_SIZE:
		drop_piece(col)

func drop_piece(col):
	for row in range(BOARD_SIZE - 1, -1, -1):
		if board[col][row] == 0:
			board[col][row] = current_player
			play_drop_animation(col, row, current_player)
			
			if check_winner_logic(false):
				return 
				
			next_turn()
			return

func play_drop_animation(col, row, player, start_y_offset = -400):
	var p = PIECE_SCENE.instantiate()
	piece_container.add_child(p)
	p.set_piece_type(player)
	pieces_grid[col][row] = p
	var target_x = (col - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var target_y = (row - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	p.position = Vector2(target_x, start_y_offset)
	var tween = create_tween()
	tween.tween_property(p, "position:y", target_y, 0.4).set_trans(Tween.TRANS_BOUNCE)

func next_turn():
	turn_in_round += 1
	current_player = 2 if current_player == 1 else 1
	
	if turn_in_round >= 2:
		turn_in_round = 0
		start_rotation_sequence()

# 旋轉部分

func start_rotation_sequence():
	is_animating = true
	await get_tree().create_timer(0.5).timeout
	
	var new_board = []
	for i in range(BOARD_SIZE):
		new_board.append([])
		for j in range(BOARD_SIZE): new_board[i].append(0)
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			new_board[BOARD_SIZE - 1 - y][x] = board[x][y]
	board = new_board

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

	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			pieces_grid[x][y] = null

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
				pieces_grid[x][y] = p
				var final_x = (x - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
				var final_y = (y - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
				p.position = Vector2(final_x, original_y_positions[current_p_count])
				final_tween.tween_property(p, "position:y", final_y, 0.5).set_trans(Tween.TRANS_BOUNCE)
				current_p_count += 1
	
	await final_tween.finished
	
	check_winner_logic(true)
	is_animating = false

func start_warning_flash():# 閃爍
	var flash = ColorRect.new()
	add_child(flash)
	flash.color = Color(1, 0.8, 0, 0.35) 
	flash.size = get_viewport_rect().size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不攔截點擊
	
	var tween = create_tween().set_loops(1)  # 閃爍4次
	tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.tween_property(flash, "modulate:a", 1.0, 0.25)
	
	await tween.finished
	flash.queue_free()
	
func check_winner_logic(after_rotation: bool) -> bool:
	var b_reached = check_logic(1)
	var w_reached = check_logic(2)

	if after_rotation:
		# 翻轉後：雙方都連四 → 平手
		if b_reached and w_reached:
			game_over = true
			highlight_winning_pieces(1)
			highlight_winning_pieces(2)
			show_result("DRAW!")
			return true
		# 翻轉後：任一方單獨連四 → 該方直接獲勝
		if b_reached:
			game_over = true
			highlight_winning_pieces(1)
			show_result("BLACK WINS!")
			return true
		if w_reached:
			game_over = true
			highlight_winning_pieces(2)
			show_result("WHITE WINS!")
			return true
			
#	else:
#		# 落子階段（有白方最後一子版本）
#		if current_player == 1 and b_reached:
#			# 黑方落子連四 → 設旗標，讓白方還有最後一子
#			black_pending_win = true
#			print("Black connected 4! White gets one last move.")
#			start_warning_flash()
#			return false  # 遊戲繼續，不結束
#		if current_player == 2:
#			if w_reached:
#				# 白方落子連四（不管 black_pending_win，白方連四就是白方贏）
#				game_over = true
#				show_result("WHITE WINS!")
#				return true
#			elif black_pending_win:
#				# 白方用完最後一子但沒連四，黑方獲勝
#				game_over = true
#				show_result("BLACK WINS!")
#				return true
	else:
		# 落子階段（無白方最後一子版本）
		if b_reached:
			game_over = true
			highlight_winning_pieces(1)
			show_result("BLACK WINS!")
			return true
		if w_reached:
			game_over = true
			highlight_winning_pieces(2)
			show_result("WHITE WINS!")
			return true

	# 棋盤滿格
	var is_full = true
	for x in range(BOARD_SIZE):
		if board[x][0] == 0:
			is_full = false
			break
	if is_full:
		game_over = true
		show_result("DRAW!")
		return true

	return false

func show_result(text: String):
	print(text)
	result_label.text = text
	
	if text == "BLACK WINS!":
		result_label.add_theme_color_override("font_color", Color.BLACK)
	elif text == "WHITE WINS!":
		result_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		result_label.add_theme_color_override("font_color", Color.GRAY)
	
	result_label.visible = true
	
func reset_game():
	print("Resetting game...")
	game_over = false
	current_player = 1
	turn_in_round = 0
	is_animating = false
	# black_pending_win = false  # 重置旗標
	
	setup_board_data()
	for child in piece_container.get_children():
		child.queue_free()
	
	result_label.visible = false  # 隱藏結果文字
		
	var tween = create_tween()
	tween.tween_property(board_container, "rotation", 0, 0.5).set_trans(Tween.TRANS_SINE)

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

func highlight_winning_pieces(p_id):
	# 取得勝利格子後，對每個格子的棋子節點呼叫 start_glow()
	var cells = get_winning_cells(p_id)
	for cell in cells:
		var piece = pieces_grid[cell.x][cell.y]
		if piece and is_instance_valid(piece):
			piece.start_glow()

func get_winning_cells(p_id) -> Array:
	# 掃描棋盤，找出所有屬於連四（或以上）的格子座標
	# 使用 dict 去重，避免同一格被多條連線重複加入
	var winning = {}
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			if board[x][y] == p_id:
				for d in [[1,0],[0,1],[1,1],[1,-1]]:
					var dx = d[0]
					var dy = d[1]
					# 只從每段連線的起點開始，避免同一段被反覆收集
					var px = x - dx
					var py = y - dy
					var is_start = (px < 0 or px >= BOARD_SIZE or py < 0 or py >= BOARD_SIZE or board[px][py] != p_id)
					if is_start:
						var cells = get_run_cells(x, y, dx, dy, p_id)
						if cells.size() >= 4:
							for c in cells:
								winning[c] = true
	return winning.keys()

func get_run_cells(x, y, dx, dy, p_id) -> Array:
	# 從 (x,y) 起沿 (dx,dy) 方向收集連續同色格子，直到邊界或不同色為止
	var cells = []
	var cx = x
	var cy = y
	while cx >= 0 and cx < BOARD_SIZE and cy >= 0 and cy < BOARD_SIZE and board[cx][cy] == p_id:
		cells.append(Vector2i(cx, cy))
		cx += dx
		cy += dy
	return cells
