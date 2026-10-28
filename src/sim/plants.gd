class_name Plants
extends RefCounted
## Plants a missed lob leaves on the floor (Barkley's Pinecone Bomb): a lob with a
## projectile "seed" block that bursts on nobody plants one where it landed. The rules
## are here; the state lives on the match (`MatchSim.plants`, `plant_seq`, saved by
## snapshot, restore and state_digest). Every number is data (the "seed" keys, in
## docs/MECHANICS.md "Projectile keys"), every check is a distance: deterministic.
##
## A plant ({id, owner, team, pos, hp, hp_max, age, stage, apple, root, grow, apple_at,
## heal_share, radius, pick_radius}):
## - stage PLANT: a sprout with `hp` health. Foes of the owner can attack it (a strike,
##   a shot or a burst that overlaps it takes its raw damage off: `strike`); at 0 it's
##   gone. A foe whose body touches it is rooted for `root` ticks (the throw's root
##   times `root_share`), and that springs the plant: it's gone. The owner's side walks
##   over it freely. After `grow` ticks on the floor it grows into a tree.
## - stage TREE: its health is back to full (`hp_max`), and the other side can cut it down
##   the same way (`plant_gone` `killed`, apple and all). It roots nobody. `apple_at` ticks
##   after growing it bears an apple (`apple`). The first fighter to touch the tree takes it: one of the owner's side,
##   hurt, heals `heal_share` of their own max HP and the tree is spent; a foe spoils it
##   and the tree is spent. An ally at full health walks past it.
##
## Events: seed {who, plant} (planted), plant_grow {who, plant}, apple {who, plant},
## plant_hit {who (owner), by, plant, hp}, plant_root {who (the rooted foe), by, plant}
## (with the usual `rooted`), apple_eaten {who, by (owner), plant, power = hp healed},
## apple_spoiled {who, plant}, plant_gone {who, plant, how: killed | sprung | eaten |
## spoiled, by}.

const PLANT := 0
const TREE := 1


## Plants a seed at `at` for `owner`: `seed` is the projectile's "seed" block, `root_ticks`
## the throw's own root (the plant's is a share of it). Nothing grows on a pit, a wall or
## a fence.
static func plant(sim: MatchSim, owner: CreatureSim, at: Vector2, seed: Dictionary, root_ticks: float) -> void:
	var cell := sim.terrain.get_cell(sim.terrain.world_to_cell(at))
	if TerrainGrid.is_pit(cell) or cell == TerrainGrid.WALL or cell == TerrainGrid.FENCE:
		return
	var hp := float(seed.get("hp", 10))
	sim.plant_seq += 1
	sim.plants.append({
		"id": sim.plant_seq, "owner": owner.id, "team": owner.team, "pos": at,
		"hp": hp, "hp_max": hp, "age": 0, "stage": PLANT, "apple": false,
		"root": int(root_ticks * float(seed.get("root_share", 0.5))),
		"grow": Hazards.ticks_of(seed.get("grow_seconds", 35)),
		"apple_at": Hazards.ticks_of(seed.get("apple_seconds", 2)),
		"heal_share": float(seed.get("heal_share", 0.15)),
		"radius": float(seed.get("radius", 10)), "pick_radius": float(seed.get("pick_radius", 12)),
	})
	sim.emit_event("seed", at, hp, {"who": owner.id, "plant": sim.plant_seq})


