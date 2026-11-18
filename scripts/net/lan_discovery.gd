class_name LanDiscovery
extends Node
## Finds LAN games without typing an address. A hosting machine broadcasts a small UDP
## beacon once a second on DISCOVERY_PORT; the start menu listens on that port and lists
## every game it heard from in the last few seconds. The beacon only reaches the local
## network (broadcast packets are not routed), and joining still goes through the normal
## ENet connection on the game port.

signal games_changed

const DISCOVERY_PORT: int = 24568
const MAGIC: String = "FLEETFALL"
const BEACON_INTERVAL: float = 1.0
## A game that has gone quiet for this long drops off the list.
const FORGET_AFTER: float = 3.5
const MAX_BEACON_BYTES: int = 512

## Called once per beacon on the host; returns the Dictionary to advertise, or {} to skip.
var beacon_source: Callable = Callable()

var _sender: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _beacon_cd: float = 0.0
var _clock: float = 0.0
## "address:port" -> {"address", "port", "name", "players", "seats", "open", "protocol", "seen"}
var _games: Dictionary[String, Dictionary] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_advertising() -> bool:
	return _sender != null


func is_browsing() -> bool:
	return _listener != null


func start_advertising() -> void:
	if _sender != null:
		return
	_sender = PacketPeerUDP.new()
	_sender.set_broadcast_enabled(true)
	_beacon_cd = 0.0


func stop_advertising() -> void:
	if _sender != null:
		_sender.close()
	_sender = null


## Returns "" or why the menu cannot listen (another Fleetfall on this PC may hold the port).
func start_browsing() -> String:
	if _listener != null:
		return ""
	var listener: PacketPeerUDP = PacketPeerUDP.new()
	var err: Error = listener.bind(DISCOVERY_PORT, "*")
	if err != OK:
		return "Can't look for LAN games (UDP port %d is busy: %s)" % [DISCOVERY_PORT, error_string(err)]
	_listener = listener
	return ""


func stop_browsing() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	if not _games.is_empty():
		_games.clear()
		games_changed.emit()


## Games heard recently, in the order they were first heard.
func games() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in _games:
		result.append(_games[key])
	return result


func _process(delta: float) -> void:
	_clock += delta
	if _sender != null:
		_beacon_cd -= delta
		if _beacon_cd <= 0.0:
			_beacon_cd = BEACON_INTERVAL
			_send_beacon()
	if _listener != null:
		_receive()
		_expire()


func _send_beacon() -> void:
	if not beacon_source.is_valid():
		return
	var info: Dictionary = beacon_source.call()
	if info.is_empty():
		return
	info["m"] = MAGIC
	var bytes: PackedByteArray = JSON.stringify(info).to_utf8_buffer()
	for target: String in broadcast_targets():
		_sender.set_dest_address(target, DISCOVERY_PORT)
		_sender.put_packet(bytes)


## The limited broadcast address plus each local network's /24 broadcast (Windows sends
## 255.255.255.255 out of one adapter only), and loopback so a second copy on this PC sees it.
static func broadcast_targets() -> PackedStringArray:
	var targets: PackedStringArray = PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for address: String in NetSession.lan_addresses():
		var parts: PackedStringArray = address.split(".")
		var subnet: String = "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not targets.has(subnet):
			targets.append(subnet)
	return targets


func _receive() -> void:
	var changed: bool = false
	var budget: int = 64
	while _listener.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var bytes: PackedByteArray = _listener.get_packet()
		var address: String = _listener.get_packet_ip()
		if bytes.size() > MAX_BEACON_BYTES or address == "":
			continue
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not (parsed is Dictionary):
			continue
		var info: Dictionary = parsed
		if String(info.get("m", "")) != MAGIC:
			continue
		var port: int = int(info.get("port", 0))
		if port < 1024 or port > 65535:
			continue
		# The same host is heard on several addresses (loopback and LAN): keep one entry,
		# preferring the LAN address so the listing reads the same on every machine.
		var key: String = "%s|%d" % [String(info.get("id", address)), port]
		var entry: Dictionary = _games.get(key, {})
		var keep_address: String = String(entry.get("address", ""))
		if keep_address == "" or keep_address.begins_with("127."):
			keep_address = address
		var fresh: Dictionary = {
			"address": keep_address, "port": port,
			"name": NetSession.clean_name(String(info.get("name", "")), "Fleetfall host"),
			"players": clampi(int(info.get("players", 0)), 0, Layers.MAX_TEAMS),
			"seats": clampi(int(info.get("seats", 0)), 0, Layers.MAX_TEAMS),
			"protocol": int(info.get("protocol", 0)),
			"seen": _clock,
		}
		var shown: Dictionary = entry.duplicate()
		shown.erase("seen")
		var shown_fresh: Dictionary = fresh.duplicate()
		shown_fresh.erase("seen")
		if shown != shown_fresh:
			changed = true
		_games[key] = fresh
	if changed:
		games_changed.emit()


func _expire() -> void:
	var gone: Array[String] = []
	for key: String in _games:
		if _clock - float(_games[key]["seen"]) > FORGET_AFTER:
			gone.append(key)
	for key: String in gone:
		_games.erase(key)
	if not gone.is_empty():
		games_changed.emit()
