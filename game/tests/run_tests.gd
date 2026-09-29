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
