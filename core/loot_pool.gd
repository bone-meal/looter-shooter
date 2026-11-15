# Purpose: pure loot-pool roller. One kill of a pool's source (a sea boss, a raid boss, the Vault, any sea enemy for
# the world pool) gives some rolled guns and maybe named uniques from that pool (data/loot_pools.json).
# Dependencies: core/gun_db.gd (pools, pool_uniques), core/gun_gen.gd (generate, unique). No nodes.
extends RefCounted

const GunGen = preload("res://core/gun_gen.gd")


# The guns one kill drops: [] for an unknown pool. lvl = the source's item level; luck_mult scales the pool's luck
# (Fortune / Lucky Find, later NG+).
static func roll(db: RefCounted, rng: RandomNumberGenerator, pool_id: String, lvl: int, luck_mult: float = 1.0) -> Array:
	if not db.pools.has(pool_id):
		return []
	var pool: Dictionary = db.pools[pool_id]
	var out: Array = []
	for _i in int(pool.get("guns", 0)):
		out.append(GunGen.generate(db, rng, float(pool.get("luck", 0.0)) * luck_mult, "", "", String(pool.get("min_tier", "")), lvl))
	for _i in int(pool.get("unique_rolls", 1)):
		if rng.randf() < float(pool.get("unique_chance", 0.0)):
			var id := pick_unique(db, rng, pool_id)
			if id != "":
				out.append(GunGen.unique(db, id, lvl))
	return out


# One unique id from the pool: a chase gun with the pool's chase_share, else a plain one (the other kind when one is
# empty); "" when the pool has none yet.
static func pick_unique(db: RefCounted, rng: RandomNumberGenerator, pool_id: String) -> String:
	var chase := rng.randf() < float((db.pools.get(pool_id, {}) as Dictionary).get("chase_share", 0.5))
	var ids: Array = db.pool_uniques(pool_id, chase)
	if ids.is_empty():
		ids = db.pool_uniques(pool_id, not chase)
	return String(ids[rng.randi_range(0, ids.size() - 1)]) if not ids.is_empty() else ""
