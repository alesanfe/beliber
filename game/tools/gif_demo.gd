extends SceneTree
## Graba una partida IA-vs-IA frame a frame → docs/assets/_frames/.
## Uso:  godot --path game -s res://tools/gif_demo.gd
##       python tools/make_gif.py
## (ventana, no --headless: necesita GPU)

const OUT := "res://../docs/assets/_frames/"
const CAPTURE_EVERY := 8      # ~7 fps capturados
const MAX_SHOTS := 90         # ~11 s de partida real

var _app
var _frame := 0
var _n := 0

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUT))
	_app = load("res://scenes/main.tscn").instantiate()
	root.add_child(_app)

func _process(_dt: float) -> bool:
	_frame += 1
	if _frame == 15:
		# IA vs IA: el bot juega solo, los turnos se ven animados
		_app.opt_ai.select(4)
		_app._start_game()
		return false
	if _frame < 15 or _frame % CAPTURE_EVERY != 0:
		return false
	var img := root.get_texture().get_image()
	img.save_png(OUT + "f%03d.png" % _n)
	_n += 1
	if _n % 10 == 0:
		print("frame ", _n)
	return _n >= MAX_SHOTS
