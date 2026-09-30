class_name NetClient
extends RefCounted

## Cliente WebSocket del relay / host autoritativo (salas por código,
## matchmaking, resincronización y reconexión).
## Funciones estáticas que operan sobre el controlador raíz (app):
## el estado de la conexión vive en app (ws, ws_room, ws_token…).

static func open(app, create: bool) -> void:
	# si ya tenemos sala+token y no se pide crear, es una reconexión
	var rejoin: bool = not create and app.ws_room != "" \
		and app.ws_code.text.strip_edges() == ""
	app.ws = WebSocketPeer.new()
	var url: String = app.ws_url.text.strip_edges()
	if app.ws.connect_to_url(url) != OK:
		app.hud_alert("No se pudo conectar a %s" % url)
		return
	app._ws_pending = "create" if create \
		else ("rejoin" if rejoin else "join")

static func send(app, msg: Dictionary) -> void:
	if app.ws != null and app.ws.get_ready_state() \
			== WebSocketPeer.STATE_OPEN:
		app.ws.send_text(JSON.stringify(msg))

static func poll(app) -> void:
	app.ws.poll()
	var st: WebSocketPeer.State = app.ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not app.ws_open:
		app.ws_open = true
		if app._ws_pending == "create":
			send(app, {"op": "create", "cfg": app._game_cfg(),
				"name": app.ws_name.text.strip_edges()})
		elif app._ws_pending == "join":
			send(app, {"op": "join",
				"code": app.ws_code.text.strip_edges(),
				"name": app.ws_name.text.strip_edges()})
		elif app._ws_pending == "rejoin":
			send(app, {"op": "rejoin", "code": app.ws_room,
				"side": app.ws_side, "token": app.ws_token})
		elif app._ws_pending == "ladder":
			send(app, {"op": "ladder"})
		elif app._ws_pending == "queue":
			# matchmaking: envío mis preferencias, el server empareja
			var prefs := {
				"f": app.opt_p0.selected, "eq": app.opt_eq0.selected,
				"clock": app.opt_clock.selected,
				"mid": app.chk_midline.button_pressed}
			# ejército custom: las filas viajan (el rival no tiene
			# mi archivo local)
			if app.opt_eq0.selected >= 2:
				var cf: Dictionary = app.factions[app.opt_p0.selected]
				if cf.setups.size() > app.opt_eq0.selected:
					prefs["rows"] = cf.setups[app.opt_eq0.selected]
			send(app, {"op": "queue",
				"name": app.ws_name.text.strip_edges(),
				"prefs": prefs})
		app._ws_pending = ""
	elif st == WebSocketPeer.STATE_CLOSED and app.ws_open:
		app.ws_open = false
		app.hud_alert(
			"Conexión perdida — usa Entrar con el mismo código")
	while app.ws.get_ready_state() == WebSocketPeer.STATE_OPEN \
			and app.ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(
			app.ws.get_packet().get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY:
			_dispatch(app, msg)

static func _dispatch(app, m: Dictionary) -> void:
	match str(m.get("op", "")):
		"hello":
			# el árbitro Godot saluda → modo autoritativo
			app.ws_auth = true
			if app.board != null: app.board.defer_play = true
		"queued":
			app.hud_alert("Buscando rival… (%d en cola)"
				% int(m.get("n", 1)))
		"dequeued":
			app.hud_alert("Cola abandonada")
		"room":
			app.ws_room = str(m.code)
			app.ws_token = str(m.token)
			app.ws_side = int(m.side)
			app.online = true
			app.my_net = app.ws_side
			if app.ws_side == 1 and m.has("cfg"):
				apply_cfg(app, m.cfg)
				app._start_game()
			elif app.ws_side == 0 and m.has("cfg"):
				# matchmaking: la cfg llega fusionada a ambos lados
				apply_cfg(app, m.cfg)
			else:
				app.hud_alert(
					"Sala %s — esperando rival. Comparte el código."
					% app.ws_room)
		"start":
			if app.ws_side == 0 and app.tm == null:
				app._start_game()
		"move":
			var mv: Dictionary = NetCodec.dec(m.mv)
			if mv.get("resign", false):
				app.tm.resign(int(mv.get("side", 1 - app.ws_side)))
			elif mv.get("draw", false):
				app.tm.agree_draw()   # tablas declaradas por el rival
			else:
				app.tm.play(mv)  # eco autoritativo (también del propio)
		"resync":
			resync(app, m)
		"offline":
			if app.hud_info:
				app.hud_info.text += "\n%s" % \
					("Rival desconectado" if m.on \
						else "Rival reconectado")
		"over":
			if app.tm != null and not app.tm.over:
				app.tm.over = true
				# con servidor autoritativo el ganador viene explícito
				app.tm.winner = int(m.get("winner", app.ws_side))
				app.tm.game_over.emit(app.tm.winner)
		"chat":
			app._chat_log("[rival] " + str(m.text).left(200))
		"rating":
			# ELO actualizado tras la partida
			var lines := []
			for n in m.you.keys():
				var r: Dictionary = m.you[n]
				lines.append("%s: %d (%dV)" % [
					n, int(r.elo), int(r.wins)])
			if app.hud_info:
				app.hud_info.text += "\nELO — " + " · ".join(lines)
		"ladder":
			var txt := ""
			for r in m.rows:
				txt += "%s  %d  (%d partidas)\n" % [
					r.name, int(r.elo), int(r.games)]
			if is_instance_valid(app._ladder_label):
				app._ladder_label.text = \
					txt.strip_edges() if txt != "" else "Sin datos"
			else:
				app.hud_alert(txt.strip_edges())
		"err":
			app.hud_alert("Servidor: " + str(m.msg))

static func apply_cfg(app, cfg: Dictionary) -> void:
	app._ws_cfg = cfg   # memorizada para reconstruir en resync
	app.opt_p0.select(int(cfg.f0)); app.opt_eq0.select(int(cfg.eq0))
	app.opt_p1.select(int(cfg.f1)); app.opt_eq1.select(int(cfg.eq1))
	# inyectar filas custom recibidas como setups[2] (eq Personalizado)
	for si in [0, 1]:
		if cfg.has("rows%d" % si):
			ArmyBuilder.inject(
				app.factions[int(cfg["f%d" % si])], cfg["rows%d" % si])
	app.chk_midline.button_pressed = bool(cfg.mid)
	# stall: activar el check + volcar el valor, si no el cliente
	# jugaría con su propio límite y divergiría del host
	var stall: int = int(cfg.get("stall", 0))
	app.chk_stall.button_pressed = stall > 0
	if stall > 0:
		app.stall_spin.value = stall
	app.opt_clock.select(int(cfg.clock))
	app.ai_player = -1

## Reconstruye la partida reproduciendo el historial del servidor.
static func resync(app, m: Dictionary) -> void:
	app._over_handled = false   # el resync puede abrir una partida nueva
	# el relay Python no adjunta cfg en resync (llegó en 'room'); el
	# servidor autoritativo sí — solo aplicar/reconstruir si viene
	var c: Dictionary = m.get("cfg", {})
	if not c.is_empty(): apply_cfg(app, c)
	# reconstruir siempre desde cero: replay sobre un tm existente
	# duplicaría jugadas; sin cfg en el mensaje usar la memorizada
	var c2: Dictionary = c if not c.is_empty() else app._ws_cfg
	app.ai_player = -1
	var from_ply := 0
	if not c2.is_empty():
		# cfg completa: reconstruir desde cero y retraer TODO el historial
		app.tm = TurnManager.new(app.factions[int(c2.f0)], int(c2.eq0),
			app.factions[int(c2.f1)], int(c2.eq1),
			{"midline": bool(c2.mid),
				"stall_limit": int(c2.stall),
				"clock_secs": TurnManager.CLOCK_CHOICES[int(c2.clock)][0],
				"clock_inc": TurnManager.CLOCK_CHOICES[int(c2.clock)][1]})
	elif app.tm != null:
		# sin cfg no conocemos el despliegue inicial (p.ej. draft) —
		# no se puede reconstruir; aplicar solo la cola que falta
		from_ply = app.tm.log.size()
	else:
		return   # sin cfg ni partida previa — nada que resincronizar
	for i in range(from_ply, m.moves.size()):
		var mv: Dictionary = NetCodec.dec(m.moves[i])
		if mv.get("resign", false):
			# el lado que se rindió viaja en el mv (host autoritativo);
			# en relay sin 'side' solo cabe asumir que fue el rival
			app.tm.resign(int(mv.get("side", 1 - app.ws_side)))
		elif mv.get("draw", false):
			app.tm.agree_draw()
		else:
			app.tm.play(mv)
	if app.game_ui == null:
		app.menu_root.queue_free()
		app._build_game()
		# si la partida ya terminó durante el replay, la señal
		# game_over disparó antes de conectarla — disparar a mano
		if app.tm.over and not app._over_handled:
			app._over_handled = true
			app._on_game_over(app.tm.winner)
	else:
		# board quedaba apuntando al TurnManager viejo — reasignar
		# estado mutable y reconectar señales del tm nuevo
		app.board.bind(app.tm)   # reasigna tm y reconecta sus señales
		app.board.selected = Vector2i(-1, -1)
		app.board.legal = []
		app.board.premove = {}
		app.board.pre_sel = Vector2i(-1, -1)
		app.board.flipped = (app.my_net == 1)
		app._wire_tm()
		app.board.queue_redraw()
		app._update_hud()
		# igual que arriba: si el replay terminó la partida, la señal
		# game_over salió antes de reconectar — disparar a mano
		if app.tm.over and not app._over_handled:
			app._over_handled = true
			app._on_game_over(app.tm.winner)
