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

func _ready() -> void:
	_init_zobrist()

func clear_tt() -> void:
	_tt.clear()

func reinit() -> void:
	_tt.clear()
	_init_zobrist()


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

func _board_hash(board: Array, turn: int) -> int:
	var h: int = _zt[turn]
	for c in range(BOARD_SIZE):
		for r in range(BOARD_SIZE):
			var p: int = board[c][r]
			if p != 0:
				h ^= _zobrist[p][c][r]
	return h

# Returns best column for ai_player to play.
# board[col][row], row 0 = top, row BOARD_SIZE-1 = bottom
func best_move(board: Array, ai_player: int, turn_in_round: int, difficulty: int, new_rule: bool = false, counter_draw: bool = false) -> int:
	_cancel = false
	var human:     int   = 3 - ai_player
	var max_depth: int   = _test_depth(board) if difficulty == 4 else DIFF_DEPTH[difficulty]
	var rand_ch:   float = DIFF_RANDOM[difficulty]

	# 強制判斷：在隨機和 minimax 之前執行
	# 1. AI 立即可勝 → 直接落子（所有難度）
	for c in COL_ORDER:
		if board[c][0] != 0: continue
		var dr := _find_drop_row(board, c)
		var nb := _drop(board, c, ai_player, dr)
		if _check_win(nb, ai_player):
			if new_rule and ai_player == 1 and not counter_draw:
				if not _white_can_win_last_move(nb): return c
			else:
				return c

	# 2. 對方立即可勝 → 強制擋（Normal 以上）
	if difficulty >= 1:
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
		if _check_win(nb, ai_player):
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
		if _check_win(nb, ai_player):
			if new_rule and ai_player == 1 and not counter_draw:
				if not _white_can_win_last_move(nb): return c
			else:
				return c

		var next_turn := (turn_in_round + 1) % 2
		var nb_eval   := nb
		if turn_in_round == 1:
			nb_eval = _rotate_and_gravity(nb)
		var h   := _board_hash(nb_eval, next_turn)
		var val := _minimax(nb_eval, max_depth - 1, alpha, beta, false, ai_player, human, next_turn, h, new_rule, counter_draw)
		if val > best_val:
			best_val = val
			best_col = c
		alpha = maxi(alpha, val)

	if best_col == -1:
		for c in COL_ORDER:
			if board[c][0] == 0:
				return c
	return best_col


func _white_can_win_last_move(board: Array) -> bool:
	for c in range(BOARD_SIZE):
		var dr := _find_drop_row(board, c)
		if dr < 0: continue
		if _check_win(_drop(board, c, 2, dr), 2):
			return true
	return false


func _minimax(board: Array, depth: int, alpha: int, beta: int,
			  is_ai_turn: bool, ai_player: int, human: int,
			  turn: int, board_hash: int, new_rule: bool = false, counter_draw: bool = false) -> int:

	if _cancel: return 0

	# 雙方同時連四（旋轉後）→ 平局，必須在單方勝利之前檢查
	if _check_win(board, ai_player) and _check_win(board, human): return 0

	# 新規則：黑方落子連四（turn==1 代表黑方剛落子）→ 白方最後一手
	if new_rule and turn == 1 and _check_win(board, 1):
		if not (counter_draw and ai_player == 1):
			for c in range(BOARD_SIZE):
				var dr := _find_drop_row(board, c)
				if dr < 0: continue
				if _check_win(_drop(board, c, 2, dr), 2):
					if counter_draw: return 0   # 白方 AI：反殺 = 平局
					return (INF_VAL + depth) if (ai_player == 2) else -(INF_VAL + depth)
			return (INF_VAL + depth) if (ai_player == 1) else -(INF_VAL + depth)
		# counter_draw + 黑方 AI：直接落到下方 _check_win 當作正常黑方勝，保持進攻性

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
		if _check_win(nb, mover):
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
			if _check_win(nb, mover):
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

		var val := _minimax(nb_eval, depth - 1, alpha, beta, not is_ai_turn, ai_player, human, next_turn, nh, new_rule, counter_draw)

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


func _find_drop_row(board: Array, c: int) -> int:
	for r in range(BOARD_SIZE - 1, -1, -1):
		if board[c][r] == 0:
			return r
	return -1


func _drop(board: Array, c: int, player: int, drop_row: int) -> Array:
	var nb := []
	for i in range(BOARD_SIZE):
		nb.append(board[i].duplicate())
	nb[c][drop_row] = player
	return nb


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


func _check_win(board: Array, player: int) -> bool:
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			if board[x][y] == player:
				if _cd(board, x, y, 1,  0, player): return true
				if _cd(board, x, y, 0,  1, player): return true
				if _cd(board, x, y, 1,  1, player): return true
				if _cd(board, x, y, 1, -1, player): return true
	return false


func _cd(board: Array, x: int, y: int, dx: int, dy: int, player: int) -> bool:
	for i in range(4):
		var nx := x + dx * i
		var ny := y + dy * i
		if nx < 0 or nx >= BOARD_SIZE or ny < 0 or ny >= BOARD_SIZE: return false
		if board[nx][ny] != player: return false
	return true


func _is_full(board: Array) -> bool:
	for c in range(BOARD_SIZE):
		if board[c][0] == 0:
			return false
	return true


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


func _test_depth(board: Array) -> int:
	var pieces := 0
	for c in range(BOARD_SIZE):
		for r in range(BOARD_SIZE):
			if board[c][r] != 0:
				pieces += 1
	if   pieces <= 5:  return 12
	elif pieces <= 12: return 14
	else:              return 15
