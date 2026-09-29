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
var sfx: AudioStreamPlayer
var muted := false
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
	Juice.ui_sfx = _beep
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

func _build_menu() -> void:
	var margin := MarginContainer.new()
	menu_root = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 12)
	add_child(margin)
	var scroll := SmoothScroll.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var wrapper := CenterContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wrapper)
	select_ui = VBoxContainer.new()
	select_ui.custom_minimum_size = Vector2(560, 0)
	select_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(select_ui)
	# transición de entrada (fade suave al abrir el menú)
	select_ui.modulate.a = 0.0
	var _mt := create_tween()
	_mt.tween_property(select_ui, "modulate:a", 1.0, 0.2)

	var title := Label.new()
	title.text = "BELIBER"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_ui.add_child(title)

	var sub := Label.new()
	sub.text = "Ajedrez asimétrico por facciones"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_ui.add_child(sub)

	# ── NIVEL 1: acciones principales (botones enormes) ──
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 10)
	select_ui.add_child(row1)
	var btn := Widgets.primary("Jugar", 64)
	btn.custom_minimum_size.x = 210
	btn.tooltip_text = "Partida local con la configuración elegida"
	btn.pressed.connect(_start_game)
	row1.add_child(btn)
	var btn_onl := Button.new()
	btn_onl.text = "Online"
	btn_onl.custom_minimum_size = Vector2(145, 64)
	btn_onl.tooltip_text = "Matchmaking, salas, LAN y clasificación"
	btn_onl.pressed.connect(_open_online)
	row1.add_child(btn_onl)
	var btn_tut := Button.new()
	btn_tut.text = "Tutorial"
	btn_tut.custom_minimum_size = Vector2(135, 64)
	btn_tut.tooltip_text = "Partida guiada con objetivos paso a paso"
	btn_tut.pressed.connect(_start_tutorial)
	row1.add_child(btn_tut)
	var btn_prof := Button.new()
	btn_prof.text = "Perfil"
	btn_prof.custom_minimum_size = Vector2(105, 64)
	btn_prof.tooltip_text = "Estadísticas, logros y récords"
	btn_prof.pressed.connect(_open_profile)
	row1.add_child(btn_prof)

	select_ui.add_child(HSeparator.new())

	# selector de facción + emblema dibujado por código (config del vs)
	var grid := GridContainer.new()
	grid.columns = 3
	select_ui.add_child(grid)

	grid.add_child(_lbl("Jugador 1 (abajo)"))
	grid.add_child(_lbl("Jugador 2 (arriba)"))
	grid.add_child(Control.new())

	opt_p0 = _faction_picker()
	var pic0 := HBoxContainer.new()
	var ic0 := FactionIcon.new(factions[0].id, factions[0].color, 30)
	pic0.add_child(ic0)
	opt_p0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic0.add_child(opt_p0)
	grid.add_child(pic0)
	opt_p0.item_selected.connect(func(i):
		ic0.fid = factions[i].id; ic0.col = factions[i].color
		ic0.queue_redraw(); _refresh_values())

	opt_p1 = _faction_picker(); opt_p1.select(1)
	var pic1 := HBoxContainer.new()
	var ic1 := FactionIcon.new(factions[1].id, factions[1].color, 30)
	pic1.add_child(ic1)
	opt_p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic1.add_child(opt_p1)
	grid.add_child(pic1)
	opt_p1.item_selected.connect(func(i):
		ic1.fid = factions[i].id; ic1.col = factions[i].color
		ic1.queue_redraw(); _refresh_values())
	grid.add_child(Control.new())

	# valor del ejército (regla de equilibrio estilo Betza/CEO)
	val_lbl0 = _lbl(""); grid.add_child(val_lbl0)
	val_lbl1 = _lbl(""); grid.add_child(val_lbl1)
	grid.add_child(Control.new())

	grid.add_child(_lbl("Equipo"))
	grid.add_child(_lbl("Equipo"))
	grid.add_child(Control.new())

	opt_eq0 = OptionButton.new()
	opt_eq0.add_item("Eq1"); opt_eq0.add_item("Eq2"); opt_eq0.add_item("Personalizado")
	opt_eq0.item_selected.connect(func(_i): _refresh_values())
	grid.add_child(opt_eq0)
	opt_eq1 = OptionButton.new()
	opt_eq1.add_item("Eq1"); opt_eq1.add_item("Eq2"); opt_eq1.add_item("Personalizado")
	opt_eq1.item_selected.connect(func(_i): _refresh_values())
	grid.add_child(opt_eq1)
	grid.add_child(Control.new())

	opt_p0.item_selected.connect(func(_i): _refresh_values())
	opt_p1.item_selected.connect(func(_i): _refresh_values())

	# ── CONFIGURACIÓN AVANZADA (colapsada por defecto — reduce la
	# carga visual del menú; todo sigue a un clic de distancia) ──
	var adv_t := CheckButton.new()
	adv_t.text = "⚙ Configuración avanzada"
	adv_t.tooltip_text = "Reglas, rival IA, reloj, co-op y tema"
	select_ui.add_child(adv_t)
	var adv := VBoxContainer.new()
	adv.visible = false
	adv_t.toggled.connect(func(on): adv.visible = on)
	select_ui.add_child(adv)

	# reglas opcionales (de la competencia: Chess 2 midline, anti-stall)
	chk_midline = CheckBox.new()
	chk_midline.text = "Invasión de línea (líder llega a la última fila rival)"
	adv.add_child(chk_midline)
	var stall_row := HBoxContainer.new()
	adv.add_child(stall_row)
	chk_stall = CheckBox.new()
	chk_stall.text = "Anti-estancamiento"
	stall_row.add_child(chk_stall)
	stall_row.add_child(_lbl("turnos sin captura:"))
	stall_spin = SpinBox.new()
	stall_spin.min_value = 10; stall_spin.max_value = 60
	stall_spin.value = 30
	stall_row.add_child(stall_spin)

	# rival IA + reloj
	var opt_row := HBoxContainer.new()
	adv.add_child(opt_row)
	opt_row.add_child(_lbl("Jugador 2:"))
	opt_ai = OptionButton.new()
	for t in ["Humano", "IA nivel 1", "IA nivel 2", "IA nivel 3",
			"IA vs IA"]:
		opt_ai.add_item(t)
	opt_row.add_child(opt_ai)
	opt_row.add_child(_lbl("  Estilo:"))
	opt_style = OptionButton.new()
	for t in ["Auto (facción)", "Equilibrada", "Agresiva", "Defensiva"]:
		opt_style.add_item(t)
	opt_row.add_child(opt_style)
	var opt_row2 := HBoxContainer.new()
	adv.add_child(opt_row2)
	opt_row2.add_child(_lbl("Reloj:"))
	opt_clock = OptionButton.new()
	for t in ["Sin reloj", "1+0 Bullet", "3+2 Blitz", "5+0 Blitz",
			"10+5 Rapid", "30 min Clásico"]:
		opt_clock.add_item(t)
	opt_row2.add_child(opt_clock)
	chk_handicap = CheckBox.new()
	chk_handicap.text = "La IA juega con la mitad de tiempo"
	opt_row2.add_child(chk_handicap)
	chk_coop = CheckBox.new()
	chk_coop.text = "Co-op: 2 humanos vs IA"
	chk_coop.tooltip_text = "Dos jugadores alternan los movimientos de J1"
	opt_row2.add_child(chk_coop)
	var opt_row3 := HBoxContainer.new()
	adv.add_child(opt_row3)
	opt_row3.add_child(_lbl("Tema:"))
	var opt_skin := OptionButton.new()
	var modes := ["dark", "light", "contrast"]
	for t in ["Oscuro", "Claro", "Alto contraste"]:
		opt_skin.add_item(t)
	opt_skin.select(maxi(0, modes.find(ui_theme_mode)))
	opt_skin.item_selected.connect(func(i):
		ui_theme_mode = modes[i]
		theme = BeliberTheme.make(ui_theme_mode)
		RenderingServer.set_default_clear_color(BeliberTheme._v.bg)
		_save_settings())
	opt_row3.add_child(opt_skin)
	chk_flip = CheckBox.new()
	chk_flip.text = "Girar el tablero cada turno (modo local)"
	adv.add_child(chk_flip)

	# ── NIVEL 2: modos de juego (botones medianos) ──
	select_ui.add_child(HSeparator.new())
	select_ui.add_child(_lbl("Modos"))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 8)
	select_ui.add_child(row2)

	var btn_daily := Button.new()
	var _d := Time.get_date_dict_from_system()
	var today: int = int(_d.year) * 10000 + int(_d.month) * 100 + int(_d.day)
	var played_today: bool = int(stats.get("daily", 0)) == today
	btn_daily.text = "Desafío diario" + (" ✓" if played_today else "")
	btn_daily.custom_minimum_size = Vector2(130, 42)
	btn_daily.tooltip_text = "Enfrentamiento determinista por fecha" + \
		(" (ya jugado hoy)" if played_today else "")
	btn_daily.pressed.connect(_daily_challenge)
	row2.add_child(btn_daily)
	var btn_run := Button.new()
	btn_run.text = "Modo Run"
	btn_run.custom_minimum_size = Vector2(105, 42)
	btn_run.tooltip_text = "Racha: cada victoria sube el nivel del rival"
	btn_run.pressed.connect(_start_run)
	row2.add_child(btn_run)
	var btn_draft := Button.new()
	btn_draft.text = "Draft"
	btn_draft.custom_minimum_size = Vector2(90, 42)
	btn_draft.tooltip_text = "Pick alterno de piezas con presupuesto (CEO)"
	btn_draft.pressed.connect(_open_draft)
	row2.add_child(btn_draft)
	var btn_puz := Button.new()
	btn_puz.text = "Puzzles"
	btn_puz.custom_minimum_size = Vector2(100, 42)
	btn_puz.tooltip_text = "Encuentra la captura del líder"
	btn_puz.pressed.connect(_open_puzzles)
	row2.add_child(btn_puz)

	# ── NIVEL 3: herramientas (discretas) ──
	select_ui.add_child(_lbl("Herramientas"))
	var row3 := HBoxContainer.new()
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	row3.add_theme_constant_override("separation", 6)
	select_ui.add_child(row3)
	var btn_ed := Button.new()
	btn_ed.text = "Editor de piezas"
	btn_ed.custom_minimum_size = Vector2(125, 36)
	btn_ed.pressed.connect(_open_editor)
	row3.add_child(btn_ed)
	var btn_ab := Button.new()
	btn_ab.text = "Constructor"
	btn_ab.custom_minimum_size = Vector2(115, 36)
	btn_ab.tooltip_text = "Constructor de ejército personalizado"
	btn_ab.pressed.connect(_open_builder)
	row3.add_child(btn_ab)
	var btn_pos := Button.new()
	btn_pos.text = "Editor de posición"
	btn_pos.custom_minimum_size = Vector2(135, 36)
	btn_pos.pressed.connect(_open_pos_editor)
	row3.add_child(btn_pos)
	var btn_guide := Button.new()
	btn_guide.text = "Guía"
	btn_guide.custom_minimum_size = Vector2(70, 36)
	btn_guide.tooltip_text = "Aprende cada facción: ejército, reglas y patrones"
	btn_guide.pressed.connect(_open_guide)
	row3.add_child(btn_guide)
	var btn_load := Button.new()
	btn_load.text = "Cargar"
	btn_load.custom_minimum_size = Vector2(80, 36)
	btn_load.tooltip_text = "Cargar partida guardada"
	btn_load.disabled = not FileAccess.file_exists(
		SAVE_PATH)
	btn_load.pressed.connect(_load_game)
	row3.add_child(btn_load)

	# microinteracciones en los botones principales (hover + squash)
	for r in [row1, row2, row3]:
		for b in r.get_children():
			Juice.hover_pop(b)
			Juice.squash(b)
	# iconos procedurales en los botones principales (estilo Lucide)
	Icons.apply_icons({
		btn: "swords", btn_onl: "clock", btn_tut: "hint",
		btn_prof: "trophy", btn_daily: "bolt", btn_run: "flag",
		btn_puz: "puzzle", btn_draft: "clock", btn_ab: "gear",
		btn_guide: "book", btn_load: "back", btn_ed: "gear",
		btn_pos: "gear"}, self)

	# estadísticas y logros (línea dim al pie)
	var st := _lbl("")
	var parts := []
	parts.append("Partidas: %d" % int(stats.games))
	for fid in stats.wins:
		parts.append("%s: %dV" % [fid, stats.wins[fid]])
	# dominio por facción (XP): nivel = xp/100 + 1
	if stats.has("xp") and stats.xp.size() > 0:
		var lvls := []
		for fid in stats.xp:
			lvls.append("%s nv%d" % [fid, _faction_level(fid)])
		parts.append("Dominio: " + " · ".join(lvls))
	if stats.ach.size() > 0:
		var names := []
		for a in stats.ach: names.append(ACH.get(a, a))
		parts.append("Logros: " + ", ".join(names))
	st.text = " · ".join(parts)
	select_ui.add_child(st)
	_refresh_values()

