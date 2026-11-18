class_name AIController
extends Node
## Skirmish opponent. It has no special powers: it reads only what its team has
## spotted and issues the same orders a player can (move, attack, torpedo,
## queue ship, upgrade shipyard).
##
## Loop: expand with Destroyers -> tech up shipyards -> mass an army ->
## stage outside the enemy base -> assault; fall back and rebuild if the wave breaks.
##
## Difficulty: Hard sends every order the moment it decides on it. Easy and Medium can only
## control one ship at a time: every ship order goes through `_command`, which collects
## what the AI wants during a think and sends just one of them, to the ship that has waited
## longest. Medium does that every ORDER_INTERVAL_MEDIUM seconds, Easy every
## ORDER_INTERVAL_EASY seconds, and both plan production less often than Hard. Ships still fire, launch planes and drop depth
## charges on their own, exactly as a player's ships do.

enum ArmyState { BUILDUP, STAGING, ASSAULT }

const THINK_INTERVAL: float = 1.0
const HOME_DEFENSE_RADIUS: float = 1200.0
const STAGE_DISTANCE: float = 1500.0
const STAGE_TIMEOUT: float = 150.0
const ASSAULT_STALL_TIMEOUT: float = 240.0
const REINFORCE_STRENGTH: float = 900.0
const RECALL_THREAT_STRENGTH: float = 500.0
const COMMITTED_DISTANCE: float = 1400.0
const WAVE_BASE_STRENGTH: float = 2200.0
const WAVE_STEP_STRENGTH: float = 700.0
const WAVE_MAX_STRENGTH: float = 5600.0
## Seconds between ship orders on Medium and Easy.
const ORDER_INTERVAL_MEDIUM: float = 2.0
const ORDER_INTERVAL_EASY: float = 5.0
## Medium and Easy only revisit their build queues every this many thinks.
const MEDIUM_PRODUCTION_EVERY: int = 2
const EASY_PRODUCTION_EVERY: int = 4

var team: int = 1
var match_ref: Match = null
var army_state: ArmyState = ArmyState.BUILDUP
var waves_launched: int = 0
var difficulty: GameSettings.Difficulty = GameSettings.Difficulty.HARD
## Ship orders actually sent (tests use it to check the one-ship-at-a-time limit).
var orders_sent: int = 0

var _think_cd: float = 0.5
var _capture_jobs: Dictionary[Ship, Island] = {}
## Resource Ships and the island each one is sent to mine.
var _mining_jobs: Dictionary[Ship, Island] = {}
var _order_keys: Dictionary[Ship, String] = {}
var _wave: Array[Ship] = []
var _stage_point: Vector2 = Vector2.ZERO
var _stage_timer: float = 0.0
var _assault_start_strength: float = 0.0
var _stall_timer: float = 0.0
var _last_activity: int = -1
var _last_base_hp: float = 0.0
## Limited difficulties: orders wanted this think (ship -> [key, Callable]), and the sim
## time each ship last received an order.
var _pending: Dictionary[Ship, Array] = {}
var _last_ordered: Dictionary[Ship, float] = {}
var _order_cd: float = 0.0
var _thinks: int = 0


func setup(p_match: Match, p_team: int,
		p_difficulty: GameSettings.Difficulty = GameSettings.Difficulty.HARD) -> void:
	match_ref = p_match
	team = p_team
	difficulty = p_difficulty
	_think_cd = 0.5 + 0.37 * float(p_team)


func _physics_process(delta: float) -> void:
	if match_ref != null and match_ref.replica:
		return
	if match_ref == null or match_ref.is_over or match_ref.eliminated[team]:
		return
	_think_cd -= delta
	_order_cd -= delta
	if _think_cd <= 0.0:
		_think_cd += THINK_INTERVAL
		think()


func think() -> void:
	_thinks += 1
	_prune()
	if _thinks % production_every() == 1 % production_every():
		_think_production()
	_think_capture()
	_think_army()
	_think_support()
	_think_submarines()
	_flush_orders()


## True on Easy and Medium: one ship order at a time.
func is_limited() -> bool:
	return difficulty != GameSettings.Difficulty.HARD


