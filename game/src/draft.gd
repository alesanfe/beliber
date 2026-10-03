class_name DraftScreen
extends Control

## Draft de ejércitos (estilo Chess Evolved Online): J1 y J2 eligen
## piezas por turnos con presupuesto = valor del ejército oficial de
## su facción. Al terminar, auto-despliegue en la zona propia y la
## partida empieza con posición personalizada.

signal done(pos: Array)     # [{x,y,l,o}] para TurnManager
signal cancel

var factions: Array
var fi := [0, 1]            # facción elegida por cada jugador
var budget := [0, 0]
var spent := [0, 0]
var picked: Array = [[], []]  # letras elegidas por jugador
var turn := 0
var passed := [false, false]

var info: Label
var pool: GridContainer
var cost_lbl: Label
var picks_lbl: Array = []       # resumen de picks por jugador

func _init(p_factions: Array, p_f0 := 0, p_f1 := 1) -> void:
	factions = p_factions
	fi = [p_f0, p_f1]

func _ready() -> void:
	# and_offsets: set_anchors_preset solo tocaba las anchors y los
	# offsets quedaban -1280 → pantalla con size 0, contenido pegado
	# arriba-izquierda en vez de centrado
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	budget[0] = PiecesData.army_value(factions[fi[0]], 0)
	budget[1] = PiecesData.army_value(factions[fi[1]], 0)
	# CenterContainer directo: el VBox+CenterContainer anterior dejaba
	# el contenido apretado arriba-izquierda (la pantalla quedaba ~80%
	# vacía)
	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var col := VBoxContainer.new()
	root.add_child(col)
	var t := Label.new()
	t.text = Lang.t("DRAFT_TITLE")
	t.add_theme_font_size_override("font_size", 26)
	col.add_child(t)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 16)
	col.add_child(info)
	cost_lbl = Label.new()
	col.add_child(cost_lbl)
	# resumen de lo ya elegido por cada uno (antes solo se veía el
	# contador del turno actual — sin contexto del rival)
	for pl in [0, 1]:
		var pl_lbl := Label.new()
		pl_lbl.add_theme_font_size_override("font_size", 13)
		pl_lbl.add_theme_color_override("font_color",
			factions[fi[pl]].color)
		col.add_child(pl_lbl)
		picks_lbl.append(pl_lbl)
	pool = GridContainer.new()
	pool.columns = 3
	col.add_child(pool)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(brow)
	var b_pass := Button.new()
	b_pass.text = Lang.t("DRAFT_PASS")
	b_pass.pressed.connect(_pass)
	brow.add_child(b_pass)
	var b_done := Widgets.primary(Lang.t("DRAFT_PLAY"))
	b_done.pressed.connect(_finish)
	brow.add_child(b_done)
	var b_cancel := Button.new()
	b_cancel.text = Lang.t("UI_BACK")
	b_cancel.pressed.connect(func(): cancel.emit())
	brow.add_child(b_cancel)
	_refresh()

func _fac() -> Dictionary: return factions[fi[turn]]

func _refresh() -> void:
	var f := _fac()
	info.text = Lang.t("DRAFT_TURN") % [turn + 1, PiecesData.fac_name(f)]
	info.add_theme_color_override("font_color", f.color)
	cost_lbl.text = Lang.t("DRAFT_POINTS") % [
		spent[turn], budget[turn], picked[turn].size()]
	for pl in [0, 1]:
		var pj: Array = picked[pl]
		picks_lbl[pl].text = Lang.t("DRAFT_PICKS") % [
			pl + 1, PiecesData.fac_name(factions[fi[pl]]),
			" ".join(pj) if not pj.is_empty() else "—",
			spent[pl], budget[pl],
			Lang.t("DRAFT_PASSED") if passed[pl] else ""]
	for c in pool.get_children(): c.queue_free()
	for letter in f.pieces:
		var p: Dictionary = f.pieces[letter]
		var v := int(p.get("value", 0))
		var b := Button.new()
		b.text = "%s %s (%d)" % [letter, PiecesData.piece_name(p), v]
		b.disabled = spent[turn] + v > budget[turn]
		# deshabilitado justificado: si no entra en el presupuesto el
		# tooltip lo dice, no el tooltip normal de la pieza
		b.tooltip_text = Lang.t("DRAFT_NO_BUDGET") % [
			budget[turn] - spent[turn]] if b.disabled \
			else Lang.t("DRAFT_VALUE_TIP") % [v,
				Lang.t("DRAFT_LEADER") if p.get("leader", false) else ""]
		b.pressed.connect(func(): _pick(letter))
		pool.add_child(b)

