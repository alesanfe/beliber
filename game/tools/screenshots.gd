extends SceneTree
## Capturas de pantalla para docs/assets/ (README, docs).
## Uso:   godot --path game -s res://tools/screenshots.gd
## Recorre las pantallas reales de la app; sobrescribe los PNG.
## NOTA: ejecuta en ventana (no --headless): necesita GPU.

const OUT := "res://../docs/assets"
const WAIT := 25              # frames tras cada acción antes del shot

var _app
var _queue: Array = []
var _wait := 0
var _name := ""

func _init() -> void:
	_app = load("res://scenes/main.tscn").instantiate()
	root.add_child(_app)
	_queue = [
		["menu", func(): pass],
		["online", func(): _app._open_online()],
		["guide", func(): _close(); _app._open_guide()],
		["piece_editor", func(): _close(); _app._open_editor()],
		["builder", func(): _close(); _app._open_builder()],
		# el editor arranca vacío: precargo el setup oficial de ambas
		# facciones para que la captura muestre el tablero real
		["pos_editor", func():
			_close(); _app._open_pos_editor()
			var ed: PosEditor = _app.editor_ui
			for pl in [0, 1]:
				var f: Dictionary = _app.factions[
					_app.opt_p0.selected if pl == 0
					else _app.opt_p1.selected]
				var base := 7 if pl == 0 else 0
				var d := -1 if pl == 0 else 1
				var rows: Array = f.setups[0]
				for j in rows.size():
					for x in mini(rows[j].length(), 8):
						var ch: String = rows[j].substr(x, 1)
						if ch != "." and ch != " ":
							ed.grid[Vector2i(x, base + d * j)] = \
								{"l": ch, "o": pl}
			ed._board.queue_redraw()],
		["puzzles", func(): _close(); _app._open_puzzles()],
		["profile", func(): _close(); _app._open_profile()],
		# un par de picks para que la captura muestre estado, no la
		# pantalla vacía inicial
		["draft", func():
			_close(); _app._open_draft()
			var d: DraftScreen = _app.editor_ui
			d._pick("Y"); d._pick("X"); d._pick("C"); d._pick("T")],
		["game", func(): _close(); _app._start_game()],
		["postgame", func(): PostGame.modal(_app, 0,
			PostGame.summary(_app.tm))],
		["tutorial", func(): _app._restart(); _app._start_tutorial()],
	]

func _close() -> void:
	if _app.editor_ui != null or (
			is_instance_valid(_app.menu_root)
			and not _app.menu_root.visible):
		_app._close_editor()

func _process(_dt: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img := root.get_texture().get_image()
			img.save_png(OUT + "/" + _name + ".png")
			print("shot %s %s" % [_name, img.get_size()])
		return false
	if _queue.is_empty():
		return true
	var s: Array = _queue.pop_front()
	_name = s[0]
	s[1].call()
	_wait = WAIT
	return false
