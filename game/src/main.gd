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
static func _env_path(env: String, fallback: String) -> String:
	# los tests E2E instancian la escena real; sin override leían y
	# escribían el beliber.cfg / beliber_save.json del jugador
	var v := OS.get_environment(env)
	return v if v != "" else fallback

var CFG_PATH := _env_path("BELIBER_CFG", "user://beliber.cfg")
var SAVE_PATH := _env_path("BELIBER_SAVE", "user://beliber_save.json")
var EXPORT_PATH := _env_path("BELIBER_EXPORT", "user://beliber_match.txt")

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
var draw_offered := false          # ya ofrecí tablas en esta partida

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
	# reconstruir facciones desde disco: apply_cfg online muta
	# app.factions (filas/ovr del rival) y sin el refresco la
	# siguiente partida local las heredaba en silencio
	factions = PiecesData.all()
	PieceEditor.apply_overrides(factions)
	ArmyBuilder.apply(factions)
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
	# viajan las FILAS EFECTIVAS del equipo elegido — siempre, no solo
	# con 'Personalizado': un Eq1/Eq2 editado en el editor de
	# despliegue también es distinto del archivo local del rival
	for si in [0, 1]:
		var fac: Dictionary = factions[int(cfg["f%d" % si])]
		var ei := mini(int(cfg["eq%d" % si]), fac.setups.size() - 1)
		if ei >= 0:
			cfg["rows%d" % si] = fac.setups[ei]
	# overrides del editor de piezas (cells/leg2/valor/etc.): si no
	# viajan, el rival genera movimientos con defs distintas → desync
	var ovr := PieceEditor.load_overrides()
	if not ovr.is_empty() and JSON.stringify(ovr).length() < 48000:
		cfg["ovr"] = ovr
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
	if tm == null: return   # paquete temprano, antes de _rpc_config
	if mv.get("resign", false):
		tm.resign(1 - my_net)   # quien envió es el rival
		return
	if mv.has("draw"):
		match mv.draw:
			"offer": _on_draw_offered()
			"decline":
				draw_offered = false   # puede volver a ofrecer
				hud_alert("El rival rechazó las tablas.")
			_:
				# un "accept" sin oferta previa empataba la partida
				# sin que hubiéramos ofrecido nada (trampa remota)
				if draw_offered:
					tm.agree_draw()
				draw_offered = false
		return
	# nunca aplicar el dict remoto a ciegas (ENet no tiene árbitro):
	# casamos contra las legales locales y jugamos la variante LOCAL
	# — un 'captures'/'push' falsificado por el rival no tendría efecto
	var legal: Variant = TurnManager.match_legal(tm, mv)
	if legal == null:
		hud_alert("Jugada remota ilegal ignorada.")
		return
	tm.play(legal)

## Tablas = oferta + consentimiento (antes un solo clic cerraba la
## partida para ambos: ni siquiera era una oferta).
func _offer_draw() -> void:
	if tm == null or tm.over or ai_both: return
	if not online:
		# vs IA la IA también decide: un solo clic empataba la
		# partida cuando el bot iba ganando
		if ai_player >= 0 and not coop and bot != null \
				and BeliberBot.evaluate(tm.state, ai_player) > 1.0:
			hud_alert("La IA rechaza las tablas.")
			return
		tm.agree_draw()
		return
	if draw_offered:
		hud_alert("Ya ofreciste tablas.")
		return
	draw_offered = true
	hud_alert("Oferta de tablas enviada.")
	_send_draw_resp("offer")

## El rival ofreció tablas: aceptar cierra la partida en tablas y se
## lo comunica; rechazar solo se lo comunica.
func _on_draw_offered() -> void:
	if tm == null or tm.over: return
	var d := ConfirmationDialog.new()
	d.dialog_text = "El rival ofrece tablas. ¿Aceptar?"
	d.ok_button_text = "Aceptar"
	d.cancel_button_text = "Rechazar"
	d.confirmed.connect(func():
		d.queue_free()
		# la partida pudo terminar con el diálogo abierto (reloj,
		# desconexión): tm puede ser null/over al confirmar
		if tm != null and not tm.over:
			tm.agree_draw()
			_send_draw_resp("accept"))
	d.canceled.connect(func(): d.queue_free(); _send_draw_resp("decline"))
	add_child(d)
	d.popup_centered()

## Envía offer/accept/decline por el transporte activo.
func _send_draw_resp(k: String) -> void:
	var dv := {"draw": k}
	if ws != null:
		if ws_auth: _ws_send({"op": "play", "draw": k})
		else: _ws_send({"op": "move", "mv": dv})
	elif online:
		_rpc_move.rpc(dv)

