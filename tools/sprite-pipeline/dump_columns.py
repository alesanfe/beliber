#!/usr/bin/env python3
"""
Para cada hoja IMG-*.jpg: detecta las columnas de paneles (grupos de
9 líneas verticales) y transcribe TODAS las filas de celdas de cada
columna con la paleta corregida. Imprime con índice de fila para que
se puedan separar los paneles a mano.
"""
import os, glob
from PIL import Image
from read_diagrams import clasifica, es_linea

HERE = os.path.dirname(__file__)
ROOT = HERE

def vlines(px, w, h):
    col = [0] * w
    for x in range(w):
        c = 0
        for y in range(0, h, 2):
            if es_linea(px[x, y]): c += 1
        col[x] = c
    gs = []
    for x in range(w):
        if col[x] > h * 0.30:
            if gs and x - gs[-1][-1] <= 6: gs[-1].append(x)
            else: gs.append([x])
    return [g[len(g) // 2] for g in gs]

def hline_scan(im, x0, x1):
    px = im.load(); w, h = im.size
    cnt = [0] * h
    for y in range(h):
        c = 0
        for x in range(x0, x1, 2):
            if es_linea(px[x, y]): c += 1
        cnt[y] = c
    thr = (x1 - x0) * 0.30
    gs = []
    for y in range(h):
        if cnt[y] > thr:
            if gs and y - gs[-1][-1] <= 6: gs[-1].append(y)
            else: gs.append([y])
    return [g[len(g) // 2] for g in gs]

def col_groups(xs):
    """grupos de ≥9 líneas consecutivas casi equiespaciadas → una
    columna de paneles (la rejilla de 8 celdas de ancho)."""
    groups = []
    cur = [xs[0]]
    for i in range(1, len(xs)):
        d = xs[i] - xs[i - 1]
        if 15 <= d <= 75:      # separación de celda típica
            cur.append(xs[i])
        else:
            if len(cur) >= 9: groups.append(cur[:9])
            cur = [xs[i]]
    if len(cur) >= 9: groups.append(cur[:9])
    return groups

for f in sorted(glob.glob(os.path.join(ROOT, "IMG-*.jpg"))):
    im = Image.open(f).convert("RGB")
    px = im.load(); w, h = im.size
    xs = vlines(px, w, h)
    print("=" * 70)
    print(os.path.basename(f), "size", w, "x", h, "| lineasV:", len(xs))
    for gi, g in enumerate(col_groups(xs)):
        x0, x1 = g[0], g[min(8, len(g) - 1)]
        gx = g[:9]
        ys = hline_scan(im, g[0], g[-1])
        print("--- columna %d  x=[%d..%d]  %d lineasH" % (gi, x0, x1, len(ys)))
        for j in range(len(ys) - 1):
            row = "".join(
                clasifica(px[(gx[i] + gx[i + 1]) // 2,
                             (ys[j] + ys[j + 1]) // 2])
                for i in range(8))
            print("  r%02d %s" % (j, row))
