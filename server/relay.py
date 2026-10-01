#!/usr/bin/env python3
"""
Relay WebSocket para Beliber — salas por código, retransmisión de
jugadas y resincronización tras desconexión.

Uso:
    python relay.py [host] [puerto]     # defecto: 0.0.0.0:7778

Protocolo (JSON):
  cliente -> servidor
    {"op": "create", "cfg": {...}}        crea sala; devuelve code y side=0
    {"op": "join",   "code": "AB12"}      entra a la sala; devuelve cfg y side=1
    {"op": "rejoin", "code": "…", "side": n, "token": "…"}
    {"op": "move",   "mv": {...}}         retransmitida al rival y archivada
    {"op": "chat",   "text": "…"}         opcional
    {"op": "leave"}                       abandono limpio
    {"op": "queue",  "prefs": {f,eq,clock,mid,stall}}   matchmaking
    {"op": "dequeue"}                     salir de la cola

  servidor -> cliente
    {"op": "queued","n": k}    {"op": "dequeued"}
    {"op": "room",  "code": "AB12", "side": 0, "token": "…"}
    {"op": "peer",  "side": 1, "cfg": {...}}   al host cuando entra J2
    {"op": "start"}                             a ambos cuando hay 2
    {"op": "move",  "mv": {...}, "n": k}        jugada retransmitida
    {"op": "resync","moves": [...], "side": n}  tras rejoin
    {"op": "offline", "on": true/false}         rival ausente/presente
    {"op": "over",  "reason": "leave"}          rival abandonó
    {"op": "err",   "msg": "…"}

El servidor guarda la lista de jugadas, de modo que un cliente que se
reconecta recibe la partida completa y la reconstruye localmente.
"""

import asyncio
import json
import secrets
import string
import sys
import time

try:
    import websockets
except ImportError:
    print("Falta 'websockets':  pip install websockets")
    sys.exit(1)

HOST = sys.argv[1] if len(sys.argv) > 1 else "0.0.0.0"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 7778
ROOM_TTL = 3600 * 4          # una sala vive 4 h tras quedar vacía
MOVE_LIMIT = 5000            # protección básica


class Room:
    def __init__(self, code: str):
        self.code = code
        self.cfg = {}
        self.moves: list = []           # historial de jugadas (resync)
        self.sides = [None, None]       # websockets por lado
        self.tokens = ["", ""]          # tokens de reconexión
        self.empty_since = time.time()
        self.over = False               # resign/tablas archivados

    def ws_of(self, side: int):
        return self.sides[side]

    def other(self, side: int) -> int:
        return 1 - side


rooms: dict = {}
queue: list = []            # [(ws, prefs)] esperando emparejamiento


def new_code() -> str:
    # secrets también en el código: es la única credencial para
    # entrar a una sala y con random era predecible
    while True:
        c = "".join(secrets.choice(
            string.ascii_uppercase + string.digits) for _ in range(4))
        if c not in rooms:
            return c


def new_token() -> str:
    # secrets: el token guarda el rejoin — con random (Mersenne)
    # un rival podría predecirlo y suplantar la sesión
    return "".join(secrets.choice(string.ascii_letters + string.digits)
                   for _ in range(24))


async def send(ws, msg: dict):
    try:
        await ws.send(json.dumps(msg))
    except websockets.ConnectionClosed:
        pass


async def create(ws, msg):
    code = new_code()
    r = Room(code)
    r.cfg = msg.get("cfg", {})
    r.sides[0] = ws
    r.tokens[0] = new_token()
    rooms[code] = r
    await send(ws, {"op": "room", "code": code, "side": 0,
                    "token": r.tokens[0]})
    return code, r


async def join(ws, msg):
    code = str(msg.get("code", "")).upper()
    r = rooms.get(code)
    if r is None:
        # 'return await send(...)' devolvía None → el desempaquetado
        # "code, room = await join()" lanzaba TypeError y mataba el socket
        await send(ws, {"op": "err", "msg": "Sala inexistente"})
        return None, None
    if r.sides[1] is not None:
        await send(ws, {"op": "err", "msg": "Sala llena"})
        return None, None
    if r.sides[0] is None:
        # sala con el host caído: notificar a None.send() mataba el
        # handler del recién llegado (AttributeError sin capturar)
        await send(ws, {"op": "err", "msg": "Sala cerrada"})
        return None, None
    # los overrides de piezas del invitado viajan en el join — unión
    # por facción con los del creador (misma fusión que el árbitro)
    jo = msg.get("ovr")
    if isinstance(jo, dict):
        ovr = r.cfg.setdefault("ovr", {})
        for fid in jo:
            ovr[fid] = jo[fid]
    r.sides[1] = ws
    r.tokens[1] = new_token()
    await send(ws, {"op": "room", "code": code, "side": 1,
                    "token": r.tokens[1], "cfg": r.cfg})
    await send(r.sides[0], {"op": "peer", "side": 1})
    # el 'start' lleva la cfg FINAL (ovr del invitado ya fusionado):
    # el lado 0 la recibe aquí por primera vez y la aplica al arrancar
    await send(ws, {"op": "start", "cfg": r.cfg})
    await send(r.sides[0], {"op": "start", "cfg": r.cfg})
    # si el host ya jugó, resincronizar al que entra tarde
    if r.moves:
        await send(ws, {"op": "resync", "moves": r.moves, "side": 1})
    return code, r


