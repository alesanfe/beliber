class_name TurnManager
extends RefCounted

## Orquesta turnos, reglas de facción y condición de victoria.

signal move_made(mv: Dictionary)
signal turn_started(player: int)
signal game_over(winner: int)

## Relojes seleccionables [segundos, incremento] — compartido por el
## menú, el cliente WS y el servidor autoritativo (antes duplicado).
const CLOCK_CHOICES := [[0, 0], [60, 0], [180, 2], [300, 0],
	[600, 5], [1800, 0]]

var state: BoardState
var current := 0
var over := false
var winner := -1
var moves_left := 1          # Humenex: 2 en su primer turno
var first_turn_done := {0: false, 1: false}
var log: Array[String] = []

# Opciones de partida (inspiradas en Chess 2 / Chess Evolved Online)
var opt_midline := false     # gana quien lleva un líder a la última fila
var opt_stall := 0           # turnos sin captura → decisión por material

var stall_count := 0
var history: Array = []        # pila de snapshots + metadatos de turno
var clock: Array = []          # [seg0, seg1] o [] si sin reloj
var clock_inc := 0.0           # incremento Fischer por jugada
var pos_counts := {}           # clave de posición → nº de veces (3 = tablas)
var _replay_pos: Array = []    # snapshots tras cada jugada (para replay)
var move_times: Array = []     # segundos usados por jugada (stats)
var _turn_start := 0.0
var captured_by: Array = [[], []]  # letras capturadas por cada jugador
var started := {}              # para resumen: piezas iniciales por jugador
var game_secs := 0.0

func _init(f0: Dictionary, eq0: int, f1: Dictionary, eq1: int,
		options := {}) -> void:
	opt_midline = options.get("midline", false)
	opt_stall = int(options.get("stall_limit", 0))
	var clock_secs: int = int(options.get("clock_secs", 0))
	clock_inc = float(options.get("clock_inc", 0))
	if clock_secs > 0: clock = [clock_secs, clock_secs]
	state = BoardState.new()
	state.factions = [f0, f1]
	var custom: Array = options.get("pos", [])
	if custom.is_empty():
		state.deploy(f0, 0, eq0)
		state.deploy(f1, 1, eq1)
	else:
		# posición libre desde el editor: [{x,y,l,o}]
		for e in custom:
			var def: Dictionary = state.factions[int(e.o)] \
				.pieces.get(str(e.l), {})
			if def.is_empty(): continue
			state.set_at(Vector2i(int(e.x), int(e.y)),
				state.new_piece(def, int(e.o)))
	for pl in [0, 1]:
		started[pl] = []
		for p in state.grid:
			if p != null and p.owner == pl:
				started[pl].append(p.def.letter)
	_replay_pos.append(state.snapshot())   # posición inicial = índice 0
	_count_position()
	_turn_start = Time.get_ticks_msec() / 1000.0
	# orden de salida: Elfos primero, Humenex segundo; o forzado por
	# 'first' (editor de posiciones)
	current = 0
	if f1.rules.get("primero", false) or f0.rules.get("segundo", false):
		current = 1
	elif f0.rules.get("primero", false) or f1.rules.get("segundo", false):
		current = 0
	if options.has("first"):
		current = clampi(int(options.first), 0, 1)
	_begin_turn()

func _begin_turn() -> void:
	moves_left = 1
	var f: Dictionary = state.factions[current]
	if f.rules.get("doble_apertura", false) and not first_turn_done[current]:
		moves_left = 2  # primer turno Humenex = 2 movimientos
	turn_started.emit(current)

func legal_moves(pos: Vector2i) -> Array:
	if over: return []
	var p: Variant = state.at(pos)
	if p == null or p.owner != current: return []
	return MoveGen.moves_for(state, pos)

