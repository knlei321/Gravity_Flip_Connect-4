extends Node

const BOARD_SIZE  = 6
const INF_VAL     = 100000
const DIFF_DEPTH  = [2, 4, 7, 16, 0]   # index 4 = Test，深度由 _test_depth() 動態決定
const DIFF_RANDOM = [0.70, 0.40, 0.10, 0.00, 0.02]
const COL_ORDER   = [2, 3, 1, 4, 0, 5]     # 中間欄優先，同 HTML 版

var _zobrist: Array = []   # _zobrist[piece][col][row]
var _zt:      Array = []   # _zt[turn_in_round]
var _tt:      Dictionary = {}  # 永久保留，不在每次 best_move 清除
var _cancel  := false

# 初始化時建立 Zobrist 雜湊表
func _ready() -> void:
	_init_zobrist()

# 清空置換表（換局時呼叫）
func clear_tt() -> void:
	_tt.clear()

# 重置置換表並重新隨機化 Zobrist 表（換局時完整重置）
func reinit() -> void:
	_tt.clear()
	_init_zobrist()


# 產生所有棋子、欄、行的隨機 64-bit 數，用於後續棋盤雜湊計算
func _init_zobrist() -> void:
	_zobrist = []
	for _p in range(3):
		var c_arr = []
		for _c in range(BOARD_SIZE):
			var r_arr = []
			for _r in range(BOARD_SIZE):
				r_arr.append(randi() | (randi() << 32))  # 64-bit，大幅降低碰撞率
			c_arr.append(r_arr)
		_zobrist.append(c_arr)
	_zt = [randi() | (randi() << 32), randi() | (randi() << 32)]

# 計算棋盤當前狀態的 Zobrist 雜湊值（含輪次資訊）
func _board_hash(board: Array, turn: int) -> int:
	var h: int = _zt[turn]
	for c in range(BOARD_SIZE):
		for r in range(BOARD_SIZE):
			var p: int = board[c][r]
			if p != 0:
				h ^= _zobrist[p][c][r]
	return h

# 回傳 AI 在當前棋盤的最佳落子欄位（含強制勝/擋/隨機/minimax 四層判斷）
# board[col][row], row 0 = top, row BOARD_SIZE-1 = bottom
func best_move(board: Array, ai_player: int, turn_in_round: int, difficulty: int, new_rule: bool = false, counter_draw: bool = false, post_rot_only: bool = false) -> int:
	_cancel = false
	var human:     int   = 3 - ai_player # 判斷是mini 還是max
	var max_depth: int   = _test_depth(board) if difficulty == 4 else DIFF_DEPTH[difficulty] # 決定思考深度
	var rand_ch:   float = DIFF_RANDOM[difficulty] # 機率隨機下棋功能

	# 強制判斷：在隨機和 minimax 之前執行
	# 1. AI 立即可勝 → 直接落子（所有難度）
	if not post_rot_only:
		for c in COL_ORDER:
			if board[c][0] != 0: continue
			var dr := _find_drop_row(board, c) # 檢查(翻轉後)目前的棋盤
			var nb := _drop(board, c, ai_player, dr) # 模擬落子在這一列(c)
			if _check_win(nb, ai_player): # 檢查模擬落子在那一列(c)有沒有贏
				if new_rule and ai_player == 1 and not counter_draw: # 如果開了新規則且ai是先手，不是平手
					if not _white_can_win_last_move(nb): return c # 如果落子後白色無法使用最後一子獲勝，就下第(c)列
				else: # 沒開新規則
					return c # 有就下第(c)列

	# 2. 對方立即可勝 → 強制擋（Normal 以上）
	if not post_rot_only and difficulty >= 1:
		for c in COL_ORDER:
			if board[c][0] != 0: continue
			var dr := _find_drop_row(board, c)
			if _check_win(_drop(board, c, human, dr), human):
				return c

	if randf() < rand_ch:
		var valid: Array = []
		for c in COL_ORDER:
			if board[c][0] == 0:
				valid.append(c)
		if valid.size() > 0:
			return valid[randi() % valid.size()]

	# 建立 move list：能立即勝的欄位優先，其餘維持中間欄優先順序
	var win_moves:  Array = []
	var norm_moves: Array = []
	for c in COL_ORDER:
		if board[c][0] != 0: continue
		var dr := _find_drop_row(board, c)
		var nb := _drop(board, c, ai_player, dr)
		if not post_rot_only and _check_win(nb, ai_player):
			win_moves.append([c, dr, nb])
		else:
			norm_moves.append([c, dr, nb])
	var move_list: Array = win_moves + norm_moves

	var best_col  := -1
	var best_val  := -INF_VAL - max_depth - 1
	var alpha     := -INF_VAL - max_depth - 1
	var beta      :=  INF_VAL + max_depth + 1

	for move in move_list:
		var c:         int   = move[0]
		var _drop_row: int   = move[1]
		var nb:        Array = move[2]

		# 落子即勝（旋轉前）→ 直接回傳
		if not post_rot_only and _check_win(nb, ai_player):
			if new_rule and ai_player == 1 and not counter_draw:
				if not _white_can_win_last_move(nb): return c
			else:
				return c

		var next_turn := (turn_in_round + 1) % 2
		var nb_eval   := nb
		if turn_in_round == 1:
			nb_eval = _rotate_and_gravity(nb)
		var h   := _board_hash(nb_eval, next_turn)
		var val := _minimax(nb_eval, max_depth - 1, alpha, beta, false, ai_player, human, next_turn, h, new_rule, counter_draw, post_rot_only)
		if val > best_val:
			best_val = val
			best_col = c
		alpha = maxi(alpha, val)

	if best_col == -1:
		for c in COL_ORDER:
			if board[c][0] == 0:
				return c
	return best_col


