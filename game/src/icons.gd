class_name Icons
extends RefCounted

## Emblemas de facción dibujados por código (sin assets externos).
## Formas geométricas distintivas por facción dentro de un rect.

static func draw(cv: CanvasItem, fid: String, r: Rect2,
		col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.44
	match fid:
		"humenex":   _crown(cv, c, s, col)
		"elfos":     _leaf(cv, c, s, col)
		"mortifers": _skull(cv, c, s, col)
		"bestiarios": _paw(cv, c, s, col)
		"enanos":    _hammer(cv, c, s, col)
		"chlontos":  _hex(cv, c, s, col)
		"aquontes":  _drop(cv, c, s, col)
		"kronturs":  _peaks(cv, c, s, col)
		_:           cv.draw_circle(c, s * 0.5, col)

## Corona de tres puntas (Humenex — realeza clásica).
static func _crown(cv: CanvasItem, c: Vector2, s: float,
		col: Color) -> void:
	var p := PackedVector2Array([
		c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.35),
		c + Vector2(-s * 0.5, s * 0.05), c + Vector2(0, -s * 0.6),
		c + Vector2(s * 0.5, s * 0.05), c + Vector2(s, -s * 0.35),
		c + Vector2(s, s * 0.6)])
	cv.draw_colored_polygon(p, col)
	cv.draw_rect(Rect2(c + Vector2(-s, s * 0.6), Vector2(s * 2, s * 0.25)), col)

## Hoja (Elfos): elipse rotada + nervadura.
static func _leaf(cv: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * s * 0.55, sin(a) * s).rotated(-PI / 4) + c)
	cv.draw_colored_polygon(pts, col)
	cv.draw_line(c + Vector2(s * 0.5, -s * 0.5) * -1,
		c + Vector2(s * 0.62, s * 0.62), col.lightened(0.3), 2.0)

## Cráneo (Mortifers): cráneo + mandíbula + ojos.
static func _skull(cv: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	cv.draw_circle(c + Vector2(0, -s * 0.15), s * 0.7, col)
	cv.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.15),
		Vector2(s * 0.8, s * 0.55)), col)
	cv.draw_circle(c + Vector2(-s * 0.28, -s * 0.15), s * 0.16, Color.BLACK)
	cv.draw_circle(c + Vector2(s * 0.28, -s * 0.15), s * 0.16, Color.BLACK)

## Garra/pata (Bestiarios): almohadilla + tres garras.
static func _paw(cv: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	cv.draw_circle(c + Vector2(0, s * 0.25), s * 0.5, col)
	for dx in [-0.55, 0.0, 0.55]:
		cv.draw_circle(c + Vector2(s * dx, -s * 0.35), s * 0.22, col)

## Martillo (Enanos): cabeza + mango.
static func _hammer(cv: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	cv.draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.6),
		Vector2(s * 1.4, s * 0.55)), col)
	cv.draw_rect(Rect2(c + Vector2(-s * 0.15, -s * 0.05),
		Vector2(s * 0.3, s * 0.9)), col.darkened(0.2))

## Hexágono (Chlontos): núcleo de colmena.
static func _hex(cv: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + TAU * i / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * s * 0.9)
	cv.draw_colored_polygon(pts, col)
	cv.draw_circle(c, s * 0.28, col.darkened(0.4))

## Gota (Aquontes): lágrima — círculo + punta.
static func _drop(cv: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	cv.draw_circle(c + Vector2(0, s * 0.2), s * 0.55, col)
	var pts := PackedVector2Array([
		c + Vector2(0, -s * 0.9),
		c + Vector2(-s * 0.52, s * 0.15),
		c + Vector2(s * 0.52, s * 0.15)])
	cv.draw_colored_polygon(pts, col)

## Picos (Kronturs): dos montañas.
static func _peaks(cv: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	cv.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s, s * 0.6), c + Vector2(-s * 0.35, -s * 0.5),
		c + Vector2(s * 0.1, s * 0.6)]), col)
	cv.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s * 0.1, s * 0.6), c + Vector2(s * 0.45, -s * 0.7),
		c + Vector2(s, s * 0.6)]), col.lightened(0.15))