func _pick(letter: String) -> void:
	var p: Variant = _fac().pieces.get(letter)
	if p == null: return   # botón obsoleto de un turno anterior
	spent[turn] += int(p.get("value", 0))
	picked[turn].append(letter)
	_next()

func _pass() -> void:
	passed[turn] = true
	_next()

func _next() -> void:
	if passed[0] and passed[1]:
		_refresh(); return
	turn = 1 - turn
	if passed[turn]: turn = 1 - turn   # salta al que aún no pasó
	_refresh()

## Auto-despliegue: líderes atrás, caras al medio, baratas delante.
func _layout(picks: Array, f: Dictionary, owner_i: int) -> Array:
	var rest := picks.duplicate()
	var leaders: Array = []
	rest = rest.filter(func(l):
		if f.pieces[l].get("leader", false): leaders.append(l); return false
		return true)
	rest.sort_custom(func(a, b):
		return f.pieces[a].get("value", 0) > f.pieces[b].get("value", 0))
	# filas de la zona propia (5 filas): la última para líderes
	var rows_y: Array
	if owner_i == 0:
		rows_y = [7, 6, 5, 4, 3]
	else:
		rows_y = [0, 1, 2, 3, 4]
	var pos := []
	var back: int = rows_y[0]
	# líderes centrados en la última fila
	var lx := 4 - leaders.size() / 2
	for i in leaders.size():
		pos.append({"x": lx + i, "y": back, "l": leaders[i], "o": owner_i})
	# el resto: delante, alternando columnas para no amontonar
	var slots := []
	for ri in range(1, rows_y.size()):
		for x in range(8):
			slots.append(Vector2i(x, rows_y[ri]))
	# orden de columnas centrado: 3,4,2,5,1,6,0,7
	slots.sort_custom(func(a, b):
		return absf(a.x - 3.5) < absf(b.x - 3.5))
	for i in mini(rest.size(), slots.size()):
		var s: Vector2i = slots[i]
		pos.append({"x": s.x, "y": s.y, "l": rest[i], "o": owner_i})
	return pos

func _finish() -> void:
	var pos := []
	for pl in [0, 1]:
		var mine: Array = picked[pl]
		if mine.is_empty():   # sin picks → ejército oficial
			var rows: Array = factions[fi[pl]].setups[0]
			var base := 7 if pl == 0 else 0
			var d := -1 if pl == 0 else 1
			for j in rows.size():
				for x in mini(rows[j].length(), 8):
					var ch: String = rows[j].substr(x, 1)
					if ch != "." and ch != " ":
						pos.append({"x": x, "y": base + d * j,
							"l": ch, "o": pl})
		else:
			# ejército sin líder = derrota instantánea en la 1ª jugada;
			# forzar el líder más barato de la facción si falta
			var fac: Dictionary = factions[fi[pl]]
			var has_leader := mine.any(func(l):
				return fac.pieces[l].get("leader", false))
			if not has_leader:
				var best := ""
				var best_v := 1 << 30
				for l in fac.pieces:
					var pp: Dictionary = fac.pieces[l]
					if pp.get("leader", false) and \
							int(pp.get("value", 0)) < best_v:
						best = l; best_v = int(pp.value)
				if best != "": mine.append(best)
			pos.append_array(_layout(mine, fac, pl))
	done.emit(pos)
