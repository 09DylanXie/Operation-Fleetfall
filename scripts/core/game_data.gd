class_name GameData
extends RefCounted
## Lazy loader for balance resources plus the values the GDD defines as
## ratios of other stats (torpedo damage, torpedo speed, plane speed).

const BALANCE_PATH: String = "res://data/balance.tres"
const MAP_CONFIG_PATH: String = "res://data/map_config.tres"
## Indexed by MapConfig.Size. Medium is the original map.
const MAP_CONFIG_PATHS: Array[String] = [
	"res://data/maps/small.tres",
	"res://data/map_config.tres",
	"res://data/maps/large.tres",
]
## Indexed by ShipStats.ShipClass.
const SHIP_PATHS: Array[String] = [
	"res://data/ships/dd.tres",
	"res://data/ships/ss.tres",
	"res://data/ships/cl.tres",
	"res://data/ships/ca.tres",
	"res://data/ships/bb.tres",
	"res://data/ships/cv.tres",
	"res://data/ships/bc.tres",
	"res://data/ships/sbb.tres",
	"res://data/ships/rs.tres",
	"res://data/ships/rd.tres",
	"res://data/ships/lcv.tres",
]

static var _balance: GameBalance = null
static var _map_config: MapConfig = null
static var _map_configs: Dictionary[int, MapConfig] = {}
static var _ships: Dictionary[int, ShipStats] = {}


static func balance() -> GameBalance:
	if _balance == null:
		_balance = load(BALANCE_PATH) as GameBalance
	return _balance


static func map_config() -> MapConfig:
	if _map_config == null:
		_map_config = load(MAP_CONFIG_PATH) as MapConfig
	return _map_config


static func map_config_for(size: MapConfig.Size) -> MapConfig:
	var key: int = int(size)
	if not _map_configs.has(key):
		_map_configs[key] = load(MAP_CONFIG_PATHS[key]) as MapConfig
	return _map_configs[key]


static func ship(ship_class: ShipStats.ShipClass) -> ShipStats:
	var key: int = int(ship_class)
	if not _ships.has(key):
		_ships[key] = load(SHIP_PATHS[key]) as ShipStats
	return _ships[key]


static func all_classes() -> Array[ShipStats.ShipClass]:
	return [
		ShipStats.ShipClass.DD,
		ShipStats.ShipClass.SS,
		ShipStats.ShipClass.CL,
		ShipStats.ShipClass.CA,
		ShipStats.ShipClass.BC,
		ShipStats.ShipClass.BB,
		ShipStats.ShipClass.SBB,
		ShipStats.ShipClass.CV,
		ShipStats.ShipClass.RS,
		ShipStats.ShipClass.RD,
		ShipStats.ShipClass.LCV,
	]


## 30% more than a single Battleship shell.
static func torpedo_damage() -> float:
	return balance().torpedo_damage_multiplier * ship(ShipStats.ShipClass.BB).shell_damage


## Standard torpedo speed: slightly slower than a Battleship shell. Each class scales it
## with ShipStats.torpedo_speed_scale (Destroyer torpedoes run at half speed).
static func torpedo_speed() -> float:
	return balance().torpedo_speed_factor * ship(ShipStats.ShipClass.BB).shell_speed


## 50% of the standard torpedo speed.
static func plane_speed() -> float:
	return balance().plane_speed_factor * torpedo_speed()


## One HE bomb run of a squadron on station (ignores armor).
static func bomb_damage() -> float:
	return balance().bomb_damage


static func ship_speed(stats: ShipStats) -> float:
	return balance().base_speed * stats.speed_factor
