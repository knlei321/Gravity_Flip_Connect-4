extends Node

const MENU_FONT = preload("res://fonts/PressStart2P-Regular.ttf")

var _main: Node
var is_paused := false
var _pause_layer: CanvasLayer = null
var _resume_rect: Rect2  = Rect2()
var _restart_rect: Rect2 = Rect2()
var _menu_rect: Rect2    = Rect2()

func setup(main_node: Node) -> void:
	_main = main_node
	process_mode = Node.PROCESS_MODE_ALWAYS

func cleanup() -> void:
	is_paused = false
	get_tree().paused = false
	_destroy_pause_ui()

func toggle() -> void:
	if is_paused:
		_resume()
	else:
		_show_pause()

func _show_pause() -> void:
	is_paused = true
	get_tree().paused = true
	_main.duck_bgm()
	_create_pause_ui()

func _resume() -> void:
	is_paused = false
	get_tree().paused = false
	_main.unduck_bgm()
	_destroy_pause_ui()

func _input(event: InputEvent) -> void:
	if not is_paused:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_ENTER: _resume()
			KEY_R:                 _on_restart()
			KEY_M:                 _on_menu()
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
		if _resume_rect.has_point(pt):    _resume()
		elif _restart_rect.has_point(pt): _on_restart()
		elif _menu_rect.has_point(pt):    _on_menu()

func _create_pause_ui() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 10
	add_child(_pause_layer)

	var vp: Vector2 = _main.get_viewport_rect().size

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.size = vp
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_layer.add_child(overlay)

	var sz  := int(vp.y * 0.033)
	var h   := vp.y * 0.073
	var w   := vp.x * 0.43
	var gap := vp.y * 0.022
	var items := ["RESUME", "RESTART", "MAIN MENU"]
	var total_h: float = items.size() * h + (items.size() - 1) * gap
	var start_y: float = (vp.y - total_h) / 2.0

	for i in range(items.size()):
		var lbl := Label.new()
		lbl.text = items[i]
		lbl.add_theme_font_override("font", MENU_FONT)
		lbl.add_theme_font_size_override("font_size", sz)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.size                 = Vector2(w, h)
		lbl.position             = Vector2((vp.x - w) / 2.0, start_y + float(i) * (h + gap))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		_pause_layer.add_child(lbl)

		var rect := Rect2(lbl.position, lbl.size)
		match i:
			0: _resume_rect  = rect
			1: _restart_rect = rect
			2: _menu_rect    = rect

func _destroy_pause_ui() -> void:
	if is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
	_pause_layer  = null
	_resume_rect  = Rect2()
	_restart_rect = Rect2()
	_menu_rect    = Rect2()

func _on_restart() -> void:
	is_paused = false
	get_tree().paused = false
	_destroy_pause_ui()
	_main.reset_game()

func _on_menu() -> void:
	is_paused = false
	get_tree().paused = false
	_main.unduck_bgm()
	_destroy_pause_ui()
	_main.return_to_menu()
