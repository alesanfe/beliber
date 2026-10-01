class_name Lang
extends RefCounted

## i18n: ui.csv (es/en) se importa a i18n/ui.<loc>.translation; el
## remap de locale/translations no carga en runtime headless, así que
## los registramos a mano la primera vez que se usa la clase.
## Uso: Lang.t("MENU_PLAY"). En métodos de instancia de Node, tr().
static var _o := RefCounted.new()
static var _loaded := _register()

static func _register() -> bool:
	for loc in ["es", "en"]:
		var p := "res://i18n/ui.%s.translation" % loc
		var t: Translation = load(p)
		if t != null:
			TranslationServer.add_translation(t)
	return true

static func t(key: String) -> String:
	return _o.tr(key)
