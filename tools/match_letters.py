#!/usr/bin/env python3
"""Transcribe tableros de despliegue emparejando glifos por píxeles.

Para cada hoja de facción:
  1. extrae el glifo de la casilla negra de cada panel de pieza
     (la pieza está dibujada sobre negro con letra blanca/clara)
  2. extrae el glifo de cada casilla con letra de los tableros de setup
  3. imprime el grid de letras del setup + el mejor match por celda
"""
import os
import numpy as np
from PIL import Image

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def tinta(crop):
    """Máscara bool de la letra dentro de un recorte de casilla."""
    g = np.asarray(crop.convert('L'), dtype=float)
    if g.size == 0: return None
    med = np.median(g)
    # letra puede ser clara u oscura respecto al fondo; usar bordes
    m = g > med + 55 if med < 120 else g < med - 55
    if m.sum() < 10: return None
    ys, xs = np.where(m)
    sub = m[ys.min():ys.max()+1, xs.min():xs.max()+1]
    if sub.shape[0] < 8 or sub.shape[1] < 4: return None
    return np.asarray(Image.fromarray((sub*255).astype(np.uint8))
                      .resize((40, 48))) > 0

def es_negra(im, x, y, s):
    a = np.asarray(im.crop((x-s, y-s, x+s, y+s)).convert('L'))
    return a.mean() < 80

def celda(im, cx, cy, s):
    return im.crop((int(cx-s), int(cy-s), int(cx+s), int(cy+s)))

def glifos_piezas(im, paneles):
    """paneles: {nombre: (x0,y0,x1,y1)} bbox de la rejilla 8x8 del diagrama."""
    out = {}
    for nombre, (x0,y0,x1,y1) in paneles.items():
        w, h = (x1-x0)/8.0, (y1-y0)/8.0
        # la casilla negra con la letra: buscar la más oscura
        best, pos = 1e9, None
        for j in range(8):
            for i in range(8):
                cx, cy = x0+(i+.5)*w, y0+(j+.5)*h
                m = np.asarray(celda(im, cx, cy, min(w,h)*0.42).convert('L')).mean()
                if m < best:
                    best, pos = m, (cx, cy)
        if pos is None: continue
        s = min(w, h)*0.55
        g = tinta(celda(im, pos[0], pos[1], s))
        if g is not None:
            out[nombre] = (g, pos)
    return out

def letras_setup(im, bbox, tam):
    """Itera celdas del setup: devuelve {(i,j): (mascara, color)}."""
    x0,y0,x1,y1 = bbox
    out = {}
    for j in range(8):
        for i in range(8):
            cx, cy = x0+(i+.5)*tam, y0+(j+.5)*tam
            c = celda(im, cx, cy, tam*0.45)
            arr = np.asarray(c.convert('RGB')).mean(axis=(0,1))
            # casilla coloreada = no blanca/no negra tiene letra? mejor: tinta
            g = tinta(celda(im, cx, cy, tam*0.33))
            if g is not None:
                out[(i,j)] = (g, tuple(int(v) for v in arr))
    return out

def emparejar(g, refs):
    best, bn = 1e9, None
    for nombre, (rg, _pos) in refs.items():
        d = 1.0 - float((g == rg).mean())
        if d < best:
            best, bn = d, nombre
    return bn, best
