extends Node
## Sound effects and ambience (autoload `Sfx`). Every sound is synthesised in code when the
## game starts (on a worker thread, so there are no audio files), with its own random number
## generator: sound is cosmetic and never touches `Match.rng` or game state. Nothing is made
## or played when running headless (tests, dedicated hosts).

const RATE: int = 22050
const POOL_SIZE: int = 24
const UI_POOL_SIZE: int = 4
const LISTEN_DISTANCE: float = 2400.0

## Loudness (dB) and shortest gap between two plays (seconds) for each sound.
const VOLUME: Dictionary[String, float] = {
	"gun_small": -9.0, "gun_mid": -7.0, "gun_big": -4.0, "splash": -15.0, "hit": -9.0,
	"torpedo_launch": -10.0, "torpedo_hit": -3.0, "explosion": -1.0, "depth_charge": -6.0,
	"bomb": -5.0, "plane": -15.0, "flak": -10.0, "ui_click": -10.0, "ui_hover": -20.0,
	"build_done": -8.0, "capture": -7.0, "alert": -8.0,
}
const MIN_GAP: Dictionary[String, float] = {
	"gun_small": 0.04, "gun_mid": 0.05, "gun_big": 0.08, "splash": 0.05, "hit": 0.05,
	"torpedo_launch": 0.15, "torpedo_hit": 0.1, "explosion": 0.15, "depth_charge": 0.12,
	"bomb": 0.08, "plane": 0.6, "flak": 0.2, "ui_click": 0.03, "ui_hover": 0.05,
	"build_done": 0.5, "capture": 0.5, "alert": 1.0,
}

var muted: bool = false
var enabled: bool = false
var _streams: Dictionary[String, AudioStreamWAV] = {}
var _pool: Array[AudioStreamPlayer2D] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _next_ui: int = 0
var _last_play: Dictionary[String, int] = {}
var _ocean: AudioStreamPlayer = null
var _wind: AudioStreamPlayer = null
var _ambience: bool = false
var _thread: Thread = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	enabled = true
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.max_distance = LISTEN_DISTANCE
		player.attenuation = 1.2
		player.panning_strength = 0.8
		add_child(player)
		_pool.append(player)
	for i: int in UI_POOL_SIZE:
		var ui: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(ui)
		_ui_pool.append(ui)
	_ocean = AudioStreamPlayer.new()
	_wind = AudioStreamPlayer.new()
	add_child(_ocean)
	add_child(_wind)
	_rng.seed = 7741
	_thread = Thread.new()
	_thread.start(_bake_all)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## Plays `sound` at world point `at` (heard by distance from the camera).
func play_at(sound: String, at: Vector2) -> void:
	var stream: AudioStreamWAV = _take(sound)
	if stream == null:
		return
	var player: AudioStreamPlayer2D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.global_position = at
	player.volume_db = VOLUME.get(sound, -8.0) as float
	player.pitch_scale = _rng.randf_range(0.92, 1.08)
	player.play()


## Plays an interface sound (not positional).
func ui(sound: String) -> void:
	var stream: AudioStreamWAV = _take(sound)
	if stream == null:
		return
	var player: AudioStreamPlayer = _ui_pool[_next_ui]
	_next_ui = (_next_ui + 1) % _ui_pool.size()
	player.stream = stream
	player.volume_db = VOLUME.get(sound, -8.0) as float
	player.pitch_scale = _rng.randf_range(0.97, 1.03)
	player.play()


## Ocean ambience on while a match is on screen.
func set_ambience(on: bool) -> void:
	_ambience = on
	if not enabled:
		return
	if not on:
		_ocean.stop()
		_wind.stop()


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, muted)


func _take(sound: String) -> AudioStreamWAV:
	if not enabled or muted or not _streams.has(sound):
		return null
	var now: int = Time.get_ticks_msec()
	var gap: int = int((MIN_GAP.get(sound, 0.05) as float) * 1000.0)
	if now - _last_play.get(sound, -100000) < gap:
		return null
	_last_play[sound] = now
	return _streams[sound]


