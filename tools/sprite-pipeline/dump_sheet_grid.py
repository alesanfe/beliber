#!/usr/bin/env python3
"""
Cada hoja de referencia es UNA rejilla global de ~35-42 px por celda.
Este script detecta todas las lineas de rejilla y vuelca la matriz
completa (cols x filas) con coordenadas, para segmentar los paneles.
"""
import os, glob, sys
from PIL import Image
from read_diagrams import clasifica, es_linea

HERE = os.path.dirname(__file__)
ROOT = HERE

def scan_v(px, w, h, lo=2, hi=8):
    cnt = [0] * w
    for x in range(w):
        c = 0
        for y in range(0, h, 2):
            if es_linea(px[x, y]): c += 1
        cnt[x] = c
    thr = h * 0.12   # lineas de panel local (span parcial)
    gs = []
    for x in range(w):
        if cnt[x] > thr:
            if gs and x - gs[-1][-1] <= 6: gs[-1].append(x)
            else: gs.append([x])
    return [g[len(g) // 2] for g in gs]

def scan_h(px, w, h):
    cnt = [0] * h
    for y in range(h):
        c = 0
        for x in range(0, w, 2):
            if es_linea(px[x, y]): c += 1
        cnt[y] = c
    thr = w * 0.12
    gs = []
    for y in range(h):
        if cnt[y] > thr:
            if gs and y - gs[-1][-1] <= 6: gs[-1].append(y)
            else: gs.append([y])
    return [g[len(g) // 2] for g in gs]

def merge_close(xs, target_gap):
    """reconstruye la rejilla uniforme: propaga el gap medio y une
    huecos donde una linea quedo sin detectar."""
    if len(xs) < 2: return xs
    diffs = sorted(xs[i + 1] - xs[i] for i in range(len(xs) - 1))
    gap = diffs[len(diffs) // 2]
    out = [xs[0]]
    for x in xs[1:]:
        d = x - out[-1]
        n = round(d / gap)
        for k in range(1, n):
            out.append(out[-1] + gap)
        out.append(x)
    return out

fname = sys.argv[1] if len(sys.argv) > 1 else None
files = [fname] if fname else sorted(
    glob.glob(os.path.join(ROOT, "IMG-2026*.jpg")))

for f in files:
    im = Image.open(f).convert("RGB")
    px = im.load(); w, h = im.size
    xs = merge_close(scan_v(px, w, h), 0)
    ys = merge_close(scan_h(px, w, h), 0)
    print("=" * 70)
    print(os.path.basename(f), w, "x", h, "| cols:", len(xs) - 1,
          "filas:", len(ys) - 1)
    for j in range(len(ys) - 1):
        row = []
        for i in range(len(xs) - 1):
            row.append(clasifica(px[(xs[i] + xs[i + 1]) // 2,
                                    (ys[j] + ys[j + 1]) // 2]))
        print("r%02d %s" % (j, "".join(row)))
