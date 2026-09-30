extends Control

## Controlador raíz: menú de selección de facción → partida hotseat.

var factions: Array = []
var tm: TurnManager
var board: BoardView
var hud_turn: Label
var hud_info: Label
var hud_log: Label
var select_ui: Control
var menu_root: Control
var game_ui: Control
var opt_p0: OptionButton
var opt_p1: OptionButton
var opt_eq0: OptionButton
var opt_eq1: OptionButton
var val_lbl0: Label
var val_lbl1: Label
var chk_midline: CheckBox
var chk_stall: CheckBox
var stall_spin: SpinBox
var opt_ai: OptionButton
var opt_style: OptionButton
var opt_clock: OptionButton
var chk_handicap: CheckBox
var chk_flip: CheckBox
var _flip_board := false   # estado copiado al arrancar (menu queda freed)
var _last_sel := [0, 1]    # facciones elegidas (para rematch)
var _saved_opts := {}      # config congelada al arrancar (menú freed)
var _over_handled := false # fin de partida ya registrado en stats
var btn_cov: CheckButton
var hud_clock: Label
var hud_eval: Label
var hud_opening: Label    # nombre de apertura (estilo lichess)
var hud_rival: Label
var hud_rival_icon: FactionIcon
var eval_bar: EvalBar
var tray0: CapturedTray          # capturas de J1 (bandeja lichess)
var tray1: CapturedTray          # capturas de J2
var move_list: VBoxContainer
var _log_n := 0
var _move_marks: Array = []      # clasificación ! ? ?? por jugada
var tutorial := false            # partida guiada con objetivos
var tut_steps: Array = []        # {text, done, check(mv)->bool}
var tut_box: VBoxContainer
var side_panel: VBoxContainer
var _opt_toggles := {}           # CheckButtons de Opciones (blind/coords/conf/mute)
var _compact := false            # layout apilado (ventana estrecha)
var _low_warned := [false, false]  # aviso <10 s ya emitido por bando
var coop := false                # 2 humanos alternan el bando J1
var coop_turn := 0               # 0 = humano A, 1 = humano B
var chk_coop: CheckBox
var bot: BeliberBot
var ai_player := -1            # jugador controlado por la IA (-1 = ninguno)
var sfx: BeliberSfx
var muted := false:
	set(v):
		muted = v
		if sfx != null: sfx.muted = v
var ui_theme_mode := "dark"      # dark / light / contrast
const CFG_PATH := "user://beliber.cfg"
const SAVE_PATH := "user://beliber_save.json"
const EXPORT_PATH := "user://beliber_match.txt"

var stats := {}                # persistido vía StatsStore
var online := false            # partida por red
var my_net := -1               # lado local en online (-1 = hotseat)
var ai_both := false           # IA vs IA: el bot controla a los dos
# ---- modo Run (roguelike): racha con dificultad y bendiciones ----
var run_active := false
var run_level := 1
var run_blunder := 0.0         # extra de fallo del rival
var run_clock_bonus := 0.0     # segundos extra para ti
var run_first := false         # sales primero
var net_peer: ENetMultiplayerPeer
var net_ip: LineEdit
var net_port: LineEdit
# ---- relay por WebSocket (salas con código + reconexión) ----
var ws: WebSocketPeer
var ws_url: LineEdit
var ws_code: LineEdit
var ws_name: LineEdit
var ws_room := ""
var ws_token := ""
var ws_side := -1
var ws_open := false
var _ws_last_addr := "ws://127.0.0.1:7778"
var _ws_last_nick := ""
var _ladder_label: Label = null   # etiqueta del tab Ladder (pantalla online)
var ws_auth := false               # servidor autoritativo (hello)

var editor_ui: Control
var _ws_pending := ""
var _ws_cfg := {}          # última cfg aplicada (para resync sin cfg)

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		ui_theme_mode = str(cf.get_value("ui", "skin", "dark"))
	theme = BeliberTheme.make(ui_theme_mode)
	RenderingServer.set_default_clear_color(BeliberTheme._v.bg)
	# sonido de interfaz: los componentes llaman Juice.ui_sfx
	sfx = BeliberSfx.new()
	add_child(sfx)
	sfx.muted = muted
	Juice.ui_sfx = sfx.beep
	factions = PiecesData.all()
	PieceEditor.apply_overrides(factions)
	ArmyBuilder.apply(factions)
	_load_stats()
	_build_menu()

## ===== Stats/progresión (delegada a StatsStore) =====

func _load_stats() -> void:
	stats = StatsStore.load_stats()

func _save_stats() -> void:
	StatsStore.save(stats)

func _grant(id: String) -> void:
	StatsStore.grant(self, id)

