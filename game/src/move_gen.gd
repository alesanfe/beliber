class_name MoveGen
extends RefCounted

## Generador de movimientos. Las piezas se definen como MAPA DE CASILLAS
## (como en los diagramas): cada celda pintada es un destino posible con
## su código de efecto (ver PiecesData.code_fx).
##
## Semántica:
##  - destino = origen + offset (orientado al jugador)
##  - si el offset está alineado (misma fila/col/diagonal): el camino
##    intermedio debe estar libre, salvo que el código lleve JUMP
##    (ignora piezas) o ATRAVESAR (pasa, inmovilizando enemigos)
##  - si no está alineado (saltos de caballo y similares): no hay camino
##  - la casilla destino se evalúa con los flags del código:
##    MOVE en vacía / CAPTURE en enemiga / EMPUJAR / ATRAER en ocupada
##
## Move: Dictionary {from,to,captures,immobilize,push,attract,castle,
##                   double_step,second,fx,cond,piece_letter,captured_def}

## Atoms derivados de las celdas de una pieza (cache por pieza instancia).
static func cells_of(state: BoardState, piece: Dictionary) -> Dictionary:
	return piece.cells_override if piece.cells_override.size() > 0 \
		else piece.def.cells

static func moves_for(state: BoardState, pos: Vector2i,
		attack_only := false) -> Array:
	var piece: Variant = state.at(pos)
	if piece == null: return []
	if not attack_only and piece.immobilized > 0: return []
	var out: Array = []
	_gen_cells(state, piece, pos, cells_of(state, piece), out, attack_only)
	# Tritón y piezas encadenadas: un segundo juego de celdas tras mover
	var leg2: Variant = piece.def.get("leg2")
	if leg2 != null and not attack_only:
		var chained_out: Array = []
		for mv in out:
			var sim := _sim(state, mv)
			var sub: Array = []
			_gen_cells(sim, sim.at(mv.to), mv.to, leg2, sub, attack_only)
			for s in sub:
				var chained: Dictionary = mv.duplicate(true)
				chained["second"] = s
				chained_out.append(chained)
		out.append_array(chained_out)
	return out

static func _gen_cells(state: BoardState, piece: Dictionary, pos: Vector2i,
		cells: Dictionary, out: Array, attack_only: bool) -> void:
	var sym: String = piece.def.get("sym", "all")
	for key in cells:
		var code: String = cells[key]
		var fx := PiecesData.code_fx(code)
		var cond := PiecesData.code_cond(code)
		if attack_only and cond != FX.C_NONE and cond != FX.C_AQUONTE:
			continue
		if cond == FX.C_DEPLOY and piece.has_moved:
			continue
		var parts: PackedStringArray = key.split(",")
		var local := Vector2i(int(parts[0]), int(parts[1]))
		for off in _offsets(local, sym, piece.owner):
			_gen_one(state, piece, pos, off, fx, cond, code, out, attack_only)

## Expande el offset según simetría del patrón.
static func _offsets(local: Vector2i, sym: String, owner: int) -> Array:
	if sym == "lit":
		return [BoardState.orient(local, owner)]
	# "all": las 8 transformaciones (4 rotaciones × espejo), sin duplicados
	var seen := {}
	var out := []
	var v := local
	for _r in 4:
		for t in [v, Vector2i(-v.x, v.y)]:
			var k := "%d,%d" % [t.x, t.y]
			if not seen.has(k):
				seen[k] = true
				out.append(t)
		v = Vector2i(-v.y, v.x)
	# orientar al jugador (rotación 180 para owner 1)
	var res := []
	for o in out:
		res.append(BoardState.orient(o, owner))
	return res

