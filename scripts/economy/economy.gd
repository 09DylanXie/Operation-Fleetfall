class_name Economy
extends Node
## Banks for both teams and the 15-second income tick. Income comes only from
## map control: a surviving Home Base plus every captured Minor/Major island.

signal resources_changed(team: int, gold: int, steel: int)
signal tick_paid(team: int, gold: int, steel: int)

var gold: Array[int] = [0, 0]
var steel: Array[int] = [0, 0]
var time_to_tick: float = 15.0
var ticks_paid: int = 0
var match_ref: Match = null


func setup(p_match: Match) -> void:
	match_ref = p_match
	var balance: GameBalance = GameData.balance()
	time_to_tick = balance.tick_interval
	for team: int in 2:
		gold[team] = balance.start_gold
		steel[team] = balance.start_steel


func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over:
		return
	time_to_tick -= delta
	if time_to_tick <= 0.0:
		time_to_tick += GameData.balance().tick_interval
		pay_tick()


## Income (gold, steel) the team will receive on the next tick.
func income_for(team: int) -> Vector2i:
	var total: Vector2i = Vector2i.ZERO
	if team < match_ref.bases.size() and match_ref.bases[team].is_alive():
		total += match_ref.bases[team].income()
	for island: Island in match_ref.islands:
		if island.owner_team == team:
			total += island.income()
	return total


func pay_tick() -> void:
	ticks_paid += 1
	for team: int in 2:
		var income: Vector2i = income_for(team)
		gold[team] += income.x
		steel[team] += income.y
		tick_paid.emit(team, income.x, income.y)
		resources_changed.emit(team, gold[team], steel[team])


func can_afford(team: int, gold_cost: int, steel_cost: int) -> bool:
	return gold[team] >= gold_cost and steel[team] >= steel_cost


func spend(team: int, gold_cost: int, steel_cost: int) -> bool:
	if not can_afford(team, gold_cost, steel_cost):
		return false
	gold[team] -= gold_cost
	steel[team] -= steel_cost
	resources_changed.emit(team, gold[team], steel[team])
	return true


func refund(team: int, gold_amount: int, steel_amount: int) -> void:
	gold[team] += gold_amount
	steel[team] += steel_amount
	resources_changed.emit(team, gold[team], steel[team])


func set_bank(team: int, gold_amount: int, steel_amount: int) -> void:
	gold[team] = gold_amount
	steel[team] = steel_amount
	resources_changed.emit(team, gold[team], steel[team])
