class_name PiecesData
extends RefCounted

## Definición data-driven de las 8 facciones de Beliber.
##
## MODELO: cada pieza es un MAPA DE CASILLAS —idéntico a los diagramas de
## referencia—. "cells" es un Dictionary: "dx,dy" (offset desde la pieza,
## frente = -y) → código de efecto. El mapa se pinta SOLO en la orientación
## del diagrama; la expansión se hace con "sym" en tiempo de generación:
##   "all" = las 8 transformaciones diédricas (patrón radial, pieza dibujada
##           en la esquina inferior derecha del diagrama)
##   "lit" = literal, solo rotado 180° para el jugador 1 (patrón dirigido,
##           pieza dibujada en mitad de tablero)
##
## Códigos (letra → efecto, siguiendo la leyenda de colores):
##   m amarillo   Mover                    c rojo       Capturar
##   o naranja    Mover o Capturar         j cian       Mover saltando
##   g lima       Capturar saltando        J morado     Mover/Capturar saltando
##   t oliva      Mover atravesando        T rojo osc   Capturar atravesando
##   w verdeosc   M/C atravesando          p teal       Mover o Empujar
##   P magenta    Capturar o Empujar       3 azul osc   M/C/Empujar
##   e azul       Empujar                  a magenta2   Atraer
##   E rosa       Capturar / al paso       d verdecl    Despliegue
##   k/K verde    Enroque                  q/Q marrón   Salto de Aquonte
##
## DESPLIEGUES: "setups" son filas de texto del diagrama (8 columnas,
## '.'=vacío). Se anclan a la base del jugador y se rotan 180° para el rival.

static func code_fx(ch: String) -> int:
	match ch:
		"m": return FX.MOVE
		"c": return FX.CAPTURE
		"o": return FX.MOVE | FX.CAPTURE
		"j": return FX.MOVE | FX.JUMP
		"g": return FX.CAPTURE | FX.JUMP
		"J": return FX.MOVE | FX.CAPTURE | FX.JUMP
		"t": return FX.MOVE | FX.ATRAVESAR
		"T": return FX.CAPTURE | FX.ATRAVESAR
		"w": return FX.MOVE | FX.CAPTURE | FX.ATRAVESAR
		"p": return FX.MOVE | FX.EMPUJAR
		"P": return FX.CAPTURE | FX.EMPUJAR
		"3": return FX.MOVE | FX.CAPTURE | FX.EMPUJAR
		"e": return FX.EMPUJAR
		"a": return FX.ATRAER
		"E": return FX.CAPTURE
		"d": return FX.MOVE
		"k": return FX.MOVE
		"K": return FX.MOVE | FX.CAPTURE
		"q": return FX.MOVE
		"Q": return FX.MOVE | FX.CAPTURE
	return 0

static func code_cond(ch: String) -> int:
	match ch:
		"E": return FX.C_EN_PASSANT
		"d": return FX.C_DEPLOY
		"k", "K": return FX.C_CASTLE
		"q", "Q": return FX.C_AQUONTE
	return FX.C_NONE

static func code_color(ch: String) -> Color:
	match ch:
		"m": return FX.COL.MOVE
		"c": return FX.COL.CAPTURE
		"o": return FX.COL.MOVE_OR_CAPTURE
		"j": return FX.COL.MOVE_JUMP
		"g": return FX.COL.CAPTURE_JUMP
		"J": return FX.COL.BOTH_JUMP
		"t": return FX.COL.MOVE_ATRAV
		"T": return FX.COL.CAPTURE_ATRAV
		"w": return FX.COL.BOTH_ATRAV
		"p": return FX.COL.MOVE_PUSH
		"P": return FX.COL.CAPTURE_PUSH
		"3": return FX.COL.MCP
		"e": return FX.COL.EMPUJAR
		"a": return FX.COL.ATRAER
		"E": return FX.COL.EN_PASSANT
		"d": return FX.COL.DEPLOY
		"k", "K": return FX.COL.CASTLE
		"q": return FX.COL.AQUONTE
		"Q": return FX.COL.AQUONTE.darkened(0.25)
	return Color.BLACK

