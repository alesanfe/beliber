class_name Juice
extends RefCounted

## Microinteracciones de UI nativas (equivalente a Godotwind/Juicee
## sin plugins externos): fade-in de paneles, hover con escala,
## scroll suave y toasts animados. Todo Tween — GPU, sin coste.

## Hook de audio: la app asigna `Juice.ui_sfx = _beep` y los
## componentes suenan solos (hover agudo corto, click grave).
static var ui_sfx: Callable = Callable()

static func _snd(freq: float, dur: float) -> void:
	if ui_sfx.is_valid():
		ui_sfx.call(freq, dur)

## Aparición de panel: fade + pop suave (como un modal moderno).
static func pop_in(c: Control, dur := 0.22) -> void:
	c.modulate.a = 0.0
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.92, 0.92)
	var t := c.create_tween().set_parallel()
	t.tween_property(c, "modulate:a", 1.0, dur)
	t.tween_property(c, "scale", Vector2.ONE, dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Desvanecer y eliminar un nodo.
static func fade_out(c: Control, dur := 0.3) -> void:
	var t := c.create_tween()
	t.tween_property(c, "modulate:a", 0.0, dur)
	t.tween_callback(c.queue_free)

## Hover con leve escala + color de acento (botones principales).
static func hover_pop(b: Button, scale_to := 1.04) -> void:
	b.pivot_offset = b.size / 2.0
	b.mouse_entered.connect(func():
		_snd(900.0, 0.03)
		b.create_tween().tween_property(b, "scale",
			Vector2.ONE * scale_to, 0.1) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	b.mouse_exited.connect(func():
		b.create_tween().tween_property(b, "scale",
			Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))

## Press "squash": comprime al pulsar y rebota al soltar.
static func squash(b: Button) -> void:
	b.pivot_offset = b.size / 2.0
	b.button_down.connect(func():
		_snd(600.0, 0.05)
		b.create_tween().tween_property(b, "scale",
			Vector2(0.94, 0.94), 0.06))
	b.button_up.connect(func():
		b.create_tween().tween_property(b, "scale",
			Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

## Toast: aparece con slide+fade y se autodestruye (estilo ProperUI).
static func toast(parent: Control, text: String, dur := 3.5) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate.a = 0.0
	l.position = Vector2(16, -8)
	l.z_index = 20
	l.add_theme_color_override("font_color",
		Color("#e8ecf2"))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "modulate:a", 1.0, 0.15)
	t.tween_property(l, "position:y", l.position.y - 22, 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(dur)
	t.tween_property(l, "modulate:a", 0.0, 0.4)
	t.tween_callback(l.queue_free)
	return l
