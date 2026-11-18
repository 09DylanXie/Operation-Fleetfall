class_name NetSync
extends RefCounted
## Full-state snapshots of a match for LAN play. The host builds one every few physics
## frames and sends it to every client; a client's Match runs as a replica (no game rules
## at all) and copies the snapshot into its own nodes. Vision is not sent: each client runs
## its own VisionSystem on the replicated positions.
##
## Ships carry Ship.NET_FIELDS floats each (see Ship.net_write); projectiles PROJ_FIELDS.

const PROJ_FIELDS: int = 8
const ISLAND_FIELDS: int = 5
const GARRISON_FIELDS: int = 2
const YARD_FIELDS: int = 10
const ORDER_FIELDS: int = 7
## Keys compared by differences(): everything but the one-off effect events.
const STATE_KEYS: Array[String] = ["f", "t", "gold", "steel", "tick", "elim", "over", "win", "ships",
	"bases", "isl", "gar", "yards", "wx", "proj"]


static func build(m: Match) -> Dictionary:
	var ships: PackedFloat32Array = PackedFloat32Array()
	for ship: Ship in m.ships:
		if ship.is_alive():
			ship.net_write(ships)
	var bases: PackedFloat32Array = PackedFloat32Array()
	for base: HomeBase in m.bases:
		bases.append(base.hp if base.is_alive() else -1.0)
	var isl: PackedFloat32Array = PackedFloat32Array()
	for island: Island in m.islands:
		if island.is_capturable():
			isl.append_array(PackedFloat32Array([float(island.owner_team), island.capture_progress,
				float(island.capturing_team), 1.0 if island.contested else 0.0, 1.0 if island.has_radar else 0.0]))
	var gar: PackedFloat32Array = PackedFloat32Array()
	for fort: IslandGarrison in m.garrisons:
		gar.append_array(PackedFloat32Array([float(fort.team), fort.hp]))
	var yards: Array = []
	for yard: Shipyard in m.yards:
		var row: PackedFloat32Array = PackedFloat32Array([float(yard.team), float(yard.tier),
			1.0 if yard.waiting_for_resources else 0.0, float(yard.repairing), yard.rally_point.x,
			yard.rally_point.y, yard.slip_position.x, yard.slip_position.y, yard.slip_rotation,
			float(m.combatant_ref(yard.hull))])
		for order: Shipyard.BuildOrder in yard.queue:
			row.append_array(PackedFloat32Array([1.0 if order.is_upgrade else 0.0, float(order.ship_class),
				order.total, order.remaining, float(order.gold), float(order.steel), 1.0 if order.paid else 0.0]))
		yards.append(row)
	var wx: PackedFloat32Array = PackedFloat32Array()
	for front: WeatherFront in m.fronts:
		wx.append_array(PackedFloat32Array([front.position.x, front.position.y]))
	var proj: PackedFloat32Array = PackedFloat32Array()
	for node: Node in m.projectiles():
		var p: Projectile = node as Projectile
		if p == null or p.is_queued_for_deletion():
			continue
		var kind: float = 0.0
		var count: int = 1
		if p is Torpedo:
			kind = 1.0
		elif p is PlaneSquadron:
			kind = 2.0
			count = int((p as PlaneSquadron).role) + 1
		else:
			count = (p as Shell).shell_count
		var at: Vector2 = p.net_pos if m.replica else p.position
		proj.append_array(PackedFloat32Array([float(p.net_id), kind, float(p.team), at.x, at.y, p.rotation,
			p.net_speed(), float(count)]))
	var elim: PackedByteArray = PackedByteArray()
	for flag: bool in m.eliminated:
		elim.append(1 if flag else 0)
	return {
		"f": m.frame(), "t": m.sim_time,
		"gold": PackedInt32Array(m.economy.gold), "steel": PackedInt32Array(m.economy.steel),
		"tick": m.economy.time_to_tick, "elim": elim, "over": m.is_over, "win": m.winner,
		"ships": ships, "bases": bases, "isl": isl, "gar": gar, "yards": yards, "wx": wx, "proj": proj,
		"fx": m.take_effect_log() if m.record_effects else PackedFloat32Array(),
	}


## Copies a host snapshot into a replica Match.
static func apply(m: Match, data: Dictionary) -> void:
	m.net_set_clock(int(data.get("f", 0)), float(data.get("t", 0.0)))
	var gold: PackedInt32Array = data.get("gold", PackedInt32Array())
	var steel: PackedInt32Array = data.get("steel", PackedInt32Array())
	for team: int in mini(m.team_count, mini(gold.size(), steel.size())):
		m.economy.gold[team] = gold[team]
		m.economy.steel[team] = steel[team]
	m.economy.time_to_tick = float(data.get("tick", 0.0))
	_apply_ships(m, data.get("ships", PackedFloat32Array()))
	var bases: PackedFloat32Array = data.get("bases", PackedFloat32Array())
	for i: int in mini(bases.size(), m.bases.size()):
		var base: HomeBase = m.bases[i]
		if bases[i] < 0.0:
			m.net_remove(base)
		elif base.is_alive():
			base.hp = bases[i]
	_apply_islands(m, data.get("isl", PackedFloat32Array()), data.get("gar", PackedFloat32Array()))
	_apply_yards(m, data.get("yards", []))
	var wx: PackedFloat32Array = data.get("wx", PackedFloat32Array())
	for i: int in mini(m.fronts.size(), wx.size() / 2):
		m.fronts[i].position = Vector2(wx[i * 2], wx[i * 2 + 1])
	_apply_projectiles(m, data.get("proj", PackedFloat32Array()))
	var fx: PackedFloat32Array = data.get("fx", PackedFloat32Array())
	for i: int in fx.size() / 3:
		var kind: int = clampi(int(fx[i * 3]), 0, Effect.Kind.size() - 1)
		m.spawn_effect(Vector2(fx[i * 3 + 1], fx[i * 3 + 2]), kind as Effect.Kind)
	var elim: PackedByteArray = data.get("elim", PackedByteArray())
	for team: int in mini(elim.size(), m.team_count):
		if elim[team] == 1:
			m.net_eliminate(team, true)
	if bool(data.get("over", false)):
		m.net_end(int(data.get("win", -1)))