func _process(delta: float) -> void:
	if not enabled or not _streams.has("ocean"):
		return
	if not _ambience:
		return
	if not _ocean.playing:
		_ocean.stream = _streams["ocean"]
		_ocean.volume_db = -16.0
		_ocean.play()
	# Wind and rain while the camera is inside a storm.
	var storm: float = 0.0
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		var at: Vector2 = camera.get_screen_center_position()
		for node: Node in get_tree().get_nodes_in_group("weather_fronts"):
			var front: WeatherFront = node as WeatherFront
			if front == null:
				continue
			var d: float = front.position.distance_to(at)
			storm = maxf(storm, clampf(1.0 - (d - front.radius * 0.6) / (front.radius * 0.8), 0.0, 1.0))
	if storm > 0.01:
		if not _wind.playing:
			_wind.stream = _streams["wind"]
			_wind.volume_db = -40.0
			_wind.play()
		_wind.volume_db = move_toward(_wind.volume_db, lerpf(-34.0, -10.0, storm), 30.0 * delta)
	elif _wind.playing:
		_wind.volume_db = move_toward(_wind.volume_db, -50.0, 30.0 * delta)
		if _wind.volume_db <= -49.0:
			_wind.stop()


# --- Synthesis --------------------------------------------------------------

func _bake_all() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 90210
	var baked: Dictionary[String, AudioStreamWAV] = {}
	baked["gun_small"] = _wav(_gun(rng, 0.45, 0.30, 140.0, 0.06), 0.9)
	baked["gun_mid"] = _wav(_gun(rng, 0.8, 0.18, 95.0, 0.12), 0.95)
	baked["gun_big"] = _wav(_gun(rng, 1.6, 0.09, 55.0, 0.28), 1.0)
	baked["splash"] = _wav(_splash(rng, 0.6), 0.8)
	baked["hit"] = _wav(_hit(rng), 0.9)
	baked["explosion"] = _wav(_boom(rng, 2.4, 0.05, 45.0, 0.7, true), 1.0)
	baked["bomb"] = _wav(_boom(rng, 1.2, 0.09, 60.0, 0.35, false), 1.0)
	baked["torpedo_hit"] = _wav(_torpedo_hit(rng), 1.0)
	baked["depth_charge"] = _wav(_depth_charge(rng), 1.0)
	baked["torpedo_launch"] = _wav(_torpedo_launch(rng), 0.8)
	baked["plane"] = _wav(_plane(rng), 0.7)
	baked["flak"] = _wav(_flak(rng), 0.8)
	baked["ui_click"] = _wav(_blip(0.07, 1250.0, 700.0, 0.015), 0.7)
	baked["ui_hover"] = _wav(_blip(0.045, 1900.0, 1700.0, 0.01), 0.5)
	baked["build_done"] = _wav(_chime([659.25, 987.77], 0.16, 0.6), 0.7)
	baked["capture"] = _wav(_chime([523.25, 659.25, 783.99, 1046.5], 0.11, 0.7), 0.7)
	baked["alert"] = _wav(_alert(), 0.6)
	baked["ocean"] = _wav(_ocean_loop(rng), 0.8, true)
	baked["wind"] = _wav(_wind_loop(rng), 0.8, true)
	_on_baked.call_deferred(baked)


func _on_baked(baked: Dictionary[String, AudioStreamWAV]) -> void:
	_streams = baked


