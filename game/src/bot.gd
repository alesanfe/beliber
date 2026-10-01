class_name BeliberBot
extends RefCounted

## IA por minimax con poda alfa-beta sobre el estado puro del tablero.
## Niveles: 1=profundidad 1 (rápido), 2=profundidad 2, 3=profundidad 3.
## Evalúa material + actividad + peligro sobre líderes.

const INF := 1_000_000
const LEADER_VAL := 200

var depth := 2
var style := "normal"            # normal | aggro | defense
var blunder := 0.0               # probabilidad de jugada subóptima (nivel humano)
var rng := RandomNumberGenerator.new()

func _init(p_depth := 2, p_style := "normal", p_blunder := 0.0) -> void:
	depth = clampi(p_depth, 1, 3)
	style = p_style
	blunder = p_blunder
	# BELIBER_SEED=<n> → RNG determinista (tests reproducibles);
	# sin env, aleatorio normal.
	var s := OS.get_environment("BELIBER_SEED")
	if s.is_valid_int(): rng.seed = int(s)
	else: rng.randomize()

## Bonus de estilo tras aplicar el movimiento sobre el estado clonado.
func _style_bonus(state: BoardState, mv: Dictionary, player: int) -> float:
	var b := 0.0
	# en una cadena la pieza aterriza en second.to — mv.to es el
	# tramo intermedio y premiaba el avance equivocado
	var land: Vector2i = mv.get("second", {}).get("to", mv.to)
	var moved: Variant = state.at(land)
	if style == "aggro":
		# avanzar hacia la fila rival y capturar
		var prog: float = land.y if player == 1 else float(BoardState.SIZE - 1 - land.y)
		b += prog * 0.4 + mv.get("captures", []).size() * 4.0
	elif style == "defense":
		# penaliza dejar la pieza en prise y premiar mantener cobertura
		if moved != null \
				and MoveGen.is_attacked(state, land, player):
			b -= float(moved.def.get("value", 3))
		b += mv.get("captures", []).size() * 1.5
	return b

## Evaluación estática desde el punto de vista de 'player'.
static func evaluate(state: BoardState, player: int) -> int:
	var score := 0
	for p in state.grid:
		if p == null: continue
		var v: int = int(p.def.get("value", 0))
		if p.def.get("leader", false): v += LEADER_VAL
		if p.immobilized > 0: v = int(v * 0.5)
		score += v if p.owner == player else -v
	return score

## Recoge todos los movimientos de un jugador (con posición de origen).
static func _all_moves(state: BoardState, player: int) -> Array:
	var out: Array = []
	for y in BoardState.SIZE:
		for x in BoardState.SIZE:
			var pos := Vector2i(x, y)
			var p: Variant = state.at(pos)
			if p != null and p.owner == player:
				out.append_array(MoveGen.moves_for(state, pos))
	return out

## Clona el estado copiando las piezas (apply() muta has_moved,
## immobilized y cells_override — una copia superficial corrompería
## el estado real durante la búsqueda).
static func _clone_state(state: BoardState) -> BoardState:
	var s := BoardState.new()
	for i in state.grid.size():
		var p: Variant = state.grid[i]
		s.grid[i] = p.duplicate(true) if p != null else null
	s.factions = state.factions
	s.last_move = state.last_move
	return s

static func _leader_dead(state: BoardState, player: int) -> bool:
	for p in state.grid:
		if p != null and p.owner == player \
				and p.def.get("leader", false):
			return false
	return true

func _minimax(state: BoardState, player: int, me: int, d: int,
		alpha: int, beta: int) -> int:
	# condiciones terminales
	if _leader_dead(state, 0):
		return -INF + (depth - d) if 0 == me else INF - (depth - d)
	if _leader_dead(state, 1):
		return -INF + (depth - d) if 1 == me else INF - (depth - d)
	if d <= 0:
		return evaluate(state, me)
	var moves := _all_moves(state, player)
	if moves.is_empty():
		# el motor real PASA el turno (no evalúa estático); si el rival
		# tampoco puede mover, la partida es tablas
		if _all_moves(state, 1 - player).is_empty(): return 0
		return _minimax(state, 1 - player, me, d, alpha, beta)
	if player == me:
		var best := -INF
		for mv in moves:
			var s := _clone_state(state)
			s.apply(mv)
			best = maxi(best, _minimax(s, 1 - player, me, d - 1,
				alpha, beta))
			alpha = maxi(alpha, best)
			if beta <= alpha: break
		return best
	else:
		var best := INF
		for mv in moves:
			var s := _clone_state(state)
			s.apply(mv)
			best = mini(best, _minimax(s, 1 - player, me, d - 1,
				alpha, beta))
			beta = mini(beta, best)
			if beta <= alpha: break
		return best

## Mejor movimiento para 'player' en 'tm'. Devuelve {} si no hay.
func best_move(tm: TurnManager, player: int) -> Dictionary:
	var moves := _all_moves(tm.state, player)
	if moves.is_empty(): return {}
	# mezclar para variedad a igualdad de evaluación
	moves.shuffle()
	var best: Dictionary = moves[0]
	var second: Dictionary = {}
	var best_val := -INF
	var second_val := -INF
	for mv in moves:
		var s := _clone_state(tm.state)
		s.apply(mv)
		var v := float(_minimax(s, 1 - player, player, depth - 1,
			-INF, INF))
		# premio a capturas + sesgo de personalidad
		v += mv.get("captures", []).size()
		v += _style_bonus(s, mv, player)
		if v > best_val:
			second_val = best_val; second = best
			best_val = v; best = mv
		elif v > second_val:
			second_val = v; second = mv
	# errores humanos: a veces elige la 2ª mejor
	if blunder > 0 and not second.is_empty() \
			and rng.randf() < blunder:
		return second
	return best
