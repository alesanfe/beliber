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
##        {"op":"leave"}  {"op":"chat","text"}
##   S→C  room | start | move (jugada resuelta, a ambos) | resync |
##        offline | over | err

const PORT_DEFAULT := 7779
const ROOM_TTL := 3600 * 4
const MOVE_LIMIT := 5000

var tcp := TCPServer.new()
var pending: Array = []          # WebSocketPeer en handshake
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
	var names: Array = ["", ""]    # nicks para el ladder
	var empty_since := 0.0
	func other(s: int) -> int: return 1 - s

var factions: Array = []
var ratings := {}                # name -> {elo, games, wins}
const RATINGS_PATH := "user://beliber_ratings.json"

func _init() -> void:
	var port := PORT_DEFAULT
	if OS.get_cmdline_args().size() > 0:
		var a := OS.get_cmdline_args()[-1]
		if a.is_valid_int(): port = int(a)
	factions = PiecesData.all()
	PieceEditor.apply_overrides(factions)
	ArmyBuilder.apply(factions)
	_load_ratings()
	var err := tcp.listen(port)
	print("Beliber host en ws://0.0.0.0:%d  (err=%d)" % [port, err])

## ===== Ladder (ELO por nick, persistido en JSON) =====

func _load_ratings() -> void:
	if FileAccess.file_exists(RATINGS_PATH):
		var f := FileAccess.open(RATINGS_PATH, FileAccess.READ)
		ratings = JSON.parse_string(f.get_as_text()) or {}
		f.close()

func _save_ratings() -> void:
	var f := FileAccess.open(RATINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(ratings))
	f.close()

func _rating(name: String) -> int:
	return int(ratings.get(name, {}).get("elo", 1200))

## Actualiza el ELO de ambos jugadores y lo emite a la sala.
func _record_result(r: Room, w_side: int) -> void:
	var l_side := r.other(w_side)
	var wn: String = r.names[w_side]
	var ln: String = r.names[l_side]
	if wn == "" or ln == "": return
	var ew := 1.0 / (1.0 + pow(10.0, (_rating(ln) - _rating(wn)) / 400.0))
	var el := 1.0 / (1.0 + pow(10.0, (_rating(wn) - _rating(ln)) / 400.0))
	for n in [wn, ln]:
		if not ratings.has(n):
			ratings[n] = {"elo": 1200, "games": 0, "wins": 0}
	ratings[wn].elo = int(_rating(wn) + 32.0 * (1.0 - ew))
	ratings[ln].elo = int(_rating(ln) + 32.0 * (0.0 - el))
	ratings[wn].games += 1; ratings[ln].games += 1
	ratings[wn].wins += 1
	_save_ratings()
	_broadcast(r, {"op": "rating",
		"you": {wn: ratings[wn], ln: ratings[ln]}})

func _process(_d: float) -> bool:
	# aceptar nuevas conexiones TCP → handshake WebSocket
	while tcp.is_connection_available():
		var peer := WebSocketPeer.new()
		peer.accept_stream(tcp.take_connection())
		pending.append(peer)
	# avanzar handshakes
	for p in pending.duplicate():
		p.poll()
		if p.get_ready_state() == WebSocketPeer.STATE_OPEN:
			pending.erase(p)
			peers[p] = {"room": null, "side": -1}
			_send(p, {"op": "hello"})
		elif p.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			pending.erase(p)
	# mensajes de peers ya conectados
	for p in peers.keys().duplicate():
		p.poll()
		if p.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_on_disconnect(p)
			continue
		while p.get_available_packet_count() > 0:
			var raw: String = p.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(raw)
			if typeof(msg) == TYPE_DICTIONARY:
				_dispatch(p, msg)
	# limpieza de salas vacías
	var now := Time.get_ticks_msec() / 1000.0
	for code in rooms.keys().duplicate():
		var r: Room = rooms[code]
		if r.sides[0] == null and r.sides[1] == null:
			if r.empty_since == 0.0: r.empty_since = now
			elif now - r.empty_since > ROOM_TTL: rooms.erase(code)
		else:
			r.empty_since = 0.0
	return false  # nunca salir

