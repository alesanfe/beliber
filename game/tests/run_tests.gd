extends SceneTree

## Tests del motor. Ejecutar:
##   godot --headless -s tests/run_tests.gd

var failures := 0

func _init() -> void:
	print("== Beliber: tests del motor ==")
	_test_deploy()
	_test_pawn_moves()
	_test_knight_jumps()
	_test_turns_and_humenex_double()
	_test_elfos_first()
	_test_push()
	_test_immobilize()
	_test_consorte_swap()
	_test_win_by_leader()
	_test_undo_resign_export()
	_test_bot_and_save()
	_test_replay_and_clock()
	_test_perft()
	_test_piece_patterns()
	_test_puzzle_gen()
	_test_belfen()
	_test_belfen_bad()
	_test_load_fields()
	_test_undo_after_over()
	_test_castle_partner()
	_test_chain_apply()
	_test_castle_adjacent()
	_test_save_roundtrip()
	_test_undo_clock()
	_test_leg2_caps()
	_test_match_legal()
	_test_zero_and_leg2_deploy()
	_test_load_regression()
	_test_bak_recovery()
	print("== %s ==" % ("OK" if failures == 0 else "%d FALLOS" % failures))
	quit(0 if failures == 0 else 1)

func _ok(cond: bool, name: String) -> void:
	if cond:
		print("  PASS ", name)
	else:
		failures += 1
		printerr("  FAIL ", name)

func _tm(f0id := "humenex", f1id := "humenex") -> TurnManager:
	var all := PiecesData.all()
	var f0: Dictionary; var f1: Dictionary
	for f in all:
		if f.id == f0id: f0 = f
		if f.id == f1id: f1 = f
	return TurnManager.new(f0, 0, f1, 0)

func _find(state: BoardState, owner: int, letter: String) -> Vector2i:
	for y in 8:
		for x in 8:
			var p: Variant = state.at(Vector2i(x, y))
			if p != null and p.owner == owner and p.def.letter == letter:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _targets(moves: Array) -> Array:
	var t := []
	for m in moves: t.append(m.to)
	return t

func _test_deploy() -> void:
	var tm := _tm()
	var n := 0
	for p in tm.state.grid: if p != null: n += 1
	_ok(n == 32, "despliegue Humenex: 32 piezas")
	_ok(tm.state.leaders_alive(0) == 1, "1 líder por jugador")

func _empty_state(f0id := "humenex", f1id := "humenex") -> BoardState:
	var st := BoardState.new()
	for f in PiecesData.all():
		if f.id == f0id or f.id == f1id:
			st.factions.append(f)
	return st

func _test_pawn_moves() -> void:
	# escenario sintético: peón solo en campo abierto
	var st := _empty_state()
	var pos := Vector2i(4, 4)
	st.set_at(pos, st.new_piece(st.factions[0].pieces["P"], 0))
	var t := _targets(MoveGen.moves_for(st, pos))
	_ok(t.has(Vector2i(4, 3)), "peón avanza 1")
	_ok(t.has(Vector2i(4, 2)), "peón despliegue doble")
	_ok(not t.has(Vector2i(5, 3)), "peón no captura casilla vacía")

func _test_knight_jumps() -> void:
	# escenario sintético: caballero rodeado de peones debe saltar
	var st := _empty_state()
	var def: Dictionary = st.factions[0].pieces["C"]
	var pos := Vector2i(4, 4)
	st.set_at(pos, st.new_piece(def, 0))
	var peon: Dictionary = st.factions[0].pieces["P"]
	for o in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1),
			Vector2i(-1, 0), Vector2i(1, -1), Vector2i(-1, -1)]:
		st.set_at(pos + o, st.new_piece(peon, 0))
	var t := _targets(MoveGen.moves_for(st, pos))
	_ok(t.has(pos + Vector2i(1, -2)), "caballero en L")
	_ok(t.size() == 8, "caballero salta sobre peones (8 salidas)")

func _test_turns_and_humenex_double() -> void:
	var tm := _tm("elfos", "humenex")
	# elfos primero, humenex segundo con doble apertura
	_ok(tm.current == 0, "elfos (J1) abren")
	var moves0: Array = tm.all_moves(0)
	_ok(moves0.size() > 0, "elfos tiene movimientos")
	tm.play(moves0[0])
	_ok(tm.current == 1, "turno pasa a humenex")
	_ok(tm.moves_left == 2, "humenex: 2 movimientos en su apertura")
	var moves1: Array = tm.all_moves(1)
	tm.play(moves1[0])
	_ok(tm.current == 1, "humenex aún tiene su 2º movimiento")
	var moves2: Array = tm.all_moves(1)
	tm.play(moves2[0])
	_ok(tm.current == 0, "doble apertura agotada")

func _test_elfos_first() -> void:
	var tm := _tm("elfos", "kronturs")
	_ok(tm.current == 0, "elfos siempre primeros")