## Every plant ages a tick: sprouts root a foe that treads on them and grow into trees,
## trees bear an apple and hand it to the first fighter who touches it.
static func step(sim: MatchSim) -> void:
	var keep: Array = []
	for pl in sim.plants:
		pl["age"] = int(pl["age"]) + 1
		var gone := false
		if int(pl["stage"]) == PLANT:
			var foe := _touching(sim, pl, float(pl["radius"]), true)
			if foe != null:
				foe.root = maxi(foe.root, int(pl["root"]))
				sim.emit_event("rooted", foe.pos, float(pl["root"]), {"who": foe.id, "by": int(pl["owner"]), "plant": int(pl["id"])})
				sim.emit_event("plant_root", pl["pos"], float(pl["root"]), {"who": foe.id, "by": int(pl["owner"]), "plant": int(pl["id"])})
				_gone(sim, pl, "sprung", foe.id)
				gone = true
			elif int(pl["age"]) >= int(pl["grow"]):
				pl["stage"] = TREE
				pl["hp"] = float(pl["hp_max"])  # a fresh trunk: full health again
				sim.emit_event("plant_grow", pl["pos"], 1.0, {"who": int(pl["owner"]), "plant": int(pl["id"])})
		else:
			if not bool(pl["apple"]) and int(pl["age"]) >= int(pl["grow"]) + int(pl["apple_at"]):
				pl["apple"] = true
				sim.emit_event("apple", pl["pos"], 1.0, {"who": int(pl["owner"]), "plant": int(pl["id"])})
			if bool(pl["apple"]):
				var taker := _touching(sim, pl, float(pl["pick_radius"]), false)
				if taker != null:
					gone = true
					if taker.team == int(pl["team"]):
						var healed := minf(taker.max_hp - taker.hp, taker.max_hp * float(pl["heal_share"]))
						taker.hp += healed
						sim.emit_event("apple_eaten", taker.pos, healed, {"who": taker.id, "by": int(pl["owner"]), "plant": int(pl["id"])})
						_gone(sim, pl, "eaten", taker.id)
					else:
						sim.emit_event("apple_spoiled", taker.pos, 0.0, {"who": taker.id, "plant": int(pl["id"])})
						_gone(sim, pl, "spoiled", taker.id)
		if not gone:
			keep.append(pl)
	sim.plants = keep


## The first fighter (by slot) whose body overlaps the plant within `r`: on its feet
## (not in the air, not down, not falling or knocked out, not mid-leap), hittable. For a
## sprout (`foes_only`) only the owner's foes; for an apple, anyone, but an ally only
## when hurt (a full ally walks past it).
static func _touching(sim: MatchSim, pl: Dictionary, r: float, foes_only: bool) -> CreatureSim:
	var at: Vector2 = pl["pos"]
	for c in sim.creatures:
		var ally := c.team == int(pl["team"])
		if foes_only and ally:
			continue
		if not foes_only and ally and c.hp >= c.max_hp:
			continue
		if not c.can_be_hit() or c.is_airborne() or c.state == CreatureSim.State.KNOCKDOWN:
			continue
		if c.pos.distance_to(at) <= r + c.radius:
			return c
	return null


## A hit from `attacker` covering the circle (`center`, `radius`) strikes every sprout or
## tree of the other side it overlaps for `damage` (raw: no combo scaling), skipping the ids in
## `struck` (filled in, so one swing or shot hurts a plant once). Returns how many it hit.
static func strike(sim: MatchSim, attacker: CreatureSim, center: Vector2, radius: float, damage: float, struck: Array) -> int:
	var hit := 0
	var keep: Array = []
	for pl in sim.plants:
		var id := int(pl["id"])
		if int(pl["team"]) == attacker.team or struck.has(id) \
				or center.distance_to(pl["pos"]) > radius + float(pl["radius"]):
			keep.append(pl)
			continue
		struck.append(id)
		hit += 1
		pl["hp"] = float(pl["hp"]) - damage
		sim.emit_event("plant_hit", pl["pos"], damage, {"who": int(pl["owner"]), "by": attacker.id, "plant": id, "hp": maxf(0.0, float(pl["hp"]))})
		if float(pl["hp"]) <= 0.0:
			_gone(sim, pl, "killed", attacker.id)
		else:
			keep.append(pl)
	if hit > 0:
		sim.plants = keep
	return hit


static func _gone(sim: MatchSim, pl: Dictionary, how: String, by: int) -> void:
	sim.emit_event("plant_gone", pl["pos"], 0.0, {"who": int(pl["owner"]), "plant": int(pl["id"]), "how": how, "by": by})