func _faction_level(fid: String) -> int:
	return StatsStore.faction_level(stats, fid)

func _record_result() -> void:
	StatsStore.record_result(self)

## Menú principal (delegado a MenuScreen).
func _build_menu() -> void:
	MenuScreen.build(self)

## Pantalla "Jugar online" (delegada a OnlineScreen).
func _open_online() -> void:
	OnlineScreen.build(self)

## ===== Red (ENet) =====
## Host = J1 (jugador 0), cliente = J2 (jugador 1). Solo se sincronizan
## jugadas; el resto del estado es determinista en ambos lados.

func _host_game() -> void:
	var port := int(net_port.text) if net_port.text != "" else 7777
	net_peer = ENetMultiplayerPeer.new()
	if net_peer.create_server(port, 1) != OK:
		hud_alert("No se pudo abrir el puerto %d" % port)
		return
	multiplayer.multiplayer_peer = net_peer
	online = true
	my_net = 0
	hud_alert("Esperando rival en :%d …" % port)
	multiplayer.peer_connected.connect(func(_id: int):
		# cliente conectado → enviar configuración y arrancar
		_rpc_config.rpc(_game_cfg())
		_start_game())
	multiplayer.peer_disconnected.connect(func(_id: int):
		if tm != null and not tm.over:
			tm.over = true; tm.winner = my_net
			tm.game_over.emit(my_net))

func _join_game() -> void:
	var ip := net_ip.text.strip_edges()
	if ip == "": ip = "127.0.0.1"
	var port := int(net_port.text) if net_port.text != "" else 7777
	net_peer = ENetMultiplayerPeer.new()
	if net_peer.create_client(ip, port) != OK:
		hud_alert("No se pudo conectar a %s:%d" % [ip, port])
		return
	multiplayer.multiplayer_peer = net_peer
	online = true
	my_net = 1
	hud_alert("Conectando a %s:%d …" % [ip, port])
	multiplayer.server_disconnected.connect(func():
		if tm != null and not tm.over:
			tm.over = true; tm.winner = my_net
			tm.game_over.emit(my_net))

## Configuración que el host envía al cliente.
func _game_cfg() -> Dictionary:
	var cfg := {"f0": opt_p0.selected, "eq0": opt_eq0.selected,
		"f1": opt_p1.selected, "eq1": opt_eq1.selected,
		"mid": chk_midline.button_pressed,
		"stall": int(stall_spin.value)
			if chk_stall.button_pressed else 0,
		"clock": opt_clock.selected}
	# ejércitos personalizados: viajan los ROWS, no solo el índice —
	# el rival tendría su propio archivo local (o ninguno)
	for si in [0, 1]:
		var eq: int = cfg["eq%d" % si]
		if eq >= 2:
			var fac: Dictionary = factions[int(cfg["f%d" % si])]
			if fac.setups.size() > eq:
				cfg["rows%d" % si] = fac.setups[eq]
	return cfg

## El cliente arranca con la config recibida del host.
@rpc("authority", "reliable")
func _rpc_config(cfg: Dictionary) -> void:
	# misma aplicación de cfg que el relay WS: sin las filas custom
	# cada lado usa su archivo local y los tableros divergen
	NetClient.apply_cfg(self, cfg)
	_start_game()

## Movimiento remoto recibido (determinista en ambos lados).
@rpc("any_peer", "reliable")
func _rpc_move(mv: Dictionary) -> void:
	if mv.get("resign", false):
		tm.resign(1 - my_net)   # quien envió es el rival
		return
	if mv.get("draw", false):
		tm.agree_draw()         # tablas declaradas por el rival
		return
	# Vector2i se serializa como tal; nada más que aplicar
	tm.play(mv)

## Chat por ENet (el relay WS usa {"op":"chat"}).
@rpc("any_peer", "reliable")
func _rpc_chat(t: String) -> void:
	_chat_log("[rival] " + t.left(200))

## Registro de chat con límite: sin cap el Label crecía sin tope
## y cada append re-renderizaba todo el historial.
func _chat_log(t: String) -> void:
	if hud_log == null: return
	hud_log.text += "\n" + t
	var lines := hud_log.text.split("\n")
	if lines.size() > 50:
		hud_log.text = "\n".join(lines.slice(-50))

func hud_alert(t: String) -> void:
	# toast animado (fade + slide, se autodestruye)
	Juice.toast(self, t)



## ===== Relay WebSocket (delegado a NetClient) =====

func _ws_connect(create: bool) -> void:
	NetClient.open(self, create)

func _ws_send(msg: Dictionary) -> void:
	NetClient.send(self, msg)