# 檢查白方（player 2）是否能在當前棋盤立即落子連四獲勝
func _white_can_win_last_move(board: Array) -> bool:
	for c in range(BOARD_SIZE):
		var dr := _find_drop_row(board, c)
		if dr < 0: continue
		if _check_win(_drop(board, c, 2, dr), 2):
			return true
	return false


# Minimax 遞迴搜尋主體，含 alpha-beta 剪枝、置換表查詢/寫入、旋轉重力模擬
func _minimax(board: Array, depth: int, alpha: int, beta: int,
			  is_ai_turn: bool, ai_player: int, human: int,
			  turn: int, board_hash: int, new_rule: bool = false, counter_draw: bool = false, post_rot_only: bool = false) -> int:

	if _cancel: return 0

	# post_rot_only：turn=1 代表棋盤尚未旋轉，不在此判勝負；turn=0 代表已旋轉，正常判
	if not post_rot_only or turn == 0:
		# 雙方同時連四：正式規則為平手（main.gd 旋轉後同時連四=DRAW）
		# 只有 post_rot_only 模擬模式才套用決勝邏輯
		if _check_win(board, ai_player) and _check_win(board, human):
			if post_rot_only:
				return _tiebreak_val(board, ai_player, human, depth)
			return 0

		# 新規則：黑方落子連四（turn==1 代表黑方剛落子）→ 白方最後一手
		if new_rule and turn == 1 and _check_win(board, 1):
			if not (counter_draw and ai_player == 1):
				for c in range(BOARD_SIZE):
					var dr := _find_drop_row(board, c)
					if dr < 0: continue
					if _check_win(_drop(board, c, 2, dr), 2):
						if counter_draw: return 0
						return (INF_VAL + depth) if (ai_player == 2) else -(INF_VAL + depth)
				return (INF_VAL + depth) if (ai_player == 1) else -(INF_VAL + depth)

		if _check_win(board, ai_player):  return  INF_VAL + depth
		if _check_win(board, human):       return -INF_VAL - depth
	if _is_full(board):                return 0
	if depth == 0:                     return _evaluate(board, ai_player, human)

	if board_hash in _tt:
		var e = _tt[board_hash]
		if e["d"] >= depth:
			if   e["f"] == 0: return e["v"]
			elif e["f"] == 1: alpha = maxi(alpha, e["v"])
			elif e["f"] == 2: beta  = mini(beta,  e["v"])
			if alpha >= beta: return e["v"]

	var mover      := ai_player if is_ai_turn else human
	var orig_alpha := alpha
	var best       := -INF_VAL - 1 if is_ai_turn else INF_VAL + 1

	# Move ordering：能立即勝的欄位優先，其餘維持中間欄優先順序
	var win_moves:  Array = []
	var norm_moves: Array = []
	for c in COL_ORDER:
		if board[c][0] != 0: continue
		var dr := _find_drop_row(board, c)
		var nb := _drop(board, c, mover, dr)
		if not post_rot_only and _check_win(nb, mover):
			win_moves.append([c, dr, nb])
		else:
			norm_moves.append([c, dr, nb])

	for move in (win_moves + norm_moves):
		var c:        int   = move[0]
		var drop_row: int   = move[1]
		var nb:       Array = move[2]
		var next_turn := (turn + 1) % 2
		var nb_eval   := nb

		if turn == 1:
			if not post_rot_only and _check_win(nb, mover):
				var pre_win_val := (INF_VAL + depth - 1) if (mover == ai_player) else -(INF_VAL + depth - 1)
				if is_ai_turn:
					if pre_win_val > best: best = pre_win_val
					alpha = maxi(alpha, pre_win_val)
				else:
					if pre_win_val < best: best = pre_win_val
					beta  = mini(beta, pre_win_val)
				if alpha >= beta:
					break
				continue
			nb_eval = _rotate_and_gravity(nb)

		var nh: int = board_hash ^ (_zt[turn] as int) ^ (_zt[next_turn] as int) ^ (_zobrist[mover][c][drop_row] as int)
		if turn == 1:
			nh = _board_hash(nb_eval, next_turn)

		var val := _minimax(nb_eval, depth - 1, alpha, beta, not is_ai_turn, ai_player, human, next_turn, nh, new_rule, counter_draw, post_rot_only)

		if is_ai_turn:
			if val > best: best = val
			alpha = maxi(alpha, val)
		else:
			if val < best: best = val
			beta = mini(beta, val)
		if alpha >= beta:
			break

	var flag := 0
	if   best <= orig_alpha: flag = 2
	elif best >= beta:       flag = 1
	_tt[board_hash] = {"d": depth, "f": flag, "v": best}

	return best


