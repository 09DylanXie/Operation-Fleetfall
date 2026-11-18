class_name ShipStats
extends Resource
## Balance data for one ship class. One .tres per class lives in res://data/ships/.

## New classes are appended so saved class ids (network, data files) stay valid.
enum ShipClass { DD, SS, CL, CA, BB, CV, BC, SBB, RS, RD, LCV }
enum TorpedoMode { NONE, AUTO_BROADSIDE, MANUAL_BOW_STERN }

@export_group("Identity")
@export var ship_class: ShipClass = ShipClass.DD
@export var code: String = "DD"
@export var display_name: String = "Destroyer"

@export_group("Production")
@export var gold_cost: int = 100
@export var steel_cost: int = 50
@export var build_time: float = 15.0
@export var required_shipyard_tier: int = 1

@export_group("Hull")
## Movement speed relative to the Destroyer (1.0 = 100%).
@export var speed_factor: float = 1.0
@export var turn_rate_deg: float = 90.0
## Flat damage reduction, 0.0 - 1.0.
@export var base_armor: float = 0.0
@export var max_hp: float = 600.0
@export var hull_length: float = 48.0
@export var hull_width: float = 12.0
## Shallow-draft hulls (DD, SS) may enter shallow water around Minor islands.
@export var shallow_draft: bool = false
@export var spotting_range: float = 700.0
@export var is_submarine: bool = false
@export var detects_submarines: bool = false

@export_group("Guns")
@export var gun_mounts: int = 0
@export var shells_per_mount: int = 0
@export var shell_damage: float = 0.0
@export var shell_speed: float = 300.0
@export var gun_range: float = 0.0
## Seconds between salvos.
@export var fire_interval: float = 4.0
@export var dispersion_deg: float = 0.0
## False for hulls whose weapons cannot be aimed at Submarines (Battleships).
@export var can_target_submarines: bool = true
## Roster "Pen" rating. The GDD defines no penetration mechanic yet, so this is data only.
@export var penetration: float = 0.0
## Position of each mount along the hull axis (+ is toward the bow).
@export var mount_offsets: PackedFloat32Array = PackedFloat32Array()
## Rest facing of each mount relative to the bow (0 = forward, 180 = aft).
@export var mount_facings_deg: PackedFloat32Array = PackedFloat32Array()
## Each mount can train this far either side of its rest facing.
@export var mount_arc_half_deg: float = 150.0

@export_group("Secondary Guns")
## Small guns on the citadel (Battleships) that fight on their own, with their own
## target, range and reload. One shell per mount. 0 = none.
@export var secondary_mounts: int = 0
@export var secondary_shell_damage: float = 0.0
@export var secondary_shell_speed: float = 300.0
@export var secondary_range: float = 0.0
## Seconds between secondary salvos.
@export var secondary_interval: float = 8.0
@export var secondary_dispersion_deg: float = 0.6
## Position of each secondary mount on the hull (x toward the bow, y toward starboard).
@export var secondary_offsets: PackedVector2Array = PackedVector2Array()
## Rest facing of each secondary mount relative to the bow (90 = starboard, -90 = port).
@export var secondary_facings_deg: PackedFloat32Array = PackedFloat32Array()
@export var secondary_arc_half_deg: float = 100.0

@export_group("Torpedoes")
@export var torpedo_mode: TorpedoMode = TorpedoMode.NONE
@export var torpedoes_per_launch: int = 0
@export var torpedo_interval: float = 30.0
@export var torpedo_range: float = 0.0
@export var torpedo_spread_deg: float = 0.0
## Multiplier on the standard torpedo speed (GameData.torpedo_speed()).
@export var torpedo_speed_scale: float = 1.0

@export_group("Depth Charges")
## Enemy submarines this close are depth-charged automatically. 0 = no depth charges.
@export var depth_charge_range: float = 0.0
## Damage of one pattern; depth charges ignore armor.
@export var depth_charge_damage: float = 0.0
## Seconds between patterns.
@export var depth_charge_interval: float = 2.5