func play(mv: Dictionary) -> bool:
	if over: return false
	var mover: Variant = state.at(mv.from)
	if mover == null or mover.owner != current: return false
	history.append({
		"snap": state.snapshot(),
		"current": current,
		"moves_left": moves_left,
		"first_turn_done": first_turn_done.duplicate(),
		"stall_count": stall_count,
		"log_len": log.size(),
		"caps": mv.get("captures", []).size(),   # para restaurar bandejas
	})
	# letra REAL de cada captura ANTES de aplicar (después ya están
	# fuera del tablero) — multi-captura llevaba siempre captured_def
	for c in mv.get("captures", []):
		var vic: Variant = state.at(c)
		captured_by[current].append(
			vic.def.letter if vic != null else "?")
	state.apply(mv)
	move_times.append(Time.get_ticks_msec() / 1000.0 - _turn_start)
	_turn_start = Time.get_ticks_msec() / 1000.0
	if clock_inc > 0 and not clock.is_empty():
		clock[current] += clock_inc
	# devolver snapshot a la lista de posiciones para replay
	_replay_pos.append(state.snapshot())
	_count_position()
	log.append("J%d %s" % [current + 1, state.describe(mv)])
	move_made.emit(mv)
	# victoria: líder(es) eliminados
	for pl in [0, 1]:
		if state.leaders_alive(pl) == 0:
			over = true
			winner = 1 - pl
			game_over.emit(winner)
			return true
	# midline invasion: líder llega a la última fila rival
	if opt_midline:
		var target_row := 0 if current == 0 else BoardState.SIZE - 1
		for x in BoardState.SIZE:
			var p: Variant = state.at(Vector2i(x, target_row))
			if p != null and p.owner == current \
					and p.def.get("leader", false):
				over = true
				winner = current
				log.append("¡Invasión de línea!")
				game_over.emit(winner)
				return true
	# material insuficiente: solo quedan líderes → tablas
	if _check_bare():
		over = true
		winner = -1
		log.append("Tablas: material insuficiente")
		game_over.emit(-1)
		return true
	# anti-stall: N turnos sin captura → decide el material
	stall_count = 0 if not mv.get("captures", []).is_empty() \
		else stall_count + 1
	if opt_stall > 0 and stall_count >= opt_stall:
		var v0 := material_value(0)
		var v1 := material_value(1)
		over = true
		winner = -1 if v0 == v1 else (0 if v0 > v1 else 1)
		log.append("Límite de inacción: %d vs %d en valor" % [v0, v1])
		game_over.emit(winner)
		return true
	moves_left -= 1
	if moves_left <= 0:
		first_turn_done[current] = true
		# la inmovilización dura exactamente un turno del dueño: se limpia
		# al terminar el turno del jugador afectado
		_tick_immobilized(current)
		current = 1 - current
		_begin_turn()
		# si el jugador no puede mover, pasa turno; si nadie puede mover,
		# es tablas
		var guard := 0
		while not over and all_moves(current).is_empty() and guard < 3:
			guard += 1
			_tick_immobilized(current)
			current = 1 - current
			_begin_turn()
		if guard >= 3:
			over = true
			winner = -1
			game_over.emit(-1)
	return true

## Deshacer la última jugada (un movimiento, no todo el turno).
func undo() -> bool:
	if history.is_empty(): return false
	var h: Dictionary = history.pop_back()
	# la posición PRE-jugada ya estaba contada; al deshacer hay que
	# descontar también la posición POST-jugada (se va a revertir)
	var pk := _pos_key()
	if pos_counts.has(pk):
		pos_counts[pk] -= 1
	_replay_pos.pop_back()   # el snapshot post-jugada sale del replay
	state.restore(h.snap)
	current = h.current
	moves_left = h.moves_left
	first_turn_done = h.first_turn_done
	stall_count = h.stall_count
	over = false
	winner = -1
	log.resize(h.log_len)
	# devolver las piezas capturadas a su bando (las bandejas y el
	# contador del resumen no reflejaban el undo)
	for _i in int(h.get("caps", 0)):
		if not captured_by[current].is_empty():
			captured_by[current].pop_back()
	if not move_times.is_empty(): move_times.pop_back()
	turn_started.emit(current)
	return true

## Rendición: el jugador actual pierde la partida.
func resign(player: int) -> void:
	if over: return
	over = true
	winner = 1 - player
	log.append("J%d se rinde" % (player + 1))
	game_over.emit(winner)

## Exporta el registro de la partida en notación compacta.
func export_log(path: String) -> String:
	var lines := PackedStringArray()
	lines.append("# Beliber — %s vs %s" % [
		state.factions[0].name, state.factions[1].name])
	for i in log.size():
		lines.append("%d. %s" % [i + 1, log[i]])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return ""
	f.store_string("\n".join(lines))
	f.close()
	return path

## Clave de posición para repetición triple (ignora historial).
func _pos_key() -> String:
	var parts := PackedStringArray()
	for i in state.grid.size():
		var p: Variant = state.grid[i]
		parts.append("" if p == null else
			"%s%d" % [p.def.letter, p.owner])
	return ";".join(parts) + "|" + str(current)

func _count_position() -> void:
	var k := _pos_key()
	pos_counts[k] = pos_counts.get(k, 0) + 1
	# tres repeticiones de la misma posición → tablas
	if pos_counts[k] >= 3 and not over:
		over = true
		winner = -1
		log.append("Tablas por triple repetición")
		game_over.emit(-1)

## Material insuficiente: ambos bandos sin piezas no-líder → tablas.
func _check_bare() -> bool:
	var bare0 := true
	var bare1 := true
	for p in state.grid:
		if p == null or p.def.get("leader", false): continue
		if p.owner == 0: bare0 = false
		else: bare1 = false
	return bare0 and bare1

## Tablas acordadas (ambos humanos en local → inmediato).
func agree_draw() -> void:
	if over: return
	over = true
	winner = -1
	log.append("Tablas acordadas")
	game_over.emit(-1)