func _test_push() -> void:
	# Mole (kronturs) empuja frontalmente: poner enemigo delante
	var tm := _tm("kronturs", "humenex")
	var st := tm.state
	var mpos := Vector2i(0, 5)  # Mole con camino libre hacia delante
	var target := mpos + Vector2i(0, -2)  # casilla 'e' del Mole: empujar
	var enemy := st.new_piece(st.factions[1].pieces["P"], 1)
	st.set_at(target, enemy)
	var moves := MoveGen.moves_for(st, mpos)
	var push: Dictionary = {}
	for mv in moves:
		if mv.to == target and mv.has("push"): push = mv
	_ok(not push.is_empty(), "mole puede empujar")
	if not push.is_empty():
		st.apply(push)
		_ok(st.at(target) != null and st.at(target).def.letter == "M",
			"mole ocupa la casilla")
		_ok(st.at(target + Vector2i(0, -1)) == enemy,
			"enemigo empujado una casilla")

func _test_immobilize() -> void:
	# Forestal atraviesa e inmoviliza enemigos
	var tm := _tm("elfos", "humenex")
	var st := tm.state
	var fpos := _find(st, 0, "F")
	# colocar enemigo en el camino del forestal
	var block := fpos + Vector2i(0, -2)
	var enemy := st.new_piece(st.factions[1].pieces["P"], 1)
	st.set_at(block, enemy)
	var moves := MoveGen.moves_for(st, fpos)
	var thru: Dictionary = {}
	for mv in moves:
		if mv.to == fpos + Vector2i(0, -3): thru = mv
	_ok(not thru.is_empty() and thru.get("immobilize", []).has(block),
		"forestal atraviesa marcando inmovilización")
	if not thru.is_empty():
		st.apply(thru)
		_ok(st.at(block).immobilized > 0, "enemigo inmovilizado")
		_ok(MoveGen.moves_for(st, block).is_empty(),
			"pieza inmovilizada no genera movimientos")

func _test_consorte_swap() -> void:
	var tm := _tm("mortifers", "humenex")
	var st := tm.state
	var cpos := _find(st, 0, "X")
	# celda 'J' a distancia 2: salta por encima de los propios carroñeros
	var target := cpos + Vector2i(0, -2)
	var victim := st.new_piece(st.factions[1].pieces["T"], 1)
	st.set_at(target, victim)
	var cap: Dictionary = {}
	for mv in MoveGen.moves_for(st, cpos):
		if mv.to == target and mv.get("captures", []).has(target): cap = mv
	_ok(not cap.is_empty(), "consorte puede capturar")
	if not cap.is_empty():
		st.apply(cap)
		var cons: Dictionary = st.at(target)
		_ok(cons.cells_override == st.factions[1].pieces["T"].cells,
			"consorte adopta movimientos de la torre capturada")

func _test_win_by_leader() -> void:
	var tm := _tm()
	var st := tm.state
	var me: int = tm.current
	var rival := 1 - me
	var ypos := _find(st, rival, "Y")
	st.set_at(ypos, null)  # simular captura del emperador
	_ok(st.leaders_alive(rival) == 0, "líder eliminado")
	var moves: Array = tm.all_moves(me)
	tm.play(moves[0])
	_ok(tm.over and tm.winner == me, "victoria al eliminar líder")

func _test_undo_resign_export() -> void:
	var tm := _tm("elfos", "humenex")
	var before := tm.state.snapshot()
	var cur := tm.current
	var moves: Array = tm.all_moves(cur)
	tm.play(moves[0])
	_ok(tm.history.size() == 1, "historial registra jugada")
	_ok(tm.undo(), "deshacer devuelve true")
	var same := true
	for i in before.grid.size():
		var a: Variant = before.grid[i]
		var b: Variant = tm.state.grid[i]
		if (a == null) != (b == null): same = false
		elif a != null and (a.def.letter != b.def.letter \
				or a.owner != b.owner): same = false
	_ok(same and tm.current == cur, "deshacer restaura tablero y turno")
	var me := tm.current
	tm.resign(me)
	_ok(tm.over and tm.winner == 1 - me, "rendición da la victoria al rival")
	var p := tm.export_log("user://test_match.txt")
	_ok(p != "" and FileAccess.file_exists(p), "exportar partida crea fichero")

func _test_bot_and_save() -> void:
	var tm := _tm("elfos", "humenex")
	var bot := BeliberBot.new(1)
	var mv := bot.best_move(tm, tm.current)
	_ok(not mv.is_empty(), "bot propone un movimiento")
	_ok(BoardState.inside(mv.to), "movimiento del bot dentro del tablero")
	# guardar → restaurar
	var data := tm.save_game()
	var tm2 := TurnManager.load_game(data, PiecesData.all())
	_ok(tm2 != null, "cargar partida funciona")
	var cnt := 0
	for p in tm2.state.grid: if p != null: cnt += 1
	_ok(cnt == 32, "partida cargada conserva 32 piezas")
	_ok(tm2.current == tm.current, "partida cargada conserva el turno")

