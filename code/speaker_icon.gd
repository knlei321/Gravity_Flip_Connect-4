extends Node2D

var _sz := 56.0

func setup(cell_size: float) -> void:
	_sz = cell_size * 5.0
	queue_redraw()

func _draw() -> void:
	var s  := _sz
	var c  := Color.WHITE
	var lw := maxf(1.0, roundf(s * 0.035))

	# Speaker body
	var bh := roundf(s * 0.24)
	var bw := roundf(s * 0.14)
	var bx := -roundf(s * 0.38)
	var by := -roundf(bh * 0.5)
	draw_rect(Rect2(bx, by, bw, bh), c)

	# Cone (trapezoid, opens wider than body)
	var cl  := bx + bw
	var cw  := roundf(s * 0.17)
	var ext := roundf(s * 0.24)
	draw_polygon(PackedVector2Array([
		Vector2(cl,      by),
		Vector2(cl + cw, -ext),
		Vector2(cl + cw,  ext),
		Vector2(cl,      by + bh)
	]), PackedColorArray([c, c, c, c]))

	# 2 sound waves, with gap from cone tip
	var ao  := Vector2(cl, 0.0)
	var ang := deg_to_rad(28)
	draw_arc(ao, cw + roundf(s * 0.22), -ang, ang, 8, c, lw, true)
	draw_arc(ao, cw + roundf(s * 0.38), -ang, ang, 8, c, lw, true)