func _ws_poll() -> void:
	NetClient.poll(self)


## Conecta las señales del TurnManager con sonido/HUD/juice.
## Separada porque _ws_resync puede sustituir el tm en caliente.
func _wire_tm() -> void:
	if not tm.move_made.is_connected(sfx.play_move):
		tm.move_made.connect(sfx.play_move)
	if not tm.game_over.is_connected(_on_game_over):
		tm.game_over.connect(_on_game_over)
	if not tm.move_made.is_connected(_tm_move_ui):
		tm.move_made.connect(_tm_move_ui)
	if not tm.turn_started.is_connected(_tm_turn_ui):
		tm.turn_started.connect(_tm_turn_ui)

## Jugada → HUD + coop + tutorial (separada para poder reconectarla).
func _tm_move_ui(mv: Dictionary) -> void:
	_update_hud()
	var moved: Variant = tm.state.at(mv.to)
	# co-op: al terminar el turno de J1 toca el otro humano
	if coop and moved != null and moved.owner == 0 \
			and tm.current != 0:
		coop_turn = 1 - coop_turn
	# el tutorial solo cuenta jugadas del humano (J1)
	if tutorial and moved != null and moved.owner == 0:
		_tut_check(mv)

## Cambio de turno → HUD + auto-giro local + turno de la IA.
func _tm_turn_ui(p: int) -> void:
	# auto-giro SOLO en partida local sin IA (en online cada
	# cliente ve siempre su propio lado)
	if ai_player < 0 and not online and _flip_board:
		board.flipped = (p == 1)
		board.queue_redraw()
	_update_hud()
	_maybe_bot()

func _faction_picker() -> OptionButton:
	var o := OptionButton.new()
	for f in factions:
		o.add_item(f.name)
	return o

func _refresh_values() -> void:
	if val_lbl0 == null: return
	var f0: Dictionary = factions[opt_p0.selected]
	var f1: Dictionary = factions[opt_p1.selected]
	val_lbl0.text = "Valor: %d\n%s" % [
		PiecesData.army_value(f0, opt_eq0.selected),
		PiecesData.STYLES.get(f0.id, "")]
	val_lbl1.text = "Valor: %d\n%s" % [
		PiecesData.army_value(f1, opt_eq1.selected),
		PiecesData.STYLES.get(f1.id, "")]
	val_lbl0.add_theme_color_override("font_color", f0.color)
	val_lbl1.add_theme_color_override("font_color", f1.color)

const CLOCK_CHOICES := TurnManager.CLOCK_CHOICES

## Opciones del TurnManager leídas del menú (midline/stall/reloj).
## Las tres rutas de arranque (normal, draft, editor de posición)
## compartían este dict casi literal — una sola fuente.
func _tm_opts() -> Dictionary:
	return {
		"midline": chk_midline.button_pressed,
		"stall_limit": int(stall_spin.value)
			if chk_stall.button_pressed else 0,
		"clock_secs": CLOCK_CHOICES[opt_clock.selected][0],
		"clock_inc": CLOCK_CHOICES[opt_clock.selected][1]}

func _start_game() -> void:
	# solo persiste si el arranque vino del botón Tutorial
	if not tutorial: tut_steps = []
	tut_box = null
	_low_warned = [false, false]
	_over_handled = false
	ai_both = opt_ai.selected == 4 and not online
	_flip_board = chk_flip.button_pressed   # el menú se libera abajo
	_last_sel = [opt_p0.selected, opt_p1.selected]   # para _rematch
	ai_player = -1 if online or ai_both else \
		(opt_ai.selected - 1 if opt_ai.selected > 0 else -1)
	coop = chk_coop.button_pressed and ai_player >= 0
	coop_turn = 0
	# la IA controla a J2 (arriba)
	if ai_player == 0: ai_player = 1
	# los controles del menú mueren al liberarse el menú — congelar la
	# configuración para que _run_next/_rematch no lean objetos freed
	_saved_opts = {"eq0": opt_eq0.selected, "eq1": opt_eq1.selected,
		"mid": chk_midline.button_pressed,
		"stall": int(stall_spin.value) if chk_stall.button_pressed else 0,
		"clock": opt_clock.selected,
		"style": opt_style.selected,
		"ai_lvl": opt_ai.selected,
		"handicap": chk_handicap.button_pressed,
		"coop": chk_coop.button_pressed}
	tm = TurnManager.new(factions[opt_p0.selected], opt_eq0.selected,
		factions[opt_p1.selected], opt_eq1.selected, _tm_opts())
	# handicap temporal de la IA — solo cuando el rival es IA
	# (en hotseat J2 es humano y no debería castigarse)
	if _saved_opts.handicap and ai_player >= 0 \
			and not tm.clock.is_empty():
		tm.clock[1] = tm.clock[1] / 2.0
	# modo run: bendiciones activas
	if run_active:
		if run_clock_bonus > 0 and not tm.clock.is_empty():
			tm.clock[0] += run_clock_bonus
		if run_first:
			tm.current = 0
			tm.first_turn_done = {0: false, 1: false}
			tm._begin_turn()
	var styles := ["auto", "normal", "aggro", "defense"]
	var blunders := [0.25, 0.10, 0.0]
	bot = null
	if ai_player >= 0:
		var stl: String = styles[opt_style.selected]
		if stl == "auto":
			# Clockwork (Root): la IA adopta el arquetipo de su facción
			stl = PiecesData.FACTION_STYLE.get(
				tm.state.factions[ai_player].id, "normal")
		bot = BeliberBot.new(opt_ai.selected, stl,
			blunders[opt_ai.selected - 1] + run_blunder)
	elif ai_both:
		# IA vs IA: Test Area del constructor — misma personalidad/lvl 2
		bot = BeliberBot.new(2, styles[opt_style.selected], 0.0)
	menu_root.queue_free()
	_build_game()

