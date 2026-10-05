class_name GameHUD
extends RefCounted

## Construcción de la UI de partida: tablero + eval bar + panel
## lateral con pestañas (Partida / Opciones / Chat).
## Los controles quedan en el controlador raíz (app) porque el resto
## del código los usa para actualizar el HUD cada jugada.

static func build(app) -> void:
	# reset del estado del historial: sin esto una partida cargada
	# con el mismo nº de plies que la anterior saltaba el rebuild
	# (lista vacía) y las marcas !/? heredadas eran de la otra partida
	app._log_n = -1
	app._move_marks = []
	app._tts_log_n = 0   # re-anunciar la 1ª jugada de la nueva partida
	app.game_ui = BoxContainer.new()     # vertical flag → layout adaptable
	app.game_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.add_child(app.game_ui)
	var tm: TurnManager = app.tm

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app.game_ui.add_child(center)
	# barra de evaluación vertical junto al tablero (estilo lichess)
	var board_row := HBoxContainer.new()
	app.eval_bar = EvalBar.new()
	app.eval_bar.col0 = tm.state.factions[0].color
	app.eval_bar.col1 = tm.state.factions[1].color
	app.eval_bar.tooltip_text = Lang.t("HUD_EVAL_TIP")
	# estira a la altura del tablero (antes alto fijo 512 — con el
	# tablero escalado quedaban desalineados)
	app.eval_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_row.add_child(app.eval_bar)
	center.add_child(board_row)
	app.board = BoardView.new(tm)
	app.board.premove_enabled = app.ai_player >= 0
	app.board.human_idx = 0
	app.board.net_me = 9 if app.ai_both else app.my_net   # IA vs IA = espectador
	app.board.defer_play = app.ws_auth   # árbitro: solo emite intención
	# el invitado online siempre ve su bando abajo
	if app.online and app.my_net == 1: app.board.flipped = true
	app.board.move_played.connect(func(mv):
		if not app.online: return
		if app.ws != null:
			if app.ws_auth:
				# servidor autoritativo: solo intención from→to;
				# second_to desambigua las cadenas (Tritón)
				var pm := {"op": "play",
					"from": NetCodec.enc(mv.from),
					"to": NetCodec.enc(mv.to)}
				if mv.has("second"):
					pm["second_to"] = NetCodec.enc(mv.second.to)
				app._ws_send(pm)
			else:
				app._ws_send({"op": "move", "mv": NetCodec.enc(mv)})
		else:
			app._rpc_move.rpc(mv))
	board_row.add_child(app.board)

	# margen inferior: el botón Zen (último hijo) quedaba pegado al
	# borde de la ventana en 800px de alto
	var side_m := MarginContainer.new()
	side_m.add_theme_constant_override("margin_bottom", 8)
	app.game_ui.add_child(side_m)
	# scroll: en modo compacto (<950px) el panel va debajo del
	# tablero y su contenido puede superar el alto de la ventana;
	# follow_focus además hace visible el control al navegar con Tab
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.follow_focus = true
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# el mínimo vive en el scroll (el de un ScrollContainer no
	# propaga el de sus hijos); el propio scroll estira el VBox al
	# alto visible cuando cabe y activa la barra cuando no
	side_scroll.custom_minimum_size = Vector2(300, 0)
	side_m.add_child(side_scroll)
	app._side_scroll = side_scroll
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app.side_panel = side
	side.name = "SideVBox"
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)
	# tarjeta del rival (emblema + faccion, estilo chess.com)
	var rc := HBoxContainer.new()
	side.add_child(rc)
	app.hud_rival_icon = FactionIcon.new("", Color.WHITE, 30)
	rc.add_child(app.hud_rival_icon)
	app.hud_rival = Label.new()
	app.hud_rival.add_theme_font_size_override("font_size", 18)
	rc.add_child(app.hud_rival)
	# checklist del tutorial (walkthrough estilo Root): en tarjeta
	# propia para separarlo visualmente del bloque de pestañas
	if app.tutorial:
		var tut_card := PanelContainer.new()
		side.add_child(tut_card)
		app.tut_box = VBoxContainer.new()
		tut_card.add_child(app.tut_box)
		app.tut_box.add_child(Widgets.lbl(Lang.t("TUT_GOALS")))
		for s in app.tut_steps:
			var l := Widgets.lbl("• " + s.t)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.add_theme_font_size_override("font_size", 13)
			app.tut_box.add_child(l)
	# pestanas: Partida / Opciones / Chat (panel estilo lichess)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(tabs)
	var tab_game := VBoxContainer.new()
	tab_game.name = Lang.t("TAB_GAME")
	tabs.add_child(tab_game)
	var tab_opts := VBoxContainer.new()
	tab_opts.name = Lang.t("TAB_OPTIONS")
	tabs.add_child(tab_opts)
	var tab_chat := VBoxContainer.new()
	tab_chat.name = Lang.t("TAB_CHAT")
	tabs.add_child(tab_chat)
	var tg := tab_game
	var opts := tab_opts

	app.hud_turn = Label.new()
	app.hud_turn.add_theme_font_size_override("font_size", 28)
	tg.add_child(app.hud_turn)
	app.hud_clock = Label.new()
	app.hud_clock.add_theme_font_size_override("font_size", 20)
	tg.add_child(app.hud_clock)
	app.hud_eval = Label.new()
	app.hud_eval.add_theme_font_size_override("font_size", 16)
	app.hud_eval.tooltip_text = Lang.t("HUD_EVAL_TIP")
	tg.add_child(app.hud_eval)
	app.hud_opening = Label.new()
	app.hud_opening.add_theme_font_size_override("font_size", 13)
	app.hud_opening.add_theme_color_override("font_color",
		BeliberTheme.dim())
	# el nombre combinado "Apertura — Elfos: … · Humenex: …" se
	# cortaba en el borde del panel de 300px
	app.hud_opening.autowrap_mode = TextServer.AUTOWRAP_WORD
	tg.add_child(app.hud_opening)
	app.hud_info = Label.new()
	app.hud_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	tg.add_child(app.hud_info)
	# las marcas/flechas de análisis (clic/arrastre derecho) eran un
	# gesto indescubrible — una línea dim lo hace explícito
	var marks_hint := Widgets.lbl(Lang.t("HUD_MARKS_HINT"), 0, true)
	marks_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tg.add_child(marks_hint)
	# bandejas de capturadas — sección colapsable (clic en el toggle
	# oculta/muestra; estilo panel lichess)
	var cap_t := CheckButton.new()
	cap_t.text = Lang.t("HUD_CAPTURES")
	cap_t.button_pressed = true
	tg.add_child(cap_t)
	var cap_box := VBoxContainer.new()
	tg.add_child(cap_box)
	cap_t.toggled.connect(func(on): cap_box.visible = on)
	var tr0 := HBoxContainer.new()
	tr0.add_child(Widgets.lbl("J1 ▸"))
	app.tray0 = CapturedTray.new()
	app.tray0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr0.add_child(app.tray0)
	cap_box.add_child(tr0)
	var tr1 := HBoxContainer.new()
	tr1.add_child(Widgets.lbl("J2 ▸"))
	app.tray1 = CapturedTray.new()
	app.tray1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr1.add_child(app.tray1)
	cap_box.add_child(tr1)
	# historial de movimientos — sección colapsable propia
	var mv_t := CheckButton.new()
	mv_t.text = Lang.t("HUD_MOVES")
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
	app.move_list = VBoxContainer.new()
	app.move_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(app.move_list)
	app.hud_log = Label.new()
	app.hud_log.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab_chat.add_child(app.hud_log)
	# ===== Partida =====
	_opts_sec(opts, "TAB_GAME")
	app.btn_cov = CheckButton.new()
	# también marca destinos MOVER — es influencia, no solo amenaza
	app.btn_cov.text = Lang.t("HUD_INFLUENCE")
	app.btn_cov.toggled.connect(func(on):
		app.board.show_coverage = on; app.board.queue_redraw())
	# flow: el panel lateral mide ~300px y 4 botones en una fila
	# fija cortaban "Guardar" en ventanas de 800px
	var btn_row := HFlowContainer.new()
	opts.add_child(btn_row)
	var b_undo := Button.new()
	b_undo.text = Lang.t("HUD_UNDO")
	b_undo.pressed.connect(func():
		# online desincronizaría; tras el fin, undo resucitaría la
		# partida (las terminaciones no están en history)
		if app.online or app.tm.over or app.ai_both: return
		if app.tm.undo():
			# vs IA: deshacer solo tu jugada devolvía el turno al bot
			# (re-roll gratis de sus blunders) — hay que deshacer el par
			if app.ai_player >= 0 and not app.coop \
					and app.tm.current == app.ai_player:
				app.tm.undo()
			# premove obsoleto: la posición cambió, se ejecutaría mal
			app.board.premove = {}
			app.board.pre_sel = Vector2i(-1, -1)
			app.board.queue_redraw(); app._update_hud())
	btn_row.add_child(b_undo)
	var b_resign := Widgets.danger(Lang.t("HUD_RESIGN"))
	b_resign.pressed.connect(func():
		# IA-vs-IA: el espectador no puede rendir a los bots; ni hay
		# partida que abandonar si tm no existe (diálogo huérfano)
		if app.tm == null or app.tm.over or app.ai_both: return
		# diálogo de confirmación (estilo ProperUI Modal)
		var dlg := ConfirmationDialog.new()
		dlg.title = Lang.t("HUD_RESIGN")
		dlg.dialog_text = Lang.t("DLG_RESIGN_CONFIRM")
		dlg.ok_button_text = Lang.t("HUD_RESIGN")
		dlg.cancel_button_text = Lang.t("DLG_KEEP_PLAYING")
		app.add_child(dlg)
		dlg.confirmed.connect(func():
			# la partida pudo terminar con el diálogo abierto
			if app.tm == null or app.tm.over: return
			var me: int = app.tm.current if not app.online else app.my_net
			app._do_resign(me))
		# también al confirmar: quedaba oculto colgado de app
		dlg.confirmed.connect(dlg.queue_free)
		dlg.canceled.connect(dlg.queue_free)
		dlg.popup_centered())
	btn_row.add_child(b_resign)
	var b_draw := Button.new()
	b_draw.text = Lang.t("HUD_DRAW_OFFER") if app.online \
		else Lang.t("HUD_DRAW")
	# online ahora es oferta→aceptar/rechazar real, no tablas
	# unilaterales: el rival decide con un diálogo
	b_draw.pressed.connect(app._offer_draw)
	btn_row.add_child(b_draw)
	var b_save := Button.new()
	b_save.text = Lang.t("HUD_SAVE")
	b_save.pressed.connect(func():
		# una partida online/run se recarga como hotseat local — fork
		# silencioso (y un reloj a 0 flaggeaba al instante)
		if app.online or app.run_active:
			app.hud_alert(Lang.t("HUD_SAVE_LOCAL"))
			return
		StatsStore.atomic_write(app.SAVE_PATH,
			JSON.stringify(app.tm.save_game()))
		app.hud_alert(Lang.t("HUD_SAVED")))
	btn_row.add_child(b_save)
	var btn := Button.new()
	btn.text = Lang.t("HUD_NEW_GAME")
	btn.pressed.connect(app._restart)
	opts.add_child(btn)

	# ===== Tablero =====
	_opts_sec(opts, "OPT_SEC_BOARD")
	var btn_row2 := HFlowContainer.new()
	opts.add_child(btn_row2)
	var b_flip := Button.new()
	b_flip.text = Lang.t("HUD_FLIP")
	b_flip.pressed.connect(func():
		app.board.flipped = not app.board.flipped
		app.board.queue_redraw())
	btn_row2.add_child(b_flip)
	var b_theme := Button.new()
	b_theme.text = Lang.t("HUD_THEME")
	b_theme.pressed.connect(func():
		app.board.theme_i = (app.board.theme_i + 1) \
			% BoardView.THEMES.size()
		app.board.queue_redraw(); app._save_settings())
	btn_row2.add_child(b_theme)
	btn_row2.add_child(app.btn_cov)
	var btn_row3 := HFlowContainer.new()
	opts.add_child(btn_row3)
	var b_thr := CheckButton.new()
	b_thr.text = Lang.t("HUD_THREATS")
	b_thr.toggled.connect(func(on):
		app.board.show_threats = on; app.board.queue_redraw()
		app._save_settings())
	btn_row3.add_child(b_thr)
	var b_coords := CheckButton.new()
	b_coords.text = Lang.t("HUD_COORDS")
	b_coords.button_pressed = true
	b_coords.toggled.connect(func(on):
		app.board.show_coords = on; app.board.queue_redraw()
		app._save_settings())
	btn_row3.add_child(b_coords)
	var b_blind := CheckButton.new()
	b_blind.text = Lang.t("HUD_BLIND")
	b_blind.tooltip_text = Lang.t("HUD_BLIND_TIP")
	b_blind.toggled.connect(func(on):
		app.board.blindfold = on; app.board.queue_redraw()
		app._save_settings())
	btn_row3.add_child(b_blind)
	var btn_row4 := HBoxContainer.new()
	opts.add_child(btn_row4)
	var b_prev := Button.new()
	b_prev.text = "◀"
	b_prev.pressed.connect(func():
		if app.board.view_i < 0:
			app.board.view_i = app.tm.replay_len() - 1
		else:
			app.board.view_i = maxi(0, app.board.view_i - 1)
		app.board.queue_redraw())
	btn_row4.add_child(b_prev)
	var b_next := Button.new()
	b_next.text = "▶"
	b_next.pressed.connect(func():
		if app.board.view_i < 0: return
		app.board.view_i += 1
		if app.board.view_i >= app.tm.replay_len(): app.board.view_i = -1
		app.board.queue_redraw())
	btn_row4.add_child(b_next)
	var b_live := Button.new()
	b_live.text = Lang.t("HUD_LIVE")
	b_live.pressed.connect(func():
		app.board.view_i = -1; app.board.queue_redraw())
	btn_row4.add_child(b_live)
	# zoom + velocidad de animación
	var btn_row5 := HBoxContainer.new()
	opts.add_child(btn_row5)
	btn_row5.add_child(Widgets.lbl("Zoom"))
	var zoom := HSlider.new()
	zoom.min_value = 0.7; zoom.max_value = 1.4
	zoom.step = 0.05
	# reflejar el zoom cargado (antes arrancaba en 1.0 aunque el
	# ajuste guardado fuese otro — el slider mentía). zoom_v es la
	# intención del usuario; la escala real puede ser menor si la
	# ventana no da para el tablero (auto-encaje en _process)
	zoom.set_value_no_signal(app.zoom_v)
	zoom.custom_minimum_size = Vector2(90, 0)
	zoom.value_changed.connect(func(v):
		app.zoom_v = v
		app._apply_zoom()
		app._save_settings())
	btn_row5.add_child(zoom)
	var opt_anim := OptionButton.new()
	for t in [Lang.t("ANIM_SLOW"), Lang.t("ANIM_NORMAL"),
			Lang.t("ANIM_FAST"), Lang.t("ANIM_OFF")]:
		opt_anim.add_item(t)
	# seleccionar el valor cargado, no siempre "normal"
	var adurs := [0.35, 0.18, 0.08, 0.001]
	var best := 1
	for i in adurs.size():
		if absf(adurs[i] - app.board.anim_dur) \
				< absf(adurs[best] - app.board.anim_dur):
			best = i
	opt_anim.select(best)
	opt_anim.item_selected.connect(func(i):
		app.board.anim_dur = [0.35, 0.18, 0.08, 0.001][i]
		app._save_settings())
	btn_row5.add_child(opt_anim)

	# ===== Jugada =====
	_opts_sec(opts, "OPT_SEC_MOVE")
	# entrada por teclado: "e2e4" o "e2 e4"
	var key_row := HBoxContainer.new()
	opts.add_child(key_row)
	var inp := LineEdit.new()
	inp.placeholder_text = "e2e4"
	inp.tooltip_text = Lang.t("HUD_MOVE_TIP")
	inp.custom_minimum_size = Vector2(80, 0)
	key_row.add_child(inp)
	var b_go := Button.new()
	b_go.text = Lang.t("HUD_MOVE")
	var do_key_move := func():
		var txt: String = inp.text.strip_edges().to_lower() \
			.replace(" ", "")
		inp.text = ""
		if txt.length() != 4: return
		var frm := Vector2i(txt.unicode_at(0) - 97,
			8 - int(txt.unicode_at(1) - 48))
		var to := Vector2i(txt.unicode_at(2) - 97,
			8 - int(txt.unicode_at(3) - 48))
		if not BoardState.inside(frm) or not BoardState.inside(to): return
		for mv in app.tm.legal_moves(frm):
			if mv.to == to:
				# commit() respeta defer_play/emite move_played → la
				# jugada se sincroniza online igual que con el ratón
				app.board.commit(mv); return
		# sin legal y fuera de turno → premove (paridad con el ratón:
		# solo vs IA, que es cuando premove_enabled está activo)
		if app.board.premove_enabled \
				and app.tm.current != app.board.human_idx:
			var ph: Variant = app.tm.state.at(frm)
			if ph != null and ph.owner == app.board.human_idx:
				app.board.premove = {"from": frm, "to": to}
				app.board.queue_redraw()
	b_go.pressed.connect(do_key_move)
	inp.text_submitted.connect(func(_t): do_key_move.call())
	key_row.add_child(b_go)
	var b_hint := Button.new()
	b_hint.text = Lang.t("HUD_HINT")
	b_hint.pressed.connect(app._suggest)
	key_row.add_child(b_hint)
	var btn_row6 := HBoxContainer.new()
	opts.add_child(btn_row6)
	var b_conf := CheckButton.new()
	b_conf.text = Lang.t("HUD_CONFIRM")
	b_conf.tooltip_text = Lang.t("HUD_CONFIRM_TIP")
	b_conf.toggled.connect(func(on):
		app.board.confirm_moves = on; app._save_settings())
	btn_row6.add_child(b_conf)

	# ===== Accesibilidad =====
	_opts_sec(opts, "OPT_SEC_A11Y")
	var btn_row7 := HBoxContainer.new()
	opts.add_child(btn_row7)
	var b_mute := CheckButton.new()
	b_mute.text = Lang.t("HUD_MUTE")
	b_mute.toggled.connect(func(on):
		app.muted = on; app._save_settings())
	btn_row7.add_child(b_mute)
	# reduce motion (WCAG 2.3.3): pop_in, hover, toasts y confetti
	# se vuelven instantáneos
	var b_rm := CheckButton.new()
	b_rm.text = Lang.t("HUD_REDUCE")
	b_rm.tooltip_text = Lang.t("HUD_REDUCE_TIP")
	b_rm.button_pressed = Juice.reduce
	b_rm.toggled.connect(func(on):
		Juice.reduce = on; app._save_settings())
	btn_row7.add_child(b_rm)
	var btn_row8 := HBoxContainer.new()
	opts.add_child(btn_row8)
	# lector de pantalla (TTS del SO): anuncia pantallas, toasts,
	# confirmaciones y turnos — independiente del mute de SFX
	var b_tts := CheckButton.new()
	b_tts.text = Lang.t("HUD_TTS")
	b_tts.tooltip_text = Lang.t("HUD_TTS_TIP")
	b_tts.button_pressed = Tts.enabled
	b_tts.toggled.connect(func(on):
		Tts.enabled = on; app._save_settings()
		if on: Tts.say(Lang.t("HUD_TTS_ON")))
	btn_row8.add_child(b_tts)
	app._opt_toggles = {
		"blind": b_blind, "coords": b_coords,
		"conf": b_conf, "mute": b_mute, "reduce": b_rm, "tts": b_tts}

	# ===== Exportar =====
	_opts_sec(opts, "OPT_SEC_DATA")
	var btn_row9 := HBoxContainer.new()
	opts.add_child(btn_row9)
	var b_export := Button.new()
	b_export.text = Lang.t("HUD_EXPORT")
	b_export.pressed.connect(func():
		var p: String = app.tm.export_log(app.EXPORT_PATH)
		app.hud_alert(Lang.t("HUD_EXPORTED") + p if p != "" \
			else Lang.t("HUD_EXPORT_ERR")))
	btn_row9.add_child(b_export)
	var b_png := Button.new()
	b_png.text = "PNG"
	b_png.tooltip_text = Lang.t("HUD_PNG_TIP")
	b_png.pressed.connect(app._export_png)
	btn_row9.add_child(b_png)
	var b_bel := Button.new()
	b_bel.text = "BEL-FEN"
	b_bel.tooltip_text = Lang.t("HUD_BEL_TIP")
	b_bel.pressed.connect(func():
		# opt_* ya están liberados — usar la config congelada
		var s := BoardState.to_bel(app.tm.state,
			app._last_sel[0], int(app._saved_opts.get("eq0", 0)),
			app._last_sel[1], int(app._saved_opts.get("eq1", 0)),
			app.tm.current)
		DisplayServer.clipboard_set(s)
		app.hud_alert(Lang.t("HUD_BEL_COPIED") + s.left(48) + "…"))
	btn_row9.add_child(b_bel)
	# botón Zen SIEMPRE visible: fuera de lo que se oculta, si no no
	# se podía salir del modo concentración (el propio botón se ocultaba)
	var zen_btn := Button.new()
	zen_btn.name = "ZenToggle"
	zen_btn.text = Lang.t("HUD_ZEN")
	zen_btn.custom_minimum_size = Vector2(0, 32)
	zen_btn.pressed.connect(func(): app._toggle_zen())
	side.add_child(zen_btn)
	# chat online (protocolo ya existe en relay y arbitro)
	if app.online:
		var chat := LineEdit.new()
		chat.placeholder_text = Lang.t("HUD_CHAT_PH")
		chat.text_submitted.connect(func(t):
			if t.strip_edges() == "": return
			if app.ws != null:
				app._ws_send({"op": "chat", "text": t})
			elif app.net_peer != null:
				app._rpc_chat.rpc(t)
			app._chat_log("[tú] " + t)
			chat.text = "")
		tab_chat.add_child(chat)
	else:
		# local/hotseat: sin input — el aviso va centrado como estado
		# vacío intencional, no una etiqueta suelta arriba
		var chat_cc := CenterContainer.new()
		chat_cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tab_chat.add_child(chat_cc)
		var hint := Widgets.lbl(Lang.t("CHAT_OFFLINE"), 13, true, true)
		# CenterContainer usa el min-size del hijo: sin ancho el wrap
		# cortaba palabra a palabra en una columna ilegible
		hint.custom_minimum_size = Vector2(240, 0)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chat_cc.add_child(hint)

	app._wire_tm()
	app._apply_settings()
	# sincronizar los toggles con los ajustes cargados
	app._opt_toggles.blind.set_pressed_no_signal(app.board.blindfold)
	app._opt_toggles.coords.set_pressed_no_signal(app.board.show_coords)
	app._opt_toggles.conf.set_pressed_no_signal(app.board.confirm_moves)
	app._opt_toggles.mute.set_pressed_no_signal(app.muted)
	app._opt_toggles.reduce.set_pressed_no_signal(Juice.reduce)
	app._opt_toggles.tts.set_pressed_no_signal(Tts.enabled)
	app._update_hud()
	app._maybe_bot()