## Pantalla "Jugar online" — pestañas propias (estilo lichess):
## Rápida / Salas / LAN / Ladder. El menú queda oculto (visible=false)
## para que los opt_* de configuración sigan vivos para el matchmaking.
func _open_online() -> void:
	editor_ui = Control.new()
	editor_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.visible = false
	add_child(editor_ui)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor_ui.add_child(cc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	cc.add_child(box)
	var title := _lbl("Jugar online")
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 300)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)

	# — Rápida: matchmaking por cola (preferencias = tu facción/equipo) —
	var t_q := VBoxContainer.new()
	t_q.name = "Rápida"
	tabs.add_child(t_q)
	var srv := HBoxContainer.new()
	t_q.add_child(srv)
	srv.add_child(_lbl("Servidor:"))
	ws_url = LineEdit.new()
	ws_url.text = _ws_last_addr
	ws_url.custom_minimum_size = Vector2(190, 0)
	ws_url.text_changed.connect(func(t): _ws_last_addr = t)
	srv.add_child(ws_url)
	ws_name = LineEdit.new()
	ws_name.placeholder_text = "Tu nick"
	ws_name.text = _ws_last_nick
	ws_name.text_changed.connect(func(t): _ws_last_nick = t)
	srv.add_child(ws_name)
	t_q.add_child(_lbl(
		"Cola automática: se empareja con tu facción, equipo y reloj."))
	var b_queue := Widgets.primary("Buscar rival", 44)
	b_queue.tooltip_text = "Matchmaking: cola automática (tu facción/equipo)"
	b_queue.pressed.connect(func():
		if ws != null and ws.get_ready_state() \
				== WebSocketPeer.STATE_OPEN:
			_ws_pending = "queue"
			_ws_send({"op": "queue", "name": ws_name.text.strip_edges(),
				"prefs": {
					"f": opt_p0.selected, "eq": opt_eq0.selected,
					"clock": opt_clock.selected,
					"mid": chk_midline.button_pressed}})
		else:
			ws = WebSocketPeer.new()
			if ws.connect_to_url(ws_url.text.strip_edges()) != OK:
				hud_alert("No se pudo conectar")
				return
			_ws_pending = "queue")
	t_q.add_child(b_queue)

	# — Salas: crear / entrar por código / reconexión —
	var t_r := VBoxContainer.new()
	t_r.name = "Salas"
	tabs.add_child(t_r)
	var rrow := HBoxContainer.new()
	t_r.add_child(rrow)
	rrow.add_child(_lbl("Código:"))
	ws_code = LineEdit.new()
	ws_code.placeholder_text = "ABCD"
	ws_code.custom_minimum_size = Vector2(90, 0)
	rrow.add_child(ws_code)
	var b_ws_host := Button.new()
	b_ws_host.text = "Crear sala"
	b_ws_host.tooltip_text = "Crear sala online en el servidor"
	b_ws_host.pressed.connect(func(): _ws_connect(true))
	rrow.add_child(b_ws_host)
	var b_ws_join := Button.new()
	b_ws_join.text = "Entrar"
	b_ws_join.tooltip_text = "Unirse a una sala por código"
	b_ws_join.pressed.connect(func(): _ws_connect(false))
	rrow.add_child(b_ws_join)
	t_r.add_child(_lbl(
		"El creador comparte el código. " +
		"Sin código y con sala previa, «Entrar» intenta reconectar."))

	# — LAN: ENet directo por IP/puerto —
	var t_l := VBoxContainer.new()
	t_l.name = "LAN"
	tabs.add_child(t_l)
	var lrow := HBoxContainer.new()
	t_l.add_child(lrow)
	lrow.add_child(_lbl("IP:"))
	net_ip = LineEdit.new()
	net_ip.placeholder_text = "127.0.0.1"
	net_ip.custom_minimum_size = Vector2(140, 0)
	lrow.add_child(net_ip)
	lrow.add_child(_lbl("Puerto:"))
	net_port = LineEdit.new()
	net_port.text = "7777"
	net_port.custom_minimum_size = Vector2(70, 0)
	lrow.add_child(net_port)
	var b_host := Button.new()
	b_host.text = "Crear partida"
	b_host.pressed.connect(_host_game)
	lrow.add_child(b_host)
	var b_join := Button.new()
	b_join.text = "Unirse"
	b_join.pressed.connect(_join_game)
	lrow.add_child(b_join)
	t_l.add_child(_lbl(
		"Conexión directa punto a punto — el host juega como J1."))

	# — Ladder: clasificación ELO del servidor —
	var t_d := VBoxContainer.new()
	t_d.name = "Ladder"
	tabs.add_child(t_d)
	var b_ladder := Button.new()
	b_ladder.text = "Ver clasificación"
	b_ladder.tooltip_text = "Clasificación ELO del servidor"
	t_d.add_child(b_ladder)
	var lad_lbl := Label.new()
	lad_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	t_d.add_child(lad_lbl)
	b_ladder.pressed.connect(func():
		lad_lbl.text = "…"
		if ws == null or ws.get_ready_state() \
				!= WebSocketPeer.STATE_OPEN:
			ws = WebSocketPeer.new()
			if ws.connect_to_url(ws_url.text.strip_edges()) != OK:
				lad_lbl.text = "No se pudo conectar"
				return
			_ws_pending = "ladder"
		else:
			_ws_send({"op": "ladder"}))
	_ladder_label = lad_lbl
	_add_back()

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

