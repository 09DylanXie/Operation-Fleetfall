class_name Shipyard
extends Node
## Build queue attached to a Home Base or a captured island.
## Tier 1 builds DD/SS, Tier 2 adds CL/CA, Tier 3 (Major islands only) adds BC/BB/SBB/CV.
## The hull of the order being built sits on the slip: targetable and defenseless.
##
## Orders are paid for in full when they are queued and refunded in full when they are
## cancelled. The yard starts the next order in the same tick the previous one finishes.
## If the site is lost, the order on the slip is lost with it; the orders still waiting
## behind it are refunded.
##
## The slip is also the yard's dock: friendly ships lying next to it are repaired, but only
## while the yard is not building anything and only if its tier could build that class.

signal changed(yard: Shipyard)
signal ship_launched(ship: Ship)

class BuildOrder extends RefCounted:
	var is_upgrade: bool = false
	var ship_class: ShipStats.ShipClass = ShipStats.ShipClass.DD
	var total: float = 1.0
	var remaining: float = 1.0
	var gold: int = 0
	var steel: int = 0
	## True once the cost has been taken (always, since orders are paid when queued).
	var paid: bool = false

	func progress() -> float:
		return clampf(1.0 - remaining / maxf(0.001, total), 0.0, 1.0)

	func label() -> String:
		return "Upgrade" if is_upgrade else GameData.ship(ship_class).code

var team: int = -1
var tier: int = 0
var max_tier: int = 1
var site_name: String = "Shipyard"
var site_position: Vector2 = Vector2.ZERO
var site_radius: float = 80.0
var slip_position: Vector2 = Vector2.ZERO
var slip_rotation: float = 0.0
var rally_point: Vector2 = Vector2.ZERO
var queue: Array[BuildOrder] = []
var hull: Ship = null
## Kept for the network format; orders are paid when queued, so the yard never waits.
var waiting_for_resources: bool = false
## Ships repaired in the dock during the last tick.
var repairing: int = 0
var match_ref: Match = null


func has_owner() -> bool:
	return team >= 0


func has_upgrade_queued() -> bool:
	for order: BuildOrder in queue:
		if order.is_upgrade:
			return true
	return false


func can_upgrade() -> bool:
	return has_owner() and tier < max_tier and not has_upgrade_queued()


func upgrade_cost() -> Vector2i:
	var balance: GameBalance = GameData.balance()
	var index: int = clampi(tier, 0, balance.shipyard_gold_costs.size() - 1)
	return Vector2i(balance.shipyard_gold_costs[index], balance.shipyard_steel_costs[index])


func can_build_class(ship_class: ShipStats.ShipClass) -> bool:
	return has_owner() and tier >= GameData.ship(ship_class).required_shipyard_tier


## True while an order is under construction (a ship on the slip or a tier upgrade).
func is_building() -> bool:
	return not queue.is_empty()


## Where ships sent to the dock gather: just off the slip, on its seaward side.
func dock_point() -> Vector2:
	return slip_position + Vector2.from_angle(slip_rotation) * 90.0


func in_dock(ship: Ship) -> bool:
	if not has_owner() or ship.team != team or not ship.is_combat_ready():
		return false
	return ship.position.distance_to(slip_position) <= GameData.balance().dock_radius


## "" if this yard would repair `ship` in its dock right now, otherwise the reason it will not.
func repair_block_reason(ship: Ship) -> String:
	if not has_owner() or ship.team != team:
		return "Not a friendly dock"
	if tier <= 0:
		return "No shipyard has been built here"
	if tier < ship.stats.required_shipyard_tier:
		return "%s repairs need a Tier %d shipyard" % [ship.stats.display_name, ship.stats.required_shipyard_tier]
	if is_building():
		return "The shipyard is building - no repairs until it is free"
	return ""


func can_repair(ship: Ship) -> bool:
	return repair_block_reason(ship) == ""


func _update_repairs(delta: float) -> void:
	repairing = 0
	if not has_owner() or tier <= 0 or is_building():
		return
	var rate: float = GameData.balance().repair_rate
	for ship: Ship in match_ref.ships:
		if ship.hp >= ship.max_hp or not in_dock(ship) or not can_repair(ship):
			continue
		ship.repair(ship.max_hp * rate * delta)
		repairing += 1


## Ship orders that do not yet have a hull on the map (still count toward the fleet cap).
func pending_ship_orders() -> int:
	var count: int = 0
	for order: BuildOrder in queue:
		if not order.is_upgrade:
			count += 1
	if hull != null and count > 0:
		count -= 1
	return count


## Cost of queued orders not paid for yet (always zero: orders are paid when queued).
func unpaid_cost() -> Vector2i:
	var total: Vector2i = Vector2i.ZERO
	for order: BuildOrder in queue:
		if not order.paid:
			total += Vector2i(order.gold, order.steel)
	return total


