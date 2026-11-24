extends Node
## Sound effects and ambience (autoload `Sfx`). Every sound is synthesised in code when the
## game starts (on a worker thread by `synth_all`, so there are no audio files), with its own random number
## generator: sound is cosmetic and never touches `Match.rng` or game state. Nothing is made
## or played when running headless (tests, dedicated hosts).

const RATE: int = 32000
const POOL_SIZE: int = 32
const UI_POOL_SIZE: int = 4
const LISTEN_DISTANCE: float = 2400.0

## Loudness (dB) and shortest gap between two plays (seconds) for each sound.
const VOLUME: Dictionary[String, float] = {
	"gun_small": -10.0, "gun_mid": -8.0, "gun_big": -5.0, "splash": -14.0, "hit": -9.0,
	"torpedo_launch": -11.0, "torpedo_hit": -4.0, "explosion": -2.0, "depth_charge": -6.0,
	"bomb": -5.0, "plane": -13.0, "flak": -11.0, "ui_click": -12.0, "ui_hover": -22.0,
	"build_done": -21.0, "capture": -22.0, "alert": -10.0,
}
## The ocean bed sits far under combat and music: it should be felt more than heard.
const OCEAN_DB: float = -27.0
const MIN_GAP: Dictionary[String, float] = {
	"gun_small": 0.04, "gun_mid": 0.05, "gun_big": 0.08, "splash": 0.05, "hit": 0.05,
	"torpedo_launch": 0.15, "torpedo_hit": 0.1, "explosion": 0.15, "depth_charge": 0.12,
	"bomb": 0.08, "plane": 0.6, "flak": 0.2, "ui_click": 0.03, "ui_hover": 0.05,
	"build_done": 0.5, "capture": 0.5, "alert": 1.0,
}

## Emitted when the whole game is muted or unmuted (M, or the Sound panel).
signal mute_changed(muted: bool)

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
	AudioMix.setup()
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.bus = AudioMix.SFX
		player.max_distance = LISTEN_DISTANCE
		player.attenuation = 1.2
		player.panning_strength = 0.8
		add_child(player)
		_pool.append(player)
	for i: int in UI_POOL_SIZE:
		var ui: AudioStreamPlayer = AudioStreamPlayer.new()
		ui.bus = AudioMix.SFX
		add_child(ui)
		_ui_pool.append(ui)
	_ocean = AudioStreamPlayer.new()
	_wind = AudioStreamPlayer.new()
	_ocean.bus = AudioMix.SFX
	_wind.bus = AudioMix.SFX
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
	mute_changed.emit(muted)


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
		_ocean.volume_db = OCEAN_DB
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
	if storm > 0.01 and _streams.has("wind"):
		if not _wind.playing:
			_wind.stream = _streams["wind"]
			_wind.volume_db = -40.0
			_wind.play()
		_wind.volume_db = move_toward(_wind.volume_db, lerpf(-36.0, -20.0, storm), 30.0 * delta)
	elif _wind.playing:
		_wind.volume_db = move_toward(_wind.volume_db, -50.0, 30.0 * delta)
		if _wind.volume_db <= -49.0:
			_wind.stop()


# --- Synthesis --------------------------------------------------------------
# Every sound is built from a few physical layers: the sharp blast front (bright noise, a few
# milliseconds), the pressure thump (a falling sine), the body (noise through a closing
# low-pass), a rolling low rumble with a random tremble, and an outdoor reverb with a far echo.
# Metal rings with inharmonic modes; water is a band-passed column of noise, falling spray
# and droplet pings. Layers are soft-clipped together for weight.

const FILTER_LP: int = 0
const FILTER_BP: int = 1
const FILTER_HP: int = 2


func _bake_all() -> void:
	synth_all(func(sound: String, wav: AudioStreamWAV) -> void: _on_baked.call_deferred(sound, wav))


func _on_baked(sound: String, wav: AudioStreamWAV) -> void:
	_streams[sound] = wav


