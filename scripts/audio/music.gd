extends Node
## Soundtrack playlist (autoload `Music`). Finds every track dropped anywhere under
## `res://assets/music/` (`.ogg`, `.mp3` or `.wav`, subfolders included) and, each time a
## track ends, picks another one at random (never the same one twice in a row). Plays on the
## "Music" bus (`AudioMix`) and keeps playing across scene changes. Cosmetic only: it never
## touches `Match.rng` or game state. Nothing plays headless (tests, dedicated hosts).

const FOLDER: String = "res://assets/music/"
const EXTENSIONS: PackedStringArray = ["ogg", "mp3", "wav"]
## Silence between two tracks, seconds.
const GAP: float = 2.0

## Title and artist of every soundtrack piece, by file name (without extension). Shown on
## the Credits page and as "Now playing". A file missing here is credited by its file name.
const TRACK_CREDITS: Dictionary[String, Array] = {
	"alex_besss-pirate-455262": ["Pirate", "Alex_Besss"],
	"atlasaudio-battle-drums-636771": ["Battle Drums", "AtlasAudio"],
	"audiodollar-pirate-music-pirate-331490": ["Pirate Music Pirate", "AudioDollar"],
	"juliush-traditional-german-imperial-era-cavalry-march-601125": [
		"Traditional German Imperial Era Cavalry March", "JuliusH"],
	"music_for_videos-pirates-163389": ["Pirates", "Music_For_Videos"],
	"paulyudin-battle-military-157972": ["Battle Military", "PaulYudin"],
	"starostin-army-military-war-music-261862": ["Army Military War Music", "STAROSTIN"],
	"tatamusic-army-military-war-music-590380": ["Army Military War Music", "Tatamusic"],
}

signal track_changed(title: String, artist: String)

var enabled: bool = false
var tracks: PackedStringArray = []
var current: String = ""
var _player: AudioStreamPlayer = null
var _wait: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	AudioMix.setup()
	tracks = find_tracks()
	if tracks.is_empty():
		return
	enabled = true
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.bus = AudioMix.MUSIC
	_player.finished.connect(func() -> void: _wait = GAP)
	add_child(_player)
	_play_next()


## Every playable track under `FOLDER` (recursively), sorted. Uses
## `ResourceLoader.list_directory` so it also works in exported builds, where the folder
## holds imported resources rather than the original files.
static func find_tracks(folder: String = FOLDER) -> PackedStringArray:
	var found: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for entry: String in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			found.append_array(find_tracks(folder + entry))
		elif entry.get_extension().to_lower() in EXTENSIONS:
			found.append(folder + entry)
	found.sort()
	return found


## [title, artist] for a track path, from `TRACK_CREDITS` or else the file name.
static func credit_for(path: String) -> Array[String]:
	var stem: String = path.get_file().get_basename()
	if TRACK_CREDITS.has(stem):
		var entry: Array = TRACK_CREDITS[stem]
		return [String(entry[0]), String(entry[1])]
	return [stem.replace("_", " ").replace("-", " ").capitalize(), "Unknown artist"]


## "Title - Artist" of the track playing now, or "" when none is.
func now_playing() -> String:
	if not enabled or current == "":
		return ""
	var credit: Array[String] = credit_for(current)
	return "%s - %s" % [credit[0], credit[1]]


## Skips to another random track.
func skip() -> void:
	if enabled:
		_play_next()


func _process(delta: float) -> void:
	if not enabled or _wait <= 0.0:
		return
	_wait -= delta
	if _wait <= 0.0:
		_play_next()


## A random track, never the one that just played (unless it is the only one).
func pick_next(last: String) -> String:
	if tracks.size() == 1:
		return tracks[0]
	var choice: String = last
	while choice == last:
		choice = tracks[_rng.randi_range(0, tracks.size() - 1)]
	return choice


func _play_next() -> void:
	_wait = 0.0
	current = pick_next(current)
	var stream: AudioStream = load(current) as AudioStream
	if stream == null:
		_wait = GAP
		return
	# A track that loops on import would never end; play each once.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_player.stream = stream
	_player.play()
	var credit: Array[String] = credit_for(current)
	track_changed.emit(credit[0], credit[1])
