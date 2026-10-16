class_name Presence
extends RefCounted
## What Discord shows on the player's profile ("Rich Presence"): built from main's state
## once a second and handed to DiscordRpc, which sends it only when it changes.
##
## details: what you're doing ("Versus CPU · Hard", "Online ranked 1v1", "In the menus")
## state:   the matchup or progress ("Cairn vs Culvert · Round 2 · 1–0")
## The large image is the game's art; the small one is your fighter (its id is the asset
## key) when data/discord.json lists art for it. The elapsed clock restarts when
## `details` changes, so it runs for a whole match, not a round.

const CONFIG_PATH := "res://data/discord.json"
const RULE_NAMES := {"": "Team battle", "deathmatch": "Team Deathmatch", "sinkhole": "Sinkhole",
	"crater": "King of the Crater"}

var config := {}
var _key := ""
var _start := 0


func _init(p_config := {}) -> void:
	config = p_config


static func load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## The Discord activity for main (`g`) right now. `now` is unix seconds.
func activity(g: Node, now := int(Time.get_unix_time_from_system())) -> Dictionary:
	var d := describe(g)
	var details := String(d.get("details", ""))
	if details != _key:
		_key = details
		_start = now
	var a := {"type": 0, "timestamps": {"start": _start}}
	_put_text(a, "details", details)
	_put_text(a, "state", String(d.get("state", "")))
	var assets := {}
	var large := String(config.get("large_image", ""))
	if large != "":
		assets["large_image"] = large
		assets["large_text"] = String(d.get("arena", "Creature Arena"))
	var fighter := String(d.get("fighter", ""))
	if fighter != "" and fighter in config.get("fighter_images", []):
		assets["small_image"] = fighter
		assets["small_text"] = String(d.get("fighter_name", fighter))
	if not assets.is_empty():
		a["assets"] = assets
	return a


## Discord wants 2..128 characters, or the key left out.
static func _put_text(a: Dictionary, key: String, text: String) -> void:
	if text.length() >= 2:
		a[key] = text.left(128)


## {details, state, fighter, fighter_name, arena} from main's flow and match.
static func describe(g: Node) -> Dictionary:
	if g.flow == g.Flow.LOBBY:
		var searching: bool = g.netplay != null
		return {"details": "Online", "state": "Looking for a match" if searching else "In the lobby"}
	if g.flow == g.Flow.MENU or g.sim == null:
		return {"details": "In the menus"}
	var cfg: Dictionary = g.MODES[g.mode]
	var out := {}
	var me = _my_creature(g)
	if me != null:
		out["fighter"] = String(me.def.get("id", ""))
		out["fighter_name"] = String(me.def.get("name", ""))
	out["arena"] = String(g.sim.arena.get("name", "Creature Arena"))
	if g.flow == g.Flow.SELECT:
		out["details"] = _mode_title(g, cfg)
		out["state"] = "Picking fighters"
		out.erase("fighter")
		return out
	if g.showcase != null:
		return {"details": "Watching the combo showcases", "arena": out["arena"]}
	if g.watch != null:
		out["details"] = "Spectating an online match"
		out["state"] = _matchup(g, null)
		out.erase("fighter")
		return out
	if g._replaying():
		out["details"] = "Watching a replay"
		out["state"] = _matchup(g, null)
		out.erase("fighter")
		return out
	if cfg.get("training", false):
		out["details"] = "Training"
		out["state"] = "as %s" % out.get("fighter_name", "?")
		return out
	if cfg.get("trials", false):
		out["details"] = "Combo Trials"
		out["state"] = String(g.coach.title) if g.coach != null and "title" in g.coach else ""
		return out
	if cfg.has("drill"):
		out["details"] = "Reaction Drill"
		out["state"] = String(g.coach.title) if g.coach != null and "title" in g.coach else ""
		return out
	out["details"] = _mode_title(g, cfg)
	if g.brawl != null:
		out["state"] = "as %s" % out.get("fighter_name", "?")
		return out
	var state := _matchup(g, me)
	if g.online == null and g.duel == null and g.team_battle == null and g.arcade == null:
		state += "  ·  Round %d  ·  %d–%d" % [g.round_num, g.wins[0], g.wins[1]]
	out["state"] = state
	if me == null:
		out.erase("fighter")
	return out


## The mode's name as a player would say it.
static func _mode_title(g: Node, cfg: Dictionary) -> String:
	var level: String = g.LEVEL_NAMES[clampi(g.level, 0, g.LEVEL_NAMES.size() - 1)]
	if g.online != null:
		var o = g.online
		var size := "%dv%d" % [o.size, o.size]
		if o.team != null:
			return "Online %s %s" % [RULE_NAMES.get(String(o.rules_id), "team battle"), size]
		if g.netplay != null and g.netplay.ranked:
			return "Online ranked 1v1"
		return "Online 1v1"
	if g.arcade != null:
		if g.arcade is Daily:
			return "Daily Challenge"
		var run := "Gauntlet" if g.arcade is Gauntlet else "Arcade"
		return "%s  ·  Stage %d" % [run, int(g.arcade.stage) + 1]
	var cpu_vs_cpu := true
	for s in g.sides:
		if s in g.LOCAL_SIDES:
			cpu_vs_cpu = false
	if cpu_vs_cpu:
		return "Watching CPU vs CPU"
	var players := 0
	for s in g.sides:
		if s in g.LOCAL_SIDES:
			players += 1
	if cfg.get("brawl", false):
		if cfg.get("chaos", false):
			return "Chaos Cup"
		return "Brawl  ·  %d players" % players if players > 1 else "Brawl vs CPU"
	if cfg.has("team"):
		var kind := String(cfg.get("rules", "deathmatch" if cfg.get("deathmatch", false) else ""))
		return "%s %dv%d vs CPU  ·  %s" % [RULE_NAMES.get(kind, "Team battle"), int(cfg["team"]),
			int(cfg["team"]), level]
	var what := "Duel (3v3 tag)" if cfg.get("duel", false) else "Versus"
	if players > 1:
		return "%s  ·  2 players" % what
	return "%s vs CPU  ·  %s" % [what, level]


## "Cairn vs Culvert": you (or the left side) against the first fighter of another team.
static func _matchup(g: Node, me) -> String:
	var a = me
	if a == null:
		a = _side_creature(g, 0)
	var b = null
	if a != null:
		if g.duel != null:
			b = g.duel.active_creature(1 - a.team)
		else:
			for c in g.sim.creatures:
				if c.team != a.team:
					b = c
					break
	if a == null or b == null:
		return ""
	return "%s vs %s" % [a.def.get("name", "?"), b.def.get("name", "?")]


## The creature someone at this machine plays (in a Duel: the one on the field).
static func _my_creature(g: Node):
	for i in mini(g.sides.size(), g.sim.creatures.size()):
		if g.sides[i] in g.LOCAL_SIDES:
			if g.duel != null:
				return g.duel.active_creature(g.sim.creatures[i].team)
			return g.sim.creatures[i]
	return null


static func _side_creature(g: Node, team: int):
	if g.duel != null:
		return g.duel.active_creature(team)
	for c in g.sim.creatures:
		if c.team == team:
			return c
	return null
