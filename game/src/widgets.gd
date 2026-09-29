class_name Widgets
extends RefCounted

## Biblioteca de componentes reutilizables (patrón React-style:
## un botón primario/secundario/icono compartido en vez de un botón
## ad-hoc por pantalla). Aplica el tema oscuro + microinteracciones.

## Botón primario (acción principal de la pantalla).
static func primary(text: String, h := 48) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	_style_primary(b)
	_juice(b)
	return b

## Botón secundario (acciones normales).
static func secondary(text: String, h := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	_juice(b)
	return b

## Botón de peligro (borrar, rendirse, salir).
static func danger(text: String, h := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_color_override("font_color", Color("#ff6b6b"))
	_juice(b)
	return b

## Label de cabecera de sección.
static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", BeliberTheme.TEXT_DIM)
	return l

## Label genérico: size>0 cambia el tamaño, dim lo atenúa,
## wrap activa el ajuste de línea. Antes cada pantalla tenía su
## propio _lbl() casi idéntico.
static func lbl(text: String, size := 0, dim := false,
		wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0: l.add_theme_font_size_override("font_size", size)
	if dim: l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l

## Pantalla completa con panel centrado (perfil, guía, puzzles).
static func screen(title: String, w := 480) -> Control:
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(w, 0)
	root.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(HSeparator.new())
	Juice.pop_in(root, 0.18)
	return root

## El panel interior (hijos) de una screen.
static func screen_body(scr: Control) -> VBoxContainer:
	return scr.get_child(0)

static func _style_primary(b: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = BeliberTheme.ACCENT
	s.set_corner_radius_all(8)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", s)
	var h := s.duplicate()
	h.bg_color = BeliberTheme.ACCENT_HI
	b.add_theme_stylebox_override("hover", h)
	var p := s.duplicate()
	p.bg_color = BeliberTheme.ACCENT.darkened(0.25)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_font_size_override("font_size", 17)

static func _juice(b: Button) -> void:
	Juice.hover_pop(b)
	Juice.squash(b)
