extends Node2D

var _bar_h := 0.0
var _bar_w := 0.0
var _gap   := 0.0

func setup(btn_h: float) -> void:
	_bar_h = btn_h * 0.48
	_bar_w = btn_h * 0.10
	_gap   = btn_h * 0.20
	queue_redraw()

func _draw() -> void:
	var x1 := -(_bar_w + _gap * 0.5)
	var x2 :=  _gap * 0.5
	var y  := -_bar_h * 0.5
	var o  := 4.0
	draw_rect(Rect2(x1 - o, y - o, _bar_w + o * 2, _bar_h + o * 2), Color.BLACK)
	draw_rect(Rect2(x2 - o, y - o, _bar_w + o * 2, _bar_h + o * 2), Color.BLACK)
	draw_rect(Rect2(x1, y, _bar_w, _bar_h), Color.WHITE)
	draw_rect(Rect2(x2, y, _bar_w, _bar_h), Color.WHITE)
