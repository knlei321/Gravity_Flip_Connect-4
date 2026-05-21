extends Node

const RESET_HOLD_DURATION := 2.0  # 長按幾秒後觸發重置
const RESET_INITIAL_ALPHA := 0.0  # UI 出現時的初始透明度（0.0 全透明 → 1.0 不透明）
const RESET_SHAKE_MAX     := 8.0  # 長按結束時的最大震動幅度（px）
const RESET_FADE_DURATION := 1.5  # UI 從初始透明度淡入到完全不透明所需的秒數
const RESET_LABEL_SIZE    := 40   # "Reseting..." 文字大小（px）

var _main: Node

var space_hold_time  := 0.0
var is_holding_space := false
var _reset_ui_layer  : CanvasLayer = null
var _reset_bar_fill  : ColorRect   = null
var _reset_ui_root   : Control     = null

func setup(main_node: Node) -> void:
	_main = main_node

func cleanup() -> void:
	if not is_holding_space:
		return
	is_holding_space = false
	space_hold_time  = 0.0
	_destroy_reset_ui()
	_restore_shake()

func _process(delta: float) -> void:
	if not is_holding_space:
		return
	if _main.is_animating:
		_restore_shake()
		return
	space_hold_time += delta
	var t := clampf(space_hold_time / RESET_HOLD_DURATION, 0.0, 1.0)
	_update_reset_ui(t)
	_apply_shake(t)
	if space_hold_time >= RESET_HOLD_DURATION:
		is_holding_space = false
		space_hold_time  = 0.0
		_destroy_reset_ui()
		_restore_shake()
		_main.reset_game()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.physical_keycode == KEY_SPACE):
		return
	if event.pressed and not event.echo and not is_holding_space:
		is_holding_space = true
		_create_reset_ui()
	elif not event.pressed and is_holding_space:
		is_holding_space = false
		space_hold_time  = 0.0
		_destroy_reset_ui()
		_restore_shake()

func _create_reset_ui() -> void:
	var board_sprite: Sprite2D = _main.get_node("BoardContainer/bored")
	var grid_half: float  = _main.BOARD_SIZE / 2.0 * _main.GRID_STEP
	var board_half: float = board_sprite.texture.get_size().y * board_sprite.scale.y / 2.0
	var border_mid: float = (grid_half + board_half) / 2.0
	var bar_w: float      = float(_main.BOARD_SIZE * _main.GRID_STEP)
	var bar_h: float      = 12.0
	var cp: Vector2       = _main.CENTER_POS

	_reset_ui_layer       = CanvasLayer.new()
	_reset_ui_layer.layer = 1
	add_child(_reset_ui_layer)

	_reset_ui_root = Control.new()
	_reset_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reset_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_ui_layer.add_child(_reset_ui_root)

	var bar_x := cp.x - bar_w / 2.0
	var bar_y := cp.y + border_mid - bar_h / 2.0

	var bar_border          := ColorRect.new()
	bar_border.color         = Color.BLACK
	bar_border.size          = Vector2(bar_w + 4, bar_h + 4)
	bar_border.position      = Vector2(bar_x - 2, bar_y - 2)
	bar_border.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_reset_ui_root.add_child(bar_border)

	var bar_bg          := ColorRect.new()
	bar_bg.color         = Color(0.15, 0.15, 0.15)
	bar_bg.size          = Vector2(bar_w, bar_h)
	bar_bg.position      = Vector2(bar_x, bar_y)
	bar_bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_reset_ui_root.add_child(bar_bg)

	_reset_bar_fill              = ColorRect.new()
	_reset_bar_fill.color        = Color.WHITE
	_reset_bar_fill.size         = Vector2(0.0, bar_h)
	_reset_bar_fill.position     = Vector2(bar_x, bar_y)
	_reset_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_ui_root.add_child(_reset_bar_fill)

	var lbl_h: float      = RESET_LABEL_SIZE * 1.5  # 容器高度留行距
	var lbl               := Label.new()
	lbl.text               = "Reseting..."
	lbl.add_theme_font_size_override("font_size", RESET_LABEL_SIZE)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.size                 = Vector2(bar_w, lbl_h)
	lbl.position             = Vector2(bar_x, cp.y - board_half - lbl_h / 2.0)  # 中心對齊木紋上緣
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_reset_ui_root.add_child(lbl)

	_reset_ui_root.modulate.a = RESET_INITIAL_ALPHA

func _update_reset_ui(t: float) -> void:
	if not is_instance_valid(_reset_ui_root):
		return
	_reset_ui_root.modulate.a = lerp(RESET_INITIAL_ALPHA, 1.0, minf(space_hold_time / RESET_FADE_DURATION, 1.0))
	if is_instance_valid(_reset_bar_fill):
		_reset_bar_fill.size.x = _main.BOARD_SIZE * _main.GRID_STEP * t

func _apply_shake(t: float) -> void:
	var intensity := t * RESET_SHAKE_MAX
	var offset    := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
	_main.board_container.position = _main.CENTER_POS + offset
	_main.piece_container.position = _main.CENTER_POS + offset

func _restore_shake() -> void:
	_main.board_container.position = _main.CENTER_POS
	_main.piece_container.position = _main.CENTER_POS

func _destroy_reset_ui() -> void:
	if is_instance_valid(_reset_ui_layer):
		_reset_ui_layer.queue_free()
	_reset_ui_layer = null
	_reset_bar_fill = null
	_reset_ui_root  = null
