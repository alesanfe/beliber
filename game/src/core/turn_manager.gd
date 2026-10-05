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
			var p := state.new_piece(def, int(e.o))
			# BEL-FEN '*' / editor de posición: piezas ya movidas
			# (sin derecho a doble paso ni enroque)
			p.has_moved = bool(e.get("has_moved", e.get("m", false)))
			state.set_at(Vector2i(int(e.x), int(e.y)), p)
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
	# posición sin líderes (facción custom mal construida): la victoria
	# antes solo se detectaba tras el primer movimiento
	for pl in [0, 1]:
		if state.leaders_alive(pl) == 0:
			over = true
			winner = 1 - pl

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
	# capturas del 1er tramo + del 2º (cadenas Tritón): bandejas,
	# undo y anti-stall deben contar todas
	var all_caps: Array = mv.get("captures", []) \
		+ mv.get("second", {}).get("captures", [])
	history.append({
		"snap": state.snapshot(),
		"current": current,
		"moves_left": moves_left,
		"first_turn_done": first_turn_done.duplicate(),
		"stall_count": stall_count,
		"clock": clock.duplicate(),   # undo también revierte el Fischer
		"log_len": log.size(),
		"caps": all_caps.size(),   # para restaurar bandejas
	})
	# letra REAL de cada captura ANTES de aplicar (después ya están
	# fuera del tablero) — multi-captura llevaba siempre captured_def
	for c in all_caps:
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
	# anti-stall: N turnos sin captura → decide el material. El conteo
	# es por TURNO: la doble apertura de Humenex (2 jugadas en un
	# turno) solo puede consumir 1 del límite, no 2
	if not all_caps.is_empty():
		stall_count = 0
	elif moves_left <= 1:
		stall_count += 1
	if opt_stall > 0 and stall_count >= opt_stall:
		var v0 := material_value(0)
		var v1 := material_value(1)
		over = true
		winner = -1 if v0 == v1 else (0 if v0 > v1 else 1)
		log.append("Límite de inacción: %d vs %d en valor" % [v0, v1])
		game_over.emit(winner)
		return true
	# triple repetición: DESPUÉS de las victorias — una jugada que
	# captura al último líder y repite posición debe ganar, no ser
	# tablas (la repetición se chequeaba antes y "robaba" el mate)
	_count_position()
	if over: return true
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
	# las terminaciones (rendición/tablas/victoria) no están en history:
	# deshacer ahí resucitaba la partida con stats ya registradas
	if over or history.is_empty(): return false
	var h: Dictionary = history.pop_back()
	clock = h.get("clock", clock)   # revierte también el incremento
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
		# has_moved/immobilized cambian los derechos: dos posiciones
		# con las mismas piezas NO son la misma posición
		parts.append("" if p == null else
			"%s%d%d%d%s" % [p.def.letter, p.owner,
				int(p.has_moved), p.immobilized,
				# Consorte tras absorber ≠ misma pieza sin absorber
				"c" if p.cells_override.is_empty() else "x"])
	var tail := ";" + str(current) + "." + str(moves_left)
	# al paso disponible cambia la legalidad: distinta posición
	if not state.last_move.is_empty() \
			and state.last_move.get("double_step", false):
		tail += ".ep"
	return ";".join(parts) + "|" + tail

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
## finish=false: el display sigue corriendo pero la victoria por
## tiempo la decide el servidor autoritativo (antes cada cliente
## flaggeaba por su cuenta y podían divergir).
func tick_clock(dt: float, finish := true) -> void:
	if over or clock.is_empty(): return
	game_secs += dt
	clock[current] -= dt
	if clock[current] <= 0:
		clock[current] = 0
		if not finish: return
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
	return {"v": 1,   # versión del formato — load_game la exige
		"f0": state.factions[0].id, "f1": state.factions[1].id,
		"current": current, "moves_left": moves_left,
		"first": first_turn_done, "stall": stall_count,
		"clock": clock, "clock_inc": clock_inc,
		"log": log, "grid": g,
		"captured": captured_by,    # bandejas de capturadas
		"pos_counts": pos_counts,   # sin esto, cargar reinicia la 3ª repetición
		# al paso tras cargar: last_move referencia la pieza en tablero —
		# se rehace al reconstruir (la pieza guardada sería otra instancia)
		"last_move": {} if state.last_move.is_empty() else {
			"fx": state.last_move.from.x, "fy": state.last_move.from.y,
			"tx": state.last_move.to.x, "ty": state.last_move.to.y,
			"ds": state.last_move.get("double_step", false)},
		"midline": opt_midline, "stall_limit": opt_stall,
		"over": over, "winner": winner}   # partida ya terminada

