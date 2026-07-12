extends Node2D

signal game_started(time_limit: bool, time_seconds: int, new_rule: bool)
signal ai_game_started(difficulty: int, human_player: int, time_limit: bool, time_seconds: int, new_rule: bool)

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
var _rules_nav_right_rect: Rect2 = Rect2()
var _rules2_nav_left_rect: Rect2 = Rect2()
var _rules_came_from_setup: bool = false

var _setup_container: Node2D = null
var _setup_back_btn_rect: Rect2 = Rect2()
var _volume_level: int = 5
var _is_muted: bool = false
var _volume_pieces: Array = []
var _note_piece: Node = null
var _note_icon:  Node = null
var _volume_rects: Array = []
var _note_rect: Rect2 = Rect2()
var _bgm_volume_level: int   = 5
var _bgm_is_muted:     bool  = false
var _bgm_volume_pieces: Array = []
var _bgm_note_piece:   Node  = null
var _bgm_note_icon:    Node  = null
var _bgm_volume_rects: Array = []
var _bgm_note_rect:    Rect2 = Rect2()
var _time_limit_enabled:  bool       = true
var _time_limit_seconds:  int        = 60
var _time_toggle_piece:   Node       = null
var _time_toggle_rect:    Rect2      = Rect2()
var _timer_toggle_label:  Label      = null
var _time_value_rect:     Rect2      = Rect2()
var _digit_labels:        Array       = []
var _time_minus1_symbol:  Node       = null
var _time_plus1_symbol:   Node       = null
var _time_minus1_rect:    Rect2      = Rect2()
var _time_plus1_rect:     Rect2      = Rect2()
var _time_row1_backing:   Array       = []
var _time_input_layer:    CanvasLayer = null
var _time_input_edit:     LineEdit    = null
var _filler_pieces:       Array       = []
var _piece_natural_scale := Vector2.ZERO
var _question_piece:      Node       = null
var _question_rect:       Rect2      = Rect2()
var _in_rules2:           bool       = false
var _rules2_container:    Node2D     = null
var _rules2_back_rect:    Rect2      = Rect2()

var _new_rule_enabled:     bool  = false
var _new_rule_piece:       Node  = null
var _new_rule_toggle_rect: Rect2 = Rect2()
var _new_rule_label:       Label = null

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
const SAVE_PATH   := "user://settings.cfg"

func _ready() -> void:
	pass  # 由 main.gd 在取得 CENTER_POS 後呼叫 initialize()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_volume_level       = cfg.get_value("audio", "volume_level",     5)
		_is_muted           = cfg.get_value("audio", "muted",           false)
		_bgm_volume_level   = cfg.get_value("audio", "bgm_volume_level", 5)
		_bgm_is_muted       = cfg.get_value("audio", "bgm_muted",        false)
		_time_limit_enabled = cfg.get_value("game",  "time_limit",      true)
		_time_limit_seconds = cfg.get_value("game",  "time_limit_secs", 60)
		_new_rule_enabled   = cfg.get_value("game",  "new_rule",        false)
	_apply_volume()
	_apply_bgm_volume()

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume_level",     _volume_level)
	cfg.set_value("audio", "muted",           _is_muted)
	cfg.set_value("audio", "bgm_volume_level", _bgm_volume_level)
	cfg.set_value("audio", "bgm_muted",        _bgm_is_muted)
	cfg.set_value("game",  "time_limit",      _time_limit_enabled)
	cfg.set_value("game",  "time_limit_secs", _time_limit_seconds)
	cfg.set_value("game",  "new_rule",        _new_rule_enabled)
	cfg.save(SAVE_PATH)

func initialize(center: Vector2) -> void:
	CENTER_POS = center
	board_container.position = center
	piece_container.position = Vector2.ZERO  # 相對於 board_container，不需重設
	_load_settings()

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