## Glifo de ajedrez Unicode según el patrón de movimiento de la pieza.
static func chess_glyph(def: Dictionary) -> String:
	if def.get("leader", false): return "\u265A"
	var cells: Dictionary = def.cells
	var ortho_max := 0
	var diag_max := 0
	var has_leap := false
	for key in cells:
		var parts: PackedStringArray = key.split(",")
		var d := Vector2i(int(parts[0]), int(parts[1]))
		var code: String = cells[key]
		var can_act := code in ["m","c","o","j","g","J","t","T","w",
			"p","P","3","q","Q","e","a","E"]
		if not can_act: continue
		var alineado: bool = d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y)
		if not alineado:
			has_leap = true
			continue
		var steps := maxi(absi(d.x), absi(d.y))
		if steps <= 1 and code in ["j","g","J"]:
			has_leap = true
			continue
		if d.x == 0 or d.y == 0:
			ortho_max = maxi(ortho_max, steps)
		else:
			diag_max = maxi(diag_max, steps)
	if ortho_max >= 3 and diag_max >= 3: return "\u265B"   # dama
	if has_leap and ortho_max <= 2 and diag_max <= 2: return "\u265E"  # caballo
	if diag_max >= 3 and ortho_max < 3: return "\u265D"    # alfil
	if ortho_max >= 3: return "\u265C"                     # torre
	if has_leap: return "\u265E"
	return "\u265F"                                        # peón

const CODE_NAMES := {
	"m": "Mover", "c": "Capturar", "o": "Mover o Capturar",
	"j": "Mover saltando", "g": "Capturar saltando",
	"J": "Mover/Capturar saltando",
	"t": "Mover atravesando", "T": "Capturar atravesando",
	"w": "Mover/Capturar atravesando",
	"p": "Mover o Empujar", "P": "Capturar o Empujar",
	"3": "Mover/Capturar/Empujar", "e": "Empujar", "a": "Atraer",
	"E": "Capturar / al paso", "d": "Despliegue", "k": "Enroque",
	"K": "M/C o Enroque", "q": "Salto de Aquonte", "Q": "M/C o Aquonte",
}

# ---------------------------------------------------------------- helpers
static func _cells(list: Array) -> Dictionary:
	var d := {}
	for e in list:
		d["%d,%d" % [e[0].x, e[0].y]] = e[1]
	return d

static func _ray(unit: Vector2i, codes: Array, start := 1) -> Dictionary:
	var d := {}
	for i in codes.size():
		var cell: Vector2i = unit * (start + i)
		d["%d,%d" % [cell.x, cell.y]] = codes[i]
	return d

static func _leap(d: Vector2i, code: String) -> Dictionary:
	return {"%d,%d" % [d.x, d.y]: code}

static func _leaps(units: Array, code: String) -> Dictionary:
	var d := {}
	for u in units:
		d["%d,%d" % [u.x, u.y]] = code
	return d

static func _mrg(list: Array) -> Dictionary:
	var d := {}
	for a in list:
		for k in a: d[k] = a[k]
	return d

static func _pc(letter: String, nombre: String, valor: int, cells: Dictionary,
		extra := {}) -> Dictionary:
	var p := {"letter": letter, "name": nombre, "value": valor,
		"cells": cells, "sym": "all"}
	for k in extra: p[k] = extra[k]
	return p

static func _faction(id: String, nombre: String, color: Color, pieces: Array,
		setups: Array, reglas := {}) -> Dictionary:
	var map := {}
	for p in pieces:
		p["fid"] = id   # para i18n: PIECE_<fid>_<letter>
		map[p.letter] = p
	return {"id": id, "name": nombre, "color": color, "pieces": map,
		"setups": setups, "rules": reglas}

## Nombre localizado de una facción (FAC_<ID> en ui.csv; el campo
## 'name' del dict queda como fallback español para piezas custom).
static func fac_name(f: Dictionary) -> String:
	var k := "FAC_" + String(f.get("id", "")).to_upper()
	var t := Lang.t(k)
	return t if t != k else String(f.get("name", "?"))