## Reconstruye una partida guardada. Devuelve null si falla.
static func load_game(data: Dictionary, facs: Array) -> TurnManager:
	# formato versionado: saves sin "v" son heredados (v1); una versión
	# mayor sería un formato que este build no entiende
	if int(data.get("v", 1)) > 1: return null
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
		if not (e is Dictionary): continue
		# JSON manipulado: o fuera de rango o coords fuera del tablero
		# crasheaban el arranque del juego entero
		var eo := int(e.get("o", -1))
		if eo != 0 and eo != 1: continue
		var cell := Vector2i(int(e.get("x", -9)), int(e.get("y", -9)))
		if not BoardState.inside(cell): continue
		var fac: Dictionary = tm.state.factions[eo]
		var def: Dictionary = fac.pieces.get(str(e.l), {})
		if def.is_empty(): continue
		var p := tm.state.new_piece(def, eo)
		p.has_moved = bool(e.get("m", false))
		p.immobilized = int(e.get("i", 0))
		if e.has("c"):
			# solo claves "dx,dy" - claves arbitrarias rompían el split(",")
			# del MoveGen (save manipulado como vector de crash/cheat)
			for k in e.c:
				var kk := str(k).split(",")
				if kk.size() == 2 and kk[0].is_valid_int() \
						and kk[1].is_valid_int():
					p.cells_override[k] = e.c[k]
		tm.state.set_at(cell, p)
	# last_move (al paso): la pieza referenciada es la que está en 'to'
	var lm: Variant = data.get("last_move", {})
	if lm is Dictionary and not lm.is_empty():
		var to := Vector2i(int(lm.get("tx", -1)), int(lm.get("ty", -1)))
		var pc: Variant = tm.state.at(to)
		if pc != null:
			tm.state.last_move = {
				"piece": pc, "from": Vector2i(
					int(lm.get("fx", 0)), int(lm.get("fy", 0))),
				"to": to, "double_step": bool(lm.get("ds", false))}
	# current fuera de {0,1} o clock con elementos no numéricos rompían
	# tick_clock cada frame tras cargar un save manipulado
	tm.current = clampi(int(data.get("current", 0)), 0, 1)
	tm.moves_left = maxi(int(data.get("moves_left", 1)), 0)
	# JSON convierte las claves int en "0"/"1" — hay que reconstruirlas
	# o la doble apertura de Humenex se restaura indebidamente
	var ftd: Variant = data.get("first", {})
	if ftd is Dictionary:
		tm.first_turn_done = {
			0: bool(ftd.get(0, ftd.get("0", false))),
			1: bool(ftd.get(1, ftd.get("1", false)))}
	tm.stall_count = int(data.get("stall", 0))
	var ck: Variant = data.get("clock", [])
	tm.clock = []
	if ck is Array:
		for v in ck:
			tm.clock.append(float(v) if (v is float or v is int) else 0.0)
	tm.clock_inc = float(data.get("clock_inc", 0.0))   # el incremento
	# Fischer se perdía al cargar (el reloj quedaba +0)
	# log es Array[String]: asignar un Array genérico de JSON fallaba
	var lg: Variant = data.get("log", [])
	if lg is Array:
		for s in lg: tm.log.append(str(s))
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
	var saved_counts: Variant = data.get("pos_counts", null)
	if saved_counts is Dictionary:
		# el save ya incluye el conteo de la posición actual (lo sumó
		# play() al guardar) — recontarla producía una triple repetición
		# espuria nada más cargar la partida
		for k in saved_counts: tm.pos_counts[k] = int(saved_counts[k])
	else:
		# saves antiguos sin pos_counts: contar una vez la posición
		tm._count_position()
	# partida terminada al guardar: restaurar el fin — antes se cargaba
	# "en curso" y un reloj a 0 la cerraba al primer tick
	if data.get("over", false):
		tm.over = true
		tm.winner = clampi(int(data.get("winner", -1)), -1, 1)
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

## Convierte una celda de red ({"x","y"} JSON o Vector2i ENet) a
## Vector2i. (-9,-9) si es ilegible — fuera del tablero siempre.
static func _cell(v: Variant) -> Vector2i:
	if v is Vector2i: return v
	if v is Dictionary:
		return Vector2i(int(v.get("x", -9)), int(v.get("y", -9)))
	return Vector2i(-9, -9)

## Localiza la variante legal equivalente a un movimiento REMOTO y
## devuelve la jugada LOCAL completa (efectos/capturas/castle/second).
## En transportes sin árbitro (ENet, relay WS) aplicar el dict del
## rival a ciegas permitía falsificar 'captures'/'push'/campos que
## aquí nunca se consultan: solo se casa from/to/segundo destino.
static func match_legal(tm: TurnManager, mv: Dictionary) -> Variant:
	var frm := _cell(mv.get("from"))
	var to := _cell(mv.get("to"))
	if not BoardState.inside(frm) or not BoardState.inside(to):
		return null
	var st := _cell(mv.get("second_to"))
	if st == Vector2i(-9, -9) and mv.get("second") is Dictionary:
		st = _cell(mv.second.get("to"))
	var hits := []
	for c in tm.legal_moves(frm):
		if c.to != to: continue
		var cst: Vector2i = c.second.to if c.has("second") \
			else Vector2i(-9, -9)
		if st == cst: hits.append(c)
	if hits.is_empty(): return null
	if hits.size() > 1:
		# el mismo from/to puede ser captura O empuje (códigos P/3/e):
		# el remitente incluye 'push'/'captures' en su dict — usarlo
		# como discriminador para aplicar la variante pretendida
		for c in hits:
			if c.has("push") == mv.has("push") \
					and c.get("captures", []).is_empty() \
						== mv.get("captures", []).is_empty():
				return c
	return hits[0]

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
