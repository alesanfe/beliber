#!/usr/bin/env python3
"""Test del ladder ELO en el arbitro Godot."""
import asyncio
import json
import uuid
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

    # pids únicos por run: el host emite un token la primera vez que ve
    # un pid; reutilizar el mismo pid sin token degrada a invitado
    pid_a = f"pid-alice-{uuid.uuid4().hex[:8]}"
    pid_b = f"pid-bob-{uuid.uuid4().hex[:8]}"

    h = await websockets.connect(URL)
    await recv(h)  # hello
    await h.send(json.dumps({"op": "create", "name": "alice",
        "pid": pid_a,
        "cfg": {"f0": 0, "eq0": 0, "f1": 0, "eq1": 0, "clock": 0}}))
    m = await recv_until(h, "room")
    code = m["code"]

    c = await websockets.connect(URL)
    await recv(c)
    await c.send(json.dumps({"op": "join", "code": code,
                             "name": "bob", "pid": pid_b}))
    # id_tok llega ANTES de room (se emite dentro de _on_join)
    got_tok, room = "", {}
    for _ in range(20):
        m = await recv(c)
        if m.get("op") == "id_tok": got_tok = m["tok"]
        if m.get("op") == "room": room = m; break
    ok(room.get("side") == 1, "join con nick")
    # el host emite token de identidad al primer claim del pid
    ok(got_tok != "", "host emite id_tok al registrar pid")
    # drenar peer/start en ambos lados
    await recv_until(h, "start")
    await recv_until(c, "start")

    # las partidas de <4 plies no mueven ELO (anti-farming): jugar
    # al menos 4 plies reales antes de rendir
    async def try_one(ws, other):
        for dy in (-1, 1):
            for y in range(8):
                for x in range(8):
                    await ws.send(json.dumps({"op": "play",
                        "from": {"x": x, "y": y},
                        "to": {"x": x, "y": y + dy}}))
                    m = await recv(ws)
                    if m.get("op") == "move":
                        await recv_until(other, "move")
                        return True
        return False
    plies = 0
    while plies < 4:
        moved = await try_one(h, c) or await try_one(c, h)
        if not moved:
            break
        plies += 1
    ok(plies >= 4, f"4 plies jugados para que cuente el rating "
                   f"({plies})")

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

    # robar pid ajeno sin token -> invitado (id_err), sin rating
    e = await websockets.connect(URL)
    await recv(e)
    await e.send(json.dumps({"op": "create", "name": "mallory",
        "pid": pid_a, "tok": "bogus",
        "cfg": {"f0": 0, "eq0": 0, "f1": 0, "eq1": 0, "clock": 0}}))
    err = await recv_until(e, "id_err")
    ok(err.get("op") == "id_err", "pid ajeno sin token -> id_err")
    await e.close()

    # ladder
    await h.send(json.dumps({"op": "ladder"}))
    m = await recv(h)
    ok(m["op"] == "ladder" and m["rows"][0]["name"] == "alice",
       "ladder devuelve ranking")

    # .bak de ratings: atomic_write lo mantiene como última versión
    # escrita con éxito (restore manual ante corrupción)
    import os
    rpath = os.environ.get("BELIBER_RATINGS", "")
    if rpath:
        ok(os.path.exists(rpath + ".bak"), ".bak de ratings existe")

    await h.close(); await c.close()
    print("== %s ==" % ("OK" if fails == 0 else f"{fails} FALLOS"))
    return fails


raise SystemExit(asyncio.run(main()))
