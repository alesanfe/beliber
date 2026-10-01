class_name PieceEditor
extends Control

## Editor de piezas de Beliber.
## Pinta el mapa de casillas de una pieza exactamente como en los diagramas
## de referencia, y guarda las sobrescrituras en user://beliber_pieces.json.

const SAVE_PATH := "user://beliber_pieces.json"
const EDIT_CELL := 56

var factions: Array = []
var faction: Dictionary
var piece_def: Dictionary
var cells: Dictionary = {}          # "dx,dy" -> código
var leg2_cells: Dictionary = {}     # 2º tramo encadenado (leg2)
var anchor := Vector2i(3, 4)        # casilla donde se dibuja la pieza
var paint := "o"                    # código seleccionado
var placing_piece := false
var editing_leg2 := false           # pintando el segundo tramo
var preview := false
var preview_moves: Array = []

var opt_f: OptionButton
var opt_p: OptionButton
var opt_eq: OptionButton
var opt_mode: OptionButton
var name_edit: LineEdit
var value_spin: SpinBox
var sym_opt: OptionButton
var leader_chk: CheckBox
var swap_chk: CheckBox
var castle_chk: CheckBox
var status_lbl: Label
var canvas: EditorCanvas
var dep_canvas: DeployCanvas
var move_box: Control          # UI de edición de movimiento
var dep_sec: VBoxContainer     # sección de despliegue (modo Posición)
var dep_pal: GridContainer     # paleta de letras para despliegue
var deploy_rows: Array = []    # filas de texto editables del setup

# modo de edición
var mode := "moves"            # "moves" | "deploy"
var dep_paint := "P"           # letra a colocar en el despliegue

class EditorCanvas extends Control:
	var ed: PieceEditor

	func _init(p_ed: PieceEditor) -> void:
		ed = p_ed
		custom_minimum_size = Vector2(EDIT_CELL * 8, EDIT_CELL * 8)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for y in 8:
			for x in 8:
				var r := Rect2(x * EDIT_CELL, y * EDIT_CELL, EDIT_CELL, EDIT_CELL)
				draw_rect(r, Color(0.92, 0.92, 0.90))
				draw_rect(r, Color(0.55, 0.55, 0.55), false, 1.0)
				var cell := Vector2i(x, y)
				var off := cell - ed.anchor
				var key := "%d,%d" % [off.x, off.y]
				var act: Dictionary = ed._active_cells()
				if cell != ed.anchor and act.has(key):
					var code: String = act[key]
					draw_rect(r.grow(1), PiecesData.code_color(code))
					_text(font, code, r, Color.BLACK)
		if ed.preview:
			for mv in ed.preview_moves:
				var dst: Vector2i = mv.to
				var r := Rect2(dst.x * EDIT_CELL, dst.y * EDIT_CELL,
					EDIT_CELL, EDIT_CELL)
				draw_rect(r.grow(2), Color(0.1, 0.9, 0.9, 0.45))
				draw_rect(r.grow(2), Color.CYAN, false, 3.0)
		# la pieza
		var ra := Rect2(ed.anchor.x * EDIT_CELL, ed.anchor.y * EDIT_CELL,
			EDIT_CELL, EDIT_CELL)
		draw_rect(ra.grow(1), Color(0.1, 0.1, 0.1))
		_text(font, ed.piece_def.letter, ra, Color.WHITE, true)
		var lbl := "2º TRAMO (%d celdas)" % ed.leg2_cells.size() \
			if ed.editing_leg2 else "PIEZA (%s)" % (
				"literal" if ed.piece_def.get("sym") == "lit"
				else "simétrico")
		_text(font, lbl, Rect2(0, -24, 400, 22), Color(0.4, 0.4, 0.4))

	func _text(font: Font, t: String, r: Rect2, col: Color, big := false) -> void:
		var fs := int(EDIT_CELL * (0.6 if big else 0.4))
		var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, r.get_center() - Vector2(sz.x / 2, -sz.y / 3), t,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			var cell := Vector2i(e.position / EDIT_CELL)
			if cell.x < 0 or cell.x > 7 or cell.y < 0 or cell.y > 7: return
			ed.on_cell(cell, e.button_index)


