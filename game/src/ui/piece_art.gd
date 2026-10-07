class_name PieceArt
extends RefCounted

## Siluetas vectoriales por arquetipo de pieza — sustituye a los glifos
## Unicode de ajedrez (dependían de la fuente del SO y se veían planos).
## Cada arquetipo es una lista de primitivas en coordenadas normalizadas
## (-0.5…0.5, +y hacia abajo, base ≈ y=0.40): polígonos y círculos que
## escalan con la casilla, así el zoom las re-renderiza nítido.
##
## Uso: PieceArt.draw(self, centro, CELL, arch, fill, carve)
##   fill  = tinta de la silueta
##   carve = color de fondo para los detalles "excavados" (ranura del
##           alfil, ojo del caballo)

const PAWN := "pawn"
const KNIGHT := "knight"
const BISHOP := "bishop"
const ROOK := "rook"
const QUEEN := "queen"
const KING := "king"

## Del glifo Unicode al arquetipo (los datos ya clasifican cada pieza
## por patrón — chess_glyph decide peón/caballo/… igual que antes).
static func arch_of_glyph(g: String) -> String:
	match g:
		"♞", "♘": return KNIGHT
		"♝", "♗": return BISHOP
		"♜", "♖": return ROOK
		"♛", "♕": return QUEEN
		"♚", "♔": return KING
	return PAWN

static func draw(c: Control, ctr: Vector2, cell: float, arch: String,
		fill: Color, carve: Color) -> void:
	var s := cell * 0.9          # la silueta usa ~90% de la casilla
	var P := func(pt: Vector2) -> Vector2:
		return ctr + pt * s
	var draw_poly := func(pts: Array) -> void:
		var pa := PackedVector2Array()
		for pt in pts: pa.append(P.call(pt))
		c.draw_colored_polygon(pa, fill)
	var circle := func(pt: Vector2, r: float) -> void:
		c.draw_circle(P.call(pt), r * s, fill)
	match arch:
		PAWN:
			draw_poly.call([vec(-0.30, 0.40), vec(0.30, 0.40),
				vec(0.22, 0.30), vec(-0.22, 0.30)])
			draw_poly.call([vec(-0.18, 0.30), vec(0.18, 0.30),
				vec(0.07, -0.02), vec(-0.07, -0.02)])
			circle.call(vec(0, -0.06), 0.10)
			circle.call(vec(0, -0.22), 0.14)
		ROOK:
			draw_poly.call([vec(-0.30, 0.40), vec(0.30, 0.40),
				vec(0.24, 0.32), vec(-0.24, 0.32)])
			draw_poly.call([vec(-0.24, 0.32), vec(0.24, 0.32),
				vec(0.16, -0.12), vec(-0.16, -0.12)])
			# almenas: corona con dos muescas
			draw_poly.call([vec(-0.20, -0.38), vec(-0.10, -0.38),
				vec(-0.10, -0.28), vec(-0.04, -0.28), vec(-0.04, -0.38),
				vec(0.04, -0.38), vec(0.04, -0.28), vec(0.10, -0.28),
				vec(0.10, -0.38), vec(0.20, -0.38), vec(0.20, -0.20),
				vec(-0.20, -0.20)])
			draw_poly.call([vec(-0.18, -0.20), vec(0.18, -0.20),
				vec(0.16, -0.12), vec(-0.16, -0.12)])
		BISHOP:
			draw_poly.call([vec(-0.30, 0.40), vec(0.30, 0.40),
				vec(0.22, 0.32), vec(-0.22, 0.32)])
			draw_poly.call([vec(-0.20, 0.32), vec(0.20, 0.32),
				vec(0.08, -0.05), vec(-0.08, -0.05)])
			circle.call(vec(0, -0.15), 0.16)
			circle.call(vec(0, -0.34), 0.05)
			# corte diagonal de la mitra
			c.draw_line(P.call(vec(0.05, -0.26)), P.call(vec(-0.05, -0.06)),
				carve, cell * 0.05, true)
		KNIGHT:
			# perfil de caballo mirando a la izquierda
			draw_poly.call([vec(-0.26, 0.40), vec(0.26, 0.40),
				vec(0.24, 0.30), vec(0.18, 0.08), vec(0.16, -0.10),
				vec(0.10, -0.22), vec(0.00, -0.34), vec(-0.08, -0.40),
				vec(-0.14, -0.34), vec(-0.10, -0.28), vec(-0.20, -0.26),
				vec(-0.28, -0.16), vec(-0.32, -0.04), vec(-0.26, 0.04),
				vec(-0.16, 0.02), vec(-0.10, 0.06), vec(-0.18, 0.16),
				vec(-0.22, 0.30)])
			c.draw_circle(P.call(vec(-0.10, -0.14)), cell * 0.025, carve)
		QUEEN:
			draw_poly.call([vec(-0.32, 0.40), vec(0.32, 0.40),
				vec(0.24, 0.32), vec(-0.24, 0.32)])
			draw_poly.call([vec(-0.22, 0.32), vec(0.22, 0.32),
				vec(0.10, -0.10), vec(-0.10, -0.10)])
			# corona de 5 puntas con orbes
			draw_poly.call([vec(-0.22, -0.06), vec(-0.24, -0.30),
				vec(-0.16, -0.16), vec(-0.12, -0.34), vec(-0.05, -0.16),
				vec(0.00, -0.38), vec(0.05, -0.16), vec(0.12, -0.34),
				vec(0.16, -0.16), vec(0.24, -0.30), vec(0.22, -0.06)])
			for tip in [vec(-0.24, -0.33), vec(-0.12, -0.37), vec(0, -0.41),
					vec(0.12, -0.37), vec(0.24, -0.33)]:
				circle.call(tip, 0.035)
		KING:
			draw_poly.call([vec(-0.32, 0.40), vec(0.32, 0.40),
				vec(0.24, 0.32), vec(-0.24, 0.32)])
			draw_poly.call([vec(-0.22, 0.32), vec(0.22, 0.32),
				vec(0.10, -0.08), vec(-0.10, -0.08)])
			draw_poly.call([vec(-0.20, -0.08), vec(0.20, -0.08),
				vec(0.18, -0.22), vec(-0.18, -0.22)])
			# cruz
			draw_poly.call([vec(-0.035, -0.24), vec(0.035, -0.24),
				vec(0.035, -0.40), vec(-0.035, -0.40)])
			draw_poly.call([vec(-0.10, -0.34), vec(0.10, -0.34),
				vec(0.10, -0.29), vec(-0.10, -0.29)])

## Atajo: vector unitario en espacio normalizado.
static func vec(x: float, y: float) -> Vector2:
	return Vector2(x, y)
