extends SceneTree

## Exporta el mapa de celdas de cada pieza para compararlo con los
## diagramas de referencia (tools/read_diagrams.py).
## Formato por pieza:
##   ### <faccion>/<nombre_en_minuscula>
##   sym=<all|lit>
##   <dx,dy>=<code> ...

func _init() -> void:
	for f in PiecesData.all():
		for letter in f.pieces:
			var p: Dictionary = f.pieces[letter]
			var slug := String(p.name).to_lower() \
				.replace("á","a").replace("é","e").replace("í","i") \
				.replace("ó","o").replace("ú","u").replace("ñ","n")
			print("### %s/%s" % [f.id, slug])
			print("sym=" + String(p.get("sym", "all")))
			var cells: Dictionary = p.cells
			for key in cells:
				print("%s=%s" % [key, cells[key]])
			var leg2: Variant = p.get("leg2")
			if leg2 != null:
				for key in leg2:
					print("leg2:%s=%s" % [key, leg2[key]])
	quit()
