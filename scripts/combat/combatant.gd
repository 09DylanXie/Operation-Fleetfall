class_name Combatant
extends Area2D
## Anything that can be spotted, shot at and destroyed: ships and Home Bases.
## Destroyed combatants are removed from the tree but kept alive by the Match,
## so references held by orders and projectiles never dangle. Always check is_alive().

signal destroyed(who: Combatant)
signal hp_changed(who: Combatant)

var team: int = 0
var max_hp: float = 1.0
var hp: float = 1.0
## Flat damage reduction, 0.0 - 1.0.
var base_armor: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var match_ref: Match = null
## spotted_by[t] is true while team t can currently see this combatant.
var spotted_by: Array[bool] = [false, false, false, false]
var last_known_position: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]

var _dead: bool = false
## Attacker instance id -> sim time at which its attack stops counting.
var _attackers: Dictionary[int, float] = {}


## GDD focus-fire rule: every attacker beyond the first strips `strip` armor, floored at 0.
static func compute_effective_armor(base: float, active_attackers: int, strip: float) -> float:
	return maxf(0.0, base - strip * float(maxi(0, active_attackers - 1)))


func is_alive() -> bool:
	return not _dead


## True when `other_team` may shoot at this combatant: any other side that is not an ally.
func is_enemy_of(other_team: int) -> bool:
	if match_ref != null:
		return match_ref.are_enemies(team, other_team)
	return team != other_team


func is_home_base() -> bool:
	return false


## Fixed installations: Home Bases and island garrisons. Everyone knows where they are,
## and Submarines can neither target nor damage them.
func is_structure() -> bool:
	return is_home_base()


## A body that must not count as cover for this target (the island a garrison stands on).
func los_blocker() -> CollisionObject2D:
	return null


func is_submarine() -> bool:
	return false


## Radius used for range checks and bomb drops.
func hit_radius() -> float:
	return 20.0


## Chance (0-1) to shoot down a squadron that has just bombed this target.
func aa_kill_chance() -> float:
	return 0.0


## Extra reach granted to attackers of large targets (measured to the edge, not the centre).
func range_padding() -> float:
	return 0.0


# --- Air wing hooks (carriers and island air bases override these) -----------

## What this combatant's dive bombers are working right now.
func air_target() -> Combatant:
	return null


## True while the dive bombers in the air may keep working `air_target()`.
func strike_active() -> bool:
	return false


## The target for one dive-bomber squadron from here, or null to send it home. By default
## every squadron works `air_target()` while the strike is active (island air bases).
func dive_target_for(_squadron: PlaneSquadron) -> Combatant:
	return air_target() if strike_active() else null


## How far from home this combatant's planes may chase a target.
func air_reach() -> float:
	return 0.0


## A squadron from here landed (`shot_down` false) or was lost.
func squadron_gone(_squadron: PlaneSquadron, _shot_down: bool) -> void:
	pass


## Enemy ships that attacked this combatant within the last few seconds.
func recent_attackers() -> Array[Combatant]:
	var now: float = _now()
	var result: Array[Combatant] = []
	for id: int in _attackers.keys():
		if _attackers[id] < now:
			continue
		var who: Combatant = instance_from_id(id) as Combatant
		if who != null and who.is_alive():
			result.append(who)
	return result


func configure_layers() -> void:
	collision_layer = Layers.SHIPS | Layers.team_hitbox(team)
	collision_mask = 0
	monitoring = false


func _now() -> float:
	return match_ref.sim_time if match_ref != null else 0.0


## Marks `attacker` as actively engaging this target for `duration` seconds.
func register_attacker(attacker: Combatant, duration: float) -> void:
	_attackers[attacker.get_instance_id()] = _now() + duration


func active_attacker_count() -> int:
	var now: float = _now()
	var count: int = 0
	for id: int in _attackers.keys():
		if _attackers[id] >= now:
			count += 1
		else:
			_attackers.erase(id)
	return count


func effective_armor() -> float:
	var strip: float = GameData.balance().armor_strip_per_attacker
	return compute_effective_armor(base_armor, active_attacker_count(), strip)


## Applies damage and returns the amount actually dealt.
## HE bombs pass ignore_armor; submarine weapons can never hurt a Home Base or an island garrison.
func apply_damage(amount: float, ignore_armor: bool, from_submarine: bool) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	if from_submarine and is_structure():
		return 0.0
	var armor: float = 0.0 if ignore_armor else effective_armor()
	var dealt: float = amount * (1.0 - armor)
	hp -= dealt
	hp_changed.emit(self)
	if hp <= 0.0:
		kill()
	return dealt


## Restores hit points, never above the maximum.
func repair(amount: float) -> void:
	if _dead or amount <= 0.0 or hp >= max_hp:
		return
	hp = minf(max_hp, hp + amount)
	hp_changed.emit(self)


func kill() -> void:
	if _dead:
		return
	_dead = true
	hp = 0.0
	destroyed.emit(self)


## Network replica only: the host says this combatant is gone. No signal, no side effects.
func net_kill() -> void:
	_dead = true
	hp = 0.0
