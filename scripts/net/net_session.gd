class_name NetSession
extends Node
## LAN multiplayer session, registered as the autoload "Net" so it survives scene changes
## and sits at the same node path on every machine (RPCs need that).
##
## The host is the only machine that runs the game rules. Clients send it their commands
## (Match.execute_command validates them against the sender's side) and draw the
## full-state snapshots it broadcasts (see NetSync). Up to four sides; each human player
## has a side of their own, sides with the same team number are allies, empty seats can
## be filled with AI.

signal lobby_changed
signal status_changed(text: String)

enum Mode { OFFLINE, HOST, CLIENT }
enum Slot { OPEN, CLOSED, AI, HUMAN }

const DEFAULT_PORT: int = 24567
## Bumped whenever the messages change, so mismatched builds refuse each other politely.
const PROTOCOL: int = 1
const MAX_NAME_LENGTH: int = 16
## The host sends a snapshot every this many physics frames (15 per second at 60 Hz).
const SNAPSHOT_EVERY: int = 4
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"

var mode: Mode = Mode.OFFLINE
var player_name: String = "Admiral"
var port: int = DEFAULT_PORT
## Lobby seats, owned by the host and mirrored to the clients. Each is
## {"kind": Slot, "peer": int, "name": String, "team": int (1-4)}.
var slots: Array[Dictionary] = []
var map_size: int = MapConfig.Size.MEDIUM
var difficulty: int = GameSettings.Difficulty.MEDIUM
var in_match: bool = false
## Host: the seed of the next match (0 = random). Used by tests.
var next_seed: int = 0
## Why the last session ended, for the menu to show. The menu clears it.
var last_error: String = ""
## Client: snapshots applied so far, and the last one (used by tests).
var snapshots_applied: int = 0
var last_snapshot: Dictionary = {}

var _match_config: Dictionary = {}
var _match: Match = null
## Host: side played by each connected peer in the running match.
var _peer_side: Dictionary[int, int] = {}
var _frames: int = 0
## Broadcasts this game to the LAN while hosting; the start menu browses with it.
var discovery: LanDiscovery = null
var _session_id: String = ""
var _leaving: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_reset_slots()
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	discovery.beacon_source = _beacon
	add_child(discovery)


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func my_peer_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


static func clean_name(text: String, fallback: String) -> String:
	var cleaned: String = text.strip_edges().replace("\n", " ").left(MAX_NAME_LENGTH)
	return cleaned if cleaned != "" else fallback


## The LAN addresses other players can join (IPv4, no loopback or link-local).
static func lan_addresses() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for address: String in IP.get_local_addresses():
		if address.count(".") != 3 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if not result.has(address):
			result.append(address)
	return result


# --- Starting and leaving ---------------------------------------------------