# 找出指定欄位最低的空行索引（重力落子位置），欄滿回傳 -1
func _find_drop_row(board: Array, c: int) -> int:
	for r in range(BOARD_SIZE - 1, -1, -1):
		if board[c][r] == 0:
			return r
	return -1


# 深複製棋盤並在指定欄/行落子，回傳新棋盤（不修改原棋盤）
func _drop(board: Array, c: int, player: int, drop_row: int) -> Array:
	var nb := []
	for i in range(BOARD_SIZE):
		nb.append(board[i].duplicate())
	nb[c][drop_row] = player
	return nb


# 將棋盤順時針旋轉 90 度（同 main.gd 的旋轉方向），再對每欄重新套用重力（棋子下沉）
func _rotate_and_gravity(board: Array) -> Array:
	var rot := []
	for i in range(BOARD_SIZE):
		var col = []
		col.resize(BOARD_SIZE)
		col.fill(0)
		rot.append(col)
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			rot[BOARD_SIZE - 1 - y][x] = board[x][y]
	for x in range(BOARD_SIZE):
		var pieces: Array = []
		for y in range(BOARD_SIZE):
			if rot[x][y] != 0:
				pieces.append(rot[x][y])
				rot[x][y] = 0
		for i in range(pieces.size()):
			rot[x][BOARD_SIZE - 1 - i] = pieces[pieces.size() - 1 - i]
	return rot


# 檢查指定玩家是否已在棋盤上形成連四（四個方向）
func _check_win(board: Array, player: int) -> bool:
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			if board[x][y] == player:
				if _cd(board, x, y, 1,  0, player): return true
				if _cd(board, x, y, 0,  1, player): return true
				if _cd(board, x, y, 1,  1, player): return true
				if _cd(board, x, y, 1, -1, player): return true
	return false


