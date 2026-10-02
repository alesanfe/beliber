class_name CapturedTray
extends Control

## Bandeja de piezas capturadas estilo lichess: iconos (glifos de
## ajedrez) de las piezas tomadas por un jugador, ordenadas por valor,
## seguidos del diferencial de material "+N" si ese jugador va por
## delante.

var letters: Array = []        # letras capturadas por ESTE jugador
var defs: Dictionary = {}      # mapa letra -> def de la facción víctima
var ink := Color.WHITE         # color de la facción víctima
var diff := 0                  # diferencial de material a favor

func setup(p_letters: Array, victim_faction: Dictionary, p_diff := 0) -> void:
	letters = p_letters.duplicate()
	defs = victim_faction.pieces
	ink = victim_faction.color
	diff = p_diff
	custom_minimum_size = Vector2(0, 24 if not letters.is_empty() or diff != 0 else 0)
	tooltip_text = ""
	var names := []
	for l in letters:
		var d: Variant = defs.get(l)
		names.append(PiecesData.piece_name(d) if d != null else l)
	tooltip_text = Lang.t("CAP_CAPTURED") + (
		", ".join(names) if names else Lang.t("CAP_NOTHING"))
	queue_redraw()

func _draw() -> void:
	if letters.is_empty() and diff <= 0:
		return
	var font := _font()
	var base := get_theme_default_font()
	var x := 0.0
	var y := 18.0
	# glifos ordenados por valor (peones primero, como lichess)
	var items := []
	for l in letters:
		var d: Variant = defs.get(l)
		var arch := PieceArt.arch_of_glyph(
			PiecesData.chess_glyph(d)) if d != null else PieceArt.PAWN
		var v := int(d.get("value", 0)) if d != null else 0
		items.append([v, arch])
	items.sort_custom(func(a, b): return a[0] < b[0])
	# siluetas vectoriales (PieceArt) en vez de glifos de fuente
	for it in items:
		PieceArt.draw(self, Vector2(x + 9, y - 9), 20, it[1], ink,
			Color(0, 0, 0, 0))
		x += 19.0
	if diff > 0:
		var txt := "+%d" % diff
		draw_string(base, Vector2(x + 4, y - 3), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 1, 0.75))

var _f: Font
func _font() -> Font:
	if _f == null:
		_f = SystemFont.new()
		_f.font_names = ["Segoe UI Symbol", "DejaVu Sans",
			"Noto Sans Symbols2"]
	return _f
