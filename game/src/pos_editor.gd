class_name PosEditor
extends Control

## Editor de posiciones libres: coloca piezas de ambas facciones en un
## tablero 8×8 y arranca una partida desde esa configuración.
## El resultado se entrega por la señal 'start' como [{x,y,l,o}].

signal start(pos: Array, first: int)
signal cancel()

const CELL := 64

var f0: Dictionary
var f1: Dictionary
var grid := {}                    # Vector2i -> {l, o}
var _undo: Array = []             # snapshots de grid para Ctrl+Z

func _push_undo() -> void:
	_undo.append(grid.duplicate(true))
	if _undo.size() > 60: _undo.pop_front()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and event.ctrl_pressed and event.keycode == KEY_Z:
		if _undo.is_empty(): return
		grid = _undo.pop_back()
		_board.queue_redraw()
var sel_letter := "P"
var sel_owner := 0
var first := 0
var _board: Control
var _err_lbl: Label

func _init(p_f0: Dictionary, p_f1: Dictionary) -> void:
	f0 = p_f0
	f1 = p_f1
	sel_letter = _letters(0)[0]

func _letters(owner: int) -> Array:
	var f: Dictionary = f0 if owner == 0 else f1
	return f.pieces.keys()

func _ready() -> void:
	# and_offsets: set_anchors_preset solo tocaba anchors y la
	# pantalla quedaba con size 0 — el tablero se cortaba tras la
	# columna lateral en vez de centrarse en el área disponible
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# scroll: tablero + panel (≈800px) rozaban el borde en compactas
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sc)
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(hbox)

	# tablero
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(center)
	var board := Control.new()
	board.draw.connect(_draw_board.bind(board))
	board.gui_input.connect(_on_board_input)
	board.mouse_exited.connect(func(): board.queue_redraw())
	_board = board
	# wrapper plano: el Center resetearía el scale del tablero —
	# el wrapper reserva el espacio escalado en el layout
	var wrap := Control.new()
	center.add_child(wrap)
	wrap.add_child(board)
	var fit := func():
		if sc.size.x <= 0: return
		var s: float = clampf(minf(
			(sc.size.x - 300.0) / (CELL * 8.0),
			sc.size.y / (CELL * 8.0 + 20.0)), 0.6, 1.3)
		board.size = Vector2(CELL * 8, CELL * 8)
		board.scale = Vector2(s, s)
		wrap.custom_minimum_size = \
			Vector2(CELL * 8, CELL * 8) * s
	sc.resized.connect(fit)
	fit.call_deferred()

	# lateral: paleta + controles — wrapper plano: topea el mínimo
	# que el contenido propaga (el hint es una línea muy larga)
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(280, 0)
	sw.clip_contents = true
	hbox.add_child(sw)
	var side := VBoxContainer.new()
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	sw.add_child(side)
	side.add_child(_lbl(Lang.t("MENU_POS_EDITOR"), 22))
	side.add_child(Widgets.lbl(Lang.t("POSE_HINT"), 0, false, true))

	for who in [0, 1]:
		var f: Dictionary = f0 if who == 0 else f1
		side.add_child(_lbl(Lang.t("POSE_PLAYER") % [
			who + 1, PiecesData.fac_name(f)], 16))
		var flow := GridContainer.new()
		# 6 columnas → casillas de 40px (objetivo táctil ≥44 rozaba el
		# ancho del panel; 40px es el compromiso con 8 por fila fuera)
		flow.columns = 6
		side.add_child(flow)
		for letter in _letters(who):
			var b := Button.new()
			b.text = letter
			b.custom_minimum_size = Vector2(40, 40)
			b.tooltip_text = PiecesData.piece_name(f.pieces[letter])
			var w: int = who; var l: String = letter
			b.pressed.connect(func():
				sel_owner = w; sel_letter = l
				board.queue_redraw())
			flow.add_child(b)

	side.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	side.add_child(row)
	row.add_child(_lbl(Lang.t("POSE_FIRST")))
	var opt := OptionButton.new()
	opt.add_item(Lang.t("POSE_P1")); opt.add_item(Lang.t("POSE_P2"))
	opt.item_selected.connect(func(i): first = i)
	row.add_child(opt)

	var b_clear := Button.new()
	b_clear.text = Lang.t("POSE_CLEAR")
	b_clear.pressed.connect(func():
		Widgets.confirm(self, Lang.t("POSE_CLEAR_T"),
			Lang.t("POSE_CLEAR_C"), Lang.t("POSE_CLEAR"),
			func(): _push_undo(); grid.clear(); board.queue_redraw()))
	side.add_child(b_clear)
	# línea de errores persistente — antes cada fallo APILABA un
	# Label nuevo en el panel (nunca se limpiaban)
	_err_lbl = _lbl("")
	_err_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.45, 0.4))
	_err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_err_lbl)
	# BEL-FEN: compartir posiciones como texto (estilo lichess)
	var fen_row := HBoxContainer.new()
	side.add_child(fen_row)
	var fen_edit := LineEdit.new()
	fen_edit.placeholder_text = "BEL1 …"
	# 150px + 2 botones no cabían en el panel de 280 → Importar
	# quedaba cortado en el borde de la ventana
	fen_edit.custom_minimum_size = Vector2(80, 0)
	fen_row.add_child(fen_edit)
	var b_fexp := Button.new()
	b_fexp.text = Lang.t("POSE_COPY")
	b_fexp.pressed.connect(func():
		fen_edit.text = _export_bel()
		DisplayServer.clipboard_set(fen_edit.text)
		# confirmación visible: antes solo cambiaba el campo, sin
		# feedback de que el portapapeles se actualizó
		_err_lbl.add_theme_color_override("font_color",
			Color(0.55, 0.85, 0.55))
		_err_lbl.text = Lang.t("POSE_COPIED"))
	fen_row.add_child(b_fexp)
	var b_fimp := Button.new()
	b_fimp.text = Lang.t("POSE_IMPORT")
	b_fimp.pressed.connect(func():
		_err_lbl.add_theme_color_override("font_color",
			Color(0.95, 0.45, 0.4))
		_err_lbl.text = _import_bel(fen_edit.text)
		board.queue_redraw())
	fen_row.add_child(b_fimp)
	var b_play := Button.new()
	b_play.text = Lang.t("POSE_PLAY")
	b_play.custom_minimum_size = Vector2(0, 40)
	b_play.pressed.connect(func():
		if _leaders(0) == 0 or _leaders(1) == 0:
			_err_lbl.add_theme_color_override("font_color",
				Color(0.95, 0.45, 0.4))
			_err_lbl.text = Lang.t("POSE_NEED_LEADERS")
			return
		start.emit(_to_array(), first))
	side.add_child(b_play)
	var b_back := Button.new()
	b_back.text = Lang.t("POSE_BACK")
	b_back.pressed.connect(func(): cancel.emit())
	side.add_child(b_back)

