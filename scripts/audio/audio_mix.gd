class_name AudioMix
extends RefCounted
## The audio buses and the player's volume settings. Two buses feed Master: "Music" (the
## `Music` playlist) and "SFX" (every `Sfx` sound and the ambience). Volumes are linear
## 0..1 sliders, saved to `user://audio.cfg` so they survive restarts. Cosmetic only.

const MUSIC: String = "Music"
const SFX: String = "SFX"
const SAVE_PATH: String = "user://audio.cfg"
## Slider defaults: the soundtrack sits a little under the effects.
const DEFAULTS: Dictionary[String, float] = {MUSIC: 0.55, SFX: 0.8}

static var _ready_done: bool = false
static var _volumes: Dictionary[String, float] = {}


## Creates the buses (once) and applies the saved volumes.
static func setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	for bus: String in [MUSIC, SFX]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	var config: ConfigFile = ConfigFile.new()
	var loaded: bool = config.load(SAVE_PATH) == OK
	for bus: String in [MUSIC, SFX]:
		var value: float = DEFAULTS[bus]
		if loaded:
			value = float(config.get_value("volume", bus, value))
		_apply(bus, value)


## Linear volume 0..1 of `bus`.
static func volume(bus: String) -> float:
	return _volumes.get(bus, DEFAULTS.get(bus, 1.0)) as float


## Sets `bus` to linear volume `value` (0..1) and saves it.
static func set_volume(bus: String, value: float) -> void:
	setup()
	_apply(bus, value)
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	for name: String in _volumes:
		config.set_value("volume", name, _volumes[name])
	config.save(SAVE_PATH)


static func _apply(bus: String, value: float) -> void:
	var v: float = clampf(value, 0.0, 1.0)
	_volumes[bus] = v
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	# A slider at zero silences the bus outright; otherwise a gentle curve so the low end
	# of the slider is usable.
	AudioServer.set_bus_mute(index, v <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v * v, 0.0001)))