## Lienzo de despliegue: edita las filas del tablero de inicio (Eq1/Eq2)
## de la facción. Muestra las 8 columnas × filas del diagrama.
class DeployCanvas extends Control:
	var ed: PieceEditor

	func _init(p_ed: PieceEditor) -> void:
		ed = p_ed
		custom_minimum_size = Vector2(EDIT_CELL * 8, EDIT_CELL * 8)

	func _rows() -> int:
		return ed.deploy_rows.size()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var n := maxi(_rows(), 1)
		for y in 8:
			for x in 8:
				var r := Rect2(x * EDIT_CELL, y * EDIT_CELL, EDIT_CELL, EDIT_CELL)
				var in_zone := y < n
				draw_rect(r, Color(0.92, 0.92, 0.90) if in_zone
					else Color(0.80, 0.80, 0.78))
				draw_rect(r, Color(0.55, 0.55, 0.55), false, 1.0)
				if in_zone and y < ed.deploy_rows.size():
					var row: String = ed.deploy_rows[y]
					if x < row.length() and row.substr(x, 1) != ".":
						var letter := row.substr(x, 1)
						var def: Dictionary = ed.faction.pieces.get(letter, {})
						var fc: Color = ed.faction.color
						draw_rect(r.grow(2), fc.darkened(0.45))
						draw_rect(r.grow(2), fc, false, 2.0)
						_t(font, letter, r, Color.WHITE)
						if def.get("leader", false):
							draw_circle(r.get_center() + Vector2(0, -EDIT_CELL*0.34),
								5.0, Color(1, 0.85, 0.2))
		_t(font, "fila inferior = fila trasera del jugador",
			Rect2(0, 8 * EDIT_CELL + 4, 640, 20), Color(0.4, 0.4, 0.4))

	func _t(font: Font, t: String, r: Rect2, col: Color) -> void:
		var fs := int(EDIT_CELL * 0.5)
		var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, r.get_center() - Vector2(sz.x / 2, -sz.y / 3), t,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			var cell := Vector2i(e.position / EDIT_CELL)
			if cell.x < 0 or cell.x > 7 or cell.y < 0 or cell.y >= _rows():
				return
			ed.on_deploy_cell(cell, e.button_index)


