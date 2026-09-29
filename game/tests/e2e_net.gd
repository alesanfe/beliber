extends SceneTree
## E2E online: DOS clientes WebSocket contra el relay Python real
## (ws://127.0.0.1:7778). Cada lado lleva su propio TurnManager,
## envía jugadas por el relay y valida el eco del rival — la partida
## entera con el mismo flujo que el cliente de verdad.
##
## Requisito: relay.py corriendo en 127.0.0.1:7778.

const URL := "ws://127.0.0.1:7778"
var fails := 0

func ok(cond: bool, name: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + name)
	if not cond: fails += 1

func _enc(v: Variant) -> Variant:
	return NetCodec.enc(v)

func _dec(v: Variant) -> Variant:
	return NetCodec.dec(v)

func _initialize() -> void:
	print("== E2E online: 2 clientes x relay ==")
	var factions := PiecesData.all()
	ArmyBuilder.apply(factions)

	var wa := WebSocketPeer.new()
	var wb := WebSocketPeer.new()
	if wa.connect_to_url(URL) != OK or wb.connect_to_url(URL) != OK:
		print("  SKIP — relay no disponible en %s" % URL)
		quit(0); return

	# A crea sala, B entra por código
	var code := ""
	var deadline := Time.get_ticks_msec() + 5000
	while code == "" and Time.get_ticks_msec() < deadline:
		wa.poll(); wb.poll()
		await process_frame
		if wa.get_ready_state() == WebSocketPeer.STATE_OPEN:
			wa.send_text(JSON.stringify({"op": "create",
				"cfg": {"f0": 0, "eq0": 0, "f1": 1, "eq1": 0}}))
			while wa.get_available_packet_count() == 0:
				wa.poll(); await process_frame
			var m: Dictionary = JSON.parse_string(
				wa.get_packet().get_string_from_utf8())
			code = str(m.get("code", ""))
	ok(code != "", "sala creada: %s" % code)

	wb.poll()
	while wb.get_ready_state() != WebSocketPeer.STATE_OPEN:
		wb.poll(); await process_frame
	wb.send_text(JSON.stringify({"op": "join", "code": code}))
	var got_start := false
	deadline = Time.get_ticks_msec() + 5000
	while not got_start and Time.get_ticks_msec() < deadline:
		wa.poll(); wb.poll(); await process_frame
		if wb.get_available_packet_count() > 0:
			var m: Dictionary = JSON.parse_string(
				wb.get_packet().get_string_from_utf8())
			if m.get("op") == "start": got_start = true
	ok(got_start, "ambos reciben start")

	# cada lado juega con su propio TurnManager (J1=Humenex, J2=Elfos)
	var tm_a := TurnManager.new(factions[0], 0, factions[1], 0, {})
	var tm_b := TurnManager.new(factions[0], 0, factions[1], 0, {})
	var bot := BeliberBot.new(1, "normal", 0.0)
	var plies := 0
	while not tm_a.over and plies < 400:
		var mover: TurnManager = tm_a if tm_a.current == 0 else tm_b
		var ws: WebSocketPeer = wa if tm_a.current == 0 else wb
		var other: WebSocketPeer = wb if tm_a.current == 0 else wa
		var mv: Dictionary = bot.best_move(mover, mover.current)
		if mv.is_empty(): break
		ws.send_text(JSON.stringify({"op": "move", "mv": _enc(mv)}))
		mover.play(mv)
		# el rival recibe el eco y lo aplica a su copia
		var echoed := false
		var t0 := Time.get_ticks_msec() + 3000
		while not echoed and Time.get_ticks_msec() < t0:
			other.poll(); await process_frame
			while other.get_available_packet_count() > 0:
				var em: Dictionary = JSON.parse_string(
					other.get_packet().get_string_from_utf8())
				if em.get("op") == "move":
					var recv_mv: Dictionary = _dec(em.mv)
					if recv_mv.get("resign", false):
						echoed = true; continue
					var rtm: TurnManager = tm_b if mover == tm_a else tm_a
					rtm.play(recv_mv)
					echoed = true
		if not echoed:
			ok(false, "eco no recibido en ply %d" % plies)
			break
		plies += 1
		# las dos copias deben diverger NUNCA
		if tm_a.log.size() != tm_b.log.size():
			ok(false, "logs divergentes en ply %d" % plies)
			break
	ok(plies > 0, "%d plies jugados por la red" % plies)
	ok(tm_a.log.size() == tm_b.log.size(),
		"estados idénticos en ambos extremos (%d jugadas)" % tm_a.log.size())
	var same_pos := true
	for y in 8: for x in 8:
		var pa: Variant = tm_a.state.at(Vector2i(x, y))
		var pb: Variant = tm_b.state.at(Vector2i(x, y))
		if (pa == null) != (pb == null): same_pos = false
		elif pa != null and (pa.def.letter != pb.def.letter \
				or pa.owner != pb.owner): same_pos = false
	ok(same_pos, "tableros idénticos tras la partida")

	if not tm_a.over:
		# rendición por la red
		wa.send_text(JSON.stringify({"op": "move",
			"mv": {"resign": true}}))
		var t0 := Time.get_ticks_msec() + 3000
		var over_ok := false
		while not over_ok and Time.get_ticks_msec() < t0:
			wb.poll(); await process_frame
			while wb.get_available_packet_count() > 0:
				var em: Dictionary = JSON.parse_string(
					wb.get_packet().get_string_from_utf8())
				if em.get("op") == "move": over_ok = true
		ok(over_ok, "rendición retransmitida al rival")

	wa.close(); wb.close()
	print("== %s ==" % ("OK" if fails == 0 else "%d FALLOS" % fails))
	quit(0 if fails == 0 else 1)
