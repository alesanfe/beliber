class_name BoardState
extends RefCounted

## Estado puro del tablero 8x8. Sin nodos: testeable y reutilizable por la IA.

const SIZE := 8

# grid[y][x] -> Dictionary pieza o null
# pieza: {def:Dictionary, owner:int, has_moved:bool, immobilized:int,
#         cells_override:Dictionary (Consorte)}
var grid: Array = []
var factions: Array = []      # FactionDef (Dictionary) por jugador 0/1
var last_move: Dictionary = {}  # {piece, from, to, double_step}
# (move_log eliminado: write-only, se duplicaba en CADA snapshot —
#  O(n²) de memoria en partidas largas sin ningún lector)

static func idx(c: Vector2i) -> int:
	return c.y * SIZE + c.x

static func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < SIZE and c.y >= 0 and c.y < SIZE

func _init() -> void:
	grid.resize(SIZE * SIZE)
	grid.fill(null)

func at(c: Vector2i) -> Variant:
	if not inside(c): return null
	return grid[idx(c)]

func set_at(c: Vector2i, p: Variant) -> void:
	grid[idx(c)] = p

func new_piece(def: Dictionary, owner: int) -> Dictionary:
	return {"def": def, "owner": owner, "has_moved": false,
		"immobilized": 0, "cells_override": {}}

## Dirección "hacia adelante" del jugador (player 0 abajo → -y).
static func fwd(owner: int) -> int:
	return -1 if owner == 0 else 1

## Rota un offset local (frente = -y) al espacio del jugador.
static func orient(d: Vector2i, owner: int) -> Vector2i:
	return d if owner == 0 else Vector2i(-d.x, -d.y)

## Coloca un ejército: setup = filas de texto del diagrama de despliegue
## (8 columnas, '.' = vacío). La última fila del diagrama = fila trasera
## del jugador (y=7 para J0). El rival se despliega rotado 180°.
func deploy(faction: Dictionary, owner: int, eq: int) -> void:
	var rows: Array = faction.setups[mini(eq, faction.setups.size() - 1)]
	var h := rows.size()
	for j in h:
		var row: String = rows[j]
		# la fila h-1 del diagrama es la base propia (y=7 para J0)
		var dy: int = SIZE - h + j
		# setup JSON custom con más de SIZE filas → dy negativo y
		# set_at indexaba fuera del grid
		if dy < 0 or dy >= SIZE: continue
		for x in mini(row.length(), SIZE):
			var letter := row.substr(x, 1)
			if letter == "." or letter == " ": continue
			var cell := Vector2i(x, dy) if owner == 0 \
				else Vector2i(SIZE - 1 - x, SIZE - 1 - dy)
			var def: Dictionary = faction.pieces.get(letter, {})
			if def.is_empty():
				push_warning("Letra de despliegue desconocida: %s (%s)" % [
					letter, faction.id])
				continue
			set_at(cell, new_piece(def, owner))

## Snapshot completo para deshacer (las defs de pieza se comparten).
func snapshot() -> Dictionary:
	var g := []
	g.resize(grid.size())
	for i in grid.size():
		g[i] = grid[i].duplicate(true) if grid[i] != null else null
	return {"grid": g, "last_move": last_move.duplicate()}

func restore(s: Dictionary) -> void:
	grid = s.grid
	last_move = s.last_move
	# last_move.piece del snapshot apunta a una instancia antigua —
	# reanclar a la pieza restaurada realmente en 'to' (al paso)
	if not last_move.is_empty() and last_move.get("to") != null:
		var pc: Variant = at(last_move.to)
		if pc != null: last_move["piece"] = pc

func leaders_alive(owner: int) -> int:
	var n := 0
	for p in grid:
		if p != null and p.owner == owner and p.def.get("leader", false):
			n += 1
	return n

## Aplica un movimiento completo (incluye efectos y sub-movimientos).
func apply(mv: Dictionary) -> void:
	_apply_leg(mv)
	# en una cadena (leg2/Tritón) la pieza termina en second.to: marcar
	# has_moved y last_move sobre mv.to dejaba la pieza "virgen" y un
	# last_move.piece nulo (al paso falso, enroque/doble paso infinitos)
	var last_to: Vector2i = mv.to
	var second: Variant = mv.get("second")
	if second != null:
		_apply_leg(second)
		last_to = second.to
	var piece: Variant = at(last_to)
	if piece != null:
		piece.has_moved = true
	last_move = {"piece": piece, "from": mv.from, "to": last_to,
		"double_step": mv.get("double_step", false)}