## Igual pero con el id suelto ("humenex" → FAC_HUMENEX → "Humenex").
static func fac_name_id(fid: String) -> String:
	var k := "FAC_" + fid.to_upper()
	var t := Lang.t(k)
	return t if t != k else fid.capitalize()

## Nombre localizado de una pieza (PIECE_<FID>_<LETRA>).
static func piece_name(p: Dictionary) -> String:
	var k := "PIECE_%s_%s" % [
		String(p.get("fid", "")).to_upper(), String(p.letter)]
	var t := Lang.t(k)
	return t if t != k else String(p.get("name", "?"))

## Arquetipo de facción localizado (STYLE_<ID> — antes el dict STYLES
## era español puro).
static func style_of(f: Dictionary) -> String:
	var k := "STYLE_" + String(f.get("id", "")).to_upper()
	var t := Lang.t(k)
	return t if t != k else String(STYLES.get(f.get("id", ""), ""))

## Nombre localizado de un efecto de casilla (FX_<código>; el código es
## case-sensitive — 'p' empuja y 'P' captura/empuja, no se normaliza).
static func code_name(ch: String) -> String:
	var k := "FX_" + ch
	var t := Lang.t(k)
	return t if t != k else String(CODE_NAMES.get(ch, ch))

## Arquetipo de juego de cada facción (estilo Duelyst/Root): cómo se
## siente jugarla, mostrado en el menú.
const STYLES := {
	"humenex": "Clásico equilibrado: enroque, al paso y doble apertura",
	"elfos": "Control móvil: atraviesan líneas, abren siempre ellos",
	"mortifers": "Combo corruptor: el Consorte copia lo que captura",
	"bestiarios": "Horda de saltos: dos líderes, presión por saltos",
	"enanos": "Empuje y atrincheramiento: capturan al empujar",
	"chlontos": "Asedio aéreo: capturas y saltos de largo alcance",
	"aquontes": "Avalancha: saltos encadenados y salto de Aquonte",
	"kronturs": "Muro y martillo: empujan y capturan a la vez",
}

## Personalidad de la IA por facción (Clockwork de Root): el bot
## "Auto" adopta el estilo que encaja con el arquetipo de cada raza.
const FACTION_STYLE := {
	"humenex": "normal",     # clásico equilibrado
	"elfos": "normal",       # control móvil
	"mortifers": "aggro",    # busca capturas para el combo del Consorte
	"bestiarios": "aggro",   # horda: presión constante por saltos
	"enanos": "defense",     # atrincheramiento
	"chlontos": "normal",    # asedio posicional de largo alcance
	"aquontes": "aggro",     # avalancha
	"kronturs": "defense",   # muro primero, martillo después
}

## Valor total de un despliegue (suma de valores de las piezas colocadas).
static func army_value(fac: Dictionary, eq: int) -> int:
	var total := 0
	for row in fac.setups[mini(eq, fac.setups.size() - 1)]:
		for ch in row:
			if ch != "." and fac.pieces.has(ch):
				total += int(fac.pieces[ch].get("value", 0))
	return total

static func all() -> Array[Dictionary]:
	return [_humenex(), _elfos(), _mortifers(), _bestiarios(),
		_enanos(), _chlontos(), _aquontes(), _kronturs()]

## ---------------------------------------------------------------- facciones
## Transcripción celda a celda de los diagramas y tableros de despliegue.