## Desafío diario (Prismata/CEO): combinación determinista por fecha —
## hoy todos los jugadores reciben el mismo enfrentamiento.
func _daily_challenge() -> void:
	var d := Time.get_date_dict_from_system()
	var seed_val: int = int(d.year) * 10000 + int(d.month) * 100 \
		+ int(d.day)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var f0 := rng.randi_range(0, factions.size() - 1)
	var f1 := rng.randi_range(0, factions.size() - 1)
	if f1 == f0: f1 = (f1 + 1) % factions.size()
	opt_p0.select(f0); opt_p1.select(f1)
	opt_eq0.select(rng.randi_range(0, 1))
	opt_eq1.select(rng.randi_range(0, 1))
	chk_midline.button_pressed = rng.randf() < 0.3
	opt_clock.select(rng.randi_range(1, 4))   # siempre con reloj
	opt_ai.select(2 + int(rng.randf() < 0.4)) # IA nivel 2-3
	stats["daily"] = seed_val
	_save_stats()
	hud_alert("Desafío del día: %s vs %s" % [
		factions[f0].name, factions[f1].name])
	_start_game()

## Modo Run (Shotgun King): cadena de enfrentamientos contra la IA.
## Cada victoria sube el nivel del rival; entre combates eliges una
## bendición. Al perder termina la racha.
func _start_run() -> void:
	run_active = true
	run_level = 1
	run_blunder = 0.0
	run_clock_bonus = 0.0
	run_first = false
	opt_ai.select(1)
	opt_p1.select(randi() % factions.size())
	opt_clock.select(3)   # 5+0 blitz
	hud_alert("Run — combate 1. ¡Que empiece la racha!")
	_start_game()

## Bendición tras ganar un combate de la run.
func _run_boon() -> void:
	var opts := [
		{"t": "Rival distraído (+15% fallos)",
			"f": func(): run_blunder += 0.15},
		{"t": "+60 s a tu reloj",
			"f": func(): run_clock_bonus += 60.0},
		{"t": "Iniciativa (sales primero)",
			"f": func(): run_first = true},
	]
	var box := VBoxContainer.new()
	box.add_child(Widgets.lbl(
		"Victoria — combate %d. Elige bendición:" % run_level))
	for o in opts:
		var b := Button.new()
		b.text = o.t
		b.pressed.connect(func():
			o.f.call()
			for c in box.get_children(): c.queue_free()
			box.queue_free()
			_run_next())
		box.add_child(b)
	side_panel.add_child(box)

func _run_next() -> void:
	run_level += 1
	# los controles del menú se liberaron al empezar la partida —
	# _restart reconstruye el menú y desmonta la UI de juego.
	# _restart limpia run_active (salir al menú corta el run), pero
	# esto es el paso de nivel: preservar la cadena.
	_restart()
	run_active = true
	var f1 := randi() % factions.size()
	if f1 == opt_p0.selected: f1 = (f1 + 1) % factions.size()
	opt_p1.select(f1)
	opt_ai.select(mini(run_level, 3))
	_start_game()

