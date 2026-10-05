class_name NetClient
extends RefCounted

## Cliente WebSocket del relay / host autoritativo (salas por código,
## matchmaking, resincronización y reconexión).
## Funciones estáticas que operan sobre el controlador raíz (app):
## el estado de la conexión vive en app (ws, ws_room, ws_token…).

## Deadline del handshake WS (ms desde open). Un servidor que acepta
## TCP pero nunca completa el handshake dejaba el socket CONNECTING
## para siempre y _ws_pending atascado sin escape.
static var _deadline: int = 0
static var _retry := 0       # intentos de auto-rejoin restantes
static var _retry_at := 0    # msec en que toca el siguiente

static func open(app, create: bool) -> void:
	# la URL persiste para el auto-rejoin en mitad de partida: los
	# LineEdit de la pantalla online ya están freed en ese punto
	var url := str(app.ws_last_url)
	var code_empty: bool = not is_instance_valid(app.ws_code) \
		or app.ws_code.text.strip_edges() == ""
	if is_instance_valid(app.ws_url):
		var typed: String = app.ws_url.text.strip_edges()
		if typed != "": url = typed
	app.ws_last_url = url
	# si ya tenemos sala+token y no se pide crear, es una reconexión
	var rejoin: bool = not create and app.ws_room != "" and code_empty
	app.ws = WebSocketPeer.new()
	# wss:// usa TLS con validación normal; BELIBER_TLS_INSECURE=1 salta
	# la validación para probar contra certs autofirmados del host
	var err: int
	if url.begins_with("wss://") \
			and OS.get_environment("BELIBER_TLS_INSECURE") == "1":
		err = app.ws.connect_to_url(url, TLSOptions.client_unsafe())
	else:
		err = app.ws.connect_to_url(url)
	if err != OK:
		app.hud_alert("No se pudo conectar a %s" % url)
		return
	_deadline = Time.get_ticks_msec() + 8000
	app._ws_pending = "create" if create \
		else ("rejoin" if rejoin else "join")

static func send(app, msg: Dictionary) -> void:
	if app.ws != null and app.ws.get_ready_state() \
			== WebSocketPeer.STATE_OPEN:
		app.ws.send_text(JSON.stringify(msg))

## Preferencias de matchmaking — una sola construcción para las dos
## rutas de envío (socket nuevo en poll / socket ya abierto en la UI).
## Sin esto la ruta directa no mandaba 'rows' ni 'stall' → desync.
static func queue_prefs(app) -> Dictionary:
	var prefs := {
		"f": app.opt_p0.selected, "eq": app.opt_eq0.selected,
		"clock": app.opt_clock.selected,
		"mid": app.chk_midline.button_pressed}
	if app.chk_stall.button_pressed:
		prefs["stall"] = int(app.stall_spin.value)
	# siempre las filas EFECTIVAS del equipo elegido (un Eq1/Eq2
	# editado también difiere del archivo del rival)
	var cf: Dictionary = app.factions[app.opt_p0.selected]
	var ei := mini(app.opt_eq0.selected, cf.setups.size() - 1)
	if ei >= 0:
		prefs["rows"] = cf.setups[ei]
	# overrides del editor de piezas viajan también (defs distintas
	# en cada extremo = desync de movimientos)
	var ovr := PieceEditor.load_overrides()
	if not ovr.is_empty() and JSON.stringify(ovr).length() < 48000:
		prefs["ovr"] = ovr
	return prefs