static func _humenex() -> Dictionary:
	var peon := _pc("P", "Peón", 1, _cells([
		[Vector2i(0, -1), "m"], [Vector2i(0, -2), "d"],
		[Vector2i(-1, -1), "E"], [Vector2i(1, -1), "E"],
	]), {"sym": "lit"})
	var emperatriz := _pc("X", "Emperatriz", 8,
		_mrg([_ray(Vector2i(1, 0), ["o","o","o","o","o","o","o"]),
			_ray(Vector2i(1, 1), ["o","o","o","o","o","o","o"])]))
	var emperador := _pc("Y", "Emperador", 0,
		_mrg([_cells([[Vector2i(-1, -1), "o"], [Vector2i(0, -1), "o"],
				[Vector2i(1, -1), "o"]]),
			_cells([[Vector2i(-1, 0), "K"], [Vector2i(1, 0), "K"]]),
			_cells([[Vector2i(-4, 0), "k"], [Vector2i(-3, 0), "k"],
				[Vector2i(-2, 0), "k"], [Vector2i(2, 0), "k"],
				[Vector2i(3, 0), "k"], [Vector2i(4, 0), "k"]])]),
		{"leader": true, "sym": "lit"})
	var espia := _pc("E", "Espía", 3,
		_ray(Vector2i(1, 1), ["o","o","o","o","o","o","o"]))
	var caballero := _pc("C", "Caballero", 3, _leap(Vector2i(1, 2), "J"))
	var torre := _pc("T", "Torre", 5,
		_ray(Vector2i(1, 0), ["o","o","o","o","o","o","o"]),
		{"castle_partner": true})
	return _faction("humenex", "Humenex", Color(0.3, 0.6, 1.0),
		[peon, emperatriz, emperador, espia, caballero, torre],
		[[
			"........",
			"...PP...",
			"..C.ECP.",
			"PPP..PEP",
			".YT.X..T",
		], [
			"........",
			"...PP...",
			"..C.ECP.",
			"PPP..PEP",
			".YT.X..T",
		]],
		{"segundo": true, "doble_apertura": true})

static func _elfos() -> Dictionary:
	# en el tablero de despliegue el Centinela usa el glifo 'P'
	var centinela := _pc("P", "Centinela", 1, _cells([
		[Vector2i(0, -1), "t"],
		[Vector2i(-1, -1), "o"], [Vector2i(1, -1), "o"],
	]), {"sym": "lit"})
	var dama := _pc("X", "Dama", 8,
		_mrg([_ray(Vector2i(1, 0), ["w","w","w","t","t","t","t"]),
			_ray(Vector2i(1, 1), ["w","w","t","t","t","t","t"]),
			_leap(Vector2i(1, 2), "j"), _leap(Vector2i(2, 1), "j")]))
	var monarca := _pc("Y", "Monarca", 0,
		_cells([[Vector2i(1, 0), "w"], [Vector2i(1, 1), "w"]]), {"leader": true})
	var hostigador := _pc("H", "Hostigador", 3,
		_mrg([_ray(Vector2i(1, 1), ["w","w","w","T","T","T","T"]),
			_cells([[Vector2i(0, -1), "t"]])]))
	var explorador := _pc("E", "Explorador", 3,
		_mrg([_ray(Vector2i(1, 1), ["T","T","T","T","T","T"], 2),
			_leaps([Vector2i(1, 2), Vector2i(2, 1)], "j")]))
	var forestal := _pc("F", "Forestal", 5,
		_mrg([_ray(Vector2i(1, 0), ["w","w","w","t"]),
			_ray(Vector2i(1, 1), ["t","t"])]),
		{"castle_partner": true})
	return _faction("elfos", "Elfos", Color(0.3, 0.8, 0.3),
		[centinela, dama, monarca, hostigador, explorador, forestal],
		[[
			".......F",
			"EPPFXPP.",
			".PHP.HP.",
			"....P.E.",
			"......Y.",
		], [
			".......F",
			"EPPFXPP.",
			".PHP.HP.",
			"....P.E.",
			"......Y.",
		]],
		{"primero": true})

