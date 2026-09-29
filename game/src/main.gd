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
const STATS_PATH := "user://beliber_stats.json"
const CFG_PATH := "user://beliber.cfg"
const SAVE_PATH := "user://beliber_save.json"
const EXPORT_PATH := "user://beliber_match.txt"

var stats := {}                # persistido en STATS_PATH
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

func _load_stats() -> void:
	if FileAccess.file_exists(STATS_PATH):
		var f := FileAccess.open(STATS_PATH,
			FileAccess.READ)
		# solo aceptar Dictionary (un JSON dañado puede dar bool/null)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary: stats = parsed
		f.close()
	stats.merge({"games": 0, "wins": {}, "ach": [], "xp": {},
		"w": 0, "l": 0, "d": 0, "fstat": {}, "history": [],
		"rec_fast": 0, "rec_long": 0}, false)

func _save_stats() -> void:
	var f := FileAccess.open(STATS_PATH,
		FileAccess.WRITE)
	f.store_string(JSON.stringify(stats))
	f.close()

const ACH := {
	"primera": "Primera victoria",
	"caza5": "Cazador: 5+ capturas en una partida",
	"ia3": "Vencer a la IA nivel 3",
	"cinco": "Cinco partidas disputadas",
	"veloz": "Ganar en menos de 15 movimientos",
}

func _grant(id: String) -> void:
	if stats.ach.has(id): return
	stats.ach.append(id)
	if hud_info: hud_info.text += "\n🏆 " + ACH[id]

const XP_GAME := 10   # por jugar
const XP_WIN := 30    # bonus por ganar

## Nivel de dominio de una facción (progresión estilo perfil lichess).
func _faction_level(fid: String) -> int:
	return int(stats.xp.get(fid, 0)) / 100 + 1

func _record_result() -> void:
	stats.games = int(stats.games) + 1
	for k in ["xp", "fstat", "history", "wins", "ach"]:
		if not stats.has(k): stats[k] = {} if k != "ach" \
			and k != "history" else []
	# XP para la facción que jugó el humano (J1 local, mi lado online)
	var human_side := my_net if online else (0 if not ai_both else -1)
	if human_side >= 0:
		var played_fid: String = tm.state.factions[human_side].id
		var before := int(stats.xp.get(played_fid, 0))
		var gain := XP_GAME + (XP_WIN if tm.winner == human_side else 0)
		stats.xp[played_fid] = before + gain
		if before / 100 != stats.xp[played_fid] / 100:
			if hud_info:
				hud_info.text += "\n⭐ ¡%s sube a nivel %d!" % [
					played_fid.capitalize(), _faction_level(played_fid)]
		# resultado V/E/D + stats por facción + historial
		var res := "E"
		if tm.winner == human_side: res = "V"; stats.w += 1
		elif tm.winner < 0: stats.d += 1
		else: stats.l += 1
		var fs: Dictionary = stats.fstat.get(played_fid,
			{"g": 0, "w": 0})
		fs.g += 1
		if res == "V": fs.w += 1
		stats.fstat[played_fid] = fs
		var mode := "online" if online else \
			("run" if run_active else \
			("IA" if ai_player >= 0 else "local"))
		stats.history.append({"r": res, "me": played_fid,
			"vs": tm.state.factions[1 - human_side].id,
			"mv": tm.log.size(), "mode": mode,
			"ts": int(Time.get_unix_time_from_system())})
		while stats.history.size() > 20: stats.history.pop_front()
		# récords
		if res == "V" and (int(stats.rec_fast) == 0 \
				or tm.log.size() < int(stats.rec_fast)):
			stats.rec_fast = tm.log.size()
		stats.rec_long = maxi(int(stats.rec_long), tm.log.size())
	if tm.winner >= 0:
		var fid: String = tm.state.factions[tm.winner].id
		stats.wins[fid] = int(stats.wins.get(fid, 0)) + 1
		_grant("primera")
		if ai_player >= 0 and tm.winner == 0 \
				and int(_saved_opts.get("ai_lvl", 0)) == 3:
			_grant("ia3")
		if tm.log.size() < 15: _grant("veloz")
	if stats.games >= 5: _grant("cinco")
	if tm.captured_by[0].size() >= 5 or tm.captured_by[1].size() >= 5:
		_grant("caza5")
	_save_stats()

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
	# inyectar filas custom (ejército "Personalizado" del host) —
	# igual que _apply_cfg: sin ellas cada lado usa su archivo local
	for si in [0, 1]:
		if cfg.has("rows%d" % si):
			var fac: Dictionary = factions[int(cfg["f%d" % si])]
			if fac.setups.size() > 2: fac.setups[2] = cfg["rows%d" % si]
			else: fac.setups.append(cfg["rows%d" % si])
	opt_p0.select(int(cfg.f0)); opt_eq0.select(int(cfg.eq0))
	opt_p1.select(int(cfg.f1)); opt_eq1.select(int(cfg.eq1))
	chk_midline.button_pressed = bool(cfg.mid)
	var stall2: int = int(cfg.get("stall", 0))
	chk_stall.button_pressed = stall2 > 0
	if stall2 > 0: stall_spin.value = stall2
	opt_clock.select(int(cfg.clock))
	ai_player = -1
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



