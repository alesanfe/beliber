class_name MenuScreen
extends RefCounted

## Menú principal: selector de facción/equipo, acciones principales,
## modos de juego, herramientas y configuración avanzada colapsable.
## Los controles quedan en el controlador raíz (app) porque la red y
## las partidas los leen después de que el menú se oculte.

static func build(app) -> void:
	var margin := MarginContainer.new()
	app.menu_root = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 12)
	app.add_child(margin)
	var scroll := SmoothScroll.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var wrapper := CenterContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wrapper)
	app.select_ui = VBoxContainer.new()
	app.select_ui.custom_minimum_size = Vector2(560, 0)
	app.select_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(app.select_ui)
	# transición de entrada (fade suave al abrir el menú)
	app.select_ui.modulate.a = 0.0
	var _mt: Tween = app.create_tween()
	_mt.tween_property(app.select_ui, "modulate:a", 1.0, 0.2)
	var select_ui: VBoxContainer = app.select_ui

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
	btn.pressed.connect(app._start_game)
	row1.add_child(btn)
	var btn_onl := Button.new()
	btn_onl.text = "Online"
	btn_onl.custom_minimum_size = Vector2(145, 64)
	btn_onl.tooltip_text = "Matchmaking, salas, LAN y clasificación"
	btn_onl.pressed.connect(app._open_online)
	row1.add_child(btn_onl)
	var btn_tut := Button.new()
	btn_tut.text = "Tutorial"
	btn_tut.custom_minimum_size = Vector2(135, 64)
	btn_tut.tooltip_text = "Partida guiada con objetivos paso a paso"
	btn_tut.pressed.connect(app._start_tutorial)
	row1.add_child(btn_tut)
	var btn_prof := Button.new()
	btn_prof.text = "Perfil"
	btn_prof.custom_minimum_size = Vector2(105, 64)
	btn_prof.tooltip_text = "Estadísticas, logros y récords"
	btn_prof.pressed.connect(app._open_profile)
	row1.add_child(btn_prof)

	select_ui.add_child(HSeparator.new())

	# selector de facción + emblema dibujado por código (config del vs)
	var grid := GridContainer.new()
	grid.columns = 3
	select_ui.add_child(grid)

	grid.add_child(Widgets.lbl("Jugador 1 (abajo)"))
	grid.add_child(Widgets.lbl("Jugador 2 (arriba)"))
	grid.add_child(Control.new())

	app.opt_p0 = app._faction_picker()
	var pic0 := HBoxContainer.new()
	var ic0 := FactionIcon.new(app.factions[0].id,
		app.factions[0].color, 30)
	pic0.add_child(ic0)
	app.opt_p0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic0.add_child(app.opt_p0)
	grid.add_child(pic0)
	app.opt_p0.item_selected.connect(func(i):
		ic0.fid = app.factions[i].id
		ic0.col = app.factions[i].color
		ic0.queue_redraw(); app._refresh_values())

	app.opt_p1 = app._faction_picker(); app.opt_p1.select(1)
	var pic1 := HBoxContainer.new()
	var ic1 := FactionIcon.new(app.factions[1].id,
		app.factions[1].color, 30)
	pic1.add_child(ic1)
	app.opt_p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic1.add_child(app.opt_p1)
	grid.add_child(pic1)
	app.opt_p1.item_selected.connect(func(i):
		ic1.fid = app.factions[i].id
		ic1.col = app.factions[i].color
		ic1.queue_redraw(); app._refresh_values())
	grid.add_child(Control.new())

	# valor del ejército (regla de equilibrio estilo Betza/CEO)
	app.val_lbl0 = Widgets.lbl(""); grid.add_child(app.val_lbl0)
	app.val_lbl1 = Widgets.lbl(""); grid.add_child(app.val_lbl1)
	grid.add_child(Control.new())

	grid.add_child(Widgets.lbl("Equipo"))
	grid.add_child(Widgets.lbl("Equipo"))
	grid.add_child(Control.new())

	app.opt_eq0 = OptionButton.new()
	app.opt_eq0.add_item("Eq1"); app.opt_eq0.add_item("Eq2")
	app.opt_eq0.add_item("Personalizado")
	app.opt_eq0.item_selected.connect(func(_i): app._refresh_values())
	grid.add_child(app.opt_eq0)
	app.opt_eq1 = OptionButton.new()
	app.opt_eq1.add_item("Eq1"); app.opt_eq1.add_item("Eq2")
	app.opt_eq1.add_item("Personalizado")
	app.opt_eq1.item_selected.connect(func(_i): app._refresh_values())
	grid.add_child(app.opt_eq1)
	grid.add_child(Control.new())

	app.opt_p0.item_selected.connect(func(_i): app._refresh_values())
	app.opt_p1.item_selected.connect(func(_i): app._refresh_values())

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
	app.chk_midline = CheckBox.new()
	app.chk_midline.text = \
		"Invasión de línea (líder llega a la última fila rival)"
	adv.add_child(app.chk_midline)
	var stall_row := HBoxContainer.new()
	adv.add_child(stall_row)
	app.chk_stall = CheckBox.new()
	app.chk_stall.text = "Anti-estancamiento"
	stall_row.add_child(app.chk_stall)
	stall_row.add_child(Widgets.lbl("turnos sin captura:"))
	app.stall_spin = SpinBox.new()
	app.stall_spin.min_value = 10; app.stall_spin.max_value = 60
	app.stall_spin.value = 30
	stall_row.add_child(app.stall_spin)

	# rival IA + reloj
	var opt_row := HBoxContainer.new()
	adv.add_child(opt_row)
	opt_row.add_child(Widgets.lbl("Jugador 2:"))
	app.opt_ai = OptionButton.new()
	for t in ["Humano", "IA nivel 1", "IA nivel 2", "IA nivel 3",
			"IA vs IA"]:
		app.opt_ai.add_item(t)
	opt_row.add_child(app.opt_ai)
	opt_row.add_child(Widgets.lbl("  Estilo:"))
	app.opt_style = OptionButton.new()
	for t in ["Auto (facción)", "Equilibrada", "Agresiva", "Defensiva"]:
		app.opt_style.add_item(t)
	opt_row.add_child(app.opt_style)
	var opt_row2 := HBoxContainer.new()
	adv.add_child(opt_row2)
	opt_row2.add_child(Widgets.lbl("Reloj:"))
	app.opt_clock = OptionButton.new()
	for t in ["Sin reloj", "1+0 Bullet", "3+2 Blitz", "5+0 Blitz",
			"10+5 Rapid", "30 min Clásico"]:
		app.opt_clock.add_item(t)
	opt_row2.add_child(app.opt_clock)
	app.chk_handicap = CheckBox.new()
	app.chk_handicap.text = "La IA juega con la mitad de tiempo"
	opt_row2.add_child(app.chk_handicap)
	app.chk_coop = CheckBox.new()
	app.chk_coop.text = "Co-op: 2 humanos vs IA"
	app.chk_coop.tooltip_text = \
		"Dos jugadores alternan los movimientos de J1"
	opt_row2.add_child(app.chk_coop)
	var opt_row3 := HBoxContainer.new()
	adv.add_child(opt_row3)
	opt_row3.add_child(Widgets.lbl("Tema:"))
	var opt_skin := OptionButton.new()
	var modes := ["dark", "light", "contrast"]
	for t in ["Oscuro", "Claro", "Alto contraste"]:
		opt_skin.add_item(t)
	opt_skin.select(maxi(0, modes.find(app.ui_theme_mode)))
	opt_skin.item_selected.connect(func(i):
		app.ui_theme_mode = modes[i]
		app.theme = BeliberTheme.make(app.ui_theme_mode)
		RenderingServer.set_default_clear_color(BeliberTheme._v.bg)
		app._save_settings())
	opt_row3.add_child(opt_skin)
	app.chk_flip = CheckBox.new()
	app.chk_flip.text = "Girar el tablero cada turno (modo local)"
	adv.add_child(app.chk_flip)

	# ── NIVEL 2: modos de juego (botones medianos) ──
	select_ui.add_child(HSeparator.new())
	select_ui.add_child(Widgets.lbl("Modos"))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 8)
	select_ui.add_child(row2)

	var btn_daily := Button.new()
	var _d := Time.get_date_dict_from_system()
	var today: int = int(_d.year) * 10000 + int(_d.month) * 100 \
		+ int(_d.day)
	var played_today: bool = int(app.stats.get("daily", 0)) == today
	btn_daily.text = "Desafío diario" + (" ✓" if played_today else "")
	btn_daily.custom_minimum_size = Vector2(130, 42)
	btn_daily.tooltip_text = "Enfrentamiento determinista por fecha" + \
		(" (ya jugado hoy)" if played_today else "")
	btn_daily.pressed.connect(app._daily_challenge)
	row2.add_child(btn_daily)
	var btn_run := Button.new()
	btn_run.text = "Modo Run"
	btn_run.custom_minimum_size = Vector2(105, 42)
	btn_run.tooltip_text = "Racha: cada victoria sube el nivel del rival"
	btn_run.pressed.connect(app._start_run)
	row2.add_child(btn_run)
	var btn_draft := Button.new()
	btn_draft.text = "Draft"
	btn_draft.custom_minimum_size = Vector2(90, 42)
	btn_draft.tooltip_text = \
		"Pick alterno de piezas con presupuesto (CEO)"
	btn_draft.pressed.connect(app._open_draft)
	row2.add_child(btn_draft)
	var btn_puz := Button.new()
	btn_puz.text = "Puzzles"
	btn_puz.custom_minimum_size = Vector2(100, 42)
	btn_puz.tooltip_text = "Encuentra la captura del líder"
	btn_puz.pressed.connect(app._open_puzzles)
	row2.add_child(btn_puz)

	# ── NIVEL 3: herramientas (discretas) ──
	select_ui.add_child(Widgets.lbl("Herramientas"))
	var row3 := HBoxContainer.new()
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	row3.add_theme_constant_override("separation", 6)
	select_ui.add_child(row3)
	var btn_ed := Button.new()
	btn_ed.text = "Editor de piezas"
	btn_ed.custom_minimum_size = Vector2(125, 36)
	btn_ed.pressed.connect(app._open_editor)
	row3.add_child(btn_ed)
	var btn_ab := Button.new()
	btn_ab.text = "Constructor"
	btn_ab.custom_minimum_size = Vector2(115, 36)
	btn_ab.tooltip_text = "Constructor de ejército personalizado"
	btn_ab.pressed.connect(app._open_builder)
	row3.add_child(btn_ab)
	var btn_pos := Button.new()
	btn_pos.text = "Editor de posición"
	btn_pos.custom_minimum_size = Vector2(135, 36)
	btn_pos.pressed.connect(app._open_pos_editor)
	row3.add_child(btn_pos)
	var btn_guide := Button.new()
	btn_guide.text = "Guía"
	btn_guide.custom_minimum_size = Vector2(70, 36)
	btn_guide.tooltip_text = \
		"Aprende cada facción: ejército, reglas y patrones"
	btn_guide.pressed.connect(app._open_guide)
	row3.add_child(btn_guide)
	var btn_load := Button.new()
	btn_load.text = "Cargar"
	btn_load.custom_minimum_size = Vector2(80, 36)
	btn_load.tooltip_text = "Cargar partida guardada"
	btn_load.disabled = not FileAccess.file_exists(app.SAVE_PATH)
	btn_load.pressed.connect(app._load_game)
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
		btn_pos: "gear"}, app)

	# estadísticas y logros (línea dim al pie)
	var st := Widgets.lbl("")
	var parts := []
	parts.append("Partidas: %d" % int(app.stats.games))
	for fid in app.stats.wins:
		parts.append("%s: %dV" % [fid, app.stats.wins[fid]])
	# dominio por facción (XP): nivel = xp/100 + 1
	if app.stats.has("xp") and app.stats.xp.size() > 0:
		var lvls := []
		for fid in app.stats.xp:
			lvls.append("%s nv%d" % [fid, app._faction_level(fid)])
		parts.append("Dominio: " + " · ".join(lvls))
	if app.stats.ach.size() > 0:
		var names := []
		for a in app.stats.ach:
			names.append(StatsStore.ACH.get(a, a))
		parts.append("Logros: " + ", ".join(names))
	st.text = " · ".join(parts)
	select_ui.add_child(st)
	app._refresh_values()
