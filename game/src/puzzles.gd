class_name PuzzleScreen
extends Control

## Puzzles tácticos (estilo lichess): posiciones generadas por juego
## aleatorio donde existe una jugada que captura un líder. El jugador
## debe encontrarla; fallar deshace la jugada.

var factions: Array
var tm: TurnManager
var board: BoardView
var status: Label
var solved := 0
var rush := false            # modo contrarreloj (Puzzle Rush)
var rush_secs := 60.0
var rush_on := false         # timer activo
var _target_side := -1       # bando cuyo líder hay que capturar
var _leaders_before := 0

func _init(p_factions: Array) -> void:
	factions = p_factions
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	row.add_child(side)
	side.add_child(_lbl("Puzzle táctico", 26))
	status = _lbl("", 15)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	side.add_child(status)
	var b := Button.new()
	b.text = "Otro puzzle"
	b.pressed.connect(_gen)
	side.add_child(b)
	var b_rush := Widgets.primary("Rush (60 s)")
	b_rush.tooltip_text = "Racha de puzzles: cada acierto suma,\n" + \
		"cada fallo resta 5 s. Modo estilo lichess Puzzle Rush."
	b_rush.pressed.connect(_start_rush)
	side.add_child(b_rush)
	_board_holder = center
	_gen()

var _board_holder: Control

func _lbl(t: String, size := 0) -> Label:
	return Widgets.lbl(t, size)

## Simula partidas aleatorias hasta encontrar una posición donde el
## jugador al turno puede capturar un líder.
func _gen() -> void:
	status.text = "Generando…"
	for _attempt in 200:
		var f0: Dictionary = factions[randi() % factions.size()]
		var f1: Dictionary = factions[randi() % factions.size()]
		var t := TurnManager.new(f0, 0, f1, 0, {})
		for _ply in 60:
			if t.over: break
			var killer: Variant = _find_leader_capture(t)
			if killer != null:
				_setup(t)
				return
			# jugada aleatoria para avanzar la simulación
			var all := _all_moves(t)
			if all.is_empty(): break
			t.play(all[randi() % all.size()])
	status.text = "Sin puzzle generado — pulsa «Otro puzzle»."

func _all_moves(t: TurnManager) -> Array:
	var out := []
	for y in 8:
		for x in 8:
			var pos := Vector2i(x, y)
			var p: Variant = t.state.at(pos)
			if p != null and p.owner == t.current:
				out.append_array(t.legal_moves(pos))
	return out

## Devuelve una jugada que captura un líder, o null.
func _find_leader_capture(t: TurnManager) -> Variant:
	for mv in _all_moves(t):
		for c in mv.get("captures", []):
			var p: Variant = t.state.at(c)
			if p != null and p.def.get("leader", false):
				return mv
	return null

func _setup(t: TurnManager) -> void:
	tm = t
	_target_side = 1 - tm.current
	_leaders_before = tm.state.leaders_alive(_target_side)
	if board != null: board.queue_free()
	board = BoardView.new(tm)
	board.net_me = tm.current       # solo mueves el bando al turno
	_board_holder.add_child(board)
	tm.move_made.connect(_on_move)
	var fac: Dictionary = tm.state.factions[tm.current]
	status.text = "J%d (%s): captura un líder rival.\nResueltos: %d" % [
		tm.current + 1, fac.name, solved]

func _start_rush() -> void:
	rush = true
	rush_on = true
	rush_secs = 60.0
	solved = 0
	_gen()

func _process(dt: float) -> void:
	if not rush_on: return
	rush_secs -= dt
	if rush_secs <= 0.0:
		rush_on = false
		status.text = "¡Tiempo! Racha final: %d puzzles." % solved
		if board != null: board.net_me = 9
		return
	if tm != null and status != null and rush:
		var l := status.text.find("\n")
		var base := status.text if l < 0 else status.text.substr(0, l)
		status.text = "%s\n⏱ %.0f s" % [base, rush_secs]

func _on_move(_mv: Dictionary) -> void:
	if tm.over or tm.state.leaders_alive(_target_side) < _leaders_before:
		solved += 1
		if rush:
			_gen()   # siguiente puzzle al instante
			return
		status.text = "¡Correcto! Resueltos: %d\nPulsa «Otro puzzle»." % solved
		board.net_me = 9   # bloquear más jugadas
	else:
		tm.undo()
		if rush:
			rush_secs = maxf(1.0, rush_secs - 5.0)   # penalización
		status.text = "Esa no mata al líder. Prueba otra.\nResueltos: %d" \
			% solved