func _apply_leg(mv: Dictionary) -> void:
	# capturas directas (incluye al paso y arrolladas por empuje)
	for c in mv.get("captures", []):
		set_at(c, null)
	var piece: Variant = at(mv.from)
	# atraer: retirar al ocupante del destino (se coloca tras mover)
	var pulled: Variant = null
	if mv.has("attract"):
		pulled = at(mv.attract.from)
		set_at(mv.attract.from, null)
	# empujar: el ocupante del destino se mueve a push_to
	if mv.has("push"):
		var pu: Dictionary = mv.push
		var pushed: Variant = at(pu.from)
		set_at(pu.from, null)
		set_at(pu.to, pushed)
	# mover la pieza
	set_at(mv.from, null)
	set_at(mv.to, piece)
	# colocar la pieza atraída en la casilla vacía junto a la nuestra
	if pulled != null:
		set_at(mv.attract.to, pulled)
		if pulled.owner != piece.owner:
			pulled.immobilized = 1
	# inmovilizar piezas atravesadas
	for c in mv.get("immobilize", []):
		var p: Variant = at(c)
		if p != null: p.immobilized = 1
	# enroque
	if mv.has("castle"):
		var ca: Dictionary = mv.castle
		var rook: Variant = at(ca.from)
		set_at(ca.from, null)
		set_at(ca.to, rook)
		if rook != null: rook.has_moved = true
	# Consorte: adopta el mapa de casillas de la pieza capturada
	if piece != null and piece.def.get("swap_on_capture", false) \
			and mv.get("captured_def") != null:
		piece.cells_override = mv.captured_def.cells

func describe(mv: Dictionary) -> String:
	var s := "%s%s→%s" % [mv.piece_letter, _sq(mv.from), _sq(mv.to)]
	if mv.get("captures", []).size() > 0: s += " x"
	if mv.has("castle"): s += " (enroque)"
	if mv.has("second"):
		s += " +" + _sq(mv.second.to)
		# las capturas del 2º tramo también son capturas en notación
		if mv.second.get("captures", []).size() > 0: s += " x"
	return s

static func _sq(c: Vector2i) -> String:
	return "%c%d" % [97 + c.x, SIZE - c.y]

## ===== BEL-FEN: serialización compacta de posición =====
## Formato: "BEL1 <f0>.<eq0> <f1>.<eq1> <filas> <turno>"
## filas: 8 filas separadas por '/', dígitos = casillas vacías,
## MAYÚSCULA = pieza de J0, minúscula = pieza de J1, '*' tras la letra
## = la pieza ya se movió. Análogo al FEN del ajedrez estándar.

static func to_bel(state: BoardState, fi0: int, eq0: int,
		fi1: int, eq1: int, turn: int) -> String:
	var rows := []
	for y in SIZE:
		var row := ""
		var empty := 0
		for x in SIZE:
			var p: Variant = state.at(Vector2i(x, y))
			if p == null:
				empty += 1
				continue
			if empty > 0:
				row += str(empty); empty = 0
			var l: String = p.def.letter
			row += l if p.owner == 0 else l.to_lower()
			if p.has_moved: row += "*"
		if empty > 0: row += str(empty)
		rows.append(row)
	return "BEL1 %d.%d %d.%d %s %d" % [
		fi0, eq0, fi1, eq1, "/".join(rows), turn]

## Devuelve {fac:[fi0,eq0,fi1,eq1], pos:[{x,y,l,o,has_moved}],
## turn} o {"err": ...}.
static func from_bel(s: String) -> Dictionary:
	var parts := s.strip_edges().split(" ", false)
	if parts.size() < 5 or parts[0] != "BEL1":
		return {"err": "formato: BEL1 <f0>.<eq0> <f1>.<eq1> <filas> <turno>"}
	var f0 := parts[1].split("."); var f1 := parts[2].split(".")
	# campos de facción/equipo obligatorios ("0.0"): antes un campo
	# sin punto indexaba fuera de rango y tumbaba el editor
	if f0.size() != 2 or f1.size() != 2:
		return {"err": "facciones malformadas: se esperaba <f>.<eq>"}
	for f in f0 + f1:
		if not f.is_valid_int():
			return {"err": "facción/equipo no numérico: '%s'" % f}
	var pos := []
	var y := 0
	for row in parts[3].split("/"):
		var x := 0
		var prev: Dictionary = {}
		for ch in row:
			if ch.is_valid_int():
				x += int(ch)
			elif ch == "*":
				if not prev.is_empty(): prev.has_moved = true
			else:
				var l := ch.to_upper()
				var o := 0 if ch == l else 1
				prev = {"x": x, "y": y, "l": l, "o": o}
				pos.append(prev)
				x += 1
		if x > SIZE:
			return {"err": "fila %d desborda el tablero (%d celdas)" % [
				y + 1, x]}
		y += 1
	if y != SIZE:
		return {"err": "se esperaban 8 filas, hay %d" % y}
	if not parts[4].is_valid_int() or int(parts[4]) not in [0, 1]:
		return {"err": "turno inválido: '%s'" % parts[4]}
	return {"fac": [int(f0[0]), int(f0[1]), int(f1[0]), int(f1[1])],
		"pos": pos, "turn": int(parts[4])}
