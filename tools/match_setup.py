#!/usr/bin/env python3
"""Transcripción automática de tableros de despliegue.

1. Para cada hoja, extrae la rejilla 8x8 de cada panel de pieza y toma la
   casilla negra (la pieza) -> glifo de referencia con nombre de pieza.
2. En los paneles de setup, detecta casillas con letra (contraste de tinta)
   y empareja cada glifo con las referencias por correlación.
3. Imprime el grid de letras identificadas (nombre) + color de casilla.

Detección de rejillas: busca líneas negras horizontales/verticales.
"""
import os
import numpy as np
from PIL import Image

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def lineas(a1d, umbral=0.30, vmin=100):
    """Posiciones donde la fracción de píxeles oscuros supera umbral."""
    idx = [i for i, v in enumerate(a1d) if v < vmin]
    if not idx:
        return []
    # fracción de oscuros por columna/fila la calcula el llamador
    return idx

def encontrar_rejilla(im):
    """Devuelve (x0,y0,x1,y1) de la rejilla 8x8 principal de un crop."""
    g = np.asarray(im.convert('L'), dtype=float)
    H, W = g.shape
    colfrac = (g < 100).mean(axis=0)
    rowfrac = (g < 100).mean(axis=1)
    xs = np.where(colfrac > 0.35)[0]
    ys = np.where(rowfrac > 0.35)[0]
    if len(xs) < 9 or len(ys) < 9:
        return None
    # agrupar en líneas contiguas
    def grupos(v):
        out, cur = [], [v[0]]
        for x in v[1:]:
            if x - cur[-1] <= 2: cur.append(x)
            else: out.append(int(np.mean(cur))); cur = [x]
        out.append(int(np.mean(cur)))
        return out
    lx, ly = grupos(xs.tolist()), grupos(ys.tolist())
    if len(lx) < 9 or len(ly) < 9:
        return None
    # la rejilla son las 9 últimas/iguales espaciadas: usar extremos
    return (lx[0], ly[0], lx[-1], ly[-1]), lx, ly

def tinta(crop):
    g = np.asarray(crop.convert('L'), dtype=float)
    med = np.median(g)
    m = g > med + 55 if med < 120 else g < med - 55
    if m.sum() < 15:
        return None
    ys, xs = np.where(m)
    sub = m[ys.min():ys.max()+1, xs.min():xs.max()+1]
    if sub.shape[0] < 8 or sub.shape[1] < 4 or sub.shape[1] > sub.shape[0] * 2:
        return None
    return np.asarray(Image.fromarray((sub*255).astype(np.uint8))
                      .resize((40, 48))) > 0

def celda(im, cx, cy, s):
    return im.crop((int(cx-s), int(cy-s), int(cx+s), int(cy+s)))

def glifos_pieza(im, rej):
    """Extrae glifo de la casilla negra de un panel de pieza."""
    (x0,y0,x1,y1), lx, ly = rej
    w, h = (x1-x0)/8.0, (y1-y0)/8.0
    best, pos = 1e9, None
    for j in range(8):
        for i in range(8):
            cx, cy = x0+(i+.5)*w, y0+(j+.5)*h
            m = np.asarray(celda(im, cx, cy, min(w,h)*0.4).convert('L')).mean()
            if m < best:
                best, pos = m, (i, j)
    if pos is None:
        return None
    cx, cy = x0+(pos[0]+.5)*w, y0+(pos[1]+.5)*h
    return tinta(celda(im, cx, cy, min(w,h)*0.34)), pos

def colores_setup(im, rej):
    (x0,y0,x1,y1), lx, ly = rej
    w, h = (x1-x0)/8.0, (y1-y0)/8.0
    out = {}
    for j in range(8):
        for i in range(8):
            cx, cy = x0+(i+.5)*w, y0+(j+.5)*h
            c = celda(im, cx, cy, min(w,h)*0.30)
            a = np.asarray(c.convert('RGB'), dtype=float)
            med = np.median(a.reshape(-1,3), axis=0)
            g = tinta(celda(im, cx, cy, min(w,h)*0.32))
            if g is not None and med.sum() > 150:  # no negro
                out[(i,j)] = (g, tuple(int(v) for v in med))
    return out
