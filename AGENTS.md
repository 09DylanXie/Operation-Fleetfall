# AGENTS.md — Operation: Fleetfall

This file provides context, architectural guidelines, and exact game balance rules for AI coding agents working on **Operation: Fleetfall**.

## 1. Project Overview
- **Title:** Operation: Fleetfall
- **Genre:** 2D WWII Naval Real-Time Strategy (RTS) — combining macro island territory control (*Empire at War*) with micro fleet positioning, line-of-sight cover, and ship class dynamics (*World of Warships*).
- **Engine:** Godot 4.7.2 (2D)
- **Language:** GDScript (strict static typing preferred)
- **Win Condition:** Destroy the enemy's Home Base.

---

## 2. Core Gameplay Rules & Invariants

When implementing gameplay systems, strictly enforce these design rules from the GDD:

### Fleet & Construction Rules
- **Fleet Cap:** **30 ships** per player at any time, **+3 for every Major island the player owns** (whether or not its shipyard is built; `Match.fleet_cap()`, `GameBalance.major_island_fleet_bonus`). Losing the island lowers the cap again (ships already afloat are kept).
- **Class limits:** `ShipStats.max_active` caps a class per side at once, counting ships afloat, on the slip and queued (Supercarrier `2`, Super Battleship `3`); `ShipStats.max_per_game` caps launches per side for the whole match (Supercarrier `4`, counted in `Match.ships_launched` by `record_launch()` when a ship launches; unfinished orders count too). `Match.class_limit_reason()` gives the refusal; the shop greys the card and the AI skips the class. `ships_launched` is in the NetSync snapshot (`built`).
- **Vulnerable Construction:** Ships under construction cannot defend themselves.

