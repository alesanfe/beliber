#!/usr/bin/env python3
"""Test del arbitro autoritativo Godot: hello/create/join/play/resync."""
import asyncio
import json
import websockets

URL = "ws://127.0.0.1:7779"


async def recv(ws):
    return json.loads(await ws.recv())


async def recv_until(ws, op, n=20):
    for _ in range(n):
        m = await recv(ws)
        if m.get("op") == op:
            return m
    return {}


async def main():
    fails = 0

    def ok(cond, name):
        nonlocal fails
        print(("  PASS " if cond else "  FAIL ") + name)
        fails += 0 if cond else 1

    h = await websockets.connect(URL)
    m = await recv(h)
    ok(m.get("op") == "hello", "hello del arbitro")

    await h.send(json.dumps({"op": "create",
        "cfg": {"f0": 0, "eq0": 0, "f1": 0, "eq1": 0,
                "mid": False, "stall": 0, "clock": 0}}))
    m = await recv(h)
    ok(m["op"] == "room" and m["side"] == 0, "create -> code")
    code = m["code"]

    c = await websockets.connect(URL)
    await recv(c)  # hello
    await c.send(json.dumps({"op": "join", "code": code}))
    m = await recv(c)
    ok(m["op"] == "room" and m["side"] == 1, "join -> side 1")
    tok1 = m["token"]
    await recv_until(c, "start")

    # jugada auto-referente -> siempre ilegal
    await c.send(json.dumps({"op": "play",
        "from": {"x": 4, "y": 4}, "to": {"x": 4, "y": 4}}))
    m = await recv(c)
    ok(m["op"] == "err", "jugada ilegal rechazada por el servidor")

    # sondear con ambos lados hasta que uno juegue (el orden de salida
    # depende de la facción: primero=Elfos, segundo=Humenex…)
    async def try_side(ws, other):
        for dy_dir in (-1, 1):
            for y in range(8):
                for x in range(8):
                    await ws.send(json.dumps({"op": "play",
                        "from": {"x": x, "y": y},
                        "to": {"x": x, "y": y + dy_dir}}))
                    m = await recv(ws)
                    if m.get("op") == "move":
                        await recv(other)  # eco al rival
                        return True
        return False

    moved = await try_side(h, c)
    if not moved:
        moved = await try_side(c, h)
    ok(moved, "jugada legal validada y difundida con eco")

    # reconexión con resync
    await c.close()
    c2 = await websockets.connect(URL)
    await recv(c2)  # hello
    await c2.send(json.dumps({"op": "rejoin", "code": code,
                              "side": 1, "token": "wrong"}))  # nosec B105
    m = await recv(c2)
    ok(m["op"] == "err", "rejoin con token incorrecto rechazado")
    await c2.send(json.dumps({"op": "rejoin", "code": code,
                              "side": 1, "token": ""}))  # nosec B105
    m = await recv(c2)
    ok(m["op"] == "err", "rejoin con token vacío rechazado")
    await c2.send(json.dumps({"op": "rejoin", "code": code,
                              "side": 1, "token": tok1}))
    m = await recv(c2)
    ok(m["op"] == "room", "rejoin con token válido")
    m = await recv(c2)
    ok(m["op"] == "resync" and len(m["moves"]) == 1,
       "resync devuelve la jugada resuelta")

    # peer en sala no puede encolar (corrompía salas ajenas)
    await h.send(json.dumps({"op": "queue", "prefs": {"f": 0}}))
    m = await recv(h)
    ok(m["op"] == "err", "queue estando en sala rechazado")

    # play malformado: from/to no-dict no debe tumbar el árbitro
    # (recv_until: h puede tener 'offline' pendiente del rejoin)
    await h.send(json.dumps({"op": "play", "from": 5, "to": "x"}))
    m = await recv_until(h, "err")
    ok(m.get("op") == "err", "play con from/to no-dict rechazado")

    # health check: ping devuelve pong con carga actual (sin sala)
    await h.send(json.dumps({"op": "ping"}))
    m = await recv_until(h, "pong")
    ok(m.get("op") == "pong" and isinstance(m.get("rooms"), int),
       "ping -> pong con métricas")

    # resign archivado: un rejoin posterior reconstruye fin limpio
    await c2.send(json.dumps({"op": "play", "resign": True}))
    m = await recv(c2)
    m2 = await recv(c2)
    ops = {m.get("op"), m2.get("op")}
    ok(ops == {"move", "over"}, "resign archivado + over")
    c3 = await websockets.connect(URL)
    await recv(c3)  # hello
    await c3.send(json.dumps({"op": "rejoin", "code": code,
                              "side": 1, "token": tok1}))
    m = await recv(c3)   # room
    m = await recv(c3)   # resync
    ok(m["op"] == "resync" and any(
        isinstance(x, dict) and x.get("resign") for x in m["moves"]),
       "resync incluye la rendición archivada")
    m = await recv(c3)   # over (partida ya cerrada)
    ok(m.get("op") == "over", "over tras rejoin de partida acabada")
    await c3.close()

    # --- matchmaking: dos en cola -> sala auto-creada con cfg fusionada
    q1 = await websockets.connect(URL)
    await recv(q1)  # hello
    await q1.send(json.dumps({"op": "queue", "name": "A",
        "prefs": {"f": 0, "eq": 0, "clock": 0, "mid": False}}))
    m = await recv(q1)
    ok(m["op"] == "queued", "queue: primero en cola")
    q2 = await websockets.connect(URL)
    await recv(q2)  # hello
    await q2.send(json.dumps({"op": "queue", "name": "B",
        "prefs": {"f": 4, "eq": 2, "clock": 0, "mid": True,
                  "stall": 60,
                  "rows": ["........", "..SS....", "RRRRRRRR",
                           "........", "........"]}}))
    m = await recv(q2)
    ok(m["op"] == "queued", "queue: segundo confirmado")
    m = await recv(q2)
    ok(m["op"] == "room" and m["side"] == 1
       and m["cfg"]["f1"] == 4 and m["cfg"]["mid"],
       "queue: segundo emparejado con cfg fusionada")
    ok(m["cfg"].get("stall") == 60,
       "queue: stall fusionado en cfg")
    ok("rows1" in m["cfg"],
       "queue: filas custom viajan al emparejar")
    m = await recv(q1)
    ok(m["op"] == "room" and m["side"] == 0,
       "queue: primero emparejado side=0")
    # el PRIMERO encolado también recibe la cfg fusionada — antes el
    # mensaje 'room' de _on_create no la llevaba y desplegaba con
    # sus preferencias locales de J2 (desync con el árbitro)
    ok(m["cfg"]["f1"] == 4 and m["cfg"].get("stall") == 60,
       "queue: primero recibe cfg fusionada")
    await recv_until(q1, "start")
    await recv_until(q2, "start")
    await q1.close(); await q2.close()

    await h.close(); await c2.close()
    print("== %s ==" % ("OK" if fails == 0 else f"{fails} FALLOS"))
    return fails


raise SystemExit(asyncio.run(main()))