static func _gen_one(state: BoardState, piece: Dictionary, pos: Vector2i,
		off: Vector2i, fx: int, cond: int, code: String,
		out: Array, attack_only: bool) -> void:
	# offset (0,0) = "mover a la propia casilla": sin sentido para
	# mover/capturar, y con EMPUJAR generaba un empuje degenerado de la
	# propia pieza (dir ZERO → fwd). El editor ya no lo pinta; aquí se
	# filtra por robustez ante JSONs custom previos.
	if off == Vector2i.ZERO: return
	var target := pos + off
	if not BoardState.inside(target): return
	if cond == FX.C_AQUONTE:
		_gen_aquonte(state, piece, pos, off, fx, out)
		return
	if cond == FX.C_EN_PASSANT:
		if not attack_only: _en_passant(state, piece, pos, target, fx, out)
		return
	if cond == FX.C_CASTLE:
		if not attack_only: _castle(state, piece, pos, target, fx, out)
		# 'K' además permite mover o capturar la casilla directamente
		if not (fx & FX.CAPTURE): return
	# camino intermedio para offsets alineados
	var d := off.sign()
	var alineado: bool = off.x == 0 or off.y == 0 or absi(off.x) == absi(off.y)
	var crossed: Array = []
	if alineado:
		var steps := maxi(absi(off.x), absi(off.y))
		for k in range(1, steps):
			var mid := pos + d * k
			var occ: Variant = state.at(mid)
			if occ == null: continue
			if fx & FX.JUMP:
				continue
			if fx & FX.ATRAVESAR:
				if occ.owner != piece.owner:
					crossed.append(mid)
				continue
			return  # bloqueado
	else:
		# offset no alineado: salto puro (como el caballo), el camino no existe
		pass
	_eval_landing(state, piece, pos, target, fx, cond, d, crossed, out,
		attack_only)

static func _eval_landing(state: BoardState, piece: Dictionary, pos: Vector2i,
		target: Vector2i, fx: int, cond: int, dir: Vector2i, crossed: Array,
		out: Array, attack_only: bool) -> void:
	var occ: Variant = state.at(target)
	var mv := {
		"from": pos, "to": target,
		"captures": [], "immobilize": crossed.duplicate(),
		"fx": fx, "cond": cond,
		"piece_letter": piece.def.letter,
	}
	if occ == null:
		if fx & FX.MOVE:
			if cond == FX.C_DEPLOY: mv["double_step"] = true
			out.append(mv)
		return
	if occ.owner != piece.owner:
		if fx & FX.CAPTURE:
			var c := mv.duplicate()
			c.captures = [target]
			c["captured_def"] = occ.def
			out.append(c)
		if not attack_only and (fx & FX.EMPUJAR):
			_try_push(state, pos, target, dir, mv, out)
		if not attack_only and (fx & FX.ATRAER):
			_try_attract(state, pos, mv, out)
	else:
		if not attack_only and (fx & FX.EMPUJAR):
			_try_push(state, pos, target, dir, mv, out)
		if not attack_only and (fx & FX.ATRAER):
			_try_attract(state, pos, mv, out)

static func _try_push(state: BoardState, pos: Vector2i, target: Vector2i,
		dir: Vector2i, mv: Dictionary, out: Array) -> void:
	var d := dir
	if d == Vector2i.ZERO:
		d = Vector2i(0, BoardState.fwd(state.at(pos).owner))
	var landing := target + d
	if not BoardState.inside(landing): return
	if state.at(landing) != null: return
	var m := mv.duplicate(true)
	m["push"] = {"from": target, "to": landing}
	out.append(m)

static func _try_attract(state: BoardState, pos: Vector2i, mv: Dictionary,
		out: Array) -> void:
	var m := mv.duplicate(true)
	m["attract"] = {"from": mv.to, "to": pos}
	out.append(m)

static func _en_passant(state: BoardState, piece: Dictionary, pos: Vector2i,
		cell: Vector2i, fx: int, out: Array) -> void:
	var lm: Dictionary = state.last_move
	if lm.is_empty() or not lm.get("double_step", false): return
	var victim: Variant = lm.piece
	if victim.owner == piece.owner: return
	var victim_cell: Vector2i = lm.to
	if victim_cell.y != pos.y: return
	if cell != victim_cell - Vector2i(0, BoardState.fwd(victim.owner)): return
	# la captura al paso exige que la casilla destino esté libre (si una
	# pieza fue empujada/atraída ahí, mover encima la borraba sin
	# registrar la captura) y la víctima sea el peón que acaba de
	# desplegar
	if state.at(cell) != null: return
	var mv := {
		"from": pos, "to": cell, "captures": [victim_cell],
		"immobilize": [], "fx": fx, "cond": FX.C_EN_PASSANT,
		"piece_letter": piece.def.letter,
		"captured_def": victim.def,
	}
	out.append(mv)

