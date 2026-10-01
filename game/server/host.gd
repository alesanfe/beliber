extends SceneTree

## Servidor autoritativo de Beliber (headless):
##   godot --headless --path game -s server/host.gd [puerto]
##
## Salas por código de 4 caracteres. A diferencia del relay Python,
## este proceso instancia TurnManager y VALIDA cada jugada con el
## motor real: el cliente solo envía {from,to}; el servidor busca el
## movimiento legal, lo aplica y difunde la jugada completa a ambos.
##
## Protocolo JSON (mismos ops que el relay, más "play"):
##   C→S  {"op":"create","cfg":{f0,eq0,f1,eq1,mid,stall,clock}}
##        {"op":"join","code":"AB12"}
##        {"op":"rejoin","code","side","token"}
##        {"op":"play","from":{"x","y"},"to":{"x","y"}} | {"resign":true}
##        {"op":"leave"}  {"op":"chat","text"}  {"op":"ping"}
##   S→C  room | start | move (jugada resuelta, a ambos) | resync |
##        offline | over | err | pong (rooms, queue)

const PORT_DEFAULT := 7779
const ROOM_TTL := 3600 * 4
const MOVE_LIMIT := 5000
const MAX_ROOMS := 500      # cap de salas activas (anti-DoS capacidad)
const MIN_RATED_PLIES := 4  # un leave/resign en los primeros plies no
                            # mueve ELO (freno a farming con smurfs)
const STATS_EVERY := 60.0   # heartbeat de métricas al log

var tcp := TCPServer.new()
var pending: Array = []          # [WebSocketPeer, deadline_ms] en handshake
var rooms := {}                  # code -> Room
var peers := {}                  # WebSocketPeer -> {room, side}
var queue: Array = []            # peers en cola de matchmaking

class Room:
	var code: String
	var cfg: Dictionary
	var tm: TurnManager
	var moves: Array = []          # jugadas resueltas (historial)
	var sides: Array = [null, null]  # WebSocketPeer por lado
	var tokens: Array = ["", ""]
	var names: Array = ["", ""]    # nicks para el ladder (display)
	var pids: Array = ["", ""]     # id persistente del cliente → rating
	var draw_offer := -1           # lado con oferta de tablas pendiente
	var empty_since := 0.0
	func other(s: int) -> int: return 1 - s

var factions: Array = []
var ratings := {}                # pid -> {elo, games, wins, name}
var tls_server = null            # TLSOptions.server o null = ws plano
var _stats_at := 0.0             # timestamp del último heartbeat
var _msgs := 0                   # mensajes válidos recibidos este minuto
# override por env para tests (test_host/test_ladder escribían en el
# ratings real del usuario que lanza el host)
var RATINGS_PATH := OS.get_environment("BELIBER_RATINGS") \
	if OS.get_environment("BELIBER_RATINGS") != "" \
	else "user://beliber_ratings.json"

func _init() -> void:
	var port := PORT_DEFAULT
	# user args = lo que va tras '--' en la línea de comandos
	if OS.get_cmdline_user_args().size() > 0:
		var a := OS.get_cmdline_user_args()[-1]
		if a.is_valid_int(): port = int(a)
	factions = PiecesData.all()
	PieceEditor.apply_overrides(factions)
	ArmyBuilder.apply(factions)
	_load_ratings()
	_load_idtokens()
	# TLS opcional: con BELIBER_TLS_CERT+BELIBER_TLS_KEY el host sirve
	# wss:// nativo — cierra el gap "ws:// sin cifrar" sin necesitar
	# un proxy delante
	var cert_p := OS.get_environment("BELIBER_TLS_CERT")
	var key_p := OS.get_environment("BELIBER_TLS_KEY")
	if cert_p != "" and key_p != "":
		var cert := X509Certificate.new()
		var key := CryptoKey.new()
		if cert.load(cert_p) == OK and key.load(key_p) == OK:
			tls_server = TLSOptions.server(key, cert)
			print("TLS activo (wss://)")
		else:
			print("AVISO: cert/key TLS inválidos — sirviendo ws://")
	var err := tcp.listen(port)
	print("Beliber host en ws%s://0.0.0.0:%d  (err=%d)" % [
		"s" if tls_server != null else "", port, err])