## ===== Relay WebSocket (salas por código + reconexión) =====

## ===== Relay WebSocket (delegado a NetClient) =====

func _ws_connect(create: bool) -> void:
	NetClient.open(self, create)

var _ws_pending := ""
var _ws_cfg := {}          # última cfg aplicada (para resync sin cfg)

func _ws_send(msg: Dictionary) -> void:
	NetClient.send(self, msg)

func _ws_poll() -> void:
	NetClient.poll(self)

func _apply_cfg(cfg: Dictionary) -> void:
	NetClient.apply_cfg(self, cfg)

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

## Codificación recursiva: Vector2i → {"x":…,"y":…}
func _lbl(t: String) -> Label:
	return Widgets.lbl(t)

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

const CLOCK_CHOICES := [[0, 0], [60, 0], [180, 2], [300, 0],
	[600, 5], [1800, 0]]

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
	box.add_child(_lbl("Victoria — combate %d. Elige bendición:"
		% run_level))
	for o in opts:
		var b := Button.new()
		b.text = o.t
		b.pressed.connect(func():
			o.f.call()
			for c in box.get_children(): c.queue_free()
			box.queue_free()
			_run_next())
		box.add_child(b)
	game_ui.get_node("SideVBox").add_child(box)

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
				"chk": func(mv): return mv.get("fx", 0) & FX.JUMP != 0 \
					or false})
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
					mv.get("fx", 0) & FX.JUMP != 0 or false})
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