## Thinks between production decisions: 1 on Hard.
func production_every() -> int:
	match difficulty:
		GameSettings.Difficulty.EASY:
			return EASY_PRODUCTION_EVERY
		GameSettings.Difficulty.MEDIUM:
			return MEDIUM_PRODUCTION_EVERY
	return 1


func order_interval() -> float:
	return ORDER_INTERVAL_EASY if difficulty == GameSettings.Difficulty.EASY else ORDER_INTERVAL_MEDIUM


func _home() -> HomeBase:
	return match_ref.bases[team]


## The base this AI is trying to destroy: the nearest hostile one still standing.
func _enemy_base() -> HomeBase:
	var home_pos: Vector2 = _home().position
	var best: HomeBase = null
	var fallback: HomeBase = null
	for base: HomeBase in match_ref.bases:
		if not match_ref.are_enemies(base.team, team):
			continue
		fallback = base
		if not base.is_alive():
			continue
		if best == null or base.position.distance_squared_to(home_pos) < best.position.distance_squared_to(home_pos):
			best = base
	return best if best != null else fallback


func _prune() -> void:
	for ship: Ship in _order_keys.keys():
		if not ship.is_alive():
			_order_keys.erase(ship)
	for ship: Ship in _last_ordered.keys():
		if not ship.is_alive():
			_last_ordered.erase(ship)
	for ship: Ship in _mining_jobs.keys():
		if not ship.is_alive():
			_mining_jobs.erase(ship)
	for ship: Ship in _capture_jobs.keys():
		var island: Island = _capture_jobs[ship]
		if not ship.is_alive() or island.owner_team == team:
			_capture_jobs.erase(ship)
			_order_keys.erase(ship)
	var alive: Array[Ship] = []
	for ship: Ship in _wave:
		if ship.is_alive():
			alive.append(ship)
	_wave = alive


## Issues an order only when it differs from the ship's current one (avoids repath spam).
func _issue(ship: Ship, key: String, order: Callable) -> void:
	if _order_keys.get(ship, "") == key:
		return
	_command(ship, key, order)


## The single gate every ship order passes through. `key` (may be empty) is remembered as
## the ship's current order once the order is really sent.
func _command(ship: Ship, key: String, order: Callable) -> void:
	if not is_limited():
		_send(ship, key, order)
		return
	# A later decision about the same ship replaces an earlier one, as it would on Hard.
	_pending[ship] = [key, order]


func _send(ship: Ship, key: String, order: Callable) -> void:
	if key != "":
		_order_keys[ship] = key
	orders_sent += 1
	_last_ordered[ship] = match_ref.sim_time
	order.call()


## Limited difficulties: send one of the orders wanted this think, to the ship that has
## gone longest without one (so no ship is starved); the rest are decided again next time.
func _flush_orders() -> void:
	if _pending.is_empty():
		return
	if _order_cd > 0.0:
		_pending.clear()
		return
	var pick: Ship = null
	var oldest: float = INF
	for ship: Ship in _pending.keys():
		if not ship.is_alive():
			continue
		var last: float = _last_ordered.get(ship, -INF)
		if last < oldest:
			oldest = last
			pick = ship
	if pick != null:
		var wanted: Array = _pending[pick]
		_send(pick, wanted[0], wanted[1])
		_order_cd = order_interval() - 0.01
	_pending.clear()


# --- Production -------------------------------------------------------------

func _class_counts() -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {}
	for cls: ShipStats.ShipClass in GameData.all_classes():
		counts[int(cls)] = 0
	for ship: Ship in match_ref.ships_of(team, false):
		counts[int(ship.stats.ship_class)] += 1
	for yard: Shipyard in match_ref.yards_of(team):
		var skip_first: bool = yard.hull != null
		for order: Shipyard.BuildOrder in yard.queue:
			if order.is_upgrade:
				continue
			if skip_first:
				skip_first = false
				continue
			counts[int(order.ship_class)] += 1
	return counts


func _max_tier(yard_list: Array[Shipyard]) -> int:
	var best: int = 0
	for yard: Shipyard in yard_list:
		best = maxi(best, yard.tier)
	return best