## Chat por ENet (el relay WS usa {"op":"chat"}).
@rpc("any_peer", "reliable")
func _rpc_chat(t: String) -> void:
	_chat_log("[rival] " + t.left(200), true)

## Registro de chat con límite: sin cap el Label crecía sin tope
## y cada append re-renderizaba todo el historial.
## notify=true avisa con toast: el log vive en una pestaña oculta y
## un mensaje del rival pasaba inadvertido.
func _chat_log(t: String, notify := false) -> void:
	if notify: hud_alert(t)
	if hud_log == null: return
	hud_log.text += "\n" + t
	var lines := hud_log.text.split("\n")
	if lines.size() > 50:
		hud_log.text = "\n".join(lines.slice(-50))

func hud_alert(t: String) -> void:
	# toast animado (fade + slide, se autodestruye)
	Juice.toast(self, t)

var ws_last_url := ""  # última URL WS usada (auto-rejoin sin widgets)
var zoom_v := 1.0     # zoom elegido por el usuario (slider)
var _pid_str := ""
## ID persistente del jugador para el ladder (el nick es suplantable;
## el pid se genera una vez y vive en los ajustes).
func _pid() -> String:
	if _pid_str != "": return _pid_str
	var c := ConfigFile.new()
	if c.load(CFG_PATH) == OK:
		_pid_str = str(c.get_value("net", "pid", ""))
	if _pid_str == "":
		_pid_str = Crypto.new().generate_random_bytes(8).hex_encode()
		c.set_value("net", "pid", _pid_str)
		c.save(CFG_PATH)
	return _pid_str

## Token de identidad del ladder, emitido por el host autoritativo la
## primera vez que ve nuestro pid (op "id_tok"). Sin él el host deja
## jugar pero sin rating — evita que otro cliente declare tu pid.
func _ladder_tok() -> String:
	var c := ConfigFile.new()
	if c.load(CFG_PATH) == OK:
		return str(c.get_value("net", "tok", ""))
	return ""

func _save_ladder_tok(tok: String) -> void:
	var c := ConfigFile.new()
	c.load(CFG_PATH)
	c.set_value("net", "tok", tok)
	c.save(CFG_PATH)



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
	# "Personalizado" solo si la facción tiene setups[2] (ejército del
	# Constructor): antes se podía elegir siempre y deploy() caía a
	# Eq2 en silencio — además el índice eq=2 viajaba online sin rows
	var c0: bool = f0.setups.size() < 3
	var c1: bool = f1.setups.size() < 3
	opt_eq0.set_item_disabled(2, c0)
	opt_eq1.set_item_disabled(2, c1)
	if c0 and opt_eq0.selected == 2: opt_eq0.select(0)
	if c1 and opt_eq1.selected == 2: opt_eq1.select(0)

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
	draw_offered = false
	_over_handled = false
	# una ws pendiente de la pantalla online (queue o sala esperando
	# rival) seguía polleando durante la partida local: un 'room' o
	# 'move' tardío tocaba opt_* liberados / tm nulo → crash
	if not online: _close_net()
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
	_freeze_opts()
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
			run_first = false   # la bendición es de un solo uso
			tm.current = 0
			tm.first_turn_done = {0: false, 1: false}
			tm._begin_turn()
	_setup_bot(run_blunder)
	_teardown_screens()
	_build_game()

## Congela la config del menú en _saved_opts — los option buttons se
## liberan con menu_root y _rematch/_run_next no pueden leerlos.
## También lo usan draft y pos_editor (que no pasan por _start_game).
func _freeze_opts() -> void:
	_saved_opts = {"eq0": opt_eq0.selected, "eq1": opt_eq1.selected,
		"mid": chk_midline.button_pressed,
		"stall": int(stall_spin.value) if chk_stall.button_pressed else 0,
		"clock": opt_clock.selected,
		"style": opt_style.selected,
		"ai_lvl": opt_ai.selected,
		"handicap": chk_handicap.button_pressed,
		"coop": chk_coop.button_pressed}