## Builds every sound and hands each to `publish(name, wav)` as soon as it is ready, interface
## sounds first so menus have them at once. Pure: no scene access, safe on a worker thread.
func synth_all(publish: Callable) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 90210
	publish.call("ui_click", _wav(_ui_click(rng), 0.55))
	publish.call("ui_hover", _wav(_ui_hover(rng), 0.3))
	publish.call("build_done", _wav(_ships_bell(rng), 0.7))
	publish.call("capture", _wav(_bosuns_call(rng), 0.6))
	publish.call("alert", _wav(_general_alarm(rng), 0.6))
	publish.call("gun_small", _wav(_gun(rng, 0), 1.0))
	publish.call("gun_mid", _wav(_gun(rng, 1), 1.0))
	publish.call("gun_big", _wav(_gun(rng, 2), 1.0))
	publish.call("splash", _wav(_splash(rng), 0.85))
	publish.call("hit", _wav(_hit(rng), 0.95))
	publish.call("bomb", _wav(_bomb(rng), 1.0))
	publish.call("flak", _wav(_flak(rng), 0.9))
	publish.call("torpedo_launch", _wav(_torpedo_launch(rng), 0.85))
	publish.call("torpedo_hit", _wav(_torpedo_hit(rng), 1.0))
	publish.call("depth_charge", _wav(_depth_charge(rng), 1.0))
	publish.call("explosion", _wav(_explosion(rng), 1.0))
	publish.call("plane", _wav(_plane(rng), 0.8))
	publish.call("wind", _wav(_wind_loop(rng), 0.8, true))
	publish.call("ocean", _wav(_ocean_loop(rng), 0.8, true))


# --- Building blocks --------------------------------------------------------