func _test_replay_and_clock() -> void:
	var tm := _tm("elfos", "humenex")
	_ok(tm.replay_len() == 1, "replay empieza con posición inicial")
	var m0: Array = tm.all_moves(tm.current)
	tm.play(m0[0])
	var m1: Array = tm.all_moves(tm.current)
	tm.play(m1[0])
	_ok(tm.replay_len() == 3, "replay acumula snapshots")
	var s0: Variant = tm.replay_snapshot(0)
	_ok(s0 != null and s0.grid.size() == 64, "replay snapshot 0 válido")
	# reloj con incremento Fischer
	var all := PiecesData.all()
	var f0: Dictionary; var f1: Dictionary
	for f in all:
		if f.id == "elfos": f0 = f
		if f.id == "humenex": f1 = f
	var tc := TurnManager.new(f0, 0, f1, 0,
		{"clock_secs": 10, "clock_inc": 2})
	_ok(tc.clock.size() == 2 and tc.clock[0] == 10, "reloj inicializado")
	tc.tick_clock(3.0)
	_ok(abs(tc.clock[0] - 7) < 0.001, "reloj descuenta tiempo")
	var mv0: Array = tc.all_moves(tc.current)
	tc.play(mv0[0])
	_ok(tc.clock[0] > 7, "incremento Fischer suma tiempo")
	tc.tick_clock(600.0)
	_ok(tc.over and tc.winner == 0, "victoria por tiempo agotado")

## Perft: cuenta hojas a profundidad n; debe ser determinista y > 0.
func _perft(st: BoardState, player: int, d: int) -> int:
	if d == 0: return 1
	var n := 0
	for y in 8:
		for x in 8:
			var pos := Vector2i(x, y)
			var p: Variant = st.at(pos)
			if p == null or p.owner != player: continue
			for mv in MoveGen.moves_for(st, pos):
				var s := BoardState.new()
				for i in st.grid.size():
					var q: Variant = st.grid[i]
					s.grid[i] = q.duplicate(true) if q != null else null
				s.factions = st.factions
				s.last_move = st.last_move
				s.apply(mv)
				n += _perft(s, 1 - player, d - 1)
	return n

func _test_perft() -> void:
	var tm := _tm("humenex", "humenex")
	var a := _perft(tm.state, 0, 1)
	var b := _perft(tm.state, 0, 1)
	var c := _perft(tm.state, 0, 2)
	_ok(a > 0, "perft(1) genera movimientos")
	_ok(a == b, "perft determinista")
	_ok(c > a, "perft(2) expande posiciones")
	# posición libre desde el editor
	var pos_arr := [
		{"x": 4, "y": 7, "l": "Y", "o": 0},
		{"x": 4, "y": 0, "l": "Y", "o": 1},
		{"x": 0, "y": 4, "l": "T", "o": 0},
	]
	var tp := TurnManager.new(tm.state.factions[0], 0,
		tm.state.factions[1], 0, {"pos": pos_arr, "first": 1})
	var cnt2 := 0
	for q in tp.state.grid: if q != null: cnt2 += 1
	_ok(cnt2 == 3, "posición libre: 3 piezas colocadas")
	_ok(tp.current == 1, "posición libre: turno inicial forzado")

## Regresión de patrones contra los diagramas de referencia.
## Compara la celda canónica almacenada ("dx,dy") con el código esperado.
func _cell(defs: Dictionary, letter: String, dx: int, dy: int) -> String:
	var p: Dictionary = defs[letter]
	var key := "%d,%d" % [dx, dy]
	if p.cells.has(key):
		return p.cells[key]
	if p.get("sym", "all") != "all":
		return "."
	# "all": la celda consultada puede estar en la órbita D4 de otra clave
	var t := Vector2i(dx, dy)
	for k in p.cells:
		var parts: PackedStringArray = k.split(",")
		var v := Vector2i(int(parts[0]), int(parts[1]))
		for _r in 4:
			for s in [v, Vector2i(-v.x, v.y)]:
				if s == t:
					return p.cells[k]
			v = Vector2i(-v.y, v.x)
	return "."

func _expect(defs: Dictionary, letter: String, dx: int, dy: int,
		code: String, nota: String) -> void:
	_ok(_cell(defs, letter, dx, dy) == code,
		"%s %d,%d == '%s' (%s)" % [letter, dx, dy, code, nota])

