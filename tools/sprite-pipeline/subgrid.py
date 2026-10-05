#!/usr/bin/env python3
"""Uso: python subgrid.py <img> <x0px> <x1px> <y0px> <y1px>
Vuelca la rejilla uniforme detectada en la ventana dada."""
import sys
from PIL import Image
from read_diagrams import clasifica, es_linea

f, x0, x1, y0, y1 = sys.argv[1], *map(int, sys.argv[2:6])
im = Image.open(f).convert("RGB")
px = im.load()

def find_lines(axis, lo, hi, other_lo, other_hi, thr_frac):
    cnt = [0] * (hi - lo)
    n = other_hi - other_lo
    for a in range(lo, hi):
        c = 0
        for b in range(other_lo, other_hi, 2):
            p = px[a, b] if axis == "v" else px[b, a]
            if es_linea(p): c += 1
        cnt[a - lo] = c
    gs = []
    for i, c in enumerate(cnt):
        if c > n * thr_frac:
            if gs and i - gs[-1][-1] <= 6: gs[-1].append(i)
            else: gs.append([i])
    return [lo + g[len(g) // 2] for g in gs]

xs = find_lines("v", x0, x1, y0, y1, 0.5)
ys = find_lines("h", y0, y1, x0, x1, 0.5)
print("xs:", xs)
print("ys:", ys)
for j in range(len(ys) - 1):
    row = "".join(clasifica(px[(xs[i] + xs[i + 1]) // 2,
                               (ys[j] + ys[j + 1]) // 2])
                  for i in range(len(xs) - 1))
    print("r%02d %s" % (j, row))
