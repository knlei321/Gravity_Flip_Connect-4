extends Node2D

# --- 常數與設定 ---
const BOARD_SIZE = 6
const PIECE_SCENE = preload("res://piece.tscn")
const GRID_STEP = 111 # 棋子間距
var CENTER_POS: Vector2

# --- 遊戲變數 ---
var board = []
var pieces_grid = []  # pieces_grid[col][row] = Sprite2D node
var current_player = 1
var turn_in_round = 0
var is_animating = false
var game_over = false

# --- Undo / Redo ---
var piece_counter = 0  # 每次落子遞增，追蹤棋子總數
var undo_stack = []    # 每個動作前的快照
var redo_stack = []    # 被 undo 的動作，供 redo 使用

# --- 勝負狀態旗標 ---
var black_pending_win = false  # 黑方已連四

@onready var background_container = $background # 背景節點
@onready var board_container = $BoardContainer  # 棋盤節點
@onready var piece_container = $PieceContainer  # 棋子節點
@onready var result_label = $ResultLabel/label  # 文字節點

# ── 保留：棋盤震動動畫（原長按空白鍵 Reset 功能）──
# const _SHAKE_MAX := 8.0
# func _apply_shake(t: float) -> void:
# 	var intensity := t * _SHAKE_MAX
# 	var offset    := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
# 	board_container.position = CENTER_POS + offset
# 	piece_container.position = CENTER_POS + offset
# func _restore_shake() -> void:
# 	board_container.position = CENTER_POS
# 	piece_container.position = CENTER_POS

var _pause_menu: Node
var _audio: Node
var in_menu := true

var _undo_label: Label = null
var _redo_label: Label = null
var _undo_rect: Rect2  = Rect2()
var _redo_rect: Rect2  = Rect2()

func _ready():
	DisplayServer.window_set_ime_active(false)
	await get_tree().process_frame
	CENTER_POS = get_viewport_rect().size / 2
	board_container.position = CENTER_POS
	piece_container.position = CENTER_POS
	background_container.position = CENTER_POS
	result_label.visible = false
	var vp = get_viewport_rect().size
	var tex = background_container.texture.get_size()
	background_container.scale = Vector2(vp.x / tex.x, vp.y / tex.y)
	_audio = preload("res://code/audio.gd").new()
	add_child(_audio)
	board_container.hide()
	piece_container.hide()
	var menu = $MenuContainer
	menu.game_started.connect(_on_game_started)
	menu.initialize(CENTER_POS)

func _on_game_started() -> void:
	in_menu = false
	$MenuContainer.hide()
	board_container.show()
	piece_container.show()
	setup_board_data()
	_pause_menu = preload("res://code/pause_menu.gd").new()
	add_child(_pause_menu)
	_pause_menu.setup(self)
	_create_game_ui()

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
	piece_counter = 0  # 重置棋子計數
	undo_stack = []    # 清空 undo 歷史
	redo_stack = []    # 清空 redo 歷史