## ===== Ladder (ELO por nick, persistido en JSON) =====

func _load_ratings() -> void:
	if FileAccess.file_exists(RATINGS_PATH):
		var f := FileAccess.open(RATINGS_PATH, FileAccess.READ)
		# 'x or {}' no vale: 'or' devuelve bool en GDScript y un JSON
		# corrupto asignaba true a 'ratings' (parse error al arrancar)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary: ratings = parsed

func _save_ratings() -> void:
	StatsStore.atomic_write(RATINGS_PATH, JSON.stringify(ratings))

func _rating(key: String) -> int:
	return int(ratings.get(key, {}).get("elo", 1200))

## ===== Identidad del ladder =====
## El pid lo genera el cliente, pero cualquiera podía declarar el pid
## de otro jugador y corromper su ELO (N19). El host emite un token
## secreto la primera vez que ve un pid; reclamar un pid registrado
## con token incorrecto degrada la sesión a invitado SIN rating.
var idtokens := {}               # pid -> token secreto emitido
var TOKENS_PATH := OS.get_environment("BELIBER_TOKENS") \
	if OS.get_environment("BELIBER_TOKENS") != "" \
	else "user://beliber_idtokens.json"

func _load_idtokens() -> void:
	if FileAccess.file_exists(TOKENS_PATH):
		var f := FileAccess.open(TOKENS_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary: idtokens = parsed

func _save_idtokens() -> void:
	StatsStore.atomic_write(TOKENS_PATH, JSON.stringify(idtokens))

## Resuelve la identidad declarada: devuelve el pid autenticado o ""
## (invitado sin rating). El primer claim registra el token y lo
## devuelve al cliente para que lo persista en sus ajustes.
func _auth_pid(p: WebSocketPeer, pid: String, tok: String) -> String:
	if pid == "": return ""
	if idtokens.has(pid):
		if str(idtokens[pid]) == tok: return pid
		_sec_log("id_err pid=" + pid.left(12))
		_send(p, {"op": "id_err"})
		return ""
	var nt := _token()
	idtokens[pid] = nt
	_save_idtokens()
	_send(p, {"op": "id_tok", "tok": nt})
	return pid

## Actualiza el ELO de ambos jugadores y lo emite a la sala.
## La clave es el PID persistente del cliente (el nick es suplantable
## por cualquiera); el nombre solo se almacena para mostrar.
func _record_result(r: Room, w_side: int) -> void:
	var l_side := r.other(w_side)
	var wk: String = r.pids[w_side]
	var lk: String = r.pids[l_side]
	if wk == "" or lk == "": return   # sin pid no hay rating fiable
	# partidas de <4 plies no mueven ELO: frena el farming "alto
	# conecta y se rinde" con smurfs, y un abandono real instantáneo
	# tampoco merece mover el rating
	if r.tm != null and r.tm.log.size() < MIN_RATED_PLIES: return
	var wn: String = r.names[w_side]
	var ln: String = r.names[l_side]
	var ew := 1.0 / (1.0 + pow(10.0, (_rating(lk) - _rating(wk)) / 400.0))
	var el := 1.0 / (1.0 + pow(10.0, (_rating(wk) - _rating(lk)) / 400.0))
	for k in [wk, lk]:
		if not ratings.has(k):
			ratings[k] = {"elo": 1200, "games": 0, "wins": 0, "name": ""}
	ratings[wk].name = wn
	ratings[lk].name = ln
	ratings[wk].elo = int(_rating(wk) + 32.0 * (1.0 - ew))
	ratings[lk].elo = int(_rating(lk) + 32.0 * (0.0 - el))
	ratings[wk].games += 1; ratings[lk].games += 1
	ratings[wk].wins += 1
	_save_ratings()
	# 'you' se sigue enviando por nick de display (solo presentación)
	_broadcast(r, {"op": "rating",
		"you": {wn: ratings[wk], ln: ratings[lk]}})

func _process(_d: float) -> bool:
	# aceptar nuevas conexiones TCP → handshake WebSocket
	while tcp.is_connection_available():
		var conn := tcp.take_connection()
		# cap global: sin él un flood de SYN agotaba descriptores
		if pending.size() + peers.size() >= 512:
			conn.disconnect_from_host()
			continue
		var peer := WebSocketPeer.new()
		if tls_server != null:
			var stls := StreamPeerTLS.new()
			if stls.accept_stream(conn, tls_server) != OK:
				conn.disconnect_from_host()
				continue
			peer.accept_stream(stls)
		else:
			peer.accept_stream(conn)
		# deadline de handshake: un TCP que nunca completa el upgrade
		# se quedaba en pending para siempre (slowloris)
		pending.append([peer, Time.get_ticks_msec() + 5000])
	# avanzar handshakes
	for e in pending.duplicate():
		var p: WebSocketPeer = e[0]
		p.poll()
		if p.get_ready_state() == WebSocketPeer.STATE_OPEN:
			pending.erase(e)
			peers[p] = {"room": null, "side": -1}
			_send(p, {"op": "hello"})
		elif p.get_ready_state() == WebSocketPeer.STATE_CLOSED \
				or Time.get_ticks_msec() > e[1]:
			pending.erase(e)
			p.close()
	# mensajes de peers ya conectados
	for p in peers.keys().duplicate():
		p.poll()
		if p.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_on_disconnect(p)
			continue
		# límites de entrada: paquete grande o ráfaga = conexión cerrada
		# (sin cap, un peer podía inundar el árbitro)
		var n := 0
		while p.get_available_packet_count() > 0:
			n += 1
			if n > 32:
				_sec_log("peer_flood_closed")
				p.close()
				break
			var raw: String = p.get_packet().get_string_from_utf8()
			if raw.length() > 65536:
				_sec_log("oversized_packet_closed")
				p.close()
				break
			var msg = JSON.parse_string(raw)
			if typeof(msg) == TYPE_DICTIONARY:
				_msgs += 1
				_dispatch(p, msg)
	# heartbeat de métricas: un print/min da visibilidad operativa del
	# host (salas vivas, peers, cola, mensajes) sin dependencias externas
	var now_s := Time.get_ticks_msec() / 1000.0
	if now_s - _stats_at >= STATS_EVERY:
		_stats_at = now_s
		print("stats rooms=%d peers=%d pending=%d queue=%d msgs/min=%d" % [
			rooms.size(), peers.size(), pending.size(),
			queue.size(), _msgs])
		_msgs = 0
	# limpieza de salas vacías
	var now := Time.get_ticks_msec() / 1000.0
	for code in rooms.keys().duplicate():
		var r: Room = rooms[code]
		if r.sides[0] == null and r.sides[1] == null:
			if r.empty_since == 0.0: r.empty_since = now
			elif now - r.empty_since > ROOM_TTL: rooms.erase(code)
		else:
			r.empty_since = 0.0
	# árbitro del reloj: el servidor corre los relojes de las salas
	# activas y dicta el fin por tiempo (antes cada cliente flaggeaba
	# localmente y podían desincronizarse)
	for r in rooms.values():
		if r.tm != null and not r.tm.over \
				and not r.tm.clock.is_empty() \
				and r.sides[0] != null and r.sides[1] != null:
			r.tm.tick_clock(_d)
			if r.tm.over:
				_broadcast(r, {"op": "over",
					"winner": r.tm.winner})
				if r.tm.winner >= 0:
					_record_result(r, r.tm.winner)
	return false  # nunca salir

## ===== utilidades =====

func _send(p: WebSocketPeer, m: Dictionary) -> void:
	if p != null and p.get_ready_state() == WebSocketPeer.STATE_OPEN:
		p.send_text(JSON.stringify(m))

func _code() -> String:
	# PRNG criptográfico también para el código de sala: con randi()
	# el código era la única credencial para entrar y era predecible
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var c := ""
	for b in Crypto.new().generate_random_bytes(4):
		c += chars[int(b) % chars.length()]
	return c if not rooms.has(c) else _code()

## Eventos de seguridad: una línea 'sec:<evento>' por incidente
## relevante — grep-able en logs, sin datos sensibles.
func _sec_log(ev: String) -> void:
	print("sec:%s t=%d" % [ev, Time.get_ticks_msec()])

func _token() -> String:
	# Crypto: el token guarda el rejoin — con randi() un rival podría
	# predecir el estado del PRNG y suplantar la sesión
	var chars := "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789"
	var bytes := Crypto.new().generate_random_bytes(24)
	var t := ""
	for b in bytes: t += chars[b % chars.length()]
	return t

## ===== dispatch =====

func _dispatch(p: WebSocketPeer, m: Dictionary) -> void:
	var info: Dictionary = peers.get(p, {})
	var room: Room = info.get("room")
	var side: int = info.get("side", -1)
	match str(m.get("op", "")):
		"create":
			# un peer en sala que crea otra dejaría un sides[] huérfano
			# apuntándole en la sala vieja
			if room != null: return _send(p,
				{"op": "err", "msg": "Ya estás en una sala"})
			_on_create(p, m)
		"join":
			if room != null: return _send(p,
				{"op": "err", "msg": "Ya estás en una sala"})
			_on_join(p, m)
		"rejoin":
			# misma guardia que queue: un peer ya en sala no puede
			# rejoin a otra (dejaba sides[] huérfanos)
			if room != null: return _send(p,
				{"op": "err", "msg": "Ya estás en una sala"})
			_on_rejoin(p, m)
		"queue":
			# un peer en sala que encola corrompería el emparejamiento:
			# su Room viejo recibiría al rival por error
			if room != null: return _send(p,
				{"op": "err", "msg": "Ya estás en una sala"})
			_on_queue(p, m)
		"dequeue":
			queue.erase(p)
			_send(p, {"op": "dequeued"})
		"play":
			if room == null or side < 0: return
			_on_play(p, m, room, side)
		"leave":
			if room != null: _on_leave(room, side)
		"ladder":
			_on_ladder(p)
		"ping":
			# health check: permite monitorizar el servicio sin sala
			_send(p, {"op": "pong", "rooms": rooms.size(),
				"queue": queue.size()})
		"chat":
			# side puede ser -1 (peer sin sala): other(-1)=2 indexaba
			# fuera de sides[]
			if room != null and side in [0, 1] \
					and room.sides[room.other(side)] != null:
				_send(room.sides[room.other(side)], {"op": "chat",
					"text": str(m.get("text", "")).left(200)})

func _on_create(p: WebSocketPeer, m: Dictionary) -> void:
	queue.erase(p)   # entrar en sala te saca de la cola
	# cap de salas: sin límite un flood de "create" crecía RAM
	# y los dicts rooms/peers indefinidamente (DoS de capacidad)
	if rooms.size() >= MAX_ROOMS:
		_sec_log("room_cap_reached")
		return _send(p, {"op": "err",
			"msg": "Servidor lleno — prueba más tarde"})
	var cfg: Dictionary = m.get("cfg", {})
	var f0i := int(cfg.get("f0", 0)); var f1i := int(cfg.get("f1", 0))
	if f0i < 0 or f1i < 0 or f0i >= factions.size() \
			or f1i >= factions.size():
		return _send(p, {"op": "err", "msg": "Facción inválida"})
	var r := Room.new()
	r.code = _code()
	r.cfg = cfg
	_build_tm(r)
	r.sides[0] = p
	r.tokens[0] = _token()
	r.names[0] = str(m.get("name", "")).left(24)
	r.pids[0] = _auth_pid(p, str(m.get("pid", "")).left(40),
		str(m.get("tok", "")))
	rooms[r.code] = r
	peers[p] = {"room": r, "side": 0}
	# cfg también para el creador: en matchmaking por cola es la
	# cfg FUSIONADA (la facción del rival no la conoce 'a' — sin
	# esto desplegaba con sus opt locales y divergía del árbitro)
	_send(p, {"op": "room", "code": r.code, "side": 0,
		"token": r.tokens[0], "cfg": r.cfg})

## Construye el TurnManager de la sala a partir de r.cfg: las filas
## (rows0/rows1) y los overrides de piezas ('ovr') se aplican sobre
## COPIAS de las facciones — mutar las globales contaminaba las
## siguientes salas con el ejército del jugador anterior.
func _build_tm(r: Room) -> void:
	var cfg: Dictionary = r.cfg
	# clamps de índices: una cfg hostil (f/eq fuera de rango) indexaba
	# fuera de factions[]/setups[] y rompía el TurnManager de la sala
	var f0i := clampi(int(cfg.get("f0", 0)), 0, factions.size() - 1)
	var f1i := clampi(int(cfg.get("f1", 0)), 0, factions.size() - 1)
	var clock := int(cfg.get("clock", 0))
	var cs: Array = TurnManager.CLOCK_CHOICES[
		clampi(clock, 0, TurnManager.CLOCK_CHOICES.size() - 1)]
	var facs := [factions[f0i].duplicate(true),
		factions[f1i].duplicate(true)]
	# ovr ANTES que filas (un '_setups' no debe pisar rows efectivas)
	var ovr: Variant = cfg.get("ovr")
	if ovr is Dictionary:
		PieceEditor.apply_dict(facs, ovr)
	for si in [0, 1]:
		var rr: Variant = cfg.get("rows%d" % si)
		if rr is Array:
			var clean := []
			for row in rr:
				if row is String: clean.append(row)
			if not clean.is_empty():
				# idx sin cota hacía crecer setups en bucle (OOM)
				var eqi := clampi(int(cfg.get("eq%d" % si, 0)), 0, 7)
				ArmyBuilder.inject_at(facs[si], clean, eqi)
	r.tm = TurnManager.new(facs[0],
		clampi(int(cfg.get("eq0", 0)), 0, facs[0].setups.size() - 1),
		facs[1],
		clampi(int(cfg.get("eq1", 0)), 0, facs[1].setups.size() - 1),
		{"midline": bool(cfg.get("mid", false)),
			"stall_limit": maxi(int(cfg.get("stall", 0)), 0),
			"clock_secs": cs[0], "clock_inc": cs[1]})

func _on_join(p: WebSocketPeer, m: Dictionary) -> void:
	queue.erase(p)
	var code := str(m.get("code", "")).to_upper()
	var r: Room = rooms.get(code)
	if r == null: return _send(p, {"op": "err", "msg": "Sala inexistente"})
	if r.sides[1] != null:
		return _send(p, {"op": "err", "msg": "Sala llena"})
	# el creador se fue: sin esta guardia el invitado jugaba contra
	# un hueco (los mensajes a sides[0]=null se tragaban en _send)
	if r.sides[0] == null or r.sides[0].get_ready_state() \
			!= WebSocketPeer.STATE_OPEN:
		return _send(p, {"op": "err", "msg": "Sala cerrada"})
	# el invitado envía SUS overrides de piezas en el join — se fusionan
	# (unión por facción) antes de desplegar; si ya hubiera jugadas el
	# despliegue registrado prevalece (desync documentado)
	var jo: Variant = m.get("ovr")
	if jo is Dictionary:
		var ovr: Dictionary = r.cfg.get("ovr", {})
		for fid in jo: ovr[fid] = jo[fid]
		r.cfg["ovr"] = ovr
		if r.moves.is_empty(): _build_tm(r)
	r.sides[1] = p
	r.tokens[1] = _token()
	r.names[1] = str(m.get("name", "")).left(24)
	r.pids[1] = _auth_pid(p, str(m.get("pid", "")).left(40),
		str(m.get("tok", "")))
	peers[p] = {"room": r, "side": 1}
	_send(p, {"op": "room", "code": code, "side": 1,
		"token": r.tokens[1], "cfg": r.cfg})
	# el 'start' lleva la cfg FINAL (con el ovr del invitado ya
	# fusionado): side0 la recibe por primera vez aquí
	_send(p, {"op": "start", "cfg": r.cfg})
	_send(r.sides[0], {"op": "peer", "side": 1})
	_send(r.sides[0], {"op": "start", "cfg": r.cfg})
	if not r.moves.is_empty():
		_send(p, {"op": "resync", "moves": r.moves.map(NetCodec.enc),
			"side": 1})

## Matchmaking: cola FIFO; al haber 2 se crea la sala fusionando
## las preferencias de cada lado (facción propia + reglas comunes).
func _on_queue(p: WebSocketPeer, m: Dictionary) -> void:
	if p in queue: return
	peers[p]["prefs"] = m.get("prefs", {})
	peers[p]["name"] = str(m.get("name", "")).left(24)
	peers[p]["pid"] = _auth_pid(p, str(m.get("pid", "")).left(40),
		str(m.get("tok", "")))
	queue.append(p)
	_send(p, {"op": "queued", "n": queue.size()})
	if queue.size() < 2: return
	var a: WebSocketPeer = queue.pop_front()
	var b: WebSocketPeer = queue.pop_front()
	# pudo entrar a una sala por otra vía estando encolado, o el
	# socket murió encolado (TCP half-open) — el vivo se reencola
	var a_ok := peers.has(a) and peers[a].get("room") == null \
		and a.get_ready_state() == WebSocketPeer.STATE_OPEN
	var b_ok := peers.has(b) and peers[b].get("room") == null \
		and b.get_ready_state() == WebSocketPeer.STATE_OPEN
	if not (a_ok and b_ok):
		for q in [a, b]:
			if peers.has(q) and peers[q].get("room") == null \
					and q.get_ready_state() == WebSocketPeer.STATE_OPEN:
				queue.append(q)
				_send(q, {"op": "queued", "n": queue.size()})
		return
	var pa: Dictionary = peers[a].get("prefs", {})
	var pb: Dictionary = peers[b].get("prefs", {})
	# ojo: en GDScript 'x or y' devuelve bool, no el operando —
	# para ints (stall/clock) hay que fusionar a mano
	var cfg := {
		"f0": int(pa.get("f", 0)), "eq0": int(pa.get("eq", 0)),
		"f1": int(pb.get("f", 0)), "eq1": int(pb.get("eq", 0)),
		"mid": bool(pa.get("mid", false)) or bool(pb.get("mid", false)),
		"stall": _first_int(pa, pb, "stall"),
		"clock": _first_int(pa, pb, "clock")}
	# las filas de ejércitos custom también viajan en el emparejamiento
	if pa.has("rows"): cfg["rows0"] = pa.rows
	if pb.has("rows"): cfg["rows1"] = pb.rows
	# overrides de piezas de AMBOS lados (unión por facción — los
	# editores de cada jugador editaron posiblemente facciones
	# distintas)
	var ovr := {}
	for prefs in [pa, pb]:
		var o: Variant = prefs.get("ovr")
		if o is Dictionary:
			for fid in o: ovr[fid] = o[fid]
	if not ovr.is_empty(): cfg["ovr"] = ovr
	# crear la sala como si 'a' fuera el host
	_on_create(a, {"cfg": cfg, "name": peers[a].get("name", ""),
		"pid": peers[a].get("pid", "")})
	var r: Room = peers[a].get("room")
	if r == null or r.code == "":
		# create falló (prefs inválidas de 'a'): 'b' no debe quedar
		# colgado en "queued" eterno — devolverlo a la cola
		if peers.has(b) and peers[b].get("room") == null \
				and b.get_ready_state() == WebSocketPeer.STATE_OPEN:
			queue.append(b)
			_send(b, {"op": "queued", "n": queue.size()})
		return
	var code: String = r.code
	# entrada directa de 'b' (equivale a join sin código)
	r.sides[1] = b
	r.tokens[1] = _token()
	r.names[1] = str(peers[b].get("name", ""))
	r.pids[1] = str(peers[b].get("pid", ""))
	peers[b] = {"room": r, "side": 1}
	_send(b, {"op": "room", "code": code, "side": 1,
		"token": r.tokens[1], "cfg": r.cfg})
	_send(a, {"op": "peer", "side": 1})
	_send(a, {"op": "start"})
	_send(b, {"op": "start"})

## Primer valor entero no-cero entre las prefs de ambos jugadores.
func _first_int(pa: Dictionary, pb: Dictionary, k: String) -> int:
	var v := int(pa.get(k, 0))
	return v if v != 0 else int(pb.get(k, 0))

func _on_rejoin(p: WebSocketPeer, m: Dictionary) -> void:
	queue.erase(p)
	var code := str(m.get("code", "")).to_upper()
	var side := int(m.get("side", -1))
	var r: Room = rooms.get(code)
	var tok := str(m.get("token", ""))
	# token vacío: sin esto un extraño ocupaba el hueco libre de la
	# sala (tokens[side]=="" aún no emitido) sin haber hecho join
	if r == null or side not in [0, 1] or tok == "" \
			or r.tokens[side] != tok:
		return _send(p, {"op": "err", "msg": "Reconexión inválida"})
	# si el hueco sigue ocupado por otro socket vivo, el viejo pierde
	# la sesión (su peers[] dejaba de ser coherente con sides[])
	var old: WebSocketPeer = r.sides[side]
	if old != null and old != p:
		peers.erase(old)
		_send(old, {"op": "err", "msg": "Sesión reemplazada"})
		# cerrar de verdad: el socket viejo quedaba OPEN sin poll ni
		# cierre (fuga de fd) y el cliente viejo creía seguir jugando
		old.close()
	r.sides[side] = p
	peers[p] = {"room": r, "side": side}
	_send(p, {"op": "room", "code": code, "side": side,
		"token": r.tokens[side], "cfg": r.cfg})
	_send(p, {"op": "resync", "moves": r.moves.map(NetCodec.enc),
		"side": side})
	# partida ya terminada (reloj por ejemplo): sin 'over' el cliente
	# resync la veía en curso eternamente
	if r.tm.over:
		_send(p, {"op": "over", "winner": r.tm.winner})
	if r.sides[r.other(side)] != null:
		_send(r.sides[r.other(side)], {"op": "offline", "on": false})

## Validación autoritativa: el cliente solo envía from/to; el servidor
## encuentra la jugada legal y la aplica (o rechaza).
func _on_play(p: WebSocketPeer, m: Dictionary, r: Room, side: int) -> void:
	if r.tm.over: return
	if m.get("resign", false):
		r.tm.resign(side)
		# archivar la rendición: sin ella el resync de un rejoin
		# reconstruía la partida "en curso" aunque ya terminó
		r.moves.append({"resign": true, "side": side})
		_broadcast(r, {"op": "move",
			"mv": {"resign": true, "side": side},
			"n": r.moves.size()})
		_broadcast(r, {"op": "over", "winner": r.other(side)})
		_record_result(r, r.other(side))
		return
	# tablas = oferta + consentimiento (draw:"offer"/"accept"/"decline");
	# draw:true legado = tablas directas (clientes viejos)
	var draw: Variant = m.get("draw", false)
	if draw is String:
		match draw:
			"offer":
				r.draw_offer = side
				var o0: WebSocketPeer = r.sides[r.other(side)]
				if o0 != null:
					_send(o0, {"op": "draw_offer"})
			"accept":
				# solo vale aceptar la oferta del otro lado
				if r.draw_offer >= 0 and r.draw_offer != side:
					r.draw_offer = -1
					r.tm.agree_draw()
					r.moves.append({"draw": "accept"})   # ver resign
					_broadcast(r, {"op": "move",
						"mv": {"draw": "accept"},
						"n": r.moves.size()})
					_broadcast(r, {"op": "over", "winner": -1})
			"decline":
				r.draw_offer = -1
				var o1: WebSocketPeer = r.sides[r.other(side)]
				if o1 != null:
					_send(o1, {"op": "draw_decline"})
		return
	if draw == true:
		r.tm.agree_draw()
		r.moves.append({"draw": true})   # ver resign
		_broadcast(r, {"op": "move",
			"mv": {"draw": true}, "n": r.moves.size()})
		_broadcast(r, {"op": "over", "winner": -1})
		return
	if side != r.tm.current:
		return _send(p, {"op": "err", "msg": "No es tu turno"})
	# from/to deben ser dict {x,y}: un tipo suelto (int, string…)
	# rompía .get() dentro de _process y podía tumbar el árbitro
	var fd: Variant = m.get("from"); var td: Variant = m.get("to")
	if not (fd is Dictionary and td is Dictionary):
		return _send(p, {"op": "err", "msg": "Jugada ilegal"})
	var frm := Vector2i(int(fd.get("x", -9)), int(fd.get("y", -9)))
	var to := Vector2i(int(td.get("x", -9)), int(td.get("y", -9)))
	# resolver la jugada legal; second_to desambigua cadenas
	# (mismo from→to con y sin 2º tramo — el Tritón)
	var mv: Dictionary = {}
	var want_second := m.has("second_to")
	var s_dec: Variant = NetCodec.dec(m.second_to) if want_second else null
	for cand in r.tm.legal_moves(frm):
		if cand.to != to: continue
		if want_second:
			var s: Variant = cand.get("second")
			if s != null and s.to == s_dec: mv = cand
		elif not cand.has("second"):
			mv = cand
	if mv.is_empty():
		return _send(p, {"op": "err", "msg": "Jugada ilegal"})
	if r.moves.size() >= MOVE_LIMIT:
		return _send(p, {"op": "err", "msg": "Partida cerrada"})
	r.tm.play(mv)
	r.moves.append(mv)
	_broadcast(r, {"op": "move", "mv": NetCodec.enc(mv),
		"n": r.moves.size()})
	if r.tm.over:
		_broadcast(r, {"op": "over", "winner": r.tm.winner})
		if r.tm.winner >= 0:
			_record_result(r, r.tm.winner)

func _on_leave(r: Room, side: int) -> void:
	# abandonar en curso cuenta como derrota en el ladder
	if not r.tm.over:
		_record_result(r, r.other(side))
	if r.sides[r.other(side)] != null:
		_send(r.sides[r.other(side)], {"op": "over", "reason": "leave"})
	# liberar referencias: sin esto peers[p].room seguía apuntando a
	# una sala borrada y los ops siguientes usaban estado muerto
	for s in [0, 1]:
		var q: WebSocketPeer = r.sides[s]
		if q != null and peers.has(q):
			peers[q]["room"] = null
			peers[q]["side"] = -1
	rooms.erase(r.code)

## Top 20 del ladder (op "ladder").
func _on_ladder(p: WebSocketPeer) -> void:
	var rows := []
	for k in ratings.keys():
		rows.append({"name": str(ratings[k].get("name", k.left(8))),
			"elo": _rating(k),
			"games": int(ratings[k].get("games", 0)),
			"wins": int(ratings[k].get("wins", 0))})
	rows.sort_custom(func(a, b): return a.elo > b.elo)
	_send(p, {"op": "ladder", "rows": rows.slice(0, 20)})

func _broadcast(r: Room, m: Dictionary) -> void:
	for s in [0, 1]:
		if r.sides[s] != null: _send(r.sides[s], m)

func _on_disconnect(p: WebSocketPeer) -> void:
	queue.erase(p)
	var info: Dictionary = peers.get(p, {})
	var r: Room = info.get("room")
	var side: int = info.get("side", -1)
	peers.erase(p)
	if r == null or side < 0: return
	# la sala sigue viva para la reconexión
	if r.sides[side] == p: r.sides[side] = null
	if r.sides[r.other(side)] != null:
		_send(r.sides[r.other(side)], {"op": "offline", "on": true})