## ===== Iconos genéricos de interfaz (estilo Lucide, dibujados) =====
## kind: "swords","gear","chat","trophy","flag","undo","hint","puzzle",
##       "book","bolt","back","clock"
static func draw_ui(cv: CanvasItem, kind: String, r: Rect2,
		col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.42
	match kind:
		"swords":   # dos espadas cruzadas
			cv.draw_line(c + Vector2(-s, -s), c + Vector2(s, s) * 0.9,
				col, s * 0.22)
			cv.draw_line(c + Vector2(s, -s), c + Vector2(-s, s) * 0.9,
				col, s * 0.22)
			cv.draw_line(c + Vector2(-s * 0.35, s * 0.55),
				c + Vector2(-s * 0.7, s * 0.9), col.darkened(0.3), s * 0.2)
		"gear":     # anillo + 8 dientes
			cv.draw_arc(c, s * 0.55, 0, TAU, 16, col, s * 0.28)
			for i in 8:
				var a := TAU * i / 8.0
				cv.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.7,
					c + Vector2(cos(a), sin(a)) * s, col, s * 0.3)
		"chat":     # burbuja con cola
			cv.draw_rect(Rect2(c + Vector2(-s, -s * 0.7),
				Vector2(s * 2, s * 1.3)), col, false, s * 0.18)
			cv.draw_line(c + Vector2(-s * 0.4, s * 0.6),
				c + Vector2(-s * 0.6, s), col, s * 0.18)
		"trophy":   # copa
			cv.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.8),
				Vector2(s * 1.2, s * 0.9)), col)
			cv.draw_rect(Rect2(c + Vector2(-s * 0.12, s * 0.1),
				Vector2(s * 0.24, s * 0.55)), col)
			cv.draw_rect(Rect2(c + Vector2(-s * 0.45, s * 0.65),
				Vector2(s * 0.9, s * 0.2)), col)
		"flag":     # bandera
			cv.draw_line(c + Vector2(-s * 0.6, -s),
				c + Vector2(-s * 0.6, s), col, s * 0.18)
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.6, -s), c + Vector2(s, -s * 0.65),
				c + Vector2(-s * 0.6, -s * 0.3)]), col)
		"undo":     # flecha curva
			cv.draw_arc(c + Vector2(0, s * 0.2), s * 0.65,
				PI * 0.9, TAU * 1.05, 12, col, s * 0.2)
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.75, -s * 0.5),
				c + Vector2(-s * 0.15, -s * 0.5),
				c + Vector2(-s * 0.5, -s)]), col)
		"hint":     # bombilla
			cv.draw_arc(c + Vector2(0, -s * 0.15), s * 0.55,
				-PI * 0.15, PI * 1.15, 12, col, s * 0.18)
			cv.draw_rect(Rect2(c + Vector2(-s * 0.25, s * 0.3),
				Vector2(s * 0.5, s * 0.4)), col)
		"puzzle":   # pieza de puzzle
			cv.draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.8),
				Vector2(s * 1.6, s * 1.6)), col, false, s * 0.18)
			cv.draw_circle(c + Vector2(0, -s * 0.8), s * 0.28, col)
		"book":     # libro abierto
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, -s * 0.5), c + Vector2(0, -s * 0.2),
				c + Vector2(0, s * 0.7), c + Vector2(-s, s * 0.4)]), col)
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s, -s * 0.5), c + Vector2(0, -s * 0.2),
				c + Vector2(0, s * 0.7), c + Vector2(s, s * 0.4)]),
				col.darkened(0.2))
		"bolt":     # rayo
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.4, s * 0.1),
				c + Vector2(0, s * 0.1), c + Vector2(-s * 0.2, s),
				c + Vector2(s * 0.4, -s * 0.1), c + Vector2(0, -s * 0.1)]),
				col)
		"back":     # flecha atrás
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, 0), c + Vector2(s * 0.2, -s * 0.6),
				c + Vector2(s * 0.2, s * 0.6)]), col)
			cv.draw_rect(Rect2(c + Vector2(0, -s * 0.15),
				Vector2(s * 0.7, s * 0.3)), col)
		"clock":    # esfera + agujas
			cv.draw_arc(c, s * 0.85, 0, TAU, 20, col, s * 0.18)
			cv.draw_line(c, c + Vector2(0, -s * 0.55), col, s * 0.16)
			cv.draw_line(c, c + Vector2(s * 0.4, 0), col, s * 0.16)
		_: cv.draw_circle(c, s * 0.5, col)

## Control mínimo que dibuja un icono UI.
class IconGlyph extends Control:
	var kind := ""
	var col := Color.WHITE
	func _init(k: String, c: Color, px := 16) -> void:
		kind = k; col = c
		custom_minimum_size = Vector2(px, px)
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw() -> void:
		Icons.draw_ui(self, kind, Rect2(Vector2.ZERO, size), col)

## Rasteriza un icono a ImageTexture (para Button.icon).
## Requiere un nodo host dentro del árbol para el viewport offscreen.
static func ui_tex(kind: String, col: Color, host: Node, px := 18) \
		-> Texture2D:
	# headless (dummy renderer): los viewports no rasterizan — vacío
	if DisplayServer.get_name() == "headless":
		var blank := Image.create(px, px, false, Image.FORMAT_RGBA8)
		return ImageTexture.create_from_image(blank)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(px, px)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var ig := IconGlyph.new(kind, col, px)
	ig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(ig)
	host.add_child(vp)
	vp.set_process(false)
	await host.get_tree().process_frame
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		var blank := Image.create(px, px, false, Image.FORMAT_RGBA8)
		return ImageTexture.create_from_image(blank)
	return ImageTexture.create_from_image(img)

## Asigna iconos a botones ya construidos (una pasada diferida).
## map: {Button: kind}. Útil tras _build_menu sin tocar el flujo.
static func apply_icons(btns: Dictionary, host: Node,
		col := Color(0.9, 0.9, 0.9)) -> void:
	for b in btns:
		var tex: Texture2D = await ui_tex(str(btns[b]), col, host)
		# el botón puede haberse liberado durante el await (menú
		# reconstruido): 'b != null' no protege objetos freed
		if is_instance_valid(b): b.icon = tex