### Map, Vision & Environment
- **Procedural Archipelagos:** Map layout is procedurally generated each match.
- **Hard Cover (Line of Sight):** Islands physically block **both** spotting vision and artillery projectiles. Ships can use islands to break spotting or limit how many enemy turrets have a firing angle.
- **Fog of War:** The entire map is covered in fog. Ships only reveal enemies within their intrinsic spotting range (unless revealed by a penalty, such as a Submarine firing a torpedo).
- **Spotting Ranges (`spotting_range`):** `DD 720`, `CL`/`CA 360` (half a DD), `BB 240` (two thirds of a cruiser), `CV 80` (one third of a BB), `SS 0` (submarines spot nothing and are not vision sources). The local player's own low-vision ships still clear a small fog disc (`VisionSystem.OWN_SHIP_FOG_RADIUS`) so they are never drawn under fog; that disc reveals no enemies.
- **Round Map, 2-4 Sides:** `MapGenerator.generate(seed, cfg, base_radius, players)` makes a circular sea (`MapData.circular`) inscribed in a square of `MapConfig.size_for(players)`; Home Bases sit evenly round the rim and one wedge of islands is rotated once per player. Use `MapData.contains()` / `radius()` for bounds, never the bounding rectangle. Hand-built test maps may stay rectangular.
- **Sides & Alliances:** `Match.team_count` is 2 to `Layers.MAX_TEAMS` (4); `Match.alliance[team]` groups allies. Always test hostility with `Match.are_enemies()` / `Combatant.is_enemy_of()` and friendship with `are_allies()`, never `team != other`. Vision is shared inside an alliance. A side whose Home Base falls is `eliminated` (fleet sunk, islands neutral, `team_eliminated` signal); the match ends when one alliance is left (offline also when the local player's alliance is out).
- **Map Sizes:** `MapConfig.Size { SMALL, MEDIUM, LARGE }`, chosen in the start menu and held in `GameSettings.map_size`. Presets: `data/maps/small.tres`, `data/map_config.tres` (medium) and `data/maps/large.tres`, loaded with `GameData.map_config_for(size)`. Never mutate a cached config.
- **Range Rings:** Ships draw their weapon reach (gold guns, cyan torpedoes, violet aircraft) only for the local player's own ships: when selected, or for all of them while `Match.show_all_ranges` is on (top-bar switch / `R`). Enemy ranges are never drawn.
- **Dynamic Weather:** Roaming weather fronts (e.g., cyclones) drastically reduce the spotting range of any ships inside them.
- **Island Access Restrictions:**
  - **Shallow Water Islands (Minor):** Accessible **only** by Destroyers (`DD`) and Submarines (`SS`).
  - **Deep Water Islands (Major):** Required to construct Tier 3 Shipyards for capital ships (`BC`, `BB`, `SBB`, `CV`).

### Economy Loop
- **Tick Interval:** Resources are deposited automatically every **15.0 seconds** based on controlled nodes.
- **No Fuel Cost:** Ship movement has no resource cost.
- **Resource Rates (per 15s tick):**
  - **Home Base:** `+50 Gold`, `+20 Steel` (Core logistics & basic production)
  - **Minor Island (Captured):** `+30 Gold`, `+10 Steel` (Shallow-draft scouting control)
  - **Major Island (Captured):** `+20 Gold`, `+50 Steel` (Deep-water Tier 3 fleet construction)

### Combat & Damage Mechanics
- **Auto-Engagement:** Ships automatically fire at any enemy target that is **both spotted and within firing range** (and has unobstructed Line of Sight).
- **Player Priority Override:** Drag-select + right-click sets a priority target for selected units. Units prioritize that target while still strictly obeying spotting, LOS, and range rules.
- **Focus-Fire Armor Stripping:**
  - Base Armor provides a flat damage reduction percentage.
  - For every additional ship actively attacking the same armored target beyond the first, the target's effective armor is reduced by **5%** (minimum 0%).
  - *Formula:* `effective_armor = max(0.0, base_armor - 0.05 * max(0, active_attackers - 1))`
  - *Example:* A Battleship (`25%` base armor) targeted by 3 Cruisers has `25% - (2 * 5%) = 15%` effective armor.
- **Artillery Projectiles:**
  - Travel in straight lines with **no homing**.
  - Blocked on collision with islands.
  - Shell velocity scales with gun caliber (`DD` shells = baseline speed; `BB` shells = fastest).

---

## 3. Fleet Roster & Balance Baseline

All baseline movement speeds are scaled against the Destroyer (`DD` = `100%`).

| Class | Code | Gold Cost | Steel Cost | Build Time | Speed | Base Armor | Armament | Fire Rate | Salvo Dmg / Pen |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Destroyer** | `DD` | 100 | 50 | 7.5s | 100% | 0% | 4x Single + Auto Torps + Depth Charges | 4.0s | Low / Low |
| **Submarine** | `SS` | 150 | 75 | 10.0s | 50% | 0% | Manual Torps Only (3 per launch) | 20.0s | N/A |
| **Light Cruiser** | `CL` | 250 | 150 | 15.0s | 70% | 5% | 3x Triple | 4.0s | High / Medium |
| **Heavy Cruiser** | `CA` | 400 | 250 | 22.5s | 63.75% | 15% | 4x Double | 5.333s | High / High |
| **Battlecruiser** | `BC` | 650 | 450 | 37.5s | 51.3% | 20% | 4x Quad | 8.0s | Medium (80/shell) / Extreme |
| **Battleship** | `BB` | 800 | 600 | 45.0s | 42.75% | 25% | 3x Double + 4 Secondaries | 8.0s | Massive / Extreme |
| **Super Battleship** | `SBB` | 1040 | 780 | 58.5s | 38.475% | 30% | 3x Triple + 4 Secondaries + Flak | 11.0s | Massive (260/shell) / Extreme |
| **Supercarrier** | `SCV` | 1500 | 600 | 60.0s | 90% | 0% | Dive / Torpedo (3 flights) / Depth-Charge Bombers, range `2028`, bombs `+10%` | 3.33s / 6.67s / 2s | High (HE Bombs) |
| **Light Carrier** | `LCV` | 500 | 200 | 30.0s | 90% | 0% | Dive / Torpedo / Depth-Charge Bombers, range `1014`, 5 squadrons max | 5s / 10s / 3s | High (HE Bombs) |
| **Resource Ship** | `RS` | 250 | 150 | 15.0s | 50% | 0% | None (mines islands) | - | - |
| **Radar Ship** | `RD` | 150 | 75 | 10.0s | 80% | 0% | None (spots `1080`) | - | - |
| **AA Cruiser** | `CLAA` | 400 | 250 | 15.0s | 70% | 5% | Flak only: 1/3 kill chance per squadron within `310`, every 3s | 3.0s | - |

`ShipStats.ShipClass` is `{ DD, SS, CL, CA, BB, CV, BC, SBB, RS, RD, LCV, CLAA }`: new classes are appended so class ids already in data files and network commands keep their meaning. `CV` is the **Supercarrier** (code `SCV`); `LCV` is the **Light Carrier**; `CLAA` the **AA Cruiser**. `GameData.all_classes()` sets the shop and hotkey order, smallest to largest (`PlayerController.BUILD_KEYS` `1`-`9`, `0`, `-`, `=`: RD, RS, DD, SS, CL, CLAA, CA, BC, BB, SBB, LCV, SCV). BC, SBB and CV are Tier 3 (Major island) builds; CL, CLAA, CA and LCV Tier 2; RS and RD Tier 1. Build times were halved (balance pass). Speeds: CA, BC, BB and SBB went to 1.5x their original speed, then CA -15% and BC / BB / SBB -5% (CV, LCV, DD, SS and CL unchanged).

**Support ships** (`ShipStats.is_support()`: no guns, planes, torpedoes, depth charges or secondaries) never fight, never capture islands and simply explode when sunk.
- **Resource Ship (`RS`, `mines_islands`):** HP `60`, cost of a Light Cruiser. Stopped (no move order, speed under `Ship.MINING_MAX_SPEED`) within `mining_reach` (`160`) of any island's shore except a Home Base (cover, Minor or Major, any owner), it mines that island (`Ship.mining_island()`), except a Minor or Major island its own side owns (`_in_mining_reach`): `Economy.mining_income()` adds one Minor island's income (`+30 G / +10 S`) per distinct island mined, each 15 s tick, only while it stays there. **One Resource Ship per island per side:** the host keeps a claim per ship (`Ship._update_mining_claim`, each physics tick); the first ship to anchor keeps the island, another of the same side beside it mines a different island in reach or nothing (`blocked_mining_island()`, shown in the HUD), and takes over once the first leaves or sinks. Other sides, allies included, may mine the same island. The claimed island index is in the ship snapshot.
- **Radar Ship (`RD`):** HP `300` (half a DD), cost of a Submarine, `spotting_range` `1080` (1.5x a DD). Spots surface ships only (`detects_submarines = false`); `order_attack` refuses every target.
- **Radar sees over islands:** `ShipStats.sees_over_islands` (RD only). `VisionSystem` keeps the RD's circle in a separate `_radar` list that spots surface ships, Home Bases and garrisons by range alone (`_radar_sees`, no line of sight); submarines still need detectors.

**AA Cruiser (`CLAA`)** is a Light Cruiser (hull, HP `1500`, speed, armor `5%`, spotting, Tier 2, `15s` build) whose gun mounts are all replaced by anti-aircraft guns, at a Heavy Cruiser's price (`400 G / 250 S`). It has no guns (`gun_mounts 0`) and a flak barrage (`periodic_aa_chance` `1/3`, `periodic_aa_interval` `3s`, `periodic_aa_range` `310` = half a CL's `620` gun range) on top of the usual 1-in-5 roll when bombed; a pink range ring shows the flak reach. `is_support()` is false for any hull with a flak barrage, so it captures islands and fights like a warship; an attack order closes to flak range. The AI wants one once it has 10 ships, plus one per enemy carrier it can see (max 3), and sails them at the centre of an attack wave (`AIController._is_aa_escort`).