func _test_piece_patterns() -> void:
	var f := {}
	for fac in PiecesData.all(): f[fac.id] = fac.pieces
	var hum: Dictionary = f.humenex
	_expect(hum, "Y", 0, -1, "o", "emperador avanza frontal")
	_expect(hum, "Y", -1, -1, "o", "emperador diag frontal")
	_expect(hum, "Y", 1, 0, "K", "emperador: M/C o enroque lateral")
	_expect(hum, "Y", -1, 0, "K", "emperador: K a la izquierda")
	for d in [-4, -3, -2, 2, 3, 4]:
		_expect(hum, "Y", d, 0, "k", "emperador: fila de enroque")
	_expect(hum, "Y", 1, 1, ".", "emperador: sin celda lateral atrás")
	var elf: Dictionary = f.elfos
	_expect(elf, "X", 1, 0, "w", "dama: atraviesa capturando cerca")
	_expect(elf, "X", 3, 0, "w", "dama: w ortogonal hasta 3")
	_expect(elf, "X", 4, 0, "t", "dama: solo mover tras 3")
	_expect(elf, "X", 2, 2, "w", "dama: w diagonal hasta 2")
	_expect(elf, "X", 3, 3, "t", "dama: solo mover diagonal tras 2")
	_expect(elf, "X", 1, 2, "j", "dama: salto caballo")
	_expect(elf, "X", 2, 1, "j", "dama: salto caballo 2")
	_expect(elf, "Y", 1, 0, "w", "monarca: atraviesa y captura")
	_expect(elf, "Y", 1, 1, "w", "monarca diagonal w")
	_expect(elf, "H", 1, 1, "w", "hostigador: w cerca en diagonal")
	_expect(elf, "H", 3, 3, "w", "hostigador: w diagonal hasta 3")
	_expect(elf, "H", 4, 4, "T", "hostigador: captura atravesando lejos")
	_expect(elf, "H", 0, -1, "t", "hostigador: ortogonal mover")
	_expect(elf, "E", 2, 2, "T", "explorador: diagonal T desde 2")
	_expect(elf, "E", 7, 7, "T", "explorador: T alcanza la esquina")
	_expect(elf, "E", 1, 1, ".", "explorador: sin celda en -1,-1")
	_expect(elf, "E", 1, 2, "j", "explorador: salto caballo")
	var mor: Dictionary = f.mortifers
	_expect(mor, "X", 4, 4, "c", "consorte: captura en diag 4")
	_expect(mor, "X", 4, 0, "o", "consorte: ortogonal sigue o en 4")
	var bes: Dictionary = f.bestiarios
	_expect(bes, "F", 3, 0, "J", "fugaz: salto (3,0)")
	_expect(bes, "F", 0, -3, "J", "fugaz: salto (0,3)")
	_expect(bes, "F", 2, 2, "J", "fugaz: salto diagonal (2,2)")
	_expect(bes, "F", -2, -2, "J", "fugaz: salto diagonal (-2,-2)")
	_expect(bes, "F", 1, 3, ".", "fugaz: sin salto de camello (1,3)")
	_expect(bes, "F", 0, 4, ".", "fugaz: sin salto (0,4)")
	_expect(bes, "E", 0, -4, "o", "edaz: ortogonal hasta 4")
	_expect(bes, "E", 3, 3, "o", "edaz: diagonal hasta 3")
	_expect(bes, "E", 1, 2, ".", "edaz: sin saltos de caballo")
	_expect(bes, "A", -2, -2, "j", "audaz: bloque salta 2x2")
	var aqu: Dictionary = f.aquontes
	_expect(aqu, "A", 0, -5, "q", "alevín: aquonte alcanza 5")
	_expect(aqu, "X", 3, 0, "Q", "anfitrite: M/C o Aquonte")
	_expect(aqu, "X", 3, 3, "Q", "anfitrite: Q en diagonal")
	_expect(aqu, "M", 3, 3, "Q", "mako: Q en diagonal")
	_expect(aqu, "C", 3, 0, "Q", "carchar: Q ortogonal")
	_expect(aqu, "T", 1, -1, "o", "tritón: paso 1 diagonal")
	_expect(aqu, "T", -1, -1, ".", "tritón: paso 1 solo a la derecha")
	_ok(aqu["T"].get("leg2", {}).get("-2,-2") == "Q",
		"tritón: 2 movimiento = salto Aquonte")
	var chl: Dictionary = f.chlontos
	_expect(chl, "C", 0, -2, "g", "céfiro: captura salta lejos")
	_expect(chl, "C", -2, -2, "g", "céfiro: g diagonal")
	_expect(chl, "C", -1, -2, "j", "céfiro: solo mover cerca")
	_expect(chl, "C", -1, 0, ".", "céfiro: sin aquonte")
	# celdas de enroque del emperador deben generar movimientos k/K
	var st := _empty_state()
	var ypos := Vector2i(3, 6)
	st.set_at(ypos, st.new_piece(hum["Y"], 0))
	var movs := MoveGen.moves_for(st, ypos)
	var k_cells := 0
	for mv in movs:
		if mv.get("castle") != null: k_cells += 1
	_ok(k_cells == 0, "emperador sin torre no enroca")
	var tdef: Dictionary = hum["T"]
	st.set_at(Vector2i(7, 6), st.new_piece(tdef, 0))
	movs = MoveGen.moves_for(st, ypos)
	k_cells = 0
	var k_dsts := []
	for mv in movs:
		if mv.get("castle") != null:
			k_cells += 1
			k_dsts.append(mv.to)
	_ok(k_cells > 0, "emperador enroca hacia la torre")
	_ok(k_dsts.has(Vector2i(5, 6)) or k_dsts.has(Vector2i(6, 6)),
		"enroque: rey aterriza en celda k de la fila")