## Tutorial guiado (walkthrough estilo Root): partida real contra una
## IA débil mientras una lista de objetivos se marca en el panel.
## Los objetivos se adaptan a la mecánica distintiva de tu facción.
func _start_tutorial() -> void:
	tutorial = true
	opt_ai.select(1)               # IA nivel 1
	opt_style.select(0)            # Auto: la IA imita a su facción
	# rival distinto al jugador para ver asimetría real
	if opt_p1.selected == opt_p0.selected:
		opt_p1.select((opt_p0.selected + 1) % factions.size())
	var f0: Dictionary = factions[opt_p0.selected]
	# objetivos base (todo jugador)
	tut_steps = [
		{"t": "Mueve tu primera pieza",
			"chk": func(_mv): return true},
		{"t": "Captura una pieza enemiga",
			"chk": func(mv): return mv.get("captures", []).size() > 0},
	]
	# objetivo distintivo por facción (su regla de la hoja)
	match f0.id:
		"humenex":
			tut_steps.append({"t": "Enroca o mueve dos veces en la apertura",
				"chk": func(mv): return mv.has("castle") or \
					tm.current == 0})
		"elfos":
			tut_steps.append({"t": "Atraviesa a un enemigo (inmovilízalo)",
				"chk": func(mv): return mv.get("immobilize", []).size() > 0})
		"mortifers":
			tut_steps.append({"t": "Captura con el Consorte (copia su patrón)",
				"chk": func(mv): return mv.get("captures", []).size() > 0 \
					and mv.get("piece_letter") == "X"})
		"bestiarios":
			tut_steps.append({"t": "Presiona: salta con un saltador (J/j)",
				"chk": func(mv): return mv.get("fx", 0) & FX.JUMP != 0})
		"enanos", "kronturs":
			tut_steps.append({"t": "Empuja a un enemigo",
				"chk": func(mv): return mv.has("push")})
		"chlontos":
			tut_steps.append({"t": "Ataca a distancia: captura a 3+ casillas",
				"chk": func(mv): return mv.get("captures", []).size() > 0 \
					and (mv.to - mv.from).length() >= 3.0})
		"aquontes":
			tut_steps.append({"t": "Salto de Aquonte o cadena del Tritón",
				"chk": func(mv): return mv.has("second") or \
					mv.get("fx", 0) & FX.JUMP != 0})
	tut_steps.append({"t": "Elimina al líder enemigo (o invade su línea)",
		"chk": func(_mv): return tm.over and tm.winner == 0})
	hud_alert("Tutorial: completa los objetivos del panel")
	_start_game()

## Marca objetivos del tutorial tras cada jugada del jugador.
func _tut_check(mv: Dictionary) -> void:
	if not tutorial or tut_box == null: return
	for i in tut_steps.size():
		var s: Dictionary = tut_steps[i]
		if not s.done and s.chk.call(mv):
			s.done = true
			var l: Label = tut_box.get_child(i + 1)
			l.text = "✔ " + s.t
			l.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6))
	if tut_steps.all(func(s): return s.done):
		hud_alert("¡Tutorial completado!")

## Draft estilo CEO: picks alternos y la partida arranca con la
## posición resultante (sin tocar los despliegues oficiales).
func _open_draft() -> void:
	var d := DraftScreen.new(factions, opt_p0.selected,
		opt_p1.selected)
	editor_ui = d
	menu_root.visible = false
	add_child(d)
	d.done.connect(func(pos: Array):
		var o := _tm_opts()
		o["pos"] = pos
		tm = TurnManager.new(factions[opt_p0.selected], 0,
			factions[opt_p1.selected], 0, o)
		# un draft es siempre local — cortar cualquier estado online
		online = false; net_peer = null; ws = null; ws_auth = false
		my_net = -1
		coop = false
		_over_handled = false
		_flip_board = chk_flip.button_pressed
		_last_sel = [opt_p0.selected, opt_p1.selected]
		# "IA vs IA" (opción 4) también funciona en draft — y sin el
		# clamp, blunders[3] estaba fuera de rango
		ai_both = opt_ai.selected == 4
		ai_player = -1 if ai_both else \
			(opt_ai.selected - 1 if opt_ai.selected > 0 else -1)
		if ai_player == 0: ai_player = 1
		bot = null
		var stl2: String = ["auto", "normal", "aggro", "defense"][
			opt_style.selected]
		if ai_player >= 0:
			var stl := stl2
			if stl == "auto":
				stl = PiecesData.FACTION_STYLE.get(
					tm.state.factions[ai_player].id, "normal")
			bot = BeliberBot.new(mini(opt_ai.selected, 3), stl,
				[0.25, 0.10, 0.0][mini(opt_ai.selected - 1, 2)])
		elif ai_both:
			bot = BeliberBot.new(2, stl2, 0.0)
		d.queue_free()
		editor_ui = null   # evita un doble queue_free en _close_editor
		menu_root.queue_free()
		_build_game())
	d.cancel.connect(func():
		d.queue_free()
		editor_ui = null
		menu_root.visible = true)

