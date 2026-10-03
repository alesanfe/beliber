class_name Tts
extends RefCounted

## Capa de lector de pantalla sobre DisplayServer.tts_speak —
## Godot no expone ARIA nativo en Control, así que los anuncios se
## hacen explícitos en los puntos clave: título de pantalla al abrir,
## toasts, diálogos de confirmación y cambios de turno.
##
## Se activa desde Opciones ("Lector de pantalla"); persistido como
## ui.tts. Independiente de 'mute' — el TTS es accesibilidad, no SFX.
static var enabled := false
static var _last := ""

static func ok() -> bool:
	return enabled and DisplayServer.has_feature(
		DisplayServer.FEATURE_TEXT_TO_SPEECH)

## Anuncia un texto; ignora repeticiones seguidas (el HUD refresca el
## mismo turno varias veces por jugada).
static func say(text: String) -> void:
	if not ok() or text == _last: return
	_last = text
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, "")
