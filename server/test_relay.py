#!/usr/bin/env python3
"""Test del relay: create -> join -> move -> resync."""
import asyncio
import json
import websockets

URL = "ws://127.0.0.1:7778"


async def recv(ws):
    return json.loads(await ws.recv())


async def main():
    fails = 0

    def ok(cond, name):
        nonlocal fails
        print(("  PASS " if cond else "  FAIL ") + name)
        fails += 0 if cond else 1

    # host crea sala
    h = await websockets.connect(URL)
    await h.send(json.dumps({"op": "create", "cfg": {"f0": 1}}))
    m = await recv(h)
    ok(m["op"] == "room" and m["side"] == 0, "create -> code")
    code = m["code"]

    # cliente entra
    c = await websockets.connect(URL)
    await c.send(json.dumps({"op": "join", "code": code}))
    m = await recv(c)
    ok(m["op"] == "room" and m["side"] == 1, "join -> side 1")
    token1 = m["token"]
    m = await recv(c)
    ok(m["op"] == "start", "cliente recibe start")
    m = await recv(h)
    ok(m["op"] == "peer", "host avisado del peer")
    m = await recv(h)
    ok(m["op"] == "start", "host recibe start")

    # host mueve -> cliente lo recibe
    await h.send(json.dumps({"op": "move",
                             "mv": {"from": {"x": 1, "y": 6},
                                    "to": {"x": 1, "y": 4}}}))
    m = await recv(c)
    ok(m["op"] == "move" and m["mv"]["to"]["y"] == 4,
       "jugada retransmitida")

    # desconexión + reconexión con resync
    await c.close()
    m = await recv(h)
    ok(m["op"] == "offline" and m["on"], "host ve rival offline")

    c2 = await websockets.connect(URL)
    await c2.send(json.dumps({"op": "rejoin", "code": code,
                              "side": 1, "token": token1}))
    m = await recv(c2)
    ok(m["op"] == "room", "rejoin aceptado")
    m = await recv(c2)
    ok(m["op"] == "resync" and len(m["moves"]) == 1,
       "resync devuelve el historial")
    m = await recv(h)
    ok(m["op"] == "offline" and not m["on"], "host ve rival online")

    # token incorrecto -> error
    bad = await websockets.connect(URL)
    await bad.send(json.dumps({"op": "rejoin", "code": code,
                               "side": 1, "token": "wrong"}))
    m = await recv(bad)
    ok(m["op"] == "err", "token inválido rechazado")

    # sala inexistente
    j2 = await websockets.connect(URL)
    await j2.send(json.dumps({"op": "join", "code": "ZZZZ"}))
    m = await recv(j2)
    ok(m["op"] == "err", "sala inexistente rechazada")
    await j2.close()

    # --- matchmaking: dos en cola se emparejan en sala automática ---
    q1 = await websockets.connect(URL)
    await q1.send(json.dumps({"op": "queue",
                              "prefs": {"f": 0, "eq": 0}}))
    m = await recv(q1)
    ok(m["op"] == "queued", "queue: confirmado en cola")
    q2 = await websockets.connect(URL)
    await q2.send(json.dumps({"op": "queue",
                              "prefs": {"f": 5, "eq": 1}}))
    m = await recv(q2)
    ok(m["op"] == "queued", "queue: segundo confirmado")
    m = await recv(q2)
    ok(m["op"] == "room" and m["side"] == 1,
       "queue: segundo recibe sala side=1")
    ok(m["cfg"]["f1"] == 5, "queue: cfg fusionada (facción J2)")
    m = await recv(q1)
    ok(m["op"] == "room" and m["side"] == 0,
       "queue: primero recibe sala side=0")
    m = await recv(q1)
    ok(m["op"] == "peer", "queue: aviso de rival")
    m = await recv(q1)
    ok(m["op"] == "start", "queue: start para el primero")
    m = await recv(q2)
    ok(m["op"] == "peer", "queue: peer para el segundo")
    m = await recv(q2)
    ok(m["op"] == "start", "queue: start para el segundo")
    # dequeue no rompe nada tras emparejar
    q3 = await websockets.connect(URL)
    await q3.send(json.dumps({"op": "queue", "prefs": {"f": 2}}))
    m = await recv(q3)
    ok(m["op"] == "queued", "cola tras emparejar")
    await q3.send(json.dumps({"op": "dequeue"}))
    m = await recv(q3)
    ok(m["op"] == "dequeued", "dequeue confirma")
    await q1.close(); await q2.close(); await q3.close()

    await h.close(); await c2.close(); await bad.close()
    print("== %s ==" % ("OK" if fails == 0 else f"{fails} FALLOS"))
    return fails


raise SystemExit(asyncio.run(main()))