static func _castle(state: BoardState, piece: Dictionary, pos: Vector2i,
		cell: Vector2i, fx: int, out: Array) -> void:
	if piece.has_moved: return
	var dir_x := signi(cell.x - pos.x)
	if dir_x == 0: return
	var rook_pos := Vector2i(-1, -1)
	var x := pos.x + dir_x
	while x >= 0 and x < BoardState.SIZE:
		var p: Variant = state.at(Vector2i(x, pos.y))
		if p != null:
			if p.owner == piece.owner and not p.has_moved \
					and p.def.get("castle_partner", false):
				rook_pos = Vector2i(x, pos.y)
			break
		x += dir_x
	if rook_pos.x < 0: return
	# la celda destino debe estar LIBRE: un 'k/K' sobre la propia
	# torre adyacente (o sobre cualquier pieza) la pisaba en apply()
	# y el intercambio del enroque la borraba del tablero
	if state.at(cell) != null: return
	var a: int = mini(pos.x, rook_pos.x) + 1
	var b: int = maxi(pos.x, rook_pos.x)
	for cx in range(a, b):
		if state.at(Vector2i(cx, pos.y)) != null: return
	var steps := absi(cell.x - pos.x)
	for i in range(0, steps + 1):
		if is_attacked(state, pos + Vector2i(dir_x * i, 0), piece.owner):
			return
	out.append({
		"from": pos, "to": cell, "captures": [], "immobilize": [],
		"fx": fx, "cond": FX.C_CASTLE, "piece_letter": piece.def.letter,
		"castle": {"from": rook_pos, "to": Vector2i(cell.x - dir_x, pos.y)},
	})

## Salto de Aquonte: hay una pieza a distancia k en la línea; se aterriza
## en la casilla a la misma distancia al otro lado (offset 2·d·k desde el
## origen, donde d es la dirección del átomo). La celda `off` marca la
## dirección y alcance máximo del pivote.
static func _gen_aquonte(state: BoardState, piece: Dictionary, pos: Vector2i,
		off: Vector2i, fx: int, out: Array) -> void:
	var d := off.sign()
	var alineado: bool = off.x == 0 or off.y == 0 or absi(off.x) == absi(off.y)
	if not alineado: return
	var steps := maxi(absi(off.x), absi(off.y))
	for k in range(1, steps + 1):
		var mid := pos + d * k
		if not BoardState.inside(mid): break
		var occ: Variant = state.at(mid)
		if occ == null: continue
		var landing := mid + d * k
		if not BoardState.inside(landing): break
		var dest: Variant = state.at(landing)
		var mv := {
			"from": pos, "to": landing, "captures": [], "immobilize": [],
			"fx": fx, "cond": FX.C_AQUONTE,
			"piece_letter": piece.def.letter,
		}
		if dest == null and (fx & FX.MOVE):
			out.append(mv)
		elif dest != null and dest.owner != piece.owner and (fx & FX.CAPTURE):
			mv.captures = [landing]
			mv["captured_def"] = dest.def
			out.append(mv)
		break

static func is_attacked(state: BoardState, cell: Vector2i, owner: int) -> bool:
	for y in BoardState.SIZE:
		for x in BoardState.SIZE:
			var pos := Vector2i(x, y)
			var p: Variant = state.at(pos)
			if p == null or p.owner == owner: continue
			# una pieza inmovilizada no puede mover en el turno
			# relevante — no puede capturar, luego no "amenaza" la
			# casilla (enroque / jaque / mapa de amenazas)
			if p.immobilized > 0: continue
			for mv in moves_for(state, pos, true):
				if mv.to == cell: return true
	return false

## Estado simulado tras un movimiento (para cadenas).
## Estado tras el 1er tramo para generar el 2º (Tritón).
## Reutiliza apply() real en lugar de re-implementar efectos — la versión
## manual no marcaba has_moved ni aplicaba castle/swap/immobilize, así que
## un leg2 con celda C_DEPLOY o en-passant divergía del motor.
## Las piezas se clonan a fondo: apply() muta has_moved/immobilized/
## cells_override y una copia superficial corrompería el estado real.
static func _sim(state: BoardState, mv: Dictionary) -> BoardState:
	var s := BoardState.new()
	for i in state.grid.size():
		var p: Variant = state.grid[i]
		s.grid[i] = p.duplicate(true) if p != null else null
	s.factions = state.factions
	s.last_move = state.last_move
	s.apply(mv)
	return s