async def rejoin(ws, msg):
    code = str(msg.get("code", "")).upper()
    try:
        side = int(msg.get("side", -1))
    except (TypeError, ValueError):
        side = -1
    token = str(msg.get("token", ""))
    r = rooms.get(code)
    # token vacío: sin esto un extraño ocupaba el hueco libre de la
    # sala (tokens[side]=="" aún no emitido) sin haber hecho join
    if r is None or side not in (0, 1) or not token \
            or r.tokens[side] != token:
        await send(ws, {"op": "err", "msg": "Reconexión inválida"})
        return None, None
    # si el hueco sigue ocupado por otro socket vivo, el viejo pierde
    # la sesión (antes quedaba escuchando una sala que ya no era suya)
    old = r.sides[side]
    if old is not None and old is not ws:
        await send(old, {"op": "err", "msg": "Sesión reemplazada"})
    r.sides[side] = ws
    await send(ws, {"op": "room", "code": code, "side": side,
                    "token": token, "cfg": r.cfg})
    await send(ws, {"op": "resync", "moves": r.moves, "side": side})
    other = r.other(side)
    if r.sides[other] is not None:
        await send(r.sides[other], {"op": "offline", "on": False})
    return code, r


def _alive(ws) -> bool:
    """¿El socket sigue utilizable? Compat: websockets legacy expone
    .open, la API asyncio nueva .state (OPEN == 1)."""
    o = getattr(ws, "open", None)
    if o is not None:
        return bool(o)
    s = getattr(ws, "state", None)
    return s is None or int(s) == 1


async def queue_up(ws, msg):
    """Matchmaking: el cliente entra a la cola; al haber 2 se crea la
    sala automáticamente y se fusionan las preferencias de cada lado."""
    if any(w is ws for w, _ in queue):
        return
    prefs = msg.get("prefs", {})
    queue.append((ws, prefs))
    await send(ws, {"op": "queued", "n": len(queue)})
    if len(queue) < 2:
        return None, None
    (a, pa), (b, pb) = queue.pop(0), queue.pop(0)
    # sockets que murieron encolados (TCP half-open): el vivo se
    # reencola — sin esto quedaba en sala con side0 muerto hasta TTL
    if not (_alive(a) and _alive(b)):
        for w, p in ((a, pa), (b, pb)):
            if _alive(w):
                queue.append((w, p))
                await send(w, {"op": "queued", "n": len(queue)})
        return None, None
    r = Room(new_code())
    r.cfg = {"f0": pa.get("f", 0), "eq0": pa.get("eq", 0),
             "f1": pb.get("f", 0), "eq1": pb.get("eq", 0),
             "mid": pa.get("mid") or pb.get("mid"),
             "stall": pa.get("stall") or pb.get("stall") or 0,
             "clock": pa.get("clock") or pb.get("clock") or 0}
    # ejércitos custom: las filas viajan en prefs ("rows"), si no cada
    # lado desplegaría su propio archivo local → posiciones distintas
    if "rows" in pa: r.cfg["rows0"] = pa["rows"]
    if "rows" in pb: r.cfg["rows1"] = pb["rows"]
    # overrides de piezas de ambos lados (unión por facción, igual
    # que el árbitro Godot — sin ellos cada lado generaba legales
    # con defs distintas)
    ovr = {}
    for pr in (pa, pb):
        o = pr.get("ovr")
        if isinstance(o, dict):
            ovr.update(o)
    if ovr: r.cfg["ovr"] = ovr
    rooms[r.code] = r
    for w, s in ((a, 0), (b, 1)):
        r.sides[s] = w
        r.tokens[s] = new_token()
        await send(w, {"op": "room", "code": r.code, "side": s,
                       "token": r.tokens[s], "cfg": r.cfg})
    await send(a, {"op": "peer", "side": 1})
    await send(b, {"op": "peer", "side": 0})
    await send(a, {"op": "start"})
    await send(b, {"op": "start"})
    return r.code, r


async def queue_leave(ws):
    queue[:] = [(w, p) for w, p in queue if w is not ws]
    await send(ws, {"op": "dequeued"})