func _buf(seconds: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	return buf


static func _env(t: float, attack: float, tau: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-(t - attack) / tau)


## Filtered noise added to `buf`: `lp` sets the brightness (0-1, one-pole low-pass); `high`
## subtracts the low-passed part for hiss.
func _add_noise(rng: RandomNumberGenerator, buf: PackedFloat32Array, start: float, lp: float,
		attack: float, tau: float, amp: float, high: bool = false) -> void:
	var low: float = 0.0
	var low2: float = 0.0
	var first: int = int(start * RATE)
	for i: int in range(first, buf.size()):
		var t: float = float(i - first) / RATE
		var e: float = _env(t, attack, tau)
		if e < 0.0005 and t > attack:
			break
		var n: float = rng.randf() * 2.0 - 1.0
		low += lp * (n - low)
		low2 += lp * (low - low2)
		var v: float = (n - low2) if high else low2
		buf[i] += v * e * amp


## A pitched thump or tone, gliding from `f0` to `f1`.
func _add_tone(buf: PackedFloat32Array, start: float, f0: float, f1: float, attack: float,
		tau: float, amp: float, square: bool = false) -> void:
	var phase: float = 0.0
	var first: int = int(start * RATE)
	var span: float = maxf(tau * 4.0, 0.01)
	for i: int in range(first, buf.size()):
		var t: float = float(i - first) / RATE
		var e: float = _env(t, attack, tau)
		if e < 0.0005 and t > attack:
			break
		var f: float = lerpf(f0, f1, clampf(t / span, 0.0, 1.0))
		phase += TAU * f / RATE
		var s: float = sin(phase)
		if square:
			s = clampf(s * 3.0, -1.0, 1.0) * 0.6 + s * 0.4
		buf[i] += s * e * amp


func _gun(rng: RandomNumberGenerator, length: float, lp: float, thump: float, tau: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(length)
	_add_noise(rng, buf, 0.0, minf(0.9, lp * 2.5), 0.002, 0.02, 0.9)
	_add_noise(rng, buf, 0.0, lp, 0.004, tau, 1.0)
	_add_tone(buf, 0.0, thump * 1.6, thump * 0.7, 0.003, tau * 0.8, 0.9)
	_add_noise(rng, buf, 0.05, lp * 0.5, 0.05, tau * 2.0, 0.35)
	return buf


func _splash(rng: RandomNumberGenerator, length: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(length)
	_add_noise(rng, buf, 0.0, 0.35, 0.015, 0.12, 0.8, true)
	_add_noise(rng, buf, 0.03, 0.12, 0.04, 0.16, 0.6)
	_add_tone(buf, 0.0, 180.0, 90.0, 0.005, 0.05, 0.3)
	return buf


func _hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(0.6)
	_add_noise(rng, buf, 0.0, 0.5, 0.001, 0.03, 0.8)
	_add_tone(buf, 0.0, 820.0, 760.0, 0.001, 0.09, 0.35)
	_add_tone(buf, 0.0, 1370.0, 1290.0, 0.001, 0.06, 0.25)
	_add_tone(buf, 0.0, 120.0, 70.0, 0.002, 0.08, 0.7)
	_add_noise(rng, buf, 0.02, 0.15, 0.01, 0.12, 0.5)
	return buf


func _boom(rng: RandomNumberGenerator, length: float, lp: float, thump: float, tau: float,
		crackle: bool) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(length)
	_add_noise(rng, buf, 0.0, lp * 3.0, 0.002, 0.05, 0.8)
	_add_noise(rng, buf, 0.0, lp, 0.01, tau, 1.0)
	_add_tone(buf, 0.0, thump * 1.8, thump * 0.5, 0.004, tau * 0.6, 1.0)
	if crackle:
		for i: int in 14:
			_add_noise(rng, buf, 0.15 + rng.randf() * (length * 0.6), 0.6, 0.001, 0.015, 0.35)
		_add_tone(buf, 0.35, 70.0, 35.0, 0.02, 0.35, 0.5)
	return buf


func _torpedo_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.8)
	_add_tone(buf, 0.0, 70.0, 32.0, 0.01, 0.35, 1.0)
	_add_noise(rng, buf, 0.0, 0.05, 0.01, 0.3, 0.9)
	_add_noise(rng, buf, 0.12, 0.3, 0.08, 0.45, 0.55, true)
	_add_noise(rng, buf, 0.0, 0.4, 0.001, 0.04, 0.5)
	return buf


func _depth_charge(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.4)
	_add_tone(buf, 0.0, 55.0, 28.0, 0.03, 0.3, 1.0)
	_add_noise(rng, buf, 0.0, 0.025, 0.03, 0.35, 0.9)
	_add_noise(rng, buf, 0.25, 0.25, 0.1, 0.3, 0.35, true)
	return buf


func _torpedo_launch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(0.7)
	_add_noise(rng, buf, 0.0, 0.08, 0.004, 0.05, 0.6)
	_add_noise(rng, buf, 0.03, 0.3, 0.08, 0.18, 0.7, true)
	_add_tone(buf, 0.0, 260.0, 140.0, 0.003, 0.06, 0.4)
	return buf


func _plane(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.6)
	var phase: float = 0.0
	for i: int in buf.size():
		var t: float = float(i) / RATE
		var e: float = clampf(t / 0.4, 0.0, 1.0) * clampf((1.6 - t) / 0.7, 0.0, 1.0)
		var f: float = 92.0 + 18.0 * t
		phase += TAU * f / RATE
		var saw: float = fmod(phase / TAU, 1.0) * 2.0 - 1.0
		var am: float = 0.65 + 0.35 * sin(t * TAU * 23.0)
		buf[i] = saw * am * e * 0.6
	_add_noise(rng, buf, 0.0, 0.2, 0.4, 0.6, 0.25)
	return buf


func _flak(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.0)
	for k: int in 4:
		var at: float = k * 0.17 + rng.randf() * 0.05
		_add_noise(rng, buf, at, 0.45, 0.001, 0.035, 0.9)
		_add_tone(buf, at, 220.0, 120.0, 0.001, 0.03, 0.4)
	return buf


func _blip(length: float, f0: float, f1: float, tau: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(length)
	_add_tone(buf, 0.0, f0, f1, 0.002, tau, 1.0)
	_add_tone(buf, 0.0, f0 * 2.0, f1 * 2.0, 0.002, tau * 0.5, 0.25)
	return buf


func _chime(notes: Array[float], step: float, tail: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(step * notes.size() + tail)
	for i: int in notes.size():
		_add_tone(buf, step * i, notes[i], notes[i], 0.004, 0.22, 0.7)
		_add_tone(buf, step * i, notes[i] * 2.0, notes[i] * 2.0, 0.004, 0.1, 0.2)
	return buf


func _alert() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(0.9)
	for i: int in 4:
		var f: float = 587.33 if i % 2 == 0 else 440.0
		_add_tone(buf, i * 0.18, f, f, 0.005, 0.07, 0.6, true)
	return buf


func _ocean_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length: float = 8.0
	var fade: float = 0.75
	var buf: PackedFloat32Array = _buf(length + fade)
	var low: float = 0.0
	var low2: float = 0.0
	var hiss_low: float = 0.0
	for i: int in buf.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf() * 2.0 - 1.0
		low += 0.02 * (n - low)
		low2 += 0.02 * (low - low2)
		hiss_low += 0.25 * (n - hiss_low)
		var swell: float = 0.55 + 0.45 * pow(sin(PI * t / 4.0), 2.0)
		var surf: float = pow(maxf(0.0, sin(PI * (t - 1.0) / 2.0)), 6.0)
		buf[i] = low2 * 9.0 * swell + (n - hiss_low) * (0.05 + 0.12 * surf)
	return _loop(buf, length, fade)


func _wind_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length: float = 6.0
	var fade: float = 0.75
	var buf: PackedFloat32Array = _buf(length + fade)
	var a: float = 0.0
	var b: float = 0.0
	var rain_low: float = 0.0
	for i: int in buf.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf() * 2.0 - 1.0
		a += 0.06 * (n - a)
		b += 0.008 * (n - b)
		rain_low += 0.5 * (n - rain_low)
		var gust: float = 0.6 + 0.4 * sin(TAU * t / 3.0) * sin(TAU * t / 6.0)
		var drop: float = 0.0
		if rng.randf() < 0.004:
			drop = rng.randf_range(0.3, 0.8)
		buf[i] = (a - b) * 4.0 * gust + (n - rain_low) * 0.18 + drop * 0.3
	return _loop(buf, length, fade)


## Cross-fades the overhang into the start so the clip loops without a click.
func _loop(buf: PackedFloat32Array, length: float, fade: float) -> PackedFloat32Array:
	var n: int = int(length * RATE)
	var f: int = int(fade * RATE)
	for i: int in f:
		var w: float = float(i) / f
		buf[i] = buf[i] * w + buf[n + i] * (1.0 - w)
	buf.resize(n)
	return buf


func _wav(buf: PackedFloat32Array, peak: float, loop: bool = false) -> AudioStreamWAV:
	var top: float = 0.0001
	for v: float in buf:
		top = maxf(top, absf(v))
	var gain: float = peak / top
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i: int in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	return wav