func _buf(seconds: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	return buf


static func _env(t: float, attack: float, tau: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-(t - attack) / tau)


## Noise mixed into `buf` from `start` for `length` seconds through a state-variable filter
## (FILTER_LP / BP / HP) whose cutoff glides exponentially from `c0` to `c1` Hz; `q` is the
## damping (lower rings more). Low and band outputs are gain-matched so `amp` means about the
## same loudness at any cutoff. The level rises over `attack`, decays with time constant
## `decay`, and `rough` (0-1) makes it tremble at random about `rate` times a second, like
## rolling thunder or breaking surf.
func _noise(rng: RandomNumberGenerator, buf: PackedFloat32Array, start: float, length: float,
		c0: float, c1: float, mode: int, q: float, attack: float, decay: float, amp: float,
		rough: float = 0.0, rate: float = 14.0) -> void:
	var first: int = int(start * RATE)
	var count: int = mini(int(length * RATE), buf.size() - first)
	if count <= 0:
		return
	var step: float = pow(c1 / c0, 1.0 / float(count))
	var fc: float = c0
	var low: float = 0.0
	var band: float = 0.0
	var span: int = maxi(1, int(float(RATE) / rate))
	var mod_a: float = rng.randf()
	var mod_b: float = rng.randf()
	var fade: int = maxi(1, mini(count / 8, RATE / 25))
	var top: float = float(RATE) / 7.0
	for i: int in count:
		var t: float = float(i) / RATE
		var e: float = _env(t, attack, decay)
		if e < 0.0003 and t > attack:
			break
		var cut: float = minf(fc, top)
		fc *= step
		var f: float = 2.0 * sin(PI * cut / RATE)
		var n: float = rng.randf() * 2.0 - 1.0
		var high: float = n - low - q * band
		band += f * high
		low += f * band
		var v: float = high
		if mode == FILTER_LP:
			v = low * sqrt(RATE * 0.5 / maxf(cut, 20.0)) * 0.6
		elif mode == FILTER_BP:
			v = band * sqrt(RATE * 0.5 / maxf(cut, 20.0)) * 0.6 * q
		if rough > 0.0:
			if i % span == 0:
				mod_a = mod_b
				mod_b = rng.randf()
			var m: float = lerpf(mod_a, mod_b, float(i % span) / span)
			e *= 1.0 - rough + rough * 2.0 * m * m
		if i > count - fade:
			e *= float(count - i) / fade
		buf[first + i] += v * e * amp


## A sine mixed into `buf`, pitch falling from `f0` toward `f1` with time constant `glide`
## (a pressure thump), with an optional touch of second harmonic.
func _tone(buf: PackedFloat32Array, start: float, f0: float, f1: float, glide: float, attack: float,
		decay: float, amp: float, harm: float = 0.0) -> void:
	var first: int = int(start * RATE)
	var count: int = mini(int((attack + decay * 7.0) * RATE), buf.size() - first)
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		phase += TAU * (f1 + (f0 - f1) * exp(-t / glide)) / RATE
		var v: float = sin(phase)
		if harm > 0.0:
			v += harm * sin(2.0 * phase)
		buf[first + i] += v * _env(t, attack, decay) * amp


## Struck metal: inharmonic partials of `base`, each with its own level and decay.
func _modes(buf: PackedFloat32Array, start: float, base: float, ratios: PackedFloat32Array,
		levels: PackedFloat32Array, decays: PackedFloat32Array, amp: float) -> void:
	for k: int in ratios.size():
		_tone(buf, start, base * ratios[k], base * ratios[k], 1.0, 0.0008, decays[k], amp * levels[k])


## `count` tiny pitched pings between `from` and `to` seconds: droplets, bubbles (rise > 1),
## debris. Pitch is spread evenly on a log scale between `f_lo` and `f_hi`.
func _grains(rng: RandomNumberGenerator, buf: PackedFloat32Array, from: float, to: float, count: int,
		f_lo: float, f_hi: float, rise: float, decay: float, amp_lo: float, amp_hi: float) -> void:
	for k: int in count:
		var f: float = f_lo * pow(f_hi / f_lo, rng.randf())
		_tone(buf, rng.randf_range(from, to), f, f * rise, decay * 1.5, 0.0005,
			decay * rng.randf_range(0.6, 1.4), rng.randf_range(amp_lo, amp_hi))


## `count` short broadband ticks between `from` and `to`: crackle, rattling debris.
func _ticks(rng: RandomNumberGenerator, buf: PackedFloat32Array, from: float, to: float, count: int,
		cutoff: float, decay: float, amp_lo: float, amp_hi: float) -> void:
	for k: int in count:
		_noise(rng, buf, rng.randf_range(from, to), decay * 8.0, cutoff, cutoff * 0.6, FILTER_BP, 0.7,
			0.0003, decay * rng.randf_range(0.6, 1.5), rng.randf_range(amp_lo, amp_hi))


## The blast front of a gun or explosion: a few milliseconds of very bright noise.
func _crack(rng: RandomNumberGenerator, buf: PackedFloat32Array, start: float, decay: float, amp: float) -> void:
	_noise(rng, buf, start, decay * 10.0, 9500.0, 2500.0, FILTER_LP, 0.7, 0.0006, decay, amp)


## Soft-clips the sound after normalising it: louder body, tamed peaks - the weight of a blast.
func _drive(buf: PackedFloat32Array, k: float) -> void:
	var top: float = 0.0001
	for v: float in buf:
		top = maxf(top, absf(v))
	var norm: float = tanh(k)
	for i: int in buf.size():
		buf[i] = tanh(buf[i] / top * k) / norm


## Two-pole low-pass in place.
func _lowpass(buf: PackedFloat32Array, hz: float) -> void:
	var a: float = 1.0 - exp(-TAU * hz / RATE)
	var l1: float = 0.0
	var l2: float = 0.0
	for i: int in buf.size():
		l1 += a * (buf[i] - l1)
		l2 += a * (l1 - l2)
		buf[i] = l2


## Open-sea reverb: a dark diffuse tail (damped comb filters into all-passes) after a short
## pre-delay, plus a faint low-passed far echo, as off a distant shore. Returns the sound
## with the tail added, `tail` seconds longer.
func _reverb(dry: PackedFloat32Array, tail: float, decay: float, damp: float, wet: float,
		echo: float = 0.0) -> PackedFloat32Array:
	var n: int = dry.size() + int(tail * RATE)
	var verb: PackedFloat32Array = PackedFloat32Array()
	verb.resize(n)
	var pre: int = int(0.025 * RATE)
	for delay_ms: float in [25.3, 28.9, 32.2, 35.3, 37.9]:
		var d: int = int(delay_ms * 0.001 * RATE)
		var g: float = pow(10.0, -3.0 * (float(d) / RATE) / decay)
		var line: PackedFloat32Array = PackedFloat32Array()
		line.resize(d)
		var idx: int = 0
		var store: float = 0.0
		for i: int in n:
			var j: int = i - pre
			var x: float = dry[j] if j >= 0 and j < dry.size() else 0.0
			var y: float = line[idx]
			store = y * (1.0 - damp) + store * damp
			line[idx] = x + store * g
			idx += 1
			if idx == d:
				idx = 0
			verb[i] += y * 0.2
	for delay_ms: float in [12.6, 7.7, 5.1]:
		var d: int = int(delay_ms * 0.001 * RATE)
		var line: PackedFloat32Array = PackedFloat32Array()
		line.resize(d)
		var idx: int = 0
		for i: int in n:
			var x: float = verb[i]
			var b: float = line[idx]
			line[idx] = x + b * 0.5
			verb[i] = b - x
			idx += 1
			if idx == d:
				idx = 0
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i: int in n:
		out[i] = (dry[i] if i < dry.size() else 0.0) + verb[i] * wet
	if echo > 0.0:
		var e: int = int(0.38 * RATE)
		var lp: float = 0.0
		for i: int in range(e, n):
			lp += 0.12 * (out[i - e] - lp)
			out[i] += lp * echo
	return out


# --- Weapons ----------------------------------------------------------------

## Naval guns by calibre: 0 = destroyer / secondary, 1 = cruiser, 2 = battleship. A bigger
## gun has a lower, longer thump, a darker body and a longer roll across the water.
func _gun(rng: RandomNumberGenerator, calibre: int) -> PackedFloat32Array:
	var c: float = float(calibre) / 2.0
	var length: float = lerpf(1.1, 3.2, c)
	var buf: PackedFloat32Array = _buf(length)
	_crack(rng, buf, 0.0, lerpf(0.005, 0.012, c), 1.0)
	_noise(rng, buf, 0.0, length * 0.5, lerpf(2600.0, 950.0, c), lerpf(420.0, 120.0, c), FILTER_LP, 0.8,
		0.002, lerpf(0.05, 0.18, c), 1.0)
	_tone(buf, 0.0, lerpf(190.0, 75.0, c), lerpf(90.0, 32.0, c), lerpf(0.04, 0.12, c), 0.002,
		lerpf(0.06, 0.22, c), lerpf(0.7, 1.3, c), 0.3)
	_noise(rng, buf, 0.03, length, lerpf(420.0, 170.0, c), lerpf(150.0, 60.0, c), FILTER_LP, 0.9,
		lerpf(0.03, 0.07, c), lerpf(0.22, 0.9, c), lerpf(0.4, 0.85, c), 0.7, 9.0)
	_drive(buf, lerpf(1.8, 2.4, c))
	return _reverb(buf, lerpf(1.0, 2.2, c), lerpf(1.2, 2.4, c), 0.55, lerpf(0.28, 0.36, c), lerpf(0.15, 0.28, c))


## A shell falling short: the plunge, a column of white water, the spray coming down.
func _splash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.8)
	_tone(buf, 0.0, 160.0, 60.0, 0.03, 0.002, 0.05, 0.7)
	_noise(rng, buf, 0.0, 0.15, 2500.0, 800.0, FILTER_LP, 0.8, 0.001, 0.02, 0.6)
	_noise(rng, buf, 0.01, 0.6, 500.0, 3000.0, FILTER_BP, 0.9, 0.05, 0.18, 0.9)
	_noise(rng, buf, 0.25, 1.5, 2500.0, 1700.0, FILTER_BP, 1.2, 0.12, 0.35, 0.55, 0.8, 25.0)
	_grains(rng, buf, 0.3, 1.4, 30, 900.0, 2600.0, 1.6, 0.012, 0.05, 0.2)
	_drive(buf, 1.3)
	return _reverb(buf, 0.8, 0.9, 0.4, 0.15)