## Refresco del HUD tras cada jugada: turno, líderes, material,
## bandejas, eval bar y lista clickeable de jugadas.
static func update(app) -> void:
	var tm: TurnManager = app.tm
	var f: Dictionary = tm.state.factions[tm.current]
	var extra := ""
	if tm.moves_left > 1:
		extra = Lang.t("HUD_MOVES_LEFT") % tm.moves_left
	var who := PiecesData.fac_name(f)
	if app.online:
		who += Lang.t("HUD_YOU_ARE") % [app.my_net + 1,
			Lang.t("HUD_YOUR_TURN") if tm.current == app.my_net
			else Lang.t("HUD_THEIR_TURN")]
	elif app.coop and tm.current == 0:
		who += Lang.t("HUD_COOP_TURN") % \
			(Lang.t("HUD_HUMAN_A") if app.coop_turn == 0
			else Lang.t("HUD_HUMAN_B"))
	app.hud_turn.text = Lang.t("HUD_TURN") % who
	app.hud_turn.add_theme_color_override("font_color", f.color)
	# lector de pantalla: anunciar la jugada nueva (si la hay) y a
	# quién le toca. Tts deduplica — update() se llama varias veces
	# por jugada; la combinación en un solo say() evita que tts_stop
	# de la segunda llamada pise a la primera.
	var say_txt: String = app.hud_turn.text
	if tm.log.size() > app._tts_log_n:
		app._tts_log_n = tm.log.size()
		# la notación usa glifos ("→", "x") que los motores TTS leen
		# literalmente; traducirlos a palabras
		var mv_say: String = tm.log.back() \
			.replace("→", " " + Lang.t("HUD_MV_TO") + " ") \
			.replace(" x", " " + Lang.t("HUD_MV_CAPTURE"))
		say_txt = "%s. %s" % [mv_say, app.hud_turn.text]
	elif tm.log.size() < app._tts_log_n:
		app._tts_log_n = tm.log.size()   # undo/nueva partida
	Tts.say(say_txt)
	# tarjeta del rival (arriba del panel): facción + bando
	var riv: int = 1 - app.my_net if app.online else \
		(1 if not app.board.flipped else 0)
	var rf: Dictionary = tm.state.factions[riv]
	app.hud_rival.text = "%s  J%d" % [PiecesData.fac_name(rf), riv + 1]
	app.hud_rival.add_theme_color_override("font_color", rf.color)
	app.hud_rival_icon.fid = rf.id
	app.hud_rival_icon.col = rf.color
	app.hud_rival_icon.queue_redraw()
	var l0 := tm.state.leaders_alive(0)
	var l1 := tm.state.leaders_alive(1)
	app.hud_info.text = \
		Lang.t("HUD_INFO") % [
			PiecesData.fac_name(tm.state.factions[0]), l0,
			PiecesData.fac_name(tm.state.factions[1]), l1, extra,
			tm.material_value(0), tm.material_value(1)]
	# bandejas: las piezas de la facción víctima en su color
	var m0 := tm.material_value(0)
	var m1 := tm.material_value(1)
	app.tray0.setup(tm.captured_by[0], tm.state.factions[1],
		maxi(0, m0 - m1))
	app.tray1.setup(tm.captured_by[1], tm.state.factions[0],
		maxi(0, m1 - m0))
	# nombre de apertura (primeras jugadas, estilo lichess)
	app.hud_opening.text = "" if tm.log.size() > 10 \
		else PostGame.opening_name(tm)
	# barra de evaluación (motor propio): el signo no decía a quién
	# favorecía — ahora el texto nombra el jugador que va por delante
	var ev := BeliberBot.evaluate(tm.state, 0)
	app.hud_eval.text = Lang.t("HUD_EVAL_TIE") if ev == 0 \
		else Lang.t("HUD_EVAL_LEAD") % [
			"J1" if ev > 0 else "J2", absi(int(ev))]
	app.eval_bar.frac = clampf(0.5 + ev / 400.0, 0.0, 1.0)
	app.eval_bar.queue_redraw()
	# lista de jugadas clickeable (solo reconstruir si cambia)
	if tm.log.size() != app._log_n:
		app._log_n = tm.log.size()
		# clasificación incremental: solo las jugadas nuevas (undo
		# recorta el array; sin esto era O(n²) evaluaciones)
		while app._move_marks.size() > tm.log.size():
			app._move_marks.pop_back()
		for i in range(app._move_marks.size(), tm.log.size()):
			app._move_marks.append(PostGame.classify_move(tm, i))
		for c in app.move_list.get_children(): c.queue_free()
		for i in tm.log.size():
			var b := Button.new()
			var mark: String = app._move_marks[i] \
				if i < app._move_marks.size() else ""
			b.text = "%d. %s%s" % [i + 1, tm.log[i], mark]
			if mark != "":
				b.add_theme_color_override("font_color",
					BeliberTheme.ok() if mark[0] == "!" \
					else BeliberTheme.danger())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.flat = true
			b.add_theme_font_size_override("font_size", 12)
			b.pressed.connect(func(idx := i):
				app.board.view_i = idx + 1   # snapshot tras la jugada idx
				app.board.queue_redraw())
			app.move_list.add_child(b)

## Cabecera de sección de la pestaña Opciones: texto dim pequeño +
## separador — la lista plana de ~20 controles no tenía jerarquía.
static func _opts_sec(opts: Control, key: String) -> void:
	var l := Widgets.lbl(Lang.t(key), 12, true)
	opts.add_child(l)
	opts.add_child(HSeparator.new())