## Exporta el tablero del editor como BEL-FEN (las facciones del
## encabezado son índices informativos; al importar solo se usan letras).
func _export_bel() -> String:
	var st := BoardState.new()
	st.factions = [f0, f1]
	for cell in grid:
		var e: Dictionary = grid[cell]
		var f: Dictionary = f0 if e.o == 0 else f1
		var def: Dictionary = f.pieces.get(e.l, {})
		if not def.is_empty():
			st.set_at(cell, st.new_piece(def, e.o))
	return BoardState.to_bel(st, 0, 0, 0, 0, first)

## Importa un BEL-FEN usando las facciones actuales del editor.
func _import_bel(s: String) -> String:
	var r: Dictionary = BoardState.from_bel(s)
	if r.has("err"):
		# el parser devuelve códigos; aquí se traducen con parámetros
		match String(r.err):
			"BEL_ERR_ROW":
				return Lang.t("BEL_ERR_ROW") % [r.row, r.x]
			"BEL_ERR_ROWS":
				return Lang.t("BEL_ERR_ROWS") % r.n
			"BEL_ERR_NONNUM", "BEL_ERR_TURN":
				return Lang.t(r.err) % r.v
			_:
				return Lang.t(r.err)
	# validar ANTES de tocar el grid: un BEL con una letra ajena dejaba
	# la posición importada a medias junto al mensaje de error
	var tmp := {}
	for e in r.pos:
		var f: Dictionary = f0 if e.o == 0 else f1
		if not f.pieces.has(e.l):
			return Lang.t("POSE_IMPORT_ERR") % [PiecesData.fac_name(f), e.l]
		tmp[Vector2i(int(e.x), int(e.y))] = {"l": e.l, "o": e.o,
			"has_moved": bool(e.get("has_moved", false))}
	_push_undo()
	grid = tmp   # propagar '*' de BEL-FEN (has_moved)
	if r.has("turn"): first = int(r.turn)
	return ""

