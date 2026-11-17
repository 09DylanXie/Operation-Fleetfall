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
	return super.apply_damage(amount, ignore_armor, from_submarine)


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
	spotted_by = [false, false]
	_attackers.clear()
	hp_changed.emit(self)
