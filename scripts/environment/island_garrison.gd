class_name IslandGarrison
extends Combatant
## The defences of a captured island: a "mini base". While an island has an owner its
## garrison can be spotted, shelled, torpedoed by surface ships and bombed like a Home
## Base (Submarines cannot hurt it). At 0 HP the island falls neutral and loses its
## shipyard; only then can anyone capture it with the usual 30 second hold.
##
## Unlike other combatants a garrison is never removed: it changes team with its island
## and counts as "not alive" while the island is neutral. It has no hitbox of its own:
## projectiles that strike the island's shore damage it (see Projectile).

var island: Island = null
## Air base (Major island with a Tier 3 shipyard): bomber squadrons in the air, the enemy
## ship they are working, and the time to the next launch.
var squadrons_launched: int = 0
var squadrons_lost: int = 0
var _squadrons: Array[PlaneSquadron] = []
var _air_target: Combatant = null
var _air_cd: float = 0.0
## Seconds since the garrison was last hit (for regeneration).
var since_hit: float = 1000.0


func setup(p_island: Island, p_match: Match) -> void:
	island = p_island
	match_ref = p_match
	position = p_island.position
	var balance: GameBalance = GameData.balance()
	max_hp = balance.minor_garrison_hp if p_island.kind == Island.Kind.MINOR else balance.major_garrison_hp
	base_armor = balance.garrison_armor
	hp = max_hp
	team = p_island.owner_team
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false


func is_alive() -> bool:
	return team >= 0


func is_structure() -> bool:
	return true


func hit_radius() -> float:
	return island.radius


func range_padding() -> float:
	return island.radius * 0.8


## The island the garrison stands on must not block the line of sight to itself.
func los_blocker() -> CollisionObject2D:
	return island


func apply_damage(amount: float, ignore_armor: bool, from_submarine: bool) -> float:
	if team < 0:
		return 0.0
	var dealt: float = super.apply_damage(amount, ignore_armor, from_submarine)
	if dealt > 0.0:
		since_hit = 0.0
	return dealt


## A garrison is not destroyed for good: its island falls neutral instead.
func kill() -> void:
	if team < 0:
		return
	hp = 0.0
	if match_ref != null:
		match_ref.spawn_effect(position, Effect.Kind.EXPLOSION)
	island.garrison_fell()


## Called by the island whenever it changes hands: a fresh garrison for the new owner.
func assign(new_team: int) -> void:
	team = new_team
	hp = max_hp
	_squadrons.clear()
	_air_target = null
	_air_cd = 0.0
	since_hit = 1000.0
	spotted_by.fill(false)
	_attackers.clear()
	hp_changed.emit(self)


# --- Air base ---------------------------------------------------------------
# A Major island with a Tier 3 shipyard defends itself with up to `air_base_squadrons` HE
# bomber squadrons. They go only after enemy ships that have fired on the island and are
# within `air_base_range` of it, circle them bombing every few seconds like a carrier's
# dive bombers, and fly home when the target sinks, escapes or slips out of sight.

func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over or match_ref.replica:
		return
	_regenerate(delta)
	if not is_alive() or not island.has_air_base():
		_air_target = null
		return
	_air_cd = maxf(0.0, _air_cd - delta)
	if not _air_target_valid(_air_target, 1.0):
		_air_target = _pick_air_target()
	if _air_target == null or _air_cd > 0.0 or _squadrons.size() >= GameData.balance().air_base_squadrons:
		return
	var heading: float = (_air_target.position - position).angle()
	_squadrons.append(match_ref.spawn_squadron(self, position, heading))
	squadrons_launched += 1
	_air_cd = GameData.balance().air_base_interval


## Islands with a Tier 2+ shipyard slowly rebuild their garrison once nobody has hit it
## for a few seconds.
func _regenerate(delta: float) -> void:
	since_hit += delta
	if not can_regenerate() or hp >= max_hp:
		return
	var balance: GameBalance = GameData.balance()
	if since_hit < balance.garrison_regen_delay:
		return
	hp = minf(max_hp, hp + max_hp * balance.garrison_regen_rate * delta)
	hp_changed.emit(self)


func can_regenerate() -> bool:
	return is_alive() and island.shipyard != null \
		and island.shipyard.tier >= GameData.balance().garrison_regen_min_tier


func airborne_squadrons() -> int:
	return _squadrons.size()


func air_target() -> Combatant:
	return _air_target


func strike_active() -> bool:
	return is_alive() and island.has_air_base() and _air_target_valid(_air_target, 1.3)


func air_reach() -> float:
	return GameData.balance().air_base_range * 1.3 + island.radius


func squadron_gone(squadron: PlaneSquadron, shot_down: bool) -> void:
	_squadrons.erase(squadron)
	if shot_down:
		squadrons_lost += 1


func _air_target_valid(target: Combatant, reach_scale: float) -> bool:
	if target == null or not target.is_alive() or not target.is_enemy_of(team) or not target.spotted_by[team]:
		return false
	var reach: float = GameData.balance().air_base_range * reach_scale + island.radius
	return target.position.distance_to(position) <= reach


## The nearest spotted enemy ship that has fired on this island lately and is in range.
func _pick_air_target() -> Combatant:
	var best: Combatant = null
	var best_dist: float = INF
	for attacker: Combatant in recent_attackers():
		if not attacker is Ship or not _air_target_valid(attacker, 1.0):
			continue
		var dist: float = attacker.position.distance_to(position)
		if dist < best_dist:
			best_dist = dist
			best = attacker
	return best
