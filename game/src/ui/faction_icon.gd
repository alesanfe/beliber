class_name FactionIcon
extends Control

## Control que dibuja el emblema de una facción (Icons.draw).

var fid := "humenex"
var col := Color.WHITE

func _init(p_fid := "humenex", p_col := Color.WHITE, s := 28.0) -> void:
	fid = p_fid
	col = p_col
	custom_minimum_size = Vector2(s, s)
	mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	Icons.draw(self, fid, Rect2(Vector2.ZERO, size), col)
