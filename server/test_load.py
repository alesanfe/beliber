#!/usr/bin/env python3
"""Test de carga del host autoritativo: conexiones masivas concurrentes,
salas y ráfagas de mensajes. Verifica que el servidor sigue respondiendo
(ping) tras el diluvio — prueba de capacidad, no de corrección."""
import asyncio
import json
import sys
import websockets

URL = "ws://127.0.0.1:7779"
N_CONN = 60        # conexiones simultáneas
N_ROOMS = 20       # salas a crear/emparejar


async def recv_until(ws, op, n=40):
    for _ in range(n):
        m = json.loads(await ws.recv())
        if m.get("op") == op:
            return m
    return {}


async def main():
    fails = 0

    def ok(cond, name):
        nonlocal fails
        print(("  PASS " if cond else "  FAIL ") + name)
        fails += 0 if cond else 1

    # oleada de conexiones concurrentes
    conns = await asyncio.gather(*[websockets.connect(URL)
                                   for _ in range(N_CONN)])
    await asyncio.gather(*[recv_until(ws, "hello") for ws in conns])
    ok(len(conns) == N_CONN, f"{N_CONN} conexiones simultáneas aceptadas")

    # crear+emparejar salas en paralelo
    async def pair(i):
        a, b = conns[2 * i], conns[2 * i + 1]
        await a.send(json.dumps({"op": "create", "name": f"a{i}",
            "cfg": {"f0": 0, "eq0": 0, "f1": 0, "eq1": 0, "clock": 0}}))
        rm = await recv_until(a, "room")
        await b.send(json.dumps({"op": "join", "code": rm["code"],
                                 "name": f"b{i}"}))
        rj = await recv_until(b, "room")
        return rm.get("op") == "room" and rj.get("op") == "room"
    res = await asyncio.gather(*[pair(i) for i in range(N_ROOMS)])
    ok(all(res), f"{N_ROOMS} salas creadas y emparejadas")

    # ráfaga: todos los sockets libres mandan ping+chat a la vez
    free = conns[2 * N_ROOMS:]
    for ws in conns[:2 * N_ROOMS] + free:
        for _ in range(5):
            await ws.send(json.dumps({"op": "ping"}))
            await ws.send(json.dumps({"op": "chat", "text": "spam"}))
    alive = False
    probe = await websockets.connect(URL)
    await recv_until(probe, "hello")
    await probe.send(json.dumps({"op": "ping"}))
    m = await recv_until(probe, "pong")
    alive = m.get("op") == "pong" and m.get("rooms", 0) >= N_ROOMS
    ok(alive, "host responde tras la ráfaga (pong con métricas)")

    await asyncio.gather(*[ws.close() for ws in conns])
    await probe.close()
    print("== %s ==" % ("OK" if fails == 0 else f"{fails} FALLOS"))
    return fails


raise SystemExit(asyncio.run(main()))
