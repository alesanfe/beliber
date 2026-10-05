#!/usr/bin/env python3
"""
Lee las hojas de referencia de Beliber y transcribe cada mini-tablero
a una matriz de colores.

Uso:
    python read_diagrams.py <imagen>            # todos los paneles
    python read_diagrams.py <imagen> x0 y0 x1 y1  # un recorte concreto

Detecta rejillas por sus líneas negras, muestrea el centro de cada
casilla y la clasifica según la paleta de la leyenda.
"""
import os
import sys
from PIL import Image

PALETA = [
    # (nombre, simbolo, rgb medido en la leyenda impresa)
    ("vacia",    ".",  (245, 245, 245)),
    ("pieza",    "@",  (15, 15, 15)),
    ("amarillo", "m",  (240, 241, 0)),     # Mover
    ("rojo",     "c",  (237, 1, 3)),       # Capturar
    ("naranja",  "o",  (233, 146, 4)),     # Mover o Capturar
    ("cian",     "j",  (3, 239, 239)),     # Mover saltando
    ("lima",     "g",  (0, 241, 138)),     # Capturar saltando
    ("morado",   "J",  (143, 0, 236)),     # Capt/Mov saltando
    ("oliva",    "t",  (176, 176, 2)),     # Mover atravesando
    ("rojoosc",  "T",  (180, 60, 61)),     # Capturar atravesando
    ("verdeosc", "w",  (98, 143, 0)),      # M/C atravesando
    ("teal",     "p",  (79, 140, 133)),    # Mover o Empujar
    ("magenta",  "P",  (140, 2, 141)),     # Capturar o Empujar
    ("azulosc",  "3",  (68, 71, 142)),     # M/C/Empujar
    ("azul",     "e",  (0, 0, 238)),       # Empujar
    ("rosa",     "E",  (239, 144, 150)),   # al paso
    ("verdecl",  "d",  (145, 241, 143)),   # despliegue
    ("enroque",  "k",  (0, 149, 3)),       # Mover condicionado: enroque
    ("lime",     "K",  (5, 241, 0)),       # M/C o Enroque
    ("marron",   "q",  (141, 71, 2)),      # salto de Aquonte
    ("granate",  "Q",  (145, 0, 0)),       # M/C o Aquonte
    ("magenta2", "a",  (242, 0, 243)),     # Atraer
]

def clasifica(rgb):
    r, g, b = rgb[:3]
    best, bestd = "?", 1e9
    for _n, s, (pr, pg, pb) in PALETA:
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < bestd:
            best, bestd = s, d
    return best

def es_linea(v):  # pixel oscuro (borde de rejilla)
    return sum(v[:3]) < 180