func _ws_connect(create: bool) -> void:
	# si ya tenemos sala+token y no se pide crear, es una reconexión
	var rejoin := not create and ws_room != "" \
		and ws_code.text.strip_edges() == ""
	ws = WebSocketPeer.new()
	var url := ws_url.text.strip_edges()
	if ws.connect_to_url(url) != OK:
		hud_alert("No se pudo conectar a %s" % url)
		return
	_ws_pending = "create" if create \
		else ("rejoin" if rejoin else "join")

var _ws_pending := ""
var _ws_cfg := {}          # última cfg aplicada (para resync sin cfg)

func _ws_send(msg: Dictionary) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

func _ws_poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not ws_open:
		ws_open = true
		if _ws_pending == "create":
			_ws_send({"op": "create", "cfg": _game_cfg(),
				"name": ws_name.text.strip_edges()})
		elif _ws_pending == "join":
			_ws_send({"op": "join", "code": ws_code.text.strip_edges(),
				"name": ws_name.text.strip_edges()})
		elif _ws_pending == "rejoin":
			_ws_send({"op": "rejoin", "code": ws_room,
				"side": ws_side, "token": ws_token})
		elif _ws_pending == "ladder":
			_ws_send({"op": "ladder"})
		elif _ws_pending == "queue":
			# matchmaking: envío mis preferencias, el server empareja
			var prefs := {
				"f": opt_p0.selected, "eq": opt_eq0.selected,
				"clock": opt_clock.selected,
				"mid": chk_midline.button_pressed}
			# ejército custom: las filas viajan (el rival no tiene
			# mi archivo local)
			if opt_eq0.selected >= 2:
				var cf: Dictionary = factions[opt_p0.selected]
				if cf.setups.size() > opt_eq0.selected:
					prefs["rows"] = cf.setups[opt_eq0.selected]
			_ws_send({"op": "queue", "name": ws_name.text.strip_edges(),
				"prefs": prefs})
		_ws_pending = ""
	elif st == WebSocketPeer.STATE_CLOSED and ws_open:
		ws_open = false
		hud_alert("Conexión perdida — usa Entrar con el mismo código")
	while ws.get_ready_state() == WebSocketPeer.STATE_OPEN \
			and ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(
			ws.get_packet().get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY:
			_ws_dispatch(msg)

func _ws_dispatch(m: Dictionary) -> void:
	match str(m.get("op", "")):
		"hello":
			# el árbitro Godot saluda → modo autoritativo
			ws_auth = true
			if board != null: board.defer_play = true
		"queued":
			hud_alert("Buscando rival… (%d en cola)" % int(m.get("n", 1)))
		"dequeued":
			hud_alert("Cola abandonada")
		"room":
			ws_room = str(m.code)
			ws_token = str(m.token)
			ws_side = int(m.side)
			online = true
			my_net = ws_side
			if ws_side == 1 and m.has("cfg"):
				_apply_cfg(m.cfg)
				_start_game()
			elif ws_side == 0 and m.has("cfg"):
				# matchmaking: la cfg llega fusionada a ambos lados
				_apply_cfg(m.cfg)
			else:
				hud_alert("Sala %s — esperando rival. Comparte el código."
					% ws_room)
		"start":
			if ws_side == 0 and tm == null:
				_start_game()
		"move":
			var mv: Dictionary = NetCodec.dec(m.mv)
			if mv.get("resign", false):
				tm.resign(int(mv.get("side", 1 - ws_side)))
			elif mv.get("draw", false):
				tm.agree_draw()   # tablas declaradas por el rival
			else:
				tm.play(mv)  # eco autoritativo (también del propio)
		"resync":
			_ws_resync(m)
		"offline":
			if hud_info:
				hud_info.text += "\n%s" % \
					("Rival desconectado" if m.on else "Rival reconectado")
		"over":
			if tm != null and not tm.over:
				tm.over = true
				# con servidor autoritativo el ganador viene explícito
				tm.winner = int(m.get("winner", ws_side))
				tm.game_over.emit(tm.winner)
		"chat":
			_chat_log("[rival] " + str(m.text).left(200))
		"rating":
			# ELO actualizado tras la partida
			var lines := []
			for n in m.you.keys():
				var r: Dictionary = m.you[n]
				lines.append("%s: %d (%dV)" % [
					n, int(r.elo), int(r.wins)])
			if hud_info: hud_info.text += "\nELO — " + " · ".join(lines)
		"ladder":
			var txt := ""
			for r in m.rows:
				txt += "%s  %d  (%d partidas)\n" % [
					r.name, int(r.elo), int(r.games)]
			if is_instance_valid(_ladder_label):
				_ladder_label.text = \
					txt.strip_edges() if txt != "" else "Sin datos"
			else:
				hud_alert(txt.strip_edges())
		"err":
			hud_alert("Servidor: " + str(m.msg))

func _apply_cfg(cfg: Dictionary) -> void:
	_ws_cfg = cfg   # memorizada para reconstruir en resync
	opt_p0.select(int(cfg.f0)); opt_eq0.select(int(cfg.eq0))
	opt_p1.select(int(cfg.f1)); opt_eq1.select(int(cfg.eq1))
	# inyectar filas custom recibidas como setups[2] (eq Personalizado)
	for si in [0, 1]:
		if cfg.has("rows%d" % si):
			var fac: Dictionary = factions[int(cfg["f%d" % si])]
			if fac.setups.size() > 2: fac.setups[2] = cfg["rows%d" % si]
			else: fac.setups.append(cfg["rows%d" % si])
	chk_midline.button_pressed = bool(cfg.mid)
	# stall: activar el check + volcar el valor, si no el cliente
	# jugaría con su propio límite y divergiría del host
	var stall: int = int(cfg.get("stall", 0))
	chk_stall.button_pressed = stall > 0
	if stall > 0:
		stall_spin.value = stall
	opt_clock.select(int(cfg.clock))
	ai_player = -1

## Reconstruye la partida reproduciendo el historial del servidor.
func _ws_resync(m: Dictionary) -> void:
	_over_handled = false   # el resync puede abrir una partida nueva
	# el relay Python no adjunta cfg en resync (llegó en 'room'); el
	# servidor autoritativo sí — solo aplicar/reconstruir si viene
	var c: Dictionary = m.get("cfg", {})
	if not c.is_empty(): _apply_cfg(c)
	# reconstruir siempre desde cero: replay sobre un tm existente
	# duplicaría jugadas; sin cfg en el mensaje usar la memorizada
	var c2: Dictionary = c if not c.is_empty() else _ws_cfg
	ai_player = -1
	var from_ply := 0
	if not c2.is_empty():
		# cfg completa: reconstruir desde cero y retraer TODO el historial
		tm = TurnManager.new(factions[int(c2.f0)], int(c2.eq0),
			factions[int(c2.f1)], int(c2.eq1),
			{"midline": bool(c2.mid),
				"stall_limit": int(c2.stall),
				"clock_secs": CLOCK_CHOICES[int(c2.clock)][0],
				"clock_inc": CLOCK_CHOICES[int(c2.clock)][1]})
	elif tm != null:
		# sin cfg no conocemos el despliegue inicial (p.ej. draft) —
		# no se puede reconstruir; aplicar solo la cola que falta
		from_ply = tm.log.size()
	else:
		return   # sin cfg ni partida previa — nada que resincronizar
	for i in range(from_ply, m.moves.size()):
		var mv: Dictionary = NetCodec.dec(m.moves[i])
		if mv.get("resign", false):
			# el lado que se rindió viaja en el mv (host autoritativo);
			# en relay sin 'side' solo cabe asumir que fue el rival
			tm.resign(int(mv.get("side", 1 - ws_side)))
		elif mv.get("draw", false):
			tm.agree_draw()
		else:
			tm.play(mv)
	if game_ui == null:
		menu_root.queue_free()
		_build_game()
		# si la partida ya terminó durante el replay, la señal
		# game_over disparó antes de conectarla — disparar a mano
		if tm.over and not _over_handled:
			_over_handled = true
			_on_game_over(tm.winner)
	else:
		# board quedaba apuntando al TurnManager viejo — reasignar
		# estado mutable y reconectar señales del tm nuevo
		board.bind(tm)   # reasigna tm y reconecta sus señales
		board.selected = Vector2i(-1, -1)
		board.legal = []
		board.premove = {}
		board.pre_sel = Vector2i(-1, -1)
		board.flipped = (my_net == 1)
		_wire_tm()
		board.queue_redraw()
		_update_hud()

## Conecta las señales del TurnManager con sonido/HUD/juice.
## Separada porque _ws_resync puede sustituir el tm en caliente.
func _wire_tm() -> void:
	if not tm.move_made.is_connected(_on_move_sound):
		tm.move_made.connect(_on_move_sound)
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

## Panel de perfil: estadísticas agregadas, logros y récords
## (equivalente al /perfil de lichess, versión local).
func _open_profile() -> void:
	menu_root.queue_free()
	editor_ui = Widgets.screen("Perfil", 560)
	add_child(editor_ui)
	var box := Widgets.screen_body(editor_ui)

	# — global —
	var g: int = int(stats.get("games", 0))
	var w: int = int(stats.get("w", 0))
	var l: int = int(stats.get("l", 0))
	var d: int = int(stats.get("d", 0))
	var played := w + l + d
	box.add_child(Widgets.heading("General"))
	box.add_child(_lbl(
		"Partidas: %d   ·   %dV %dE %dD   ·   %d%% de victorias" % [
			g, w, d, l, int(100.0 * w / maxi(played, 1))]))

	# — por facción: winrate + dominio (nivel XP) —
	var fstat: Dictionary = stats.get("fstat", {})
	if not fstat.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(Widgets.heading("Por facción"))
		var fav := ""; var fav_g := 0
		var eff := ""; var eff_wr := -1.0
		for fid in fstat:
			var fs: Dictionary = fstat[fid]
			var wr := 100.0 * int(fs.w) / maxi(int(fs.g), 1)
			box.add_child(_lbl("  %s  nv%d  —  %d partidas, %d%% victorias" % [
				fid.capitalize(), _faction_level(fid), int(fs.g), int(wr)]))
			if int(fs.g) > fav_g: fav = fid; fav_g = int(fs.g)
			if int(fs.g) >= 3 and wr > eff_wr: eff = fid; eff_wr = wr
		var extra := "  Favorita: %s" % fav.capitalize()
		if eff != "": extra += "   ·   Más efectiva: %s" % eff.capitalize()
		box.add_child(_lbl(extra))

	# — historial reciente —
	var hist: Array = stats.get("history", [])
	if not hist.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(Widgets.heading("Últimas partidas"))
		var marks := {"V": "✔", "E": "½", "D": "✘"}
		var n := mini(8, hist.size())
		for i in range(hist.size() - n, hist.size()):
			var h: Dictionary = hist[i]
			box.add_child(_lbl("  %s  %s vs %s — %d jugadas (%s)" % [
				marks.get(h.r, "?"), String(h.me).capitalize(),
				String(h.vs).capitalize(), int(h.mv), h.mode]))

	# — récords —
	box.add_child(HSeparator.new())
	box.add_child(Widgets.heading("Récords"))
	var recs := []
	if int(stats.get("rec_fast", 0)) > 0:
		recs.append("Victoria más rápida: %d jugadas" % int(stats.rec_fast))
	if int(stats.get("rec_long", 0)) > 0:
		recs.append("Partida más larga: %d jugadas" % int(stats.rec_long))
	if int(stats.get("run_best", 0)) > 0:
		recs.append("Mejor racha Run: nivel %d" % int(stats.run_best))
	box.add_child(_lbl("  ".join(recs) if not recs.is_empty()
		else "Sin récords todavía."))

	# — logros —
	var ach: Array = stats.get("ach", [])
	box.add_child(HSeparator.new())
	box.add_child(Widgets.heading("Logros"))
	if ach.is_empty():
		box.add_child(_lbl("Ninguno aún — gana tu primera partida."))
	else:
		for a in ach:
			box.add_child(_lbl("  🏆 " + str(ACH.get(a, a))))
	var b := Widgets.secondary("Volver")
	b.pressed.connect(_close_editor)
	box.add_child(b)

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
					_beep(880.0, 0.08)
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

## SFX por tipo de jugada (mini-pack sintetizado estilo lichess):
## captura = golpe grave+ruido, especial = trino, castillo = doble tono,
## push/attract = barrido, normal = click.
func _on_move_sound(mv: Dictionary) -> void:
	if muted: return
	if mv.get("captures", []).size() > 0:
		_beep(180.0, 0.07); _beep(90.0, 0.12); return
	if mv.has("castle") or mv.has("second"):
		_beep(392.0, 0.07); _beep(523.0, 0.10); return
	if mv.has("push") or mv.has("attract") \
			or mv.get("immobilize", []).size() > 0:
		_sweep(300.0, 620.0, 0.10); return
	_beep(440.0, 0.07)

func _beep(freq: float, dur := 0.1) -> void:
	if muted: return
	_ensure_sfx()
	var pb: AudioStreamGeneratorPlayback = sfx.get_stream_playback()
	var rate := 22050.0
	var frames := int(dur * rate)
	for i in frames:
		var t := float(i) / rate
		var env := 1.0 - t / dur
		pb.push_frame(Vector2(sin(TAU * freq * t) * env,
			sin(TAU * freq * t) * env))

## Barrido de frecuencia (push/atract/inmovilizar).
func _sweep(f0: float, f1: float, dur := 0.1) -> void:
	if muted: return
	_ensure_sfx()
	var pb: AudioStreamGeneratorPlayback = sfx.get_stream_playback()
	var rate := 22050.0
	var frames := int(dur * rate)
	var phase := 0.0
	for i in frames:
		var k := float(i) / frames
		var freq := lerpf(f0, f1, k)
		phase += TAU * freq / rate
		pb.push_frame(Vector2(sin(phase) * (1.0 - k),
			sin(phase) * (1.0 - k)))

func _ensure_sfx() -> void:
	if sfx != null: return
	sfx = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	sfx.stream = gen
	sfx.volume_db = -14.0
	add_child(sfx)
	sfx.play()

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
		_beep(523.0, 0.12); _beep(659.0, 0.12); _beep(784.0, 0.18)
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
	_end_modal(w, resumen)

## Panel de fin de partida (estilo chess.com): overlay + resumen +
## análisis + revancha.
func _end_modal(w: int, resumen: String) -> void:
	hud_info.text = resumen
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_ui.add_child(overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	cc.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := _lbl("¡Tablas!" if w < 0 else \
		"¡Ganan %s!" % tm.state.factions[w].name)
	title.add_theme_font_size_override("font_size", 30)
	if w >= 0:
		title.add_theme_color_override("font_color",
			tm.state.factions[w].color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var res := _lbl(resumen)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(res)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var b_re := Button.new()
	b_re.text = "Revancha"
	b_re.pressed.connect(_rematch)
	row.add_child(b_re)
	var b_close := Button.new()
	b_close.text = "Ver tablero"
	b_close.pressed.connect(func():
		Juice.fade_out(overlay, 0.2))
	row.add_child(b_close)
	Juice.pop_in(panel)

## Análisis post-partida (estilo lichess): evalúa cada posición del
## replay y reporta los errores más grandes de cada jugador.
func _postgame_analysis() -> String:
	var snaps: Array = tm._replay_pos
	if snaps.size() < 2: return ""
	var evals := []
	var bs := BoardState.new()
	bs.factions = tm.state.factions
	for snap in snaps:
		bs.restore(snap)
		evals.append(BeliberBot.evaluate(bs, 0))
	var worst := {0: {"d": 0, "i": -1}, 1: {"d": 0, "i": -1}}
	var best := {0: {"d": 0, "i": -1}, 1: {"d": 0, "i": -1}}
	var loss := {0: 0.0, 1: 0.0}
	var moves_n := {0: 0, 1: 0}
	var decisive_i := -1
	var decisive_swing := 0.0
	for i in mini(tm.log.size(), tm.history.size()):
		# en partida cargada history está vacío pero log conserva las
		# jugadas pasadas — sin el límite esto indexaba fuera de rango
		if i + 1 >= evals.size(): break
		var mover: int = int(tm.history[i].current)
		var d: float = evals[i + 1] - evals[i]
		if mover == 1: d = -d   # delta desde la perspectiva del que mueve
		if d < worst[mover].d: worst[mover] = {"d": d, "i": i}
		if d > best[mover].d: best[mover] = {"d": d, "i": i}
		if d < 0: loss[mover] += -d
		moves_n[mover] += 1
		# momento decisivo: el mayor cambio absoluto de evaluación
		if absf(d) > decisive_swing:
			decisive_swing = absf(d); decisive_i = i
	var lines := []
	# precisión aproximada: 100% menos el error medio por jugada
	var acc := []
	for pl in [0, 1]:
		var avg: float = loss[pl] / maxi(int(moves_n[pl]), 1)
		acc.append(int(clampf(100.0 - avg * 2.0, 5.0, 100.0)))
	lines.append("Precisión (aprox): J1 %d%% · J2 %d%%" % [acc[0], acc[1]])
	for pl in [0, 1]:
		var bst: Dictionary = best[pl]
		if int(bst.i) >= 0 and float(bst.d) > 30:
			lines.append("Mejor J%d en jugada %d: %s (+%d)" % [
				pl + 1, int(bst.i) + 1,
				tm.log[int(bst.i)].get_slice(" ", 1), int(bst.d)])
	for pl in [0, 1]:
		var w: Dictionary = worst[pl]
		if int(w.i) >= 0 and float(w.d) < -30:
			lines.append("Error J%d en jugada %d: %s (perdió %d)" % [
				pl + 1, int(w.i) + 1,
				tm.log[int(w.i)].get_slice(" ", 1), int(-w.d)])
	if decisive_i >= 0 and decisive_swing > 40:
		lines.append("Momento decisivo: jugada %d (%s, swing %d)" % [
			decisive_i + 1, tm.log[decisive_i].get_slice(" ", 1),
			int(decisive_swing)])
	if lines.size() <= 1:
		lines.append("Sin errores graves detectados.")
	return "Análisis: " + "\n".join(lines)

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

