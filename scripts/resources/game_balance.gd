class_name GameBalance
extends Resource
## Global balance values (res://data/balance.tres). Values marked "GDD" are fixed
## by the design document; the rest are tunable defaults the GDD leaves open.

@export_group("Fleet")
## GDD: 30 ships per player, including hulls under construction and queued orders.
@export var fleet_cap: int = 30
## Destroyer speed in px/s; every class scales from this.
@export var base_speed: float = 100.0
## Fraction of max HP a hull has when it is first laid down.
@export var construction_start_hp_fraction: float = 0.2

@export_group("Economy")
## GDD: 15 second deposit interval.
@export var tick_interval: float = 15.0
@export var home_gold: int = 50
@export var home_steel: int = 20
@export var minor_gold: int = 30
@export var minor_steel: int = 10
@export var major_gold: int = 20
@export var major_steel: int = 50
@export var start_gold: int = 400
@export var start_steel: int = 200

@export_group("Combat")
## GDD: -5% armor per additional attacker beyond the first.
@export var armor_strip_per_attacker: float = 0.05
## GDD: torpedo = 1.30 x one Battleship shell.
@export var torpedo_damage_multiplier: float = 1.3
## GDD: "slightly slower than Battleship shells". Destroyer torpedoes run at half of this
## (ShipStats.torpedo_speed_scale).
@export var torpedo_speed_factor: float = 0.92
@export var torpedo_homing_turn_deg: float = 60.0
## GDD: planes fly at 50% of the standard torpedo speed.
@export var plane_speed_factor: float = 0.5
## Damage of one HE bomb run. Bombs ignore armor. A squadron on station drops one every
## `bomb_interval` seconds, so this is far below the single-drop payload of the original GDD.
@export var bomb_damage: float = 150.0
## Seconds between bomb runs of a squadron circling its target.
@export var bomb_interval: float = 3.0
@export var plane_turn_rate_deg: float = 150.0

@export_group("Submarines")
## GDD: homing ping lasts 2 seconds.
@export var sub_homing_time: float = 2.0
## GDD: firing reveals the submarine for 15 seconds.
@export var sub_reveal_time: float = 15.0
## Range at which enemy Destroyers and Shipyards detect a submerged submarine.
@export var sub_detection_range: float = 320.0

@export_group("Home Base")
@export var home_base_hp: float = 15000.0
@export var home_base_armor: float = 0.0
@export var home_base_spotting: float = 700.0
@export var home_base_radius: float = 80.0
@export var home_shipyard_start_tier: int = 1
@export var home_shipyard_max_tier: int = 2

@export_group("Islands")
@export var island_spotting: float = 380.0
## Seconds a team must hold an island uncontested to capture it.
@export var capture_time: float = 30.0
@export var minor_capture_radius: float = 230.0
@export var major_capture_radius: float = 280.0
@export var minor_shipyard_max_tier: int = 1
## Hit points of the garrison of a captured island. An owned island cannot be captured:
## its garrison has to be destroyed first, which turns the island neutral.
@export var minor_garrison_hp: float = 2000.0
@export var major_garrison_hp: float = 4000.0
@export var garrison_armor: float = 0.0
## GDD: Tier 3 shipyards require a Deep Water (Major) island.
@export var major_shipyard_max_tier: int = 3

@export_group("Shipyards")
## Cost to build/upgrade to tier 1, 2, 3 (index = tier - 1).
@export var shipyard_gold_costs: PackedInt32Array = PackedInt32Array([150, 300, 500])
@export var shipyard_steel_costs: PackedInt32Array = PackedInt32Array([50, 200, 400])
@export var shipyard_build_times: PackedFloat32Array = PackedFloat32Array([20.0, 30.0, 45.0])
@export var max_queue_length: int = 5
## Friendly ships this close to a yard's slip are in its dock.
@export var dock_radius: float = 220.0
## Fraction of its max HP a docked ship regains per second while the yard is free.
@export var repair_rate: float = 0.02

@export_group("Weather")
@export var weather_front_count: int = 2
@export var weather_radius: float = 420.0
@export var weather_speed: float = 24.0
## Spotting range multiplier for ships inside a weather front.
@export var weather_spotting_multiplier: float = 0.35
