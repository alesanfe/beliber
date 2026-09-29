class_name OnlineScreen
extends RefCounted

## Pantalla "Jugar online" — pestañas propias (estilo lichess):
## Rápida / Salas / LAN / Ladder. El menú queda oculto (visible=false)
## para que los opt_* de configuración sigan vivos para el matchmaking.

static func build(app) -> void:
	app.editor_ui = Control.new()
	app.editor_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.menu_root.visible = false
	app.add_child(app.editor_ui)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.editor_ui.add_child(cc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	cc.add_child(box)
	var title := Widgets.lbl("Jugar online")
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
	srv.add_child(Widgets.lbl("Servidor:"))
	app.ws_url = LineEdit.new()
	app.ws_url.text = app._ws_last_addr
	app.ws_url.custom_minimum_size = Vector2(190, 0)
	app.ws_url.text_changed.connect(
		func(t): app._ws_last_addr = t)
	srv.add_child(app.ws_url)
	app.ws_name = LineEdit.new()
	app.ws_name.placeholder_text = "Tu nick"
	app.ws_name.text = app._ws_last_nick
	app.ws_name.text_changed.connect(
		func(t): app._ws_last_nick = t)
	srv.add_child(app.ws_name)
	t_q.add_child(Widgets.lbl(
		"Cola automática: se empareja con tu facción, equipo y reloj."))
	var b_queue := Widgets.primary("Buscar rival", 44)
	b_queue.tooltip_text = \
		"Matchmaking: cola automática (tu facción/equipo)"
	b_queue.pressed.connect(func():
		if app.ws != null and app.ws.get_ready_state() \
				== WebSocketPeer.STATE_OPEN:
			app._ws_pending = "queue"
			app._ws_send({"op": "queue",
				"name": app.ws_name.text.strip_edges(),
				"prefs": {
					"f": app.opt_p0.selected,
					"eq": app.opt_eq0.selected,
					"clock": app.opt_clock.selected,
					"mid": app.chk_midline.button_pressed}})
		else:
			app.ws = WebSocketPeer.new()
			if app.ws.connect_to_url(
					app.ws_url.text.strip_edges()) != OK:
				app.hud_alert("No se pudo conectar")
				return
			app._ws_pending = "queue")
	t_q.add_child(b_queue)

	# — Salas: crear / entrar por código / reconexión —
	var t_r := VBoxContainer.new()
	t_r.name = "Salas"
	tabs.add_child(t_r)
	var rrow := HBoxContainer.new()
	t_r.add_child(rrow)
	rrow.add_child(Widgets.lbl("Código:"))
	app.ws_code = LineEdit.new()
	app.ws_code.placeholder_text = "ABCD"
	app.ws_code.custom_minimum_size = Vector2(90, 0)
	rrow.add_child(app.ws_code)
	var b_ws_host := Button.new()
	b_ws_host.text = "Crear sala"
	b_ws_host.tooltip_text = "Crear sala online en el servidor"
	b_ws_host.pressed.connect(func(): app._ws_connect(true))
	rrow.add_child(b_ws_host)
	var b_ws_join := Button.new()
	b_ws_join.text = "Entrar"
	b_ws_join.tooltip_text = "Unirse a una sala por código"
	b_ws_join.pressed.connect(func(): app._ws_connect(false))
	rrow.add_child(b_ws_join)
	t_r.add_child(Widgets.lbl(
		"El creador comparte el código. " +
		"Sin código y con sala previa, «Entrar» intenta reconectar."))

	# — LAN: ENet directo por IP/puerto —
	var t_l := VBoxContainer.new()
	t_l.name = "LAN"
	tabs.add_child(t_l)
	var lrow := HBoxContainer.new()
	t_l.add_child(lrow)
	lrow.add_child(Widgets.lbl("IP:"))
	app.net_ip = LineEdit.new()
	app.net_ip.placeholder_text = "127.0.0.1"
	app.net_ip.custom_minimum_size = Vector2(140, 0)
	lrow.add_child(app.net_ip)
	lrow.add_child(Widgets.lbl("Puerto:"))
	app.net_port = LineEdit.new()
	app.net_port.text = "7777"
	app.net_port.custom_minimum_size = Vector2(70, 0)
	lrow.add_child(app.net_port)
	var b_host := Button.new()
	b_host.text = "Crear partida"
	b_host.pressed.connect(app._host_game)
	lrow.add_child(b_host)
	var b_join := Button.new()
	b_join.text = "Unirse"
	b_join.pressed.connect(app._join_game)
	lrow.add_child(b_join)
	t_l.add_child(Widgets.lbl(
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
		if app.ws == null or app.ws.get_ready_state() \
				!= WebSocketPeer.STATE_OPEN:
			app.ws = WebSocketPeer.new()
			if app.ws.connect_to_url(
					app.ws_url.text.strip_edges()) != OK:
				lad_lbl.text = "No se pudo conectar"
				return
			app._ws_pending = "ladder"
		else:
			app._ws_send({"op": "ladder"}))
	app._ladder_label = lad_lbl
	app._add_back()
