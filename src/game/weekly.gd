class_name Weekly
extends Daily
## The Weekly Challenge (Settings > Game > Progression on): the Daily's sibling, one
## seeded fight a week, the same for everyone that ISO week (UTC). The week picks the
## opponent, the CPU level (Normal or Hard), three mutators from data/rules/mutators.json
## (hazards included), the map and its time of day and weather. Scored like the Daily
## (health left and time to spare); the player may play it as often as they like that
## week and the local best is kept (progress.json `weekly`: {"YYYYWW": best}). The first
## scoring win of a week also pays `weekly_clear` XP (data/progression.json). No server
## board: nothing is sent anywhere.

const WEEK_PICKS := 3

var week := 0  ## ISO year * 100 + ISO week (202644), UTC
var arena_id := ArenaMap.DEFAULT
var time_id := WeatherView.DAY
var weather_id := WeatherView.CLEAR


## This week (UTC), as ISO year * 100 + week.
static func this_week() -> int:
	return week_of(Daily.today())


## The ISO week of a YYYYMMDD date, as ISO year * 100 + week (Monday starts a week; the
## week holding the year's first Thursday is week 1, so 2027-01-01 is 2026's week 53).
static func week_of(p_date: int) -> int:
	var d := Daily.day_number(p_date)
	var wd := posmod(d + 3, 7)  # 0 Monday .. 6 Sunday (1970-01-01 was a Thursday)
	var thu := d - wd + 3
	var y := Daily.date_of_day(thu) / 10000
	return y * 100 + (thu - Daily.day_number(y * 10000 + 101)) / 7 + 1


## `p_date` (YYYYMMDD, 0 = today, UTC) names the week; tests pass one.
func _init(p_fighter: String, p_date := 0) -> void:
	super(p_fighter, p_date if p_date > 0 else Daily.today())
	week = week_of(date)
	date = week  # the seed handed to the match and the CPU, like the Daily's date
	var rng := RandomNumberGenerator.new()
	rng.seed = week * 6151 + 4099
	_roll(rng, WEEK_PICKS)
	arena_id = String(ArenaMap.IDS[rng.randi_range(0, ArenaMap.IDS.size() - 1)])
	var map := ArenaMap.get_map(arena_id)
	var times := WeatherView.times_of(map)
	var weathers := WeatherView.weathers_of(map)
	time_id = String(times[rng.randi_range(0, times.size() - 1)])
	weather_id = String(weathers[rng.randi_range(0, weathers.size() - 1)])


## The week's look (main's `_match_look`): looks only, never how the fight plays.
func look() -> Dictionary:
	return {"time": time_id, "weather": weather_id}


func stage_label() -> String:
	return "WEEKLY CHALLENGE  %d WEEK %d" % [week / 100, week % 100]


## The week's mutators' names, in the draw's order.
func mutator_names_list() -> Array:
	var table := Daily.mutator_table()
	return picks.map(func(id): return String(table[id].get("name", id)))


## The week's map, not the stadium.
func build() -> MatchSim:
	var sim := MatchFactory.versus(fighter, opponent(), arena_id)
	sim.apply_mutators(mutators(), date)
	return sim