func _leaders(owner: int) -> int:
	var n := 0
	for e in grid.values():
		var f: Dictionary = f0 if e.o == 0 else f1
		var def: Dictionary = f.pieces.get(e.l, {})
		if e.o == owner and def.get("leader", false): n += 1
	return n

func _to_array() -> Array:
	var out := []
	for cell in grid:
		var e: Dictionary = grid[cell]
		out.append({"x": cell.x, "y": cell.y, "l": e.l, "o": e.o,
			"has_moved": bool(e.get("has_moved", false))})
	return out

func _lbl(t: String, fs := 0) -> Label:
	return Widgets.lbl(t, fs)

func _draw_board(board: Control) -> void:
	var font := ThemeDB.fallback_font
	for y in 8:
		for x in 8:
			var r := Rect2(x * CELL, y * CELL, CELL, CELL)
			board.draw_rect(r, Color(0.13, 0.15, 0.19)
				if (x + y) % 2 == 0 else Color(0.22, 0.25, 0.31))
	for cell in grid:
		var e: Dictionary = grid[cell]
		var f: Dictionary = f0 if e.o == 0 else f1
		var def: Dictionary = f.pieces.get(e.l, {})
		var r := Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
		var fc: Color = f.color
		board.draw_circle(r.get_center(), CELL * 0.40, fc.darkened(0.15))
		board.draw_circle(r.get_center(), CELL * 0.40,
			fc.darkened(0.7), false, 2.0)
		var ts := font.get_string_size(e.l,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
		board.draw_string(font,
			r.get_center() + Vector2(-ts.x / 2, ts.y / 3),
			e.l, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
		if def.get("leader", false):
			board.draw_circle(r.get_center() + Vector2(0, -CELL * 0.36),
				5.0, Color(1, 0.85, 0.2))
	# casilla seleccionada de la paleta → vista previa
	var mp := board.get_local_mouse_position()
	var hc := Vector2i(int(mp.x / CELL), int(mp.y / CELL))
	if BoardState.inside(hc):
		board.draw_rect(Rect2(hc.x * CELL, hc.y * CELL, CELL, CELL),
			Color(1, 1, 1, 0.25), false, 2.0)
		var ts := font.get_string_size(sel_letter,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		board.draw_string(font, mp + Vector2(6, -ts.y / 2),
			Lang.t("POSE_CURSOR") % [sel_letter, sel_owner + 1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_board.queue_redraw()
		return
	if not event is InputEventMouseButton or not event.pressed: return
	var cell := Vector2i(int(event.position.x / CELL),
		int(event.position.y / CELL))
	if not BoardState.inside(cell): return
	_push_undo()
	if event.button_index == MOUSE_BUTTON_LEFT:
		grid[cell] = {"l": sel_letter, "o": sel_owner}
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		grid.erase(cell)
	_board.queue_redraw()
