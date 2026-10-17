extends TestCase
## Every fighter's knockout effect plays. A broken one (a missing ko_fx key) killed the
## release build mid-match: Mister Crease's "scatter" had no "pieces" (Oct 2026).


func _rig(id: String) -> Dictionary:
	var sim := MatchFactory.training(id)
	var views: Array = []
	for c in sim.creatures:
		var v := CreatureView.new()
		v.setup(c)
		views.append(v)
	var fx := FxView.new()
	fx.sim = sim
	fx.views = views
	return {"sim": sim, "views": views, "fx": fx}


func _free(r: Dictionary) -> void:
	for v in r["views"]:
		(v as Node).free()
	(r["fx"] as Node).free()


func _run_ko(r: Dictionary) -> FxView:
	var fx: FxView = r["fx"]
	var c: CreatureSim = (r["sim"] as MatchSim).creatures[0]
	fx._ko(c)
	for i in 60:
		fx.advance()
	return fx


func _pieces(fx: FxView) -> int:
	return fx._parts.filter(func(p): return bool(p.get("piece", false))).size()


func test_every_fighters_knockout_effect_plays() -> void:
	for id in MatchFactory.FIGHTERS:
		var r := _rig(id)
		var fx := _run_ko(r)
		assert_true(fx._parts.size() > 0, "%s's knockout leaves something on screen" % id)
		var ko: Dictionary = (r["sim"] as MatchSim).creatures[0].def.get("ko_fx", {})
		if String(ko.get("style", "")) == "scatter":
			assert_eq(_pieces(fx), (ko.get("pieces", [0, 0, 0, 0]) as Array).size(),
				"%s comes apart in its pieces:" % id)
			assert_true((r["views"][0] as CreatureView).ko_hidden, "%s's sprite is replaced by the pieces" % id)
		_free(r)


func test_scatter_without_pieces_falls_back_to_even_bands() -> void:
	var r := _rig("crease")
	var c: CreatureSim = (r["sim"] as MatchSim).creatures[0]
	var ko: Dictionary = (c.def["ko_fx"] as Dictionary).duplicate()
	ko.erase("pieces")
	ko.erase("frame")
	c.def = c.def.duplicate()
	c.def["ko_fx"] = ko
	var fx := _run_ko(r)
	assert_eq(_pieces(fx), 4, "no pieces listed: four bands of the figure")
	for p in fx._parts:
		if bool(p.get("piece", false)):
			var reg: Rect2 = p["region"]
			assert_true(reg.size.y > 0.0, "every band has height")
			assert_true(reg.end.y <= 160.0, "and stays inside his 160 px tall side frame")
	_free(r)
