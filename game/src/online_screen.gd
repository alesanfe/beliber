class_name OnlineScreen
extends RefCounted

## Pantalla "Jugar online" — pestañas propias (estilo lichess):
## Rápida / Salas / LAN / Ladder. El menú queda oculto (visible=false)
## para que los opt_* de configuración sigan vivos para el matchmaking.

static func build(app) -> void:
	app.editor_ui = Control.new()
	# and_offsets: set_anchors_preset solo dejaba anchors=1 sin tocar
	# offsets → size 0 si el padre medía 0 al añadirse (bug del draft)
	app.editor_ui.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT)
	app.menu_root.visible = false
	app.add_child(app.editor_ui)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.editor_ui.add_child(cc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	cc.add_child(box)
	var title := Widgets.lbl(Lang.t("ONLINE_TITLE"))
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 300)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)

	# — Rápida: matchmaking por cola (preferencias = tu facción/equipo) —
	var t_q := VBoxContainer.new()
	t_q.name = Lang.t("ONLINE_TAB_QUICK")
	tabs.add_child(t_q)
	var srv := HBoxContainer.new()
	t_q.add_child(srv)
	srv.add_child(Widgets.lbl(Lang.t("ONLINE_SERVER")))
	app.ws_url = LineEdit.new()
	app.ws_url.text = app._ws_last_addr
	app.ws_url.custom_minimum_size = Vector2(190, 0)
	app.ws_url.text_changed.connect(
		func(t): app._ws_last_addr = t)
	srv.add_child(app.ws_url)
	app.ws_name = LineEdit.new()
	app.ws_name.placeholder_text = Lang.t("ONLINE_NICK_PH")
	app.ws_name.text = app._ws_last_nick
	app.ws_name.text_changed.connect(
		func(t): app._ws_last_nick = t)
	srv.add_child(app.ws_name)
	t_q.add_child(Widgets.lbl(Lang.t("ONLINE_QUEUE_INFO")))
	var b_queue := Widgets.primary(Lang.t("ONLINE_FIND"), 44)
	b_queue.tooltip_text = Lang.t("ONLINE_FIND_TIP")
	b_queue.pressed.connect(func():
		if app.ws != null and app.ws.get_ready_state() \
				== WebSocketPeer.STATE_OPEN:
			app._ws_send({"op": "queue",
				"name": app.ws_name.text.strip_edges(),
				"pid": app._pid(),
				"prefs": NetClient.queue_prefs(app)})
		else:
			app.ws = WebSocketPeer.new()
			if app.ws.connect_to_url(
					app.ws_url.text.strip_edges()) != OK:
				app.hud_alert(Lang.t("ONLINE_CONN_FAIL"))
				return
			app._ws_pending = "queue")
	t_q.add_child(b_queue)

	# — Salas: crear / entrar por código / reconexión —
	var t_r := VBoxContainer.new()
	t_r.name = Lang.t("ONLINE_TAB_ROOMS")
	tabs.add_child(t_r)
	var rrow := HBoxContainer.new()
	t_r.add_child(rrow)
	rrow.add_child(Widgets.lbl(Lang.t("ONLINE_CODE")))
	app.ws_code = LineEdit.new()
	app.ws_code.placeholder_text = "ABCD"
	app.ws_code.custom_minimum_size = Vector2(90, 0)
	rrow.add_child(app.ws_code)
	var b_ws_host := Button.new()
	b_ws_host.text = Lang.t("ONLINE_CREATE_ROOM")
	b_ws_host.tooltip_text = Lang.t("ONLINE_CREATE_ROOM_TIP")
	b_ws_host.pressed.connect(func(): app._ws_connect(true))
	rrow.add_child(b_ws_host)
	var b_ws_join := Button.new()
	b_ws_join.text = Lang.t("ONLINE_JOIN_ROOM")
	b_ws_join.tooltip_text = Lang.t("ONLINE_JOIN_ROOM_TIP")
	b_ws_join.pressed.connect(func(): app._ws_connect(false))
	rrow.add_child(b_ws_join)
	t_r.add_child(Widgets.lbl(Lang.t("ONLINE_ROOM_INFO")))

	# — LAN: ENet directo por IP/puerto —
	var t_l := VBoxContainer.new()
	t_l.name = Lang.t("ONLINE_TAB_LAN")
	tabs.add_child(t_l)
	var lrow := HBoxContainer.new()
	t_l.add_child(lrow)
	lrow.add_child(Widgets.lbl(Lang.t("ONLINE_IP")))
	app.net_ip = LineEdit.new()
	app.net_ip.placeholder_text = "127.0.0.1"
	app.net_ip.custom_minimum_size = Vector2(140, 0)
	lrow.add_child(app.net_ip)
	lrow.add_child(Widgets.lbl(Lang.t("ONLINE_PORT")))
	app.net_port = LineEdit.new()
	app.net_port.text = "7777"
	app.net_port.custom_minimum_size = Vector2(70, 0)
	lrow.add_child(app.net_port)
	var b_host := Button.new()
	b_host.text = Lang.t("ONLINE_HOST")
	b_host.pressed.connect(app._host_game)
	lrow.add_child(b_host)
	var b_join := Button.new()
	b_join.text = Lang.t("ONLINE_JOIN")
	b_join.pressed.connect(app._join_game)
	lrow.add_child(b_join)
	t_l.add_child(Widgets.lbl(Lang.t("ONLINE_LAN_INFO")))

	# — Ladder: clasificación ELO del servidor —
	var t_d := VBoxContainer.new()
	t_d.name = Lang.t("ONLINE_TAB_LADDER")
	tabs.add_child(t_d)
	var b_ladder := Button.new()
	b_ladder.text = Lang.t("ONLINE_LADDER_VIEW")
	b_ladder.tooltip_text = Lang.t("ONLINE_LADDER_TIP")
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
				lad_lbl.text = Lang.t("ONLINE_CONN_FAIL")
				return
			app._ws_pending = "ladder"
		else:
			app._ws_send({"op": "ladder"}))
	app._ladder_label = lad_lbl
	app._add_back()