func _owned_majors() -> Array[Island]:
	var result: Array[Island] = []
	for island: Island in match_ref.islands:
		if island.kind == Island.Kind.MAJOR and island.owner_team == team:
			result.append(island)
	var home_pos: Vector2 = _home().position
	result.sort_custom(func(a: Island, b: Island) -> bool:
		return a.position.distance_squared_to(home_pos) < b.position.distance_squared_to(home_pos))
	return result


## True if the bank covers the cost on top of every queued order that is not paid for yet.
func _can_afford(gold_cost: int, steel_cost: int) -> bool:
	var committed: Vector2i = Vector2i.ZERO
	for yard: Shipyard in match_ref.yards_of(team):
		committed += yard.unpaid_cost()
	var economy: Economy = match_ref.economy
	return economy.gold[team] - committed.x >= gold_cost and economy.steel[team] - committed.y >= steel_cost


func _queue_upgrade_if_affordable(yard: Shipyard) -> bool:
	var cost: Vector2i = yard.upgrade_cost()
	return _can_afford(cost.x, cost.y) and yard.enqueue_upgrade()


func _think_production() -> void:
	var my_yards: Array[Shipyard] = match_ref.yards_of(team)
	var total: int = match_ref.fleet_count(team)
	var home_yard: Shipyard = _home().shipyard
	var saving: bool = false

	# Tech: Tier 2 at home once a few scouts are out, then a Tier 3 yard on the safest Major island.
	# Orders are paid for when they start, so the AI only queues what it can cover right now.
	if home_yard.can_upgrade() and total >= 3:
		if not _queue_upgrade_if_affordable(home_yard):
			saving = total >= 5
	var majors: Array[Island] = _owned_majors()
	if not majors.is_empty() and home_yard.tier + (1 if home_yard.has_upgrade_queued() else 0) >= 2:
		var forward: Shipyard = majors[0].shipyard
		if forward.can_upgrade():
			if not _queue_upgrade_if_affordable(forward):
				saving = saving or total >= 6
	_buy_radar()
	if saving or total >= match_ref.fleet_cap(team):
		return

	var counts: Dictionary[int, int] = _class_counts()
	for cls: ShipStats.ShipClass in _desired_classes(counts, _max_tier(my_yards), total):
		if match_ref.class_limit_reason(team, cls) != "":
			continue
		var yard: Shipyard = _yard_for(cls, my_yards)
		if yard == null:
			continue
		var stats: ShipStats = GameData.ship(cls)
		if _can_afford(stats.gold_cost, stats.steel_cost):
			yard.enqueue_ship(cls)
			return
		# Save up for capital ships once there is a fleet to hold the line.
		if stats.required_shipyard_tier >= 3 and total >= 12:
			return


func _desired_classes(counts: Dictionary[int, int], best_tier: int, total: int) -> Array[ShipStats.ShipClass]:
	var dd: int = counts[int(ShipStats.ShipClass.DD)]
	var ss: int = counts[int(ShipStats.ShipClass.SS)]
	var cl: int = counts[int(ShipStats.ShipClass.CL)]
	var ca: int = counts[int(ShipStats.ShipClass.CA)]
	var bb: int = counts[int(ShipStats.ShipClass.BB)]
	var cv: int = counts[int(ShipStats.ShipClass.CV)]
	var bc: int = counts[int(ShipStats.ShipClass.BC)]
	var sbb: int = counts[int(ShipStats.ShipClass.SBB)]
	var rs: int = counts[int(ShipStats.ShipClass.RS)]
	var rd: int = counts[int(ShipStats.ShipClass.RD)]
	var lcv: int = counts[int(ShipStats.ShipClass.LCV)]
	var claa: int = counts[int(ShipStats.ShipClass.CLAA)]
	var want: Array[ShipStats.ShipClass] = []
	if dd < 3:
		want.append(ShipStats.ShipClass.DD)
	if rs < 2 and dd >= 3:
		want.append(ShipStats.ShipClass.RS)
	if rd < 1 and total >= 8:
		want.append(ShipStats.ShipClass.RD)
	if best_tier >= 3:
		if bb < 3:
			want.append(ShipStats.ShipClass.BB)
		if sbb < 1 and bb >= 2:
			want.append(ShipStats.ShipClass.SBB)
		if bc < 2 and bb >= 1:
			want.append(ShipStats.ShipClass.BC)
		if cv < 2 and bb >= 1:
			want.append(ShipStats.ShipClass.CV)
	if best_tier >= 2:
		# AA Cruisers: one escort once the fleet grows, one more per enemy carrier seen.
		if claa < mini(3, (1 if total >= 10 else 0) + _enemy_carriers_seen()):
			want.append(ShipStats.ShipClass.CLAA)
		if lcv < 1 and total >= 6:
			want.append(ShipStats.ShipClass.LCV)
		if ca < 5 and ca <= cl:
			want.append(ShipStats.ShipClass.CA)
		if cl < 6:
			want.append(ShipStats.ShipClass.CL)
		if ca < 6:
			want.append(ShipStats.ShipClass.CA)
	if ss < 2 and total >= 6:
		want.append(ShipStats.ShipClass.SS)
	if dd < 6:
		want.append(ShipStats.ShipClass.DD)
	if best_tier >= 2:
		want.append(ShipStats.ShipClass.CL)
	elif dd < 10:
		want.append(ShipStats.ShipClass.DD)
	return want


