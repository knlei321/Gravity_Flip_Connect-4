extends Node2D

const N        := 8
const STEP_SEC := 0.10

var _head    := 0
var _alphas  := []
var _radius  := 22.0
var _tick_w  := 4.0
var _tick_l  := 10.0
var _color   := Color.WHITE
var _running := false

func start(radius: float, color: Color) -> void:
	_radius = radius
	_tick_w = maxf(3.0, radius * 0.30)
	_tick_l = radius * 0.46
	_color  = color
	_alphas = []
	for i in range(N):
		_alphas.append(0.12)
	_running = true
	_animate()

func _animate() -> void:
	while _running:
		for i in range(N):
			var behind := (_head - i + N) % N
			match behind:
				0: _alphas[i] = 1.0
				1: _alphas[i] = 0.55
				2: _alphas[i] = 0.28
				_: _alphas[i] = 0.12
		_head = (_head + 1) % N
		queue_redraw()
		await get_tree().create_timer(STEP_SEC).timeout

func stop() -> void:
	_running = false

func _draw() -> void:
	for i in range(N):
		var angle := TAU * float(i) / float(N) - PI / 2.0
		var dir   := Vector2(cos(angle), sin(angle))
		var a     := dir * (_radius - _tick_l * 0.5)
		var b     := dir * (_radius + _tick_l * 0.5)
		var c     := _color
		c.a = _alphas[i]
		draw_line(a, b, c, _tick_w)
