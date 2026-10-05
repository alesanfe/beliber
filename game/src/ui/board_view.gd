class_name BoardView
extends Control

## Vista del tablero: dibuja casillas, piezas (letra + color de facción) y
## highlights de movimientos legales usando los colores de la leyenda.

const CELL := 72

var tm: TurnManager
var selected := Vector2i(-1, -1)
var legal: Array = []
var show_coverage := false
var flipped := false           # J0 arriba ↔ abajo
var anim := {}                 # {from,to,t0} animación en curso
var anim_dur := 0.18
var dragging := Vector2i(-1, -1)   # casilla que se arrastra
var drag_pos := Vector2.ZERO       # posición del ratón durante drag
var premove := {}                  # {from,to} programado contra la IA
var premove_enabled := false       # activado si hay rival IA
var human_idx := 0                 # lado humano en modo vs IA
var pre_sel := Vector2i(-1, -1)    # origen del premove en selección
var net_me := -1                   # online: lado que controla este cliente
var sync_pending := false          # eco del árbitro pendiente (ws_auth)
var defer_play := false            # autoritativo: solo emite, no aplica
var inspect := false               # guía: inspecciona, no mueve
var quiz := false                  # guía-quiz: clic emite cell_picked
signal cell_picked(cell: Vector2i)
var hover := Vector2i(-1, -1)      # casilla bajo el cursor (tooltip)

signal move_played(mv: Dictionary)
var view_i := -1                   # >=0 → modo replay (snapshot i)
var theme_i := 0                   # índice de tema de casillas
var show_threats := false          # punto rojo en piezas propias atacadas
var blindfold := false             # modo ciego: oculta todas las piezas
var show_coords := true            # coordenadas visibles
var confirm_moves := false         # requiere 2º clic en el destino
var pending := {}                  # jugada pendiente de confirmar
var chain_cands: Array = []        # variantes encadenadas a elegir
var arrows: Array = []             # {from,to} flechas de análisis
var marks := {}                    # cell → color (click derecho)
var arrow_from := Vector2i(-1, -1) # origen de flecha en curso
var mark_cols := [Color(1, 0.3, 0.3, 0.5), Color(0.3, 0.9, 0.3, 0.5),
	Color(1, 0.9, 0.2, 0.5), Color(0.4, 0.6, 1, 0.5)]

const THEMES := [
	[Color(0.13, 0.15, 0.19), Color(0.22, 0.25, 0.31)],  # noche
	[Color(0.82, 0.79, 0.70), Color(0.58, 0.47, 0.35)],  # clásico
	[Color(0.90, 0.91, 0.85), Color(0.42, 0.62, 0.45)],  # lichess
]

func _init(p_tm: TurnManager) -> void:
	custom_minimum_size = Vector2(CELL * 8, CELL * 8)
	bind(p_tm)

## Vincula el tablero a un TurnManager (init o tras un resync que
## sustituye el tm en caliente — las conexiones viejas mueren con él).
func bind(p_tm: TurnManager) -> void:
	if tm != null:
		if tm.move_made.is_connected(_on_move):
			tm.move_made.disconnect(_on_move)
		if tm.turn_started.is_connected(_tm_turn):
			tm.turn_started.disconnect(_tm_turn)
	tm = p_tm
	tm.move_made.connect(_on_move)
	tm.turn_started.connect(_tm_turn)

func _tm_turn(_p: int) -> void:
	# al volver tu turno, un origen de premove a medio elegir quedaría
	# iluminado para siempre — limpiarlo aquí (el premove completo se
	# conserva: es la intención real)
	if pre_sel.x >= 0 and tm.current == human_idx:
		pre_sel = Vector2i(-1, -1)
	_refresh()

func _on_move(mv: Dictionary) -> void:
	anim = {"from": mv.from, "to": mv.to,
		"t0": Time.get_ticks_msec()}
	pending = {}
	_refresh()

## Convierte casilla lógica → casilla de pantalla según la orientación.
func _scr(c: Vector2i) -> Vector2i:
	return Vector2i(7 - c.x, 7 - c.y) if flipped else c

## Convierte casilla de pantalla → casilla lógica.
func _log(c: Vector2i) -> Vector2i:
	return _scr(c)  # la misma transformación invierte

