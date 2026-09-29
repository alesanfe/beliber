extends SceneTree
## Smoke test: instancia la escena principal y fuerza _build_game con
## tutorial activo para cubrir los nuevos paneles (bandejas, checklist).
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var root := scene.instantiate()
	self.root.add_child(root)
	await process_frame
	# arranca una partida tutorial (Humenex vs Elfos) sin IA real
	root.tutorial = true
	root.opt_p0.select(0)
	root.opt_p1.select(1)
	root.tut_steps = [
		{"t": "Mueve", "chk": func(_m): return true},
		{"t": "Gana", "chk": func(_m): return false},
	]
	root._start_game()
	await process_frame
	var ok := root.tray0 != null and root.tut_box != null
	print("tray+tutbox: ", "OK" if ok else "FAIL")
	root._update_hud()
	print("hud: OK")
	# draft: picks alternos + auto-despliegue produce posición válida
	var got := {"pos": []}
	var d := DraftScreen.new(PiecesData.all(), 0, 4)
	d.done.connect(func(pos): got.pos = pos)
	self.root.add_child(d)
	await process_frame
	for i in 6:
		# simula picks legales (primera pieza disponible)
		for b in d.pool.get_children():
			if not b.disabled:
				b.pressed.emit()
				break
	d._finish()
	await process_frame
	var ok2: bool = not got.pos.is_empty()
	print("draft pos=%d piezas: %s" % [got.pos.size(),
		"OK" if ok2 else "FAIL"])
	quit(0 if ok and ok2 else 1)