@export_group("Aircraft")
## HE dive-bomber squadrons sent up per launch. 0 = not a carrier.
@export var squadrons_per_launch: int = 0
## Seconds between dive-bomber launches while there is a target.
@export var plane_interval: float = 5.0
## A strike target must be within this range of the carrier.
@export var plane_range: float = 0.0
## Most dive-bomber squadrons this carrier can have in the air at once.
@export var max_squadrons: int = 0
## Most squadrons of every role together this carrier can have in the air (Light Carrier). 0 = no limit.
@export var max_total_squadrons: int = 0
## Most dive-bomber squadrons this carrier stacks on any one target. 0 = no limit.
@export var squadrons_per_target: int = 0
## Torpedo bombers: one flight every this many seconds against capital ships (BC and up),
## dropping two parallel torpedoes at the target's broadside and flying home. 0 = none.
@export var torpedo_bomber_interval: float = 0.0
@export var max_torpedo_bombers: int = 0
## Torpedo flights sent per launch, spread round-robin over up to this many capital targets
## (the ordered strike target first, then the nearest). The Heavy Carrier sends 3.
@export var torpedo_flights_per_launch: int = 1
## Most torpedo flights from this carrier in the air against any one target.
@export var torpedo_flights_per_target: int = 1
## Depth-charge bombers: one flight every this many seconds against spotted submarines. 0 = none.
@export var depth_bomber_interval: float = 0.0
@export var max_depth_bombers: int = 0
## Multiplies the HE bomb damage of this carrier's dive bombers (Heavy Carrier 1.1).
@export var bomb_damage_multiplier: float = 1.0

@export_group("Support")
## Resource Ship: anchored by an island (not a Home Base) it earns a Minor island's income.
@export var mines_islands: bool = false
## Radar Ship: its radar sees over islands (spotting needs no line of sight).
@export var sees_over_islands: bool = false

@export_group("Anti-Air")
## Chance (0-1) that this ship shoots down a squadron each time it is bombed.
@export var aa_kill_chance: float = 0.0
## Defensive anti-air barrage (Super Battleship): every `periodic_aa_interval` seconds each
## enemy squadron within `periodic_aa_range` is shot down with this chance. 0 = none.
@export var periodic_aa_chance: float = 0.0
@export var periodic_aa_interval: float = 10.0
@export var periodic_aa_range: float = 0.0


## Classes torpedo bombers may attack: Battlecruiser and larger.
static func is_capital_class(cls: ShipClass) -> bool:
	return cls == ShipClass.BC or cls == ShipClass.BB or cls == ShipClass.SBB or cls == ShipClass.CV


## Non-combat hulls (Resource Ship, Radar Ship): no weapons at all. They never capture or
## contest islands.
func is_support() -> bool:
	return not has_guns() and not has_planes() and torpedo_mode == TorpedoMode.NONE \
		and not has_depth_charges() and not has_secondaries()


func has_torpedo_bombers() -> bool:
	return has_planes() and torpedo_bomber_interval > 0.0 and max_torpedo_bombers > 0


func has_depth_bombers() -> bool:
	return has_planes() and depth_bomber_interval > 0.0 and max_depth_bombers > 0


func has_guns() -> bool:
	return gun_mounts > 0 and shells_per_mount > 0


func has_secondaries() -> bool:
	return secondary_mounts > 0 and secondary_shell_damage > 0.0 and secondary_range > 0.0


## Sustained secondary damage per second before armor.
func secondary_dps() -> float:
	if not has_secondaries():
		return 0.0
	return float(secondary_mounts) * secondary_shell_damage / maxf(0.001, secondary_interval)


func has_periodic_aa() -> bool:
	return periodic_aa_chance > 0.0 and periodic_aa_range > 0.0


## Visual turret traverse in degrees per second: small fast hulls train quickly, big slow
## capital ships slowly. Cosmetic only (firing arcs decide when a mount may shoot).
func turret_traverse_deg() -> float:
	return 12.0 + 70.0 * speed_factor * sqrt(48.0 / maxf(1.0, hull_length))


func has_depth_charges() -> bool:
	return depth_charge_range > 0.0 and depth_charge_damage > 0.0


func has_planes() -> bool:
	return squadrons_per_launch > 0


func shells_per_salvo() -> int:
	return gun_mounts * shells_per_mount


func salvo_damage() -> float:
	return float(shells_per_salvo()) * shell_damage


## Sustained gun damage per second before armor.
func gun_dps() -> float:
	return salvo_damage() / maxf(0.001, fire_interval) if has_guns() else 0.0


## Longest reach of any weapon system on this hull.
func engage_range() -> float:
	var best: float = 0.0
	if has_guns():
		best = gun_range
	if torpedo_mode != TorpedoMode.NONE:
		best = maxf(best, torpedo_range)
	if has_planes():
		best = maxf(best, plane_range)
	return best