## Configura la IA según opt_ai/opt_style. "auto" = la IA adopta el
## arquetipo de su facción (Clockwork); IA vs IA usa nivel fijo 2.
## Antes este bloque estaba duplicado en _start_game y en el
## diálogo "jugar desde el editor".
func _setup_bot(extra_blunder := 0.0) -> void:
	var styles := ["auto", "normal", "aggro", "defense"]
	var blunders := [0.25, 0.10, 0.0]
	var stl: String = styles[mini(opt_style.selected, styles.size() - 1)]
	bot = null
	if ai_player >= 0:
		if stl == "auto":
			stl = PiecesData.FACTION_STYLE.get(
				tm.state.factions[ai_player].id, "normal")
		bot = BeliberBot.new(mini(opt_ai.selected, 3), stl,
			blunders[mini(opt_ai.selected - 1, 2)] + extra_blunder)
	elif ai_both:
		bot = BeliberBot.new(2, stl, 0.0)

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
	# _restart reconstruye el menú con defaults — restaurar la config
	# del run congelada en _saved_opts o la facción del jugador, el
	# reloj 5+0 y las reglas se perdían desde el combate 2 (la
	# bendición "+60 s a tu reloj" quedaba sin efecto)
	if not _saved_opts.is_empty():
		opt_p0.select(_last_sel[0])
		opt_eq0.select(clampi(int(_saved_opts.eq0), 0,
			opt_eq0.item_count - 1))
		opt_eq1.select(clampi(int(_saved_opts.eq1), 0,
			opt_eq1.item_count - 1))
		chk_midline.button_pressed = bool(_saved_opts.mid)
		chk_stall.button_pressed = int(_saved_opts.stall) > 0
		if int(_saved_opts.stall) > 0:
			stall_spin.value = int(_saved_opts.stall)
		opt_clock.select(clampi(int(_saved_opts.clock), 0,
			opt_clock.item_count - 1))
		opt_style.select(clampi(int(_saved_opts.style), 0,
			opt_style.item_count - 1))
		chk_handicap.button_pressed = bool(_saved_opts.handicap)
		chk_coop.button_pressed = bool(_saved_opts.coop)
		chk_flip.button_pressed = _flip_board
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
		_close_net()   # envía 'leave' y cierra el socket de verdad
		my_net = -1
		coop = false
		_over_handled = false
		draw_offered = false
		_low_warned = [false, false]
		_flip_board = chk_flip.button_pressed
		_last_sel = [opt_p0.selected, opt_p1.selected]
		# sin _saved_opts la revancha tras un draft restauraba la
		# config de la partida normal anterior (o defaults)
		_freeze_opts()
		# "IA vs IA" (opción 4) también funciona en draft — y sin el
		# clamp, blunders[3] estaba fuera de rango
		ai_both = opt_ai.selected == 4
		ai_player = -1 if ai_both else \
			(opt_ai.selected - 1 if opt_ai.selected > 0 else -1)
		if ai_player == 0: ai_player = 1
		_setup_bot()   # misma configuración que _start_game
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
	# botón volver dedicado para no depender del nombre del nodo raíz;
	# debe colgar de editor_ui — antes era hijo de app y quedaba
	# huérfano encima del menú tras cada visita
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
	editor_ui.add_child(back)

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
	# récord de Puzzle Rush en el perfil (antes se perdía al cerrar)
	editor_ui.rush_done.connect(func(s: int):
		if s > int(stats.get("rush_best", 0)):
			stats["rush_best"] = s
			_save_stats()
			hud_alert("🏁 ¡Nuevo récord de Rush: %d puzzles!" % s))
	add_child(editor_ui)
	_add_back()

## Cierra la pantalla auxiliar (editor/guía/puzzles/perfil/online) →
## menú.
func _close_editor() -> void:
	# salir de la pantalla online con una ws pendiente la dejaba
	# abierta: un 'room'/'move' tardío tocaba opt_* liberados o un
	# tm nulo — abandonar la sala/cola al volver
	_close_net()
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
	# hijo de la pantalla (no de app): se libera con ella — antes cada
	# visita a guía/puzzles/online dejaba un '← Volver' apilado
	if is_instance_valid(editor_ui):
		editor_ui.add_child(back)
	else:
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
	editor_ui.add_child(back)   # hijo de la pantalla: se libera con ella

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
		# auto-encaje: si el viewport no da para el tablero a 1:1 se
		# reduce la escala efectiva sin pisar el zoom del usuario
		if board != null:
			var fit := minf(1.0,
				(get_viewport_rect().size.x - 24.0) / 512.0)
			if absf(board.scale.x - zoom_v * fit) > 0.001:
				_apply_zoom()
	if tm != null and not tm.over and not tm.clock.is_empty():
		# con árbitro autoritativo el fin por tiempo lo decide el servidor
		tm.tick_clock(dt, not ws_auth)
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
			# side explícito: sin él el resync asumía que se rindió
			# el rival (el relay archiva el mv tal cual)
			_ws_send({"op": "move",
				"mv": {"resign": true, "side": my_net}})
	elif online:
		_rpc_move.rpc({"from": Vector2i(-1, -1),
			"to": Vector2i(-1, -1), "resign": true})