def detectar_rejillas(im):
    """Devuelve [(x0,y0,x1,y1), ...] con el bbox de cada rejilla 8x8."""
    w, h = im.size
    px = im.load()
    # histograma de oscuridad por columna/fila
    ch = [0] * w
    for x in range(w):
        for y in range(h):
            if es_linea(px[x, y]):
                ch[x] += 1
    cv = [0] * h
    for y in range(h):
        for x in range(w):
            if es_linea(px[x, y]):
                cv[y] += 1
    # una línea de rejilla es larga (>25% del eje) y vertical/horizontal
    def grupos(hist, umbral):
        idx = [i for i, v in enumerate(hist) if v > umbral]
        out = []
        for i in idx:
            if out and i - out[-1][-1] <= 2:
                out[-1].append(i)
            else:
                out.append([i])
        return [g[len(g) // 2] for g in out]
    xs = grupos(ch, h * 0.20)
    ys = grupos(cv, w * 0.20)
    # una rejilla necesita ~9 líneas espaciadas de forma regular
    rejillas = []
    def bloques(lineas):
        grup = []
        for l in lineas:
            if grup and l - grup[-1][-1] < 80:
                grup[-1].append(l)
            else:
                grup.append([l])
        return [g for g in grup if len(g) >= 7]
    bx = bloques(xs)
    by = bloques(ys)
    for gx in bx:
        for gy in by:
            rejillas.append((gx[0], gy[0], gx[-1], gy[-1]))
    return rejillas

def leer_panel(im, bbox):
    """Devuelve matriz de símbolos para la rejilla dada."""
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0, y1 - y0
    px = im.load()
    ch = [0] * w
    for x in range(w):
        for y in range(h):
            if es_linea(px[x0 + x, y0 + y]):
                ch[x] += 1
    cv = [0] * h
    for y in range(h):
        for x in range(w):
            if es_linea(px[x0 + x, y0 + y]):
                cv[y] += 1
    def grupos(hist, umbral):
        idx = [i for i, v in enumerate(hist) if v > umbral]
        out = []
        for i in idx:
            if out and i - out[-1][-1] <= 3:
                out[-1].append(i)
            else:
                out.append([i])
        return [g[len(g) // 2] for g in out]
    xs = grupos(ch, h * 0.6)
    ys = grupos(cv, w * 0.6)
    if len(xs) < 2 or len(ys) < 2:
        return None
    n_x = len(xs) - 1
    n_y = len(ys) - 1
    filas = []
    for j in range(n_y):
        fila = ""
        for i in range(n_x):
            cx = x0 + (xs[i] + xs[i + 1]) // 2
            cy = y0 + (ys[j] + ys[j + 1]) // 2
            fila += clasifica(px[cx, cy])
        filas.append(fila)
    return filas, n_x, n_y

def muestreo_uniforme(im, bbox, nx=8, ny=8, margen=0.0):
    """Divide el bbox en nx*ny y muestrea el centro de cada casilla."""
    x0, y0, x1, y1 = bbox
    px = im.load()
    w, h = x1 - x0, y1 - y0
    filas = []
    for j in range(ny):
        fila = ""
        for i in range(nx):
            cx = x0 + int((i + 0.5) * w / nx)
            cy = y0 + int((j + 0.5) * h / ny)
            fila += clasifica(px[cx, cy])
        filas.append(fila)
    return filas


def detectar_panel(im):
    """Encuentra la rejilla 8x8 dentro de un recorte de panel.
    Estrategia: 9 líneas verticales equiespaciadas; luego busca el bloque
    de filas con el mismo paso hacia abajo desde el borde inferior."""
    w, h = im.size
    px = im.load()
    def dark(v):
        return sum(v[:3]) < 180
    # columnas con mucha oscuridad concentrada en la mitad inferior
    ch = [0] * w
    for x in range(w):
        for y in range(h // 3, h):
            if dark(px[x, y]):
                ch[x] += 1
    xs = [x for x in range(w) if ch[x] > h * 0.5]
    # agrupar líneas contiguas
    grup = []
    for x in xs:
        if grup and x - grup[-1][-1] <= 3:
            grup[-1].append(x)
        else:
            grup.append([x])
    xs = [g[len(g) // 2] for g in grup]
    if len(xs) < 9:
        return None
    # las 9 líneas de la rejilla forman el grupo equiespaciado más largo
    best = None
    i = 0
    while i + 8 < len(xs) + 1:
        seg = xs[i:i + 9]
        if len(seg) == 9:
            pasos = [seg[k + 1] - seg[k] for k in range(8)]
            if max(pasos) - min(pasos) <= 6:
                best = seg
                break
        i += 1
    if best is None:
        return None
    cell = (best[-1] - best[0]) / 8.0
    cv = [0] * h
    for y in range(h):
        for x in range(best[0], best[-1] + 1):
            if dark(px[x, y]):
                cv[y] += 1
    ys = [y for y in range(h) if cv[y] > (best[-1] - best[0]) * 0.85]
    gy = []
    for y in ys:
        if gy and y - gy[-1][-1] <= 3:
            gy[-1].append(y)
        else:
            gy.append([y])
    ys = [g[len(g) // 2] for g in gy]
    # filas de la rejilla: líneas espaciadas ~cell, terminando en la última
    filas_ok = []
    for y in reversed(ys):
        if filas_ok and abs(filas_ok[-1] - y - cell) > cell * 0.35:
            break
        filas_ok.append(y)
        if len(filas_ok) == 9:
            break
    if len(filas_ok) < 9:
        return None
    ys9 = sorted(filas_ok)
    return best[0], ys9[0], best[-1], ys9[-1], cell


def leer_panel_auto(im):
    r = detectar_panel(im)
    if not r:
        return None
    x0, y0, x1, y1, cell = r
    px = im.load()
    filas = []
    for j in range(8):
        fila = ""
        for i in range(8):
            cx = int(x0 + (i + 0.5) * cell)
            cy = int(y0 + (j + 0.5) * cell)
            fila += clasifica(px[cx, cy])
        filas.append(fila)
    return filas


def main():
    import glob
    if len(sys.argv) >= 2 and sys.argv[1] == "crops":
        for p in sorted(glob.glob(os.path.join(
                os.path.dirname(__file__), "crops", "*.png"))):
            im = Image.open(p).convert("RGB")
            filas = leer_panel_auto(im)
            print("###", os.path.basename(p))
            if filas:
                for f in filas:
                    print("  " + f)
            else:
                print("  (no detectado)")
            print()
        return
    path = sys.argv[1]
    im = Image.open(path).convert("RGB")
    if len(sys.argv) >= 6:
        box = tuple(int(v) for v in sys.argv[2:6])
        nx = int(sys.argv[6]) if len(sys.argv) > 6 else 8
        ny = int(sys.argv[7]) if len(sys.argv) > 7 else 8
        filas = muestreo_uniforme(im, box, nx, ny)
        print(f"muestreo {nx}x{ny} en {box}")
        for f in filas:
            print("  " + f)
        return
    for i, box in enumerate(detectar_rejillas(im)):
        r = leer_panel(im, box)
        if not r:
            continue
        filas, nx, ny = r
        print(f"panel {i}  rejilla {nx}x{ny}  bbox={box}")
        for f in filas:
            print("  " + f)
        print()

if __name__ == "__main__":
    main()
