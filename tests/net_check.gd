extends Node
## Multi-process LAN check over real ENet sockets on this machine. Start one host and N
## clients (each a separate Godot process):
##   godot --headless --path . res://tests/net_check.tscn -- --role=host --clients=2 --seconds=80
##   godot --headless --path . res://tests/net_check.tscn -- --role=client --name=Ann
## Host options: --port=N --seed=N --ai=K (extra AI seats) --coop (seat 2 allied with the host)
##   --rounds=N (after each round the host takes everybody back to the lobby and starts again)
## Client options: --port=N --name=S --quit-at=SECONDS (drop out mid-match) --seconds=N
##   --late=SECONDS (connect only after this long: joins the running match as a spectator)
##   --team=N (pick a team in the lobby) --rounds=N
## Client: --discover opens the start menu, waits for the host's game in its LAN list and
##   presses that row's Join button (no address typed).
## Either role: --via-menu goes through the real start menu (its --host / --join= command line)
##   instead of calling Net directly.
##
## A client builds a Destroyer, sails it, tries forged commands for other sides, and after
## every snapshot checks that its replica holds exactly the state the host sent. Both sides
## print a NETCHECK line per round.


func _ready() -> void:
	# The driver must outlive the scene changes (menu -> lobby -> match), so it hangs off the root.
	var driver: Driver = Driver.new()
	driver.name = "NetCheckDriver"
	get_tree().root.add_child.call_deferred(driver)