async def relay_move(ws, msg, r: Room, side: int):
    if len(r.moves) >= MOVE_LIMIT or r.over:
        return await send(ws, {"op": "err", "msg": "Partida cerrada"})
    mv = msg.get("mv", {})
    if not isinstance(mv, dict):
        # un mv arbitrario se archivaba tal cual y corrompía el
        # resync de ambos clientes (y hasta 320MB de historial)
        return await send(ws, {"op": "err", "msg": "mv inválido"})
    # estampar el lado emisor: el cliente declaraba 'side' en resigns
    # y un side falsificado rendía al rival en los resync
    if mv.get("resign") or "draw" in mv:
        mv["side"] = side
    r.moves.append(mv)
    if mv.get("resign") or mv.get("draw") in ("accept", True):
        # la partida terminó: jugadas posteriores no se archivan
        # (un resync las intentaba sobre tm.over → "Resync corrupto")
        r.over = True
    other = r.other(side)
    if r.sides[other] is not None:
        await send(r.sides[other],
                   {"op": "move", "mv": mv, "n": len(r.moves)})


async def leave(ws, r: Room, side: int):
    other = r.other(side)
    if r.sides[other] is not None:
        await send(r.sides[other], {"op": "over", "reason": "leave"})
    rooms.pop(r.code, None)


async def handle(ws):
    room: Room | None = None
    side = -1
    # límites de entrada: flood (>30 msg/s) = conexión cerrada;
    # el tamaño lo corta max_size en websockets.serve
    win_t, win_n = time.monotonic(), 0
    try:
        async for raw in ws:
            win_n += 1
            if time.monotonic() - win_t >= 1.0:
                win_t, win_n = time.monotonic(), 0
            elif win_n > 30:
                await ws.close()
                break
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(msg, dict):
                continue   # "[1,2]" o "5": .get("op") mataba el handler
            op = msg.get("op")
            # Un ws ya asignado a una sala no puede abrir otra: dejaba
            # sides[] huérfanos (sala zombie sin expirar ni avisar).
            if op in ("create", "join", "rejoin", "queue") \
                    and room is not None:
                await send(ws, {"op": "err",
                                "msg": "Ya estás en una sala"})
                continue
            if op == "create":
                queue[:] = [(w, p) for w, p in queue if w is not ws]
                code, room = await create(ws, msg)
                side = 0
            elif op == "join":
                queue[:] = [(w, p) for w, p in queue if w is not ws]
                code, room = await join(ws, msg)
                side = 1 if room is not None else -1
            elif op == "rejoin":
                queue[:] = [(w, p) for w, p in queue if w is not ws]
                code, room = await rejoin(ws, msg)
                # int() sobre string no numérico lanzaba ValueError
                # y cerraba la conexión silenciosamente
                try:
                    side = int(msg.get("side", -1)) \
                        if room is not None else -1
                except (TypeError, ValueError):
                    side = -1
            elif op == "queue":
                code, room = await queue_up(ws, msg)
                side = 0 if room is not None and room.sides[0] is ws \
                    else (1 if room is not None else -1)
            elif op == "dequeue":
                await queue_leave(ws)
            elif room is None or side < 0:
                await send(ws, {"op": "err", "msg": "No estás en sala"})
            elif op == "move":
                await relay_move(ws, msg, room, side)
            elif op == "leave":
                await leave(ws, room, side)
                room = None
            elif op == "chat":
                other = room.other(side)
                if room.sides[other] is not None:
                    # msg.get: un chat sin "text" mataba el handler
                    # entero (KeyError → cierre silencioso)
                    await send(room.sides[other],
                               {"op": "chat",
                                "text": str(msg.get("text", ""))[:200]})
    except websockets.ConnectionClosed:
        pass
    finally:
        queue[:] = [(w, p) for w, p in queue if w is not ws]
        # marcar al rival como offline; la sala sigue viva para rejoin
        if room is not None and side in (0, 1) \
                and room.code in rooms \
                and room.sides[side] is ws:
            # 'is ws': tras un rejoin el socket viejo cerraba y liberaba
            # el asiento del nuevo → un join externo lo ocupaba sin token
            room.sides[side] = None
            other = room.other(side)
            if room.sides[other] is not None:
                await send(room.sides[other],
                           {"op": "offline", "on": True})
            if room.sides[0] is None and room.sides[1] is None:
                room.empty_since = time.time()


async def janitor():
    while True:
        await asyncio.sleep(300)
        now = time.time()
        for c in [c for c, r in rooms.items()
                  if r.sides[0] is None and r.sides[1] is None
                  and now - r.empty_since > ROOM_TTL]:
            del rooms[c]


async def main():
    async with websockets.serve(handle, HOST, PORT,
                                max_size=64 * 1024):
        asyncio.create_task(janitor())
        print(f"Beliber relay en ws://{HOST}:{PORT}")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