func _test_puzzle_gen() -> void:
	# posicion puzzle: la torre J0 puede capturar al lider J1 en 1
	var tm0 := _tm("humenex", "elfos")
	var pos := [
		{"x": 4, "y": 7, "l": "Y", "o": 0},
		{"x": 6, "y": 4, "l": "Y", "o": 1},
		{"x": 0, "y": 4, "l": "T", "o": 0},
	]
	var t := TurnManager.new(tm0.state.factions[0], 0,
		tm0.state.factions[1], 0, {"pos": pos, "first": 0})
	var killer: Variant = null
	for mv in t.legal_moves(Vector2i(0, 4)):
		for c in mv.get("captures", []):
			var p: Variant = t.state.at(c)
			if p != null and p.def.get("leader", false):
				killer = mv
	_ok(killer != null, "puzzle: captura de lider detectada en 1")
	if killer != null:
		t.play(killer)
		_ok(t.over and t.winner == 0, "puzzle: capturar lider gana")

## Round-trip BEL-FEN: serializar y re-parsear una posición.
func _test_belfen() -> void:
	var tm0 := _tm("humenex", "elfos")
	var s := BoardState.to_bel(tm0.state, 0, 0, 1, 0, 0)
	_ok(s.begins_with("BEL1 "), "BEL-FEN: prefijo")
	var r: Dictionary = BoardState.from_bel(s)
	_ok(not r.has("err"), "BEL-FEN: parsea sin error")
	_ok(r.fac[0] == 0 and r.fac[2] == 1, "BEL-FEN: facciones")
	_ok(r.pos.size() == 32, "BEL-FEN: 32 piezas desplegadas")
	var t2 := TurnManager.new(tm0.state.factions[0], 0,
		tm0.state.factions[1], 0, {"pos": r.pos, "first": 1})
	_ok(t2.state.leaders_alive(0) > 0 and t2.state.leaders_alive(1) > 0,
		"BEL-FEN: lideres presentes tras importar")
	_ok(t2.current == 1, "BEL-FEN: turno restaurado")

## Entradas corruptas deben devolver {"err":…}, nunca indexar fuera
## de rango ni colar piezas fuera del tablero.
func _test_belfen_bad() -> void:
	_ok(BoardState.from_bel("basura").has("err"), "BEL malo: prefijo")
	_ok(BoardState.from_bel("BEL1 0 8/8/8/8/8/8/8/8 0").has("err"),
		"BEL malo: facción sin punto")
	_ok(BoardState.from_bel("BEL1 a.b 0.0 8/8/8/8/8/8/8/8 0").has("err"),
		"BEL malo: facción no numérica")
	_ok(BoardState.from_bel("BEL1 0.0 0.0 8/8/8 0").has("err"),
		"BEL malo: pocas filas")
	_ok(BoardState.from_bel("BEL1 0.0 0.0 9/8/8/8/8/8/8/8 0").has("err"),
		"BEL malo: fila desbordada")
	_ok(BoardState.from_bel("BEL1 0.0 0.0 8/8/8/8/8/8/8/8 9").has("err"),
		"BEL malo: turno inválido")

## save/load conserva clock_inc y pos_counts (antes se perdían).
func _test_load_fields() -> void:
	var tm := _tm()
	var bot := BeliberBot.new(1)
	for i in 4:
		var mv := bot.best_move(tm, tm.current)
		if mv.is_empty(): break
		tm.play(mv)
	tm.clock_inc = 2.5
	var data := tm.save_game()
	var back := TurnManager.load_game(data,
		[tm.state.factions[0], tm.state.factions[1]])
	_ok(back != null, "load: reconstruye")
	_ok(is_equal_approx(back.clock_inc, 2.5),
		"load: clock_inc conservado")
	# pos_counts: todas las claves guardadas sobreviven al round-trip
	# (la recarga recuenta la posición actual, que puede ser una clave
	# nueva si el turno decayó inmovilizaciones tras la última jugada)
	var shared := 0
	for k in tm.pos_counts:
		if back.pos_counts.has(k): shared += 1
	_ok(shared == tm.pos_counts.size(),
		"load: pos_counts conservados")

## Undo tras el fin no resucita la partida.
func _test_undo_after_over() -> void:
	var tm := _tm()
	tm.resign(0)
	_ok(not tm.undo(), "undo tras rendición: bloqueado")
	var tm2 := _tm()
	tm2.agree_draw()
	_ok(not tm2.undo(), "undo tras tablas: bloqueado")

