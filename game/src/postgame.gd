class_name PostGame
extends RefCounted

## Fin de partida: modal de resumen (estilo chess.com) + análisis de
## errores por swing de evaluación (estilo lichess).

## Clasifica la jugada i del log por su swing de evaluación
## (estilo chess.com): ! buena, ? error, ?? blunder.
static func classify_move(tm: TurnManager, i: int) -> String:
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
	if d <= -7: return " ??"
	if d <= -3: return " ?"
	return ""

## Nombre de apertura tipo lichess: la primera jugada de cada bando
## define el nombre ("Apertura Torre" = salió la Torre primero).
## El log es "J{n} {letra}{desde}→{hasta}" — se parsea la letra.
static func opening_name(tm: TurnManager) -> String:
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
		parts.append("%s: %s" % [PiecesData.fac_name(f), pn])
	return Lang.t("POST_OPENING") + " · ".join(parts) if parts else ""

## Texto del resumen de fin de partida: movimientos, capturas,
## piezas restantes vs iniciales, material, ritmo y análisis.
static func summary(tm: TurnManager) -> String:
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
		mt = Lang.t("POST_PACE") % [acc / tm.move_times.size()]
	return Lang.t("POST_SUMMARY") % [
		tm.log.size(), mt, cap0 if cap0 != "" else "—",
		cap1 if cap1 != "" else "—",
		n0, tm.started[0].size(), n1, tm.started[1].size(),
		tm.material_value(0), tm.material_value(1),
		analysis(tm)]

## Panel de fin de partida: overlay + resumen + análisis + revancha.
static func modal(app, w: int, resumen: String) -> void:
	app.hud_info.text = resumen
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# sobre app (no game_ui): game_ui es un BoxContainer y un hijo sin
	# min-size quedaba con altura 0 — el modal nunca se veía
	overlay.name = "PostGameOverlay"   # _restart lo libera aparte
	app.add_child(overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	cc.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Widgets.lbl(Lang.t("GAME_DRAW") if w < 0 else \
		Lang.t("GAME_WIN") % PiecesData.fac_name(
			app.tm.state.factions[w]))
	title.add_theme_font_size_override("font_size", 30)
	if w >= 0:
		title.add_theme_color_override("font_color",
			app.tm.state.factions[w].color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var res := Widgets.lbl(resumen)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(res)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var b_re := Button.new()
	b_re.text = Lang.t("POST_REMATCH")
	b_re.pressed.connect(app._rematch)
	# online no hay rematch real: _rematch reiniciaba en hotseat y
	# cortaba la conexión dejando al rival "offline" eterno
	b_re.visible = not app.online
	row.add_child(b_re)
	var b_close := Button.new()
	b_close.text = Lang.t("POST_VIEW_BOARD")
	b_close.pressed.connect(func():
		Juice.fade_out(overlay, 0.2))
	row.add_child(b_close)
	Juice.pop_in(panel)
	if w >= 0:
		# celebración: confeti del color ganador sobre el dim del
		# overlay; las partículas son hijas suyas y mueren con él
		var parts := Control.new()
		parts.set_anchors_preset(Control.PRESET_FULL_RECT)
		parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(parts)
		Juice.confetti(parts, app.tm.state.factions[w].color)

## Análisis post-partida: evalúa cada posición del replay y reporta
## los errores más grandes de cada jugador, precisión y momento
## decisivo.
static func analysis(tm: TurnManager) -> String:
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
	lines.append(Lang.t("POST_ACCURACY") % [acc[0], acc[1]])
	for pl in [0, 1]:
		var bst: Dictionary = best[pl]
		if int(bst.i) >= 0 and float(bst.d) > 30:
			lines.append(Lang.t("POST_BEST") % [
				pl + 1, int(bst.i) + 1,
				tm.log[int(bst.i)].get_slice(" ", 1), int(bst.d)])
	for pl in [0, 1]:
		var w: Dictionary = worst[pl]
		if int(w.i) >= 0 and float(w.d) < -30:
			lines.append(Lang.t("POST_BLUNDER") % [
				pl + 1, int(w.i) + 1,
				tm.log[int(w.i)].get_slice(" ", 1), int(-w.d)])
	if decisive_i >= 0 and decisive_swing > 40:
		lines.append(Lang.t("POST_DECISIVE") % [
			decisive_i + 1, tm.log[decisive_i].get_slice(" ", 1),
			int(decisive_swing)])
	if lines.size() <= 1:
		lines.append(Lang.t("POST_CLEAN"))
	return Lang.t("POST_ANALYSIS") + "\n".join(lines)