func _build_game() -> void:
	# reset del estado del historial: sin esto una partida cargada
	# con el mismo nº de plies que la anterior saltaba el rebuild
	# (lista vacía) y las marcas !/? heredadas eran de la otra partida
	_log_n = -1
	_move_marks = []
	game_ui = BoxContainer.new()     # vertical flag → layout adaptable
	game_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(game_ui)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_ui.add_child(center)
	# barra de evaluación vertical junto al tablero (estilo lichess)
	var board_row := HBoxContainer.new()
	eval_bar = EvalBar.new()
	eval_bar.col0 = tm.state.factions[0].color
	eval_bar.col1 = tm.state.factions[1].color
	board_row.add_child(eval_bar)
	center.add_child(board_row)
	board = BoardView.new(tm)
	board.premove_enabled = ai_player >= 0
	board.human_idx = 0
	board.net_me = 9 if ai_both else my_net   # IA vs IA = espectador
	board.defer_play = ws_auth   # árbitro: solo emite intención
	# el invitado online siempre ve su bando abajo
	if online and my_net == 1: board.flipped = true
	board.move_played.connect(func(mv):
		if not online: return
		if ws != null:
			if ws_auth:
				# servidor autoritativo: solo intención from→to
				_ws_send({"op": "play",
					"from": NetCodec.enc(mv.from),
					"to": NetCodec.enc(mv.to)})
			else:
				_ws_send({"op": "move", "mv": NetCodec.enc(mv)})
		else:
			_rpc_move.rpc(mv))
	board_row.add_child(board)

	var side := VBoxContainer.new()
	side_panel = side
	side.name = "SideVBox"
	side.custom_minimum_size = Vector2(300, 0)
	game_ui.add_child(side)
	# tarjeta del rival (emblema + faccion, estilo chess.com)
	var rc := HBoxContainer.new()
	side.add_child(rc)
	hud_rival_icon = FactionIcon.new("", Color.WHITE, 30)
	rc.add_child(hud_rival_icon)
	hud_rival = Label.new()
	hud_rival.add_theme_font_size_override("font_size", 18)
	rc.add_child(hud_rival)
	# checklist del tutorial (walkthrough estilo Root)
	if tutorial:
		tut_box = VBoxContainer.new()
		tut_box.add_child(_lbl("Objetivos del tutorial"))
		for s in tut_steps:
			var l := _lbl("• " + s.t)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.add_theme_font_size_override("font_size", 13)
			tut_box.add_child(l)
		side.add_child(tut_box)
	# pestanas: Partida / Opciones / Chat (panel estilo lichess)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(tabs)
	var tab_game := VBoxContainer.new()
	tab_game.name = "Partida"
	tabs.add_child(tab_game)
	var tab_opts := VBoxContainer.new()
	tab_opts.name = "Opciones"
	tabs.add_child(tab_opts)
	var tab_chat := VBoxContainer.new()
	tab_chat.name = "Chat"
	tabs.add_child(tab_chat)
	var tg := tab_game
	var opts := tab_opts

	hud_turn = Label.new()
	hud_turn.add_theme_font_size_override("font_size", 28)
	tg.add_child(hud_turn)
	hud_clock = Label.new()
	hud_clock.add_theme_font_size_override("font_size", 20)
	tg.add_child(hud_clock)
	hud_eval = Label.new()
	hud_eval.add_theme_font_size_override("font_size", 16)
	tg.add_child(hud_eval)
	hud_opening = Label.new()
	hud_opening.add_theme_font_size_override("font_size", 13)
	hud_opening.add_theme_color_override("font_color",
		Color(0.75, 0.7, 0.55))
	tg.add_child(hud_opening)
	hud_info = Label.new()
	hud_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	tg.add_child(hud_info)
	# bandejas de capturadas — sección colapsable (clic en el toggle
	# oculta/muestra; estilo panel lichess)
	var cap_t := CheckButton.new()
	cap_t.text = "Capturas"
	cap_t.button_pressed = true
	tg.add_child(cap_t)
	var cap_box := VBoxContainer.new()
	tg.add_child(cap_box)
	cap_t.toggled.connect(func(on): cap_box.visible = on)
	var tr0 := HBoxContainer.new()
	tr0.add_child(_lbl("J1 ▸"))
	tray0 = CapturedTray.new()
	tray0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr0.add_child(tray0)
	cap_box.add_child(tr0)
	var tr1 := HBoxContainer.new()
	tr1.add_child(_lbl("J2 ▸"))
	tray1 = CapturedTray.new()
	tray1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr1.add_child(tray1)
	cap_box.add_child(tr1)
	# historial de movimientos — sección colapsable propia
	var mv_t := CheckButton.new()
	mv_t.text = "Movimientos (clic para revisar)"
	mv_t.button_pressed = true
	tg.add_child(mv_t)
	var mv_box := VBoxContainer.new()
	mv_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tg.add_child(mv_box)
	mv_t.toggled.connect(func(on): mv_box.visible = on)
	# lista clickeable: cada jugada salta a su posición de replay
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 130)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv_box.add_child(scroll)
	move_list = VBoxContainer.new()
	move_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(move_list)
	hud_log = Label.new()
	hud_log.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab_chat.add_child(hud_log)
	btn_cov = CheckButton.new()
	btn_cov.text = "Mapa de cobertura"
	btn_cov.toggled.connect(func(on): board.show_coverage = on; board.queue_redraw())
	opts.add_child(btn_cov)
	var btn_row := HBoxContainer.new()
	opts.add_child(btn_row)
	var b_undo := Button.new()
	b_undo.text = "Deshacer"
	b_undo.pressed.connect(func():
		if online: return  # deshacer desincronizaría ambos clientes
		if tm.undo(): board.queue_redraw(); _update_hud())
	btn_row.add_child(b_undo)
	var b_resign := Widgets.danger("Rendirse")
	b_resign.pressed.connect(func():
		if tm.over: return
		# diálogo de confirmación (estilo ProperUI Modal)
		var dlg := ConfirmationDialog.new()
		dlg.title = "Rendirse"
		dlg.dialog_text = "¿Seguro que quieres abandonar la partida?"
		dlg.ok_button_text = "Rendirse"
		dlg.cancel_button_text = "Seguir jugando"
		add_child(dlg)
		dlg.confirmed.connect(func():
			var me := tm.current if not online else my_net
			_do_resign(me))
		dlg.canceled.connect(dlg.queue_free)
		dlg.popup_centered())
	btn_row.add_child(b_resign)
	var b_export := Button.new()
	b_export.text = "Exportar"
	b_export.pressed.connect(func():
		var p := tm.export_log(EXPORT_PATH)
		hud_info.text += ("\nPartida exportada:\n" + p) if p != "" \
			else "\nError exportando")
	btn_row.add_child(b_export)
	var btn_row2 := HBoxContainer.new()
	opts.add_child(btn_row2)
	var b_flip := Button.new()
	b_flip.text = "Girar"
	b_flip.pressed.connect(func():
		board.flipped = not board.flipped; board.queue_redraw())
	btn_row2.add_child(b_flip)
	var b_hint := Button.new()
	b_hint.text = "Sugerir"
	b_hint.pressed.connect(_suggest)
	btn_row2.add_child(b_hint)
	var b_draw := Button.new()
	b_draw.text = "Tablas"
	b_draw.pressed.connect(func():
		if tm.over: return
		tm.agree_draw()
		# declarar tablas también al rival — si no solo se cierra
		# la mitad local y la otra queda desincronizada
		if online:
			var dv := {"draw": true}
			if ws != null and not ws_auth:
				_ws_send({"op": "move", "mv": dv})
			elif ws != null:
				_ws_send({"op": "play", "draw": true})
			else:
				_rpc_move.rpc(dv))
	btn_row2.add_child(b_draw)
	var b_save := Button.new()
	b_save.text = "Guardar"
	b_save.pressed.connect(func():
		var f := FileAccess.open(SAVE_PATH,
			FileAccess.WRITE)
		f.store_string(JSON.stringify(tm.save_game()))
		f.close()
		hud_info.text += "\nPartida guardada.")
	btn_row2.add_child(b_save)
	var btn_row3 := HBoxContainer.new()
	opts.add_child(btn_row3)
	var b_theme := Button.new()
	b_theme.text = "Tema"
	b_theme.pressed.connect(func():
		board.theme_i = (board.theme_i + 1) % BoardView.THEMES.size()
		board.queue_redraw(); _save_settings())
	btn_row3.add_child(b_theme)
	var b_prev := Button.new()
	b_prev.text = "◀"
	b_prev.pressed.connect(func():
		if board.view_i < 0:
			board.view_i = tm.replay_len() - 1
		else:
			board.view_i = maxi(0, board.view_i - 1)
		board.queue_redraw())
	btn_row3.add_child(b_prev)
	var b_next := Button.new()
	b_next.text = "▶"
	b_next.pressed.connect(func():
		if board.view_i < 0: return
		board.view_i += 1
		if board.view_i >= tm.replay_len(): board.view_i = -1
		board.queue_redraw())
	btn_row3.add_child(b_next)
	var b_live := Button.new()
	b_live.text = "Vivo"
	b_live.pressed.connect(func():
		board.view_i = -1; board.queue_redraw())
	btn_row3.add_child(b_live)
	# amenazas + zoom + velocidad de animación
	var btn_row4 := HBoxContainer.new()
	opts.add_child(btn_row4)
	var b_thr := CheckButton.new()
	b_thr.text = "Amenazas"
	b_thr.toggled.connect(func(on):
		board.show_threats = on; board.queue_redraw(); _save_settings())
	btn_row4.add_child(b_thr)
	btn_row4.add_child(_lbl("Zoom"))
	var zoom := HSlider.new()
	zoom.min_value = 0.7; zoom.max_value = 1.4
	zoom.step = 0.05; zoom.value = 1.0
	zoom.custom_minimum_size = Vector2(90, 0)
	zoom.value_changed.connect(func(v):
		board.scale = Vector2(v, v)
		board.custom_minimum_size = Vector2(512 * v, 512 * v)
		_save_settings())
	btn_row4.add_child(zoom)
	var opt_anim := OptionButton.new()
	for t in ["Animación lenta", "Animación normal", "Animación rápida",
			"Sin animación"]:
		opt_anim.add_item(t)
	opt_anim.select(1)
	opt_anim.item_selected.connect(func(i):
		board.anim_dur = [0.35, 0.18, 0.08, 0.001][i]
		_save_settings())
	btn_row4.add_child(opt_anim)
	# entrada por teclado: "e2e4" o "e2 e4"
	var key_row := HBoxContainer.new()
	opts.add_child(key_row)
	var inp := LineEdit.new()
	inp.placeholder_text = "e2e4"
	inp.custom_minimum_size = Vector2(80, 0)
	key_row.add_child(inp)
	var b_go := Button.new()
	b_go.text = "Mover"
	var do_key_move := func():
		var txt: String = inp.text.strip_edges().to_lower().replace(" ", "")
		inp.text = ""
		if txt.length() != 4: return
		var frm := Vector2i(txt.unicode_at(0) - 97,
			8 - int(txt.unicode_at(1) - 48))
		var to := Vector2i(txt.unicode_at(2) - 97,
			8 - int(txt.unicode_at(3) - 48))
		if not BoardState.inside(frm) or not BoardState.inside(to): return
		for mv in tm.legal_moves(frm):
			if mv.to == to:
				tm.play(mv); return
	b_go.pressed.connect(do_key_move)
	inp.text_submitted.connect(func(_t): do_key_move.call())
	key_row.add_child(b_go)
	# toggles: ciego, coordenadas, confirmación, mute, PNG
	var btn_row5 := HBoxContainer.new()
	opts.add_child(btn_row5)
	var b_blind := CheckButton.new()
	b_blind.text = "Ciego"
	b_blind.tooltip_text = "Oculta las piezas (memoria)"
	b_blind.toggled.connect(func(on):
		board.blindfold = on; board.queue_redraw(); _save_settings())
	btn_row5.add_child(b_blind)
	var b_coords := CheckButton.new()
	b_coords.text = "Coords"
	b_coords.button_pressed = true
	b_coords.toggled.connect(func(on):
		board.show_coords = on; board.queue_redraw(); _save_settings())
	btn_row5.add_child(b_coords)
	var b_conf := CheckButton.new()
	b_conf.text = "Confirmar"
	b_conf.tooltip_text = "Requiere un 2º clic en el destino"
	b_conf.toggled.connect(func(on):
		board.confirm_moves = on; _save_settings())
	btn_row5.add_child(b_conf)
	var btn_row6 := HBoxContainer.new()
	opts.add_child(btn_row6)
	var b_mute := CheckButton.new()
	b_mute.text = "Silencio"
	b_mute.toggled.connect(func(on): muted = on; _save_settings())
	btn_row6.add_child(b_mute)
	_opt_toggles = {
		"blind": b_blind, "coords": b_coords,
		"conf": b_conf, "mute": b_mute}
	var b_png := Button.new()
	b_png.text = "PNG"
	b_png.tooltip_text = "Exportar el tablero como imagen"
	b_png.pressed.connect(_export_png)
	btn_row6.add_child(b_png)
	var b_bel := Button.new()
	b_bel.text = "BEL-FEN"
	b_bel.tooltip_text = "Copiar la posición como texto compartible"
	b_bel.pressed.connect(func():
		# opt_* ya están liberados — usar la config congelada
		var s := BoardState.to_bel(tm.state,
			_last_sel[0], int(_saved_opts.get("eq0", 0)),
			_last_sel[1], int(_saved_opts.get("eq1", 0)), tm.current)
		DisplayServer.clipboard_set(s)
		hud_info.text += "\nPosición copiada: " + s.left(48) + "…")
	btn_row6.add_child(b_bel)
	var b_bel2 := Button.new()
	b_bel2.text = "Zen"
	b_bel2.tooltip_text = "Ocultar el panel (modo concentración)"
	b_bel2.pressed.connect(func(): _toggle_zen())
	btn_row6.add_child(b_bel2)
	var btn := Button.new()
	btn.text = "Nueva partida"
	btn.pressed.connect(_restart)
	opts.add_child(btn)
	# botón Zen SIEMPRE visible: fuera de lo que se oculta, si no no
	# se podía salir del modo concentración (el propio botón se ocultaba)
	var zen_btn := Button.new()
	zen_btn.name = "ZenToggle"
	zen_btn.text = "Zen"
	zen_btn.custom_minimum_size = Vector2(0, 32)
	zen_btn.pressed.connect(func(): _toggle_zen())
	side.add_child(zen_btn)
	# chat online (protocolo ya existe en relay y arbitro)
	if online:
		var chat := LineEdit.new()
		chat.placeholder_text = "Chat… (Enter para enviar)"
		chat.text_submitted.connect(func(t):
			if t.strip_edges() == "": return
			if ws != null:
				_ws_send({"op": "chat", "text": t})
			elif net_peer != null:
				_rpc_chat.rpc(t)
			_chat_log("[tú] " + t)
			chat.text = "")
		tab_chat.add_child(chat)

	_wire_tm()
	_apply_settings()
	# sincronizar los toggles con los ajustes cargados
	_opt_toggles.blind.set_pressed_no_signal(board.blindfold)
	_opt_toggles.coords.set_pressed_no_signal(board.show_coords)
	_opt_toggles.conf.set_pressed_no_signal(board.confirm_moves)
	_opt_toggles.mute.set_pressed_no_signal(muted)
	_update_hud()
	_maybe_bot()

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