## castle_partner (flag en el def) sustituye la lista hardcodeada.
func _test_castle_partner() -> void:
	var hum: Dictionary = _tm().state.factions[0].pieces
	_ok(hum["T"].get("castle_partner", false),
		"torre: castle_partner flag")
	var st := _empty_state()
	var ypos := Vector2i(3, 6)
	st.set_at(ypos, st.new_piece(hum["Y"], 0))
	# una pieza normal en la fila NO habilita el enroque
	st.set_at(Vector2i(7, 6), st.new_piece(hum["P"], 0))
	var k := 0
	for mv in MoveGen.moves_for(st, ypos):
		if mv.get("castle") != null: k += 1
	_ok(k == 0, "sin castle_partner no hay enroque")
	# def custom con el flag sí enroca
	var custom := {"letter": "R", "name": "Torre2", "value": 5,
		"cells": {}, "castle_partner": true}
	st.set_at(Vector2i(0, 6), st.new_piece(custom, 0))
	k = 0
	for mv in MoveGen.moves_for(st, ypos):
		if mv.get("castle") != null: k += 1
	_ok(k > 0, "castle_partner custom permite enrocar")

## La cadena del Tritón se aplica de verdad: el segundo tramo ejecuta
## su propio movimiento tras el primero.
func _test_chain_apply() -> void:
	var st := _empty_state("aquontes", "humenex")
	# ojo: el orden en st.factions es el de PiecesData.all(), no el
	# de los argumentos — buscar por id
	var aqu: Dictionary = {}
	var hum: Dictionary = {}
	for f in st.factions:
		if f.id == "aquontes": aqu = f.pieces
		if f.id == "humenex": hum = f.pieces
	# Tritón en (4,4): 1er tramo (1,-1) lit → (5,3); 2º tramo Aquonte
	# (-2,-2): pivote enemigo en (4,2) → aterriza en (3,1)
	st.set_at(Vector2i(4, 4), st.new_piece(aqu["T"], 0))
	st.set_at(Vector2i(4, 2), st.new_piece(hum["P"], 1))
	var chained: Dictionary = {}
	for mv in MoveGen.moves_for(st, Vector2i(4, 4)):
		if mv.get("second") != null:
			chained = mv
	_ok(not chained.is_empty(), "cadena: variante con 2º tramo generada")
	if not chained.is_empty():
		st.apply(chained)
		_ok(st.at(chained.second.to) != null,
			"cadena: pieza aterriza en el 2º destino")
		_ok(st.at(chained.to) == null or \
			st.at(chained.to).def.letter != "T" \
			or chained.second.to == chained.to,
			"cadena: el 1er tramo no deja la pieza atrás")

## Enroque con torre adyacente: la celda 'k/K' caía sobre la propia
## torre — el intercambio la borraba (bug del despliegue Humenex).
func _test_castle_adjacent() -> void:
	var st := _empty_state()
	var hum: Dictionary = _tm().state.factions[0].pieces
	st.set_at(Vector2i(1, 6), st.new_piece(hum["Y"], 0))
	st.set_at(Vector2i(2, 6), st.new_piece(hum["T"], 0))
	var bad := false
	for mv in MoveGen.moves_for(st, Vector2i(1, 6)):
		if mv.get("castle") != null and st.at(mv.to) != null:
			bad = true
	_ok(not bad, "enroque: ningún destino sobre pieza")
	# el enroque válido (torre lejana) se sigue generando
	var found := false
	for mv in MoveGen.moves_for(st, Vector2i(1, 6)):
		if mv.get("castle") != null: found = true
	_ok(found, "enroque válido se sigue generando")
	# y aplicado no borra piezas (apply real, no _sim que omite castle)
	for mv in MoveGen.moves_for(st, Vector2i(1, 6)):
		if mv.get("castle") == null: continue
		var st2 := BoardState.new()
		st2.factions = st.factions
		st2.restore(st.snapshot())
		st2.apply(mv)
		var n := 0
		for p in st2.grid: if p != null: n += 1
		_ok(n == 2, "enroque aplicado conserva las 2 piezas")

## Round-trip save→JSON→load: first_turn_done con claves int y
## last_move apuntando a la pieza en tablero (al paso persistido).
func _test_save_roundtrip() -> void:
	var tm := _tm()
	var bot := BeliberBot.new(1)
	for i in 4:
		var mv := bot.best_move(tm, tm.current)
		if mv.is_empty(): break
		tm.play(mv)
	# JSON real: las claves int se serializan como "0"/"1"
	var data: Dictionary = JSON.parse_string(
		JSON.stringify(tm.save_game()))
	var back := TurnManager.load_game(data,
		[tm.state.factions[0], tm.state.factions[1]])
	_ok(back != null, "round-trip: reconstruye")
	_ok(back.first_turn_done[0] == tm.first_turn_done[0] \
		and back.first_turn_done[1] == tm.first_turn_done[1],
		"round-trip: doble apertura conservada (claves int)")
	if not tm.state.last_move.is_empty():
		_ok(back.state.last_move.get("piece") == \
			back.state.at(back.state.last_move.to),
			"round-trip: last_move apunta a la pieza en tablero")
	else:
		_ok(true, "round-trip: last_move (vacío)")

## Undo también revierte el incremento Fischer (antes regalaba
## clock_inc segundos por cada jugar+deshacer).
func _test_undo_clock() -> void:
	var tm := _tm()
	tm.clock = [60, 60]
	tm.clock_inc = 5.0
	var bot := BeliberBot.new(1)
	var mv := bot.best_move(tm, tm.current)
	_ok(tm.play(mv), "clock: jugada")
	_ok(tm.undo(), "clock: undo")
	_ok(tm.clock[0] == 60 and tm.clock[1] == 60,
		"undo revierte incremento Fischer")