# 從 (x,y) 沿 (dx,dy) 方向確認連續四格是否全為同一玩家的棋子
func _cd(board: Array, x: int, y: int, dx: int, dy: int, player: int) -> bool:
	for i in range(4):
		var nx := x + dx * i
		var ny := y + dy * i
		if nx < 0 or nx >= BOARD_SIZE or ny < 0 or ny >= BOARD_SIZE: return false
		if board[nx][ny] != player: return false
	return true


# 檢查棋盤是否已滿（所有欄頂端均無空格）
func _is_full(board: Array) -> bool:
	for c in range(BOARD_SIZE):
		if board[c][0] == 0:
			return false
	return true


# 掃描棋盤所有方向的四格窗口並加總分數，作為 depth=0 時的靜態評估值
func _evaluate(board: Array, ai: int, human: int) -> int:
	var score := 0
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE - 3):
			score += _win(board, x, y, 1, 0, ai, human)
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE - 3):
			score += _win(board, x, y, 0, 1, ai, human)
	for x in range(BOARD_SIZE - 3):
		for y in range(3, BOARD_SIZE):
			score += _win(board, x, y, 1, -1, ai, human)
	for x in range(BOARD_SIZE - 3):
		for y in range(BOARD_SIZE - 3):
			score += _win(board, x, y, 1, 1, ai, human)
	return score


# 計算單一四格窗口的分數（混色視窗得 0，純色依子數給分）
func _win(board: Array, x: int, y: int, dx: int, dy: int, ai: int, human: int) -> int:
	var ac := 0
	var hc := 0
	for i in range(4):
		var v: int = board[x + dx * i][y + dy * i]
		if   v == ai:    ac += 1
		elif v == human: hc += 1
	if ac > 0 and hc > 0: return 0
	if ac == 4: return 100
	if ac == 3: return 10
	if ac == 2: return  3
	if ac == 1: return  1
	if hc == 4: return -100
	if hc == 3: return -10
	if hc == 2: return  -3
	if hc == 1: return  -1
	return 0


# 統計指定玩家的最長連線長度與連四（含以上）組數，供決勝判定使用
func _win_stats(board: Array, player: int) -> Array:
	var max_len    := 0
	var win_groups := 0
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			if board[x][y] != player: continue
			for d in [[1, 0], [0, 1], [1, 1], [1, -1]]:
				var dx: int = d[0]
				var dy: int = d[1]
				var px := x - dx
				var py := y - dy
				if px >= 0 and px < BOARD_SIZE and py >= 0 and py < BOARD_SIZE:
					if board[px][py] == player: continue
				var run_len := 0
				var cx := x
				var cy := y
				while cx >= 0 and cx < BOARD_SIZE and cy >= 0 and cy < BOARD_SIZE and board[cx][cy] == player:
					run_len += 1
					cx += dx
					cy += dy
				if run_len > max_len: max_len = run_len
				if run_len >= 4:      win_groups += 1
	return [win_groups, max_len]

# 雙方同時連四時，依最長連線再依連四組數判定勝者，均等則回傳 0（真平）
func _tiebreak_winner(board: Array, p1: int, p2: int) -> int:
	var s1 := _win_stats(board, p1)
	var s2 := _win_stats(board, p2)
	if s1[1] > s2[1]: return p1
	if s2[1] > s1[1]: return p2
	if s1[0] > s2[0]: return p1
	if s2[0] > s1[0]: return p2
	return 0

# 將決勝勝者轉換為 minimax 分數（AI 勝正值、Human 勝負值、平局 0）
func _tiebreak_val(board: Array, ai: int, human: int, depth: int) -> int:
	var winner := _tiebreak_winner(board, ai, human)
	if winner == ai:    return  INF_VAL + depth
	if winner == human: return -INF_VAL - depth
	return 0

# Test 難度專用：依棋盤棋子數量動態調整搜尋深度（殘局時加深）
func _test_depth(board: Array) -> int:
	var pieces := 0
	for c in range(BOARD_SIZE):
		for r in range(BOARD_SIZE):
			if board[c][r] != 0:
				pieces += 1
	if   pieces <= 5:  return 12
	elif pieces <= 12: return 14
	else:              return 15
