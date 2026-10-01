extends SceneTree

## Playthrough: partidas reales bot-vs-bot para todas las facciones.
## Verifica que el juego se puede JUGAR de principio a fin: cada
## jugada del bot es legal, el estado se mantiene coherente, el
## deshacer/guardar/replay funcionan en medio de una partida y las
## partidas terminan (victoria, tablas o límite anti-stall).
##
##   godot --headless -s tests/playthrough.gd

var failures := 0

func _init() -> void:
	print("== Beliber: playthrough bot-vs-bot ==")
	var all := PiecesData.all()
	# cada facción contra sí misma (espejo) + 4 cruces variados
	var matchups := []
	for f in all: matchups.append([f.id, f.id])
	matchups.append_array([
		["humenex", "elfos"], ["mortifers", "enanos"],
		["bestiarios", "chlontos"], ["aquontes", "kronturs"]])
	var finished := 0
	for m in matchups:
		var over := _play_game(m[0], m[1])
		if over: finished += 1
	_ok(finished >= 8, "la mayoría de partidas terminan (%d/12)" % finished)
	_test_midgame_save_undo()
	_test_bot_always_legal()
	print("== %s ==" % ("OK" if failures == 0 else "%d FALLOS" % failures))
	quit(0 if failures == 0 else 1)

func _ok(cond: bool, name: String) -> void:
	if cond:
		print("  PASS ", name)
	else:
		failures += 1
		printerr("  FAIL ", name)

func _faction(id: String) -> Dictionary:
	for f in PiecesData.all():
		if f.id == id: return f
	return {}

## Todas las jugadas legales del jugador actual.
func _all_legal(tm: TurnManager) -> Array:
	var out := []
	for y in 8:
		for x in 8:
			var cell := Vector2i(x, y)
			var p: Variant = tm.state.at(cell)
			if p != null and p.owner == tm.current:
				out.append_array(tm.legal_moves(cell))
	return out

## Comprueba que una jugada está en la lista legal del estado actual.
func _is_legal(tm: TurnManager, mv: Dictionary) -> bool:
	for m in _all_legal(tm):
		if m.from == mv.from and m.to == mv.to:
			return true
	return false

## Una partida completa entre dos bots nivel 1 (rápido).
## Devuelve true si terminó antes del límite de plies.
func _play_game(f0id: String, f1id: String) -> bool:
	var tm := TurnManager.new(_faction(f0id), 0, _faction(f1id), 0,
		{"stall_limit": 60, "midline": true})
	var bot := BeliberBot.new(1)
	var plies := 0
	var max_plies := 200
	var prev_mat := tm.material_value(0) + tm.material_value(1)
	while not tm.over and plies < max_plies:
		var mv := bot.best_move(tm, tm.current)
		if mv.is_empty():
			break  # sin jugadas → ahogado (debería contar como fin)
		if not _is_legal(tm, mv):
			failures += 1
			printerr("  FAIL jugada ilegal en %s vs %s: %s" % [
				f0id, f1id, mv])
			break
		if not tm.play(mv):
			failures += 1
			printerr("  FAIL play() rechazó jugada legal %s vs %s" % [
				f0id, f1id])
			break
		plies += 1
		# invariantes en cada ply: material nunca crece
		var mat := tm.material_value(0) + tm.material_value(1)
		if mat > prev_mat:
			failures += 1
			printerr("  FAIL material creció en %s vs %s (ply %d)" % [
				f0id, f1id, plies])
			break
		prev_mat = mat
	# el historial de deshacer coincide con los plies jugados
	# (tm.log añade además mensajes de fin — no sirve para contar)
	_ok(tm.history.size() == plies,
		"%s vs %s: hist=%d plies=%d" % [f0id, f1id,
			tm.history.size(), plies])
	_ok(tm.replay_len() == plies + 1,
		"%s vs %s: replay tiene %d snapshots" % [
			f0id, f1id, tm.replay_len()])
	if tm.over:
		var w := tm.winner
		# ganador válido: -1 tablas, 0 o 1
		_ok(w >= -1 and w <= 1, "%s vs %s: resultado válido %d" % [
			f0id, f1id, w])
	return tm.over

## Guardar + cargar a mitad de partida → la posición es idéntica,
## y deshacer hasta el inicio restaura el despliegue original.
func _test_midgame_save_undo() -> void:
	var tm := TurnManager.new(_faction("humenex"), 0,
		_faction("elfos"), 0, {"stall_limit": 80})
	var bot := BeliberBot.new(1)
	var turn0 := tm.current   # Elfos (y otras facciones) abre primero
	var initial := BoardState.to_bel(tm.state, 0, 0, 1, 0, turn0)
	for i in 20:
		if tm.over: break
		var mv := bot.best_move(tm, tm.current)
		if mv.is_empty(): break
		tm.play(mv)
	var mid := tm.save_game()
	var restored := TurnManager.load_game(mid,
		[_faction("humenex"), _faction("elfos")])
	_ok(restored != null, "midgame: carga sin error")
	var bel_now := BoardState.to_bel(tm.state, 0, 0, 1, 0, tm.current)
	var bel_loaded := BoardState.to_bel(restored.state, 0, 0, 1, 0,
		restored.current)
	_ok(bel_now == bel_loaded, "midgame: posición idéntica tras cargar")
	# deshacer hasta el ply 0 recupera el despliegue exacto (solo si la
	# partida no terminó: tras el fin el undo está bloqueado a propósito)
	if not tm.over:
		while tm.undo(): pass
		var bel_back := BoardState.to_bel(tm.state, 0, 0, 1, 0, tm.current)
		_ok(bel_back == initial, "midgame: undo total = despliegue inicial")
	else:
		_ok(not tm.undo(), "midgame: undo bloqueado tras el fin")

## El bot nunca propone una jugada ilegal, en varias posiciones.
func _test_bot_always_legal() -> void:
	var tm := _tm_random_mid()
	var bot := BeliberBot.new(1)
	var ok := true
	for i in 30:
		if tm.over: break
		var mv := bot.best_move(tm, tm.current)
		if mv.is_empty(): break
		if not _is_legal(tm, mv):
			ok = false; break
		tm.play(mv)
	_ok(ok, "bot: 30 jugadas consecutivas todas legales")

## Estado de media partida cualquiera.
func _tm_random_mid() -> TurnManager:
	var tm := TurnManager.new(_faction("enanos"), 0,
		_faction("mortifers"), 0, {})
	var bot := BeliberBot.new(0)   # nivel 0: pseudo-aleatorio
	for i in 16:
		if tm.over: break
		var mv := bot.best_move(tm, tm.current)
		if mv.is_empty(): break
		tm.play(mv)
	return tm