## Avanza el reloj del jugador actual (llamar cada frame desde main).
func tick_clock(dt: float) -> void:
	if over or clock.is_empty(): return
	game_secs += dt
	clock[current] -= dt
	if clock[current] <= 0:
		clock[current] = 0
		over = true
		winner = 1 - current
		log.append("Tiempo agotado para J%d" % (current + 1))
		game_over.emit(winner)

## Serializa la partida para guardar/cargar.
func save_game() -> Dictionary:
	var g := []
	for y in BoardState.SIZE:
		for x in BoardState.SIZE:
			var p: Variant = state.at(Vector2i(x, y))
			if p == null: continue
			var e := {"x": x, "y": y, "l": p.def.letter,
				"o": p.owner, "m": p.has_moved, "i": p.immobilized}
			if not p.cells_override.is_empty():
				e["c"] = p.cells_override
			g.append(e)
	return {"f0": state.factions[0].id, "f1": state.factions[1].id,
		"current": current, "moves_left": moves_left,
		"first": first_turn_done, "stall": stall_count,
		"clock": clock, "log": log, "grid": g,
		"captured": captured_by,    # bandejas de capturadas
		"midline": opt_midline, "stall_limit": opt_stall}

## Reconstruye una partida guardada. Devuelve null si falla.
static func load_game(data: Dictionary, facs: Array) -> TurnManager:
	var f0: Dictionary; var f1: Dictionary
	for f in facs:
		if f.id == data.get("f0"): f0 = f
		if f.id == data.get("f1"): f1 = f
	if f0.is_empty() or f1.is_empty(): return null
	var tm := TurnManager.new(f0, 0, f1, 0,
		{"midline": data.get("midline", false),
			"stall_limit": int(data.get("stall_limit", 0)),
			"clock_secs": 0})
	# reconstruye el tablero desde cero
	for i in tm.state.grid.size(): tm.state.grid[i] = null
	for e in data.get("grid", []):
		var fac: Dictionary = tm.state.factions[int(e.o)]
		var def: Dictionary = fac.pieces.get(str(e.l), {})
		if def.is_empty(): continue
		var p := tm.state.new_piece(def, int(e.o))
		p.has_moved = bool(e.get("m", false))
		p.immobilized = int(e.get("i", 0))
		if e.has("c"):
			for k in e.c: p.cells_override[k] = e.c[k]
		tm.state.set_at(Vector2i(int(e.x), int(e.y)), p)
	tm.current = int(data.get("current", 0))
	tm.moves_left = int(data.get("moves_left", 1))
	tm.first_turn_done = data.get("first", {0: false, 1: false})
	tm.stall_count = int(data.get("stall", 0))
	tm.clock = data.get("clock", [])
	tm.log = Array(data.get("log", []))
	# restaurar las capturas (bandejas + material del resumen)
	var caps: Variant = data.get("captured", null)
	if caps is Array and caps.size() >= 2:
		tm.captured_by = [Array(caps[0]), Array(caps[1])]
	tm.history = []
	# el snapshot 0 del constructor es el despliegue oficial — para una
	# partida cargada el "inicio" del replay es la posición guardada
	tm._replay_pos = [tm.state.snapshot()]
	# igual con 'started': refleja el despliegue oficial, no el guardado
	for pl in [0, 1]:
		tm.started[pl] = []
		for p in tm.state.grid:
			if p != null and p.owner == pl:
				tm.started[pl].append(p.def.letter)
	tm.pos_counts = {}
	tm._count_position()
	return tm

## Posición del replay: i=0 → inicial; i=n → tras n jugadas.
func replay_snapshot(i: int) -> Variant:
	if i < 0 or i >= _replay_pos.size(): return null
	return _replay_pos[i]

func replay_len() -> int:
	return _replay_pos.size()

func _tick_immobilized(player: int) -> void:
	for p in state.grid:
		if p != null and p.owner == player and p.immobilized > 0:
			p.immobilized -= 1

func all_moves(player: int) -> Array:
	var out: Array = []
	for y in BoardState.SIZE:
		for x in BoardState.SIZE:
			var pos := Vector2i(x, y)
			var p: Variant = state.at(pos)
			if p != null and p.owner == player:
				out.append_array(MoveGen.moves_for(state, pos))
	return out

## Valor material vivo de un jugador (suma de 'value' de sus piezas).
func material_value(player: int) -> int:
	var total := 0
	for p in state.grid:
		if p != null and p.owner == player:
			total += int(p.def.get("value", 0))
	return total

## Mapa de cobertura: casillas atacadas por 'player' (para UI estilo CEO).
func coverage(player: int) -> Dictionary:
	var map := {}
	for mv in all_moves(player):
		var fx: int = mv.get("fx", 0)
		if fx & (FX.CAPTURE | FX.MOVE):
			map[mv.to] = true
	return map