func _init(p_factions: Array) -> void:
	factions = p_factions

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# ---------- columna izquierda: selección + paleta ----------
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	root.add_child(left)

	# hueco para el botón "← Volver" (absolute en 8,8 sobre esta UI)
	var pad := Control.new()
	pad.custom_minimum_size.y = 36
	left.add_child(pad)
	left.add_child(_title("Editor de piezas"))
	opt_mode = OptionButton.new()
	opt_mode.add_item("Movimiento")
	opt_mode.add_item("Posición inicial")
	opt_mode.item_selected.connect(func(_i): _switch_mode())
	left.add_child(opt_mode)
	opt_f = OptionButton.new()
	for i in factions.size():
		opt_f.add_item(factions[i].name)
	opt_f.item_selected.connect(func(_i): _reload_pieces())
	left.add_child(opt_f)
	opt_p = OptionButton.new()
	opt_p.item_selected.connect(func(_i): _load_piece())
	left.add_child(opt_p)

	left.add_child(_lbl("Efecto (clic izq pinta, der borra)"))
	var pal := GridContainer.new()
	pal.columns = 2
	left.add_child(pal)
	for code in ["m","c","o","j","g","J","t","T","w","p","P","3","e","a",
			"E","d","k","q","Q"]:
		var b := Button.new()
		b.text = "%s  %s" % [code, PiecesData.CODE_NAMES[code]]
		b.custom_minimum_size = Vector2(0, 26)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PiecesData.code_color(code)
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(func(): paint = code)
		pal.add_child(b)

	# plantillas rápidas: patrones clásicos de un clic
	left.add_child(_lbl("Plantillas rápidas"))
	var tpl := GridContainer.new()
	tpl.columns = 3
	left.add_child(tpl)
	for tn in ["Caballero", "Arquero", "Torre", "Alfil", "Salto",
			"Teleport"]:
		var tb := Button.new()
		tb.text = tn
		tb.custom_minimum_size = Vector2(0, 26)
		var tname: String = tn
		tb.pressed.connect(func(): _template(tname))
		tpl.add_child(tb)

	# ---------- centro: lienzo ----------
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var cv := VBoxContainer.new()
	center.add_child(cv)
	move_box = VBoxContainer.new()
	cv.add_child(move_box)
	canvas = EditorCanvas.new(self)
	move_box.add_child(canvas)
	dep_canvas = DeployCanvas.new(self)
	dep_canvas.visible = false
	cv.add_child(dep_canvas)
	var btn_preview := Button.new()
	btn_preview.text = "Vista previa de movimientos (tablero vacío)"
	btn_preview.pressed.connect(_toggle_preview)
	move_box.add_child(btn_preview)
	var btn_place := Button.new()
	btn_place.text = "Reubicar pieza (clic en el tablero)"
	btn_place.pressed.connect(func(): placing_piece = true)
	move_box.add_child(btn_place)
	# segundo tramo encadenado (Tritón): mismo lienzo, otro mapa
	var btn_leg2 := CheckButton.new()
	btn_leg2.text = "Editar 2º tramo (cadena)"
	btn_leg2.toggled.connect(func(on: bool):
		editing_leg2 = on
		preview = false; preview_moves = []
		canvas.queue_redraw())
	move_box.add_child(btn_leg2)

	# ---------- derecha: propiedades ----------
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	root.add_child(right)
	right.add_child(_title("Propiedades"))
	right.add_child(_lbl("Nombre"))
	name_edit = LineEdit.new()
	right.add_child(name_edit)
	right.add_child(_lbl("Valor"))
	value_spin = SpinBox.new()
	value_spin.max_value = 20
	right.add_child(value_spin)
	right.add_child(_lbl("Simetría"))
	sym_opt = OptionButton.new()
	sym_opt.add_item("Simétrica (8 direcciones)")
	sym_opt.add_item("Literal (solo hacia adelante)")
	right.add_child(sym_opt)
	leader_chk = CheckBox.new(); leader_chk.text = "Líder (victoria)"
	right.add_child(leader_chk)
	swap_chk = CheckBox.new()
	swap_chk.text = "Roba movimientos al capturar"
	right.add_child(swap_chk)
	castle_chk = CheckBox.new()
	castle_chk.text = "Pareja de enroque (estilo torre)"
	right.add_child(castle_chk)

	# ---- sección despliegue (visible en modo Posición inicial) ----
	right.add_child(HSeparator.new())
	dep_sec = VBoxContainer.new()
	right.add_child(dep_sec)
	dep_sec.add_child(_lbl("Equipo a editar"))
	opt_eq = OptionButton.new()
	opt_eq.add_item("Eq1"); opt_eq.add_item("Eq2")
	opt_eq.item_selected.connect(func(_i): _load_deploy())
	dep_sec.add_child(opt_eq)
	dep_sec.add_child(_lbl("Pieza a colocar (clic izq, der borra)"))
	dep_pal = GridContainer.new()
	dep_pal.columns = 2
	dep_sec.add_child(dep_pal)
	var b_dsave := Button.new(); b_dsave.text = "Guardar despliegue"
	b_dsave.pressed.connect(_save_deploy)
	dep_sec.add_child(b_dsave)
	var b_dreset := Button.new(); b_dreset.text = "Restaurar despliegue"
	b_dreset.pressed.connect(_reset_deploy)
	dep_sec.add_child(b_dreset)
	dep_sec.visible = false

	right.add_child(HSeparator.new())
	var b_save := Button.new(); b_save.text = "Guardar pieza"
	b_save.pressed.connect(_save)
	right.add_child(b_save)
	var b_reset := Button.new(); b_reset.text = "Restaurar por defecto"
	b_reset.pressed.connect(_reset)
	right.add_child(b_reset)
	var b_wipe := Widgets.danger("Borrar TODAS las sobrescrituras")
	b_wipe.pressed.connect(func():
		var dlg := ConfirmationDialog.new()
		dlg.title = "Borrar sobrescrituras"
		dlg.dialog_text = "¿Eliminar TODAS las piezas y despliegues personalizados de todas las facciones? No se puede deshacer."
		add_child(dlg)
		dlg.confirmed.connect(_wipe_all)
		dlg.canceled.connect(dlg.queue_free)
		dlg.popup_centered())
	right.add_child(b_wipe)
	right.add_child(HSeparator.new())
	status_lbl = Label.new()
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(status_lbl)
	_reload_pieces()