static func _mortifers() -> Dictionary:
	var carronero := _pc("P", "Carroñero", 1, _cells([
		[Vector2i(0, -1), "o"],
		[Vector2i(-1, -1), "c"], [Vector2i(1, -1), "c"],
	]), {"sym": "lit"})
	var consorte := _pc("X", "Consorte", 8,
		_mrg([_ray(Vector2i(1, 0), ["o","J","o","o","o","c","c"]),
			_ray(Vector2i(1, 1), ["o","J","o","c","c","c","c"])]),
		{"swap_on_capture": true})
	var tirano := _pc("Y", "Tirano", 0,
		_mrg([_cells([[Vector2i(1, 0), "o"], [Vector2i(0, 1), "o"],
				[Vector2i(1, 1), "o"]]),
			_cells([[Vector2i(2, 0), "c"], [Vector2i(0, 2), "c"],
				[Vector2i(2, 2), "c"]])]),
		{"leader": true})
	var corruptor := _pc("C", "Corruptor", 3,
		_mrg([_ray(Vector2i(1, 1), ["o","J","o","c"]),
			_cells([[Vector2i(0, -1), "c"], [Vector2i(-1, 0), "c"]])]))
	var merodeador := _pc("M", "Merodeador", 3,
		_mrg([_ray(Vector2i(1, 1), ["m","m","c","c"]),
			_ray(Vector2i(1, 0), ["m","m","c","c"])]))
	var incubo := _pc("I", "Incubo", 5,
		_mrg([_ray(Vector2i(1, 0), ["o","J","c","c","c"]),
			_ray(Vector2i(1, 1), ["c","c","c"])]),
		{"castle_partner": true})
	return _faction("mortifers", "Mortifers", Color(0.75, 0.15, 0.15),
		[carronero, consorte, tirano, corruptor, merodeador, incubo],
		[[
			".......I",
			"M..PCCP.",
			"I.PMPP.P",
			"PP......",
			"...XY...",
		], [
			"I.......",
			".PCCP..M",
			"P.PPMP.I",
			"......PP",
			"...YX...",
		]])

static func _bestiarios() -> Dictionary:
	var rahez := _pc("H", "Rahez", 1, _cells([
		[Vector2i(0, -1), "m"], [Vector2i(0, -2), "m"],
		[Vector2i(-1, -1), "c"], [Vector2i(1, -1), "c"],
	]), {"sym": "lit"})
	var rapaz := _pc("R", "Rapaz", 4,
		_mrg([_ray(Vector2i(1, 1), ["o","o","o","o","o","o","o"]),
			_cells([[Vector2i(0, -1), "m"], [Vector2i(0, -2), "m"],
				[Vector2i(-1, 0), "m"], [Vector2i(-2, 0), "m"]])]))
	var fugaz := _pc("F", "Fugaz", 3,
		_leaps([Vector2i(3, 0), Vector2i(2, 2)], "J"))
	var edaz := _pc("E", "Edaz", 6,
		_mrg([_ray(Vector2i(0, -1), ["o","o","o","o"]),
			_ray(Vector2i(1, 1), ["o","o","o"])]))
	var voraz := _pc("V", "Voraz", 3,
		_mrg([_ray(Vector2i(1, 1), ["o","o","o","c","c","c","c"]),
			_cells([[Vector2i(0, -1), "c"], [Vector2i(-1, 0), "c"]])]))
	var sagaz := _pc("S", "Sagaz", 3,
		_leaps([Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)], "J"))
	var audaz := _pc("A", "Audaz", 5,
		_mrg([_cells([[Vector2i(0, -1), "o"], [Vector2i(-1, 0), "o"],
				[Vector2i(-1, -1), "o"]]),
			_cells([[Vector2i(-2, -2), "j"], [Vector2i(-2, -1), "j"],
				[Vector2i(-2, 0), "j"], [Vector2i(-1, -2), "j"],
				[Vector2i(0, -2), "j"]])]))
	var lideresa := _pc("X", "Lideresa", 6,
		_cells([[Vector2i(2, 0), "J"], [Vector2i(0, 2), "J"],
			[Vector2i(2, 1), "J"], [Vector2i(1, 2), "J"],
			[Vector2i(2, 2), "J"]]), {"leader": true})
	var lider := _pc("Y", "Líder", 6,
		_mrg([_cells([[Vector2i(0, -1), "o"], [Vector2i(-1, 0), "o"],
				[Vector2i(-1, -1), "o"]]),
			_cells([[Vector2i(0, -2), "J"], [Vector2i(0, -3), "J"],
				[Vector2i(-2, 0), "J"], [Vector2i(-3, 0), "J"],
				[Vector2i(-2, -2), "J"]])]), {"leader": true})
	return _faction("bestiarios", "Bestiarios", Color(0.95, 0.6, 0.1),
		[rahez, rapaz, fugaz, edaz, voraz, sagaz, audaz, lideresa, lider],
		[[
			".H......",
			"E.H.H.H.",
			"X..HRHA.",
			"H......H",
			"V...FSY.",
		], [
			"......H.",
			".H.H.H.E",
			".AHR.H.X",
			"H......H",
			".YSF...V",
		]],
		{"doble_lider": true})

