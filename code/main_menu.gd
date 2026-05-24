extends Node2D

signal game_started
signal ai_game_started(difficulty: int, human_player: int)

const PIECE_SCENE = preload("res://piece.tscn")
const BOARD_SIZE = 6
const GRID_STEP = 111
const MENU_COLS = 5
const MENU_WORDS = ["START", "RULES", "SETUP", "VS AI"]
const MENU_FONT  = preload("res://fonts/PressStart2P-Regular.ttf")

var CENTER_POS: Vector2
var _audio: Node

@onready var board_container = $MenuBoardContainer
@onready var piece_container = $MenuBoardContainer/MenuPieceContainer
@onready var label_container = $MenuLabelContainer

var pieces_grid = []
var row_pieces = [[], [], [], []]
var row_labels  = [[], [], [], []]
var hovered_row := -1
var pressed_row := -1
var is_animating := false
var _rules_container: Node2D = null
var _back_btn_rect: Rect2 = Rect2()

var _setup_container: Node2D = null
var _setup_back_btn_rect: Rect2 = Rect2()
var _volume_level: int = 5
var _is_muted: bool = false
var _volume_pieces: Array = []
var _note_piece: Node = null
var _volume_rects: Array = []
var _note_rect: Rect2 = Rect2()
var _piece_natural_scale := Vector2.ZERO

var _in_difficulty_select  := false
var _diff_back_label: Label = null
var _diff_back_rect: Rect2  = Rect2()
var _ai_mode_pending      := false
var _ai_difficulty_pending := 0

var _in_color_select       := false
var _color_back_label: Label = null
var _color_back_rect: Rect2  = Rect2()
var _human_player_pending  := 1
var _color_hover_side      := -1
var _color_pressed_side    := -1

const DIFF_WORDS  = ["EASY ", "NORM ", "HARD ", "EVIL "]
const COLOR_WORDS = ["CHOOS", "YOUR ", "COLOR"]  # rows 0-2，5 chars

func _ready() -> void:
	pass  # 由 main.gd 在取得 CENTER_POS 後呼叫 initialize()

func initialize(center: Vector2) -> void:
	CENTER_POS = center
	board_container.position = center
	piece_container.position = Vector2.ZERO  # 相對於 board_container，不需重設

	for _c in range(BOARD_SIZE):
		var col = []
		for _r in range(BOARD_SIZE):
			col.append(null)
		pieces_grid.append(col)

	_audio = preload("res://code/audio.gd").new()
	add_child(_audio)

	is_animating = true
	await _spawn_all_pieces()
	_add_menu_labels()
	is_animating = false