func _title(t: String) -> Label:
	return Widgets.lbl(t, 24)

func _lbl(t: String) -> Label:
	return Widgets.lbl(t, 13, true)

func _reload_pieces() -> void:
	faction = factions[opt_f.selected]
	opt_p.clear()
	for k in faction.pieces:
		var p: Dictionary = faction.pieces[k]
		opt_p.add_item("%s — %s" % [p.letter, p.name])
	_load_piece()
	_reload_deploy()

func _reload_deploy() -> void:
	# reconstruye la paleta de letras y carga el setup seleccionado
	for c in dep_pal.get_children(): c.queue_free()
	for k in faction.pieces:
		var p: Dictionary = faction.pieces[k]
		var b := Button.new()
		b.text = "%s — %s" % [p.letter, p.name]
		b.custom_minimum_size = Vector2(0, 24)
		var letra: String = p.letter
		b.pressed.connect(func(): dep_paint = letra)
		dep_pal.add_child(b)
	_load_deploy()

func _load_deploy() -> void:
	var idx: int = mini(opt_eq.selected, faction.setups.size() - 1)
	deploy_rows = faction.setups[idx].duplicate()
	dep_canvas.queue_redraw()

func _switch_mode() -> void:
	mode = "deploy" if opt_mode.selected == 1 else "moves"
	move_box.visible = mode == "moves"
	dep_canvas.visible = mode == "deploy"
	dep_sec.visible = mode == "deploy"
	opt_p.get_parent().visible = mode == "moves"  # selector de pieza
	status_lbl.text = "Modo despliegue: pinta las casillas iniciales." \
		if mode == "deploy" else ""

func on_deploy_cell(cell: Vector2i, button: int) -> void:
	if cell.y >= deploy_rows.size(): return
	# rellenar a 8 columnas: una fila corta hacía inmunes las
	# casillas a la derecha de su último carácter
	var row: String = deploy_rows[cell.y].rpad(8, ".")
	var ch := "." if button == MOUSE_BUTTON_RIGHT else dep_paint
	# reconstruye la fila sustituyendo la columna
	var parts := PackedStringArray()
	for i in row.length():
		parts.append(ch if i == cell.x else row.substr(i, 1))
	deploy_rows[cell.y] = "".join(parts)
	dep_canvas.queue_redraw()

func _save_deploy() -> void:
	var idx: int = mini(opt_eq.selected, faction.setups.size() - 1)
	faction.setups[idx] = deploy_rows.duplicate()
	var data := _saved_overrides()
	if not data.has(faction.id): data[faction.id] = {}
	if not data[faction.id].has("_setups"):
		data[faction.id]["_setups"] = {}
	data[faction.id]["_setups"][str(idx)] = deploy_rows.duplicate()
	_write(data)
	status_lbl.text = "Despliegue guardado."

func _reset_deploy() -> void:
	var data := _saved_overrides()
	if data.has(faction.id) and data[faction.id].has("_setups"):
		data[faction.id]["_setups"].erase(str(opt_eq.selected))
		if data[faction.id]["_setups"].is_empty():
			data[faction.id].erase("_setups")
	_write(data)
	var fresh := PiecesData.all()
	for i in factions.size():
		if fresh[i].id == faction.id:
			# conservar el ejército del Constructor (setups[2]): antes
			# la restauración lo borraba de memoria hasta el reinicio
			var custom: Variant = factions[i].setups[2] \
				if factions[i].setups.size() > 2 else null
			factions[i].setups = fresh[i].setups.duplicate()
			if custom != null: factions[i].setups.append(custom)
	_load_deploy()
	status_lbl.text = "Despliegue restaurado."

func _load_piece() -> void:
	var letters: Array = faction.pieces.keys()
	if opt_p.selected < 0 or opt_p.selected >= letters.size(): return
	piece_def = faction.pieces[letters[opt_p.selected]]
	cells = piece_def.cells.duplicate()
	leg2_cells = piece_def.get("leg2", {}).duplicate()
	name_edit.text = piece_def.name
	value_spin.value = int(piece_def.get("value", 0))
	sym_opt.select(1 if piece_def.get("sym", "all") == "lit" else 0)
	leader_chk.button_pressed = piece_def.get("leader", false)
	swap_chk.button_pressed = piece_def.get("swap_on_capture", false)
	castle_chk.button_pressed = piece_def.get("castle_partner", false)
	preview = false
	preview_moves = []
	canvas.queue_redraw()