static func _enanos() -> Dictionary:
	var vasallo := _pc("S", "Vasallo", 1, _cells([
		[Vector2i(0, -1), "p"],
		[Vector2i(-1, -1), "P"], [Vector2i(1, -1), "P"],
	]), {"sym": "lit"})
	var sultana := _pc("X", "Sultana", 6,
		_mrg([_ray(Vector2i(1, 0), ["o","o","o"]),
			_ray(Vector2i(1, 1), ["o","o","o"]),
			_leap(Vector2i(1, 2), "J"), _leap(Vector2i(2, 1), "J")]))
	var califa := _pc("Y", "Califa", 0,
		_cells([[Vector2i(0, -1), "3"], [Vector2i(-1, 0), "3"],
			[Vector2i(-1, -1), "P"], [Vector2i(0, -2), "p"],
			[Vector2i(-2, 0), "p"]]), {"leader": true})
	var verdugo := _pc("V", "Verdugo", 4,
		_mrg([_ray(Vector2i(1, 0), ["c","c","o","a"]),
			_ray(Vector2i(1, 1), ["c","o","a"])]))
	var raudo := _pc("R", "Raudo", 4,
		_mrg([_ray(Vector2i(1, 0), ["c","m","J"]),
			_ray(Vector2i(1, 1), ["c","m"])]))
	var zaguero := _pc("Z", "Zaguero", 4,
		_mrg([_ray(Vector2i(1, 0), ["3","3","P"]),
			_ray(Vector2i(1, 1), ["3","P"])]))
	return _faction("enanos", "Enanos", Color(0.7, 0.45, 0.9),
		[vasallo, sultana, califa, verdugo, raudo, zaguero],
		[[
			"..S.....",
			"S.RS.S..",
			"Z.SR.VZS",
			"...S.SX.",
			".V....Y.",
		], [
			".....S..",
			"..S.SR.S",
			"SZV.RS.Z",
			".XS.S...",
			".Y....V.",
		]])

static func _chlontos() -> Dictionary:
	var zangano := _pc("Z", "Zángano", 1, _cells([
		[Vector2i(0, -1), "m"], [Vector2i(0, -2), "c"],
		[Vector2i(-1, -1), "c"], [Vector2i(1, -1), "c"],
	]), {"sym": "lit"})
	var matriarca := _pc("X", "Matriarca", 6,
		_mrg([_ray(Vector2i(1, 1), ["c","J","J","c","c","c","c"]),
			_ray(Vector2i(1, 0), ["c","J","J","c","c","c","c"])]))
	var gerarca := _pc("Y", "Gerarca", 0,
		_mrg([_ray(Vector2i(1, 0), ["o","j"]),
			_ray(Vector2i(1, 1), ["o"])]), {"leader": true})
	var raptor := _pc("R", "Raptor", 4,
		_mrg([_ray(Vector2i(1, 0), ["c","j","j","c","c"]),
			_ray(Vector2i(1, 1), ["c","j","c","c","c"])]))
	var cefiro := _pc("C", "Céfiro", 4,
		_mrg([_cells([[Vector2i(0, -2), "g"], [Vector2i(0, -3), "g"],
				[Vector2i(-2, -2), "g"], [Vector2i(-3, -3), "g"],
				[Vector2i(-2, 0), "g"], [Vector2i(-3, 0), "g"]]),
			_cells([[Vector2i(-1, -2), "j"], [Vector2i(-2, -1), "j"]])]))
	var hoplita := _pc("H", "Hoplita", 4,
		_cells([[Vector2i(0, -2), "J"], [Vector2i(0, -3), "J"],
			[Vector2i(-2, -2), "J"], [Vector2i(-3, -3), "J"],
			[Vector2i(-3, 0), "J"], [Vector2i(-2, 0), "J"]]))
	return _faction("chlontos", "Chlontos", Color(0.2, 0.8, 0.85),
		[zangano, matriarca, gerarca, raptor, cefiro, hoplita],
		[[
			"........",
			"...ZH.Z.",
			"..RCZR.X",
			"ZZZC.Z.Z",
			"...H..Y.",
		], [
			"........",
			".Z..HZ..",
			"X.RZCR..",
			"Z.Z.CZZZ",
			".Y..H...",
		]])