## Opens a game on `p_port`. Returns "" or the reason it failed.
func host_game(p_port: int = DEFAULT_PORT) -> String:
	leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(p_port, Layers.MAX_TEAMS - 1)
	if err != OK:
		return "Could not open UDP port %d (%s)" % [p_port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	port = p_port
	_reset_slots()
	slots[0] = {"kind": Slot.HUMAN, "peer": 1, "name": player_name, "team": 1}
	_session_id = "%08x" % (randi() & 0x7fffffff)
	discovery.start_advertising()
	_broadcast_lobby()
	return ""


## Starts connecting to a host. Returns "" or the reason it failed at once; a later
## failure ends the session with last_error set.
func join_game(address: String, p_port: int = DEFAULT_PORT) -> String:
	leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address.strip_edges(), p_port)
	if err != OK:
		return "Could not connect to %s:%d (%s)" % [address, p_port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	port = p_port
	status_changed.emit("Connecting to %s:%d ..." % [address, p_port])
	return ""


## What the LAN beacon says about this game: only while hosting and still in the lobby.
func _beacon() -> Dictionary:
	if not is_host() or in_match:
		return {}
	var open: int = 0
	for slot: Dictionary in slots:
		if int(slot["kind"]) == Slot.OPEN:
			open += 1
	return {"id": _session_id, "name": player_name, "port": port, "protocol": PROTOCOL,
		"players": filled_slots().size(), "seats": open}


## Closes the session (no-op offline). Other machines notice the disconnect.
func leave() -> void:
	if mode == Mode.OFFLINE:
		return
	_leaving = true
	discovery.stop_advertising()
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_leaving = false
	mode = Mode.OFFLINE
	in_match = false
	_match_config = {}
	_match = null
	_peer_side.clear()
	snapshots_applied = 0
	last_snapshot = {}
	_reset_slots()


func _end_session(reason: String) -> void:
	last_error = reason
	leave()
	get_tree().change_scene_to_file(GameSettings.MENU_SCENE)


# --- Lobby ------------------------------------------------------------------

func _reset_slots() -> void:
	slots.clear()
	for i: int in Layers.MAX_TEAMS:
		slots.append({"kind": Slot.OPEN, "peer": 0, "name": "", "team": i + 1})


## Index of the seat held by `peer`, or -1.
func slot_of(peer: int) -> int:
	for i: int in slots.size():
		if int(slots[i]["kind"]) == Slot.HUMAN and int(slots[i]["peer"]) == peer:
			return i
	return -1


func set_slot_kind(index: int, kind: Slot) -> void:
	if not is_host() or in_match or index <= 0 or index >= slots.size():
		return
	var current: int = int(slots[index]["kind"])
	if current == Slot.HUMAN or kind == Slot.HUMAN:
		return
	slots[index]["kind"] = kind
	slots[index]["name"] = "Computer" if kind == Slot.AI else ""
	_broadcast_lobby()


func set_slot_team(index: int, team: int) -> void:
	if not is_host() or in_match or index < 0 or index >= slots.size():
		return
	slots[index]["team"] = clampi(team, 1, Layers.MAX_TEAMS)
	_broadcast_lobby()


## Any player may pick the team of their own seat.
func request_team(team: int) -> void:
	if is_host():
		set_slot_team(0, team)
	elif mode == Mode.CLIENT:
		_rpc_request_team.rpc_id(1, team)


func set_map_size(size: int) -> void:
	if is_host() and not in_match:
		map_size = clampi(size, 0, MapConfig.Size.size() - 1)
		_broadcast_lobby()


func set_difficulty(level: int) -> void:
	if is_host() and not in_match:
		difficulty = clampi(level, 0, GameSettings.Difficulty.size() - 1)
		_broadcast_lobby()


## Seats that will play: humans and AI.
func filled_slots() -> Array[int]:
	var result: Array[int] = []
	for i: int in slots.size():
		var kind: int = int(slots[i]["kind"])
		if kind == Slot.HUMAN or kind == Slot.AI:
			result.append(i)
	return result


## "" if the host may start, otherwise what is missing.
func start_problem() -> String:
	var filled: Array[int] = filled_slots()
	if filled.size() < 2:
		return "Need at least two players (open a seat to AI or wait for someone to join)"
	var teams: Array[int] = []
	for i: int in filled:
		if not teams.has(int(slots[i]["team"])):
			teams.append(int(slots[i]["team"]))
	if teams.size() < 2:
		return "Everyone is on the same team - put someone on another team"
	return ""


func _lobby_state() -> Dictionary:
	return {"slots": slots, "size": map_size, "difficulty": difficulty}


func _broadcast_lobby() -> void:
	if is_host():
		_rpc_lobby.rpc(_lobby_state())
	lobby_changed.emit()


## Host: starts the match on every machine.
func start_match() -> String:
	if not is_host() or in_match:
		return "Only the host can start"
	var problem: String = start_problem()
	if problem != "":
		return problem
	var seed_value: int = next_seed
	if seed_value <= 0:
		var seeder: RandomNumberGenerator = RandomNumberGenerator.new()
		seeder.randomize()
		seed_value = seeder.randi_range(1, 999999)
	var ai: Array[bool] = []
	var alliance: Array[int] = []
	var names: Array[String] = []
	var peers: Array[int] = []
	var computers: int = 0
	for i: int in filled_slots():
		var slot: Dictionary = slots[i]
		var is_ai: bool = int(slot["kind"]) == Slot.AI
		if is_ai:
			computers += 1
		ai.append(is_ai)
		alliance.append(int(slot["team"]))
		names.append("Computer %d" % computers if is_ai else String(slot["name"]))
		peers.append(0 if is_ai else int(slot["peer"]))
	var config: Dictionary = {"seed": seed_value, "size": map_size, "difficulty": difficulty,
		"ai": ai, "alliance": alliance, "names": names, "peers": peers}
	_rpc_start.rpc(config)
	_begin(config)
	return ""


func _begin(config: Dictionary) -> void:
	_match_config = config
	in_match = true
	snapshots_applied = 0
	_frames = 0
	if is_host():
		multiplayer.multiplayer_peer.refuse_new_connections = true
	GameSettings.map_size = clampi(int(config.get("size", 1)), 0, MapConfig.Size.size() - 1) as MapConfig.Size
	GameSettings.ai_difficulty = clampi(int(config.get("difficulty", 2)), 0, 2) as GameSettings.Difficulty
	get_tree().change_scene_to_file(GameSettings.MATCH_SCENE)


## Host, after a match: everybody goes back to the lobby.
func return_to_lobby() -> void:
	if not is_host():
		return
	_rpc_to_lobby.rpc()
	_enter_lobby()


func _enter_lobby() -> void:
	in_match = false
	_match_config = {}
	_match = null
	_peer_side.clear()
	if is_host():
		multiplayer.multiplayer_peer.refuse_new_connections = false
	get_tree().change_scene_to_file(LOBBY_SCENE)
	if is_host():
		_broadcast_lobby.call_deferred()


# --- Match ------------------------------------------------------------------

## Called by every Match as it starts. Returns false offline (the Match sets itself up as
## usual); in a network game it receives the sides, alliances and seed from the lobby.
func configure_match(m: Match) -> bool:
	if mode == Mode.OFFLINE or _match_config.is_empty():
		return false
	var c: Dictionary = _match_config
	var ai: Array = c.get("ai", [])
	var peers: Array = c.get("peers", [])
	var alliance: Array = c.get("alliance", [])
	var names: Array = c.get("names", [])
	var count: int = clampi(peers.size(), 2, Layers.MAX_TEAMS)
	var me: int = my_peer_id()
	var control: Array[int] = []
	var allies: Array[int] = []
	var side_names: Array[String] = []
	var levels: Array[int] = []
	var local: int = -1
	_peer_side.clear()
	for i: int in count:
		var is_ai: bool = i < ai.size() and bool(ai[i])
		var peer: int = int(peers[i]) if i < peers.size() else 0
		control.append(Match.ControlType.AI if is_ai and is_host() else Match.ControlType.NONE)
		allies.append(int(alliance[i]) if i < alliance.size() else 100 + i)
		side_names.append(String(names[i]) if i < names.size() else "Side %d" % (i + 1))
		levels.append(int(c.get("difficulty", 2)))
		if peer > 0 and not is_ai:
			_peer_side[peer] = i
			if peer == me:
				local = i
	if local >= 0:
		control[local] = Match.ControlType.HUMAN
	m.map_seed = int(c.get("seed", 1))
	m.team_control = control
	m.alliance = allies
	m.side_names = side_names
	m.ai_difficulty = levels
	m.net_local_team = local
	m.end_when_local_out = false
	m.replica = mode == Mode.CLIENT
	m.record_effects = mode == Mode.HOST
	if m.replica:
		m.command_sink = _send_command
	_match = m
	m.tree_exiting.connect(_on_match_exiting.bind(m))
	return true


func current_match() -> Match:
	return _match


func _on_match_exiting(m: Match) -> void:
	if _match == m:
		_match = null


func _physics_process(_delta: float) -> void:
	if not is_host() or not in_match or _match == null or not _match.is_node_ready():
		return
	_frames += 1
	if _frames % SNAPSHOT_EVERY == 0 and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(NetSync.build(_match))
	elif _frames % SNAPSHOT_EVERY == 0:
		_match.take_effect_log()


func _send_command(cmd: Dictionary) -> void:
	if mode == Mode.CLIENT:
		_rpc_command.rpc_id(1, cmd)


## Host: a message for every player (and the host's own screen).
func announce(text: String) -> void:
	if not is_host():
		return
	# Per peer, skipping any that are already disconnecting (two players leaving at once).
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for id: int in multiplayer.get_peers():
		var link: ENetPacketPeer = enet.get_peer(id) if enet != null else null
		if link != null and link.get_state() == ENetPacketPeer.STATE_CONNECTED:
			_rpc_notice.rpc_id(id, text)
	_show_notice(text)


func _show_notice(text: String) -> void:
	if _match != null and _match.hud != null:
		_match.hud.notify(text)


# --- Connection events ------------------------------------------------------

func _on_peer_connected(_peer: int) -> void:
	pass # The newcomer introduces itself with _rpc_hello.


func _on_peer_disconnected(peer: int) -> void:
	if not is_host():
		return
	var index: int = slot_of(peer)
	var who: String = String(slots[index]["name"]) if index >= 0 else "A player"
	if index >= 0:
		slots[index] = {"kind": Slot.OPEN, "peer": 0, "name": "", "team": int(slots[index]["team"])}
	if in_match:
		var side: int = int(_peer_side.get(peer, -1))
		_peer_side.erase(peer)
		if side >= 0 and _match != null and not _match.is_over and not _match.eliminated[side]:
			_match.give_side_to_ai(side)
			announce("%s left the game - the computer takes over their fleet" % who)
	else:
		_broadcast_lobby()


func _on_connected_to_server() -> void:
	status_changed.emit("Connected - joining the lobby ...")
	_rpc_hello.rpc_id(1, PROTOCOL, player_name)


func _on_connection_failed() -> void:
	_end_session("Could not reach the host. Check the address, and that the host's firewall allows Fleetfall (UDP port %d)." % port)


func _on_server_disconnected() -> void:
	if not _leaving:
		_end_session("The host closed the game")


# --- RPCs -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(protocol: int, who: String) -> void:
	if not is_host():
		return
	var peer: int = multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_refuse(peer, "The host runs a different version of Fleetfall")
		return
	if in_match:
		_refuse(peer, "That game has already started")
		return
	if slot_of(peer) >= 0:
		return
	for i: int in slots.size():
		if int(slots[i]["kind"]) == Slot.OPEN:
			slots[i] = {"kind": Slot.HUMAN, "peer": peer, "name": clean_name(who, "Player %d" % (i + 1)),
				"team": int(slots[i]["team"])}
			_broadcast_lobby()
			return
	_refuse(peer, "The lobby is full")


func _refuse(peer: int, reason: String) -> void:
	_rpc_refused.rpc_id(peer, reason)
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_host() and enet == multiplayer.multiplayer_peer:
			enet.disconnect_peer(peer))