## Rellena el mapa de casillas con un patrón clásico (sobreescribe
## lo pintado). 'j' salta obstáculos; 'o' mueve y captura; 'c' solo
## captura; 'm' solo mueve.
func _template(tname: String) -> void:
	cells.clear()
	var put := func(dx: int, dy: int, code: String) -> void:
		cells["%d,%d" % [dx, dy]] = code
	match tname:
		"Caballero":
			for d in [Vector2i(1,2),Vector2i(2,1),Vector2i(-1,2),
					Vector2i(-2,1),Vector2i(1,-2),Vector2i(2,-1),
					Vector2i(-1,-2),Vector2i(-2,-1)]:
				put.call(d.x, d.y, "J")
		"Arquero":
			# mueve 1 ortogonal, dispara (captura) a distancia 2
			for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),
					Vector2i(0,-1)]:
				put.call(d.x, d.y, "m")
			for dx in [-2,-1,0,1,2]:
				for dy in [-2,-1,0,1,2]:
					if maxi(absi(dx), absi(dy)) == 2:
						put.call(dx, dy, "c")
		"Torre":
			for n in range(1, 8):
				for d in [Vector2i(n,0),Vector2i(-n,0),
						Vector2i(0,n),Vector2i(0,-n)]:
					put.call(d.x, d.y, "o")
		"Alfil":
			for n in range(1, 8):
				for d in [Vector2i(n,n),Vector2i(-n,n),
						Vector2i(n,-n),Vector2i(-n,-n)]:
					put.call(d.x, d.y, "o")
		"Salto":
			for d in [Vector2i(1,2),Vector2i(2,1),Vector2i(-1,2),
					Vector2i(-2,1),Vector2i(1,-2),Vector2i(2,-1),
					Vector2i(-1,-2),Vector2i(-2,-1),
					Vector2i(2,0),Vector2i(-2,0),
					Vector2i(0,2),Vector2i(0,-2)]:
				put.call(d.x, d.y, "j")
		"Teleport":
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					if dx == 0 and dy == 0: continue
					put.call(dx, dy, "j")
	_refresh_preview()
	canvas.queue_redraw()
	status_lbl.text = "Plantilla «%s» aplicada — ajusta y guarda." \
		% tname

func on_cell(cell: Vector2i, button: int) -> void:
	if placing_piece:
		anchor = cell
		placing_piece = false
	elif button == MOUSE_BUTTON_LEFT:
		# "0,0" (la propia casilla) no existe en ningún tramo:
		# generaba un empuje degenerado de la pieza sobre sí misma
		if cell == anchor: return
		var off := cell - anchor
		_active_cells()["%d,%d" % [off.x, off.y]] = paint
	elif button == MOUSE_BUTTON_RIGHT:
		var off := cell - anchor
		_active_cells().erase("%d,%d" % [off.x, off.y])
	_refresh_preview()
	canvas.queue_redraw()

func _refresh_preview() -> void:
	if not preview: return
	_build_preview()

func _toggle_preview() -> void:
	preview = not preview
	if preview:
		_build_preview()
	canvas.queue_redraw()

func _build_preview() -> void:
	preview_moves = []
	# estado temporal con la pieza en 'anchor' y algunos enemigos de prueba
	var st := BoardState.new()
	var f0: Dictionary = {"pieces": {}, "color": Color.WHITE}
	var f1: Dictionary = {"pieces": {}, "color": Color.WHITE}
	st.factions = [f0, f1]
	var p := st.new_piece(_def_from_editor(), 0)
	st.set_at(anchor, p)
	# piezas enemigas de prueba para ver capturas/empujes
	var dummy_def := {"letter": "E", "name": "Dummy", "value": 1,
		"cells": {}, "sym": "lit"}
	for c in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(4, 2), Vector2i(5, 3)]:
		var e := st.new_piece(dummy_def, 1)
		st.set_at(c, e)
	for c in [Vector2i(6, 4), Vector2i(2, 5)]:
		var a := st.new_piece(dummy_def, 0)
		st.set_at(c, a)
	preview_moves = MoveGen.moves_for(st, anchor)

