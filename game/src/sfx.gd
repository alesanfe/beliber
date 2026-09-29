class_name BeliberSfx
extends Node

## SFX sintetizado (mini-pack estilo lichess): captura = golpe grave,
## especial = trino, castillo = doble tono, push/attract = barrido,
## normal = click. Sin assets — todo se genera con AudioStreamGenerator.

var muted := false
var _player: AudioStreamPlayer

func _ensure() -> AudioStreamGeneratorPlayback:
	if _player == null:
		_player = AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050
		_player.stream = gen
		_player.volume_db = -14.0
		add_child(_player)
		_player.play()
	return _player.get_stream_playback()

func beep(freq: float, dur := 0.1) -> void:
	if muted: return
	var pb := _ensure()
	var rate := 22050.0
	var frames := int(dur * rate)
	for i in frames:
		var t := float(i) / rate
		var env := 1.0 - t / dur
		pb.push_frame(Vector2(sin(TAU * freq * t) * env,
			sin(TAU * freq * t) * env))

## Barrido de frecuencia (push/atract/inmovilizar).
func sweep(f0: float, f1: float, dur := 0.1) -> void:
	if muted: return
	var pb := _ensure()
	var rate := 22050.0
	var frames := int(dur * rate)
	var phase := 0.0
	for i in frames:
		var k := float(i) / frames
		var freq := lerpf(f0, f1, k)
		phase += TAU * freq / rate
		pb.push_frame(Vector2(sin(phase) * (1.0 - k),
			sin(phase) * (1.0 - k)))

## Fanfarria de victoria.
func fanfare() -> void:
	beep(523.0, 0.12); beep(659.0, 0.12); beep(784.0, 0.18)

## Sonido por tipo de jugada.
func play_move(mv: Dictionary) -> void:
	if muted: return
	if mv.get("captures", []).size() > 0:
		beep(180.0, 0.07); beep(90.0, 0.12); return
	if mv.has("castle") or mv.has("second"):
		beep(392.0, 0.07); beep(523.0, 0.10); return
	if mv.has("push") or mv.has("attract") \
			or mv.get("immobilize", []).size() > 0:
		sweep(300.0, 620.0, 0.10); return
	beep(440.0, 0.07)