## ===== utilidades =====

func _send(p: WebSocketPeer, m: Dictionary) -> void:
	if p != null and p.get_ready_state() == WebSocketPeer.STATE_OPEN:
		p.send_text(JSON.stringify(m))

func _code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var c := ""
	for i in 4: c += chars[randi() % chars.length()]
	return c if not rooms.has(c) else _code()

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
			_on_create(p, m)
		"join":
			_on_join(p, m)
		"rejoin":
			_on_rejoin(p, m)
		"queue":
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
		"chat":
			if room != null and room.sides[room.other(side)] != null:
				_send(room.sides[room.other(side)], {"op": "chat",
					"text": str(m.get("text", "")).left(200)})

func _on_create(p: WebSocketPeer, m: Dictionary) -> void:
	var cfg: Dictionary = m.get("cfg", {})
	var f0i := int(cfg.get("f0", 0)); var f1i := int(cfg.get("f1", 0))
	if f0i < 0 or f1i < 0 or f0i >= factions.size() \
			or f1i >= factions.size():
		return _send(p, {"op": "err", "msg": "Facción inválida"})
	var r := Room.new()
	r.code = _code()
	r.cfg = cfg
	var clock := int(cfg.get("clock", 0))
	var clocks := [[0, 0], [60, 0], [180, 2], [300, 0], [600, 5],
		[1800, 0]]
	var cs: Array = clocks[clampi(clock, 0, clocks.size() - 1)]
	# ejércitos custom: las filas viajan en cfg (rows0/rows1) — si no
	# se inyectan, cada lado desplegaría su propio archivo local
	for si in [0, 1]:
		if cfg.has("rows%d" % si):
			var rows: Array = cfg["rows%d" % si]
			var fac: Dictionary = factions[int(cfg["f%d" % si])]
			if fac.setups.size() > 2: fac.setups[2] = rows
			else: fac.setups.append(rows)
	r.tm = TurnManager.new(factions[f0i], int(cfg.get("eq0", 0)),
		factions[f1i], int(cfg.get("eq1", 0)),
		{"midline": bool(cfg.get("mid", false)),
			"stall_limit": int(cfg.get("stall", 0)),
			"clock_secs": cs[0], "clock_inc": cs[1]})
	r.sides[0] = p
	r.tokens[0] = _token()
	r.names[0] = str(m.get("name", "")).left(24)
	rooms[r.code] = r
	peers[p] = {"room": r, "side": 0}
	_send(p, {"op": "room", "code": r.code, "side": 0,
		"token": r.tokens[0]})

func _on_join(p: WebSocketPeer, m: Dictionary) -> void:
	var code := str(m.get("code", "")).to_upper()
	var r: Room = rooms.get(code)
	if r == null: return _send(p, {"op": "err", "msg": "Sala inexistente"})
	if r.sides[1] != null:
		return _send(p, {"op": "err", "msg": "Sala llena"})
	r.sides[1] = p
	r.tokens[1] = _token()
	r.names[1] = str(m.get("name", "")).left(24)
	peers[p] = {"room": r, "side": 1}
	_send(p, {"op": "room", "code": code, "side": 1,
		"token": r.tokens[1], "cfg": r.cfg})
	_send(p, {"op": "start"})
	_send(r.sides[0], {"op": "peer", "side": 1})
	_send(r.sides[0], {"op": "start"})
	if not r.moves.is_empty():
		_send(p, {"op": "resync", "moves": r.moves.map(NetCodec.enc),
			"side": 1})

