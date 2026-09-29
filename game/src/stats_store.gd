class_name StatsStore
extends RefCounted

## Persistencia de estadísticas y progresión: XP por facción, logros,
## récords e historial de partidas (guardado en user://beliber_stats.json).

const STATS_PATH := "user://beliber_stats.json"

const ACH := {
	"primera": "Primera victoria",
	"caza5": "Cazador: 5+ capturas en una partida",
	"ia3": "Vencer a la IA nivel 3",
	"cinco": "Cinco partidas disputadas",
	"veloz": "Ganar en menos de 15 movimientos",
}

const XP_GAME := 10   # por jugar
const XP_WIN := 30    # bonus por ganar

static func load_stats() -> Dictionary:
	var stats := {}
	if FileAccess.file_exists(STATS_PATH):
		var f := FileAccess.open(STATS_PATH, FileAccess.READ)
		# solo aceptar Dictionary (un JSON dañado puede dar bool/null)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary: stats = parsed
		f.close()
	stats.merge({"games": 0, "wins": {}, "ach": [], "xp": {},
		"w": 0, "l": 0, "d": 0, "fstat": {}, "history": [],
		"rec_fast": 0, "rec_long": 0}, false)
	return stats

static func save(stats: Dictionary) -> void:
	var f := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(stats))
	f.close()

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
			if app.hud_info:
				app.hud_info.text += "\n⭐ ¡%s sube a nivel %d!" % [
					played_fid.capitalize(),
					faction_level(stats, played_fid)]
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
		grant(app, "primera")
		if app.ai_player >= 0 and tm.winner == 0 \
				and int(app._saved_opts.get("ai_lvl", 0)) == 3:
			grant(app, "ia3")
		if tm.log.size() < 15: grant(app, "veloz")
	if stats.games >= 5: grant(app, "cinco")
	if tm.captured_by[0].size() >= 5 or tm.captured_by[1].size() >= 5:
		grant(app, "caza5")
	save(stats)

static func grant(app, id: String) -> void:
	if app.stats.ach.has(id): return
	app.stats.ach.append(id)
	if app.hud_info: app.hud_info.text += "\n🏆 " + ACH[id]