func _fmt_time(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

## La IA juega cuando le toca (con un pequeño retardo visual).
func _maybe_bot() -> void:
	if bot == null or tm == null or tm.over: return
	if not ai_both and tm.current != ai_player: return
	var my_tm := tm   # durante el await puede llegar otra partida
	await get_tree().create_timer(0.35).timeout
	if tm != my_tm or tm == null or tm.over: return
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
	# espectador (IA-vs-IA) o turno rival online: sugerir pintaba la
	# jugada del rival en el tablero local — confuso
	if tm == null or tm.over or ai_both: return
	if online and tm.current != my_net: return
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
	hud_alert("Tablero exportado: " + path)

## Persiste ajustes visuales en CFG_PATH.
func _save_settings() -> void:
	var c := ConfigFile.new()
	# cargar antes de guardar: save() sobrescribe el archivo entero y
	# borraba la sección [net] con el pid persistente del ladder
	c.load(CFG_PATH)
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
	zoom_v = z
	_apply_zoom()
	board.anim_dur = float(c.get_value("ui", "anim", 0.18))
	board.show_threats = bool(c.get_value("ui", "threats", false))
	board.show_coords = bool(c.get_value("ui", "coords", true))
	board.blindfold = bool(c.get_value("ui", "blind", false))
	board.confirm_moves = bool(c.get_value("ui", "confirm", false))
	muted = bool(c.get_value("ui", "mute", false))

## Escala efectiva del tablero = zoom del usuario × factor de encaje
## (ventanas < ~536 px encogen el tablero en vez de desbordarlo).
func _apply_zoom() -> void:
	if board == null: return
	var fit := minf(1.0,
		(get_viewport_rect().size.x - 24.0) / 512.0)
	var s: float = zoom_v * fit
	board.scale = Vector2(s, s)
	board.custom_minimum_size = Vector2(512 * s, 512 * s)

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
		# el tablero girado tampoco es parte de _saved_opts: se perdía
		chk_flip.button_pressed = _flip_board
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
		_close_net()   # cierra el socket de verdad (antes quedaba abierto)
		my_net = -1
		ai_player = -1
		ai_both = false
		bot = null
		coop = false
		_over_handled = false
		draw_offered = false
		_low_warned = [false, false]
		_flip_board = chk_flip.button_pressed
		_last_sel = [opt_p0.selected, opt_p1.selected]
		# misma razón que en draft: la revancha necesita la config
		# congelada, no los defaults del menú reconstruido
		_freeze_opts()
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
## Libera cualquier pantalla superpuesta antes de construir el juego:
## la pantalla online solo OCULTABA el menú — al arrancar partida por
## WebSocket quedaba viva debajo del HUD (y Esc la "cerraba" durante la
## partida reconstruyendo el menú encima del tablero).
func _teardown_screens() -> void:
	for n in [editor_ui, menu_root]:
		if is_instance_valid(n): n.queue_free()
	editor_ui = null
	menu_root = null

func _close_net() -> void:
	if ws != null and ws_room != "" and tm != null and not tm.over \
			and ws.get_ready_state() == WebSocketPeer.STATE_OPEN \
			and ws_side >= 0:
		# abandono con partida en curso = rendición: el rival y el
		# ladder reciben el 'over' limpio en vez de un 'offline' etéreo
		if ws_auth:
			ws.send_text(JSON.stringify({"op": "play", "resign": true}))
		else:
			ws.send_text(JSON.stringify({"op": "move",
				"mv": {"resign": true, "side": ws_side}}))
	online = false
	my_net = -1
	ws_auth = false
	ws_open = false
	if ws != null:
		# avisar al servidor antes de cerrar: sin 'leave' la sala
		# quedaba zombie 4 h y el rival viendo "offline" eterno
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN \
				and ws_room != "":
			ws.send_text(JSON.stringify({"op": "leave"}))
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
	# load_json recupera desde .bak si el save está corrupto
	var data = StatsStore.load_json(SAVE_PATH)
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
	# cerrar el transporte de verdad (antes: ws=null sin close() dejaba
	# el socket abierto y la sala zombi hasta el TTL del servidor)
	_close_net()
	online = false; net_peer = null; ws = null; ws_auth = false
	draw_offered = false
	menu_root.queue_free()
	_build_game()
	# partida guardada ya terminada: el fin no llega por señal (se
	# restaura 'over' sin emitir) — mostrar el resultado en el HUD
	# y no volver a registrar stats
	if tm.over:
		_over_handled = true
		hud_turn.text = "¡Tablas!" if tm.winner < 0 else \
			"¡Ganan %s!" % tm.state.factions[tm.winner].name

