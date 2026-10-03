class_name Juice
extends RefCounted

## Microinteracciones de UI nativas (equivalente a Godotwind/Juicee
## sin plugins externos): fade-in de paneles, hover con escala,
## scroll suave y toasts animados. Todo Tween — GPU, sin coste.

## Hook de audio: la app asigna `Juice.ui_sfx = _beep` y los
## componentes suenan solos (hover agudo corto, click grave).
static var ui_sfx: Callable = Callable()

## Accesibilidad (WCAG 2.3.3): reduce toda la decoración animada —
## las transiciones se hacen instantáneas y se omite confetti.
## Persistido como ui.reduce_motion; el juego en sí no usa tweens
## para estado (la anim de movimiento tiene su propio selector).
static var reduce := false

static func _snd(freq: float, dur: float) -> void:
	if ui_sfx.is_valid():
		ui_sfx.call(freq, dur)

## Aparición de panel: fade + pop suave (como un modal moderno).
static func pop_in(c: Control, dur := 0.22) -> void:
	if reduce:
		return
	c.modulate.a = 0.0
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.92, 0.92)
	var t := c.create_tween().set_parallel()
	t.tween_property(c, "modulate:a", 1.0, dur)
	t.tween_property(c, "scale", Vector2.ONE, dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Desvanecer y eliminar un nodo.
static func fade_out(c: Control, dur := 0.3) -> void:
	if reduce:
		c.queue_free()
		return
	var t := c.create_tween()
	t.tween_property(c, "modulate:a", 0.0, dur)
	t.tween_callback(c.queue_free)

## Hover con leve escala + color de acento (botones principales).
static func hover_pop(b: Button, scale_to := 1.04) -> void:
	if reduce:
		return
	# pivot en el primer hover: en el hook-up el botón aún no tiene
	# layout y size=(0,0) → la escala salía desde la esquina, no el centro
	b.mouse_entered.connect(func():
		_snd(900.0, 0.03)
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale",
			Vector2.ONE * scale_to, 0.1) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	b.mouse_exited.connect(func():
		b.create_tween().tween_property(b, "scale",
			Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))

## Press "squash": comprime al pulsar y rebota al soltar.
static func squash(b: Button) -> void:
	if reduce:
		return
	b.button_down.connect(func():
		b.pivot_offset = b.size / 2.0
		_snd(600.0, 0.05)
		b.create_tween().tween_property(b, "scale",
			Vector2(0.94, 0.94), 0.06))
	b.button_up.connect(func():
		b.create_tween().tween_property(b, "scale",
			Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

## Toast: aparece con slide+fade y se autodestruye (estilo ProperUI).
## Se apilan por slot: antes todos nacían en (16,24) y se tapaban
## entre sí (alerta de turno + chat + aviso de reloj a la vez).
static var _toast_n := {}            # instance_id del padre -> activos
static func toast(parent: Control, text: String, dur := 3.5) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate.a = 0.0 if not reduce else 1.0
	var pid := parent.get_instance_id()
	var slot := mini(int(_toast_n.get(pid, 0)), 4)
	_toast_n[pid] = slot + 1
	l.tree_exited.connect(func():
		_toast_n[pid] = maxi(0, int(_toast_n.get(pid, 1)) - 1))
	# arranca DENTRO de pantalla (antes y=-8: el toast salía parcial
	# y el slide lo subía aún más fuera — invisible por completo)
	l.position = Vector2(16, 24 + slot * 20)
	l.z_index = 20
	l.add_theme_color_override("font_color",
		Color("#e8ecf2"))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	Tts.say(text)   # lector de pantalla: los toasts son live-regions
	var t := l.create_tween().set_parallel()
	if not reduce:
		t.tween_property(l, "modulate:a", 1.0, 0.15)
	t.tween_property(l, "position:y", l.position.y - 12, 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(dur)
	t.tween_property(l, "modulate:a", 0.0, 0.4)
	t.tween_callback(l.queue_free)
	return l

## Ráfaga de confeti (victoria): N cuadraditos del color ganador que
## caen rotando desde el borde superior del padre.
static func confetti(parent: Control, col: Color, n := 42) -> void:
	var w: float = maxf(parent.size.x, 600.0)
	var h: float = maxf(parent.size.y, 400.0)
	var cols := [col, Color(1, 0.85, 0.2), Color(0.95, 0.95, 1.0)]
	if reduce: return
	for i in n:
		var p := ColorRect.new()
		p.color = cols[i % cols.size()]
		p.size = Vector2(6, 10)
		p.position = Vector2(randf() * w, -12.0)
		p.rotation = randf() * TAU
		parent.add_child(p)
		var t := p.create_tween().set_parallel()
		var dur := 1.4 + randf() * 0.9
		t.tween_property(p, "position:y", h * (0.4 + randf() * 0.5),
			dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(p, "position:x",
			p.position.x + (randf() - 0.5) * 160.0, dur)
		t.tween_property(p, "rotation", p.rotation + randf() * 9.0, dur)
		t.set_parallel(false)
		t.tween_property(p, "modulate:a", 0.0, 0.4)
		t.tween_callback(p.queue_free)