## Enemy carriers this side can currently see.
func _enemy_carriers_seen() -> int:
	var count: int = 0
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		var ship: Ship = enemy as Ship
		if ship != null and ship.is_alive() and ship.stats.has_planes():
			count += 1
	return count


func _yard_for(cls: ShipStats.ShipClass, my_yards: Array[Shipyard]) -> Shipyard:
	var best: Shipyard = null
	for yard: Shipyard in my_yards:
		if not yard.can_build_class(cls) or yard.queue.size() >= 2:
			continue
		if best == null or yard.queue.size() < best.queue.size():
			best = yard
	return best


# --- Expansion --------------------------------------------------------------

func _think_capture() -> void:
	var home_pos: Vector2 = _home().position
	var enemy_pos: Vector2 = _enemy_base().position
	var targets: Array[Island] = []
	for island: Island in match_ref.islands:
		if not island.is_capturable() or island.owner_team == team:
			continue
		# Leave islands deep in enemy water alone until an assault is under way.
		var d_home: float = island.position.distance_to(home_pos)
		var d_enemy: float = island.position.distance_to(enemy_pos)
		if d_home > d_enemy + 500.0 and army_state != ArmyState.ASSAULT:
			continue
		targets.append(island)
	targets.sort_custom(func(a: Island, b: Island) -> bool:
		return a.position.distance_squared_to(home_pos) < b.position.distance_squared_to(home_pos))
	var taken: Array[Island] = []
	for island: Island in _capture_jobs.values():
		taken.append(island)
	for island: Island in targets:
		if taken.has(island):
			continue
		var ship: Ship = _pick_capturer(island)
		if ship == null:
			continue
		_capture_jobs[ship] = island
		_wave.erase(ship)
		taken.append(island)
	for ship: Ship in _capture_jobs.keys():
		var island: Island = _capture_jobs[ship]
		if island.owner_team >= 0 and match_ref.are_enemies(island.owner_team, team) and island.garrison != null:
			# An enemy-held island is fortified: shoot its garrison down first.
			_issue(ship, "siege:%d" % island.get_instance_id(), ship.order_attack.bind(island.garrison))
			continue
		var dir: Vector2 = (ship.position - island.position).normalized()
		var spot: Vector2 = match_ref.nav.nearest_free(
			island.position + dir * (island.radius + 75.0), ship.stats.shallow_draft)
		_issue(ship, "cap:%d" % island.get_instance_id(), ship.order_move.bind(spot))


func _pick_capturer(island: Island) -> Ship:
	var best: Ship = null
	var best_score: float = INF
	for ship: Ship in match_ref.ships_of(team):
		if _capture_jobs.has(ship) or ship.stats.is_submarine or ship.stats.is_support():
			continue
		if island.kind == Island.Kind.MINOR and not ship.stats.shallow_draft:
			continue
		# Destroyers are the designated capturers; heavier hulls only as a fallback for Majors.
		var score: float = ship.position.distance_to(island.position)
		if ship.stats.ship_class != ShipStats.ShipClass.DD:
			if _wave.has(ship):
				continue
			score += 4000.0
		if score < best_score:
			best_score = score
			best = ship
	return best