func _spawn_all_pieces() -> void:
	for col in range(BOARD_SIZE):
		for row in range(BOARD_SIZE):
			var p = PIECE_SCENE.instantiate()
			piece_container.add_child(p)
			p.set_piece_type(1)

			var final_x = (col - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
			var final_y = (row - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
			p.position = Vector2(final_x, -500.0)
			pieces_grid[col][row] = p
			if row < 4:
				row_pieces[row].append(p)

			# 底排（row 5）延遲 0、頂排（row 0）延遲最大，由下往上填滿
			var row_delay = (BOARD_SIZE - 1 - row) * 0.10
			var col_jitter = randf_range(-0.04, 0.04)
			var t = create_tween()
			t.tween_interval(maxf(0.0, row_delay + col_jitter))
			t.tween_property(p, "position:y", final_y + 15.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(p, "position:y", final_y - 8.0,  0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(p, "position:y", final_y,         0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 每排落地時播一聲，由下往上共六聲
	await get_tree().create_timer(0.28).timeout  # 底排首次落地
	for _r in range(BOARD_SIZE):
		_audio.play_drop()
		if _r < BOARD_SIZE - 1:
			await get_tree().create_timer(0.10).timeout
	await get_tree().create_timer(0.22).timeout  # 等頂排彈跳完全穩定

func _add_menu_labels() -> void:
	for menu_row in range(4):
		var word = MENU_WORDS[menu_row]
		for col in range(MENU_COLS):
			var label = Label.new()
			label.text = word[col]
			label.add_theme_font_override("font", MENU_FONT)
			label.add_theme_font_size_override("font_size", 42)
			label.add_theme_color_override("font_color", Color.WHITE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			label.size = Vector2(GRID_STEP, GRID_STEP)
			var wx = CENTER_POS.x + (col      - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
			var wy = CENTER_POS.y + (menu_row - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
			label.position = Vector2(wx - GRID_STEP / 2.0, wy - GRID_STEP / 2.0)
			label_container.add_child(label)
			row_labels[menu_row].append(label)

func _get_row_at(pos: Vector2) -> int:
	var local = piece_container.to_local(pos)
	var col = int(floor((local.x + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
	var row = int(floor((local.y + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
	if col >= 0 and col < BOARD_SIZE and row >= 0 and row < 4:
		return row
	return -1

func _input(event):
	if is_animating:
		return

	if _rules_container != null:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				_go_back_from_rules()
			return
		var pressed_pos := Vector2.ZERO
		var is_pressed  := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed_pos = event.global_position
			is_pressed  = true
		elif event is InputEventScreenTouch and event.pressed:
			pressed_pos = event.position
			is_pressed  = true
		if is_pressed and _back_btn_rect.has_point(pressed_pos):
			_go_back_from_rules()
		return

	if _in_color_select:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				_go_back_from_color()
			return
		if event is InputEventMouseMotion:
			if _color_pressed_side < 0:
				var local: Vector2 = piece_container.to_local(event.global_position)
				var col := int(floor((local.x + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
				var row := int(floor((local.y + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
				var side := -1
				if row >= 3 and row < BOARD_SIZE and col >= 0 and col < BOARD_SIZE:
					side = 0 if col < 3 else 1
				_set_color_hover(side)
			return
		var _cpt    := Vector2.ZERO
		var _cpress := false
		var _crel   := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_cpt    = event.global_position
			_cpress = event.pressed
			_crel   = not event.pressed
		elif event is InputEventScreenTouch:
			_cpt    = event.position
			_cpress = event.pressed
			_crel   = not event.pressed
		if _cpress:
			if _color_back_rect.has_point(_cpt):
				_go_back_from_color()
				return
			var local: Vector2 = piece_container.to_local(_cpt)
			var col := int(floor((local.x + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
			var row := int(floor((local.y + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
			if row >= 3 and row < BOARD_SIZE and col >= 0 and col < BOARD_SIZE:
				var ps := 0 if col < 3 else 1
				_color_pressed_side = ps
				_color_hover_side   = -1
				_audio.play_drop()
				for r in range(3, BOARD_SIZE):
					for c in range(BOARD_SIZE):
						if is_instance_valid(pieces_grid[c][r]):
							pieces_grid[c][r].modulate = Color(1.64, 1.64, 1.64) if (0 if c < 3 else 1) == ps else Color.WHITE
				var t := create_tween()
				t.tween_interval(0.07)
				t.tween_callback(func():
					if _color_pressed_side == ps:
						for r2 in range(3, BOARD_SIZE):
							for c2 in range(BOARD_SIZE):
								if is_instance_valid(pieces_grid[c2][r2]) and (0 if c2 < 3 else 1) == ps:
									pieces_grid[c2][r2].modulate = Color(1.32, 1.32, 1.32)
				)
		elif _crel and _color_pressed_side >= 0:
			var local: Vector2 = piece_container.to_local(_cpt)
			var col := int(floor((local.x + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
			var row := int(floor((local.y + (BOARD_SIZE * GRID_STEP) / 2.0) / GRID_STEP))
			var rel_side := -1
			if row >= 3 and row < BOARD_SIZE and col >= 0 and col < BOARD_SIZE:
				rel_side = 0 if col < 3 else 1
			if rel_side == _color_pressed_side:
				var chosen_side       := _color_pressed_side
				_in_color_select      = false
				_color_hover_side     = -1
				_color_pressed_side   = -1
				_ai_mode_pending      = true
				_human_player_pending = 1 if chosen_side == 0 else 2
				if is_instance_valid(_color_back_label):
					_color_back_label.queue_free()
				_color_back_label = null
				_color_back_rect  = Rect2()
				is_animating = true
				await _start_game()
			else:
				var prev := _color_pressed_side
				_color_pressed_side = -1
				_color_hover_side   = -1
				for r in range(3, BOARD_SIZE):
					for c in range(BOARD_SIZE):
						if is_instance_valid(pieces_grid[c][r]):
							pieces_grid[c][r].modulate = Color.WHITE
				var hover_side := -1
				if row >= 3 and row < BOARD_SIZE and col >= 0 and col < BOARD_SIZE:
					hover_side = rel_side
				_set_color_hover(hover_side)
		return

	if _in_difficulty_select:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				_go_back_from_difficulty()
			return
		var _pt := Vector2.ZERO
		var _clicked := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pt = event.global_position
			_clicked = true
		elif event is InputEventScreenTouch and event.pressed:
			_pt = event.position
			_clicked = true
		if _clicked and _diff_back_rect.has_point(_pt):
			_go_back_from_difficulty()
			return
		# 其他輸入走一般 row 偵測邏輯（點擊難度排）

	if _setup_container != null:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				_go_back_from_setup()
			return
		var pt := Vector2.ZERO
		var clicked := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pt = event.global_position
			clicked = true
		elif event is InputEventScreenTouch and event.pressed:
			pt = event.position
			clicked = true
		if clicked:
			for i in range(_volume_rects.size()):
				if _volume_rects[i].has_point(pt):
					_volume_level = 5 - i
					_is_muted = false
					_update_volume_display()
					_apply_volume()
					_audio.play_drop()
					return
			if _note_rect.has_point(pt):
				_is_muted = not _is_muted
				_update_volume_display()
				_apply_volume()
				if not _is_muted:
					_audio.play_drop()
				return
			if _setup_back_btn_rect.has_point(pt):
				_go_back_from_setup()
		return

	if event is InputEventMouseMotion:
		_set_hover_row(_get_row_at(event.global_position))

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var row = _get_row_at(event.global_position)
		if event.pressed:
			if row >= 0:
				_on_row_press(row)
		else:
			_on_row_release(row)

	elif event is InputEventScreenTouch:
		var row = _get_row_at(event.position)
		if event.pressed:
			if row >= 0:
				_on_row_press(row)
		else:
			_on_row_release(row)

func _set_hover_row(new_row: int) -> void:
	if new_row == hovered_row:
		return
	if hovered_row >= 0:
		for p in row_pieces[hovered_row]:
			p.set_piece_type(1)
			p.modulate = Color.WHITE
		for l in row_labels[hovered_row]:
			l.add_theme_color_override("font_color", Color.WHITE)
	hovered_row = new_row
	if new_row >= 0:
		_audio.play_hover()
		for p in row_pieces[new_row]:
			p.set_piece_type(2)
		for l in row_labels[new_row]:
			l.add_theme_color_override("font_color", Color.BLACK)

func _on_row_press(row: int) -> void:
	pressed_row = row
	_set_hover_row(-1)
	# 白棋閃一下再變灰
	for p in row_pieces[row]:
		p.set_piece_type(2)
		p.modulate = Color.WHITE
	for l in row_labels[row]:
		l.add_theme_color_override("font_color", Color.BLACK)
	var t = create_tween()
	t.tween_interval(0.07)
	t.tween_callback(func():
		if pressed_row == row:  # 還沒放開才套灰色
			for p in row_pieces[row]:
				p.modulate = Color(0.68, 0.68, 0.68)
			for l in row_labels[row]:
				l.add_theme_color_override("font_color", Color(0.30, 0.30, 0.30))
	)

func _on_row_release(row: int) -> void:
	if pressed_row < 0:
		return
	var pr = pressed_row
	pressed_row = -1
	if row == pr:
		is_animating = true
		if _in_difficulty_select:
			_in_difficulty_select  = false
			_ai_difficulty_pending = pr
			if is_instance_valid(_diff_back_label):
				_diff_back_label.queue_free()
			_diff_back_label = null
			_diff_back_rect  = Rect2()
			await _show_color_select()
		else:
			match pr:
				0: await _start_game()
				1: await _show_rules()
				2: await _show_setup()
				3: await _show_difficulty()
	else:
		_restore_row(pr)

func _show_rules() -> void:
	label_container.hide()

	var dur    := 0.75
	var exit_x := CENTER_POS.x + 1500.0

	_audio.play_rotation(dur)
	var slide = create_tween().set_parallel(true)
	slide.tween_property(board_container, "position:x", exit_x, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slide.tween_property(board_container, "rotation", board_container.rotation + TAU * 1.5, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await slide.finished

	_create_rules_ui()
	var fade_in = create_tween()
	fade_in.tween_property(_rules_container, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished
	is_animating = false


func _create_rules_ui() -> void:
	_rules_container = Node2D.new()
	_rules_container.modulate.a = 0.0
	add_child(_rules_container)

	var vp := get_viewport_rect().size

	const HEADING_SIZE := 50
	const BODY_SIZE    := 20
	const HEAD_H       := HEADING_SIZE * 1.6  # 標題行高，倍數可調
	const LINE_H       := BODY_SIZE    * 2.8  # 內文行高，倍數可調 
	const BLANK_SM     := BODY_SIZE    * 1.2  # 小間距
	const BLANK_LG     := BODY_SIZE    * 2.0  # 大間距

	var lines: Array = [
		["HOW TO PLAY",                              HEADING_SIZE, HEAD_H  ],
		["",                                          0,           BLANK_SM],
		["Take turns placing one piece per turn.",   BODY_SIZE,   LINE_H  ],
		["The board rotates 90° clockwise",          BODY_SIZE,   LINE_H  ],
		["after each round.",                        BODY_SIZE,   LINE_H  ],
		["Pieces fall with gravity after rotation.", BODY_SIZE,   LINE_H  ],
		["",                                          0,           BLANK_LG],
		["WIN CONDITIONS",                           HEADING_SIZE, HEAD_H  ],
		["",                                          0,           BLANK_SM],
		["Connect 4 in a row to win.",               BODY_SIZE,   LINE_H  ],
		["Connecting 4 after rotation also wins.",   BODY_SIZE,   LINE_H  ],
		["Both connect 4 after rotation = Draw.",    BODY_SIZE,   LINE_H  ],
		["Board full with no winner = Draw.",        BODY_SIZE,   LINE_H  ],
	]

	var total_h := 0.0
	for l in lines:
		total_h += float(l[2])
	var cur_y := (vp.y - total_h) / 2.0

	for line_data in lines:
		var text: String = line_data[0]
		var size: int    = line_data[1]
		var h: float     = float(line_data[2])
		if text != "":
			var lbl := Label.new()
			lbl.text = text
			lbl.add_theme_font_override("font", MENU_FONT)
			lbl.add_theme_font_size_override("font_size", size)
			lbl.add_theme_color_override("font_color", Color.WHITE)
			lbl.add_theme_constant_override("outline_size", 2)
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.size                 = Vector2(vp.x, h)
			lbl.position             = Vector2(0.0, cur_y)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
			_rules_container.add_child(lbl)
		cur_y += h

	var back := Label.new()
	back.text = "< BACK"
	back.add_theme_font_override("font", MENU_FONT)
	back.add_theme_font_size_override("font_size", 28)
	back.add_theme_color_override("font_color", Color.WHITE)
	back.add_theme_constant_override("outline_size", 2)
	back.add_theme_color_override("font_outline_color", Color.BLACK)
	back.size                 = Vector2(320.0, 64.0)
	back.position             = Vector2(60.0, vp.y - 110.0)
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	back.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_rules_container.add_child(back)
	_back_btn_rect = Rect2(Vector2(60.0, vp.y - 110.0), Vector2(320.0, 64.0))


func _go_back_from_rules() -> void:
	if is_animating:
		return
	is_animating = true

	var fade_out = create_tween()
	fade_out.tween_property(_rules_container, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished

	_destroy_rules_ui()
	var dur   := 0.75
	_audio.play_rotation(dur)
	var slide  = create_tween().set_parallel(true)
	slide.tween_property(board_container, "position:x", CENTER_POS.x, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slide.tween_property(board_container, "rotation", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await slide.finished

	_restore_row(1)
	label_container.show()
	is_animating = false


func _show_setup() -> void:
	label_container.hide()
	_audio.play_rotation(0.5)

	var max_fly := 0.0
	for child in piece_container.get_children():
		var sy: float   = CENTER_POS.y + (child as Node2D).position.y
		var dist: float = sy + randf_range(80.0, 280.0)
		var dur         := randf_range(0.35, 0.62)
		var delay       := randf_range(0.0, 0.08)
		var x_off       := randf_range(-80.0, 80.0)
		var ft = create_tween().set_parallel(true)
		ft.tween_property(child, "position", child.position + Vector2(x_off, -dist), dur).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ft.tween_property(child, "rotation", child.rotation + randf_range(-TAU, TAU), dur).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		max_fly = maxf(max_fly, delay + dur)
	await get_tree().create_timer(max_fly).timeout

	for child in piece_container.get_children():
		child.queue_free()

	_create_setup_ui()  # 棋子從 scale 0 生成

	# ── 彈出動畫：由上往下逐顆錯開 ──
	var all_pieces: Array = _volume_pieces.duplicate()
	all_pieces.append(_note_piece)
	var max_pop := 0.0
	for i in range(all_pieces.size()):
		var p       = all_pieces[i]
		var delay: float = (all_pieces.size() - 1 - i) * 0.07
		var st = create_tween()
		st.tween_interval(delay)
		st.tween_callback(_audio.play_drop)
		st.tween_property(p, "scale", _piece_natural_scale * 1.2, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_property(p, "scale", _piece_natural_scale,       0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		max_pop = maxf(max_pop, delay + 0.28)

	# 覆蓋層在棋子彈出到一半時淡入
	var fade_in = create_tween()
	fade_in.tween_interval(max_pop * 0.45)
	fade_in.tween_property(_setup_container, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await get_tree().create_timer(max_pop).timeout
	is_animating = false


func _create_setup_ui() -> void:
	_setup_container = Node2D.new()
	_setup_container.modulate.a = 0.0
	add_child(_setup_container)
	_volume_pieces.clear()
	_volume_rects.clear()

	var local_x: float  = (0 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var screen_x: float = CENTER_POS.x + local_x

	for r in range(5):
		var local_y: float  = (r - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
		var screen_y: float = CENTER_POS.y + local_y
		var p               := PIECE_SCENE.instantiate()
		piece_container.add_child(p)
		if _piece_natural_scale == Vector2.ZERO:
			_piece_natural_scale = p.scale
		p.position = Vector2(local_x, local_y)
		p.scale    = Vector2.ZERO
		_volume_pieces.append(p)
		_volume_rects.append(Rect2(
			Vector2(screen_x - GRID_STEP / 2.0, screen_y - GRID_STEP / 2.0),
			Vector2(GRID_STEP, GRID_STEP)
		))

	var note_local_y: float  = (5 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var note_screen_y: float = CENTER_POS.y + note_local_y
	_note_piece = PIECE_SCENE.instantiate()
	piece_container.add_child(_note_piece)
	_note_piece.position = Vector2(local_x, note_local_y)
	_note_piece.scale    = Vector2.ZERO
	_note_piece.set_piece_type(1)
	_note_rect = Rect2(
		Vector2(screen_x - GRID_STEP / 2.0, note_screen_y - GRID_STEP / 2.0),
		Vector2(GRID_STEP, GRID_STEP)
	)

	# ♪ 標籤
	var note_lbl         := Label.new()
	note_lbl.text         = "♪"
	note_lbl.add_theme_font_size_override("font_size", 40)
	note_lbl.add_theme_color_override("font_color", Color.WHITE)
	note_lbl.size         = Vector2(GRID_STEP, GRID_STEP)
	note_lbl.position     = Vector2(screen_x - GRID_STEP / 2.0, note_screen_y - GRID_STEP / 2.0)
	note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	note_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_container.add_child(note_lbl)

	# 返回按鈕
	var vp   := get_viewport_rect().size
	var back := Label.new()
	back.text = "< BACK"
	back.add_theme_font_override("font", MENU_FONT)
	back.add_theme_font_size_override("font_size", 28)
	back.add_theme_color_override("font_color", Color.WHITE)
	back.add_theme_constant_override("outline_size", 2)
	back.add_theme_color_override("font_outline_color", Color.BLACK)
	back.size             = Vector2(320.0, 64.0)
	back.position         = Vector2(60.0, vp.y - 110.0)
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	back.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	_setup_container.add_child(back)
	_setup_back_btn_rect = Rect2(Vector2(60.0, vp.y - 110.0), Vector2(320.0, 64.0))

	_update_volume_display()


func _update_volume_display() -> void:
	if _volume_pieces.is_empty():
		return
	for r in range(5):
		var p = _volume_pieces[r]
		if not is_instance_valid(p):
			continue
		if _is_muted or r < (5 - _volume_level):
			p.set_piece_type(1)
			p.modulate = Color(1.0, 1.0, 1.0, 0.30)
		else:
			p.set_piece_type(2)
			p.modulate = Color.WHITE
	if is_instance_valid(_note_piece):
		_note_piece.modulate = Color(1.0, 0.35, 0.35, 1.0) if _is_muted else Color.WHITE


func _apply_volume() -> void:
	if _is_muted or _volume_level == 0:
		AudioServer.set_bus_volume_db(0, -80.0)
	else:
		AudioServer.set_bus_volume_db(0, linear_to_db(float(_volume_level) / 5.0))


func _go_back_from_setup() -> void:
	if is_animating:
		return
	is_animating = true

	# 覆蓋層淡出
	var fade_out = create_tween()
	fade_out.tween_property(_setup_container, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 棋子從上到下縮回 scale 0
	var all_pieces: Array = _volume_pieces.duplicate()
	all_pieces.append(_note_piece)
	var max_disappear := 0.0
	for i in range(all_pieces.size()):
		var p = all_pieces[i]
		if not is_instance_valid(p):
			continue
		var delay: float = i * 0.06
		var st = create_tween()
		st.tween_interval(delay)
		st.tween_callback(_audio.play_drop_reverse)
		st.tween_property(p, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		max_disappear = maxf(max_disappear, delay + 0.14)
	await get_tree().create_timer(max_disappear).timeout

	_destroy_setup_ui()
	for child in piece_container.get_children():
		child.queue_free()
	for child in label_container.get_children():
		child.queue_free()
	await get_tree().process_frame

	# 重新生成 menu 棋子（和初始化一樣從上落下）
	pieces_grid = []
	row_pieces  = [[], [], [], []]
	row_labels  = [[], [], [], []]
	for _c in range(BOARD_SIZE):
		var col := []
		for _r in range(BOARD_SIZE):
			col.append(null)
		pieces_grid.append(col)

	await _spawn_all_pieces()
	_add_menu_labels()
	label_container.show()
	is_animating = false


func _destroy_setup_ui() -> void:
	if is_instance_valid(_setup_container):
		_setup_container.queue_free()
	_setup_container = null
	for p in _volume_pieces:
		if is_instance_valid(p):
			p.queue_free()
	if is_instance_valid(_note_piece):
		_note_piece.queue_free()
	_volume_pieces.clear()
	_volume_rects.clear()
	_note_piece = null
	_setup_back_btn_rect = Rect2()
	_note_rect = Rect2()


func _destroy_rules_ui() -> void:
	if is_instance_valid(_rules_container):
		_rules_container.queue_free()
	_rules_container = null
	_back_btn_rect = Rect2()

func _restore_row(row: int) -> void:
	for p in row_pieces[row]:
		p.modulate = Color.WHITE
		p.set_piece_type(1)
	for l in row_labels[row]:
		l.add_theme_color_override("font_color", Color.WHITE)

func _start_game() -> void:
	for row_arr in row_labels:
		for l in row_arr:
			l.hide()

	_audio.play_rotation()
	_audio.play_drop()

	var rot_tween = create_tween()
	rot_tween.tween_property(board_container, "rotation", TAU * 3.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var fly_tween = create_tween().set_parallel(true)
	for child in piece_container.get_children():
		var outward: Vector2
		if child.position.length() > 5.0:
			outward = child.position.normalized()
		else:
			outward = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

		# 朝外方向混入切向分量，模擬旋轉被甩開的慣性
		var tangent = Vector2(-outward.y, outward.x)
		var dir = (outward + tangent * randf_range(-0.35, 0.35)).normalized()
		dir = dir.rotated(randf_range(-0.25, 0.25))

		var dist  = randf_range(950.0, 1350.0)
		var dur   = randf_range(0.35, 0.70)
		var delay = randf_range(0.0, 0.12)

		fly_tween.tween_property(child, "position", child.position + dir * dist, dur).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# 飛行途中自轉
		fly_tween.tween_property(child, "rotation", child.rotation + randf_range(-TAU * 1.5, TAU * 1.5), dur).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await fly_tween.finished

	rot_tween.kill()
	var n := ceili(board_container.rotation / TAU)
	if n <= 0: n = 1
	var snap = create_tween()
	snap.tween_property(board_container, "rotation", float(n) * TAU, 0.5).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await snap.finished

	if _ai_mode_pending:
		_ai_mode_pending = false
		ai_game_started.emit(_ai_difficulty_pending, _human_player_pending)
	else:
		game_started.emit()


func reinitialize(center: Vector2) -> void:
	CENTER_POS = center
	board_container.position = center
	board_container.rotation = 0.0

	_destroy_rules_ui()
	_destroy_setup_ui()
	_in_difficulty_select = false
	if is_instance_valid(_diff_back_label):
		_diff_back_label.queue_free()
	_diff_back_label = null
	_diff_back_rect  = Rect2()
	_in_color_select = false
	if is_instance_valid(_color_back_label):
		_color_back_label.queue_free()
	_color_back_label    = null
	_color_back_rect     = Rect2()
	_human_player_pending  = 1
	_color_hover_side    = -1
	_color_pressed_side  = -1
	_ai_mode_pending     = false
	hovered_row  = -1
	pressed_row  = -1

	for child in piece_container.get_children():
		child.queue_free()
	for child in label_container.get_children():
		child.queue_free()

	pieces_grid = []
	row_pieces  = [[], [], [], []]
	row_labels  = [[], [], [], []]
	for _c in range(BOARD_SIZE):
		var col := []
		for _r in range(BOARD_SIZE):
			col.append(null)
		pieces_grid.append(col)

	label_container.show()
	is_animating = true
	await _spawn_all_pieces()
	_add_menu_labels()
	is_animating = false


# ── Difficulty selection ──────────────────────────────────────────────────────

func _show_difficulty() -> void:
	_restore_row(3)  # 確保 VS AI 排先還原成黑色再開始掃描
	# 印刷掃描：白＋灰 雙排往上移動
	for wave_row in range(BOARD_SIZE - 1, -1, -1):
		# 兩排後（gray_row + 1）→ 黑色，更新標籤
		var black_row := wave_row + 2
		if black_row < BOARD_SIZE:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][black_row]):
					pieces_grid[col][black_row].set_piece_type(1)
					pieces_grid[col][black_row].modulate = Color.WHITE
			if black_row < 4:
				for col in range(MENU_COLS):
					row_labels[black_row][col].text = DIFF_WORDS[black_row][col]

		# 一排後（前一個白）→ 灰色
		var gray_row := wave_row + 1
		if gray_row < BOARD_SIZE:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][gray_row]):
					pieces_grid[col][gray_row].set_piece_type(2)
					pieces_grid[col][gray_row].modulate = Color(0.68, 0.68, 0.68)

		# 目前這排 → 白色
		for col in range(BOARD_SIZE):
			if is_instance_valid(pieces_grid[col][wave_row]):
				pieces_grid[col][wave_row].set_piece_type(2)
				pieces_grid[col][wave_row].modulate = Color.WHITE
		_audio.play_drop()
		await get_tree().create_timer(0.1).timeout

	# 收尾：row 1 灰→黑（更新標籤），row 0 白→黑（更新標籤）
	for col in range(BOARD_SIZE):
		if is_instance_valid(pieces_grid[col][1]):
			pieces_grid[col][1].set_piece_type(1)
			pieces_grid[col][1].modulate = Color.WHITE
	for col in range(MENU_COLS):
		row_labels[1][col].text = DIFF_WORDS[1][col]

	for col in range(BOARD_SIZE):
		if is_instance_valid(pieces_grid[col][0]):
			pieces_grid[col][0].set_piece_type(1)
			pieces_grid[col][0].modulate = Color.WHITE
	for col in range(MENU_COLS):
		row_labels[0][col].text = DIFF_WORDS[0][col]

	# 左下角 < 返回按鈕
	var vp    := get_viewport_rect().size
	var bw    := vp.x * 0.08
	var bh    := vp.y * 0.10
	var bx    := vp.x * 0.02
	var by    := vp.y - bh - vp.y * 0.03
	_diff_back_label = Label.new()
	_diff_back_label.text = "<"
	_diff_back_label.add_theme_font_override("font", MENU_FONT)
	_diff_back_label.add_theme_font_size_override("font_size", int(vp.y * 0.055))
	_diff_back_label.add_theme_color_override("font_color", Color.WHITE)
	_diff_back_label.add_theme_constant_override("outline_size", 2)
	_diff_back_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_diff_back_label.size                 = Vector2(bw, bh)
	_diff_back_label.position             = Vector2(bx, by)
	_diff_back_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_back_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_diff_back_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	label_container.add_child(_diff_back_label)
	_diff_back_rect = Rect2(Vector2(bx, by), Vector2(bw, bh))

	_in_difficulty_select = true
	is_animating = false


func _go_back_from_difficulty() -> void:
	if is_animating:
		return
	is_animating = true
	_in_difficulty_select = false
	if is_instance_valid(_diff_back_label):
		_diff_back_label.queue_free()
	_diff_back_label = null
	_diff_back_rect  = Rect2()

	# 反向掃描：白＋灰 雙排往下移動
	for wave_row in range(BOARD_SIZE):
		# 兩排前（gray_row - 1）→ 黑色，恢復標籤
		var black_row := wave_row - 2
		if black_row >= 0:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][black_row]):
					pieces_grid[col][black_row].set_piece_type(1)
					pieces_grid[col][black_row].modulate = Color.WHITE
			if black_row < 4:
				for col in range(MENU_COLS):
					row_labels[black_row][col].text = MENU_WORDS[black_row][col]

		# 一排前（前一個白）→ 灰色
		var gray_row := wave_row - 1
		if gray_row >= 0:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][gray_row]):
					pieces_grid[col][gray_row].set_piece_type(2)
					pieces_grid[col][gray_row].modulate = Color(0.68, 0.68, 0.68)

		# 目前這排 → 白色
		for col in range(BOARD_SIZE):
			if is_instance_valid(pieces_grid[col][wave_row]):
				pieces_grid[col][wave_row].set_piece_type(2)
				pieces_grid[col][wave_row].modulate = Color.WHITE
		_audio.play_drop()
		await get_tree().create_timer(0.1).timeout

	# 收尾：row 4 灰→黑，row 5 白→黑
	for col in range(BOARD_SIZE):
		if is_instance_valid(pieces_grid[col][BOARD_SIZE - 2]):
			pieces_grid[col][BOARD_SIZE - 2].set_piece_type(1)
			pieces_grid[col][BOARD_SIZE - 2].modulate = Color.WHITE
	for col in range(BOARD_SIZE):
		if is_instance_valid(pieces_grid[col][BOARD_SIZE - 1]):
			pieces_grid[col][BOARD_SIZE - 1].set_piece_type(1)
			pieces_grid[col][BOARD_SIZE - 1].modulate = Color.WHITE

	# 確保 modulate 與 label 顏色全部還原
	for row in range(4):
		_restore_row(row)

	is_animating = false


# ── Color selection ───────────────────────────────────────────────────────────

func _show_color_select() -> void:
	# 掃描波從最底排往上，最終呈現：
	#   rows 0-2 → 黑色棋子 + COLOR_WORDS 標籤
	#   row  3   → 黑色棋子 + 空白標籤
	#   rows 4-5 → 左半(col 0-2)黑色 / 右半(col 3-5)白色
	for wave_row in range(BOARD_SIZE - 1, -1, -1):
		var black_row := wave_row + 2
		if black_row < BOARD_SIZE:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][black_row]):
					if black_row >= 3:
						pieces_grid[col][black_row].set_piece_type(2 if col >= 3 else 1)
						pieces_grid[col][black_row].modulate = Color.WHITE
					else:
						pieces_grid[col][black_row].set_piece_type(1)
						pieces_grid[col][black_row].modulate = Color(0.45, 0.45, 0.45)
			if black_row < 3:
				for col in range(MENU_COLS):
					row_labels[black_row][col].text = COLOR_WORDS[black_row][col]
			elif black_row == 3:
				for col in range(MENU_COLS):
					row_labels[black_row][col].text = " "

		var gray_row := wave_row + 1
		if gray_row < BOARD_SIZE:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][gray_row]):
					pieces_grid[col][gray_row].set_piece_type(2)
					pieces_grid[col][gray_row].modulate = Color(0.68, 0.68, 0.68)

		for col in range(BOARD_SIZE):
			if is_instance_valid(pieces_grid[col][wave_row]):
				pieces_grid[col][wave_row].set_piece_type(2)
				pieces_grid[col][wave_row].modulate = Color.WHITE
		_audio.play_drop()
		await get_tree().create_timer(0.1).timeout

	# 收尾：row 1 和 row 0
	for row in [1, 0]:
		for col in range(BOARD_SIZE):
			if is_instance_valid(pieces_grid[col][row]):
				pieces_grid[col][row].set_piece_type(1)
				pieces_grid[col][row].modulate = Color(0.45, 0.45, 0.45)
		for col in range(MENU_COLS):
			row_labels[row][col].text = COLOR_WORDS[row][col]

	# 左下角 < 返回按鈕
	var vp  := get_viewport_rect().size
	var bw  := vp.x * 0.08
	var bh  := vp.y * 0.10
	var bx  := vp.x * 0.02
	var by  := vp.y - bh - vp.y * 0.03
	_color_back_label = Label.new()
	_color_back_label.text = "<"
	_color_back_label.add_theme_font_override("font", MENU_FONT)
	_color_back_label.add_theme_font_size_override("font_size", int(vp.y * 0.055))
	_color_back_label.add_theme_color_override("font_color", Color.WHITE)
	_color_back_label.add_theme_constant_override("outline_size", 2)
	_color_back_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_color_back_label.size                 = Vector2(bw, bh)
	_color_back_label.position             = Vector2(bx, by)
	_color_back_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_color_back_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_color_back_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	label_container.add_child(_color_back_label)
	_color_back_rect = Rect2(Vector2(bx, by), Vector2(bw, bh))

	_in_color_select = true
	is_animating     = false


func _set_color_hover(side: int) -> void:
	if _color_hover_side == side:
		return
	_color_hover_side = side
	if side >= 0:
		_audio.play_hover()
	for row in range(3, BOARD_SIZE):
		for col in range(BOARD_SIZE):
			if not is_instance_valid(pieces_grid[col][row]):
				continue
			var this_side := 0 if col < 3 else 1
			if side >= 0 and this_side == side:
				pieces_grid[col][row].modulate = Color(1.32, 1.32, 1.32)
			else:
				pieces_grid[col][row].modulate = Color.WHITE


func _go_back_from_color() -> void:
	if is_animating:
		return
	is_animating        = true
	_in_color_select    = false
	_color_hover_side   = -1
	_color_pressed_side = -1
	if is_instance_valid(_color_back_label):
		_color_back_label.queue_free()
	_color_back_label = null
	_color_back_rect  = Rect2()

	# 反向掃描：白＋灰雙排往下移動，還原回 DIFF_WORDS 狀態
	for wave_row in range(BOARD_SIZE):
		var black_row := wave_row - 2
		if black_row >= 0:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][black_row]):
					pieces_grid[col][black_row].set_piece_type(1)
					pieces_grid[col][black_row].modulate = Color.WHITE
			if black_row < 4:
				for col in range(MENU_COLS):
					row_labels[black_row][col].text = DIFF_WORDS[black_row][col]

		var gray_row := wave_row - 1
		if gray_row >= 0:
			for col in range(BOARD_SIZE):
				if is_instance_valid(pieces_grid[col][gray_row]):
					pieces_grid[col][gray_row].set_piece_type(2)
					pieces_grid[col][gray_row].modulate = Color(0.68, 0.68, 0.68)

		for col in range(BOARD_SIZE):
			if is_instance_valid(pieces_grid[col][wave_row]):
				pieces_grid[col][wave_row].set_piece_type(2)
				pieces_grid[col][wave_row].modulate = Color.WHITE
		_audio.play_drop()
		await get_tree().create_timer(0.1).timeout

	# 收尾：rows 4, 5 → 全部恢復黑色
	for row in [BOARD_SIZE - 2, BOARD_SIZE - 1]:
		for col in range(BOARD_SIZE):
			if is_instance_valid(pieces_grid[col][row]):
				pieces_grid[col][row].set_piece_type(1)
				pieces_grid[col][row].modulate = Color.WHITE

	# 確保 rows 0-3 全部還原 DIFF_WORDS
	for row in range(4):
		_restore_row(row)
		for col in range(MENU_COLS):
			row_labels[row][col].text = DIFF_WORDS[row][col]

	# 重建 < 返回按鈕，進入難度選擇狀態
	var vp  := get_viewport_rect().size
	var bw  := vp.x * 0.08
	var bh  := vp.y * 0.10
	var bx  := vp.x * 0.02
	var by  := vp.y - bh - vp.y * 0.03
	_diff_back_label = Label.new()
	_diff_back_label.text = "<"
	_diff_back_label.add_theme_font_override("font", MENU_FONT)
	_diff_back_label.add_theme_font_size_override("font_size", int(vp.y * 0.055))
	_diff_back_label.add_theme_color_override("font_color", Color.WHITE)
	_diff_back_label.add_theme_constant_override("outline_size", 2)
	_diff_back_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_diff_back_label.size                 = Vector2(bw, bh)
	_diff_back_label.position             = Vector2(bx, by)
	_diff_back_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_back_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_diff_back_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	label_container.add_child(_diff_back_label)
	_diff_back_rect = Rect2(Vector2(bx, by), Vector2(bw, bh))

	_in_difficulty_select = true
	is_animating          = false