static func poll(app) -> void:
	app.ws.poll()
	var st: WebSocketPeer.State = app.ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not app.ws_open:
		app.ws_open = true
		if app._ws_pending == "create":
			send(app, {"op": "create", "cfg": app._game_cfg(),
				"name": app.ws_name.text.strip_edges(),
				"pid": app._pid(), "tok": app._ladder_tok()})
		elif app._ws_pending == "join":
			var jo := {"op": "join",
				"code": app.ws_code.text.strip_edges(),
				"name": app.ws_name.text.strip_edges(),
				"pid": app._pid(), "tok": app._ladder_tok()}
			# el invitado envía sus overrides: el árbitro los fusiona
			# con los del creador antes de desplegar
			var ovr := PieceEditor.load_overrides()
			if not ovr.is_empty() \
					and JSON.stringify(ovr).length() < 48000:
				jo["ovr"] = ovr
			send(app, jo)
		elif app._ws_pending == "rejoin":
			send(app, {"op": "rejoin", "code": app.ws_room,
				"side": app.ws_side, "token": app.ws_token})
		elif app._ws_pending == "ladder":
			send(app, {"op": "ladder"})
		elif app._ws_pending == "queue":
			send(app, {"op": "queue",
				"name": app.ws_name.text.strip_edges(),
				"pid": app._pid(), "tok": app._ladder_tok(),
				"prefs": queue_prefs(app)})
		app._ws_pending = ""
	elif st == WebSocketPeer.STATE_CLOSED and app.ws_open:
		app.ws_open = false
		# liberar el input bloqueado por un play en vuelo; defer_play
		# se mantiene (sin conexión no se pueden enviar jugadas)
		if is_instance_valid(app.board):
			app.board.sync_pending = false
		# auto-rejoin: sin él una caída en mitad de partida era
		# irrecuperable (la pantalla online con el botón Entrar ya
		# está destruida). Backoff ~2s/6s/10s, 3 intentos.
		if app.ws_room != "" and _retry == 0:
			_retry = 3
			_retry_at = Time.get_ticks_msec() + 2000
			app.hud_alert("Conexión perdida — reintentando…")
		elif _retry == 0:
			app.hud_alert(
				"Conexión perdida — usa Entrar con el mismo código")
	# disparo del reintento: socket nuevo con _ws_pending="rejoin"
	if app.ws_room != "" and _retry > 0 and app.ws != null \
			and app.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED \
			and Time.get_ticks_msec() >= _retry_at:
		_retry -= 1
		_retry_at = Time.get_ticks_msec() + 2000 + (3 - _retry) * 4000
		if _retry == 0:
			app.hud_alert("No se pudo reconectar — recarga y reentra" +
				" con el código de sala")
		open(app, false)
	elif st == WebSocketPeer.STATE_CONNECTING \
			and Time.get_ticks_msec() > _deadline:
		app.ws.close()
		app._ws_pending = ""
		app.hud_alert("Tiempo de conexión agotado")
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
		"id_tok":
			# token de identidad del ladder emitido por el host:
			# autentica nuestro pid en las siguientes sesiones
			app._save_ladder_tok(str(m.get("tok", "")))
		"id_err":
			# nuestro pid está registrado con otro token (otro
			# dispositivo lo reclamó primero): jugamos sin rating
			app.hud_alert("Identidad del ladder en uso en otro cliente" +
				" — esta partida no puntuará")
		"queued":
			app.hud_alert("Buscando rival… (%d en cola)"
				% int(m.get("n", 1)))
		"dequeued":
			app.hud_alert("Cola abandonada")
		"room":
			_retry = 0   # rejoin/create/join conseguido → desarmar
			app.ws_room = str(m.code)
			app.ws_token = str(m.token)
			app.ws_side = int(m.side)
			app.online = true
			app.my_net = app.ws_side
			var rcfg: Variant = m.get("cfg", null)
			if app.ws_side == 1 and rcfg is Dictionary:
				apply_cfg(app, rcfg)
				app._start_game()
			elif app.ws_side == 0 and rcfg is Dictionary:
				# matchmaking: la cfg llega fusionada a ambos lados
				apply_cfg(app, rcfg)
			else:
				app.hud_alert(
					"Sala %s — esperando rival. Comparte el código."
					% app.ws_room)
		"start":
			# cfg final del árbitro (con el ovr del invitado ya
			# fusionado): side0 la ve por primera vez aquí
			if m.get("cfg") is Dictionary:
				apply_cfg(app, m.cfg)
			if app.ws_side == 0 and app.tm == null:
				app._start_game()
		"move":
			# un mv no-Dictionary (Array/String/null) abortaba el
			# dispatch entero — peer hostil en relay podía tumbarnos
			if not (m.get("mv") is Dictionary) or app.tm == null: return
			var mv: Dictionary = NetCodec.dec(m.mv)
			if mv.get("resign", false):
				# quien envía es el rival — el 'side' del payload es
				# falsificable (un side=propio rendía al receptor)
				app.tm.resign(1 - app.ws_side)
			elif mv.has("draw"):
				match mv.draw:
					"offer": app._on_draw_offered()
					"decline":
						app.hud_alert("El rival rechazó las tablas.")
					_:
						# sin árbitro, un "accept" sin oferta previa
						# cerraba la partida en tablas (trampa remota)
						if app.ws_auth or app.draw_offered:
							app.tm.agree_draw()
			else:
				# nunca aplicar el dict remoto a ciegas: casamos contra
				# las legales locales y jugamos la variante LOCAL
				var legal: Variant = TurnManager.match_legal(
					app.tm, mv)
				if legal == null:
					app.hud_alert("Jugada remota ilegal ignorada")
				else:
					app.tm.play(legal)
			# el eco libera el input bloqueado en commit()
			if is_instance_valid(app.board):
				app.board.sync_pending = false
		"draw_offer":
			app._on_draw_offered()
		"draw_decline":
			app.hud_alert("El rival rechazó las tablas.")
		"resync":
			app.draw_offered = false   # la oferta no sobrevive al resync
			if is_instance_valid(app.board):
				app.board.sync_pending = false
			if m.get("moves") is Array: resync(app, m)
		"offline":
			app.hud_alert("Rival desconectado" if m.on \
				else "Rival reconectado")
		"over":
			app.draw_offered = false   # no quedan ofertas que responder
			if is_instance_valid(app.board):
				app.board.sync_pending = false
			if app.tm != null and not app.tm.over:
				app.tm.over = true
				# con servidor autoritativo el ganador viene explícito
				app.tm.winner = int(m.get("winner", app.ws_side))
				app.tm.game_over.emit(app.tm.winner)
		"chat":
			app._chat_log("[rival] " + str(m.text).left(200), true)
		"rating":
			# ELO actualizado tras la partida
			if not (m.get("you") is Dictionary): return
			var lines := []
			for n in m.you.keys():
				var r: Variant = m.you[n]
				if not (r is Dictionary): continue
				lines.append("%s: %d (%dV)" % [
					n, int(r.get("elo", 0)), int(r.get("wins", 0))])
			app.hud_alert("ELO — " + " · ".join(lines))
		"ladder":
			if not (m.get("rows") is Array): return
			var txt := ""
			for r in m.rows:
				if not (r is Dictionary): continue
				txt += "%s  %d  (%d partidas)\n" % [
					str(r.get("name", "?")), int(r.get("elo", 0)),
					int(r.get("games", 0))]
			if is_instance_valid(app._ladder_label):
				app._ladder_label.text = \
					txt.strip_edges() if txt != "" else "Sin datos"
			else:
				app.hud_alert(txt.strip_edges())
		"err":
			_retry = 0   # un err (p.ej. rejoin inválido) frena los reintentos
			app.hud_alert("Servidor: " + str(m.get("msg", "?")))
			# el árbitro rechazó la intención: liberar el input
			if is_instance_valid(app.board):
				app.board.sync_pending = false