static func _aquontes() -> Dictionary:
	var alevin := _pc("A", "Alevín", 1, _cells([
		[Vector2i(0, -1), "m"],
		[Vector2i(-1, -1), "c"], [Vector2i(1, -1), "c"],
		[Vector2i(0, -2), "q"], [Vector2i(0, -3), "q"], [Vector2i(0, -4), "q"],
		[Vector2i(0, -5), "q"],
	]), {"sym": "lit"})
	var anfitrite := _pc("X", "Anfitrite", 8,
		_mrg([_ray(Vector2i(1, 0), ["o","J","Q","q","q","q","q"]),
			_ray(Vector2i(1, 1), ["o","J","Q","q","q","q","q"])]))
	var leviatan := _pc("Y", "Leviatán", 0,
		_mrg([_ray(Vector2i(1, 1), ["o","q","q","q","q","q","q"]),
			_ray(Vector2i(1, 0), ["o","q","q","q","q","q","q"])]),
		{"leader": true})
	var mako := _pc("M", "Mako", 2,
		_ray(Vector2i(1, 1), ["o","J","Q","q","q","q","q"]))
	var triton := _pc("T", "Tritón", 4, _cells([
		[Vector2i(1, -1), "o"],
	]), {"leg2": _cells([
		[Vector2i(-2, -2), "Q"],
	]), "sym": "lit"})
	var carchar := _pc("C", "Carchar", 4,
		_ray(Vector2i(1, 0), ["o","J","Q","q","q","q","q"]))
	return _faction("aquontes", "Aquontes", Color(0.15, 0.45, 0.85),
		[alevin, anfitrite, leviatan, mako, triton, carchar],
		[[
			"M......A",
			"AT.A.A.C",
			"C.AMATA.",
			".A...X..",
			"......Y.",
		], [
			"A......M",
			"C.A.A.TA",
			".ATAAM.C",
			"..X...A.",
			".Y......",
		]])

static func _kronturs() -> Dictionary:
	var mole := _pc("M", "Mole", 1, _cells([
		[Vector2i(0, -1), "p"], [Vector2i(0, -2), "e"],
		[Vector2i(-1, -1), "c"], [Vector2i(1, -1), "c"],
	]), {"sym": "lit"})
	var zarina := _pc("X", "Zarina", 6,
		_mrg([_ray(Vector2i(1, 0), ["3","3","3","3","P"]),
			_ray(Vector2i(1, 1), ["3","3","P"])]))
	var zar := _pc("Y", "Zar", 0,
		_mrg([_ray(Vector2i(1, 0), ["3","e"]),
			_ray(Vector2i(1, 1), ["3"])]), {"leader": true})
	var ariete := _pc("A", "Ariete", 4,
		_mrg([_ray(Vector2i(1, 0), ["P","P","p","p"]),
			_ray(Vector2i(1, 1), ["P","P","p","p"])]))
	var dique := _pc("D", "Dique", 4,
		_mrg([_ray(Vector2i(1, 0), ["3","3","p"]),
			_ray(Vector2i(1, 1), ["3","p"])]))
	var goliat := _pc("G", "Goliat", 4,
		_mrg([_ray(Vector2i(1, 0), ["3","P","P","P"]),
			_ray(Vector2i(1, 1), ["3","P","P"])]))
	return _faction("kronturs", "Kronturs", Color(0.6, 0.6, 0.65),
		[mole, zarina, zar, ariete, dique, goliat],
		[[
			"..M.....",
			"..MGMM..",
			"MAM..D..",
			"XM.G..DM",
			".Y.A....",
		], [
			".....M..",
			"..MMGM..",
			"..D..MAM",
			"MD..G.MX",
			"....A.Y.",
		]])