# --- Army -------------------------------------------------------------------

func _army() -> Array[Ship]:
	var result: Array[Ship] = []
	for ship: Ship in match_ref.ships_of(team):
		if not _capture_jobs.has(ship) and not ship.stats.is_support():
			result.append(ship)
	return result


func _strength(group: Array[Ship]) -> float:
	var total: float = 0.0
	for ship: Ship in group:
		total += float(ship.stats.gold_cost) * clampf(ship.hp / ship.max_hp, 0.0, 1.0)
	return total


func _gather_point() -> Vector2:
	var home_pos: Vector2 = _home().position
	var dir: Vector2 = (match_ref.map_data.center() - home_pos).normalized()
	return match_ref.nav.nearest_free(home_pos + dir * 480.0, false)


func _threat_near_home() -> Combatant:
	var home_pos: Vector2 = _home().position
	var best: Combatant = null
	var best_dist: float = HOME_DEFENSE_RADIUS
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		if not enemy.is_alive() or enemy.is_structure():
			continue
		var dist: float = enemy.position.distance_to(home_pos)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _move_group(group: Array[Ship], center: Vector2, tag: String) -> void:
	var slots: Array[Vector2] = match_ref.formation_positions(center, group.size())
	var key: String = "%s:%d,%d" % [tag, int(center.x / 60.0), int(center.y / 60.0)]
	for i: int in group.size():
		_issue(group[i], key, group[i].order_move.bind(slots[i]))


func _think_army() -> void:
	var army: Array[Ship] = _army()
	var threat: Combatant = _threat_near_home()
	var reserve: Array[Ship] = []
	for ship: Ship in army:
		if not _wave.has(ship):
			reserve.append(ship)

	# Anything not committed to a wave holds near home and answers raids.
	if threat != null:
		_move_group(reserve, threat.position, "def")
	else:
		_move_group(reserve, _gather_point(), "gather")

	match army_state:
		ArmyState.BUILDUP:
			var cap: int = match_ref.fleet_cap(team)
			var threshold: float = minf(WAVE_BASE_STRENGTH + WAVE_STEP_STRENGTH * float(waves_launched), WAVE_MAX_STRENGTH)
			var ready: bool = _strength(army) >= threshold or match_ref.fleet_count(team) >= cap - 2
			if threat == null and ready and army.size() >= 4:
				_wave = army
				waves_launched += 1
				_stage_timer = 0.0
				var enemy_pos: Vector2 = _enemy_base().position
				var dir: Vector2 = (_home().position - enemy_pos).normalized()
				_stage_point = match_ref.nav.nearest_free(enemy_pos + dir * STAGE_DISTANCE, false)
				army_state = ArmyState.STAGING
		ArmyState.STAGING:
			_stage_timer += THINK_INTERVAL
			_move_group(_wave, _stage_point, "stage")
			var arrived: int = 0
			for ship: Ship in _wave:
				if ship.position.distance_to(_stage_point) < 520.0:
					arrived += 1
			if _wave.size() < 2 or _home_threat_strength() >= RECALL_THREAT_STRENGTH:
				# Too few ships left, or a real raid on the Home Base: fall back and defend.
				_end_wave()
			elif float(arrived) >= 0.7 * float(_wave.size()) or _stage_timer > STAGE_TIMEOUT:
				_assault_start_strength = maxf(1.0, _strength(_wave))
				_stall_timer = 0.0
				_last_activity = -1
				_last_base_hp = _enemy_base().hp
				army_state = ArmyState.ASSAULT
		ArmyState.ASSAULT:
			_reinforce_wave(reserve, threat)
			_watch_assault_progress()
			if _wave.is_empty() or _strength(_wave) < 0.3 * _assault_start_strength \
					or _stall_timer > ASSAULT_STALL_TIMEOUT or _should_recall():
				_end_wave()
			else:
				_run_assault()


