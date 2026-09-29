extends SceneTree
func _init() -> void:
	var f0: Dictionary; var f1: Dictionary
	for f in PiecesData.all():
		if f.id == "kronturs": f0 = f
		if f.id == "humenex": f1 = f
	var tm := TurnManager.new(f0, 0, f1, 0)
	var st := tm.state
	for y in 8:
		for x in 8:
			var p = st.at(Vector2i(x, y))
			if p != null and p.owner == 0 and p.def.letter == "M":
				print("M @", x, ",", y)
	var mp := Vector2i(2, 3)
	print("at(2,1):", st.at(Vector2i(2, 1)))
	print("at(2,2):", st.at(Vector2i(2, 2)))
	print("at(2,0):", st.at(Vector2i(2, 0)))
	st.set_at(Vector2i(2, 1), st.new_piece(f1.pieces["P"], 1))
	for mv in MoveGen.moves_for(st, mp):
		print(mv)
	quit()