func _input(event):
	if in_menu: return
	if _pause_menu != null and _pause_menu.is_paused: return
	if event is InputEventKey and event.pressed and not event.echo:  # 鍵盤單次按下
		if event.physical_keycode == KEY_ESCAPE:
			_pause_menu.toggle()
			return
		if event.physical_keycode == KEY_ENTER and game_over:  # Enter：勝負後重置
			reset_game()
			return
		if event.physical_keycode == KEY_Z or event.physical_keycode == KEY_LEFT:  # Z / 左方向鍵：上一步
			perform_undo()
			return
		if event.physical_keycode == KEY_Y or event.physical_keycode == KEY_RIGHT:  # Y / 右方向鍵：下一步
			perform_redo()
			return
		# 數字鍵 1~6：落子至對應欄
		var col_key_map = {
			KEY_1: 0, KEY_2: 1, KEY_3: 2,
			KEY_4: 3, KEY_5: 4, KEY_6: 5
		}
		if event.physical_keycode in col_key_map:
			if not is_animating and not game_over:
				drop_piece(col_key_map[event.physical_keycode])
			return

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

	if _undo_rect.has_point(pressed_pos):
		perform_undo()
		return
	if _redo_rect.has_point(pressed_pos):
		perform_redo()
		return

	if game_over:
		reset_game()
		return

	var local_pos = piece_container.to_local(pressed_pos)
	var col = int(floor((local_pos.x + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))

	if col >= 0 and col < BOARD_SIZE:
		drop_piece(col)

func drop_piece(col):
	# 若最近一次 undo 的是旋轉，必須先把兩顆子都 undo 後才能下子
	if not redo_stack.is_empty() and redo_stack.back()["type"] == "rotate":
		return
	for row in range(BOARD_SIZE - 1, -1, -1):
		if board[col][row] == 0:
			undo_stack.push_back({  # 落子前存快照
				"type": "drop",
				"col": col,
				"row": row,
				"player": current_player,        # 落子的玩家
				"player_before": current_player, # undo 後要還原的玩家
				"turn_before": turn_in_round     # undo 後要還原的回合數
			})
			redo_stack.clear()  # 新動作發生，清除 redo 歷史
			_update_undo_redo_ui()
			piece_counter += 1  # 棋子編號遞增
			board[col][row] = current_player
			is_animating = true
			var anim = play_drop_animation(col, row, current_player)
			await anim.finished
			is_animating = false

			if check_winner_logic(false):
				return

			next_turn()
			return

func play_drop_animation(col, row, player, start_y_offset = -400) -> Tween:
	var p = PIECE_SCENE.instantiate()
	piece_container.add_child(p)
	p.set_piece_type(player)
	pieces_grid[col][row] = p
	var target_x = (col - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var target_y = (row - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	p.position = Vector2(target_x, start_y_offset)
	var tween = create_tween()
	tween.tween_property(p, "position:y", target_y + 15, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)  # 落子時間和彈跳高度(向下)
	tween.tween_callback(func(): _audio.play_drop())
	tween.tween_property(p, "position:y", target_y - 20, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) # 彈跳高度(向上)
	tween.tween_property(p, "position:y", target_y, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)       # 回彈時間
	return tween

func next_turn():
	turn_in_round += 1
	current_player = 2 if current_player == 1 else 1
	
	if turn_in_round >= 2:
		turn_in_round = 0
		start_rotation_sequence()

# 旋轉部分

func start_rotation_sequence(save_undo = true):  # save_undo=false 供 redo 呼叫時使用
	if save_undo:  # 正常遊戲流程才存快照，redo 時不重複存
		var board_copy = []  # 深拷貝旋轉前的盤面
		for x in range(BOARD_SIZE):
			board_copy.append(board[x].duplicate())
		undo_stack.push_back({
			"type": "rotate",
			"board_before": board_copy,                    # 旋轉前盤面
			"rotation_before": board_container.rotation,  # 旋轉前的視覺角度
			"player_before": current_player,              # 旋轉前的玩家
			"turn_before": turn_in_round                  # 旋轉前的回合數
		})
	is_animating = true
	await get_tree().create_timer(0.15).timeout # 棋子下落完成後到旋轉前的延遲時間
	
	var new_board = []
	for i in range(BOARD_SIZE):
		new_board.append([])
		for j in range(BOARD_SIZE): new_board[i].append(0)
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			new_board[BOARD_SIZE - 1 - y][x] = board[x][y]
	board = new_board

	_audio.play_rotation()
	var tween = create_tween().set_parallel(true)
	var target_rot = board_container.rotation + deg_to_rad(90)
	tween.tween_property(board_container, "rotation", target_rot, 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	for child in piece_container.get_children():
		var old_pos = child.position
		var new_pos = Vector2(-old_pos.y, old_pos.x) 
		tween.tween_property(child, "position", new_pos, 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	
	await tween.finished
	await get_tree().create_timer(0.3).timeout # 旋轉緩衝時間
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
	
	var old_children = piece_container.get_children()

	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			pieces_grid[x][y] = null

	var drop_pieces = []  # 記錄每顆棋子與其目標 Y，供後續彈跳使用

	var fall_tween = create_tween().set_parallel(true)
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
				var start_y = original_y_positions[current_p_count]
				p.position = Vector2(final_x, start_y)
				if start_y != final_y:  # 有下落才加入彈跳動畫
					fall_tween.tween_property(p, "position:y", final_y + 10, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					drop_pieces.append({"piece": p, "target_y": final_y})
				current_p_count += 1

	# 新棋子已建立後才刪除舊棋子，確保同一幀內無空白間隙
	for child in old_children:
		child.hide()
		child.queue_free()

	if not drop_pieces.is_empty():
		await fall_tween.finished
		_audio.play_drop()

		var bounce_tween = create_tween().set_parallel(true)
		for item in drop_pieces:
			bounce_tween.tween_property(item["piece"], "position:y", item["target_y"] - 6, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await bounce_tween.finished

		var settle_tween = create_tween().set_parallel(true)
		for item in drop_pieces:
			settle_tween.tween_property(item["piece"], "position:y", item["target_y"], 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await settle_tween.finished
	else:
		fall_tween.kill()
	
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
		_audio.play_win()
	elif text == "WHITE WINS!":
		result_label.add_theme_color_override("font_color", Color.WHITE)
		_audio.play_win()
	else:
		result_label.add_theme_color_override("font_color", Color.GRAY)

	result_label.visible = true
	
func return_to_menu() -> void:
	if _pause_menu:
		_pause_menu.cleanup()
		_pause_menu.queue_free()
		_pause_menu = null
	game_over     = false
	in_menu       = true
	is_animating  = false
	current_player   = 1
	turn_in_round    = 0
	for child in piece_container.get_children():
		child.queue_free()
	result_label.visible   = false
	board_container.rotation = 0.0
	board_container.hide()
	piece_container.hide()
	if is_instance_valid(_undo_label): _undo_label.queue_free()
	if is_instance_valid(_redo_label): _redo_label.queue_free()
	_undo_label = null
	_redo_label = null
	$MenuContainer.show()
	$MenuContainer.reinitialize(CENTER_POS)

func reset_game():
	print("Resetting game...")
	game_over = false
	current_player = 1
	turn_in_round = 0
	is_animating = false
	# black_pending_win = false  # 重置旗標
	
	setup_board_data()
	_update_undo_redo_ui()
	for child in piece_container.get_children():
		child.queue_free()

	result_label.visible = false  # 隱藏結果文字
		
	if absf(board_container.rotation) > 0.01:
		_audio.play_rotation(0.5)
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

# --- Undo / Redo 系統 ---

func _clear_game_over():  # undo 時如果遊戲已結束，清除勝負狀態
	if not game_over:
		return
	game_over = false
	result_label.visible = false  # 隱藏勝負文字
	for child in piece_container.get_children():  # 停止所有棋子的勝利閃爍
		child.stop_glow()

func perform_undo():
	if is_animating or undo_stack.is_empty():  # 動畫中或沒有歷史則不執行
		return

	_clear_game_over()  # 若遊戲結束也允許 undo

	var entry = undo_stack.pop_back()  # 取出最後一筆快照
	redo_stack.push_back(entry)        # 推入 redo 堆疊供之後還原
	is_animating = true

	if entry["type"] == "drop":
		current_player = entry["player_before"]  # 還原玩家
		turn_in_round = entry["turn_before"]      # 還原回合數
		piece_counter -= 1                         # 棋子數量回退

		var col = entry["col"]
		var row = entry["row"]
		var piece = pieces_grid[col][row]  # 取得要移除的棋子節點
		pieces_grid[col][row] = null       # 清除格子記錄
		board[col][row] = 0                # 清除盤面資料

		# 棋子上升飛出動畫（落子動畫反過來）
		_audio.play_drop_reverse()
		var tween = create_tween()
		tween.tween_property(piece, "position:y", -500.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tween.finished
		piece.queue_free()  # 動畫結束後移除節點
		_update_undo_redo_ui()
		is_animating = false

	elif entry["type"] == "rotate":
		current_player = entry["player_before"]  # 還原玩家
		turn_in_round = entry["turn_before"]      # 還原回合數

		# 重建「旋轉後、重力前」的盤面，以取得每格正確的 pre-gravity Y 位置
		var post_rot_board = []
		for i in range(BOARD_SIZE):
			var col_data = []
			for j in range(BOARD_SIZE):
				col_data.append(0)
			post_rot_board.append(col_data)
		for x in range(BOARD_SIZE):
			for y in range(BOARD_SIZE):
				if entry["board_before"][x][y] != 0:
					post_rot_board[BOARD_SIZE - 1 - y][x] = entry["board_before"][x][y]

		# === 第一階段：反重力動畫 ===
		# 棋子從重力後位置上升回「旋轉後、重力前」的正確位置
		_audio.play_drop_reverse()
		var phase1 = create_tween().set_parallel(true)
		for c in range(BOARD_SIZE):
			# 收集該欄在重力前（旋轉後）的 Y 位置，由上到下順序
			var pre_grav_ys = []
			for r in range(BOARD_SIZE):
				if post_rot_board[c][r] != 0:
					pre_grav_ys.append((r - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP)

			var piece_idx = 0
			for r in range(BOARD_SIZE):
				if board[c][r] != 0 and pieces_grid[c][r] != null:
					phase1.tween_property(pieces_grid[c][r], "position:y", pre_grav_ys[piece_idx], 0.4).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
					piece_idx += 1

		await phase1.finished  # 等待第一階段結束
		await get_tree().create_timer(0.3).timeout  # 到達正確位置後等待 0.3 秒再旋轉

		# === 第二階段：反向旋轉動畫 ===
		_audio.play_rotation()
		# 還原盤面資料（旋轉前的快照）
		board = []
		for x in range(BOARD_SIZE):
			board.append(entry["board_before"][x].duplicate())

		# 重置 pieces_grid
		for x in range(BOARD_SIZE):
			for y in range(BOARD_SIZE):
				pieces_grid[x][y] = null

		# 刪除第一階段的棋子，用 board_before 重建（起始位置與第一階段結束位置相同，視覺上不跳動）
		var old_phase1_children = piece_container.get_children()

		var piece_nodes = []  # 按 (x,y) 順序記錄新建的棋子節點
		var tween = create_tween().set_parallel(true)
		tween.tween_property(board_container, "rotation", entry["rotation_before"], 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)  # board 反向旋轉

		for x in range(BOARD_SIZE):
			for y in range(BOARD_SIZE):
				if board[x][y] != 0:
					var p = PIECE_SCENE.instantiate()
					piece_container.add_child(p)
					p.set_piece_type(board[x][y])
					piece_nodes.append(p)

					var pre_x = (x - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP  # 旋轉前的 X 位置
					var pre_y = (y - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP  # 旋轉前的 Y 位置
					p.position = Vector2(-pre_y, pre_x)  # 起始：旋轉後重力前的位置（第一階段結束位置）
					tween.tween_property(p, "position", Vector2(pre_x, pre_y), 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)  # 反向旋轉動畫

		# 新棋子已建立後才刪除舊棋子，確保同一幀內無空白間隙
		for child in old_phase1_children:
			child.hide()
			child.queue_free()

		await tween.finished

		# 將棋子節點對應回 pieces_grid（按相同的 x,y 迭代順序）
		var idx = 0
		for x in range(BOARD_SIZE):
			for y in range(BOARD_SIZE):
				if board[x][y] != 0:
					pieces_grid[x][y] = piece_nodes[idx]
					idx += 1

		_update_undo_redo_ui()
		is_animating = false

func perform_redo():
	if is_animating or redo_stack.is_empty():  # 動畫中或沒有 redo 歷史則不執行
		return

	var entry = redo_stack.pop_back()  # 取出最後一筆 redo 快照
	undo_stack.push_back(entry)         # 推回 undo 堆疊
	is_animating = true

	if entry["type"] == "drop":
		var col = entry["col"]
		var row = entry["row"]
		var player = entry["player"]

		piece_counter += 1           # 棋子數量前進
		board[col][row] = player     # 更新盤面資料
		play_drop_animation(col, row, player)  # 播放落子動畫

		# 計算 next_turn 後的狀態（不觸發旋轉，旋轉有獨立的 redo 項目）
		var new_turn = entry["turn_before"] + 1
		var new_player = 3 - player  # 1→2 或 2→1
		if new_turn >= 2:
			new_turn = 0  # 對應 next_turn() 裡的重置，但旋轉由 redo 旋轉項目處理
		current_player = new_player
		turn_in_round = new_turn

		await get_tree().create_timer(0.5).timeout  # 等落子動畫結束（0.4s + 緩衝）
		check_winner_logic(false)  # 落子後檢查勝負
		_update_undo_redo_ui()
		is_animating = false

	elif entry["type"] == "rotate":
		# 盤面已由 undo 還原到旋轉前狀態，直接重跑旋轉流程
		start_rotation_sequence(false)  # false = 不重複存入 undo_stack
		# is_animating 會由 apply_gravity_and_animate 內部設回 false
		_update_undo_redo_ui()


func _create_game_ui() -> void:
	var font      = preload("res://fonts/PressStart2P-Regular.ttf")
	var vp        := get_viewport_rect().size
	var sz        := int(vp.y * 0.033)
	var btn_w     := vp.x * 0.10
	var btn_h     := vp.y * 0.10
	var margin    := vp.x * 0.015
	var btn_y     := CENTER_POS.y + (BOARD_SIZE / 2.0 - 0.5) * GRID_STEP - btn_h * 0.5

	_undo_label = Label.new()
	_undo_label.text = "<<"
	_undo_label.add_theme_font_override("font", font)
	_undo_label.add_theme_font_size_override("font_size", sz)
	_undo_label.add_theme_color_override("font_color", Color.WHITE)
	_undo_label.add_theme_constant_override("outline_size", 2)
	_undo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_undo_label.size                 = Vector2(btn_w, btn_h)
	_undo_label.position             = Vector2(margin, btn_y)
	_undo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_undo_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	add_child(_undo_label)
	_undo_rect = Rect2(Vector2(margin, btn_y), Vector2(btn_w, btn_h))

	_redo_label = Label.new()
	_redo_label.text = ">>"
	_redo_label.add_theme_font_override("font", font)
	_redo_label.add_theme_font_size_override("font_size", sz)
	_redo_label.add_theme_color_override("font_color", Color.WHITE)
	_redo_label.add_theme_constant_override("outline_size", 2)
	_redo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_redo_label.size                 = Vector2(btn_w, btn_h)
	_redo_label.position             = Vector2(vp.x - btn_w - margin, btn_y)
	_redo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_redo_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	add_child(_redo_label)
	_redo_rect = Rect2(Vector2(vp.x - btn_w - margin, btn_y), Vector2(btn_w, btn_h))

	_update_undo_redo_ui()


func _update_undo_redo_ui() -> void:
	if is_instance_valid(_undo_label):
		_undo_label.modulate.a = 1.0 if not undo_stack.is_empty() else 0.25
	if is_instance_valid(_redo_label):
		_redo_label.modulate.a = 1.0 if not redo_stack.is_empty() else 0.25
