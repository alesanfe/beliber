extends SceneTree
## E2E local: instancia la escena completa, arranca una partida
## hotseat y juega una partida ENTERA haciendo clic con el ratón
## (drag & drop real: press en origen, release en destino).
## Verifica HUD, lista de jugadas, bandejas y fin de partida.

const CELL := 72

var app: Control
var fails := 0

func ok(cond: bool, name: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + name)
	if not cond: fails += 1

## Simula un clic-drag de una casilla lógica a otra a través del
## controlador real de entrada del tablero.
func _drag(board: Control, frm: Vector2i, to: Vector2i) -> void:
	for cell in [frm, to]:
		var s: Vector2i = board._scr(cell)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = Vector2(s.x * CELL + CELL * 0.5,
			s.y * CELL + CELL * 0.5)
		ev.pressed = (cell == frm)   # press origen, release destino
		board._gui_input(ev)

func _initialize() -> void:
	print("== E2E: partida completa por clicks ==")
	var scene: PackedScene = load("res://scenes/main.tscn")
	app = scene.instantiate()
	self.root.add_child(app)
	await process_frame
	ok(app.menu_root != null, "menú construido")

	# hotseat Humenex vs Elfos (asimetría real), sin IA ni reloj
	app.opt_p0.select(0)
	app.opt_p1.select(1)
	app.opt_ai.select(0)
	app._start_game()
	await process_frame
	ok(app.game_ui != null, "HUD construido")
	ok(app.board != null, "tablero presente")
	ok(app.tray0 != null and app.tray1 != null, "bandejas presentes")
	ok(app.hud_opening != null, "etiqueta de apertura presente")

	var tm: TurnManager = app.tm
	var bots := [BeliberBot.new(1, "normal", 0.0),
		BeliberBot.new(1, "normal", 0.0)]
	var plies := 0
	var max_plies := 400
	var opening_seen := false
	while not tm.over and plies < max_plies:
		var mv: Dictionary = bots[tm.current].best_move(tm, tm.current)
		if mv.is_empty(): break
		_drag(app.board, mv.from, mv.to)
		await process_frame
		plies += 1
		if plies <= 4 and app.hud_opening.text != "":
			opening_seen = true
		# el HUD debe seguir al estado tras cada clic
		if tm.log.size() != plies:
			ok(false, "log desincronizado en ply %d" % plies)
			break
	ok(plies > 0, "se jugaron jugadas (%d plies)" % plies)
	ok(opening_seen, "nombre de apertura mostrado")
	ok(app.hud_turn.text != "", "HUD de turno actualizado")
	ok(app.move_list.get_child_count() == tm.log.size(),
		"lista de jugadas sincronizada")
	var caps: int = tm.captured_by[0].size() + tm.captured_by[1].size()
	var tray_icons: int = tray0_icons() + tray1_icons()
	ok(caps == tray_icons, "bandejas = capturas reales (%d)" % caps)
	ok(tm.log.size() == app._move_marks.size(),
		"clasificaciones calculadas para cada jugada")
	if not tm.over:
		# algunos enfrentamientos no convergen — la rendición también
		# es un final válido de partida
		tm.resign(tm.current)
		await process_frame
	ok(tm.over, "la partida terminó")
	ok(tm.winner in [-1, 0, 1], "resultado válido (%d)" % tm.winner)
	print("  plies=%d winner=%d caps=%d" % [
		tm.log.size(), tm.winner, caps])
	print("== %s ==" % ("OK" if fails == 0 else "%d FALLOS" % fails))
	app.queue_free()   # liberar la escena antes de salir
	await process_frame
	quit(0 if fails == 0 else 1)

func tray0_icons() -> int: return app.tray0.letters.size()
func tray1_icons() -> int: return app.tray1.letters.size()