func _cell_rect(c: Vector2i) -> Rect2:
	var s := _scr(c)
	return Rect2(s.x * CELL, s.y * CELL, CELL, CELL)

func _process(_d: float) -> void:
	if not anim.is_empty():
		var t := float(Time.get_ticks_msec() - anim.t0) / 1000.0
		if t >= anim_dur: anim = {}
		else: queue_redraw()

func _refresh() -> void:
	selected = Vector2i(-1, -1)
	legal = []
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	# marco del tablero (borde + sombra suave)
	var outer := Rect2(-8, -8, 8 * CELL + 16, 8 * CELL + 16)
	draw_rect(Rect2(-4, -2, 8 * CELL + 8, 8 * CELL + 10),
		Color(0, 0, 0, 0.35))
	draw_rect(outer, Color(0.10, 0.12, 0.15))
	draw_rect(outer.grow(-4), Color(0.16, 0.19, 0.24), false, 1.0)
	# casillas
	for y in 8:
		for x in 8:
			var r := _cell_rect(Vector2i(x, y))
			var dark := (x + y) % 2 == 0
			draw_rect(r, THEMES[theme_i][0] if dark else THEMES[theme_i][1])
	# mapa de cobertura (estilo Chess Evolved Online)
	if show_coverage:
		for who in [0, 1]:
			var col: Color = tm.state.factions[who].color
			col.a = 0.22
			for cell in tm.coverage(who):
				var cr := _cell_rect(cell).grow(-CELL * 0.28)
				# distinguir por FORMA además de color (accesibilidad):
				# J0 = sólido, J1 = anillo — sin depender del tinte
				if who == 0: draw_rect(cr, col)
				else: draw_rect(cr, col, false, 2.5)
	# marcas de análisis (clic derecho sobre una casilla). Además del
	# color, cada marca usa una FORMA distinta (accesibilidad):
	# relleno / círculo / cruz
	for cell in marks:
		var mc: Color = marks[cell]
		var mr := _cell_rect(cell).grow(-CELL * 0.15)
		match mark_cols.find(mc):
			1: draw_circle(mr.get_center(), mr.size.x * 0.5, mc)
			2:
				draw_line(mr.position, mr.position + mr.size,
					mc, 4.0, true)
				draw_line(mr.position + Vector2(mr.size.x, 0),
					mr.position + Vector2(0, mr.size.y), mc, 4.0, true)
			_: draw_rect(mr, mc)
	# amenazas sobre piezas propias (punto rojo + "!" no cromático)
	if show_threats and view_i < 0:
		for y in 8:
			for x in 8:
				var pos := Vector2i(x, y)
				var tp: Variant = tm.state.at(pos)
				if tp != null and tp.owner == tm.current \
						and MoveGen.is_attacked(tm.state, pos, tp.owner):
					var tc := _cell_rect(pos).get_center() \
						+ Vector2(CELL * 0.34, -CELL * 0.34)
					draw_circle(tc, 7.0, Color(1, 0.2, 0.2))
					draw_string(font, tc + Vector2(-2.5, 4.5), "!",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	# último movimiento (amarillo tenue, estilo Lichess)
	if not tm.state.last_move.is_empty():
		for cc in [tm.state.last_move.from, tm.state.last_move.to]:
			draw_rect(_cell_rect(cc), Color(1.0, 0.9, 0.35, 0.28))
	# highlights de movimientos legales
	for mv in legal:
		var c: Color = FX.color_of(mv.fx, mv.cond)
		c.a = 0.45
		var r := _cell_rect(mv.to)
		draw_rect(r, c)
		c.a = 0.95
		draw_rect(r.grow(-3), c, false, 3.0)
		if mv.has("second"):
			draw_circle(r.get_center(), 10.0, Color(1, 1, 1, 0.8))
	# piezas: glifo de ajedrez sobre disco del color de la facción
	var animating := not anim.is_empty()
	var anim_t := 0.0
	if animating:
		anim_t = clampf(float(Time.get_ticks_msec() - anim.t0)
			/ 1000.0 / anim_dur, 0.0, 1.0)
	# en replay se dibuja el snapshot, no el estado vivo
	var draw_state: BoardState = tm.state
	if view_i >= 0:
		var snap: Variant = tm.replay_snapshot(view_i)
		if snap != null:
			var rs := BoardState.new()
			rs.grid = snap.grid
			rs.factions = tm.state.factions
			rs.last_move = snap.last_move
			draw_state = rs
	for y in 8:
		for x in 8:
			var pos := Vector2i(x, y)
			var p: Variant = draw_state.at(pos)
			if p == null: continue
			# ocultar la pieza que se está arrastrando
			if view_i < 0 and pos == dragging: continue
			if blindfold and view_i < 0: continue   # modo ciego
			var r := _cell_rect(pos)
			var cpos := r.get_center()
			# la pieza recién movida se desliza desde 'from'
			if animating and pos == anim.to:
				var s_from := _cell_rect(anim.from).get_center()
				var ease := 1.0 - (1.0 - anim_t) * (1.0 - anim_t)
				cpos = s_from.lerp(r.get_center(), ease)
			var fc: Color = tm.state.factions[p.owner].color
			var rad := CELL * 0.40
			# sombra + relieve (disco oscuro, núcleo de la facción,
			# arco superior aclarado simulando luz)
			draw_circle(cpos + Vector2(2, 3), rad, Color(0, 0, 0, 0.35))
			draw_circle(cpos, rad, fc.darkened(0.45))
			draw_circle(cpos, rad - 3.0, fc)
			draw_arc(cpos + Vector2(0, -rad * 0.25), rad * 0.6,
				PI * 1.15, PI * 1.85, 24, fc.lightened(0.35), 3.0)
			draw_circle(cpos, rad, fc.darkened(0.7), false, 2.0)
			var ink := Color.BLACK if fc.get_luminance() > 0.45 else Color.WHITE
			PieceArt.draw(self, cpos + Vector2(0, 2), CELL,
				PieceArt.arch_of_glyph(PiecesData.chess_glyph(p.def)),
				ink, fc)
			# letra de la pieza abajo a la derecha
			draw_string(font, cpos + Vector2(rad * 0.35, rad - 2),
				p.def.letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 1, 1, 0.75))
			if p.def.get("leader", false):
				draw_circle(cpos + Vector2(0, -rad + 4), 5.0,
					Color(1, 0.85, 0.2))
				# "jaque": líder bajo ataque → anillo rojo pulsante
				if MoveGen.is_attacked(tm.state, pos, p.owner):
					draw_arc(cpos, rad + 2.0, 0, TAU, 48,
						Color(1, 0.15, 0.15), 3.0)
			if p.immobilized > 0:
				draw_rect(Rect2(cpos - Vector2(rad, rad),
					Vector2(rad * 2, rad * 2)),
					Color(0.4, 0.4, 0.45, 0.5))
	# selección
	if selected.x >= 0:
		draw_rect(_cell_rect(selected), Color.WHITE, false, 3.0)
	# cursor de teclado: anillo discontinuo (no solo color — forma
	# distinta al rect sólido de selección, así no se confunden)
	if kb_cell.x >= 0 and view_i < 0 and not tm.over:
		var kr: Rect2 = _cell_rect(kb_cell).grow(-4)
		for i in 4:
			var a: Vector2 = kr.position \
				+ Vector2(kr.size.x, 0) * [0, 0, 1, 1][i] \
				+ Vector2(0, kr.size.y) * [0, 1, 0, 1][i]
			var b: Vector2 = kr.position \
				+ Vector2(kr.size.x, 0) * [0, 1, 1, 0][i] \
				+ Vector2(0, kr.size.y) * [1, 1, 0, 0][i]
			draw_dashed_line(a, b, Color(1, 1, 1, 0.85), 2.5, 6.0)
	# pieza arrastrada (dibujada al final, encima de todo)
	if view_i < 0 and dragging.x >= 0:
		var p: Variant = tm.state.at(dragging)
		if p != null:
			var fc: Color = tm.state.factions[p.owner].color
			var rad := CELL * 0.40
			draw_circle(drag_pos + Vector2(3, 5), rad,
				Color(0, 0, 0, 0.45))
			draw_circle(drag_pos, rad, fc.darkened(0.3))
			draw_circle(drag_pos, rad - 3.0, fc.lightened(0.08))
			draw_circle(drag_pos, rad, fc.darkened(0.7), false, 2.0)
			var ink := Color.BLACK if fc.get_luminance() > 0.45 \
				else Color.WHITE
			PieceArt.draw(self, drag_pos + Vector2(0, 2), CELL,
				PieceArt.arch_of_glyph(PiecesData.chess_glyph(p.def)),
				ink, fc)
	# origen de premove en selección: borde azul tenue
	if pre_sel.x >= 0:
		draw_rect(_cell_rect(pre_sel), Color(0.4, 0.7, 1, 0.6), false, 3.0)
	# premove programado: marco verde punteado
	if not premove.is_empty():
		for cc in [premove.from, premove.to]:
			draw_rect(_cell_rect(cc).grow(-4),
				Color(0.3, 1.0, 0.4, 0.9), false, 2.0)
	# flechas de análisis (arrastre con botón derecho)
	for a in arrows:
		_draw_arrow(a.from, a.to, a.get("col", Color(0.4, 0.8, 1, 0.75)))
	if arrow_from.x >= 0:
		var mc := _log(Vector2i(int(get_local_mouse_position().x / CELL),
			int(get_local_mouse_position().y / CELL)))
		_draw_arrow(arrow_from, mc, Color(0.4, 0.8, 1, 0.4))
	# jugada pendiente de confirmación: destino pulsante
	if not pending.is_empty():
		var pr := _cell_rect(pending.to)
		draw_rect(pr, Color(0.4, 1, 0.5, 0.35))
		draw_rect(pr.grow(-4), Color(0.4, 1, 0.5), false, 2.0)
	# cadena opcional: destinos del 2º tramo en cian pulsante; clic en
	# el destino del 1er tramo juega solo ese tramo
	if not chain_cands.is_empty():
		var ca: float = 0.3 + 0.15 * sin(
			Time.get_ticks_msec() * 0.006)
		for c in chain_cands:
			var s: Variant = c.get("second")
			if s != null:
				var sr := _cell_rect(s.to)
				draw_rect(sr, Color(0.2, 0.9, 1.0, ca))
				draw_rect(sr, Color(0.2, 0.9, 1.0, 0.95), false, 2.5)
			else:
				# variante de un solo tramo: se queda en el 1er destino
				draw_rect(_cell_rect(c.to), Color(1.0, 0.85, 0.2, ca))
		# sin el texto el jugador no sabía que la cadena esperaba un
		# segundo clic (o que clic fuera cancela)
		draw_string(_chess_font(), Vector2(8, BoardState.SIZE * CELL - 8),
			Lang.t("HUD_CHAIN_HINT"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.95, 1.0))
	# casilla bajo el cursor: highlight tenue
	if BoardState.inside(hover):
		var hr := _cell_rect(hover)
		draw_rect(hr, Color(1, 1, 1, 0.07))
		draw_rect(hr.grow(-2), Color(1, 1, 1, 0.25), false, 1.5)
	# tooltip de pieza al hover (estilo CEO): nombre + efectos
	if BoardState.inside(hover) and not blindfold:
		var hp: Variant = tm.state.at(hover)
		if hp != null:
			_draw_tooltip(hp.def, hover)
	# coordenadas (se rotan con el tablero)
	if show_coords:
		for i in 8:
			var fi := 7 - i if flipped else i
			draw_string(font, Vector2(i * CELL + 4, 8 * CELL - 6),
				"%c" % (97 + fi), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1, 1, 1, 0.4))
			draw_string(font, Vector2(4, i * CELL + 14),
				str(8 - fi), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1, 1, 1, 0.4))

