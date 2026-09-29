class_name BeliberTheme
extends RefCounted

## Tema oscuro profesional para toda la UI: paneles redondeados,
## botones con hover/pressed, campos de texto y toggles con acento.
## Todo programático con StyleBoxFlat — sin assets externos.

const BG := Color("#14181f")
const PANEL := Color("#1e2530")
const PANEL_HI := Color("#27303d")
const EDGE := Color("#333d4d")
const ACCENT := Color("#4f8cff")
const ACCENT_HI := Color("#6ea3ff")
const TEXT := Color("#e8ecf2")
const TEXT_DIM := Color("#9aa6b8")

## Variantes de tema (accesibilidad): oscuro por defecto, claro y
## alto contraste para visibilidad.
const VARIANTS := {
	"dark": {bg = Color("#14181f"), panel = Color("#1e2530"),
		panel_hi = Color("#27303d"), edge = Color("#333d4d"),
		accent = Color("#4f8cff"), accent_hi = Color("#6ea3ff"),
		text = Color("#e8ecf2"), dim = Color("#9aa6b8")},
	"light": {bg = Color("#eceadf"), panel = Color("#ffffff"),
		panel_hi = Color("#f0ede2"), edge = Color("#c9c2b2"),
		accent = Color("#2b63c9"), accent_hi = Color("#3f77d4"),
		text = Color("#1c2330"), dim = Color("#5a6472")},
	"contrast": {bg = Color("#000000"), panel = Color("#0b0b0b"),
		panel_hi = Color("#1a1a1a"), edge = Color("#f0f0f0"),
		accent = Color("#ffd166"), accent_hi = Color("#ffe08f"),
		text = Color("#ffffff"), dim = Color("#d0d0d0")},
}

static var _v: Dictionary = VARIANTS.dark

static func make(mode := "dark") -> Theme:
	_v = VARIANTS.get(mode, VARIANTS.dark)
	var t := Theme.new()
	var bg: Color = _v.bg
	var panel: Color = _v.panel
	var panel_hi: Color = _v.panel_hi
	var edge: Color = _v.edge
	var accent: Color = _v.accent
	var accent_hi: Color = _v.accent_hi
	var text_c: Color = _v.text
	t.set_color("font_color", "Label", text_c)
	t.set_color("font_color", "Button", text_c)
	t.set_color("font_color", "LineEdit", text_c)
	t.set_color("font_color", "OptionButton", text_c)
	t.set_color("font_color", "CheckBox", text_c)
	t.set_color("font_color", "CheckButton", text_c)
	t.set_color("font_color", "SpinBox", text_c)
	t.set_color("font_hover_color", "Button", accent_hi)
	t.set_color("font_pressed_color", "Button", accent)
	t.set_color("caret_color", "LineEdit", accent)
	t.set_color("font_selected_color", "OptionButton", text_c)
	# paneles y fondos de campos
	t.set_stylebox("panel", "PanelContainer", _panel())
	t.set_stylebox("panel", "PopupPanel", _panel())
	t.set_stylebox("normal", "Button", _box(panel, edge, 6, 1))
	t.set_stylebox("hover", "Button", _box(panel_hi, accent, 6, 1))
	t.set_stylebox("pressed", "Button", _box(panel.darkened(0.2),
		accent, 6, 1))
	t.set_stylebox("focus", "Button", _focus(accent))
	t.set_stylebox("disabled", "Button", _box(panel.darkened(0.15),
		edge, 6, 1))
	t.set_stylebox("normal", "OptionButton", _box(panel, edge, 6, 1))
	t.set_stylebox("hover", "OptionButton", _box(panel_hi, edge, 6, 1))
	t.set_stylebox("pressed", "OptionButton", _box(panel_hi, edge, 6, 1))
	t.set_stylebox("focus", "OptionButton", _focus(accent))
	t.set_stylebox("normal", "LineEdit", _box(panel.darkened(0.3),
		edge, 5, 1))
	t.set_stylebox("focus", "LineEdit", _box(panel.darkened(0.3),
		accent, 5, 1))
	t.set_stylebox("normal", "SpinBox", _box(panel.darkened(0.3),
		edge, 5, 1))
	# checkboxes / toggles
	for cls in ["CheckBox", "CheckButton"]:
		t.set_icon("checked", cls, _check(true))
		t.set_icon("unchecked", cls, _check(false))
		t.set_icon("radio_checked", cls, _check(true))
		t.set_icon("radio_unchecked", cls, _check(false))
	# scrollbars finas
	var sb := _box(panel.lightened(0.15), edge, 3, 0)
	for sbn in ["scroll", "grabber", "grabber_highlight",
			"grabber_pressed"]:
		t.set_stylebox(sbn, "VScrollBar", sb)
		t.set_stylebox(sbn, "HScrollBar", sb)
	t.set_stylebox("background", "VScrollBar", _empty())
	t.set_stylebox("background", "HScrollBar", _empty())
	# sliders
	t.set_stylebox("slider", "HSlider", _box(panel_hi,
		edge, 2, 0))
	t.set_stylebox("grabber_area", "HSlider", _box(accent,
		Color(0, 0, 0, 0), 3, 0))
	# pestañas (TabContainer): seleccionada con acento inferior
	t.set_color("font_selected_color", "TabContainer", text_c)
	t.set_color("font_unselected_color", "TabContainer", _v.dim)
	var sel := _box(panel_hi, edge, 4, 1)
	sel.border_width_bottom = 2
	sel.border_color = accent
	t.set_stylebox("tab_selected", "TabContainer", sel)
	t.set_stylebox("tab_unselected", "TabContainer",
		_box(panel, edge, 4, 1))
	t.set_stylebox("panel", "TabContainer", _empty())
	return t

## Anillo de foco visible (accesibilidad): solo borde, sin fondo.
static func _focus(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = col
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	return s

static func _box(bg: Color, edge: Color, radius: int,
		border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func _panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _v.panel
	s.border_color = _v.edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 8
	return s

static func _empty() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = Color(0, 0, 0, 0)
	return s

## Icono de casilla de verificación dibujado a mano (16x16).
static func _check(on: bool) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 16:
			var border := x in [0, 15] or y in [0, 15]
			img.set_pixel(x, y, _v.edge if border else
				(_v.panel_hi if not on else _v.accent))
	if on:
		# marca de tick
		for i in 3:
			for j in 5:
				img.set_pixel(4 + j, 7 + j + i - 1, Color.WHITE)
			for j in 6:
				img.set_pixel(7 + j, 12 - j + i - 1, Color.WHITE)
	return ImageTexture.create_from_image(img)
