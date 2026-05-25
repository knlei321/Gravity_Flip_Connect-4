extends Node2D

var _sz := 56.0

func setup(cell_size: float) -> void:
	_sz = cell_size * 5.0
	queue_redraw()

func _draw() -> void:
	var s   := _sz
	var c   := Color.WHITE
	var rot := deg_to_rad(-30.0)

	# Note head: small tilted oval
	var hx := -s * 0.05
	var hy :=  s * 0.24
	var hw :=  s * 0.18
	var hh :=  s * 0.12
	var n  := 16
	var pts := PackedVector2Array()
	var clr := PackedColorArray()
	for i in range(n):
		var a  := float(i) / float(n) * TAU
		var lx := cos(a) * hw
		var ly := sin(a) * hh
		pts.append(Vector2(
			hx + lx * cos(rot) - ly * sin(rot),
			hy + lx * sin(rot) + ly * cos(rot)
		))
		clr.append(c)
	draw_polygon(pts, clr)

	# Stem: thin, from right edge of head straight up
	var sx := hx + hw * cos(rot) - s * 0.05
	var sw := roundf(s * 0.07)
	var st := hy - s * 0.60
	draw_rect(Rect2(sx, st, sw, hy - st), c)

	# Flag: 5-point hook shape (top → right → curve down → back to stem)
	var fx := sx + sw
	var fy := st
	var fw := s * 0.24
	var fh := s * 0.28
	draw_polygon(PackedVector2Array([
		Vector2(sx,             fy),
		Vector2(fx + fw,        fy + fh * 0.15),
		Vector2(fx + fw * 0.85, fy + fh * 0.52),
		Vector2(sx,             fy + fh * 0.48)
	]), PackedColorArray([c, c, c, c]))
