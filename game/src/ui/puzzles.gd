class_name PuzzleScreen
extends Control

## Puzzles tácticos (estilo lichess): posiciones generadas por juego
## aleatorio donde existe una jugada que captura un líder. El jugador
## debe encontrarla; fallar deshace la jugada.

## Emitida al terminar el Rush con la racha final — el menú la
## escucha para persistir el récord en las stats del perfil.
signal rush_done(score: int)

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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	row.add_child(side)
	side.add_child(_lbl(Lang.t("PUZ_TITLE"), 26))
	status = _lbl("", 15)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	side.add_child(status)
	var b := Button.new()
	b.text = Lang.t("PUZ_NEXT")
	b.pressed.connect(_gen)
	side.add_child(b)
	var b_rush := Widgets.primary(Lang.t("PUZ_RUSH"))
	b_rush.tooltip_text = Lang.t("PUZ_RUSH_TIP")
	b_rush.pressed.connect(_start_rush)
	side.add_child(b_rush)
	_board_holder = center

func _ready() -> void:
	# _gen() await process_frame: en _init el nodo aún no está en el
	# árbol y get_tree() devuelve null — si el primer intento no
	# halla una captura de líder, el await petaba y la pantalla
	# quedaba congelada en "Generando…" sin reintentos
	_gen()

var _board_holder: Control

func _lbl(t: String, size := 0) -> Label:
	return Widgets.lbl(t, size)

## Simula partidas aleatorias hasta encontrar una posición donde el
## jugador al turno puede capturar un líder.
## Cede el frame periódicamente: la búsqueda entera en el mismo tick
## congelaba la UI varios segundos (el "Generando…" ni se pintaba).
func _gen() -> void:
	status.text = Lang.t("PUZ_GEN")
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
		# ceder cada intento: sin esto nunca se llega a pintar
		await get_tree().process_frame
		if not is_inside_tree(): return   # pantalla cerrada a mitad
	status.text = Lang.t("PUZ_GEN_FAIL") % Lang.t("PUZ_NEXT")

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
	status.text = Lang.t("PUZ_STATUS") % [
		tm.current + 1, PiecesData.fac_name(fac), solved]

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
		rush = false
		status.text = Lang.t("PUZ_TIME_UP") % solved
		rush_done.emit(solved)   # persiste el récord vía _open_puzzles
		if board != null: board.net_me = 9
		return
	if tm != null and status != null and rush:
		var l := status.text.find("\n")
		var base := status.text if l < 0 else status.text.substr(0, l)
		status.text = base + "\n" + Lang.t("PUZ_TIMER") % rush_secs

func _on_move(_mv: Dictionary) -> void:
	if tm.over or tm.state.leaders_alive(_target_side) < _leaders_before:
		solved += 1
		if rush:
			_gen()   # siguiente puzzle al instante
			return
		status.text = Lang.t("PUZ_OK") % [solved, Lang.t("PUZ_NEXT")]
		board.net_me = 9   # bloquear más jugadas
	else:
		tm.undo()
		if rush:
			rush_secs = maxf(1.0, rush_secs - 5.0)   # penalización
		status.text = Lang.t("PUZ_WRONG") % solved
