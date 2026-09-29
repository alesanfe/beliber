#!/usr/bin/env python3
"""Test del ladder ELO en el arbitro Godot."""
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
    await recv(h)  # hello
    await h.send(json.dumps({"op": "create", "name": "alice",
        "cfg": {"f0": 0, "eq0": 0, "f1": 0, "eq1": 0, "clock": 0}}))
    m = await recv(h)
    code = m["code"]

    c = await websockets.connect(URL)
    await recv(c)
    await c.send(json.dumps({"op": "join", "code": code, "name": "bob"}))
    m = await recv(c)
    ok(m["side"] == 1, "join con nick")
    # drenar peer/start en ambos lados
    await recv_until(h, "start")
    await recv_until(c, "start")

    # bob se rinde -> alice gana -> rating broadcast
    await c.send(json.dumps({"op": "play", "resign": True}))
    msgs = [await recv(h) for _ in range(3)]
    ops = [x.get("op") for x in msgs]
    ok("move" in ops and "over" in ops and "rating" in ops,
       "resign -> move + over + rating")
    rt = next(x for x in msgs if x.get("op") == "rating")
    ok(rt["you"]["alice"]["elo"] > 1200, "ganador sube ELO")
    ok(rt["you"]["bob"]["elo"] < 1200, "perdedor baja ELO")
    ok(rt["you"]["alice"]["wins"] >= 1, "victoria contabilizada")

    # ladder
    await h.send(json.dumps({"op": "ladder"}))
    m = await recv(h)
    ok(m["op"] == "ladder" and m["rows"][0]["name"] == "alice",
       "ladder devuelve ranking")

    await h.close(); await c.close()
    print("== %s ==" % ("OK" if fails == 0 else f"{fails} FALLOS"))
    return fails


raise SystemExit(asyncio.run(main()))
