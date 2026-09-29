class_name SmoothScroll
extends ScrollContainer

## Scroll con inercia estilo SmoothScroll: la rueda mueve a un objetivo
## y el contenedor interpola — sensación moderna en menús largos.

var _target := -1.0

func _ready() -> void:
	vertical_scroll_mode = SCROLL_MODE_SHOW_NEVER
	horizontal_scroll_mode = SCROLL_MODE_SHOW_NEVER

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var d := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: d = -70.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: d = 70.0
		if d != 0.0:
			if _target < 0: _target = float(scroll_vertical)
			_target = clampf(_target + d, 0.0,
				get_v_scroll_bar().max_value - size.y)
			accept_event()

func _process(dt: float) -> void:
	if _target < 0: return
	var v := float(scroll_vertical)
	v = lerpf(v, _target, 1.0 - pow(0.0005, dt))
	scroll_vertical = int(round(v))
	if abs(v - _target) < 0.6:
		scroll_vertical = int(round(_target))
		_target = -1.0