## Nombre de apertura tipo lichess: la primera jugada de cada bando
## define el nombre ("Apertura Torre" = salió la Torre primero).
## El log es "J{n} {letra}{desde}→{hasta}" — se parsea la letra.
func _opening_name() -> String:
	if tm.log.is_empty(): return ""
	var parts := []
	var seen := [false, false]
	for i in mini(tm.log.size(), 6):
		var entry: String = tm.log[i]
		if entry.length() < 3 or entry[0] != "J": continue
		var pl := int(entry.substr(1, 1)) - 1
		if seen[pl]: continue
		seen[pl] = true
		var letter := entry.substr(3, 1)
		var f: Dictionary = tm.state.factions[pl]
		var pn: String = f.pieces.get(letter, {}).get("name", letter)
		parts.append("%s: %s" % [f.name, pn])
	return "Apertura — " + " · ".join(parts) if parts else ""

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

func _update_hud() -> void:
	var f: Dictionary = tm.state.factions[tm.current]
	var extra := ""
	if tm.moves_left > 1:
		extra = "  (quedan %d movimientos)" % tm.moves_left
	var who: String = f.name
	if online:
		who += "  (eres J%d — %s)" % [my_net + 1,
			"tu turno" if tm.current == my_net else "turno rival"]
	elif coop and tm.current == 0:
		who += "  (%s mueve)" % ("Humano A" if coop_turn == 0 else "Humano B")
	hud_turn.text = "Turno: %s" % who
	hud_turn.add_theme_color_override("font_color", f.color)
	# tarjeta del rival (arriba del panel): facción + bando
	var riv := 1 - my_net if online else \
		(1 if not board.flipped else 0)
	var rf: Dictionary = tm.state.factions[riv]
	hud_rival.text = "%s  J%d" % [rf.name, riv + 1]
	hud_rival.add_theme_color_override("font_color", rf.color)
	hud_rival_icon.fid = rf.id
	hud_rival_icon.col = rf.color
	hud_rival_icon.queue_redraw()
	var l0 := tm.state.leaders_alive(0)
	var l1 := tm.state.leaders_alive(1)
	hud_info.text = "Líderes — %s: %d  |  %s: %d%s\nMaterial — %d vs %d" % [
		tm.state.factions[0].name, l0, tm.state.factions[1].name, l1, extra,
		tm.material_value(0), tm.material_value(1)]
	# bandejas: las piezas de la facción víctima en su color
	var m0 := tm.material_value(0)
	var m1 := tm.material_value(1)
	tray0.setup(tm.captured_by[0], tm.state.factions[1],
		maxi(0, m0 - m1))
	tray1.setup(tm.captured_by[1], tm.state.factions[0],
		maxi(0, m1 - m0))
	# nombre de apertura (primeras jugadas, estilo lichess)
	hud_opening.text = "" if tm.log.size() > 10 else _opening_name()
	# barra de evaluación (motor propio, vista de J1)
	var ev := BeliberBot.evaluate(tm.state, 0)
	hud_eval.text = "Eval: %s  (J1 %+d)" % [
		"+" if ev > 0 else ("-" if ev < 0 else "="), ev]
	eval_bar.frac = clampf(0.5 + ev / 400.0, 0.0, 1.0)
	eval_bar.queue_redraw()
	# lista de jugadas clickeable (solo reconstruir si cambia)
	if tm.log.size() != _log_n:
		_log_n = tm.log.size()
		# clasificación incremental: solo las jugadas nuevas (undo
		# recorta el array; sin esto era O(n²) evaluaciones)
		while _move_marks.size() > tm.log.size():
			_move_marks.pop_back()
		for i in range(_move_marks.size(), tm.log.size()):
			_move_marks.append(_classify_move(i))
		for c in move_list.get_children(): c.queue_free()
		for i in tm.log.size():
			var b := Button.new()
			var mark: String = _move_marks[i] if i < _move_marks.size() else ""
			b.text = "%d. %s%s" % [i + 1, tm.log[i], mark]
			if mark != "":
				b.add_theme_color_override("font_color",
					Color(0.45, 0.9, 0.5) if mark[0] == "!" \
					else Color(1, 0.5, 0.45))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.flat = true
			b.add_theme_font_size_override("font_size", 12)
			b.pressed.connect(func(idx := i):
				board.view_i = idx + 1   # snapshot tras la jugada idx
				board.queue_redraw())
			move_list.add_child(b)