## Gold value of the spotted, armed enemy ships near the Home Base.
func _home_threat_strength() -> float:
	var home_pos: Vector2 = _home().position
	var total: float = 0.0
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		if not enemy.is_alive() or enemy.is_structure():
			continue
		var foe: Ship = enemy as Ship
		if foe.under_construction or foe.position.distance_to(home_pos) > HOME_DEFENSE_RADIUS:
			continue
		total += float(foe.stats.gold_cost) * clampf(foe.hp / foe.max_hp, 0.0, 1.0)
	return total


## A wave that has not yet reached the enemy base turns around if home is under serious attack.
func _should_recall() -> bool:
	if _home_threat_strength() < RECALL_THREAT_STRENGTH:
		return false
	var enemy_pos: Vector2 = _enemy_base().position
	for ship: Ship in _wave:
		if ship.position.distance_to(enemy_pos) < COMMITTED_DISTANCE:
			return false
	return true


## Fresh ships follow the wave in once enough of them have gathered, so a winning push keeps its momentum.
func _reinforce_wave(reserve: Array[Ship], threat: Combatant) -> void:
	if threat != null or reserve.size() < 3 or _strength(reserve) < REINFORCE_STRENGTH:
		return
	for ship: Ship in reserve:
		_wave.append(ship)
		_order_keys.erase(ship)
	_assault_start_strength = maxf(_assault_start_strength, _strength(_wave))


## An assault that neither fires a shot nor scratches the base for a while is called off.
func _watch_assault_progress() -> void:
	var activity: int = 0
	for ship: Ship in _wave:
		activity += ship.salvos_fired + ship.torpedoes_launched + ship.squadrons_launched
	var base_hp: float = _enemy_base().hp
	if activity != _last_activity or base_hp < _last_base_hp:
		_stall_timer = 0.0
	else:
		_stall_timer += THINK_INTERVAL
	_last_activity = activity
	_last_base_hp = base_hp


func _nearest_enemy_ship(ship: Ship, radius: float) -> Ship:
	var best: Ship = null
	var best_dist: float = radius
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		if not enemy.is_alive() or enemy.is_structure():
			continue
		var foe: Ship = enemy as Ship
		if foe.under_construction or not ship.can_engage(foe):
			continue
		var dist: float = foe.position.distance_to(ship.position)
		if dist < best_dist:
			best_dist = dist
			best = foe
	return best


func _run_assault() -> void:
	var enemy_base: HomeBase = _enemy_base()
	for ship: Ship in _wave:
		if ship.stats.is_submarine:
			# Submarines cannot hurt the base; they screen the wave and hunt ships.
			var dir: Vector2 = (ship.position - enemy_base.position).normalized()
			var post: Vector2 = match_ref.nav.nearest_free(enemy_base.position + dir * 800.0, true)
			if ship.torpedo_order == null:
				_issue(ship, "screen", ship.order_move.bind(post))
			continue
		if _is_aa_escort(ship):
			# AA Cruisers have no guns: they sail in the middle of the wave to cover it from the air.
			var solo: Array[Ship] = [ship]
			_move_group(solo, match_ref.nav.nearest_free(_wave_center(ship), true), "escort")
			continue
		# Deal with armed defenders first, then siege the base. Orders are compared with the
		# ship's actual state so a dropped order is always re-issued.
		var reach: float = ship.stats.gun_range if ship.stats.has_guns() else ship.stats.engage_range()
		var foe: Ship = _nearest_enemy_ship(ship, reach * 1.2)
		var want: Combatant = foe if foe != null else enemy_base
		if ship.stats.has_planes():
			# The air wing picks its own targets (ships before the base); the carrier only
			# has to close to plane range of the enemy base.
			if ship.priority_target != enemy_base:
				_command(ship, "", func() -> void:
					ship.order_attack(enemy_base)
					ship.clear_strike())
		elif ship.priority_target != want:
			_command(ship, "", ship.order_attack.bind(want))
		_order_keys.erase(ship)


## A gunless warship whose only weapon is flak (the AA Cruiser).
static func _is_aa_escort(ship: Ship) -> bool:
	return ship.stats.has_periodic_aa() and not ship.stats.has_guns() and not ship.stats.has_planes()