## A shell striking armour: the clang of the plate, the burst inside, rattling debris.
func _hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.4)
	_crack(rng, buf, 0.0, 0.004, 1.0)
	_modes(buf, 0.0, rng.randf_range(210.0, 260.0), PackedFloat32Array([1.0, 1.58, 2.31, 2.76, 3.9, 5.4]),
		PackedFloat32Array([0.5, 0.4, 0.35, 0.3, 0.2, 0.15]),
		PackedFloat32Array([0.35, 0.25, 0.18, 0.15, 0.08, 0.05]), 0.6)
	_noise(rng, buf, 0.012, 0.7, 1800.0, 300.0, FILTER_LP, 0.8, 0.002, 0.09, 0.9)
	_tone(buf, 0.012, 110.0, 50.0, 0.05, 0.002, 0.09, 0.8)
	_ticks(rng, buf, 0.05, 0.6, 10, 4000.0, 0.004, 0.05, 0.18)
	_drive(buf, 1.8)
	return _reverb(buf, 1.0, 1.2, 0.5, 0.25, 0.12)


## An HE bomb on a deck: a sharp blast, a fireball's roar and a low roll.
func _bomb(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(2.6)
	_crack(rng, buf, 0.0, 0.01, 1.1)
	_tone(buf, 0.0, 85.0, 35.0, 0.08, 0.002, 0.2, 1.2, 0.25)
	_noise(rng, buf, 0.0, 2.0, 2000.0, 250.0, FILTER_LP, 0.8, 0.005, 0.35, 1.0, 0.4)
	_noise(rng, buf, 0.03, 2.5, 200.0, 70.0, FILTER_LP, 0.9, 0.05, 0.7, 0.6, 0.7, 8.0)
	_ticks(rng, buf, 0.1, 1.2, 8, 3500.0, 0.005, 0.05, 0.2)
	_drive(buf, 2.0)
	return _reverb(buf, 1.8, 2.0, 0.55, 0.3, 0.25)


## Anti-aircraft fire: the thump of the guns and the sharp cracks of the bursts overhead.
func _flak(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(2.0)
	for k: int in 5:
		var at: float = k * 0.3 + rng.randf() * 0.06
		_tone(buf, at, 130.0, 65.0, 0.03, 0.002, 0.05, 0.7)
		_noise(rng, buf, at, 0.3, 2500.0, 500.0, FILTER_LP, 0.8, 0.001, 0.03, 0.7)
		var burst: float = at + 0.12 + rng.randf() * 0.1
		var a: float = rng.randf_range(0.6, 1.0)
		_crack(rng, buf, burst, 0.006, 0.9 * a)
		_noise(rng, buf, burst, 0.5, 1200.0, 300.0, FILTER_LP, 0.8, 0.001, 0.08, 0.5 * a)
		_tone(buf, burst, 90.0, 45.0, 0.04, 0.002, 0.06, 0.4 * a)
	_drive(buf, 1.8)
	return _reverb(buf, 1.2, 1.6, 0.5, 0.35, 0.2)


## A torpedo leaving its tube: a puff of compressed air, the splash, the screws biting.
func _torpedo_launch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.6)
	_noise(rng, buf, 0.0, 0.4, 900.0, 300.0, FILTER_BP, 0.7, 0.003, 0.06, 1.0)
	_tone(buf, 0.0, 140.0, 70.0, 0.04, 0.002, 0.05, 0.7)
	_noise(rng, buf, 0.0, 0.3, 3500.0, 2500.0, FILTER_BP, 1.0, 0.005, 0.08, 0.4)
	_tone(buf, 0.3, 150.0, 70.0, 0.03, 0.002, 0.04, 0.5)
	_noise(rng, buf, 0.3, 0.6, 600.0, 2500.0, FILTER_BP, 0.9, 0.04, 0.15, 0.7)
	_noise(rng, buf, 0.45, 1.0, 2400.0, 1700.0, FILTER_BP, 1.1, 0.08, 0.25, 0.35, 0.8, 25.0)
	_grains(rng, buf, 0.45, 1.2, 14, 900.0, 2400.0, 1.6, 0.01, 0.04, 0.14)
	return _reverb(buf, 0.6, 0.8, 0.4, 0.15)


## A torpedo against a hull: a heavy muffled blast below the waterline, the hull ringing,
## then the water column climbing and crashing back down.
func _torpedo_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(3.6)
	_tone(buf, 0.0, 55.0, 22.0, 0.2, 0.008, 0.4, 1.4, 0.2)
	_noise(rng, buf, 0.0, 1.5, 300.0, 90.0, FILTER_LP, 0.9, 0.006, 0.4, 1.0, 0.3)
	_modes(buf, 0.0, 95.0, PackedFloat32Array([1.0, 1.47, 2.09, 2.56]),
		PackedFloat32Array([0.5, 0.35, 0.25, 0.2]), PackedFloat32Array([0.6, 0.4, 0.3, 0.2]), 0.35)
	_noise(rng, buf, 0.0, 0.9, 700.0, 160.0, FILTER_LP, 0.8, 0.004, 0.12, 0.7)
	_noise(rng, buf, 0.12, 1.0, 350.0, 3200.0, FILTER_BP, 0.8, 0.18, 0.35, 1.3, 0.3)
	_noise(rng, buf, 0.7, 2.6, 2200.0, 1500.0, FILTER_BP, 1.1, 0.3, 0.6, 0.8, 0.8, 25.0)
	_grains(rng, buf, 0.9, 3.0, 40, 800.0, 2600.0, 1.6, 0.012, 0.04, 0.18)
	_drive(buf, 1.7)
	return _reverb(buf, 1.8, 2.2, 0.55, 0.3, 0.25)


## A depth charge: a deep thud felt more than heard, then the dome of water boiling up.
func _depth_charge(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(3.4)
	_tone(buf, 0.0, 42.0, 20.0, 0.25, 0.02, 0.45, 1.4, 0.25)
	_noise(rng, buf, 0.0, 1.6, 180.0, 70.0, FILTER_LP, 0.9, 0.02, 0.5, 1.0, 0.3)
	_noise(rng, buf, 0.0, 0.8, 400.0, 120.0, FILTER_LP, 0.8, 0.02, 0.15, 0.5)
	_noise(rng, buf, 0.55, 1.4, 250.0, 2400.0, FILTER_BP, 0.9, 0.25, 0.4, 1.1, 0.4)
	_grains(rng, buf, 0.5, 1.8, 30, 120.0, 420.0, 1.8, 0.025, 0.08, 0.3)
	_noise(rng, buf, 1.0, 2.2, 2000.0, 1400.0, FILTER_BP, 1.1, 0.25, 0.5, 0.4, 0.8, 25.0)
	_drive(buf, 1.6)
	return _reverb(buf, 1.5, 1.8, 0.55, 0.25, 0.2)


## A ship blowing up: the blast, the fireball, a long roll, secondary detonations and the
## crackle of cooking-off ammunition.
func _explosion(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(5.0)
	_crack(rng, buf, 0.0, 0.015, 1.2)
	_tone(buf, 0.0, 60.0, 24.0, 0.25, 0.004, 0.45, 1.4, 0.3)
	_noise(rng, buf, 0.0, 3.5, 1600.0, 180.0, FILTER_LP, 0.8, 0.02, 0.9, 1.4, 0.5)
	_noise(rng, buf, 0.05, 5.0, 140.0, 55.0, FILTER_LP, 0.9, 0.1, 1.8, 1.0, 0.8, 6.0)
	for k: int in 4:
		var at: float = rng.randf_range(0.5, 3.0)
		var a: float = rng.randf_range(0.3, 0.7)
		_tone(buf, at, 80.0, 35.0, 0.1, 0.003, 0.15, a)
		_noise(rng, buf, at, 0.8, 1200.0, 250.0, FILTER_LP, 0.8, 0.003, 0.15, a * 0.8)
	_ticks(rng, buf, 0.3, 4.0, 25, 3000.0, 0.004, 0.1, 0.35)
	_drive(buf, 2.0)
	return _reverb(buf, 2.5, 3.0, 0.6, 0.35, 0.3)


## A squadron passing: three radial engines slightly out of step (their beat is the
## familiar throb), each a train of exhaust pulses, pitch dropping as they pass (Doppler).
func _plane(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length: float = 3.4
	var buf: PackedFloat32Array = _buf(length)
	for base: float in [86.0, 87.3, 84.9]:
		var phase: float = rng.randf()
		var gain: float = 1.0
		for i: int in buf.size():
			var t: float = float(i) / RATE
			var doppler: float = 1.07 - 0.14 * smoothstep(length * 0.35, length * 0.65, t)
			phase += base * doppler / RATE
			if phase >= 1.0:
				phase -= 1.0
				gain = rng.randf_range(0.75, 1.0)
			buf[i] += (exp(-phase * 9.0) - 0.11) * gain
	_lowpass(buf, 1800.0)
	_noise(rng, buf, 0.0, length, 700.0, 500.0, FILTER_BP, 0.6, 0.0, 1000.0, 0.25, 0.4, 4.0)
	for i: int in buf.size():
		var t: float = float(i) / RATE
		var x: float = (t - length * 0.5) / 0.7
		buf[i] *= 1.0 / (1.0 + x * x) * clampf(t / 0.3, 0.0, 1.0) * clampf((length - t) / 0.3, 0.0, 1.0)
	return _reverb(buf, 0.8, 1.0, 0.5, 0.15)


# --- Interface --------------------------------------------------------------

## A mechanical switch: press and release.
func _ui_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(0.06)
	_noise(rng, buf, 0.0, 0.02, 3500.0, 3500.0, FILTER_BP, 0.4, 0.0003, 0.0025, 1.0)
	_noise(rng, buf, 0.018, 0.02, 2800.0, 2800.0, FILTER_BP, 0.4, 0.0003, 0.002, 0.5)
	_tone(buf, 0.0, 1800.0, 1800.0, 1.0, 0.0005, 0.006, 0.3)
	return buf


func _ui_hover(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(0.03)
	_noise(rng, buf, 0.0, 0.02, 5000.0, 5000.0, FILTER_BP, 0.5, 0.0003, 0.0015, 1.0)
	return buf


## A ship's bell struck twice ("ding-ding") somewhere across the harbour: a ship is ready.
## Low, soft-struck and muffled by distance so it sits under music as ambience.
func _ships_bell(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(2.8)
	for at: float in [0.0, 0.5]:
		_noise(rng, buf, at, 0.03, 1800.0, 1800.0, FILTER_BP, 0.6, 0.002, 0.004, 0.08)
		_modes(buf, at, 410.0, PackedFloat32Array([0.5, 1.0, 1.183, 1.506, 2.0, 2.514]),
			PackedFloat32Array([0.5, 0.6, 0.35, 0.18, 0.25, 0.06]),
			PackedFloat32Array([1.6, 1.1, 0.7, 0.45, 0.4, 0.2]), 1.0)
	_lowpass(buf, 1600.0)
	return _reverb(buf, 1.2, 1.4, 0.6, 0.35, 0.2)


## A bosun's call piped on a distant deck: the pipe swells up, holds with a gentle warble,
## and falls away. Islands taken. Lower, slower-attacked and washed in reverb so it reads as
## ambience under music rather than a whistle in the ear.
func _bosuns_call(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length: float = 1.5
	var buf: PackedFloat32Array = _buf(length)
	var phase: float = 0.0
	for i: int in buf.size():
		var t: float = float(i) / RATE
		var f: float = lerpf(820.0, 1250.0, smoothstep(0.0, 0.25, t))
		f += 18.0 * sin(TAU * 6.0 * t) * smoothstep(0.25, 0.4, t)
		f -= 350.0 * smoothstep(0.95, 1.35, t)
		phase += TAU * f / RATE
		var e: float = smoothstep(0.0, 0.18, t) * clampf((length - t) / 0.3, 0.0, 1.0)
		buf[i] += (sin(phase) + 0.08 * sin(2.0 * phase)) * e
	_noise(rng, buf, 0.0, length, 1300.0, 1000.0, FILTER_BP, 0.3, 0.15, 1000.0, 0.05)
	_lowpass(buf, 1800.0)
	return _reverb(buf, 1.2, 1.3, 0.6, 0.35, 0.2)


## The general alarm: an electric gong sounding "bong-bong-bong".
func _general_alarm(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buf(1.4)
	for k: int in 5:
		var at: float = k * 0.22
		_noise(rng, buf, at, 0.02, 3000.0, 3000.0, FILTER_BP, 0.6, 0.0003, 0.002, 0.25)
		_modes(buf, at, 440.0, PackedFloat32Array([1.0, 2.0, 2.76, 4.07]),
			PackedFloat32Array([0.7, 0.3, 0.25, 0.12]), PackedFloat32Array([0.18, 0.12, 0.09, 0.06]), 1.0)
	return buf


# --- Ambience ---------------------------------------------------------------

## Open sea, heard as a distant bed under the music: a low surge and slow, soft swells rolling
## in and out. No bright foam hiss or close lapping, and everything is darkened so it never
## competes with a soundtrack.
func _ocean_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length: float = 16.0
	var fade: float = 2.5
	var buf: PackedFloat32Array = _buf(length + fade)
	var total: float = length + fade
	_noise(rng, buf, 0.0, total, 120.0, 120.0, FILTER_LP, 0.9, 0.0, 100000.0, 0.9, 0.4, 0.3)
	for k: int in 7:
		var dur: float = rng.randf_range(3.5, 5.5)
		var at: float = rng.randf_range(0.0, total - 1.5)
		var a: float = rng.randf_range(0.35, 0.65)
		if k % 2 == 0:
			_noise(rng, buf, at, dur, 250.0, 900.0, FILTER_BP, 0.9, dur * 0.45, dur * 0.3, a, 0.3, 3.0)
		else:
			_noise(rng, buf, at, dur, 900.0, 300.0, FILTER_BP, 0.9, dur * 0.3, dur * 0.35, a, 0.3, 3.0)
	_lowpass(buf, 900.0)
	return _loop(buf, length, fade)


## Storm: wind howling through the rigging (a resonant band wandering in pitch), the broad
## rush of the gale, and rain.
func _wind_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var length: float = 10.0
	var fade: float = 1.5
	var buf: PackedFloat32Array = _buf(length + fade)
	var low: float = 0.0
	var band: float = 0.0
	var span: int = int(RATE / 0.3)
	var wa: float = rng.randf_range(-0.8, 0.8)
	var wb: float = rng.randf_range(-0.8, 0.8)
	var ga: float = rng.randf()
	var gb: float = rng.randf()
	for i: int in buf.size():
		if i % span == 0:
			wa = wb
			wb = rng.randf_range(-0.8, 0.8)
			ga = gb
			gb = rng.randf()
		var s: float = smoothstep(0.0, 1.0, float(i % span) / span)
		var cut: float = 450.0 * pow(2.0, lerpf(wa, wb, s))
		var f: float = 2.0 * sin(PI * cut / RATE)
		var n: float = rng.randf() * 2.0 - 1.0
		var high: float = n - low - 0.25 * band
		band += f * high
		low += f * band
		buf[i] += band * 0.12 * (0.4 + 0.6 * lerpf(ga, gb, s))
	var total: float = length + fade
	_noise(rng, buf, 0.0, total, 600.0, 600.0, FILTER_LP, 0.9, 0.0, 100000.0, 0.6, 0.6, 0.4)
	_noise(rng, buf, 0.0, total, 4000.0, 4000.0, FILTER_HP, 0.9, 0.0, 100000.0, 0.15, 0.3, 3.0)
	_grains(rng, buf, 0.0, total, 400, 2000.0, 6000.0, 1.0, 0.003, 0.02, 0.08)
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
	# Fade the last few milliseconds so a one-shot never ends on a click.
	var tail: int = mini(buf.size(), int(0.01 * RATE)) if not loop else 0
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i: int in buf.size():
		var g: float = gain
		var left: int = buf.size() - i
		if left < tail:
			g *= float(left) / tail
		bytes.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
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
