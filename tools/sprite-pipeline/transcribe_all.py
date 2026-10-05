#!/usr/bin/env python3
"""
Transcribe TODOS los tableros 8x8 de cada hoja original con la paleta
corregida. Salida: _all_boards.txt  (para comparar con pieces_data.gd)
"""
import os, glob
from PIL import Image
from read_diagrams import clasifica, es_linea

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)

def grids(im):
    px = im.load(); w, h = im.size
    col = [0] * w
    for x in range(w):
        for y in range(h):
            if es_linea(px[x, y]): col[x] += 1
    xs, gs = [], []
    for x in range(w):
        if col[x] > h * 0.40:
            if gs and x - gs[-1][-1] <= 5: gs[-1].append(x)
            else: gs.append([x])
    xs = [g[len(g) // 2] for g in gs]
    row = [0] * h
    for y in range(h):
        for x in range(w):
            if es_linea(px[x, y]): row[y] += 1
    ys, gs = [], []
    for y in range(h):
        if row[y] > w * 0.30:
            if gs and y - gs[-1][-1] <= 5: gs[-1].append(y)
            else: gs.append([y])
    ys = [g[len(g) // 2] for g in gs]
    # rejillas 8x8: 9 líneas consecutivas equiespaciadas
    out = []
    for i in range(len(xs) - 8):
        seg = xs[i:i + 9]
        d0 = seg[1] - seg[0]
        if all(abs(seg[j + 1] - seg[j] - d0) < d0 * 0.35 for j in range(8)):
            for k in range(len(ys) - 8):
                s2 = ys[k:k + 9]
                d1 = s2[1] - s2[0]
                if all(abs(s2[j + 1] - s2[j] - d1) < d1 * 0.35
                       for j in range(8)):
                    out.append((xs[i:i + 9], ys[k:k + 9]))
            break
    # columnas alternativas de rejilla (mismo y, distinto x)
    grids_x = []
    for i in range(len(xs) - 8):
        seg = xs[i:i + 9]
        d0 = seg[1] - seg[0]
        if all(abs(seg[j + 1] - seg[j] - d0) < d0 * 0.35
               for j in range(8)):
            grids_x.append(seg)
    grids_y = []
    for k in range(len(ys) - 8):
        s2 = ys[k:k + 9]
        d1 = s2[1] - s2[0]
        if all(abs(s2[j + 1] - s2[j] - d1) < d1 * 0.35 for j in range(8)):
            grids_y.append(s2)
    out = []
    for gx in grids_x:
        for gy in grids_y:
            out.append((gx, gy))
    return out

def dump(f):
    im = Image.open(f).convert("RGB")
    px = im.load()
    out = []
    for n, (xs, ys) in enumerate(grids(im)):
        rows = []
        for j in range(8):
            rows.append("".join(
                clasifica(px[(xs[i] + xs[i + 1]) // 2,
                             (ys[j] + ys[j + 1]) // 2])
                for i in range(8)))
        out.append((n, xs[0], ys[0], rows))
    return out

for f in sorted(glob.glob(os.path.join(ROOT, "IMG-*.jpg"))):
    print("=" * 60)
    print(os.path.basename(f))
    for n, x0, y0, rows in dump(f):
        print("--- rejilla #%d (x=%d y=%d)" % (n, x0, y0))
        for r in rows:
            print("   ", r)