## Clasifica la jugada i del log por su swing de evaluación
## (estilo chess.com): ! buena, ? error, ?? blunder.
func _classify_move(i: int) -> String:
	var mover := int(tm.log[i].substr(1, 1)) - 1
	var snap0: Variant = tm.replay_snapshot(i)
	var snap1: Variant = tm.replay_snapshot(i + 1)
	if snap0 == null or snap1 == null: return ""
	var st := BoardState.new()
	st.restore(snap0)
	var e0 := BeliberBot.evaluate(st, mover)
	st.restore(snap1)
	var e1 := BeliberBot.evaluate(st, mover)
	var d := e1 - e0
	if d >= 4: return " !"
	elif d <= -7: return " ??"
	elif d <= -3: return " ?"
	return ""

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
	# resumen post-partida + análisis de errores
	var cap0 := " ".join(tm.captured_by[0])
	var cap1 := " ".join(tm.captured_by[1])
	# piezas restantes sobre el ejército inicial (tm.started lo
	# registraba pero nadie lo leía)
	var n0 := 0
	var n1 := 0
	for p in tm.state.grid:
		if p != null and p.owner == 0: n0 += 1
		elif p != null: n1 += 1
	# ritmo medio por jugada (tm.move_times se recogía pero nadie lo
	# leía — movidas rápidas/lentas son un buen sello de la partida)
	var mt := ""
	if not tm.move_times.is_empty():
		var acc := 0.0
		for t in tm.move_times: acc += float(t)
		mt = "Ritmo medio: %.1f s/jugada\n" % [acc / tm.move_times.size()]
	var resumen := "Movimientos: %d\n%sCapturado J1: %s\nCapturado J2: %s\nPiezas: %d/%d vs %d/%d\nMaterial: %d vs %d\n%s" % [
		tm.log.size(), mt, cap0 if cap0 != "" else "—",
		cap1 if cap1 != "" else "—",
		n0, tm.started[0].size(), n1, tm.started[1].size(),
		tm.material_value(0), tm.material_value(1),
		_postgame_analysis()]
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

## Fin de partida y análisis delegados a PostGame.
func _end_modal(w: int, resumen: String) -> void:
	PostGame.modal(self, w, resumen)

func _postgame_analysis() -> String:
	return PostGame.analysis(tm)

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

