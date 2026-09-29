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
                              "side": 1, "token": "wrong"}))
    m = await recv(c2)
    ok(m["op"] == "err", "rejoin con token vacío rechazado")
    await c2.send(json.dumps({"op": "rejoin", "code": code,
                              "side": 1, "token": tok1}))
    m = await recv(c2)
    ok(m["op"] == "room", "rejoin con token válido")
    m = await recv(c2)
    ok(m["op"] == "resync" and len(m["moves"]) == 1,
       "resync devuelve la jugada resuelta")

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
        "prefs": {"f": 4, "eq": 0, "clock": 0, "mid": True}}))
    m = await recv(q2)
    ok(m["op"] == "queued", "queue: segundo confirmado")
    m = await recv(q2)
    ok(m["op"] == "room" and m["side"] == 1
       and m["cfg"]["f1"] == 4 and m["cfg"]["mid"],
       "queue: segundo emparejado con cfg fusionada")
    m = await recv(q1)
    ok(m["op"] == "room" and m["side"] == 0,
       "queue: primero emparejado side=0")
    await recv_until(q1, "start")
    await recv_until(q2, "start")
    await q1.close(); await q2.close()

    await h.close(); await c2.close()
    print("== %s ==" % ("OK" if fails == 0 else f"{fails} FALLOS"))
    return fails


raise SystemExit(asyncio.run(main()))