func _open_editor() -> void:
	menu_root.queue_free()
	editor_ui = PieceEditor.new(factions)
	add_child(editor_ui)
	# botón volver dedicado para no depender del nombre del nodo raíz
	var back := Button.new()
	back.text = "← Volver"
	back.position = Vector2(8, 8)
	back.z_index = 10
	back.pressed.connect(func():
		editor_ui.queue_free()
		editor_ui = null
		factions = PiecesData.all()
		PieceEditor.apply_overrides(factions)
		ArmyBuilder.apply(factions)
		_build_menu())
	add_child(back)

## Panel de perfil (delegado a ProfileScreen).
func _open_profile() -> void:
	ProfileScreen.build(self)

func _open_guide() -> void:
	menu_root.queue_free()
	editor_ui = GuideScreen.new(factions)
	add_child(editor_ui)
	_add_back()

func _open_puzzles() -> void:
	menu_root.queue_free()
	editor_ui = PuzzleScreen.new(factions)
	add_child(editor_ui)
	_add_back()

## Cierra la pantalla auxiliar (editor/guía/puzzles/perfil) → menú.
func _close_editor() -> void:
	if is_instance_valid(editor_ui):
		editor_ui.queue_free()
	editor_ui = null
	factions = PiecesData.all()
	PieceEditor.apply_overrides(factions)
	ArmyBuilder.apply(factions)
	# el editor de posición solo oculta el menú; el resto lo destruye.
	# is_instance_valid: menu_root puede ser un objeto ya freed
	if is_instance_valid(menu_root) and menu_root.is_inside_tree():
		menu_root.visible = true
	else:
		_build_menu()

## Botón volver compartido por guía, editor, constructor y puzzles.
func _add_back() -> void:
	var back := Widgets.secondary("← Volver", 36)
	back.position = Vector2(8, 8)
	back.z_index = 10
	back.pressed.connect(_close_editor)
	add_child(back)

func _open_builder() -> void:
	menu_root.queue_free()
	editor_ui = ArmyBuilder.new(factions)
	add_child(editor_ui)
	var back := Button.new()
	back.text = "← Volver"
	back.position = Vector2(8, 8)
	back.z_index = 10
	back.pressed.connect(_close_editor)
	add_child(back)

## Construcción del HUD de partida (delegada a GameHUD).
func _build_game() -> void:
	GameHUD.build(self)

## Tras la jugada de la IA (o del humano), si hay premove programado y es
## turno del humano, lo ejecuta.

func _unhandled_input(event: InputEvent) -> void:
	# Esc → volver: del editor/guía al menú, de la partida al menú
	# (con confirmación si la partida sigue en curso).
	if event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		if editor_ui != null:
			_close_editor()
			get_viewport().set_input_as_handled()
		elif game_ui != null:
			if tm != null and not tm.over:
				var dlg := ConfirmationDialog.new()
				dlg.title = "Salir"
				dlg.dialog_text = "¿Abandonar la partida y volver al menú?"
				add_child(dlg)
				dlg.confirmed.connect(_restart)
				dlg.canceled.connect(dlg.queue_free)
				dlg.popup_centered()
			else:
				_restart()
			get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	if ws != null: _ws_poll()
	# breakpoint: <950 px → panel debajo del tablero (estilo compacto)
	if game_ui != null:
		var want := get_viewport_rect().size.x < 950.0
		if want != _compact:
			_compact = want
			game_ui.vertical = want
			side_panel.custom_minimum_size = \
				Vector2(0, 200) if want else Vector2(300, 0)
	if tm != null and not tm.over and not tm.clock.is_empty():
		tm.tick_clock(dt)
		hud_clock.text = "⏱  %s  —  %s" % [
			_fmt_time(tm.clock[0]), _fmt_time(tm.clock[1])]
		# alerta visual: rojo al que le quedan <10 s
		hud_clock.add_theme_color_override("font_color",
			Color(1, 0.25, 0.25)
				if tm.clock[tm.current] < 10.0
				else Color(1, 1, 1))
		# aviso sonoro al cruzar los 10 s (una vez por bando)
		for pl in [0, 1]:
			if tm.clock[pl] < 10.0 and not _low_warned[pl]:
				_low_warned[pl] = true
				if pl == my_net or my_net < 0:
					sfx.beep(880.0, 0.08)
			elif tm.clock[pl] >= 10.0:
				_low_warned[pl] = false

