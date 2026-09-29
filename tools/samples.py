#!/usr/bin/env python3
"""Muestrea cada celda del crop y muestra RGB + clasificación."""
import os, sys
from PIL import Image
from read_diagrams import detectar_panel, clasifica

def analyze(name):
    p = os.path.join(os.path.dirname(__file__), "crops", name + ".png")
    if not os.path.exists(p):
        print("no existe", p); return
    im = Image.open(p).convert("RGB")
    r = detectar_panel(im)
    if not r:
        print(name, ": panel no detectado"); return
    x0, y0, x1, y1, cell = r
    px = im.load()
    print(f"=== {name}  grid ({x0},{y0})-({x1},{y1}) cell={cell:.1f}")
    for j in range(8):
        row = []
        for i in range(8):
            cx = int(x0 + (i + 0.5) * cell)
            cy = int(y0 + (j + 0.5) * cell)
            rgb = px[cx, cy]
            c = clasifica(rgb)
            row.append("%s(%d,%d,%d)" % (c, rgb[0], rgb[1], rgb[2])
                       if c not in ".@" else c)
        print("  " + " ".join(f"{t:<16}" for t in row))

if __name__ == "__main__":
    for n in sys.argv[1:]:
        analyze(n)