## Centre of the wave's fighting ships (not counting `skip` or other escorts).
func _wave_center(skip: Ship) -> Vector2:
	var center: Vector2 = Vector2.ZERO
	var count: int = 0
	for other: Ship in _wave:
		if other != skip and other.is_alive() and not _is_aa_escort(other):
			center += other.position
			count += 1
	return center / float(count) if count > 0 else skip.position


func _end_wave() -> void:
	for ship: Ship in _wave:
		_order_keys.erase(ship)
		_command(ship, "", ship.order_stop)
	_wave.clear()
	_stall_timer = 0.0
	army_state = ArmyState.BUILDUP


# --- Support ships ----------------------------------------------------------

## Radar for every Tier 3 island once there is a fleet to protect.
func _buy_radar() -> void:
	if match_ref.fleet_count(team) < 10:
		return
	var balance: GameBalance = GameData.balance()
	for island: Island in _owned_majors():
		if island.radar_block_reason(team) == "" and _can_afford(balance.radar_gold_cost, balance.radar_steel_cost):
			island.try_buy_radar(team)


## Resource Ships mine the safest free islands; Radar Ships sail with the army.
func _think_support() -> void:
	var home_pos: Vector2 = _home().position
	var enemy_pos: Vector2 = _enemy_base().position
	for ship: Ship in match_ref.ships_of(team):
		if ship.stats.mines_islands:
			var island: Island = _mining_jobs.get(ship) as Island
			if island == null or (island.owner_team >= 0 and match_ref.are_enemies(island.owner_team, team)):
				island = _pick_mining_island(ship, home_pos, enemy_pos)
				if island == null:
					_mining_jobs.erase(ship)
					continue
				_mining_jobs[ship] = island
			var dir: Vector2 = (home_pos - island.position).normalized()
			var spot: Vector2 = match_ref.nav.nearest_free(island.position + dir * (island.radius + 70.0), true)
			_issue(ship, "mine:%d" % island.get_instance_id(), ship.order_move.bind(spot))
		elif ship.stats.is_support():
			# Radar picket: keep just behind the middle of the wave (or the home fleet).
			var group: Array[Ship] = _wave if not _wave.is_empty() else _army()
			if group.is_empty():
				continue
			var center: Vector2 = Vector2.ZERO
			for other: Ship in group:
				center += other.position
			center /= float(group.size())
			var back: Vector2 = (home_pos - center).normalized() * 150.0
			var solo: Array[Ship] = [ship]
			_move_group(solo, match_ref.nav.nearest_free(center + back, true), "radar")


## The nearest island to home that is not enemy-held, not deep in enemy water and not
## already being mined by another of this side's Resource Ships.
func _pick_mining_island(ship: Ship, home_pos: Vector2, enemy_pos: Vector2) -> Island:
	var taken: Array[Island] = []
	for other: Ship in _mining_jobs.keys():
		if other != ship:
			taken.append(_mining_jobs[other])
	var best: Island = null
	var best_dist: float = INF
	for island: Island in match_ref.islands:
		if taken.has(island):
			continue
		if island.owner_team >= 0 and match_ref.are_enemies(island.owner_team, team):
			continue
		var d_home: float = island.position.distance_to(home_pos)
		if d_home > island.position.distance_to(enemy_pos):
			continue
		if d_home < best_dist:
			best_dist = d_home
			best = island
	return best


# --- Submarines -------------------------------------------------------------

## Subs never auto-engage, so the AI has to "press the button" just like a player.
func _think_submarines() -> void:
	for ship: Ship in match_ref.ships_of(team):
		if not ship.stats.is_submarine or ship.torpedo_order != null or not ship.torpedo_ready():
			continue
		var best: Combatant = null
		var best_dist: float = ship.stats.torpedo_range * 1.15
		for enemy: Combatant in match_ref.vision.spotted_enemies(team):
			if not enemy.is_alive() or enemy.is_structure():
				continue
			var dist: float = enemy.position.distance_to(ship.position)
			if dist < best_dist:
				best_dist = dist
				best = enemy
		if best != null:
			var target: Combatant = best
			_command(ship, "", func() -> void:
				if ship.order_torpedo(target):
					_order_keys.erase(ship))
