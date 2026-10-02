class_name StatsStore
extends RefCounted

## Persistencia de estadísticas y progresión: XP por facción, logros,
## récords e historial de partidas (guardado en user://beliber_stats.json).

const STATS_PATH := "user://beliber_stats.json"

## Desactiva la persistencia: los tests E2E instancian la escena real
## y cada run contaminaba beliber_stats.json del jugador (games, XP y
## logros fantasmas).
static var disabled := false

# mapa de logro → clave i18n (los textos viven en ui.csv; antes eran
# const con español hardcoded, que ignoraba el idioma)
const ACH_KEYS := {
	"primera": "ACH_PRIMERA",
	"caza5": "ACH_CAZA5",
	"ia3": "ACH_IA3",
	"cinco": "ACH_CINCO",
	"veloz": "ACH_VELOZ",
}

## Nombre localizado del logro (fallback = id si falta la clave).
static func ach_name(id: String) -> String:
	var key: String = ACH_KEYS.get(id, "")
	return Lang.t(key) if key != "" else id

const XP_GAME := 10   # por jugar
const XP_WIN := 30    # bonus por ganar

## Lectura tolerante con recuperación: si el JSON principal está
## corrupto o es ilegible se cae a <path>.bak (la última versión
## escrita con éxito por atomic_write) en vez de devolver datos
## vacíos — la restauración no exige copiar ficheros a mano.
static func load_json(path: String) -> Variant:
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p): continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null: continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary or parsed is Array: return parsed
	return null

static func load_stats() -> Dictionary:
	var stats := {}
	# solo aceptar Dictionary (un JSON dañado puede dar bool/null)
	var parsed: Variant = load_json(STATS_PATH)
	if parsed is Dictionary: stats = parsed
	stats.merge({"games": 0, "wins": {}, "ach": [], "xp": {},
		"w": 0, "l": 0, "d": 0, "fstat": {}, "history": [],
		"rec_fast": 0, "rec_long": 0}, false)
	# coerción por tipo: un JSON raíz válido con interior corrupto
	# ({"xp": [], "ach": {}, "w": "x"}) crasheaba record_result
	for k in ["wins", "fstat", "xp"]:
		if not (stats[k] is Dictionary): stats[k] = {}
	for k in ["ach", "history"]:
		if not (stats[k] is Array): stats[k] = []
	for k in ["games", "w", "l", "d", "rec_fast", "rec_long"]:
		if not (stats[k] is int or stats[k] is float): stats[k] = 0
	return stats

static func save(stats: Dictionary) -> void:
	if disabled: return
	atomic_write(STATS_PATH, JSON.stringify(stats))

## Escritura atómica: un corte a mitad del write dejaba el JSON
## truncado (el load tolera el parseo nulo, pero los datos se
## pierden igualmente).
static func atomic_write(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		# rename con reemplazo puede fallar en Windows según el runtime:
		# sin esto el .tmp quedaba y los stats no se actualizaban más
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		err = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(tmp),
			ProjectSettings.globalize_path(path))
		if err != OK:
			# último recurso: escritura directa (peor que nada)
			var d := FileAccess.open(path, FileAccess.WRITE)
			if d != null:
				d.store_string(text)
				d.close()
	# .bak = última versión escrita con éxito — restore manual de un
	# fichero corrupto es copiar el .bak encima
	DirAccess.copy_absolute(ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(path + ".bak"))

## Nivel de dominio de una facción (progresión estilo perfil lichess).
static func faction_level(stats: Dictionary, fid: String) -> int:
	return int(stats.xp.get(fid, 0)) / 100 + 1

## Registra el resultado de la partida terminada: XP, V/E/D,
## historial, récords y logros. app es el controlador raíz.
static func record_result(app) -> void:
	var stats: Dictionary = app.stats
	var tm: TurnManager = app.tm
	stats.games = int(stats.games) + 1
	for k in ["xp", "fstat", "history", "wins", "ach"]:
		if not stats.has(k): stats[k] = {} if k != "ach" \
			and k != "history" else []
	# XP para la facción que jugó el humano (J1 local, mi lado online)
	var human_side: int = app.my_net if app.online \
		else (0 if not app.ai_both else -1)
	if human_side >= 0:
		var played_fid: String = tm.state.factions[human_side].id
		var before := int(stats.xp.get(played_fid, 0))
		var gain := XP_GAME + (XP_WIN if tm.winner == human_side else 0)
		stats.xp[played_fid] = before + gain
		if before / 100 != stats.xp[played_fid] / 100:
			app.hud_alert("⭐ ¡%s sube a nivel %d!" % [
				played_fid.capitalize(),
				faction_level(stats, played_fid)])
		# resultado V/E/D + stats por facción + historial
		var res := "E"
		if tm.winner == human_side: res = "V"; stats.w += 1
		elif tm.winner < 0: stats.d += 1
		else: stats.l += 1
		var fs: Dictionary = stats.fstat.get(played_fid,
			{"g": 0, "w": 0})
		fs.g += 1
		if res == "V": fs.w += 1
		stats.fstat[played_fid] = fs
		var mode := "online" if app.online else \
			("run" if app.run_active else \
			("IA" if app.ai_player >= 0 else "local"))
		stats.history.append({"r": res, "me": played_fid,
			"vs": tm.state.factions[1 - human_side].id,
			"mv": tm.log.size(), "mode": mode,
			"ts": int(Time.get_unix_time_from_system())})
		while stats.history.size() > 20: stats.history.pop_front()
		# récords
		if res == "V" and (int(stats.rec_fast) == 0 \
				or tm.log.size() < int(stats.rec_fast)):
			stats.rec_fast = tm.log.size()
		stats.rec_long = maxi(int(stats.rec_long), tm.log.size())
	if tm.winner >= 0:
		var fid: String = tm.state.factions[tm.winner].id
		stats.wins[fid] = int(stats.wins.get(fid, 0)) + 1
		# logros de mérito: solo si el HUMANO ganó — en IA vs IA
		# (human_side == -1) se concedían igualmente
		if human_side >= 0 and tm.winner == human_side:
			grant(app, "primera")
			if app.ai_player >= 0 and tm.winner == 0 \
					and int(app._saved_opts.get("ai_lvl", 0)) == 3:
				grant(app, "ia3")
			if tm.log.size() < 15: grant(app, "veloz")
	if stats.games >= 5: grant(app, "cinco")
	# caza5: solo mérito del humano (antes contaban las capturas
	# de cualquiera de los dos bandos, incluida la IA)
	if human_side >= 0 and tm.captured_by[human_side].size() >= 5:
		grant(app, "caza5")
	save(stats)

static func grant(app, id: String) -> void:
	if app.stats.ach.has(id): return
	app.stats.ach.append(id)
	app.hud_alert("🏆 " + ach_name(id))