static func apply_cfg(app, cfg: Dictionary) -> void:
	app._ws_cfg = cfg   # memorizada para reconstruir en resync
	# clamp de índices: una cfg corrupta (relay no la valida) indexaba
	# fuera de factions[]/setups[] y tumbaba el cliente
	var nf: int = app.factions.size()
	# .get con default: claves ausentes en una cfg hostil tumbaban
	# apply_cfg con "Invalid access" (dict.key sobre clave que falta)
	var f0 := clampi(int(cfg.get("f0", 0)), 0, nf - 1)
	var f1 := clampi(int(cfg.get("f1", 0)), 0, nf - 1)
	app.opt_p0.select(f0); app.opt_eq0.select(
		clampi(int(cfg.get("eq0", 0)), 0, app.opt_eq0.item_count - 1))
	app.opt_p1.select(f1); app.opt_eq1.select(
		clampi(int(cfg.get("eq1", 0)), 0, app.opt_eq1.item_count - 1))
	# overrides del editor viajados en cfg: aplicar ANTES de inyectar
	# filas (un '_setups' de ovr no debe pisar las filas efectivas)
	var ovr: Variant = cfg.get("ovr")
	if ovr is Dictionary:
		PieceEditor.apply_dict(app.factions, ovr)
	# inyectar las filas EFECTIVAS recibidas en el índice del equipo
	# elegido (un Eq1/Eq2 editado reemplaza su propio setup)
	var fs := [f0, f1]
	for si in [0, 1]:
		var rv: Variant = cfg.get("rows%d" % si)
		# validar: rows no-Array o filas no-String crasheaban al
		# desplegar (host malicioso o cfg corrupta del relay)
		if rv is Array:
			var clean := []
			for row in rv:
				if row is String: clean.append(row)
			if not clean.is_empty():
				# idx gigante haría crecer setups en un bucle (OOM)
				var eqi := clampi(int(cfg.get("eq%d" % si, 0)), 0,
					maxi(app.opt_eq0.item_count, 1) - 1)
				ArmyBuilder.inject_at(app.factions[fs[si]], clean, eqi)
	app.chk_midline.button_pressed = bool(cfg.get("mid", false))
	# stall: activar el check + volcar el valor, si no el cliente
	# jugaría con su propio límite y divergiría del host
	var stall: int = int(cfg.get("stall", 0))
	app.chk_stall.button_pressed = stall > 0
	if stall > 0:
		app.stall_spin.value = clampi(stall, 20, 200)
	app.opt_clock.select(
		clampi(int(cfg.get("clock", 0)), 0, app.opt_clock.item_count - 1))
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
		var ci := clampi(int(c2.get("clock", 0)), 0,
			TurnManager.CLOCK_CHOICES.size() - 1)
		var n0 := clampi(int(c2.get("f0", 0)), 0, app.factions.size() - 1)
		var n1 := clampi(int(c2.get("f1", 0)), 0, app.factions.size() - 1)
		var e0 := clampi(int(c2.get("eq0", 0)), 0,
			app.factions[n0].setups.size() - 1)
		var e1 := clampi(int(c2.get("eq1", 0)), 0,
			app.factions[n1].setups.size() - 1)
		app.tm = TurnManager.new(app.factions[n0], e0,
			app.factions[n1], e1,
			{"midline": bool(c2.get("mid", false)),
				"stall_limit": maxi(int(c2.get("stall", 0)), 0),
				"clock_secs": TurnManager.CLOCK_CHOICES[ci][0],
				"clock_inc": TurnManager.CLOCK_CHOICES[ci][1]})
	elif app.tm != null:
		# sin cfg no conocemos el despliegue inicial (p.ej. draft) —
		# no se puede reconstruir; aplicar solo la cola que falta
		from_ply = app.tm.log.size()
	else:
		return   # sin cfg ni partida previa — nada que resincronizar
	# rastrear ofertas: un 'accept' falsificado en el historial del
	# relay cerraba la partida en tablas al resincronizar
	var draw_offered := false
	for i in range(from_ply, m.moves.size()):
		if not (m.moves[i] is Dictionary):
			app.hud_alert("Resync corrupto: entrada no-Dictionary")
			break
		var mv: Dictionary = NetCodec.dec(m.moves[i])
		if mv.get("resign", false):
			# el relay estampa 'side' con el emisor real; el host
			# autoritativo también lo incluye. Sin 'side' (historial
			# antiguo) solo cabe asumir que fue el rival.
			var who := int(mv.get("side", 1 - app.ws_side))
			app.tm.resign(clampi(who, 0, 1))
		elif mv.has("draw"):
			# solo el accept cierra: offer/decline son transitorios
			# (aplicarlos a tm.play intentaría mover piezas)
			if mv.draw == "offer":
				draw_offered = true
			elif (mv.draw == true or mv.draw == "accept") \
					and (draw_offered or app.ws_auth):
				app.tm.agree_draw()
		elif app.ws_auth:
			app.tm.play(mv)   # historial del árbitro = verdad
		else:
			# relay sin árbitro: el historial también puede contener
			# dicts falsificados — casar cada entrada contra legales
			var legal: Variant = TurnManager.match_legal(app.tm, mv)
			if legal == null:
				app.hud_alert("Resync corrupto: jugada ilegal")
				break
			app.tm.play(legal)
	if app.game_ui == null:
		# reconstrucción fuera de _start_game: si la pantalla anterior
		# fue IA-vs-IA, ai_both/bot quedaban y el cliente quedaba como
		# espectador de su propia partida online (net_me=9)
		app.ai_both = false
		app.bot = null
		app._teardown_screens()
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