func _draw_arrow(frm: Vector2i, to: Vector2i, col: Color) -> void:
	var a := _cell_rect(frm).get_center()
	var b := _cell_rect(to).get_center()
	var dir := (b - a).normalized()
	if dir == Vector2.ZERO: return
	var tip := b - dir * CELL * 0.18
	draw_line(a, tip, col, 6.0, true)
	var side := Vector2(-dir.y, dir.x) * CELL * 0.14
	draw_colored_polygon([tip + dir * CELL * 0.22, tip + side,
		tip - side], col)

## Tooltip con nombre, valor y resumen de efectos de la pieza.
func _draw_tooltip(def: Dictionary, cell: Vector2i) -> void:
	var font := get_theme_default_font()
	var f: Dictionary = tm.state.factions[
		(tm.state.at(cell) as Dictionary).owner]
	var title := "%s  %s — %d pts" % [
		def.letter, PiecesData.piece_name(def),
		int(def.get("value", 0))]
	var eff := _effects_of(def)
	if def.get("leader", false): eff += " · LÍDER"
	var lines := PackedStringArray([title, eff])
	var w := 0.0
	for ln in lines:
		w = maxf(w, font.get_string_size(ln,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var r := _cell_rect(cell)
	var pos := r.position + Vector2(0, -2)
	if pos.y + 64 < 0: pos.y = r.end.y + 6   # si no cabe arriba, abajo
	pos.y = clampf(pos.y, 2, 8 * CELL - 62)
	pos.x = clampf(pos.x + 6, 2, 8 * CELL - w - 24)
	var box := Rect2(pos.x - 6, pos.y, w + 20, 20 + lines.size() * 18)
	draw_rect(box, Color(0.07, 0.08, 0.1, 0.94))
	draw_rect(box, f.color, false, 2.0)
	var ty := pos.y + 16
	for i in lines.size():
		draw_string(font, Vector2(pos.x, ty), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1, 1, 1) if i == 0 else Color(0.75, 0.78, 0.85))
		ty += 18

## Resumen de efectos de la pieza a partir de sus códigos de casilla.
static func _effects_of(def: Dictionary) -> String:
	var seen := {}
	for key in def.cells:
		var ch: String = def.cells[key]
		var nombre := PiecesData.code_name(ch)
		if nombre != "": seen[nombre] = true
	var list := []
	for k in seen: list.append(k)
	return ", ".join(list) if list.size() > 0 else "sin efectos"

var _cf: Font

func _chess_font() -> Font:
	if _cf == null:
		_cf = SystemFont.new()
		_cf.font_names = ["Segoe UI Symbol", "DejaVu Sans",
			"Noto Sans Symbols2"]
	return _cf

func _gui_input(event: InputEvent) -> void:
	if tm.over or view_i >= 0: return
	# con árbitro, el input se ignora hasta recibir el eco: un segundo
	# movimiento durante el eco llegaba al servidor fuera de turno
	if defer_play and sync_pending: return
	# modo guía: clic en cualquier pieza muestra su patrón completo
	if inspect:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var sc := Vector2i(int(event.position.x / CELL),
				int(event.position.y / CELL))
			var c := _log(sc)
			if quiz:
				cell_picked.emit(c)
				queue_redraw()
				return
			var p: Variant = tm.state.at(c) if BoardState.inside(c) \
				else null
			if p != null:
				selected = c
				legal = MoveGen.moves_for(tm.state, c)
			else:
				selected = Vector2i(-1, -1)
				legal = []
			queue_redraw()
		return
	# hover/tooltip siempre activo (también en turno rival)
	if event is InputEventMouseMotion:
		var sc2 := Vector2i(int(event.position.x / CELL),
			int(event.position.y / CELL))
		var hc := _log(sc2)
		if hc != hover:
			hover = hc
			queue_redraw()
	# online: solo interactúas en tu turno (el análisis con botón
	# derecho sigue permitido)
	var is_left: bool = event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT
	if net_me >= 0 and tm.current != net_me and is_left:
		return
	# ---- arrastrar y soltar ----
	if event is InputEventMouseButton:
		var scr := Vector2i(int(event.position.x / CELL),
			int(event.position.y / CELL))
		var cell := _log(scr)
		# ---- botón derecho: flechas y marcas de análisis ----
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				arrow_from = cell
			else:
				if cell == arrow_from:
					# clic: ciclar color de marca / quitar
					if marks.has(cell):
						var ci: int = mark_cols.find(marks[cell])
						if ci >= mark_cols.size() - 1:
							marks.erase(cell)
						else:
							marks[cell] = mark_cols[ci + 1]
					else:
						marks[cell] = mark_cols[0]
				elif arrow_from.x >= 0:
					# arrastre: alternar flecha
					var found := -1
					for i in arrows.size():
						if arrows[i].from == arrow_from \
								and arrows[i].to == cell:
							found = i
					if found >= 0: arrows.remove_at(found)
					else: arrows.append({"from": arrow_from,
						"to": cell, "col": Color(0.4, 0.8, 1, 0.75)})
				arrow_from = Vector2i(-1, -1)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_pos = event.position
				var p: Variant = tm.state.at(cell) \
					if BoardState.inside(cell) else null
				if p != null and p.owner == tm.current \
						and p.immobilized == 0:
					dragging = cell
					selected = cell
					legal = tm.legal_moves(cell)
					queue_redraw()
					return
			else:
				# soltar: ejecutar si es destino legal — respetando
				# confirm_moves como el flujo clic-clic (un drop
				# accidental no era cancelable)
				if dragging.x >= 0:
					var cands := _find_moves(dragging, cell)
					dragging = Vector2i(-1, -1)
					if cands.size() > 1:
						# cadena opcional: elegir el 2º tramo
						chain_cands = cands
					elif cands.size() == 1:
						if confirm_moves and pending.get("to") != cell:
							pending = cands[0]
						else:
							pending = {}
							commit(cands[0])
					queue_redraw()
					return
	if event is InputEventMouseMotion:
		drag_pos = event.position
		if dragging.x >= 0 or arrow_from.x >= 0:
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var scr := Vector2i(int(event.position.x / CELL),
			int(event.position.y / CELL))
		_activate_cell(_log(scr))

## Navegación por teclado (WCAG 2.1.1 — la partida entera sin ratón):
## flechas mueven el cursor de casilla, Enter/Espacio equivalen al
## clic izquierdo, Esc deselecciona. El cursor es visual (la casilla
## marcada con punto blanco); al voltear el tablero las flechas van
## en dirección visual, no lógica.
var kb_cell := Vector2i(-1, -1)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed \
			or tm.over or view_i >= 0:
		return
	if defer_play and sync_pending: return
	var dir := Vector2i.ZERO
	match event.keycode:
		KEY_LEFT:  dir = Vector2i(-1, 0)
		KEY_RIGHT: dir = Vector2i(1, 0)
		KEY_UP:    dir = Vector2i(0, -1)
		KEY_DOWN:  dir = Vector2i(0, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if kb_cell.x >= 0:
				if inspect:
					if quiz:
						cell_picked.emit(kb_cell)
					else:
						var ip: Variant = tm.state.at(kb_cell)
						if ip != null:
							selected = kb_cell
							legal = MoveGen.moves_for(tm.state, kb_cell)
						else:
							selected = Vector2i(-1, -1)
							legal = []
						queue_redraw()
				else:
					_activate_cell(kb_cell)
			accept_event()
			return
		KEY_ESCAPE:
			if selected.x >= 0 or not pending.is_empty():
				selected = Vector2i(-1, -1)
				legal = []
				pending = {}
				chain_cands = []
				queue_redraw()
				accept_event()
			return
		_: return
	if flipped: dir = -dir
	if kb_cell.x < 0:
		kb_cell = Vector2i(4, 7)   # nace en la primera fila propia
	else:
		kb_cell = (kb_cell + dir).clamp(Vector2i.ZERO,
			Vector2i(7, 7))
	# el cursor también alimenta el tooltip/hover de la casilla
	hover = kb_cell
	queue_redraw()
	accept_event()
	_announce_cell(kb_cell)

## Lector de pantalla: nombra la casilla (notación algebraica) y la
## pieza que contiene, para que el tablero sea operable sin vista.
func _announce_cell(c: Vector2i) -> void:
	var sq := "%c%d" % [97 + c.x, 8 - c.y]
	var p: Variant = tm.state.at(c) if BoardState.inside(c) else null
	if p != null and not blindfold:
		var who := PiecesData.fac_name(
			tm.state.factions[p.owner])
		Tts.say(Lang.t("KB_CELL_PIECE") % [sq,
			PiecesData.piece_name(p.def), who])
	else:
		Tts.say(Lang.t("KB_CELL_EMPTY") % sq)
	if selected.x >= 0 and _find_move(selected, c) != null:
		Tts.say(Lang.t("KB_CELL_LEGAL"))

## Equivalencia teclado↔ratón: todo el ciclo selección → destino →
## cadena/premove pasa por aquí (antes el flujo solo existía en el
## bloque de clic izquierdo del ratón).
func _activate_cell(cell: Vector2i) -> void:
		if not BoardState.inside(cell): return
		# resolución de cadena pendiente: 2º tramo o solo el 1er tramo
		if not chain_cands.is_empty():
			var chained: Dictionary = {}
			var base: Dictionary = {}
			for c in chain_cands:
				var s: Variant = c.get("second")
				if s != null and s.to == cell: chained = c
				elif s == null and c.to == cell: base = c
			if not chained.is_empty():
				chain_cands = []
				commit(chained)
				queue_redraw()
				return
			if not base.is_empty():
				chain_cands = []
				commit(base)
				queue_redraw()
				return
			chain_cands = []   # clic fuera: cancelar y seguir normal
		# premove contra la IA: programar jugada fuera de turno
		if premove_enabled and tm.current != human_idx:
			var ph: Variant = tm.state.at(cell)
			if ph != null and ph.owner == human_idx:
				pre_sel = cell
			elif pre_sel.x >= 0:
				premove = {"from": pre_sel, "to": cell}
				pre_sel = Vector2i(-1, -1)
			queue_redraw()
			return
		# ¿clic en destino legal?
		if selected.x >= 0:
			var cands := _find_moves(selected, cell)
			if not cands.is_empty():
				if confirm_moves and pending.get("to") != cell:
					pending = cands[0]   # primer clic: previsualizar
					queue_redraw()
					return
				pending = {}
				if cands.size() > 1:
					# cadena opcional (Tritón): elegir 2º tramo
					chain_cands = cands
					queue_redraw()
					return
				commit(cands[0])
				queue_redraw()
				return
		# seleccionar pieza propia (en online solo tu lado)
		var p: Variant = tm.state.at(cell)
		var mine: bool = p != null and p.owner == tm.current \
			and p.immobilized == 0 \
			and (net_me < 0 or p.owner == net_me)
		if mine:
			selected = cell
			legal = tm.legal_moves(cell)
			Juice.ui_sfx.call(660.0, 0.04)   # click de selección
		else:
			selected = Vector2i(-1, -1)
			legal = []
		queue_redraw()

## Ejecuta el premove si el destino es legal al empezar el turno humano.
func try_premove() -> void:
	if premove.is_empty(): return
	var mv: Variant = _find_move(premove.from, premove.to)
	premove = {}
	if mv != null:
		commit(mv)
	queue_redraw()

## Aplica la jugada local y emite la señal (main la reenvía por red).
## Con defer_play (servidor autoritativo) solo se emite la intención;
## el estado cambia al recibir el eco del servidor.
## Punto único de entrada para ratón, teclado y premove — así online
## ninguna ruta se salta la sincronización.
func commit(mv: Dictionary) -> void:
	# una jugada ejecutada invalida cualquier cadena pendiente: sin
	# esto un drag de otra pieza dejaba chain_cands obsoleto y el
	# siguiente clic aplicaba una jugada calculada sobre estado viejo
	chain_cands = []
	if defer_play:
		if sync_pending: return   # bloquear input hasta el eco
		sync_pending = true
		move_played.emit(mv)
	elif tm.play(mv):
		move_played.emit(mv)

## Busca el movimiento legal from→to (null si no existe).
func _find_move(frm: Vector2i, to: Vector2i) -> Variant:
	for mv in tm.legal_moves(frm):
		if mv.to == to: return mv
	return null

## TODAS las variantes legales from→to. Cuando hay más de una, la
## pieza tiene cadena opcional (Tritón): el primer clic elige el
## destino del 1er tramo y el siguiente elige la continuación (o la
## misma casilla para jugar solo el 1er tramo).
func _find_moves(frm: Vector2i, to: Vector2i) -> Array:
	var out := []
	for mv in tm.legal_moves(frm):
		if mv.to == to: out.append(mv)
	return out