class Driver extends Node:
	var role: String = "client"
	var clients: int = 1
	var port: int = NetSession.DEFAULT_PORT + 7
	var seed_value: int = 3
	var extra_ai: int = 0
	var coop: bool = false
	var seconds: float = 80.0
	var quit_at: float = -1.0
	var rounds: int = 1
	var round_index: int = 0
	var want_team: int = 0
	var team_requested: bool = false
	var via_menu: bool = false
	var discover: bool = false
	var discovered: bool = false
	var started: bool = false
	var wall: float = 0.0
	var lobby_since: float = -1.0
	# Client progress (reset every round).
	var phase: int = 0
	var seen_snapshots: int = 0
	var last_sim: float = -1.0
	var checked: int = 0
	var mismatches: int = 0
	var first_diff: String = ""
	var built: bool = false
	var moved: bool = false
	var move_ship: int = 0
	var move_target: Vector2 = Vector2.ZERO
	var move_start_dist: float = 0.0
	var move_time: float = 0.0
	var forged_sent: bool = false
	var max_bytes: int = 0
	var in_match: bool = false
	var reported_match: int = 0
	var shot_path: String = ""
	var shot_at: float = 45.0
	var shot_taken: bool = false
	var lobby_shot: String = ""
	var lobby_wait: float = -1.0
	var late: float = -1.0
	var player_name: String = "Client"

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		var player: String = "Client"
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--role="):
				role = arg.trim_prefix("--role=")
			elif arg.begins_with("--clients="):
				clients = int(arg.trim_prefix("--clients="))
			elif arg.begins_with("--port="):
				port = int(arg.trim_prefix("--port="))
			elif arg.begins_with("--seed="):
				seed_value = int(arg.trim_prefix("--seed="))
			elif arg.begins_with("--ai="):
				extra_ai = int(arg.trim_prefix("--ai="))
			elif arg == "--coop":
				coop = true
			elif arg == "--via-menu":
				via_menu = true
			elif arg == "--discover":
				discover = true
			elif arg.begins_with("--rounds="):
				rounds = maxi(1, int(arg.trim_prefix("--rounds=")))
			elif arg.begins_with("--team="):
				want_team = int(arg.trim_prefix("--team="))
			elif arg.begins_with("--seconds="):
				seconds = float(arg.trim_prefix("--seconds="))
			elif arg.begins_with("--quit-at="):
				quit_at = float(arg.trim_prefix("--quit-at="))
			elif arg.begins_with("--shot="):
				shot_path = arg.trim_prefix("--shot=")
			elif arg.begins_with("--shot-at="):
				shot_at = float(arg.trim_prefix("--shot-at="))
			elif arg.begins_with("--lobby-shot="):
				lobby_shot = arg.trim_prefix("--lobby-shot=")
			elif arg.begins_with("--name="):
				player = arg.trim_prefix("--name=")
			elif arg.begins_with("--late="):
				late = float(arg.trim_prefix("--late="))
		if role == "menu":
			get_tree().change_scene_to_file(GameSettings.MENU_SCENE)
			return
		if discover:
			Net.player_name = player
			get_tree().change_scene_to_file(GameSettings.MENU_SCENE)
			print("NETCHECK client %s browsing the LAN" % player)
			return
		if via_menu:
			# The menu reads --host / --join= / --name= / --port= itself, once, at launch.
			Net.port = port
			get_tree().change_scene_to_file(GameSettings.MENU_SCENE)
			print("NETCHECK %s via the start menu" % role)
			if role == "host":
				Net.next_seed = seed_value
			return
		GameSettings.menu_shown = true
		if role == "host":
			Net.player_name = "Host"
			Net.next_seed = seed_value
			var problem: String = Net.host_game(port)
			print("NETCHECK host listening on %d %s" % [port, problem])
			get_tree().change_scene_to_file(NetSession.LOBBY_SCENE)
		else:
			Net.player_name = player
			player_name = player
			if late > 0.0:
				print("NETCHECK client %s joins late, at %.0fs" % [player, late])
				return
			var problem: String = Net.join_game("127.0.0.1", port)
			print("NETCHECK client %s joining %s" % [player, problem])

	func _process(delta: float) -> void:
		wall += delta
		if wall > (seconds + 30.0) * rounds * 3.0 + 60.0:
			print("NETCHECK %s TIMEOUT round=%d phase=%d" % [role, round_index, phase])
			get_tree().quit(2)
			return
		if role == "menu":
			if wall > 2.0:
				get_viewport().get_texture().get_image().save_png(shot_path)
				get_tree().quit(0)
			return
		var m: Match = Net.current_match()
		if shot_path != "" and not shot_taken and m != null and m.is_node_ready() and m.sim_time >= shot_at:
			shot_taken = true
			get_viewport().get_texture().get_image().save_png(shot_path)
			print("NETCHECK %s screenshot %s" % [role, shot_path])
		if role == "host":
			_host_step()
		else:
			_client_step()

	func _humans() -> int:
		var count: int = 0
		for slot: Dictionary in Net.slots:
			if int(slot["kind"]) == NetSession.Slot.HUMAN:
				count += 1
		return count

	func _in_lobby_scene() -> bool:
		var scene: Node = get_tree().current_scene
		return scene != null and scene.scene_file_path == NetSession.LOBBY_SCENE

	func _host_step() -> void:
		if not started:
			if not Net.is_host() or not _in_lobby_scene():
				lobby_since = -1.0
				return
			if lobby_since < 0.0:
				lobby_since = wall
				if round_index == 0:
					Net.set_map_size(MapConfig.Size.SMALL)
					Net.set_difficulty(GameSettings.Difficulty.HARD)
			# Give the clients a moment once everyone is in (team picks arrive as RPCs).
			if _humans() != clients + 1:
				lobby_since = wall
				return
			if wall < lobby_since + 2.0:
				return
			if lobby_shot != "":
				if lobby_wait < 0.0:
					lobby_wait = wall
					_fill_lobby()
					return
				if wall < lobby_wait + 2.0:
					return
				get_viewport().get_texture().get_image().save_png(lobby_shot)
				lobby_shot = ""
			_fill_lobby()
			var problem: String = Net.start_match()
			print("NETCHECK host round %d start %s" % [round_index + 1, problem])
			started = problem == ""
			return
		_host_report()

	func _fill_lobby() -> void:
		var have: int = 0
		for slot: Dictionary in Net.slots:
			if int(slot["kind"]) == NetSession.Slot.AI:
				have += 1
		for k: int in maxi(0, extra_ai - have):
			for i: int in Net.slots.size():
				if int(Net.slots[i]["kind"]) == NetSession.Slot.OPEN:
					Net.set_slot_kind(i, NetSession.Slot.AI)
					break
		if coop:
			Net.set_slot_team(1, 1)

	func _host_report() -> void:
		var m: Match = Net.current_match()
		if m == null or not m.is_node_ready():
			return
		if m.sim_time >= seconds:
			var per_side: Array[int] = []
			for team: int in m.team_count:
				per_side.append(m.ships_of(team, false).size())
			print("NETCHECK HOST round=%d sides=%d control=%s alliance=%s names=%s ships=%s host_queue=%d elim=%s over=%s" % [
				round_index + 1, m.team_count, m.team_control, m.alliance, m.side_names, per_side,
				m.bases[0].shipyard.queue.size(), m.eliminated, m.is_over])
			round_index += 1
			if round_index < rounds:
				started = false
				Net.return_to_lobby()
				return
			Net.leave()
			get_tree().quit(0)

	## Finds the host's row in the menu's LAN list and presses its Join button.
	func _press_discovered_join() -> void:
		var menu: MainMenu = get_tree().current_scene as MainMenu
		if menu == null or menu._lan_list == null:
			return
		for row: Node in menu._lan_list.get_children():
			if row.is_queued_for_deletion():
				continue
			for child: Node in row.get_children():
				var button: Button = child as Button
				if button != null and not button.disabled:
					var games: Array[Dictionary] = Net.discovery.games()
					print("NETCHECK client %s found %s at %.1fs" % [Net.player_name, games, wall])
					discovered = true
					button.pressed.emit()
					return

	func _reset_round() -> void:
		phase = 0
		seen_snapshots = 0
		checked = 0
		mismatches = 0
		first_diff = ""
		built = false
		moved = false
		forged_sent = false
		max_bytes = 0

	func _client_step() -> void:
		if late > 0.0:
			if wall >= late:
				late = -1.0
				print("NETCHECK client %s joining late %s" % [player_name, Net.join_game("127.0.0.1", port)])
			return
		if discover and not discovered:
			_press_discovered_join()
			return
		if in_match and not Net.is_online():
			print("NETCHECK CLIENT %s host-gone notice=\"%s\" scene=%s last_sim_time=%.1f snapshots_seen=%d fps=%d wall=%.1f" % [
				Net.player_name, Net.last_error,
				get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "(loading)",
				last_sim, seen_snapshots, Engine.get_frames_per_second(), wall])
			get_tree().quit(0)
			return
		if want_team > 0 and not team_requested and Net.is_online() and not Net.in_match \
				and Net.slot_of(Net.my_peer_id()) >= 0:
			team_requested = true
			Net.request_team(want_team)
			print("NETCHECK client %s asks for team %d" % [Net.player_name, want_team])
		var m: Match = Net.current_match()
		if m != null:
			in_match = true
		if m == null or not m.is_node_ready() or Net.snapshots_applied == 0:
			return
		last_sim = m.sim_time
		if m.get_instance_id() == reported_match:
			return # This round is reported; wait for the host to start the next one.
		var me: int = m.local_team
		if Net.snapshots_applied != seen_snapshots:
			seen_snapshots = Net.snapshots_applied
			checked += 1
			max_bytes = maxi(max_bytes, var_to_bytes(Net.last_snapshot).size())
			var diff: Array[String] = NetSync.differences(Net.last_snapshot, NetSync.build(m))
			if not diff.is_empty():
				mismatches += 1
				if first_diff == "":
					first_diff = str(diff)
		if me < 0:
			_spectator_step(m)
			return
		var home: Shipyard = m.bases[me].shipyard
		if not forged_sent:
			forged_sent = true
			m.command({"type": "build", "yard": m.yards.find(home), "cls": int(ShipStats.ShipClass.DD)})
			# Forged: another side's yard and ships.
			var host_yard: int = m.yards.find(m.bases[0].shipyard)
			Net._send_command({"type": "build", "yard": host_yard, "cls": int(ShipStats.ShipClass.DD)})
			Net._send_command({"type": "upgrade", "yard": host_yard})
			Net._send_command({"type": "garbage", "yard": "x"})
		var own: Array[Ship] = m.ships_of(me, false)
		if not own.is_empty():
			built = true
		if phase == 0:
			var ready: Array[Ship] = m.ships_of(me)
			if not ready.is_empty():
				var ship: Ship = ready[0]
				var base: Vector2 = m.bases[me].position
				move_target = base + (m.map_data.center() - base).normalized() * 700.0
				move_ship = ship.net_id
				move_start_dist = ship.net_pos.distance_to(move_target)
				move_time = m.sim_time
				m.command({"type": "move", "ships": [ship.net_id], "x": move_target.x, "y": move_target.y})
				# Forged: order every ship that is not ours home.
				var others: Array[int] = []
				for other: Ship in m.ships:
					if other.team != me:
						others.append(other.net_id)
				Net._send_command({"type": "move", "ships": others, "x": 0.0, "y": 0.0})
				phase = 1
		elif phase == 1 and m.sim_time > move_time + 5.0:
			var ship: Ship = m.ships_by_id.get(move_ship) as Ship
			if ship != null:
				moved = ship.net_pos.distance_to(move_target) < move_start_dist - 60.0
			phase = 2
		var done: bool = m.sim_time >= seconds or (quit_at > 0.0 and m.sim_time >= quit_at)
		if done:
			print("NETCHECK CLIENT %s round=%d side=%d alliance=%s snapshots=%d checked=%d mismatches=%d first_diff=%s built=%s moved=%s max_bytes=%d ships_seen=%d" % [
				Net.player_name, round_index + 1, me, m.alliance, Net.snapshots_applied, checked, mismatches,
				first_diff, built, moved, max_bytes, m.ships.size()])
			round_index += 1
			if round_index < rounds and quit_at <= 0.0:
				reported_match = m.get_instance_id()
				_reset_round()
				return
			Net.leave()
			get_tree().quit(0)

	## A spectator (joined mid-match): mirrors the host, sees everything, and its commands do nothing.
	func _spectator_step(m: Match) -> void:
		if not forged_sent:
			forged_sent = true
			var host_yard: int = m.yards.find(m.bases[0].shipyard)
			m.command({"type": "build", "yard": host_yard, "cls": int(ShipStats.ShipClass.DD)})
			Net._send_command({"type": "sandbox"})
			move_time = m.sim_time
		if m.sim_time >= move_time + 15.0 or m.is_over:
			print("NETCHECK SPECTATOR %s side=%d spectator=%s watching=%s snapshots=%d checked=%d mismatches=%d first_diff=%s infinite=%s fog=%s ships_seen=%d" % [
				Net.player_name, m.local_team, m.spectator, Net.is_spectator(Net.my_peer_id()), Net.snapshots_applied,
				checked, mismatches, first_diff, m.economy.infinite, m.fog.visible if m.fog != null else false, m.ships.size()])
			Net.leave()
			get_tree().quit(0)
