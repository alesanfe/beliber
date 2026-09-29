class_name EvalBar
extends Control

## Barra de evaluación vertical estilo lichess: arriba el color de J2,
## abajo el de J1; el corte marca la ventaja (frac ∈ [0,1] desde J1).

var frac := 0.5
var col0 := Color(0.3, 0.6, 1.0)     # color J1 (abajo)
var col1 := Color(0.75, 0.15, 0.15)  # color J2 (arriba)

func _init() -> void:
	custom_minimum_size = Vector2(22, 512)

func _draw() -> void:
	var h := size.y
	var split := h * (1.0 - frac)
	draw_rect(Rect2(0, 0, size.x, split), col1)
	draw_rect(Rect2(0, split, size.x, h - split), col0)
	draw_rect(Rect2(0, 0, size.x, h), Color(0, 0, 0, 0.5), false, 1.0)
	# línea media de equilibrio
	draw_line(Vector2(0, h / 2), Vector2(size.x, h / 2),
		Color(1, 1, 1, 0.3), 1.0)
