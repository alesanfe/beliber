class_name PostGame
extends RefCounted

## Fin de partida: modal de resumen (estilo chess.com) + análisis de
## errores por swing de evaluación (estilo lichess).

## Panel de fin de partida: overlay + resumen + análisis + revancha.
static func modal(app, w: int, resumen: String) -> void:
	app.hud_info.text = resumen
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.game_ui.add_child(overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	cc.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Widgets.lbl("¡Tablas!" if w < 0 else \
		"¡Ganan %s!" % app.tm.state.factions[w].name)
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
	b_re.text = "Revancha"
	b_re.pressed.connect(app._rematch)
	row.add_child(b_re)
	var b_close := Button.new()
	b_close.text = "Ver tablero"
	b_close.pressed.connect(func():
		Juice.fade_out(overlay, 0.2))
	row.add_child(b_close)
	Juice.pop_in(panel)

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
	lines.append("Precisión (aprox): J1 %d%% · J2 %d%%" % [acc[0], acc[1]])
	for pl in [0, 1]:
		var bst: Dictionary = best[pl]
		if int(bst.i) >= 0 and float(bst.d) > 30:
			lines.append("Mejor J%d en jugada %d: %s (+%d)" % [
				pl + 1, int(bst.i) + 1,
				tm.log[int(bst.i)].get_slice(" ", 1), int(bst.d)])
	for pl in [0, 1]:
		var w: Dictionary = worst[pl]
		if int(w.i) >= 0 and float(w.d) < -30:
			lines.append("Error J%d en jugada %d: %s (perdió %d)" % [
				pl + 1, int(w.i) + 1,
				tm.log[int(w.i)].get_slice(" ", 1), int(-w.d)])
	if decisive_i >= 0 and decisive_swing > 40:
		lines.append("Momento decisivo: jugada %d (%s, swing %d)" % [
			decisive_i + 1, tm.log[decisive_i].get_slice(" ", 1),
			int(decisive_swing)])
	if lines.size() <= 1:
		lines.append("Sin errores graves detectados.")
	return "Análisis: " + "\n".join(lines)
