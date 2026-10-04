class_name ProfileScreen
extends RefCounted

## Panel de perfil: estadísticas agregadas, logros y récords
## (equivalente al /perfil de lichess, versión local).
## Recibe el controlador raíz y construye la pantalla en editor_ui.

static func build(app) -> void:
	app.menu_root.queue_free()
	app.editor_ui = Widgets.screen(Lang.t("MENU_PROFILE"), 560)
	app.add_child(app.editor_ui)
	var box := Widgets.screen_body(app.editor_ui)
	var stats: Dictionary = app.stats

	# — global —
	var g: int = int(stats.get("games", 0))
	var w: int = int(stats.get("w", 0))
	var l: int = int(stats.get("l", 0))
	var d: int = int(stats.get("d", 0))
	var played := w + l + d
	box.add_child(Widgets.heading(Lang.t("PROF_GENERAL")))
	box.add_child(Widgets.lbl(
		Lang.t("PROF_GAMES") % [
			g, w, d, l, int(100.0 * w / maxi(played, 1))]))

	# — por facción: winrate + dominio (nivel XP) —
	var fstat: Dictionary = stats.get("fstat", {})
	if not fstat.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(Widgets.heading(Lang.t("PROF_BY_FACTION")))
		var fav := ""; var fav_g := 0
		var eff := ""; var eff_wr := -1.0
		for fid in fstat:
			var fs: Dictionary = fstat[fid]
			var wr := 100.0 * int(fs.w) / maxi(int(fs.g), 1)
			box.add_child(Widgets.lbl(
				Lang.t("PROF_FAC_LINE") % [
					PiecesData.fac_name_id(fid), app._faction_level(fid),
					int(fs.g), int(wr)]))
			if int(fs.g) > fav_g: fav = fid; fav_g = int(fs.g)
			if int(fs.g) >= 3 and wr > eff_wr: eff = fid; eff_wr = wr
		var extra := Lang.t("PROF_FAV") % PiecesData.fac_name_id(fav)
		if eff != "": extra += Lang.t("PROF_EFF") % PiecesData.fac_name_id(eff)
		box.add_child(Widgets.lbl(extra))

	# — historial reciente —
	var hist: Array = stats.get("history", [])
	if not hist.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(Widgets.heading(Lang.t("PROF_RECENT")))
		var marks := {"V": "✔", "E": "½", "D": "✘"}
		var n := mini(8, hist.size())
		for i in range(hist.size() - n, hist.size()):
			var h: Dictionary = hist[i]
			box.add_child(Widgets.lbl(
				Lang.t("PROF_HIST_LINE") % [
					marks.get(h.r, "?"), PiecesData.fac_name_id(String(h.me)),
					PiecesData.fac_name_id(String(h.vs)), int(h.mv), h.mode]))

	# — récords —
	box.add_child(HSeparator.new())
	box.add_child(Widgets.heading(Lang.t("PROF_RECORDS")))
	var recs := []
	if int(stats.get("rec_fast", 0)) > 0:
		recs.append(Lang.t("PROF_REC_FAST") % int(stats.rec_fast))
	if int(stats.get("rec_long", 0)) > 0:
		recs.append(Lang.t("PROF_REC_LONG") % int(stats.rec_long))
	if int(stats.get("run_best", 0)) > 0:
		recs.append(Lang.t("PROF_REC_RUN") % int(stats.run_best))
	box.add_child(Widgets.lbl("  ".join(recs) if not recs.is_empty()
		else Lang.t("PROF_REC_NONE")))

	# — logros —
	var ach: Array = stats.get("ach", [])
	box.add_child(HSeparator.new())
	box.add_child(Widgets.heading(Lang.t("PROF_ACH")))
	if ach.is_empty():
		box.add_child(Widgets.lbl(Lang.t("PROF_ACH_NONE")))
	else:
		for a in ach:
			box.add_child(Widgets.lbl(
				"  🏆 " + StatsStore.ach_name(a)))
	var b := Widgets.secondary(Lang.t("UI_BACK"))
	b.pressed.connect(app._close_editor)
	box.add_child(b)
