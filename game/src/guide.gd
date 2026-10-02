class_name GuideScreen
extends Control

## Guía por facción (tutorial interactivo estilo Root "walkthrough"):
## muestra el ejército desplegado, el arquetipo, las reglas especiales
## y permite hacer clic en cualquier pieza para ver su patrón real.

var factions: Array
var tm: TurnManager
var board: BoardView
var info: Label
var piece_lbl: Label
var opt: OptionButton
# entrenamiento: "¿dónde puede mover esta pieza?"
var quiz_on := false
var quiz_cell := Vector2i(-1, -1)
var quiz_targets: Array = []       # destinos legales de la pieza quiz
var quiz_moves: Array = []         # jugadas completas (dicts p/ BoardView)
var quiz_done := false             # ya respondió la pregunta actual
var quiz_ok := 0
var quiz_total := 0
var quiz_lbl: Label
var quiz_btn: Button

func _init(p_factions: Array) -> void:
	factions = p_factions
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	# la facción se enfrenta a sí misma: ambos ejércitos inspeccionables
	var f0: Dictionary = factions[0]
	tm = TurnManager.new(f0, 0, f0, 0, {})
	board = BoardView.new(tm)
	board.inspect = true
	center.add_child(board)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(340, 0)
	row.add_child(side)
	side.add_child(_lbl(Lang.t("GUIDE_TITLE"), 26))
	opt = OptionButton.new()
	for f in factions:
		opt.add_item(f.name)
	opt.item_selected.connect(_pick)
	side.add_child(opt)
	info = _lbl("", 15)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	side.add_child(info)
	side.add_child(HSeparator.new())
	quiz_btn = Button.new()
	quiz_btn.text = Lang.t("GUIDE_QUIZ_BTN")
	quiz_btn.tooltip_text = Lang.t("GUIDE_QUIZ_TIP")
	quiz_btn.toggled.connect(_quiz_toggle)
	quiz_btn.toggle_mode = true
	side.add_child(quiz_btn)
	quiz_lbl = _lbl("", 14)
	quiz_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	side.add_child(quiz_lbl)
	var b_next := Button.new()
	b_next.text = Lang.t("GUIDE_NEXT")
	b_next.pressed.connect(_quiz_next)
	side.add_child(b_next)
	side.add_child(HSeparator.new())
	side.add_child(_lbl(Lang.t("GUIDE_CLICK"), 13))
	piece_lbl = _lbl("", 14)
	piece_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	piece_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(piece_lbl)
	board.cell_picked.connect(_quiz_click)
	_show_faction(0)

func _lbl(t: String, size := 0) -> Label:
	return Widgets.lbl(t, size, false, true)

func _pick(i: int) -> void:
	var f: Dictionary = factions[i]
	tm = TurnManager.new(f, 0, f, 0, {})
	board.bind(tm)   # reasigna tm y reconecta sus señales
	board.selected = Vector2i(-1, -1)
	board.legal = []
	quiz_cell = Vector2i(-1, -1)
	quiz_targets = []
	if quiz_on: _quiz_next()
	_show_faction(i)

func _show_faction(i: int) -> void:
	var f: Dictionary = factions[i]
	info.text = "%s — %s\n\n" % [
		f.name, PiecesData.STYLES.get(f.id, "")] + Lang.t("GUIDE_RULES")
	var rules: Dictionary = f.get("rules", {})
	if rules.is_empty():
		info.text += Lang.t("GUIDE_RULES_NONE")
	for k in rules:
		info.text += "\n• " + _rule_text(k)
	info.text += "\n\n" + Lang.t("GUIDE_PIECES")
	for letter in f.pieces:
		var p: Dictionary = f.pieces[letter]
		info.text += "\n%s %s (%s)%s" % [
			letter, p.name,
			Lang.t("GUIDE_VALUE") % int(p.get("value", 0)),
			Lang.t("DRAFT_LEADER") if p.get("leader", false) else ""]
	board.queue_redraw()

static func _rule_text(k: String) -> String:
	match k:
		"primero": return Lang.t("RULE_FIRST")
		"segundo": return Lang.t("RULE_SECOND")
		"doble_apertura": return Lang.t("RULE_DOUBLE_OPEN")
		"doble_lider": return Lang.t("RULE_DOUBLE_LEAD")
	return k

## ——— Entrenamiento: quiz de movimientos legales ———

func _quiz_toggle(on: bool) -> void:
	quiz_on = on
	board.quiz = on
	quiz_cell = Vector2i(-1, -1)
	quiz_targets = []
	board.legal = []
	if on:
		_quiz_next()
	else:
		quiz_lbl.text = Lang.t("GUIDE_QUIZ_PAUSE") % [
			quiz_ok, quiz_total]
		board.selected = Vector2i(-1, -1)
		board.queue_redraw()

func _quiz_next() -> void:
	if not quiz_on: return
	# pieza al azar (de cualquier bando) con al menos un destino legal
	var cands := []
	for y in 8:
		for x in 8:
			var c := Vector2i(x, y)
			if tm.state.at(c) == null: continue
			var mv := MoveGen.moves_for(tm.state, c)
			if not mv.is_empty(): cands.append({"c": c, "mv": mv})
	if cands.is_empty():
		quiz_lbl.text = Lang.t("GUIDE_QUIZ_NONE")
		return
	var pick: Dictionary = cands[randi() % cands.size()]
	quiz_cell = pick.c
	quiz_targets = []
	quiz_moves = pick.mv   # board.legal exige dicts de jugada, no celdas
	for m in pick.mv: quiz_targets.append(m.to)
	quiz_done = false
	var p: Dictionary = tm.state.at(quiz_cell)
	board.selected = quiz_cell      # marca el origen
	board.legal = []                # destinos ocultos hasta responder
	quiz_lbl.text = Lang.t("GUIDE_QUIZ_ASK") % [
		p.def.name, quiz_ok, quiz_total]
	board.queue_redraw()

func _quiz_click(c: Vector2i) -> void:
	if not quiz_on or quiz_cell.x < 0: return
	if quiz_done:
		_quiz_next()
		return
	quiz_done = true
	quiz_total += 1
	var p: Dictionary = tm.state.at(quiz_cell)
	board.legal = quiz_moves      # revela la respuesta correcta
	if c in quiz_targets:
		quiz_ok += 1
		quiz_lbl.text = Lang.t("GUIDE_QUIZ_OK") % [
			p.def.name, quiz_ok, quiz_total]
	else:
		quiz_lbl.text = Lang.t("GUIDE_QUIZ_MISS") % [
			p.def.name, quiz_targets.size(), quiz_ok, quiz_total]
	board.queue_redraw()
