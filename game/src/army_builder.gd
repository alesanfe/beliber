class_name ArmyBuilder
extends Control

## Constructor de ejércitos (estilo Chess Evolved Online).
## Coloca piezas de la facción en la zona de despliegue (5 filas propias)
## con presupuesto de puntos. Guarda en user://beliber_armies.json.

const SAVE_PATH := "user://beliber_armies.json"
const CELL := 56
const ROWS := 5

var factions: Array = []
var faction: Dictionary
var grid := {}          # Vector2i(col,fila 0=top) -> letra
var paint := "P"
var budget := 60        # presupuesto por defecto ≈ suma del setup oficial

var opt_f: OptionButton
var budget_spin: SpinBox
var cost_lbl: Label
var comp_lbl: Label
var bars := {}          # métrica -> [barra custom, barra oficial]
var pal: GridContainer  # paleta de letras de piezas
var canvas: ABCanvas

class ABCanvas extends Control:
	var ab: ArmyBuilder
	var font := ThemeDB.fallback_font

	func _init(p_ab: ArmyBuilder) -> void:
		ab = p_ab
		custom_minimum_size = Vector2(CELL * 8, CELL * ROWS)

	func _draw() -> void:
		for y in ROWS:
			for x in 8:
				var r := Rect2(x * CELL, y * CELL, CELL, CELL)
				var dark := (x + y) % 2 == 0
				draw_rect(r, Color(0.14, 0.16, 0.2) if dark
					else Color(0.23, 0.26, 0.32))
				var cell := Vector2i(x, y)
				if ab.grid.has(cell):
					var letter: String = ab.grid[cell]
					var def: Dictionary = ab.faction.pieces.get(letter, {})
					var fc: Color = ab.faction.color
					draw_rect(r.grow(-5), fc.darkened(0.55))
					draw_rect(r.grow(-5), fc, false, 2.0)
					var ts := font.get_string_size(letter,
						HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
					draw_string(font, r.get_center() + Vector2(-ts.x/2, ts.y/3),
						letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
					if def.get("leader", false):
						draw_circle(r.get_center() + Vector2(0, -CELL*0.32),
							5.0, Color(1, 0.85, 0.2))
		# etiquetas de filas
		draw_string(font, Vector2(4, -6), "zona de despliegue (filas propias)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.6))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			var cell := Vector2i(int(e.position.x / CELL),
				int(e.position.y / CELL))
			if cell.x < 0 or cell.x > 7 or cell.y < 0 or cell.y >= ROWS:
				return
			ab.on_cell(cell, e.button_index)

func _init(p_factions: Array) -> void:
	factions = p_factions

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# sin margen el texto de la columna izquierda se corta en el
	# borde de la ventana ("onstructor de ejército")
	root.offset_left = 12
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	root.add_child(left)
	# hueco para el botón "← Volver" (absolute en 8,8 sobre esta UI)
	var pad := Control.new()
	pad.custom_minimum_size.y = 36
	left.add_child(pad)
	var t := Label.new()
	t.text = "Constructor de ejército"
	t.add_theme_font_size_override("font_size", 24)
	left.add_child(t)

	opt_f = OptionButton.new()
	for i in factions.size():
		opt_f.add_item(factions[i].name)
	opt_f.item_selected.connect(func(_i): _reload())
	left.add_child(opt_f)

	left.add_child(_lbl("Piezas (clic izq coloca, der borra)"))
	pal = GridContainer.new()
	pal.columns = 2
	left.add_child(pal)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var cv := VBoxContainer.new()
	center.add_child(cv)
	canvas = ABCanvas.new(self)
	cv.add_child(canvas)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 0)
	root.add_child(right)
	right.add_child(_lbl("Presupuesto de puntos"))
	budget_spin = SpinBox.new()
	budget_spin.min_value = 10; budget_spin.max_value = 200
	budget_spin.value = 60
	budget_spin.value_changed.connect(func(_v): _update_cost())
	right.add_child(budget_spin)
	cost_lbl = Label.new()
	right.add_child(cost_lbl)
	var b_eq := Button.new(); b_eq.text = "Copiar setup oficial"
	b_eq.pressed.connect(_copy_official)
	right.add_child(b_eq)
	var b_clear := Button.new(); b_clear.text = "Vaciar"
	b_clear.pressed.connect(func(): grid.clear(); _update_cost())
	right.add_child(b_clear)
	right.add_child(HSeparator.new())
	var b_save := Button.new(); b_save.text = "Guardar como Eq personalizado"
	b_save.pressed.connect(_save)
	right.add_child(b_save)
	var b_load := Button.new(); b_load.text = "Cargar guardado"
	b_load.pressed.connect(_load)
	right.add_child(b_load)
	# comparador + métricas aproximadas vs el despliegue oficial
	right.add_child(HSeparator.new())
	right.add_child(_lbl("vs. despliegue oficial (Eq1)"))
	comp_lbl = _lbl("")
	right.add_child(comp_lbl)
	for m in ["Agresión", "Movilidad", "Control", "Resistencia"]:
		right.add_child(_lbl(m))
		var bc := ProgressBar.new()
		bc.max_value = 100; bc.show_percentage = false
		bc.custom_minimum_size = Vector2(0, 10)
		right.add_child(bc)
		var bo := ProgressBar.new()
		bo.max_value = 100; bo.show_percentage = false
		bo.custom_minimum_size = Vector2(0, 6)
		bo.modulate.a = 0.4   # tenue = ejército oficial
		right.add_child(bo)
		bars[m] = [bc, bo]

	# palette se construye en _reload
	_reload()

func _lbl(t: String) -> Label:
	return Widgets.lbl(t, 13, true)

func _reload() -> void:
	faction = factions[opt_f.selected]
	for ch in pal.get_children(): ch.queue_free()
	for letter in faction.pieces:
		var p: Dictionary = faction.pieces[letter]
		var b := Button.new()
		b.text = "%s %s (%d)" % [letter, p.name, p.get("value", 0)]
		# nombres de piezas custom pueden desbordar la columna de 280px
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = "%s — %s (valor %d)" % [
			letter, p.name, p.get("value", 0)]
		b.custom_minimum_size.x = 132
		b.pressed.connect(func(): paint = letter)
		pal.add_child(b)
	# presupuesto por defecto = valor del ejército oficial
	budget_spin.value = PiecesData.army_value(faction, 0)
	_copy_official()

func _copy_official() -> void:
	grid.clear()
	var rows: Array = faction.setups[0]
	var h := rows.size()
	for j in h:
		var row: String = rows[j]
		var y := ROWS - h + j   # alinear abajo
		for x in mini(row.length(), 8):
			var ch := row.substr(x, 1)
			if ch != "." and ch != " ":
				grid[Vector2i(x, y)] = ch
	_update_cost()

func cost() -> int:
	var total := 0
	for cell in grid:
		var def: Dictionary = faction.pieces.get(grid[cell], {})
		total += int(def.get("value", 0))
	return total

func leaders() -> int:
	var n := 0
	for cell in grid:
		if faction.pieces.get(grid[cell], {}).get("leader", false):
			n += 1
	return n

func _update_cost() -> void:
	var c := cost()
	var l := leaders()
	cost_lbl.text = "Coste: %d / %d   Líderes: %d" % [c, int(budget_spin.value), l]
	cost_lbl.add_theme_color_override("font_color",
		Color(0.4, 1, 0.4) if c <= budget_spin.value and l >= 1
		else Color(1, 0.4, 0.4))
	_update_compare()
	canvas.queue_redraw()

## Letras del despliegue oficial (setups[0]) como lista.
func _official_letters() -> Array:
	var out := []
	for row in faction.setups[0]:
		for i in row.length():
			var ch: String = row.substr(i, 1)
			if ch != "." and ch != " ": out.append(ch)
	return out

## Métricas aproximadas (heurística Betza-like): agresión = potencial
## de captura, movilidad = casillas alcanzables, control = cobertura +
## efectos (empujar/atraer), resistencia = valor + líderes.
static func _metrics(fac: Dictionary, letters: Array) -> Dictionary:
	var caps := 0.0
	var moves := 0.0
	var cover := {}
	var special := 0.0
	var val := 0.0
	var nlead := 0
	for ch in letters:
		var p: Dictionary = fac.pieces.get(ch, {})
		if p.is_empty(): continue
		val += int(p.get("value", 0))
		if p.get("leader", false): nlead += 1
		for key in p.get("cells", {}):
			var code: String = p.cells[key]
			var fx := PiecesData.code_fx(code)
			var parts: PackedStringArray = key.split(",")
			var d := Vector2i(int(parts[0]), int(parts[1]))
			cover[key] = true
			var w := 1.0 + maxi(absi(d.x), absi(d.y)) * 0.15
			if fx & FX.CAPTURE: caps += w
			if fx & FX.MOVE: moves += w
			if fx & (FX.JUMP | FX.ATRAVESAR): moves += 0.5
			if fx & (FX.EMPUJAR | FX.ATRAER): special += 1.5
	return {
		"Agresión": caps * 2.2,
		"Movilidad": moves * 1.8,
		"Control": cover.size() * 0.9 + special * 4.0,
		"Resistencia": val * 1.2 + nlead * 8.0,
	}

## Compara el grid actual con el setup oficial y refresca las barras.
func _update_compare() -> void:
	var cur := []
	for cell in grid: cur.append(grid[cell])
	var off := _official_letters()
	# diferencias pieza a pieza (conteo por letra)
	var cnt := {}
	for ch in cur: cnt[ch] = int(cnt.get(ch, 0)) + 1
	for ch in off: cnt[ch] = int(cnt.get(ch, 0)) - 1
	var diff := []
	for ch in cnt:
		var n: int = cnt[ch]
		if n > 0: diff.append("+%s×%d" % [ch, n])
		elif n < 0: diff.append("-%s×%d" % [ch, -n])
	var val_off := 0
	for ch in off: val_off += int(
		faction.pieces.get(ch, {}).get("value", 0))
	var l_off := 0
	for ch in off:
		if faction.pieces.get(ch, {}).get("leader", false): l_off += 1
	comp_lbl.text = "Valor: %d vs %d (%+d)\nLíderes: %d vs %d\n%s" % [
		cost(), val_off, cost() - val_off, leaders(), l_off,
		"Cambios: " + ", ".join(diff) if not diff.is_empty()
			else "Idéntico al oficial"]
	var mc := _metrics(faction, cur)
	var mo := _metrics(faction, off)
	for m in bars:
		bars[m][0].value = clampf(float(mc[m]), 0, 100)
		bars[m][1].value = clampf(float(mo[m]), 0, 100)

func on_cell(cell: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		grid[cell] = paint
	elif button == MOUSE_BUTTON_RIGHT:
		grid.erase(cell)
	_update_cost()

func _to_rows() -> Array:
	var rows: Array[String] = []
	for y in ROWS:
		var s := ""
		for x in 8:
			s += grid.get(Vector2i(x, y), ".")
		rows.append(s)
	return rows

func _save() -> void:
	if leaders() < 1:
		cost_lbl.text = "¡Necesitas al menos 1 líder!"
		return
	if cost() > budget_spin.value:
		cost_lbl.text = "¡Sobre el presupuesto!"
		return
	var data := _load_all()
	data[faction.id] = {"rows": _to_rows(), "budget": int(budget_spin.value)}
	StatsStore.atomic_write(SAVE_PATH, JSON.stringify(data, "\t"))
	cost_lbl.text = "Guardado. Disponible como 'Personalizado' al elegir equipo."

func _load() -> void:
	var data := _load_all()
	# JSON semi-válido: {"humenex": 3} o sin 'rows' crasheaba al abrir
	if not (data.get(faction.id) is Dictionary): return
	if not (data[faction.id].get("rows") is Array): return
	grid.clear()
	var rows: Array = data[faction.id].rows
	for y in mini(rows.size(), ROWS):
		if not (rows[y] is String): continue
		for x in mini(rows[y].length(), 8):
			var ch: String = rows[y].substr(x, 1)
			if ch != "." and ch != " ":
				grid[Vector2i(x, y)] = ch
	_update_cost()

static func _load_all() -> Dictionary:
	var parsed = StatsStore.load_json(SAVE_PATH)
	return parsed if parsed is Dictionary else {}

## Inserta las filas como un setup cualquiera (idx). Escribir en el
## índice del equipo elegido es lo que permite que los despliegues
## editados (Eq1/Eq2) también viajen por la red, no solo el custom.
static func inject_at(fac: Dictionary, rows: Array, idx: int) -> void:
	while fac.setups.size() <= idx: fac.setups.append([])
	fac.setups[idx] = rows

## Inserta (o sustituye) las filas custom como setups[2] (Eq3).
## Compartido por la carga local, el host autoritativo y el cliente WS.
static func inject(fac: Dictionary, rows: Array) -> void:
	inject_at(fac, rows, 2)

## Aplica ejércitos personalizados: se insertan como setups[2] (Eq3).
static func apply(facs: Array) -> void:
	var data := _load_all()
	for fac in facs:
		# mismo patrón: raíz validada, interior no — un JSON
		# {"humenex": 3} rompía el arranque (llamada en _ready)
		if not (data.get(fac.id) is Dictionary): continue
		if not (data[fac.id].get("rows") is Array): continue
		var rows: Array = []
		for r in data[fac.id].rows:
			if r is String: rows.append(r)
		if not rows.is_empty():
			inject(fac, rows)
