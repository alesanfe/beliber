class_name FX
extends RefCounted

## Constantes del sistema de movimientos de Beliber.
## Los efectos son bitflags combinables; los colores siguen la leyenda oficial.

# --- Efectos (bitflags) ---
const MOVE := 1        # colocar en casilla vacía
const CAPTURE := 2     # colocar en casilla con enemigo (lo captura)
const JUMP := 4        # ignora piezas en el camino
const ATRAVESAR := 8   # puede pasar a través de piezas; enemigos atravesados quedan inmovilizados
const EMPUJAR := 16    # destino ocupado: empuja al ocupante 1 casilla; arrolla enemigos del camino
const ATRAER := 32     # destino ocupado: arrastra al ocupante a la casilla adyacente

# --- Condiciones ---
const C_NONE := 0
const C_DEPLOY := 1      # solo si la pieza no ha movido (doble paso del peón)
const C_EN_PASSANT := 2  # capturar al paso
const C_CASTLE := 3      # enroque
const C_AQUONTE := 4     # salto de Aquonte (salto sobre pieza alineada)

# --- Colores de la leyenda (para highlights) ---
const COL := {
	MOVE = Color(1.0, 0.85, 0.0),            # amarillo
	CAPTURE = Color(0.9, 0.1, 0.1),          # rojo
	MOVE_OR_CAPTURE = Color(1.0, 0.55, 0.0), # naranja
	MOVE_JUMP = Color(0.1, 0.85, 0.9),       # cian
	CAPTURE_JUMP = Color(0.2, 0.9, 0.3),     # verde lima
	BOTH_JUMP = Color(0.6, 0.2, 0.9),        # morado
	MOVE_ATRAV = Color(0.5, 0.55, 0.0),      # oliva
	CAPTURE_ATRAV = Color(0.55, 0.1, 0.1),   # rojo oscuro
	BOTH_ATRAV = Color(0.25, 0.4, 0.05),     # verde oscuro
	MOVE_PUSH = Color(0.3, 0.55, 0.6),       # azul grisáceo
	CAPTURE_PUSH = Color(0.75, 0.15, 0.75),  # magenta
	MCP = Color(0.2, 0.25, 0.7),             # azul oscuro (mover/capturar/empujar)
	EMPUJAR = Color(0.15, 0.3, 0.95),        # azul
	ATRAER = Color(0.85, 0.1, 0.85),         # magenta vivo
	EN_PASSANT = Color(0.95, 0.55, 0.6),     # rosa
	DEPLOY = Color(0.55, 0.9, 0.55),         # verde claro
	CASTLE = Color(0.1, 0.55, 0.1),          # verde oscuro enroque
	AQUONTE = Color(0.55, 0.35, 0.1),        # marrón
}

## Devuelve el color de highlight según efectos/condición de un movimiento.
static func color_of(effects: int, cond: int = 0) -> Color:
	match cond:
		C_EN_PASSANT: return COL.EN_PASSANT
		C_DEPLOY: return COL.DEPLOY
		C_CASTLE: return COL.CASTLE
		C_AQUONTE: return COL.AQUONTE
	var e := effects
	if e & ATRAER: return COL.ATRAER
	var has_m: bool = (e & MOVE) != 0
	var has_c: bool = (e & CAPTURE) != 0
	var has_p: bool = (e & EMPUJAR) != 0
	var has_t: bool = (e & ATRAVESAR) != 0
	var has_j: bool = (e & JUMP) != 0
	if has_m and has_c and has_p: return COL.MCP
	if has_m and has_p: return COL.MOVE_PUSH
	if has_c and has_p: return COL.CAPTURE_PUSH
	if has_p: return COL.EMPUJAR
	if has_m and has_c and has_t: return COL.BOTH_ATRAV
	if has_m and has_t: return COL.MOVE_ATRAV
	if has_c and has_t: return COL.CAPTURE_ATRAV
	if has_m and has_c and has_j: return COL.BOTH_JUMP
	if has_m and has_j: return COL.MOVE_JUMP
	if has_c and has_j: return COL.CAPTURE_JUMP
	if has_m and has_c: return COL.MOVE_OR_CAPTURE
	if has_c: return COL.CAPTURE
	return COL.MOVE
