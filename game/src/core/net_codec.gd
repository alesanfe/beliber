class_name NetCodec
extends RefCounted

## Serialización del protocolo del relay: convierte Vector2i a
## {"x","y"} (y viceversa) recursivamente dentro de Arrays y
## Dictionaries. Compartido por cliente (main.gd), servidor
## autoritativo (host.gd) y tests E2E — antes estaba triplicado.

static func enc(v: Variant) -> Variant:
	if v is Vector2i:
		return {"x": v.x, "y": v.y}
	if v is Array:
		var a := []
		for e in v: a.append(enc(e))
		return a
	if v is Dictionary:
		var d := {}
		for k in v: d[k] = enc(v[k])
		return d
	return v

static func dec(v: Variant) -> Variant:
	if v is Dictionary:
		if v.size() == 2 and v.has("x") and v.has("y"):
			return Vector2i(int(v.x), int(v.y))
		var d := {}
		for k in v: d[k] = dec(v[k])
		return d
	if v is Array:
		var a := []
		for e in v: a.append(dec(e))
		return a
	return v
