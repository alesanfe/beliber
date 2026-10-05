#!/usr/bin/env python3
"""
Auditoría: compara el mapa de celdas de cada pieza de pieces_data.gd
contra la transcripción de los diagramas de referencia.

Uso: python audit_pieces.py
"""
import os, re

HERE = os.path.dirname(__file__)
REF = os.path.join(HERE, "_ref2.txt")
DUMP = os.path.join(HERE, "_cells_dump.txt")

# --- parsear la transcripción de los crops -------------------------------
ref = {}
name = None
rows = []
for line in open(REF, encoding="utf-8"):
    line = line.strip()
    if line.startswith("###"):
        if name and rows:
            ref[name] = rows
        name = line[3:].strip().rsplit(".", 1)[0]
        rows = []
    elif re.fullmatch(r"[.@mcojgJtTwpP3eEdkKqQ?]{8}", line):
        rows.append(line)
if name and rows:
    ref[name] = rows

# --- parsear el dump del juego -------------------------------------------
ours = {}
key = None
for line in open(DUMP, encoding="utf-8", errors="replace"):
    line = line.strip()
    if line.startswith("###"):
        key = line[3:].strip()
        ours[key] = {"sym": "all", "cells": {}}
    elif key and line.startswith("sym="):
        ours[key]["sym"] = line[4:]
    elif key and "=" in line and re.match(r"-?\d+,-?\d+=", line):
        xy, code = line.split("=")
        x, y = xy.split(",")
        ours[key]["cells"][(int(x), int(y))] = code

def expand_d4(cells):
    """las 8 transformaciones diédricas, como _offsets() de MoveGen"""
    out = {}
    for (x, y), c in cells.items():
        v = (x, y)
        seen = set()
        for _r in range(4):
            for t in (v, (-v[0], v[1])):
                if t not in seen:
                    seen.add(t)
                    out.setdefault(t, c)
            v = (-v[1], v[0])
    return out

def crop_to_slug(n):
    return n.lower()

# mapa slug_crop -> clave de ours: "faccion/pieza"
def norm(s):
    return s.replace("á","a").replace("é","e").replace("í","i") \
            .replace("ó","o").replace("ú","u").replace("ñ","n")

# alias: nombres de crop -> facción/pieza
ALIASES = {
    "humenex_espia": "humenex/espia",
    "elfos_dama": "elfos/dama",
}

PFX = {"aqu_": "aquontes", "chl_": "chlontos", "elf_": "elfos",
       "ena_": "enanos", "hum_": "humenex", "kro_": "kronturs",
       "mor_": "mortifers", "bes_": "bestiarios",
       "aquontes_": "aquontes", "chlontos_": "chlontos",
       "elfos_": "elfos", "enanos_": "enanos", "humenex_": "humenex",
       "kronturs_": "kronturs", "mortifers_": "mortifers",
       "bestiarios_": "bestiarios"}

def lookup(crop_name):
    n = norm(crop_name)
    if n in ALIASES:
        return ALIASES[n]
    for pfx, fac in PFX.items():
        if n.startswith(pfx):
            return fac + "/" + n[len(pfx):]
    return None

checked = missing = mismatched = 0
report = []
unmatched_crops = []
unmatched_pieces = set(ours.keys())

for crop_name, grid in sorted(ref.items()):
    if len(grid) != 8:
        continue
    k = lookup(crop_name)
    if k is None or k not in ours:
        continue
    unmatched_pieces.discard(k)
    piece = ours[k]
    cells = piece["cells"] if piece["sym"] == "lit" else expand_d4(piece["cells"])
    # "all": la pieza siempre ancla en la esquina (7,7) aunque el '@'
    # del sprite no se clasifique; "lit": probar las 64 anclas
    cand = [(7, 7)] if piece["sym"] == "all" else \
        [(x, y) for y in range(8) for x in range(8)]
    best = None
    for (ax, ay) in cand:
        for flip in (1, -1):
            errs = []
            for y in range(8):
                for x in range(8):
                    ch = grid[y][x]
                    if ch in (".", "@"): continue
                    off = (x - ax, (y - ay) * flip)
                    got = cells.get(off)
                    if got != ch:
                        errs.append((x, y, ch, got))
            if best is None or len(errs) < len(best[2]):
                best = ((ax, ay), flip, errs)
    (ax, ay), flip, errs = best
    checked += 1
    # filtrar artefactos: la letra de la pieza se dibuja grande encima
    # del tablero y cae en filas 0-1 aisladas del patrón real
    def aislado(x, y):
        for yy in range(max(0, y - 1), min(8, y + 2)):
            for xx in range(max(0, x - 1), min(8, x + 2)):
                if (xx, yy) != (x, y) and grid[yy][xx] not in ".@":
                    return False
        return True
    reales = [e for e in errs if not aislado(e[0], e[1])]
    arte = [e for e in errs if aislado(e[0], e[1])]
    if reales:
        mismatched += 1
        report.append(f"X {crop_name} anchor=({ax},{ay}) flip={flip}")
        for (x, y, want, got) in reales:
            report.append(f"    ({x},{y}) ref='{want}' juego='{got}'")
        if arte:
            report.append(f"    (artefactos: {len(arte)} celdas aisladas)")
    else:
        report.append(f"OK {crop_name}" +
                      (f"  [{len(arte)} artefactos de letra]" if arte else ""))

print(f"piezas comparadas: {checked}  (con diferencias: {mismatched})")
for r in report:
    print(r)
if unmatched_pieces:
    print("\nsin crop de referencia:")
    for p in sorted(unmatched_pieces):
        print("  ", p)