# 建立選單通用 Label（白字、黑框 outline 2、垂直置中、忽略滑鼠）
func _make_menu_label(text: String, font_size: int, size: Vector2, pos: Vector2, halign := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", MENU_FONT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.size                 = size
	lbl.position             = pos
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	return lbl

# 左下角「< BACK」按鈕（rules / rules2 / setup 共用），回傳點擊判定 Rect
func _create_back_button(parent: Node) -> Rect2:
	var vp        := get_viewport_rect().size
	var nav_sz    := int(vp.y * 0.033)
	var nav_btn_h := vp.y * 0.10
	var back_x    := vp.x * 0.04
	var back_y    := vp.y - nav_btn_h - vp.y * 0.04
	var back_gap  := nav_sz * 0.4
	parent.add_child(_make_menu_label("<", nav_sz, Vector2(nav_sz + back_gap, nav_btn_h), Vector2(back_x, back_y), HORIZONTAL_ALIGNMENT_LEFT))
	parent.add_child(_make_menu_label("BACK", nav_sz, Vector2(vp.x * 0.20, nav_btn_h), Vector2(back_x + nav_sz + back_gap, back_y), HORIZONTAL_ALIGNMENT_LEFT))
	return Rect2(Vector2(back_x, back_y), Vector2(vp.x * 0.25, nav_btn_h))

# 左下角單一「<」返回鍵（難度/顏色選擇頁共用），回傳 [Label, Rect2]
func _create_corner_back() -> Array:
	var vp := get_viewport_rect().size
	var bw := vp.x * 0.08
	var bh := vp.y * 0.10
	var bx := vp.x * 0.02
	var by := vp.y - bh - vp.y * 0.03
	var lbl := _make_menu_label("<", int(vp.y * 0.055), Vector2(bw, bh), Vector2(bx, by))
	label_container.add_child(lbl)
	return [lbl, Rect2(Vector2(bx, by), Vector2(bw, bh))]

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
		if is_pressed:
			if _back_btn_rect.has_point(pressed_pos):
				_go_back_from_rules()
			elif _rules_nav_right_rect.has_point(pressed_pos):
				_go_to_rules2_from_rules1()
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

	if _in_rules2:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				_go_back_from_rules2()
			return
		var _r2pt    := Vector2.ZERO
		var _r2press := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_r2pt    = event.global_position
			_r2press = true
		elif event is InputEventScreenTouch and event.pressed:
			_r2pt    = event.position
			_r2press = true
		if _r2press:
			if _rules2_back_rect.has_point(_r2pt):
				_go_back_from_rules2()
			elif _rules2_nav_left_rect.has_point(_r2pt):
				_go_to_rules1_from_rules2()
		return

	if _setup_container != null:
		if _time_input_layer != null:
			if event is InputEventKey and event.pressed and not event.echo:
				if event.physical_keycode == KEY_ESCAPE:
					_time_input_layer.queue_free()
					_time_input_layer = null
			return
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
					_volume_level = i + 1
					_is_muted = false
					_update_volume_display()
					_apply_volume()
					_save_settings()
					_audio.play_drop()
					return
			if _note_rect.has_point(pt):
				_is_muted = not _is_muted
				_update_volume_display()
				_apply_volume()
				_save_settings()
				if not _is_muted:
					_audio.play_drop()
				return
			for i in range(_bgm_volume_rects.size()):
				if _bgm_volume_rects[i].has_point(pt):
					_bgm_volume_level = i + 1
					_bgm_is_muted = false
					_update_bgm_volume_display()
					_apply_bgm_volume()
					_save_settings()
					_audio.play_drop()
					return
			if _bgm_note_rect.has_point(pt):
				_bgm_is_muted = not _bgm_is_muted
				_update_bgm_volume_display()
				_apply_bgm_volume()
				_save_settings()
				if not _bgm_is_muted:
					_audio.play_drop()
				return
			if _time_toggle_rect.has_point(pt):
				_time_limit_enabled = not _time_limit_enabled
				_update_time_toggle_display()
				_save_settings()
				_audio.play_drop()
				return
			if _time_minus1_rect.has_point(pt):
				_time_limit_seconds = maxi(1, _time_limit_seconds - 1)
				_update_time_value_display()
				_save_settings()
				_audio.play_drop()
				_pulse_symbol(_time_minus1_symbol)
				return
			if _time_plus1_rect.has_point(pt):
				_time_limit_seconds = mini(999, _time_limit_seconds + 1)
				_update_time_value_display()
				_save_settings()
				_audio.play_drop()
				_pulse_symbol(_time_plus1_symbol)
				return
			if _time_value_rect.has_point(pt):
				_show_time_input()
				return
			if _new_rule_toggle_rect.has_point(pt):
				_new_rule_enabled = not _new_rule_enabled
				_update_new_rule_display()
				_save_settings()
				_audio.play_drop()
				return
			if _question_rect.has_point(pt):
				_audio.play_drop()
				if is_instance_valid(_question_piece):
					var qt := create_tween()
					qt.tween_property(_question_piece, "scale", _piece_natural_scale * 1.35, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					qt.tween_property(_question_piece, "scale", _piece_natural_scale,        0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				await get_tree().create_timer(0.18).timeout
				_show_rules2()
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
	_rules_came_from_setup = false
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
			_rules_container.add_child(_make_menu_label(text, size, Vector2(vp.x, h), Vector2(0.0, cur_y)))
		cur_y += h

	var nav_sz     := int(vp.y * 0.033)
	var nav_btn_w  := vp.x * 0.10
	var nav_btn_h  := vp.y * 0.10
	var nav_margin := vp.x * 0.015
	var nav_btn_y  := CENTER_POS.y + (BOARD_SIZE / 2.0 - 0.5) * GRID_STEP - nav_btn_h * 0.5 + GRID_STEP * 0.30

	_back_btn_rect = _create_back_button(_rules_container)
	_rules_container.add_child(_make_menu_label(">>", nav_sz, Vector2(nav_btn_w, nav_btn_h), Vector2(vp.x - nav_btn_w - nav_margin, nav_btn_y)))
	_rules_nav_right_rect = Rect2(Vector2(vp.x - nav_btn_w - nav_margin, nav_btn_y), Vector2(nav_btn_w, nav_btn_h))


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

	if _rules_came_from_setup:
		_rules_came_from_setup = false
		_setup_container.show()
	else:
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

	# ── 彈出動畫：對角波從左下往右上 wave = col + (BOARD_SIZE-1-row) ──
	var wave_map: Dictionary = _build_setup_wave_map()
	var max_pop := 0.0
	var sorted_waves: Array = wave_map.keys()
	sorted_waves.sort()
	for wv in sorted_waves:
		var delay: float = wv * 0.07
		var wpieces: Array = wave_map[wv]
		for pi in range(wpieces.size()):
			var p = wpieces[pi]
			var is_sym: bool = (p == _time_minus1_symbol or p == _time_plus1_symbol)
			var tgt: Vector2 = Vector2.ONE if is_sym else _piece_natural_scale
			var st = create_tween()
			st.tween_interval(delay)
			if pi == 0:
				st.tween_callback(_audio.play_drop)
			st.tween_property(p, "scale", tgt * 1.2, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			st.tween_property(p, "scale", tgt,        0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
	_bgm_volume_pieces.clear()
	_bgm_volume_rects.clear()
	_filler_pieces.clear()
	_time_row1_backing.clear()
	_digit_labels.clear()

	var vp := get_viewport_rect().size

	# ── Row 5: SFX 音量（水平） ──────────────────────────────────────────
	var r5_ly: float  = (5 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r5c0_lx: float = (0 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r5c0_sx: float = CENTER_POS.x + r5c0_lx
	var r5c0_sy: float = CENTER_POS.y + r5_ly
	_note_piece = PIECE_SCENE.instantiate()
	piece_container.add_child(_note_piece)
	if _piece_natural_scale == Vector2.ZERO:
		_piece_natural_scale = _note_piece.scale
	_note_piece.position = Vector2(r5c0_lx, r5_ly)
	_note_piece.scale    = Vector2.ZERO
	_note_piece.set_piece_type(1)
	_note_rect = Rect2(Vector2(r5c0_sx - GRID_STEP / 2.0, r5c0_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP))
	_note_icon = preload("res://code/speaker_icon.gd").new()
	piece_container.add_child(_note_icon)
	(_note_icon as Node2D).position = Vector2(r5c0_lx, r5_ly)
	(_note_icon as Node2D).scale    = Vector2.ZERO
	_note_icon.call("setup", GRID_STEP)
	for c in range(1, BOARD_SIZE):
		var lx: float = (c - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
		var sx: float = CENTER_POS.x + lx
		var p         := PIECE_SCENE.instantiate()
		piece_container.add_child(p)
		p.position = Vector2(lx, r5_ly)
		p.scale    = Vector2.ZERO
		_volume_pieces.append(p)
		_volume_rects.append(Rect2(Vector2(sx - GRID_STEP / 2.0, r5c0_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP)))

	# ── Row 4: BGM 音量（水平） ──────────────────────────────────────────
	var r4_ly: float  = (4 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r4c0_lx: float = (0 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r4c0_sx: float = CENTER_POS.x + r4c0_lx
	var r4c0_sy: float = CENTER_POS.y + r4_ly
	_bgm_note_piece = PIECE_SCENE.instantiate()
	piece_container.add_child(_bgm_note_piece)
	_bgm_note_piece.position = Vector2(r4c0_lx, r4_ly)
	_bgm_note_piece.scale    = Vector2.ZERO
	_bgm_note_piece.set_piece_type(1)
	_bgm_note_rect = Rect2(Vector2(r4c0_sx - GRID_STEP / 2.0, r4c0_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP))
	_bgm_note_icon = preload("res://code/note_icon.gd").new()
	piece_container.add_child(_bgm_note_icon)
	(_bgm_note_icon as Node2D).position = Vector2(r4c0_lx, r4_ly)
	(_bgm_note_icon as Node2D).scale    = Vector2.ZERO
	_bgm_note_icon.call("setup", GRID_STEP)
	for c in range(1, BOARD_SIZE):
		var lx: float = (c - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
		var sx: float = CENTER_POS.x + lx
		var p         := PIECE_SCENE.instantiate()
		piece_container.add_child(p)
		p.position = Vector2(lx, r4_ly)
		p.scale    = Vector2.ZERO
		_bgm_volume_pieces.append(p)
		_bgm_volume_rects.append(Rect2(Vector2(sx - GRID_STEP / 2.0, r4c0_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP)))

	# ── Row 0: TIMER 標題 + ON/OFF（水平） ──────────────────────────────
	const TIMER_WORD := "TIMER"
	var r0_ly: float = (0 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	# cols 0-4: TIMER 標題
	for c in range(5):
		var lx: float = (c - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
		var sx: float = CENTER_POS.x + lx
		var sy: float = CENTER_POS.y + r0_ly
		var fp        := PIECE_SCENE.instantiate()
		piece_container.add_child(fp)
		fp.position = Vector2(lx, r0_ly)
		fp.scale    = Vector2.ZERO
		fp.set_piece_type(1)
		_filler_pieces.append(fp)
		_setup_container.add_child(_make_menu_label(TIMER_WORD[c], 42, Vector2(GRID_STEP, GRID_STEP), Vector2(sx - GRID_STEP / 2.0, sy - GRID_STEP / 2.0)))
	# col 5: timer ON/OFF 開關
	var r0c5_lx: float = (5 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r0c5_sx: float = CENTER_POS.x + r0c5_lx
	var r0c5_sy: float = CENTER_POS.y + r0_ly
	_time_toggle_piece = PIECE_SCENE.instantiate()
	piece_container.add_child(_time_toggle_piece)
	_time_toggle_piece.position = Vector2(r0c5_lx, r0_ly)
	_time_toggle_piece.scale    = Vector2.ZERO
	_time_toggle_rect = Rect2(Vector2(r0c5_sx - GRID_STEP / 2.0, r0c5_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP))
	_timer_toggle_label = _make_menu_label("", 28, Vector2(GRID_STEP, GRID_STEP), Vector2(r0c5_sx - GRID_STEP / 2.0, r0c5_sy - GRID_STEP / 2.0))
	_setup_container.add_child(_timer_toggle_label)

	# ── Row 1: TIMER 控制 ────────────────────────────────────────────────
	var r1_ly: float  = (1 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r1_sy: float  = CENTER_POS.y + r1_ly
	# col 0: -1 按鈕
	var r1c0_lx: float = (0 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r1c0_sx: float = CENTER_POS.x + r1c0_lx
	var m1_fp          := PIECE_SCENE.instantiate()
	piece_container.add_child(m1_fp)
	m1_fp.position = Vector2(r1c0_lx, r1_ly)
	m1_fp.scale    = Vector2.ZERO
	m1_fp.set_piece_type(1)
	_time_row1_backing.append(m1_fp)
	_time_minus1_symbol = preload("res://code/btn_symbol.gd").new()
	piece_container.add_child(_time_minus1_symbol)
	(_time_minus1_symbol as Node2D).position = Vector2(r1c0_lx, r1_ly)
	_time_minus1_symbol.call("setup", false, GRID_STEP)
	(_time_minus1_symbol as Node2D).scale = Vector2.ZERO
	_time_minus1_rect = Rect2(Vector2(r1c0_sx - GRID_STEP / 2.0, r1_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP))
	# cols 1-3: 數字顯示
	for c in range(1, 4):
		var lx: float = (c - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
		var sx: float = CENTER_POS.x + lx
		var dp        := PIECE_SCENE.instantiate()
		piece_container.add_child(dp)
		dp.position = Vector2(lx, r1_ly)
		dp.scale    = Vector2.ZERO
		dp.set_piece_type(2)
		_time_row1_backing.append(dp)
		var dlbl := _make_menu_label("", 42, Vector2(GRID_STEP, GRID_STEP), Vector2(sx - GRID_STEP / 2.0, r1_sy - GRID_STEP / 2.0))
		dlbl.add_theme_color_override("font_color", Color.BLACK)
		dlbl.add_theme_constant_override("outline_size", 0)
		_setup_container.add_child(dlbl)
		_digit_labels.append(dlbl)
	_time_value_rect = Rect2(
		Vector2(CENTER_POS.x + (1 - BOARD_SIZE / 2.0) * GRID_STEP, r1_sy - GRID_STEP / 2.0),
		Vector2(3.0 * GRID_STEP, GRID_STEP)
	)
	# col 4: +1 按鈕
	var r1c4_lx: float = (4 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r1c4_sx: float = CENTER_POS.x + r1c4_lx
	var p1_fp          := PIECE_SCENE.instantiate()
	piece_container.add_child(p1_fp)
	p1_fp.position = Vector2(r1c4_lx, r1_ly)
	p1_fp.scale    = Vector2.ZERO
	p1_fp.set_piece_type(1)
	_time_row1_backing.append(p1_fp)
	_time_plus1_symbol = preload("res://code/btn_symbol.gd").new()
	piece_container.add_child(_time_plus1_symbol)
	(_time_plus1_symbol as Node2D).position = Vector2(r1c4_lx, r1_ly)
	_time_plus1_symbol.call("setup", true, GRID_STEP)
	(_time_plus1_symbol as Node2D).scale = Vector2.ZERO
	_time_plus1_rect = Rect2(Vector2(r1c4_sx - GRID_STEP / 2.0, r1_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP))
	# col 5: 空白填充
	var r1c5_lx: float = (5 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r1c5_fp        := PIECE_SCENE.instantiate()
	piece_container.add_child(r1c5_fp)
	r1c5_fp.position = Vector2(r1c5_lx, r1_ly)
	r1c5_fp.scale    = Vector2.ZERO
	r1c5_fp.set_piece_type(1)
	_filler_pieces.append(r1c5_fp)

	# ── Row 2: EXTRA 標題（水平） ────────────────────────────────────────
	const EXTRA_WORD := "EXTRA"
	var r2_ly: float = (2 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	for c in range(5):
		var lx: float = (c - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
		var sx: float = CENTER_POS.x + lx
		var sy: float = CENTER_POS.y + r2_ly
		var fp        := PIECE_SCENE.instantiate()
		piece_container.add_child(fp)
		fp.position = Vector2(lx, r2_ly)
		fp.scale    = Vector2.ZERO
		fp.set_piece_type(1)
		_filler_pieces.append(fp)
		_setup_container.add_child(_make_menu_label(EXTRA_WORD[c], 42, Vector2(GRID_STEP, GRID_STEP), Vector2(sx - GRID_STEP / 2.0, sy - GRID_STEP / 2.0)))
	# col 5: EXTRA ON/OFF 開關
	var r2c5_lx: float = (5 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r2c5_sx: float = CENTER_POS.x + r2c5_lx
	var r2c5_sy: float = CENTER_POS.y + r2_ly
	_new_rule_piece = PIECE_SCENE.instantiate()
	piece_container.add_child(_new_rule_piece)
	_new_rule_piece.position = Vector2(r2c5_lx, r2_ly)
	_new_rule_piece.scale    = Vector2.ZERO
	_new_rule_toggle_rect = Rect2(Vector2(r2c5_sx - GRID_STEP / 2.0, r2c5_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP))
	_new_rule_label = _make_menu_label("", 28, Vector2(GRID_STEP, GRID_STEP), Vector2(r2c5_sx - GRID_STEP / 2.0, r2c5_sy - GRID_STEP / 2.0))
	_setup_container.add_child(_new_rule_label)

	# ── Row 3: 空白填充 + ? ───────────────────────────────────────────────
	var r3_ly: float = (3 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r3_sy: float = CENTER_POS.y + r3_ly
	# cols 0-4: 空白填充
	for c in range(5):
		var lx: float = (c - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
		var fp        := PIECE_SCENE.instantiate()
		piece_container.add_child(fp)
		fp.position = Vector2(lx, r3_ly)
		fp.scale    = Vector2.ZERO
		fp.set_piece_type(1)
		_filler_pieces.append(fp)
	var r3c5_lx: float = (5 - BOARD_SIZE / 2.0 + 0.5) * GRID_STEP
	var r3c5_sx: float = CENTER_POS.x + r3c5_lx
	_question_piece = PIECE_SCENE.instantiate()
	piece_container.add_child(_question_piece)
	_question_piece.position = Vector2(r3c5_lx, r3_ly)
	_question_piece.scale    = Vector2.ZERO
	_question_piece.set_piece_type(2)
	_question_rect = Rect2(Vector2(r3c5_sx - GRID_STEP / 2.0, r3_sy - GRID_STEP / 2.0), Vector2(GRID_STEP, GRID_STEP))
	var q_lbl := _make_menu_label("?", 42, Vector2(GRID_STEP, GRID_STEP), Vector2(r3c5_sx - GRID_STEP / 2.0, r3_sy - GRID_STEP / 2.0))
	q_lbl.add_theme_color_override("font_color", Color.BLACK)
	q_lbl.add_theme_constant_override("outline_size", 0)
	_setup_container.add_child(q_lbl)

	# ── 返回按鈕 ─────────────────────────────────────────────────────────
	_setup_back_btn_rect = _create_back_button(_setup_container)

	_update_volume_display()
	_update_bgm_volume_display()
	_update_time_toggle_display()
	_update_new_rule_display()


func _update_time_toggle_display() -> void:
	if not is_instance_valid(_time_toggle_piece): return
	if _time_limit_enabled:
		_time_toggle_piece.set_piece_type(2)
		_time_toggle_piece.modulate = Color.WHITE
	else:
		_time_toggle_piece.set_piece_type(1)
		_time_toggle_piece.modulate = Color.WHITE
	if is_instance_valid(_timer_toggle_label):
		_timer_toggle_label.text = "ON" if _time_limit_enabled else "OFF"
		_timer_toggle_label.add_theme_color_override("font_color",
			Color.BLACK if _time_limit_enabled else Color.WHITE)
	_update_time_value_display()


func _update_new_rule_display() -> void:
	if not is_instance_valid(_new_rule_piece): return
	_new_rule_piece.set_piece_type(2 if _new_rule_enabled else 1)
	_new_rule_piece.modulate = Color.WHITE
	if is_instance_valid(_new_rule_label):
		_new_rule_label.text = "ON" if _new_rule_enabled else "OFF"
		_new_rule_label.add_theme_color_override("font_color",
			Color.BLACK if _new_rule_enabled else Color.WHITE)


func _update_time_value_display() -> void:
	if _digit_labels.is_empty(): return
	var s := str(_time_limit_seconds)
	var chars := ["", "", ""]
	for i in range(s.length()):
		chars[3 - s.length() + i] = s[i]
	for i in range(3):
		_digit_labels[i].text = chars[i]
	var alpha := 1.0 if _time_limit_enabled else 0.30
	for dlbl in _digit_labels:
		dlbl.modulate.a = alpha
	for bp in _time_row1_backing:
		if is_instance_valid(bp):
			bp.modulate.a = alpha
	if is_instance_valid(_time_minus1_symbol):
		_time_minus1_symbol.modulate.a = alpha
	if is_instance_valid(_time_plus1_symbol):
		_time_plus1_symbol.modulate.a = alpha


func _show_time_input() -> void:
	if _time_input_layer != null: return
	_time_input_layer = CanvasLayer.new()
	_time_input_layer.layer = 20
	add_child(_time_input_layer)
	var vp := get_viewport_rect().size
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.size  = vp
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_time_input_layer.add_child(overlay)
	# 延遲到下一 frame 再 connect，避免建立 overlay 的同一個 click 立刻把它關掉
	get_tree().process_frame.connect(func():
		if not is_instance_valid(overlay): return
		overlay.gui_input.connect(func(ev: InputEvent) -> void:
			var fired: bool = (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed) \
						   or (ev is InputEventScreenTouch and ev.pressed)
			if fired and _time_input_edit != null:
				_apply_time_input(_time_input_edit.text)
		)
	, CONNECT_ONE_SHOT)
	var pw  := vp.x * 0.48
	var ph  := vp.y * 0.32
	var px  := (vp.x - pw) / 2.0
	var py  := (vp.y - ph) / 2.0
	var prompt := Label.new()
	prompt.text = "ENTER SECONDS"
	prompt.add_theme_font_override("font", MENU_FONT)
	prompt.add_theme_font_size_override("font_size", int(vp.y * 0.027))
	prompt.add_theme_color_override("font_color", Color.WHITE)
	prompt.add_theme_constant_override("outline_size", 2)
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.size                 = Vector2(pw, ph * 0.35)
	prompt.position             = Vector2(px, py)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_time_input_layer.add_child(prompt)
	var le := LineEdit.new()
	le.text       = str(_time_limit_seconds)
	le.max_length = 3
	le.size       = Vector2(pw, ph * 0.40)
	le.position   = Vector2(px, py + ph * 0.38)
	le.add_theme_font_override("font", MENU_FONT)
	le.add_theme_font_size_override("font_size", int(vp.y * 0.065))
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_input_layer.add_child(le)
	_time_input_edit = le
	le.grab_focus()
	le.select_all()
	le.text_submitted.connect(_apply_time_input)
	var hint := Label.new()
	hint.text = "ENTER: OK   ESC: CANCEL"
	hint.add_theme_font_override("font", MENU_FONT)
	hint.add_theme_font_size_override("font_size", int(vp.y * 0.018))
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	hint.size                 = Vector2(pw, ph * 0.22)
	hint.position             = Vector2(px, py + ph * 0.78)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_time_input_layer.add_child(hint)


func _apply_time_input(text: String) -> void:
	if _time_input_layer == null: return
	var val := text.strip_edges().to_int()
	if val >= 1 and val <= 999:
		_time_limit_seconds = val
		_update_time_value_display()
		_save_settings()
	_time_input_layer.queue_free()
	_time_input_layer = null
	_time_input_edit  = null


func _update_volume_display() -> void:
	if _volume_pieces.is_empty():
		return
	for i in range(5):
		var p = _volume_pieces[i]
		if not is_instance_valid(p):
			continue
		if _is_muted or i >= _volume_level:
			p.set_piece_type(1)
			p.modulate = Color(1.0, 1.0, 1.0, 0.30)
		else:
			p.set_piece_type(2)
			p.modulate = Color.WHITE
	if is_instance_valid(_note_piece):
		_note_piece.modulate = Color(1.0, 0.35, 0.35, 1.0) if _is_muted else Color.WHITE
	if is_instance_valid(_note_icon):
		_note_icon.modulate = Color(1.0, 0.35, 0.35, 1.0) if _is_muted else Color.WHITE


func _apply_volume() -> void:
	var bus_idx := AudioServer.get_bus_index("SFX")
	if bus_idx < 0:
		return
	if _is_muted or _volume_level == 0:
		AudioServer.set_bus_volume_db(bus_idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(bus_idx, 5.5 - float(5 - _volume_level) * 4.5)


func _update_bgm_volume_display() -> void:
	if _bgm_volume_pieces.is_empty():
		return
	for i in range(5):
		var p = _bgm_volume_pieces[i]
		if not is_instance_valid(p):
			continue
		if _bgm_is_muted or i >= _bgm_volume_level:
			p.set_piece_type(1)
			p.modulate = Color(1.0, 1.0, 1.0, 0.30)
		else:
			p.set_piece_type(2)
			p.modulate = Color.WHITE
	if is_instance_valid(_bgm_note_piece):
		_bgm_note_piece.modulate = Color(1.0, 0.35, 0.35, 1.0) if _bgm_is_muted else Color.WHITE
	if is_instance_valid(_bgm_note_icon):
		_bgm_note_icon.modulate  = Color(1.0, 0.35, 0.35, 1.0) if _bgm_is_muted else Color.WHITE


func _apply_bgm_volume() -> void:
	var bus_idx := AudioServer.get_bus_index("BGM")
	if bus_idx < 0:
		return
	if _bgm_is_muted or _bgm_volume_level == 0:
		AudioServer.set_bus_volume_db(bus_idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(bus_idx, -9.0 - float(5 - _bgm_volume_level) * 5.0)

func _pulse_symbol(sym: Node) -> void:
	if not is_instance_valid(sym): return
	var t := create_tween()
	t.tween_property(sym, "scale", Vector2.ONE * 1.35, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(sym, "scale", Vector2.ONE,        0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _go_back_from_setup() -> void:
	if is_animating:
		return
	is_animating = true
	_audio.play_drop_reverse()

	# 覆蓋層淡出
	var fade_out = create_tween()
	fade_out.tween_property(_setup_container, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 縮回動畫：對角波從右上往左下 wave = col + (BOARD_SIZE-1-row)，delay 反轉
	var wave_map2: Dictionary = _build_setup_wave_map()
	var sorted_w2: Array = wave_map2.keys()
	sorted_w2.sort()
	var max_wave2: int = sorted_w2[-1]
	var max_disappear := 0.0
	for wv in sorted_w2:
		var delay: float = (max_wave2 - wv) * 0.06
		var wpieces: Array = wave_map2[wv]
		for pi in range(wpieces.size()):
			var p = wpieces[pi]
			if not is_instance_valid(p): continue
			var st = create_tween()
			st.tween_interval(delay)
			if pi == 0 and wv != max_wave2:
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
	if is_instance_valid(_note_icon):
		_note_icon.queue_free()
	for p in _bgm_volume_pieces:
		if is_instance_valid(p):
			p.queue_free()
	if is_instance_valid(_bgm_note_piece):
		_bgm_note_piece.queue_free()
	if is_instance_valid(_bgm_note_icon):
		_bgm_note_icon.queue_free()
	_volume_pieces.clear()
	_volume_rects.clear()
	_bgm_volume_pieces.clear()
	_bgm_volume_rects.clear()
	_note_piece     = null
	_note_icon      = null
	_bgm_note_piece = null
	_bgm_note_icon  = null
	_bgm_note_rect  = Rect2()
	_setup_back_btn_rect = Rect2()
	_note_rect           = Rect2()
	if is_instance_valid(_time_toggle_piece):
		_time_toggle_piece.queue_free()
	_time_toggle_piece  = null
	_time_toggle_rect   = Rect2()
	_timer_toggle_label = null
	_filler_pieces.clear()
	_time_row1_backing.clear()
	_digit_labels.clear()
	_time_minus1_symbol = null
	_time_plus1_symbol  = null
	_time_value_rect    = Rect2()
	_time_minus1_rect   = Rect2()
	_time_plus1_rect    = Rect2()
	if is_instance_valid(_time_input_layer):
		_time_input_layer.queue_free()
	_time_input_layer     = null
	_new_rule_piece        = null
	_new_rule_toggle_rect  = Rect2()
	_new_rule_label        = null
	_question_piece = null
	_question_rect  = Rect2()


func _build_setup_wave_map() -> Dictionary:
	var m: Dictionary = {}
	# Row 5: col0=w0 (speaker/note), cols1-5=w1-5 (SFX)
	m[0] = [_note_piece]
	if is_instance_valid(_note_icon): m[0].append(_note_icon)
	for i in range(5):
		var w: int = i + 1
		if not m.has(w): m[w] = []
		m[w].append(_volume_pieces[i])
	# Row 4: col0=w1 (BGM note), cols1-5=w2-6 (BGM)
	if not m.has(1): m[1] = []
	m[1].append(_bgm_note_piece)
	if is_instance_valid(_bgm_note_icon): m[1].append(_bgm_note_icon)
	for i in range(5):
		var w: int = i + 2
		if not m.has(w): m[w] = []
		m[w].append(_bgm_volume_pieces[i])
	# Row 3: cols0-4=w2-6 (filler[11-15]), col5=w7 (?)
	if not m.has(2): m[2] = []
	m[2].append(_filler_pieces[11])
	for i in range(4):
		var w: int = i + 3
		if not m.has(w): m[w] = []
		m[w].append(_filler_pieces[12 + i])
	if not m.has(7): m[7] = []
	m[7].append(_question_piece)
	# Row 2: cols0-4=w3-7 (filler[6-10]), col5=w8 (EXTRA toggle)
	for i in range(5):
		var w: int = i + 3
		if not m.has(w): m[w] = []
		m[w].append(_filler_pieces[6 + i])
	if not m.has(8): m[8] = []
	m[8].append(_new_rule_piece)
	# Row 1: col0=w4 (-1), cols1-3=w5-7 (digits), col4=w8 (+1), col5=w9 (filler[5])
	if not m.has(4): m[4] = []
	m[4].append(_time_row1_backing[0])
	if is_instance_valid(_time_minus1_symbol): m[4].append(_time_minus1_symbol)
	for i in range(3):
		var w: int = i + 5
		if not m.has(w): m[w] = []
		m[w].append(_time_row1_backing[1 + i])
	if not m.has(8): m[8] = []
	m[8].append(_time_row1_backing[4])
	if is_instance_valid(_time_plus1_symbol): m[8].append(_time_plus1_symbol)
	if not m.has(9): m[9] = []
	m[9].append(_filler_pieces[5])
	# Row 0: cols0-4=w5-9 (filler[0-4]), col5=w10 (TIMER toggle)
	for i in range(5):
		var w: int = i + 5
		if not m.has(w): m[w] = []
		m[w].append(_filler_pieces[i])
	if not m.has(10): m[10] = []
	m[10].append(_time_toggle_piece)
	return m


func _show_rules2() -> void:
	if _in_rules2 or is_animating:
		return
	is_animating = true
	_in_rules2             = true
	_rules_came_from_setup = true

	var dur    := 0.75
	var exit_x := CENTER_POS.x + 1500.0
	_audio.play_rotation(dur)

	_setup_container.hide()

	var slide = create_tween().set_parallel(true)
	slide.tween_property(board_container, "position:x", exit_x, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slide.tween_property(board_container, "rotation", board_container.rotation + TAU * 1.5, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await slide.finished

	_create_rules2_ui()
	var fade_in = create_tween()
	fade_in.tween_property(_rules2_container, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished
	is_animating = false


func _create_rules2_ui() -> void:
	_rules2_container = Node2D.new()
	_rules2_container.modulate.a = 0.0
	add_child(_rules2_container)

	var vp := get_viewport_rect().size

	const HEADING_SIZE := 50
	const BODY_SIZE    := 20
	const HEAD_H       := HEADING_SIZE * 1.6
	const LINE_H       := BODY_SIZE    * 2.8
	const BLANK_SM     := BODY_SIZE    * 1.2
	const BLANK_LG     := BODY_SIZE    * 2.0

	var lines: Array = [
		["EXTRA RULE",                                HEADING_SIZE, HEAD_H  ],
		["LAST CHANCE",                               HEADING_SIZE, HEAD_H  ],
		["",                                          0,            BLANK_SM],
		["When Black connects 4 by placing a piece,", BODY_SIZE,   LINE_H  ],
		["White may place one final piece.",          BODY_SIZE,   LINE_H  ],
		["",                                          0,            BLANK_LG],
		["If White connects 4 -> White wins.",        BODY_SIZE,   LINE_H  ],
		["If White cannot connect 4 -> Black wins.",  BODY_SIZE,   LINE_H  ],
		["",                                          0,            BLANK_LG],
		["Note: This rule does not apply",            BODY_SIZE,   LINE_H  ],
		["if 4-in-a-row is formed after rotation.",   BODY_SIZE,   LINE_H  ],
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
			_rules2_container.add_child(_make_menu_label(text, size, Vector2(vp.x, h), Vector2(0.0, cur_y)))
		cur_y += h

	var nav_sz     := int(vp.y * 0.033)
	var nav_btn_w  := vp.x * 0.10
	var nav_btn_h  := vp.y * 0.10
	var nav_margin := vp.x * 0.015
	var nav_btn_y  := CENTER_POS.y + (BOARD_SIZE / 2.0 - 0.5) * GRID_STEP - nav_btn_h * 0.5 + GRID_STEP * 0.30

	_rules2_back_rect = _create_back_button(_rules2_container)
	_rules2_container.add_child(_make_menu_label("<<", nav_sz, Vector2(nav_btn_w, nav_btn_h), Vector2(nav_margin, nav_btn_y)))
	_rules2_nav_left_rect = Rect2(Vector2(nav_margin, nav_btn_y), Vector2(nav_btn_w, nav_btn_h))


func _go_back_from_rules2() -> void:
	if is_animating:
		return
	is_animating = true
	_in_rules2   = false

	var fade_out = create_tween()
	fade_out.tween_property(_rules2_container, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished

	if is_instance_valid(_rules2_container):
		_rules2_container.queue_free()
	_rules2_container     = null
	_rules2_back_rect     = Rect2()
	_rules2_nav_left_rect = Rect2()

	var dur := 0.75
	_audio.play_rotation(dur)

	var slide = create_tween().set_parallel(true)
	slide.tween_property(board_container, "position:x", CENTER_POS.x, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slide.tween_property(board_container, "rotation", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await slide.finished

	if _rules_came_from_setup:
		_setup_container.show()
	else:
		_restore_row(1)
		label_container.show()
	is_animating = false


func _go_to_rules2_from_rules1() -> void:
	if is_animating:
		return
	is_animating = true

	var fade_out = create_tween()
	fade_out.tween_property(_rules_container, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished

	_destroy_rules_ui()
	_in_rules2 = true
	_create_rules2_ui()

	var fade_in = create_tween()
	fade_in.tween_property(_rules2_container, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished
	is_animating = false


func _go_to_rules1_from_rules2() -> void:
	if is_animating:
		return
	is_animating = true

	var fade_out = create_tween()
	fade_out.tween_property(_rules2_container, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished

	if is_instance_valid(_rules2_container):
		_rules2_container.queue_free()
	_rules2_container     = null
	_rules2_back_rect     = Rect2()
	_rules2_nav_left_rect = Rect2()
	_in_rules2 = false

	_create_rules_ui()

	var fade_in = create_tween()
	fade_in.tween_property(_rules_container, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished
	is_animating = false


func _destroy_rules_ui() -> void:
	if is_instance_valid(_rules_container):
		_rules_container.queue_free()
	_rules_container      = null
	_back_btn_rect        = Rect2()
	_rules_nav_right_rect = Rect2()

func _restore_row(row: int) -> void:
	for p in row_pieces[row]:
		if not is_instance_valid(p): continue
		p.modulate = Color.WHITE
		p.set_piece_type(1)
	for l in row_labels[row]:
		if not is_instance_valid(l): continue
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
		ai_game_started.emit(_ai_difficulty_pending, _human_player_pending, _time_limit_enabled, _time_limit_seconds, _new_rule_enabled)
	else:
		game_started.emit(_time_limit_enabled, _time_limit_seconds, _new_rule_enabled)


func reinitialize(center: Vector2) -> void:
	CENTER_POS = center
	board_container.position = center
	board_container.rotation = 0.0

	_destroy_rules_ui()
	_destroy_setup_ui()
	if is_instance_valid(_rules2_container):
		_rules2_container.queue_free()
	_rules2_container = null
	_rules2_back_rect = Rect2()
	_in_rules2 = false
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
	var back := _create_corner_back()
	_diff_back_label = back[0]
	_diff_back_rect  = back[1]

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
					row_labels[black_row][col].add_theme_color_override("font_color", Color.WHITE)
			elif black_row == 3:
				for col in range(MENU_COLS):
					row_labels[black_row][col].text = " "
					row_labels[black_row][col].add_theme_color_override("font_color", Color.WHITE)

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
			row_labels[row][col].add_theme_color_override("font_color", Color.WHITE)

	# 左下角 < 返回按鈕
	var back := _create_corner_back()
	_color_back_label = back[0]
	_color_back_rect  = back[1]

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
	var back := _create_corner_back()
	_diff_back_label = back[0]
	_diff_back_rect  = back[1]

	_in_difficulty_select = true
	is_animating          = false