## Queues a ship and pays for it at once.
## Returns "" on success or a player-facing reason for refusal.
func try_enqueue_ship(ship_class: ShipStats.ShipClass) -> String:
	if not has_owner():
		return "Capture this island first"
	var stats: ShipStats = GameData.ship(ship_class)
	if tier < stats.required_shipyard_tier:
		return "%s needs a Tier %d shipyard" % [stats.display_name, stats.required_shipyard_tier]
	var balance: GameBalance = GameData.balance()
	if queue.size() >= balance.max_queue_length:
		return "Build queue is full"
	if match_ref.fleet_count(team) >= match_ref.fleet_cap(team):
		return "Fleet cap reached (%d ships)" % match_ref.fleet_cap(team)
	var limit: String = match_ref.class_limit_reason(team, ship_class)
	if limit != "":
		return limit
	if not match_ref.economy.spend(team, stats.gold_cost, stats.steel_cost):
		return "Not enough resources for a %s (%dG / %dS)" % [stats.display_name, stats.gold_cost, stats.steel_cost]
	var order: BuildOrder = BuildOrder.new()
	order.ship_class = ship_class
	order.total = stats.build_time
	order.remaining = stats.build_time
	order.gold = stats.gold_cost
	order.steel = stats.steel_cost
	order.paid = true
	_append(order)
	return ""


func enqueue_ship(ship_class: ShipStats.ShipClass) -> bool:
	return try_enqueue_ship(ship_class) == ""


## Queues construction of the next shipyard tier and pays for it at once.
func try_enqueue_upgrade() -> String:
	if not has_owner():
		return "Capture this island first"
	if tier >= max_tier:
		return "Shipyard is at its maximum tier"
	if has_upgrade_queued():
		return "Upgrade already in progress"
	var balance: GameBalance = GameData.balance()
	if queue.size() >= balance.max_queue_length:
		return "Build queue is full"
	var cost: Vector2i = upgrade_cost()
	if not match_ref.economy.spend(team, cost.x, cost.y):
		return "Not enough resources for the upgrade (%dG / %dS)" % [cost.x, cost.y]
	var order: BuildOrder = BuildOrder.new()
	order.is_upgrade = true
	var index: int = clampi(tier, 0, balance.shipyard_build_times.size() - 1)
	order.total = balance.shipyard_build_times[index]
	order.remaining = order.total
	order.gold = cost.x
	order.steel = cost.y
	order.paid = true
	_append(order)
	return ""


## Adds a paid order; an idle yard starts it in the same tick.
func _append(order: BuildOrder) -> void:
	queue.append(order)
	if queue.size() == 1:
		_start(order)
	changed.emit(self)


func enqueue_upgrade() -> bool:
	return try_enqueue_upgrade() == ""


func can_cancel() -> bool:
	return not queue.is_empty()


## Cancels the newest order and refunds its full cost. If that is the order under
## construction, its unfinished hull is scrapped.
func cancel_last() -> bool:
	if not can_cancel():
		return false
	var order: BuildOrder = queue.pop_back()
	if queue.is_empty() and not order.is_upgrade and hull != null:
		match_ref.scrap_hull(hull)
		hull = null
	if order.paid:
		match_ref.economy.refund(team, order.gold, order.steel)
	changed.emit(self)
	return true


## Called when the site changes hands: the yard and any hull on the slip are lost. Orders
## that had not started yet are refunded to the old owner.
func reassign(new_team: int) -> void:
	if hull != null and hull.is_alive():
		hull.kill()
	hull = null
	if team >= 0 and match_ref != null and match_ref.economy != null:
		for i: int in range(1, queue.size()):
			var order: BuildOrder = queue[i]
			if order.paid:
				match_ref.economy.refund(team, order.gold, order.steel)
	queue.clear()
	waiting_for_resources = false
	tier = 0
	team = new_team
	changed.emit(self)


## Lays `order` down (it was paid for when queued).
func _start(order: BuildOrder) -> bool:
	waiting_for_resources = false
	if not order.is_upgrade:
		hull = match_ref.spawn_ship(order.ship_class, team, slip_position, slip_rotation, true)
	changed.emit(self)
	return true


## Removes the finished head order and starts the next one in the same tick.
func _finish_head() -> void:
	queue.pop_front()
	if not queue.is_empty():
		_start(queue[0])
	changed.emit(self)


func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over or match_ref.replica:
		return
	_update_repairs(delta)
	if queue.is_empty():
		return
	var order: BuildOrder = queue[0]
	if order.is_upgrade:
		order.remaining -= delta
		if order.remaining <= 0.0:
			tier = mini(max_tier, tier + 1)
			_finish_head()
		return
	if hull == null or not hull.is_alive():
		# Sunk on the slip: the order and its resources are lost.
		hull = null
		_finish_head()
		return
	order.remaining -= delta
	hull.add_construction_progress(delta / maxf(0.001, order.total))
	if order.remaining <= 0.0:
		var ship: Ship = hull
		hull = null
		ship.complete_construction()
		match_ref.record_launch(team, ship.stats.ship_class)
		var jitter: Vector2 = Vector2.from_angle(match_ref.rng.randf() * TAU) * match_ref.rng.randf_range(0.0, 70.0)
		ship.order_move(rally_point + jitter)
		_finish_head()
		ship_launched.emit(ship)