## Rendición confirmada: aplica localmente y sincroniza online.
func _do_resign(me: int) -> void:
	tm.resign(me)
	# sincronizar rendición online: enviar un "movimiento nulo"
	if online and ws != null:
		if ws_auth:
			_ws_send({"op": "play", "resign": true})
		else:
			_ws_send({"op": "move", "mv": {"resign": true}})
	elif online:
		_rpc_move.rpc({"from": Vector2i(-1, -1),
			"to": Vector2i(-1, -1), "resign": true})


func _fmt_time(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

## La IA juega cuando le toca (con un pequeño retardo visual).
func _maybe_bot() -> void:
	if bot == null or tm.over: return
	if not ai_both and tm.current != ai_player: return
	await get_tree().create_timer(0.35).timeout
	if tm.over: return
	if not ai_both and tm.current != ai_player: return
	var side_to := tm.current
	# opt_style vive en el menú (ya liberado) — leer la copia congelada
	if ai_both and int(_saved_opts.get("style", 0)) == 0:
		# Clockwork: cada IA juega con el estilo de su facción
		bot.style = PiecesData.FACTION_STYLE.get(
			tm.state.factions[side_to].id, "normal")
	var mv := bot.best_move(tm, side_to)
	if not mv.is_empty():
		tm.play(mv)
		_maybe_bot()  # Humenex: segundo movimiento de apertura
	# tras la jugada de la IA, ejecutar premove si es turno del humano
	if not tm.over and not ai_both and tm.current == board.human_idx:
		board.try_premove()

## Modo Zen: oculta todo el panel salvo el propio botón Zen
## (que vive fuera de las pestañas para poder volver).
func _toggle_zen() -> void:
	for c in side_panel.get_children():
		if c.name != "ZenToggle":
			c.visible = not c.visible
	hud_alert("Modo Zen %s" % ("activado" if _zen_on() else "desactivado"))

func _zen_on() -> bool:
	for c in side_panel.get_children():
		if c.name != "ZenToggle" and c.visible: return false
	return true

func _suggest() -> void:
	if bot == null: bot = BeliberBot.new(1)
	var mv := bot.best_move(tm, tm.current)
	if mv.is_empty(): return
	board.selected = mv.from
	board.legal = [mv]
	board.queue_redraw()
	hud_info.text = "Sugerencia: %s" % tm.state.describe(mv)

## Refresco del HUD (delegado a GameHUD).
func _update_hud() -> void:
	GameHUD.update(self)


func _on_game_over(w: int) -> void:
	# la señal puede dispararse dos veces (jugada con resign + msg
	# "over" del árbitro, o resync de partida terminada) — el
	# registro de stats solo corre una vez
	if _over_handled: return
	_over_handled = true
	_record_result()
	if w < 0:
		hud_turn.text = "¡Tablas!"
	else:
		hud_turn.text = "¡Ganan %s!" % tm.state.factions[w].name
		sfx.fanfare()
	var resumen := PostGame.summary(tm)
	# modo run: victoria → bendición y siguiente combate
	if run_active:
		if w == 0:
			hud_info.text = resumen
			_run_boon()
		else:
			stats["run_best"] = maxi(int(stats.get("run_best", 0)),
				run_level - 1)
			_save_stats()
			resumen += "\nRun terminada — racha: %d (mejor: %d)" \
				% [run_level - 1, stats.run_best]
			run_active = false
	PostGame.modal(self, w, resumen)

## Captura el tablero a PNG (zona del BoardView).
func _export_png() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var rect := Rect2i(board.get_global_rect())
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if rect.size.x <= 0: return
	img = img.get_region(rect)
	var path := "user://beliber_board.png"
	img.save_png(path)
	hud_info.text += "\nTablero exportado:\n" + path

## Persiste ajustes visuales en CFG_PATH.
func _save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("ui", "skin", ui_theme_mode)
	if board == null:
		c.save(CFG_PATH)
		return
	c.set_value("ui", "theme", board.theme_i)
	c.set_value("ui", "zoom", board.scale.x)
	c.set_value("ui", "anim", board.anim_dur)
	c.set_value("ui", "threats", board.show_threats)
	c.set_value("ui", "coords", board.show_coords)
	c.set_value("ui", "blind", board.blindfold)
	c.set_value("ui", "confirm", board.confirm_moves)
	c.set_value("ui", "mute", muted)
	c.save(CFG_PATH)

func _apply_settings() -> void:
	var c := ConfigFile.new()
	if c.load(CFG_PATH) != OK: return
	board.theme_i = int(c.get_value("ui", "theme", 0))
	var z: float = float(c.get_value("ui", "zoom", 1.0))
	board.scale = Vector2(z, z)
	board.custom_minimum_size = Vector2(512 * z, 512 * z)
	board.anim_dur = float(c.get_value("ui", "anim", 0.18))
	board.show_threats = bool(c.get_value("ui", "threats", false))
	board.show_coords = bool(c.get_value("ui", "coords", true))
	board.blindfold = bool(c.get_value("ui", "blind", false))
	board.confirm_moves = bool(c.get_value("ui", "confirm", false))
	muted = bool(c.get_value("ui", "mute", false))

func _rematch() -> void:
	var s0: int = _last_sel[0]   # el menú original ya está freed
	var s1: int = _last_sel[1]
	_restart()
	opt_p0.select(s1)  # bandos intercambiados
	opt_p1.select(s0)
	# el menú reconstruido arranca con defaults — restaurar las
	# reglas de la partida que acabamos de dejar (stall/mid/reloj/IA)
	if not _saved_opts.is_empty():
		opt_eq0.select(int(_saved_opts.get("eq0", 0)))
		opt_eq1.select(int(_saved_opts.get("eq1", 0)))
		chk_midline.button_pressed = bool(_saved_opts.get("mid", false))
		var st: int = int(_saved_opts.get("stall", 0))
		chk_stall.button_pressed = st > 0
		if st > 0: stall_spin.value = st
		opt_clock.select(int(_saved_opts.get("clock", 0)))
		opt_style.select(int(_saved_opts.get("style", 0)))
		opt_ai.select(int(_saved_opts.get("ai_lvl", 0)))
		chk_handicap.button_pressed = \
			bool(_saved_opts.get("handicap", false))
		chk_coop.button_pressed = bool(_saved_opts.get("coop", false))
	_start_game()

## Editor de posición libre: coloca piezas y juega desde esa
## configuración (validación: un líder por bando).
func _open_pos_editor() -> void:
	var ed := PosEditor.new(factions[opt_p0.selected],
		factions[opt_p1.selected])
	editor_ui = ed
	menu_root.visible = false
	add_child(ed)
	ed.start.connect(func(pos: Array, first: int):
		# partida desde posición = local; limpiar red y estado de una
		# partida anterior (sin esto, un bot de antes seguiría jugando
		# y _over_handled saltaría el registro de stats)
		online = false; net_peer = null; ws = null; ws_auth = false
		my_net = -1
		ai_player = -1
		ai_both = false
		bot = null
		coop = false
		_over_handled = false
		_flip_board = chk_flip.button_pressed
		_last_sel = [opt_p0.selected, opt_p1.selected]
		var o := _tm_opts()
		o["pos"] = pos
		o["first"] = first
		tm = TurnManager.new(factions[opt_p0.selected], 0,
			factions[opt_p1.selected], 0, o)
		ed.queue_free()
		editor_ui = null   # evita un doble queue_free en _close_editor
		menu_root.queue_free()
		_build_game())
	ed.cancel.connect(func():
		ed.queue_free()
		editor_ui = null
		menu_root.visible = true)

func _restart() -> void:
	tutorial = false
	tut_steps = []
	# volver al menú rompe cualquier run en curso — si no se limpia,
	# la siguiente partida normal heredaría las bendiciones
	run_active = false
	coop = false
	_close_net()   # corta ws/ENet: mover del rival tocaría HUD freed
	# y el bot: en IA-vs-IA seguiría jugando la partida ya desmontada
	bot = null
	ai_player = -1
	ai_both = false
	tm = null   # el manager muere con la partida (su tick de reloj
	#         tocaría hud_clock, ya liberado por game_ui)
	game_ui.queue_free()
	_build_menu()

## Cierra cualquier conexión activa y deja el estado de red limpio.
## Llamada desde _restart: el socket abierto seguiría recibiendo
## jugadas con el TurnManager vivo y el HUD ya liberado.
func _close_net() -> void:
	online = false
	my_net = -1
	ws_auth = false
	ws_open = false
	if ws != null:
		ws.close()
		ws = null
	ws_room = ""
	ws_token = ""
	ws_side = -1
	if net_peer != null:
		net_peer.close()
		net_peer = null
		multiplayer.multiplayer_peer = null

func _load_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY: return
	var loaded := TurnManager.load_game(data, factions)
	if loaded == null: return
	tm = loaded
	# partida cargada = hotseat limpio: sin bot, sin IA vs IA, sin
	# estado de una partida anterior (sin esto un bot activo
	# seguiría jugando la partida cargada)
	ai_player = -1
	ai_both = false
	bot = null
	coop = false
	my_net = -1
	_over_handled = false
	_flip_board = chk_flip.button_pressed
	_last_sel = [opt_p0.selected, opt_p1.selected]
	online = false; net_peer = null; ws = null; ws_auth = false
	menu_root.queue_free()
	_build_game()