## Capturas del 2º tramo (cadena): contabilizan bandeja, anti-stall
## y undo igual que las del 1er tramo.
func _test_leg2_caps() -> void:
	var facs := _tm().state.factions
	var pos := [
		{"x": 4, "y": 7, "l": "Y", "o": 0},
		{"x": 4, "y": 3, "l": "P", "o": 0},
		{"x": 6, "y": 4, "l": "P", "o": 1},
		{"x": 0, "y": 4, "l": "Y", "o": 1},
	]
	var t := TurnManager.new(facs[0], 0, facs[1], 0,
		{"pos": pos, "first": 0})
	t.stall_count = 4   # contador en curso: la captura debe resetearlo
	var mv := {"from": Vector2i(4, 3), "to": Vector2i(4, 4),
		"captures": [], "piece_letter": "P",
		"second": {"from": Vector2i(4, 4), "to": Vector2i(5, 4),
			"captures": [Vector2i(6, 4)]}}
	_ok(t.play(mv), "leg2: jugada con captura en 2º tramo")
	_ok(t.captured_by[0].size() == 1, "leg2: captura en bandeja")
	_ok(t.stall_count == 0, "leg2: captura resetea anti-stall")
	_ok(t.undo(), "leg2: undo")
	_ok(t.state.at(Vector2i(6, 4)) != null,
		"leg2: undo restaura la capturada")
	_ok(t.captured_by[0].is_empty(), "leg2: undo vacía bandeja")

## match_legal: en transportes sin árbitro (ENet/relay) el dict remoto
## no se aplica jamás — solo se casa from/to contra las legales.
func _test_match_legal() -> void:
	var tm := _tm()
	# payload falsificado: una jugada legal real (sin 2º tramo) pero
	# con captures inventadas — el dict remoto jamás se aplica
	var real: Variant = null
	for m in tm.all_moves(tm.current):
		if not m.has("second"): real = m; break
	_ok(real != null, "match: hay jugada base para la prueba")
	if real != null:
		var fake := {"from": {"x": real.from.x, "y": real.from.y},
			"to": {"x": real.to.x, "y": real.to.y},
			"captures": [{"x": 4, "y": 4}], "piece_letter": "P"}
		var matched: Variant = TurnManager.match_legal(tm, fake)
		_ok(matched != null and matched.captures == real.captures,
			"match: variante local sin captures falsificadas")
	# jugada legal para el rival pero fuera de turno => null
	var foe: Array = tm.all_moves(1 - tm.current)
	if not foe.is_empty():
		var fm: Dictionary = foe[0]
		_ok(TurnManager.match_legal(tm,
				{"from": fm.from, "to": fm.to}) == null,
			"match: jugada del rival rechazada (turno)")

## Celda "0,0" (la propia casilla): sin sentido en el motor — con
## EMPUJAR generaba un empuje degenerado de la pieza sobre sí misma.
## Y leg2 con celda condicional 'd' (deploy): tras el 1er tramo la
## pieza ya se movió → el 2º tramo no puede abrir doble paso.
func _test_zero_and_leg2_deploy() -> void:
	var mkfac := func() -> Dictionary:
		return {"id": "t", "name": "T", "color": Color.WHITE,
			"rules": {},
			"pieces": {
				"Z": {"letter": "Z", "name": "Zed", "value": 1,
					"cells": {"0,0": "3", "1,0": "o"}, "sym": "lit",
					"leg2": {"0,-1": "d"}},
				"L": {"letter": "L", "name": "Lea", "value": 9,
					"cells": {}, "sym": "lit", "leader": true}},
			"setups": [[]]}
	var tm := TurnManager.new(mkfac.call(), 0, mkfac.call(), 0,
		{"pos": [{"x": 3, "y": 3, "l": "Z", "o": 0},
			{"x": 0, "y": 0, "l": "L", "o": 0},
			{"x": 7, "y": 0, "l": "L", "o": 1}]})
	var pos := Vector2i(3, 3)
	var to_normal := false
	for mv in MoveGen.moves_for(tm.state, pos):
		# '0,0' filtrada: jamás una jugada a la propia casilla ni un
		# empuje de la propia pieza
		_ok(mv.to != pos, "0,0: no auto-jugada")
		if mv.has("push"):
			_ok(mv.push.from != pos, "0,0: no auto-empuje")
		if mv.to == Vector2i(4, 3): to_normal = true
		if mv.has("second"):
			_ok(not mv.second.get("double_step", false),
				"leg2 'd': sin doble paso tras mover")
	_ok(to_normal, "celda normal sigue generando (1,0)")
	# celdas ilegibles / fuera de rango
	_ok(TurnManager.match_legal(tm, {"from": 3, "to": "x"}) == null,
		"match: payload no-dict rechazado")
	_ok(TurnManager.match_legal(tm, {"from": {"x": -5, "y": 0},
		"to": {"x": 0, "y": 0}}) == null,
		"match: origen fuera rechazado")