func _def_from_editor() -> Dictionary:
	var d := {"letter": piece_def.letter,
		"name": name_edit.text,
		"value": int(value_spin.value),
		"cells": cells.duplicate(),
		"sym": "lit" if sym_opt.selected == 1 else "all",
		"leader": leader_chk.button_pressed,
		"swap_on_capture": swap_chk.button_pressed,
		"castle_partner": castle_chk.button_pressed}
	# leg2 SIEMPRE se serializa (incluso {}): sin la clave, borrar el
	# 2º tramo se perdía al reiniciar — apply_overrides no copiaba
	# 'leg2' y el valor por defecto resucitaba
	d["leg2"] = leg2_cells.duplicate()
	return d

func _save() -> void:
	var data := _saved_overrides()
	if not data.has(faction.id): data[faction.id] = {}
	data[faction.id][piece_def.letter] = _def_from_editor()
	_write(data)
	_apply_to_memory()
	status_lbl.text = "Guardada. Activa al instante en nuevas partidas."

func _reset() -> void:
	var data := _saved_overrides()
	if data.has(faction.id):
		data[faction.id].erase(piece_def.letter)
		if data[faction.id].is_empty(): data.erase(faction.id)
	_write(data)
	_reload_defaults()
	status_lbl.text = "Restaurada a los valores por defecto."

func _wipe_all() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_reload_defaults()
	status_lbl.text = "Todas las sobrescrituras eliminadas."

func _reload_defaults() -> void:
	# reconstruye las facciones por defecto y recarga la pieza
	var fresh := PiecesData.all()
	for i in factions.size():
		factions[i] = fresh[i]
	faction = factions[opt_f.selected]
	_load_piece()

func _active_cells() -> Dictionary:
	return leg2_cells if editing_leg2 else cells

func _apply_to_memory() -> void:
	var d := _def_from_editor()
	for k in d:
		piece_def[k] = d[k]
	# leg2={} se aplica tal cual: un 2º tramo vacío = sin cadena
	# (erase() haría que el override no pudiera borrar el defecto)

## Lee el archivo de sobrescrituras tal cual (estático: lo usa la
## cfg online — los overrides viajan al rival, no solo aplican local).
static func load_overrides() -> Dictionary:
	var parsed = StatsStore.load_json(SAVE_PATH)
	return parsed if parsed is Dictionary else {}

func _saved_overrides() -> Dictionary:
	return load_overrides()

func _write(data: Dictionary) -> void:
	StatsStore.atomic_write(SAVE_PATH, JSON.stringify(data, "\t"))


## Carga sobrescrituras y las aplica a una lista de facciones recién creada.
static func apply_overrides(facs: Array) -> void:
	var parsed := load_overrides()
	if parsed.is_empty(): return
	apply_dict(facs, parsed)

## Aplica un dict de sobrescrituras explícito (archivo local o el
## 'ovr' que viaja en la cfg online — misma semántica).
static func apply_dict(facs: Array, parsed: Dictionary) -> void:
	for fac in facs:
		# el nivel raíz ya está validado; el interior también: un JSON
		# {"humenex": 3} o {"humenex": {"T": "x"}} crasheaba el arranque
		if not (parsed.get(fac.id) is Dictionary): continue
		for letter in parsed[fac.id]:
			if letter == "_setups":
				# sobrescrituras de posiciones iniciales {eq_idx: rows}
				var su: Variant = parsed[fac.id]["_setups"]
				if not (su is Dictionary): continue
				for eq in su:
					var i := int(eq)
					if i < fac.setups.size() and su[eq] is Array:
						fac.setups[i] = su[eq]
				continue
			if not fac.pieces.has(letter): continue
			if not (parsed[fac.id][letter] is Dictionary): continue
			var o: Dictionary = parsed[fac.id][letter]
			var p: Dictionary = fac.pieces[letter]
			for k in o:
				if k == "cells" and o.cells is Dictionary:
					var cd := {}
					for ck in o.cells: cd[ck] = o.cells[ck]
					cd.erase("0,0")   # ver on_cell: celda degenerada
					p.cells = cd
				elif k == "leg2" and o.leg2 is Dictionary:
					var l2 := {}
					for ck in o.leg2: l2[ck] = o.leg2[ck]
					l2.erase("0,0")
					p["leg2"] = l2
				elif k != "cells" and k != "leg2":
					p[k] = o[k]