## Matchmaking: cola FIFO; al haber 2 se crea la sala fusionando
## las preferencias de cada lado (facción propia + reglas comunes).
func _on_queue(p: WebSocketPeer, m: Dictionary) -> void:
	if p in queue: return
	peers[p]["prefs"] = m.get("prefs", {})
	peers[p]["name"] = str(m.get("name", "")).left(24)
	queue.append(p)
	_send(p, {"op": "queued", "n": queue.size()})
	if queue.size() < 2: return
	var a: WebSocketPeer = queue.pop_front()
	var b: WebSocketPeer = queue.pop_front()
	var pa: Dictionary = peers[a].get("prefs", {})
	var pb: Dictionary = peers[b].get("prefs", {})
	var cfg := {
		"f0": int(pa.get("f", 0)), "eq0": int(pa.get("eq", 0)),
		"f1": int(pb.get("f", 0)), "eq1": int(pb.get("eq", 0)),
		"mid": bool(pa.get("mid", false)) or bool(pb.get("mid", false)),
		"stall": int(pa.get("stall", 0)) or int(pb.get("stall", 0)),
		"clock": int(pa.get("clock", 0)) or int(pb.get("clock", 0))}
	# las filas de ejércitos custom también viajan en el emparejamiento
	if pa.has("rows"): cfg["rows0"] = pa.rows
	if pb.has("rows"): cfg["rows1"] = pb.rows
	# crear la sala como si 'a' fuera el host
	_on_create(a, {"cfg": cfg, "name": peers[a].get("name", "")})
	var code: String = peers[a].get("room", Room.new()).code
	if code == "": return
	var r: Room = rooms.get(code)
	if r == null: return
	# entrada directa de 'b' (equivale a join sin código)
	r.sides[1] = b
	r.tokens[1] = _token()
	r.names[1] = str(peers[b].get("name", ""))
	peers[b] = {"room": r, "side": 1}
	_send(b, {"op": "room", "code": code, "side": 1,
		"token": r.tokens[1], "cfg": r.cfg})
	_send(a, {"op": "peer", "side": 1})
	_send(a, {"op": "start"})
	_send(b, {"op": "start"})

func _on_rejoin(p: WebSocketPeer, m: Dictionary) -> void:
	var code := str(m.get("code", "")).to_upper()
	var side := int(m.get("side", -1))
	var r: Room = rooms.get(code)
	if r == null or side not in [0, 1] or r.tokens[side] != str(m.get("token", "")):
		return _send(p, {"op": "err", "msg": "Reconexión inválida"})
	r.sides[side] = p
	peers[p] = {"room": r, "side": side}
	_send(p, {"op": "room", "code": code, "side": side,
		"token": r.tokens[side], "cfg": r.cfg})
	_send(p, {"op": "resync", "moves": r.moves.map(NetCodec.enc),
		"side": side})
	if r.sides[r.other(side)] != null:
		_send(r.sides[r.other(side)], {"op": "offline", "on": false})

## Validación autoritativa: el cliente solo envía from/to; el servidor
## encuentra la jugada legal y la aplica (o rechaza).
func _on_play(p: WebSocketPeer, m: Dictionary, r: Room, side: int) -> void:
	if r.tm.over: return
	if m.get("resign", false):
		r.tm.resign(side)
		_broadcast(r, {"op": "move",
			"mv": {"resign": true, "side": side},
			"n": r.moves.size()})
		_broadcast(r, {"op": "over", "winner": r.other(side)})
		_record_result(r, r.other(side))
		return
	if m.get("draw", false):
		r.tm.agree_draw()
		_broadcast(r, {"op": "move",
			"mv": {"draw": true}, "n": r.moves.size()})
		_broadcast(r, {"op": "over", "winner": -1})
		return
	if side != r.tm.current:
		return _send(p, {"op": "err", "msg": "No es tu turno"})
	var frm := Vector2i(int(m.get("from", {}).get("x", -9)),
		int(m.get("from", {}).get("y", -9)))
	var to := Vector2i(int(m.get("to", {}).get("x", -9)),
		int(m.get("to", {}).get("y", -9)))
	var mv: Dictionary = {}
	for cand in r.tm.legal_moves(frm):
		if cand.to == to: mv = cand
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
	rooms.erase(r.code)

## Top 20 del ladder (op "ladder").
func _on_ladder(p: WebSocketPeer) -> void:
	var rows := []
	for n in ratings.keys():
		rows.append({"name": n, "elo": _rating(n),
			"games": int(ratings[n].get("games", 0)),
			"wins": int(ratings[n].get("wins", 0))})
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