## Regresiones del audit: pos_counts al cargar, last_move en cadenas
## y al paso sobre casilla ocupada.
func _test_load_regression() -> void:
	# E1: cargar un save NO debe recontar la posición actual — el save
	# ya la incluye (la contó play() al guardar). Antes sumaba +1 y
	# una posición vista 2 veces saltaba a "triple repetición".
	var tm := _tm()
	var bot := BeliberBot.new(1)
	for i in 4:
		var mv := bot.best_move(tm, tm.current)
		if mv.is_empty(): break
		tm.play(mv)
	var key: String = tm._pos_key()
	tm.pos_counts[key] = 2   # posición actual vista dos veces
	var data: Dictionary = JSON.parse_string(
		JSON.stringify(tm.save_game()))
	var back := TurnManager.load_game(data,
		[tm.state.factions[0], tm.state.factions[1]])
	_ok(back != null and not back.over,
		"load: no dispara repetición espuria")
	_ok(int(back.pos_counts.get(key, 0)) == 2,
		"load: pos_counts conserva el conteo exacto")
	# P3: save manipulado con current fuera de rango ? clamp a {0,1}
	data["current"] = 5
	var back2 := TurnManager.load_game(data,
		[tm.state.factions[0], tm.state.factions[1]])
	_ok(back2 != null and back2.current in [0, 1],
		"load: current inválido se clampea")

	# E2: una jugada encadenada debe marcar has_moved y apuntar
	# last_move.piece a la casilla del 2º tramo (antes quedaba null
	# y el al paso borraba piezas inocentes)
	var st := _empty_state("aquontes", "humenex")
	var aqu: Dictionary = {}
	var hum: Dictionary = {}
	for f in st.factions:
		if f.id == "aquontes": aqu = f.pieces
		if f.id == "humenex": hum = f.pieces
	st.set_at(Vector2i(4, 4), st.new_piece(aqu["T"], 0))
	st.set_at(Vector2i(4, 2), st.new_piece(hum["P"], 1))
	var chained: Dictionary = {}
	for mv in MoveGen.moves_for(st, Vector2i(4, 4)):
		if mv.get("second") != null: chained = mv
	if not chained.is_empty():
		st.apply(chained)
		_ok(st.last_move.get("piece") == st.at(chained.second.to),
			"cadena: last_move apunta al destino del 2º tramo")
		_ok(st.at(chained.second.to).has_moved,
			"cadena: has_moved marcado tras el 2º tramo")

	# E3: al paso con la casilla destino ocupada no se genera (antes
	# borraba al ocupante sin registrar la captura)
	var mkfac := func() -> Dictionary:
		return {"id": "t", "name": "T", "color": Color.WHITE,
			"rules": {},
			"pieces": {
				"P": {"letter": "P", "name": "P", "value": 1,
					"cells": {"0,-1": "o", "0,-2": "d"}, "sym": "lit"},
				"E": {"letter": "E", "name": "E", "value": 1,
					"cells": {"1,-1": "E"}, "sym": "lit"},
				"L": {"letter": "L", "name": "L", "value": 9,
					"cells": {}, "sym": "lit", "leader": true}},
			"setups": [[]]}
	var tm2 := TurnManager.new(mkfac.call(), 0, mkfac.call(), 0,
		{"pos": [{"x": 3, "y": 3, "l": "E", "o": 0},
			{"x": 4, "y": 2, "l": "P", "o": 0},
			{"x": 0, "y": 0, "l": "L", "o": 0},
			{"x": 7, "y": 0, "l": "L", "o": 1}]})
	# victim simula el doble paso que acaba de jugar el rival
	tm2.state.set_at(Vector2i(4, 1),
		tm2.state.new_piece(mkfac.call().pieces["P"], 1))
	tm2.state.apply({"from": Vector2i(4, 1), "to": Vector2i(4, 3),
		"captures": [], "piece_letter": "P", "double_step": true})
	var ep_found := false
	for mv in MoveGen.moves_for(tm2.state, Vector2i(3, 3)):
		if mv.to == Vector2i(4, 2):
			ep_found = true
	_ok(not ep_found, "al paso: casilla ocupada no genera captura")

## load_json: si el JSON principal está corrupto se recupera desde
## <path>.bak (última escritura buena) — un corte a mitad de write
## no borra stats/ratings/saves.
func _test_bak_recovery() -> void:
	var p := "user://_test_bak.json"
	StatsStore.atomic_write(p, JSON.stringify({"a": 1}))
	_ok(FileAccess.file_exists(p + ".bak"),
		"atomic_write deja .bak")
	# corrompe el principal: el fallback debe devolver el .bak
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{\"a\": tru")
	f.close()
	var r = StatsStore.load_json(p)
	_ok(r is Dictionary and r.get("a") == 1,
		"load_json recupera desde .bak")
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(p + ".bak"))