@rpc("authority", "call_remote", "reliable")
func _rpc_refused(reason: String) -> void:
	_end_session(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(state: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	var incoming: Array = state.get("slots", [])
	slots.clear()
	for entry: Variant in incoming:
		if entry is Dictionary:
			slots.append(entry as Dictionary)
	map_size = int(state.get("size", MapConfig.Size.MEDIUM))
	difficulty = int(state.get("difficulty", GameSettings.Difficulty.MEDIUM))
	if not in_match and get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path != LOBBY_SCENE:
		get_tree().change_scene_to_file(LOBBY_SCENE)
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_team(team: int) -> void:
	if not is_host():
		return
	var index: int = slot_of(multiplayer.get_remote_sender_id())
	if index >= 0:
		set_slot_team(index, team)


@rpc("authority", "call_remote", "reliable")
func _rpc_start(config: Dictionary) -> void:
	if mode == Mode.CLIENT:
		_begin(config)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: Dictionary) -> void:
	if not is_host() or not in_match or _match == null:
		return
	var peer: int = multiplayer.get_remote_sender_id()
	if not _peer_side.has(peer):
		return
	var note: String = _match.execute_command(_peer_side[peer], cmd)
	if note != "":
		_rpc_notice.rpc_id(peer, note)


## Reliable on a channel of its own: snapshots span several UDP packets, and on a LAN a
## resend costs little, while commands and notices never queue behind them.
@rpc("authority", "call_remote", "reliable", 1)
func _rpc_snapshot(data: Dictionary) -> void:
	if mode != Mode.CLIENT or _match == null or not _match.is_node_ready():
		return
	NetSync.apply(_match, data)
	snapshots_applied += 1
	last_snapshot = data


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(text: String) -> void:
	_show_notice(text)


@rpc("authority", "call_remote", "reliable")
func _rpc_to_lobby() -> void:
	if mode == Mode.CLIENT:
		_enter_lobby()
