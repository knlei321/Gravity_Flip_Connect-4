extends Node2D

var _is_plus := true
var _sz      := 56.0

func setup(is_plus: bool, cell_size: float) -> void:
	_is_plus = is_plus
	_sz      = cell_size * 0.52
	queue_redraw()

func _draw() -> void:
	var thick := roundf(_sz * 0.24)
	var half  := _sz * 0.5
	var ht   := thick * 0.5
	var vt_h := half - ht

	# Horizontal bar
	draw_rect(Rect2(-half, -ht,  _sz,   thick), Color.WHITE)

	if _is_plus:
		# Top arm
		draw_rect(Rect2(-ht, -half, thick, vt_h), Color.WHITE)
		# Bottom arm
		draw_rect(Rect2(-ht,  ht,   thick, vt_h), Color.WHITE)
