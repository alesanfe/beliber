#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Verifica los diagramas de referencia contra pieces_data.gd.

Para cada hoja se vuelca la matriz global (dump_sheet_grid) y se
comprueba que TODA celda dibujada en la region del panel de cada pieza
coincide con el patron expandido de esa pieza (orbita D4 para 'all',
literal para 'lit'). Celdas '@' (pieza) se ignoran.
"""
import os, sys
from PIL import Image
from read_diagrams import clasifica, es_linea

HERE = os.path.dirname(__file__)
ROOT = HERE

def scan_v(px, w, h):
    gs = []
    for x in range(w):
        c = 0
        for y in range(0, h, 2):
            if es_linea(px[x, y]): c += 1
        if c > h * 0.12:
            if gs and x - gs[-1][-1] <= 6: gs[-1].append(x)
            else: gs.append([x])
    return [g[len(g) // 2] for g in gs]

def scan_h(px, w, h):
    gs = []
    for y in range(h):
        c = 0
        for x in range(0, w, 2):
            if es_linea(px[x, y]): c += 1
        if c > w * 0.12:
            if gs and y - gs[-1][-1] <= 6: gs[-1].append(y)
            else: gs.append([y])
    return [g[len(g) // 2] for g in gs]

def merge_close(xs):
    if len(xs) < 2: return xs
    diffs = sorted(xs[i + 1] - xs[i] for i in range(len(xs) - 1))
    gap = diffs[len(diffs) // 2]
    out = [xs[0]]
    for x in xs[1:]:
        n = round((x - out[-1]) / gap)
        for _ in range(1, n):
            out.append(out[-1] + gap)
        out.append(x)
    return out

def sheet_grid(fname, votes=False):
    im = Image.open(os.path.join(ROOT, fname)).convert("RGB")
    px = im.load(); w, h = im.size
    xs = merge_close(scan_v(px, w, h)); ys = merge_close(scan_h(px, w, h))
    out = []
    for j in range(len(ys) - 1):
        row = []
        for i in range(len(xs) - 1):
            cx = (xs[i] + xs[i + 1]) // 2
            cy = (ys[j] + ys[j + 1]) // 2
            if votes:
                from collections import Counter
                v = [clasifica(px[cx + dx, cy + dy])
                     for dx in (-9, 0, 9) for dy in (-8, 0, 8)]
                row.append(Counter(v).most_common(1)[0][0])
            else:
                row.append(clasifica(px[cx, cy]))
        out.append(row)
    return out

# ---- defs desde dump_cells.gd -------------------------------------------------
def load_defs():
    defs = {}  # (faccion, slug) -> {"sym":str, "cells":{key:code}}
    cur = None
    for line in open(os.path.join(HERE, "_defs.txt"), encoding="utf-8"):
        line = line.strip()
        if line.startswith("### "):
            f, n = line[4:].split("/")
            cur = (f, n); defs[cur] = {"sym": "all", "cells": {}}
        elif line.startswith("sym="):
            defs[cur]["sym"] = line[4:]
        elif line.startswith("leg2:"):
            k, c = line[5:].split("=")
            defs[cur].setdefault("leg2", {})[k] = c
        elif "=" in line and cur:
            k, c = line.split("=")
            defs[cur]["cells"][k] = c
    return defs

def orbit(v):
    """las 8 transformaciones D4 del offset (x,y)"""
    out, x, y = set(), v[0], v[1]
    for _ in range(4):
        out.add((x, y)); out.add((-x, y))
        x, y = -y, x
    return out

def expected(defs, fac, piece, dx, dy):
    """codigo esperado en offset (dx,dy) segun la def; '.' si no hay"""
    d = defs[(fac, piece)]
    key = "%d,%d" % (dx, dy)
    if key in d["cells"]:
        return d["cells"][key]
    if d["sym"] == "all":
        t = (dx, dy)
        for k, c in d["cells"].items():
            x, y = map(int, k.split(","))
            if t in orbit((x, y)):
                return c
    return "."

# ---- paneles: (hoja, faccion, pieza, anchor(col,row), region c0,c1,r0,r1) ------
PANELS = [
    # WA0001 humenex — anclas confirmadas
    ("WA0001", "humenex", "peon",       ( 9, 6),  (8,10, 4, 5)),
    ("WA0001", "humenex", "emperatriz", (22, 7),  (15,22, 0, 7)),
    ("WA0001", "humenex", "emperador",  (28, 7),  (25,32, 6, 7)),
    ("WA0001", "humenex", "espia",      ( 7,18),  (0, 7,11,18)),
    ("WA0001", "humenex", "caballero",  (17,18),  (15,17,16,18)),
    ("WA0001", "humenex", "torre",      (27,18),  (20,27,11,18)),
    # WA0002 elfos — anclas confirmadas
    ("WA0002", "elfos", "centinela",    ( 3, 7),  (2, 4, 5, 7)),
    ("WA0002", "elfos", "dama",         (17, 8),  (10,17, 0, 8)),
    ("WA0002", "elfos", "monarca",      (28, 8),  (26,28, 6, 8)),
    ("WA0002", "elfos", "hostigador",   (12,17),  ( 5,12,10,17)),
    ("WA0002", "elfos", "explorador",   (20,17),  (14,20,10,17)),
    ("WA0002", "elfos", "forestal",     (31,17),  (27,31,13,17)),
    # WA0003 mortifers — confirmadas
    ("WA0003", "mortifers", "carronero",( 3, 9),  (2, 4, 8, 9)),
    ("WA0003", "mortifers", "consorte", (17,10),  (10,17, 3,10)),
    ("WA0003", "mortifers", "tirano",   (26, 8),  (24,26, 6, 8)),
    ("WA0003", "mortifers", "corruptor",( 7,20),  (3, 7,16,20)),
    ("WA0003", "mortifers", "merodeador",(17,20), (13,17,16,20)),
    ("WA0003", "mortifers", "incubo",   (27,20),  (22,27,15,20)),
    # WA0004 bestiarios — confirmadas por imagen
    ("WA0004", "bestiarios", "rahez",   ( 4, 4),  (2, 5, 2, 4)),
    ("WA0004", "bestiarios", "rapaz",   (16,17),  ( 9,16, 9,17)),
    ("WA0004", "bestiarios", "fugaz",   ( 7, 7),  ( 4, 7, 4, 7)),
    ("WA0004", "bestiarios", "edaz",    (36, 7),  (32,36, 3, 7)),
    ("WA0004", "bestiarios", "voraz",   ( 7,17),  ( 0, 7, 9,17)),
    ("WA0004", "bestiarios", "sagaz",   (16,17),  (14,16,15,17)),
    ("WA0004", "bestiarios", "audaz",   (36,17),  (31,36,14,17)),
    ("WA0004", "bestiarios", "lideresa",( 7,10),  ( 5, 7, 8,10)),
    ("WA0004", "bestiarios", "lider",   ( 7,16),  ( 4, 7,13,16)),
    # WA0005 enanos — confirmadas
    ("WA0005", "enanos", "vasallo",     ( 3, 7),  (2, 4, 6, 7)),
    ("WA0005", "enanos", "sultana",     (17, 8),  (14,17, 5, 8)),
    ("WA0005", "enanos", "califa",      (28, 8),  (26,28, 6, 8)),
    ("WA0005", "enanos", "verdugo",     ( 7,16),  ( 3, 7,12,16)),
    ("WA0005", "enanos", "raudo",       (16,16),  (13,16,13,16)),
    ("WA0005", "enanos", "zaguero",     (27,17),  (24,27,14,17)),
    # WA0006 chlontos — confirmadas
    ("WA0006", "chlontos", "zangano",   ( 3, 7),  (2, 4, 5, 7)),
    ("WA0006", "chlontos", "matriarca", (17, 8),  (10,17, 1, 8)),
    ("WA0006", "chlontos", "gerarca",   (27, 8),  (25,27, 5, 8)),
    ("WA0006", "chlontos", "raptor",    ( 7,18),  ( 2, 7,13,18)),
    ("WA0006", "chlontos", "cefiro",    (16,18),  (12,16,14,18)),
    ("WA0006", "chlontos", "hoplita",   (26,18),  (23,26,14,18)),
    # WA0007 aquontes — confirmadas
    ("WA0007", "aquontes", "alevin",    ( 3, 7),  (2, 4, 0, 7)),
    ("WA0007", "aquontes", "mako",      ( 7,18),  (0, 7,10,18)),
    ("WA0007", "aquontes", "anfitrite", (17, 8),  (10,17, 0, 8)),
    ("WA0007", "aquontes", "leviatan",  (26, 8),  (19,26, 0, 8)),
    ("WA0007", "aquontes", "carchar",   (26,18),  (19,26,10,18)),
    ("WA0007", "aquontes", "triton_m1", (13,16),  (12,15,14,16)),
    ("WA0007", "aquontes", "triton_m2", (20,19),  (17,20,18,19)),
    # WA0008 kronturs — confirmadas
    ("WA0008", "kronturs", "mole",      ( 3, 7),  (2, 4, 5, 7)),
    ("WA0008", "kronturs", "zarina",    (16, 8),  ( 9,16, 3, 8)),
    ("WA0008", "kronturs", "zar",       (26, 8),  (24,26, 5, 8)),
    ("WA0008", "kronturs", "ariete",    ( 7,18),  ( 3, 7,14,18)),
    ("WA0008", "kronturs", "dique",     (17,18),  (14,17,15,18)),
    ("WA0008", "kronturs", "goliat",    (27,18),  (22,27,14,18)),
]

# el triton tiene dos minimapas: mov1 usa cells, mov2 usa leg2
SPECIAL = {"triton_m2": "leg2"}

def expected_map(fac, piece):
    """offset -> code esperado tras expandir orbitas"""
    d = defs[(fac, piece)]
    out = {}
    for k, c in d["cells"].items():
        x, y = map(int, k.split(","))
        if d["sym"] == "all":
            for o in orbit((x, y)):
                out[o] = c
        else:
            out[(x, y)] = c
    return out

def bleed_ok(dx, dy, drawn, expmap, d):
    """sangrado de cabecera: el rayo continua mas alla del patron con el
    mismo codigo. Solo celdas alineadas (h/v/diag) tras la ultima del rayo."""
    if dx == 0 and dy == 0: return False
    if dx != 0 and dy != 0 and abs(dx) != abs(dy): return False
    sx = 0 if dx == 0 else (1 if dx > 0 else -1)
    sy = 0 if dy == 0 else (1 if dy > 0 else -1)
    # retrocede hasta encontrar una celda del patron en esa direccion
    x, y = dx - sx, dy - sy
    while abs(x) <= 8 and abs(y) <= 8:
        code = expmap.get((x, y))
        if code is not None:
            return code == drawn
        x -= sx; y -= sy
    return False

VOTES = "--v" in sys.argv
grids = {s: sheet_grid("IMG-20260824-%s.jpg" % s, VOTES)
         for s in ["WA0001", "WA0002", "WA0003", "WA0004", "WA0005",
                   "WA0006", "WA0007", "WA0008"]}

defs = load_defs()
alias = {"triton_m1": "triton", "triton_m2": "triton"}
ANCHORS = {}
total_fails = 0
for sheet, fac, piece, (ax, ay), (c0, c1, r0, r1) in PANELS:
    name = alias.get(piece, piece)
    grid = grids.get(sheet)
    if not grid: continue
    d = defs[(fac, name)]
    if SPECIAL.get(piece) == "leg2":
        expmap = {}
        for k, c in d.get("leg2", {}).items():
            x, y = map(int, k.split(","))
            expmap[(x, y)] = c
    else:
        expmap = expected_map(fac, name)
    drawn = [((c, r), grid[r][c])
             for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)
             if r < len(grid) and c < len(grid[r]) and grid[r][c] not in ".@"]
    # buscar ancla: celda que minimiza discrepancias (favor de la dada)
    def score(bx, by):
        f = 0
        for (c, r), ch in drawn:
            dx, dy = c - bx, r - by
            if dx == 0 and dy == 0:
                continue  # casilla de la pieza (glifo mal clasificado)
            e = expmap.get((dx, dy))
            if e == ch: continue
            if e is None and bleed_ok(dx, dy, ch, expmap, d): continue
            f += 1
        return f
    gx = range(max(0, c0 - 2), min(len(grid[0]), c1 + 3))
    gy = range(max(0, r0 - 2), min(len(grid), r1 + 3))
    best = min([(score(c, r), abs(c - ax) + abs(r - ay), (c, r))
                for r in gy for c in gx])
    nf, _, ba = best
    ANCHORS[(fac, piece)] = ba
    total_fails += nf
    tag = "OK  " if nf == 0 else "FAIL"
    print("%s %s/%s ancla=%s celds=%d" % (tag, fac, name, ba, len(drawn)))
    if nf:
        bx, by = ba
        for (c, r), ch in drawn:
            dx, dy = c - bx, r - by
            if dx == 0 and dy == 0:
                continue
            e = expmap.get((dx, dy))
            if e == ch or (e is None and bleed_ok(dx, dy, ch, expmap, d)):
                continue
            print("      celda(%d,%d) dibujo='%s' esperado='%s'"
                  % (dx, dy, ch, e or "."))
print("==", total_fails, "discrepancias (dibujado->def) ==")

# -- verificación inversa: cada celda del def debe estar dibujada ----
# los paneles dibujan el cuadrante arriba-izquierda (dx<=0, dy<=0):
# para cada offset del def, su representante del cuadrante en la orbita
# debe aparecer dibujado con el mismo codigo.
print("-- inversa: celdas del def ausentes en el dibujo --")
inv = 0
for sheet, fac, piece, (ax, ay), (c0, c1, r0, r1) in PANELS:
    name = alias.get(piece, piece)
    grid = grids.get(sheet)
    if not grid: continue
    d = defs[(fac, name)]
    if SPECIAL.get(piece) == "leg2":
        expmap = {}
        for k, c in d.get("leg2", {}).items():
            x, y = map(int, k.split(","))
            expmap[(x, y)] = c
    else:
        expmap = expected_map(fac, name)
    drawn = {(c, r): grid[r][c]
             for r in range(len(grid)) for c in range(len(grid[r]))}
    bx, by = ANCHORS[(fac, piece)]
    for (dx, dy), code in sorted(expmap.items()):
        if dx > 0 or dy > 0:
            continue  # el cuadrante dibujado es dx<=0, dy<=0
        # representante del cuadrante superior-izquierdo de la orbita
        if d["sym"] == "all" and SPECIAL.get(piece) != "leg2":
            cands = [(x, y) for (x, y) in orbit((dx, dy))
                     if x <= 0 and y <= 0]
        else:
            cands = [(dx, dy)]
        ok = False
        for (ox, oy) in cands:
            ch = drawn.get((bx + ox, by + oy))
            if ch == code:
                ok = True; break
        if not ok:
            inv += 1
            print("MISSING %s/%s (%d,%d)='%s' cands=%s"
                  % (fac, name, dx, dy, code, cands))
print("==", inv, "celdas del def no dibujadas ==")