**Super Battleship (`SBB`)** is defined against the Battleship: `10%` slower (`0.27`), `+30%` damage per shell (`260`), reload BB `+3s` (`11.0s`), armor `30%`, cost `+30%` (`1040 G / 780 S`), HP `+10%` (`5500`). It keeps the BB secondaries and adds a **flak barrage** (`ShipStats.periodic_aa_chance` `0.4`, `periodic_aa_interval` `10s`, `periodic_aa_range` `240`): every 10 s while enemy squadrons are within range, each one is shot down with a 2 in 5 chance (`Ship._aa_barrage`, `PlaneSquadron.shoot_down`), on top of the usual 1-in-5 roll when bombed.

**Battlecruiser (`BC`)**: armor `20%`, `20%` faster than a BB (`0.36`), BB reload (`8.0s`), 4 quadruple turrets, shells do `60%` less damage than a BB's (`80`), HP `20%` below a BB (`4000`). Neither BC nor SBB can target Submarines.

**Broadside on player orders:** an attack order from a player (`attack` command, `Ship.order_attack(target, true)`) sets `Ship.broadside_order` on every ship with guns (not submarines, carriers or support ships). Once in range with line of sight, the ship turns until its beam faces the target (`Ship._turn_broadside`: starts when the target is more than `25` deg off the beam, stops within `8` deg, sailing a short leg abeam to turn), so every turret (and a destroyer's broadside torpedoes) bears. AI orders do not use it. A move or stop order cancels it.

Battleships, Battlecruisers and Super Battleships cannot target Submarines (`ShipStats.can_target_submarines = false`; `Ship.can_engage()`): their guns never pick a sub and attack orders on one are refused. A stray BB shell can still hit one.

**Battleship secondaries:** every `BB` carries 4 destroyer-calibre secondary guns on its citadel (`ShipStats` "Secondary Guns" group: `25` damage per shell, one shell per mount, `8.0s` reload = half a `DD` gun's rate, range `470` = half the BB main-gun range). Two mounts face each beam (`secondary_facings_deg` +-90, `100` deg either side). They pick their own target (`Ship.secondary_target`, nearest legal one in secondary range, priority target first), need their own line of sight, reload separately from the main battery, obey the no-submarine rule, and show an orange range ring.

Gun fire rates are tied together: `CL` reloads as fast as a `DD` (`4.0s`), `BB` reloads in `8.0s`, and `CA` fires 1.5x as fast as a `BB` (`5.333s`).

---

## 4. Specialty Weapon Systems

### Torpedoes
- **Damage:** `1.30 * single_battleship_shell_damage` (30% more than a single BB shell).
- **Speed:** The standard torpedo is slightly slower than Battleship shells. Each class scales it with `torpedo_speed_scale` (`DD = 0.5`, `SS = 1.0`).
- **Destroyer (`DD`) Torpedoes:**
  - Fire **automatically**, with no order, whenever a spotted enemy is in a broadside arc; `30.0` second cooldown, spent only when torpedoes actually launch.
  - Launch **only** from port (left) or starboard (right) broadsides. Player must position the DD broadside to the enemy.
  - Travel at **half** the standard torpedo speed.
- **Submarine (`SS`) Torpedoes:**
  - Fired **manually** by the player.
  - Launch **only** from bow (front) or stern (rear) tubes.
  - **Homing Ping:** Actively homes in on the target for the first `2.0` seconds of travel, then locks trajectory and travels in a straight line.
  - **Reveal Penalty:** Launching a torpedo immediately reveals the Submarine to the entire enemy team for `15.0` seconds.
  - **Battleship tracking:** fired at a `BB` or `SBB`, the torpedoes home for `sub_battleship_homing_time` (`6s`) at `sub_battleship_homing_turn_deg` (`120` deg/s) instead of the 2 s / 60 deg/s ping (`Match.spawn_torpedo`). Every other target (BC included) gets the normal ping.

### Destroyer (`DD`) Depth Charges
- Dropped **automatically** on the nearest spotted enemy Submarine within `depth_charge_range` (`180`): `depth_charge_damage` (`100`, ignores armor) every `depth_charge_interval` (`2.5s`). Hulls under construction do not drop them.
- A DD with an attack order on a Submarine closes to inside depth-charge range instead of holding at gun range.

### Submarine (`SS`) Stealth & Restrictions
- **Stealth State:** Invisible to enemies unless within detection range of an enemy **Destroyer (`DD`)** or **Island Shipyard** (or during the 15s torpedo reveal penalty).
- **Base Attack Restriction:** Submarines **cannot** target, attack, or damage the enemy Home Base.

### Carrier (`CV`) Planes (HE Bombs)
- **Mechanic:** CVs do not fire guns. The air wing works **automatically**: with no order it picks the nearest spotted enemy within plane range (`Ship.air_target()`). The player can override it by selecting the CV and right-clicking an enemy (`Ship.order_attack` / `order_strike`); the override lasts until that target dies or is lost. Stop (`X`, `Ship.clear_strike()`) hands the wing back to automatic targeting.
- **Supercarrier (`CV`, code `SCV`) and Light (`LCV`) carriers:** Supercarrier `plane_range` `2028`; Light `1014` (half). Both fly all three roles below.
- **Per-squadron targets:** every dive-bomber squadron keeps its own `PlaneSquadron.dive_target`, handed out by `Ship.dive_target_for()`. A launch goes to the ordered strike target while it has room, otherwise to the nearest spotted enemy in plane range with room (`Ship._pick_dive_target`). At most `squadrons_per_target` (`5`) squadrons stack on one target, so a Supercarrier works several targets at once (`max_squadrons` `30` is only a safety cap). A Light Carrier has at most `max_total_squadrons` (`5`) squadrons of all roles in the air. When a target sinks or is lost, its squadrons go **at once** to another target within the carrier's strike reach (`air_reach()`), or fly home if there is none. A right-click strike order pulls airborne dive bombers onto the target, nearest first, up to 5.
- **Three roles** (`PlaneSquadron.Role`), each on its own timer (`Ship._update_air_wing`):
  - **DIVE (HE dive bombers):** one every `plane_interval` (Supercarrier `3.333s`, Light `5.0s`) while a spotted target with room is in range. Any target. Supercarrier bombs hit for `bomb_damage * bomb_damage_multiplier` (`150 * 1.1 = 165`; applied in `Match.spawn_squadron` to DIVE squadrons whose home is a Ship, so island air bases keep `150`).
  - **TORPEDO:** every `torpedo_bomber_interval` (Heavy `6.667s`, Light `10s`) the carrier sends `torpedo_flights_per_launch` flights (Heavy `3`, Light `1`), dealt round-robin over up to that many capital targets (`Ship._launch_torpedo_flights` / `_torpedo_targets`: the ordered strike target first, then the nearest): three targets get one each, two get A, B, A, a lone target gets all three. At most `torpedo_flights_per_target` (Heavy `3`, Light `1`) flights are on one target and `max_torpedo_bombers` (Heavy `9`, Light `1`) in the air. Only at capital ships (`ShipStats.is_capital_class`: BC, BB, SBB, CV). The flight flies to a release point `TORPEDO_DROP_DISTANCE` (`70` px, about half an inch) off the target's nearer broadside, led for its motion, drops **2 parallel torpedoes** aimed across its beam (`Match.spawn_air_torpedo`, standard torpedo damage, armor applies), then flies home.
  - **DEPTH (depth-charge bombers):** one flight every `depth_bomber_interval` (Heavy `2s`, Light `3s`), up to `max_depth_bombers` (`3`) airborne, at spotted enemy Submarines only; drops one depth charge (DD `depth_charge_damage`, `100`, ignores armor) and flies home.
  - Torpedo and depth flights pick the ordered strike target first if it qualifies, otherwise the nearest qualifying spotted enemy. Every attack run gets the target's anti-air roll.
- **Hover (dive bombers):** A squadron flies to the target, circles it and bombs every `3.0` seconds (`bomb_interval`) for `bomb_damage` (`150`) per run, follows the carrier's current air target, and returns to its carrier and lands when there is none. Squadrons are lost if their carrier sinks.
- **Speed:** `0.50 * torpedo_speed` (50% of the standard torpedo speed).
- **Terrain:** Planes fly over islands and land. A strike needs no line of sight (the target must still be spotted).
- **Armor Bypass:** HE Bombs **ignore standard armor damage reduction**, countering heavily armored Battleships.
- **Anti-Air:** After each bomb run on a `CL`, `CA` or `BB` (`aa_kill_chance = 0.2`) the squadron has a 1-in-5 chance of being shot down. Hulls under construction and the Home Base have no anti-air.

### Capture & Build Queue
- **Capture:** Only a **neutral** island is captured, by holding it uncontested for `30.0` seconds (`capture_time`).
- **Fortified islands:** An owned island is a mini base. Its `IslandGarrison` (a `Combatant` under the bases root, one per capturable island) has `minor_garrison_hp` (`2000`) or `major_garrison_hp` (`4000`), no armor, no weapons and no regeneration. Enemies cannot capture it by sitting on it: shells and torpedoes that strike the island's shore damage the garrison, and bombs hit it like any target. Submarines can neither target nor damage it (`Combatant.is_structure()`). It is spotted like a ship (its own island does not block the line of sight to it, `Combatant.los_blocker()`), and an attack order on it closes in even when unspotted, like the Home Base. At 0 HP the island turns **neutral**: its shipyard, queue and any hull on the slip are lost, and the normal 30 s hold captures it. A new owner always gets a full-HP garrison. Islands never change hands directly from one team to the other.
- **Garrison regeneration:** a garrison on an island whose shipyard is Tier `garrison_regen_min_tier` (`2`) or higher heals `garrison_regen_rate` (`5%`) of its max HP per second once it has not been hit for `garrison_regen_delay` (`5s`) (`IslandGarrison._regenerate`, host only; HP is already in the snapshot).
- **Build queue:** Orders (ships and upgrades) are paid **in full when queued**; an order the bank cannot cover is refused. A yard starts the next order in the same tick the previous one finishes. Cancel (`C`, `Shipyard.cancel_last()`) removes the last order and refunds it in full, including the order under construction (its hull is scrapped, `Match.scrap_hull`). When an island falls, the order in progress is lost and every order behind it is refunded. Queued orders count toward the fleet cap.
- **Island air base:** a **Major** island whose owner has upgraded its shipyard to **Tier 3** runs an air base (`Island.has_air_base()`, `IslandGarrison`): it launches HE dive-bomber squadrons, one every `air_base_interval` (`10s`), up to `air_base_squadrons` (`3`) airborne, at the nearest spotted enemy ship that has recently fired on its garrison within `air_base_range` (`700`, cruiser-like) of the shore. Its squadrons are lost if the island falls.
- **Island radar:** the owner of a Major island with a Tier 3 shipyard can buy radar once (`radar` command, `Island.try_buy_radar`, `200 G / 150 S`), raising the island's spotting from `island_spotting` (`380`) to `radar_spotting` (`720`, a DD's). Radar is lost when the island changes hands.

### Docks & Repairs
- **Dock:** Every capturable island and Home Base has a dock (`Shipyard.slip_position`, drawn by `DockArt`) where its ships are built and launched.
- **Repair:** A friendly, finished ship within `dock_radius` (`220`) of the slip regains `repair_rate` (`2%` of max HP) per second, only if **both** hold:
  - the shipyard's tier can build that ship class (a `BB` cannot repair at a Tier 2 yard; an island with no shipyard repairs nothing);
  - the shipyard is **not building** (its queue is empty).
- **Orders:** Right-clicking an own dock sends the selected ships to `Shipyard.dock_point()` (`Match.order_group_dock`). The AI does not use docks.
- **Size:** Docks are kept small (`DockArt.BERTH_HALF_LENGTH 20`, `Match.SLIP_OFFSET 70`) so they do not get in the way.
- **Tier looks (cosmetic):** `DockArt` draws each tier differently: Tier 1 a timber jetty with one shed, a derrick and crates; Tier 2 a wider concrete wharf with two warehouses, a gantry crane and fuel tanks; Tier 3 the widest apron, longer lit jetties, a hazard-striped dry-dock gate, a fabrication hall in team trim, red-roofed stores, two hammerhead cranes and a fuel farm.

### AI Difficulty
- `GameSettings.ai_difficulty` (`EASY`, `MEDIUM`, `HARD`; per team via `Match.ai_difficulty`). **Hard** is the original, full-strength AI and the default for headless runs and tests; the start menu preselects Medium.
- **Easy and Medium may control only one ship at a time.** Every AI ship order passes through `AIController._command`: on Hard it is sent at once; on Easy/Medium the orders wanted during a think are collected and only one is sent, to the ship that has waited longest. Medium sends one order every 2 s (`ORDER_INTERVAL_MEDIUM`) and plans production every 2nd think (`MEDIUM_PRODUCTION_EVERY`); Easy one every 5 s (`ORDER_INTERVAL_EASY`), production every 4th think. Tuned with AI-vs-AI duels on the round sea: Hard beats Medium ~11/16, Medium beats Easy ~15/16 (side advantage on a seed caps the margin). Ships still fire, launch planes and drop depth charges on their own. Never call ship order methods from the AI outside `_command`.

### Start Menu
- `scenes/menu.tscn` (`MainMenu`) is the project's main scene; it sets `GameSettings.map_size` and changes to `scenes/main.tscn` (the `Match` root). It also sets `GameSettings.ai_difficulty` and `GameSettings.ai_opponents` (1-3 AI fleets). User args `--size=`, `--difficulty=`, `--seed=`, `--players=`, `--ai-vs-ai` or `--skip-menu` skip it (once, at launch); `--host` / `--join=ADDRESS` (with `--name=`, `--port=`) go to the LAN lobby.

### Commands & LAN Multiplayer
- **Every player action is a command:** a plain `Dictionary` (`move`, `stop`, `attack`, `dock`, `build`, `upgrade`, `cancel`, `rally`, `radar`) passed to `Match.command()`, which runs `Match.execute_command(team, cmd)` and returns the notice to show. Ships are named by `Ship.net_id` (`Match.ships_by_id`), yards by their index in `Match.yards`, targets by `Match.combatant_ref()`. `execute_command` treats every field as hostile (types, ranges, finite on-map points, ownership, spotted targets, eliminated sides). UI code must never call ship or yard order methods directly.
- **`Net` autoload** (`scripts/net/net_session.gd`, `NetSession`): ENet session, lobby seats (human / AI / open / closed, team number), match start config, leave handling. Same node path on every machine; all RPCs live there. Up to 4 players, one side each.
- **Host-authoritative:** only the host runs the rules. On a client the Match has `replica = true`: every sim path (`Match`, `Ship`, projectiles, `Shipyard`, `Island`, `Economy`, `WeatherFront`, `AIController`) returns early, and `NetSync.apply()` copies the host's full-state snapshot (`NetSync.build()`, 15 Hz) into the nodes. Clients run their own `VisionSystem` on the replicated positions. Any new piece of game state must be added to `NetSync.build/apply` (and, for ships, `Ship.net_write/net_read`), and test_29 must keep showing that a replica's own snapshot equals the host's.
- **LAN discovery:** `LanDiscovery` (child of `Net`) broadcasts a JSON beacon on UDP `24568` once a second while hosting (`NetSession._beacon`, with `in_match` and `watch` = spectator places left); the start menu browses and lists games with a Join button, or **Spectate** for a running game or a full lobby. Beacons are untrusted input: size-capped, fields clamped, names cleaned.
- A player who drops mid-match is replaced by an AI (`Match.give_side_to_ai`); if the host leaves, clients return to the menu. Network games set `end_when_local_out = false`, so an eliminated player keeps spectating.

---

### Visuals (cosmetic only)
- **Nothing visual may touch the simulation.** Art, turret training, fires, wrecks, wake, storms and the ocean shader read game state but never change it, and use their own clocks/hashes (never `Match.rng`), so host and replicas stay identical.
- **Display scale:** the base canvas is 1920x1080 (FHD; `canvas_items` stretch with `expand` aspect, so other window sizes scale; the window opens at 1600x900 via the window override). The camera zoom is cosmetic (`CameraRig.DEFAULT_ZOOM` `2.016` = old `1.4` x `1.2` for the wider canvas x `1.2` for a 20% closer view; limits `0.72`-`4.6`), with ship and island art baked at 2x resolution (`ShipArt.BAKE_SCALE` `6`, `IslandTerrain.BAKE_SCALE` `3`). World units, distances, ranges and speeds are unchanged, so the game plays exactly as before.
- **Ship art** is vector drawing in `ShipArt` (`scripts/ships/ship_art.gd`), one function per class. `ShipArtCache` bakes every hull (per class and side) and gun house (per class) into mipmapped textures at match start; `ShipLayer` children draw the hull sprite and wake behind the ship, and `Ship._draw` draws only the guns, fires and overlays. Drawing hundreds of vector commands per ship every frame costs ~0.5 ms per ship, so keep new detail inside the baked parts. Headless runs skip baking.
- **Turrets** turn toward the ship's current target (`gun_target` / `secondary_target`; on a replica the nearest legal target) at `ShipStats.turret_traverse_deg()` = `12 + 70 * speed * sqrt(48 / hull_length)` deg/s, staying inside their firing arcs. Purely visual: firing still uses `mount_bears_on`.
- **Damage fires** grow with lost HP; **wrecks** (`ShipWreck`) sink cruisers and larger over `7s`; destroyers and submarines only explode.
- **Island terrain** (`IslandTerrain`) is generated from a seeded RNG and baked to a texture once; Major islands carry an airfield, Minor islands an outpost, cover islands are jungle atolls or volcanoes. `DockArt` draws the wharf as part of the shore.
- **Sound (`Sfx` autoload, `scripts/audio/sfx.gd`):** every sound is synthesised in code at start-up on a worker thread (`Sfx.synth_all`, 32 kHz, about 6 s; interface sounds are published first, each sound as soon as it is ready; no audio files) with its own RNG. Sounds are layered physically: blast crack, pressure thump, closing low-pass body, rolling rumble, outdoor reverb with a far echo (`_reverb`) and soft clipping (`_drive`); metal uses inharmonic modes (`_modes`), water a band-passed column, falling spray and droplets; aircraft are three detuned radial engines with Doppler; interface cues are a mechanical click, a ship's bell (ship ready), a bosun's call (island taken, victory) and the general-alarm gong; the ocean bed (`Sfx.OCEAN_DB`, dark, no foam hiss), storm wind, ship's bell and bosun's call are mixed low, muffled and reverberant as background ambience so they sit under a music playlist (combat and the alarm stay up front); nothing is made or played headless. `Match.spawn_effect` plays the effect's sound (`Effect.SOUNDS`; torpedo hits are their own `Effect.Kind.TORPEDO_HIT`, appended to the enum) after its local-visibility check, and `Match._play_launch_sounds` plays gun (size from shell speed), torpedo and aircraft launches the local player can see, on host and replicas alike. The ocean loop runs while a match with UI is in the tree; wind and rain fade in while the camera is inside a `WeatherFront` (group `weather_fronts`). The HUD plays interface cues for islands taken or lost, ships launched and the Home Base under fire. `M` mutes everything (Master bus, `Sfx.set_muted`, signal `Sfx.mute_changed`); the top-bar **Sound** button opens `SoundPanel` (`scripts/ui/sound_panel.gd`, `HUD.sound_panel`): Music and Effects sliders, a mute switch and Now playing / Next track. Buses (`AudioMix`, `scripts/audio/audio_mix.gd`): "Music" and "SFX" feed Master; every `Sfx` player is on SFX; slider volumes (linear 0-1, squared to dB, 0 mutes the bus) are saved in `user://audio.cfg`. The soundtrack is the `Music` autoload (`scripts/audio/music.gd`): every `.ogg` / `.mp3` / `.wav` under `res://assets/music/` (subfolders too, via `ResourceLoader.list_directory`, so it works exported) is a track; when one ends, after `Music.GAP` (2 s) another is picked at random, never the same twice in a row (`Music.pick_next`). Track titles and artists for Now playing and the Credits page live in `Music.TRACK_CREDITS` (keyed by file name without extension): add an entry for every new track. Nothing plays headless.
- **Spectators (`Net.spectators`, `MAX_SPECTATORS` 4, `PROTOCOL` 2):** the host keeps accepting connections during a match; `_rpc_hello` seats a newcomer in an open lobby seat, otherwise (a running match, or a full lobby) makes them a spectator. A mid-match spectator is sent `_rpc_start` with the running config (then the lobby state) and builds a replica with `local_team` -1 (so `Match.spectator`, no fog); its commands are dropped (`_peer_side` has no entry for it). In the lobby, `request_spectate(watch)` swaps a seated client to spectating and back (`_set_spectating`; the host always plays); spectators are in the lobby state and watch the next match. **Defeat:** when the local side is knocked out and the match goes on, the HUD shows `DefeatPanel` with **Spectate** (`HUD.spectate_match()`: fog lifted, everything visible) and **Leave** (the host's leave ends the game for everyone).
- **Sandbox (`Shift+E`, secret):** `HUD.toggle_sandbox()` sends a `sandbox` command; `execute_command` toggles `Economy.infinite[team]` for the sender (single player and LAN alike) and answers with a notice. While on, `can_afford` is always true, `spend` deducts nothing and `refund` adds nothing; the HUD shows the bank as infinity. Synced in snapshots as `inf`.
- **Pause (single player only):** `HUD.toggle_pause()` (P key or the top-bar button, hidden in LAN games) sets `SceneTree.paused`; the HUD runs with `PROCESS_MODE_ALWAYS` and shows a Resume / Main Menu overlay. Leaving the match or freeing the HUD unpauses. **Resource Ship marker:** a mining RS draws a pulsing gold ring, a dashed line to the island and a coin badge (`Ship._draw_mining_marker`, `shown_mining_island()`; a replica judges by synced speed) and the HUD announces when one starts mining. **Title screen:** `MainMenu` opens on a title screen with a Start button (`start_screen`, `press_start()`) the first time it is shown, unless the command line starts a match or a LAN game; returning from a match goes straight to the menu.
- **UI look (`UITheme`, `scripts/ui/ui_theme.gd`):** one code-built Theme for every screen (navy panels, brass trim, raised `Button` / `AccentButton` / `DangerButton` styles, gauges, tooltips) plus `UITheme.liven()` for hover / press animation and click sounds, and drawn `UITheme.Icon`s. The HUD top bar uses resource chips that flash on change; the selection / shop panel is a wide, low, translucent strip (panel alpha `0.55`, refitted to its contents by `HUD._fit_panel`) with a header and HP gauge, one row of flat build cards (`FlatButton`: baked ship art over hotkey, code and cost, a tier bar on top, tinted red when unaffordable), and the yard buttons (`FlatAccentButton` / `FlatDangerButton`) beside the production queue and bar. `SeaBackdrop` animates the menu and lobby. Tests read `_info_label`, `_gold_label`, `_fleet_label`, `last_notice()` and the menu button texts, so keep those.
- **Order feedback:** while the local player has ships selected, `PlayerController` swaps the system cursor (`Input.set_custom_mouse_cursor`, images built in code by `OrderFeedback.make_move_cursor` / `make_attack_cursor`) to a downward arrow over water and a crosshair over a spotted enemy (`wanted_cursor`; the normal pointer over HUD controls). A move, dock or rally order drops an impact ripple with a falling arrow at the point and an attack order flashes a red bracket on the target (`OrderFeedback.ping` / `lock_on`, a `Match.order_feedback` node at z `60`, above the fog, sized in screen pixels). Cosmetic only, own clock.
- **The swell is simulation, not art:** `Match.wave_drift()` pushes every hull back and forth by a few pixels (`WAVE_DRIFT` `3` px/s on a mid-size hull, less on big ones; deterministic on `sim_time`, nav-checked, oscillating so it never carries a ship away).

## 5. Godot 4 & GDScript Coding Standards

- **Static Typing:** Always use static typing in GDScript (`var speed: float = 100.0`, `func calculate_damage(base_dmg: float) -> float:`).
- **Data-Driven Design:** Define ship stats, weapon profiles, and island generation parameters using custom `Resource` classes (`class_name ShipStats extends Resource`) so balance tweaks do not require code changes.
- **Signals & Decoupling:** Use signals (`signal target_destroyed(ship: Ship)`) for cross-node communication (e.g., economy ticks, fog-of-war updates, UI refreshes). Call down, signal up.
- **Physics & Raycasting:**
  - Separate collision layers clearly: `1: Water/Terrain`, `2: Shallow Water`, `3: Islands (Hard Cover)`, `4: Ships`, `5: Projectiles`, `6: Vision/Spotting`.
  - Use 2D raycasts (`PhysicsRayQueryParameters2D`) to verify unobstructed Line of Sight (`LOS`) between individual turrets/ships and targets before firing or spotting.
- **Directory Structure Convention:**
  - `res://scenes/` — Scene files (`.tscn`) grouped by domain (`ships/`, `environment/`, `ui/`, `projectiles/`)
  - `res://scripts/` — GDScript logic (`.gd`) and custom `Resource` definitions (`resources/`)
  - `res://assets/` — Sprites, audio, shaders, and fonts