static func _apply_ships(m: Match, data: PackedFloat32Array) -> void:
	var seen: Dictionary[int, bool] = {}
	var stride: int = Ship.NET_FIELDS
	var class_count: int = GameData.all_classes().size()
	for i: int in data.size() / stride:
		var at: int = i * stride
		var id: int = int(data[at])
		seen[id] = true
		var ship: Ship = m.ships_by_id.get(id) as Ship
		var fresh: bool = false
		if ship == null:
			ship = m.net_spawn_ship(id, clampi(int(data[at + 1]), 0, class_count - 1), int(data[at + 2]),
				Vector2(data[at + 3], data[at + 4]), data[at + 5], data[at + 7] > 0.5)
			fresh = true
		ship.net_read(data, at, fresh)
	for ship: Ship in m.ships.duplicate():
		if not seen.has(ship.net_id):
			m.net_remove(ship)
	for ship: Ship in m.ships:
		ship.net_resolve_targets()


static func _apply_islands(m: Match, isl: PackedFloat32Array, gar: PackedFloat32Array) -> void:
	var k: int = 0
	for island: Island in m.islands:
		if not island.is_capturable():
			continue
		var at: int = k * ISLAND_FIELDS
		k += 1
		if at + ISLAND_FIELDS > isl.size():
			break
		island.owner_team = int(isl[at])
		island.capture_progress = isl[at + 1]
		island.capturing_team = int(isl[at + 2])
		island.contested = isl[at + 3] > 0.5
		island.has_radar = isl[at + 4] > 0.5
	for i: int in mini(m.garrisons.size(), gar.size() / GARRISON_FIELDS):
		var fort: IslandGarrison = m.garrisons[i]
		var team: int = int(gar[i * GARRISON_FIELDS])
		if team != fort.team:
			fort.team = team
			fort.spotted_by.fill(false)
		fort.hp = gar[i * GARRISON_FIELDS + 1]


static func _apply_yards(m: Match, rows: Array) -> void:
	for i: int in mini(rows.size(), m.yards.size()):
		var row: PackedFloat32Array = rows[i] as PackedFloat32Array
		if row.size() < YARD_FIELDS:
			continue
		var yard: Shipyard = m.yards[i]
		yard.team = int(row[0])
		yard.tier = int(row[1])
		yard.waiting_for_resources = row[2] > 0.5
		yard.repairing = int(row[3])
		yard.rally_point = Vector2(row[4], row[5])
		yard.slip_position = Vector2(row[6], row[7])
		yard.slip_rotation = row[8]
		yard.hull = m.combatant_from_ref(int(row[9])) as Ship
		yard.queue.clear()
		for j: int in (row.size() - YARD_FIELDS) / ORDER_FIELDS:
			var at: int = YARD_FIELDS + j * ORDER_FIELDS
			var order: Shipyard.BuildOrder = Shipyard.BuildOrder.new()
			order.is_upgrade = row[at] > 0.5
			order.ship_class = int(row[at + 1]) as ShipStats.ShipClass
			order.total = row[at + 2]
			order.remaining = row[at + 3]
			order.gold = int(row[at + 4])
			order.steel = int(row[at + 5])
			order.paid = row[at + 6] > 0.5
			yard.queue.append(order)


static func _apply_projectiles(m: Match, data: PackedFloat32Array) -> void:
	var live: Dictionary[int, bool] = {}
	for i: int in data.size() / PROJ_FIELDS:
		var at: int = i * PROJ_FIELDS
		var id: int = int(data[at])
		live[id] = true
		var p: Projectile = m.net_projectiles.get(id) as Projectile
		if p == null:
			p = m.net_spawn_projectile(id, int(data[at + 1]), int(data[at + 2]), int(data[at + 7]))
		p.net_update(Vector2(data[at + 3], data[at + 4]), data[at + 5], data[at + 6])
	for id: int in m.net_projectiles.keys():
		if not live.has(id):
			m.net_remove_projectile(id)


## Keys whose values differ between two snapshots (used by tests to prove a replica holds
## exactly the host's state).
static func differences(a: Dictionary, b: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in STATE_KEYS:
		if var_to_bytes(a.get(key)) != var_to_bytes(b.get(key)):
			result.append(key)
	return result
