#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Vuelca la submatriz de CADA panel de pieza de las 8 hojas.
Cada panel = ventana en pixeles; dentro detecta lineas de rejilla
y clasifica cada celda. La pieza suele estar abajo-derecha (o abajo
para 'lit'); las cabeceras (nombre/valor) quedan como r0.
"""
import os, sys
from PIL import Image
from read_diagrams import clasifica, es_linea

HERE = os.path.dirname(__file__)
ROOT = HERE

# ventanas de panel en pixeles (x0,x1,y0,y1) por hoja
PANELS = {
 "WA0001": [  # humenex: 4 arriba, 4 abajo (el 4o de cada fila es setup)
    ("peón",      (  0, 390,   0, 330)),
    ("emperatriz",(390, 790,   0, 330)),
    ("emperador", (790,1180,   0, 330)),
    ("espía",     (  0, 390, 330, 738)),
    ("caballero", (390, 790, 330, 738)),
    ("torre",     (790,1180, 330, 738)),
 ],
 "WA0002": [
    ("centinela", (  0, 400,   0, 360)),
    ("dama",      (400, 800,   0, 360)),
    ("monarca",   (800,1200,   0, 360)),
    ("hostigador",(  0, 400, 360, 732)),
    ("explorador",(400, 800, 360, 732)),
    ("forestal",  (800,1200, 360, 732)),
 ],
 "WA0003": [
    ("carroñero", (  0, 400,   0, 360)),
    ("consorte",  (400, 800,   0, 360)),
    ("tirano",    (800,1200,   0, 360)),
    ("corruptor", (  0, 400, 360, 738)),
    ("merodeador",(400, 800, 360, 738)),
    ("incubo",    (800,1200, 360, 738)),
 ],
 "WA0004": [
    ("rahez",     (  0, 390,   0, 175)),
    ("lideresa",  (  0, 320, 155, 320)),
    ("rapaz",     (640, 960,   0, 320)),
    ("fugaz",     (960,1280,   0, 320)),
    ("edaz",      (1280,1600,  0, 320)),
    ("lider",     (  0, 320, 440, 637)),
    ("voraz",     (640, 960, 320, 637)),
    ("sagaz",     (960,1280, 320, 637)),
    ("audaz",     (1280,1600,320, 637)),
 ],
 "WA0005": [
    ("vasallo",   (  0, 400,   0, 360)),
    ("sultana",   (400, 780,   0, 360)),
    ("califa",    (800,1180,   0, 360)),
    ("verdugo",   (  0, 350, 365, 725)),
    ("raudo",     (400, 780, 365, 725)),
    ("zagüero",   (820,1180, 365, 725)),
 ],
 "WA0006": [
    ("zángano",   (  0, 400,   0, 360)),
    ("matriarca", (400, 780,   0, 360)),
    ("gerarca",   (800,1180,   0, 360)),
    ("raptor",    (  0, 360, 365, 735)),
    ("céfiro",    (430, 770, 365, 735)),
    ("hoplita",   (830,1180, 365, 735)),
 ],
 "WA0007": [
    ("alevín",    (  0, 350,   0, 360)),
    ("anfitrite", (350, 780,   0, 360)),
    ("leviatán",  (780,1180,   0, 360)),
    ("mako",      (  0, 350, 360, 728)),
    ("carchar",   (780,1180, 360, 728)),
    ("tritón",    (350, 780, 360, 728)),
 ],
 "WA0008": [
    ("mole",      (  0, 400,   0, 360)),
    ("zarina",    (400, 800,   0, 360)),
    ("zar",       (800,1200,   0, 360)),
    ("ariete",    (  0, 400, 360, 737)),
    ("dique",     (400, 800, 360, 737)),
    ("goliat",    (800,1200, 360, 737)),
 ],
}

def scan(px, x0, x1, y0, y1, vertical):
    n = x1 - x0 if vertical else y1 - y0
    gs = []
    for i in range(x0, x1) if vertical else range(y0, y1):
        c = 0
        for j in range(y0, y1) if vertical else range(x0, x1):
            if es_linea(px[i, j] if vertical else px[j, i]):
                c += 1
        if c > n * 0.5:
            if gs and i - gs[-1][-1] <= 5:
                gs[-1].append(i)
            else:
                gs.append([i])
    return [g[len(g) // 2] for g in gs]

def panel_grid(px, x0, x1, y0, y1, votes=False):
    xs = scan(px, x0, x1, y0, y1, True)
    ys = scan(px, x0, x1, y0, y1, False)
    if len(xs) < 2 or len(ys) < 2:
        return []
    grid = []
    for j in range(len(ys) - 1):
        row = []
        for i in range(len(xs) - 1):
            cx = (xs[i] + xs[i + 1]) // 2
            cy = (ys[j] + ys[j + 1]) // 2
            if votes:
                from collections import Counter
                v = [clasifica(px[cx + dx, cy + dy])
                     for dx in (-10, 0, 10) for dy in (-8, 0, 8)]
                row.append(Counter(v).most_common(1)[0][0])
            else:
                row.append(clasifica(px[cx, cy]))
        grid.append("".join(row))
    return grid

which = sys.argv[1] if len(sys.argv) > 1 else None
votes = "--v" in sys.argv
for sheet, pans in PANELS.items():
    if which and sheet != which: continue
    im = Image.open(os.path.join(ROOT, "IMG-20260824-%s.jpg" % sheet)) \
           .convert("RGB")
    px = im.load()
    print("=====" * 8)
    print(sheet)
    for name, (x0, x1, y0, y1) in pans:
        g = panel_grid(px, x0, x1, y0, y1, votes)
        print("--- %s" % name)
        for j, row in enumerate(g):
            print("r%d %s" % (j, row))
