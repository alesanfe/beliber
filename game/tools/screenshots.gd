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
		["pos_editor", func(): _close(); _app._open_pos_editor()],
		["puzzles", func(): _close(); _app._open_puzzles()],
		["profile", func(): _close(); _app._open_profile()],
		["draft", func(): _close(); _app._open_draft()],
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
