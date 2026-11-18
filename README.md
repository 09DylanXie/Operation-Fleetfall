# Operation: Fleetfall

**Operation: Fleetfall** is a 2D World War II naval real-time strategy (RTS) game built in **Godot 4 (GDScript)**. It merges the macro territory control of *Star Wars: Empire at War* with the micro fleet positioning, line-of-sight mechanics, and ship class dynamics of *World of Warships*.

---

## Core Vision & Gameplay Loop

- **Objective:** Destroy the enemy's Home Base.
- **Core Loop:** Expand from your Home Base, capture strategic island resource nodes, construct tech-specific shipyards, and out-maneuver the opposing fleet using island cover, fog of war, dynamic weather, and coordinated focus fire.
- **Fleet Cap:** **30 ships** per player, **+3 for every Major island you own** (shipyard or not), to prevent unit spam and make every loss tactically meaningful. Ships under construction cannot defend themselves. You may have at most **2 Supercarriers** and **3 Super Battleships** at a time, and launch at most **4 Supercarriers** in a whole game.

---

## Map & Environment

- **Procedural Archipelagos:** Every match generates a unique island layout. Islands act as **hard cover**, physically blocking both spotting vision and artillery shells.
- **Fog of War:** The entire map is shrouded in fog. Each ship class has an intrinsic spotting range—fast, lightly armored ships must scout ahead to spot targets for heavy artillery. Destroyers are the eyes of the fleet: a Cruiser spots **half** as far as a Destroyer, a Battleship **two thirds** as far as a Cruiser, a Carrier **one third** as far as a Battleship, and a Submarine spots **nothing** at all.
- **Round Seas for Up to Four Fleets:** The sea is a circle with every Home Base on its rim, spaced evenly; one player's share of the islands is generated and rotated round the centre, so every side gets the same layout. The start menu offers **Small**, **Medium** and **Large** presets (5, 7 and 11 capturable islands for two fleets), and the sea grows with every extra fleet.
- **Opponents & Alliances:** Offline you can face **1 to 3 AI fleets** (every side against every other). Losing your Home Base knocks a side out; its ships sink and its islands turn neutral, and the match goes on until one alliance is left.
- **Dynamic Weather:** Roaming weather fronts (such as cyclones) move across the map, drastically reducing the spotting range of any ship caught inside and creating ambush opportunities.
- **Island Types:**
  - **Shallow Water Islands (Minor):** Accessible only by shallow-draft vessels (**Destroyers** and **Submarines**). Yield high **Gold** income.
  - **Deep Water Islands (Major):** Required to construct Tier 3 Shipyards for massive capital ships. Yield high **Steel** income.

---

## Economy

Resources are automatically deposited into your bank every **15 seconds** based on territory control. Movement requires no fuel.

- **Gold:** Crew and funding. Primary resource for light ships (Destroyers, Submarines, Cruisers).
- **Steel:** Raw materials. The primary bottleneck for capital ships (Battleships, Aircraft Carriers).

| Node Location | Gold Rate (per 15s) | Steel Rate (per 15s) | Primary Utility |
| :--- | :---: | :---: | :--- |
| **Home Base** | +50 Gold | +20 Steel | Core Logistics & Basic Production |
| **Minor Island (Captured)** | +30 Gold | +10 Steel | Shallow-Draft Scouting Control |
| **Major Island (Captured)** | +20 Gold | +50 Steel | Deep-Water Tier 3 Fleet Construction |

---

## Combat Mechanics

- **Auto-Engagement & Priority Override:** Ships automatically fire at any enemy that is both spotted and within range. Players can drag-select units and right-click a priority target to command focus fire (still bound by line-of-sight and range rules).
- **Line of Sight (LOS):** Islands physically block projectiles and spotting vision. Clever positioning lets ships hug islands to break enemy lock-ons or limit how many enemy turrets can return fire.
- **Focus-Fire Armor Stripping:** Armor grants a flat percentage damage reduction. However, when multiple ships attack the same armored target, the target's armor is reduced by **5% for each additional attacker beyond the first** (e.g., a Battleship with 25% armor under fire from 3 Cruisers has its effective armor reduced to 15%).
- **Ballistic Projectiles:** All artillery shells travel in straight lines with no homing. Shell velocity scales with gun caliber (Destroyer shells travel at baseline speed; massive Battleship shells travel faster).

---

## Fleet Roster

All baseline stats scale relative to the **Destroyer (DD)**.

| Class | Cost (Gold / Steel) | Build Time | Speed | Base Armor | Armament | Fire Rate | Salvo Dmg / Pen |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Destroyer (DD)** | 100 G / 50 S | 7.5s | 100% | 0% | 4x Single Guns + Torps | 4.0s | Low / Low |
| **Submarine (SS)** | 150 G / 75 S | 10s | 50% | 0% | Torpedoes Only (3 per launch) | 20.0s | N/A (Torpedo) |
| **Light Cruiser (CL)** | 250 G / 150 S | 15s | 70% | 5% | 3x Triple Guns | 4.0s | High / Medium |
| **Heavy Cruiser (CA)** | 400 G / 250 S | 22.5s | 64% | 15% | 4x Double Guns | 5.3s | High / High |
| **Battlecruiser (BC)** | 650 G / 450 S | 37.5s | 51% | 20% | 4x Quad Guns | 8.0s | Medium / Extreme |
| **Battleship (BB)** | 800 G / 600 S | 45s | 43% | 25% | 3x Double Guns + Secondaries | 8.0s | Massive / Extreme |
| **Super Battleship (SBB)** | 1040 G / 780 S | 58.5s | 38% | 30% | 3x Triple Guns + Secondaries + Flak | 11.0s | Massive+ / Extreme |
| **Supercarrier (SCV)** | 1500 G / 600 S | 60s | 90% | 0% | Dive, Torpedo & Depth-Charge Bombers | 3.3s / 6.7s / 2s | High (HE Bombs, +10%) |
| **Light Carrier (LCV)** | 500 G / 200 S | 30s | 90% | 0% | Dive, Torpedo & Depth-Charge Bombers | 5s / 10s / 3s | High (HE Bombs) |
| **AA Cruiser (CLAA)** | 400 G / 250 S | 15s | 70% | 5% | Flak only (1 in 3 per squadron within 310, every 3s) | 3s | - |
| **Resource Ship (RS)** | 250 G / 150 S | 15s | 50% | 0% | None | - | - |
| **Radar Ship (RD)** | 150 G / 75 S | 10s | 80% | 0% | None | - | - |

- **Supercarrier:** plane range 2028. It launches a third faster than the Light Carrier, its bombs hit 10% harder (165), and it can stack up to 5 dive-bomber squadrons on every target, so it can bomb several ships at once. Each torpedo launch sends **3 flights**, spread over up to 3 capital ships or all at one (never more than 3 on the same ship). **Light Carrier:** a cheaper Tier 2 carrier with half the plane range (1014) and at most 5 squadrons in the air in total.
- **Resource Ship:** an unarmed collier with almost no HP (60). Stop it next to any island that is not a Home Base or one of your own Minor/Major islands and it mines it, earning a small island's income (+30 Gold / +10 Steel per tick) for as long as it stays. Several Resource Ships on one island earn only once, so spread them out.
- **Radar Ship:** an unarmed picket with half a Destroyer's HP that spots surface ships 1.5x as far as a Destroyer (1080). It cannot see submerged Submarines.
- **Radar sees over islands:** a Radar Ship spots surface ships behind islands too (submarines still hide from it).

- **Battlecruiser:** fast and lightly armoured for a capital ship: 16 guns in four quadruple turrets, each shell doing 60% less damage than a Battleship's, on a hull with 20% less HP.
- **Super Battleship:** the biggest gun platform afloat: 30% more damage per shell, 10% more HP and 30% armor, but slower to reload (+3 s) and to steam (10% slower than a Battleship), and 30% more expensive. Its flak barrage fires every 10 seconds at enemy squadrons overhead and downs each with a 2 in 5 chance.

---

## Specialty Weapon Systems

### Torpedoes
- **Payload & Speed:** Deal **30% more damage** than a single Battleship shell. The standard torpedo travels slightly slower than a Battleship shell; **Destroyer torpedoes run at half that speed**.
- **Destroyer Deployment:** Fire automatically whenever an enemy is on the Destroyer's beam (port or starboard broadside) and the **30 second** reload is ready—no order needed, but the player must angle the Destroyer broadside to the target.
- **Submarine Deployment:** Fired manually by the player from bow (front) or stern (rear) tubes.

### Depth Charges
- **Destroyers hunt Submarines:** A Destroyer automatically drops depth charges on any spotted enemy Submarine within **180** range: **100 damage every 2.5 seconds**, ignoring armor. Three patterns sink a Submarine. A Destroyer ordered to attack a Submarine runs in over it.

### Submarine Stealth & Restrictions
- **Stealth State:** Completely invisible to the enemy unless they approach too close to an enemy **Destroyer** or **Island Shipyard**.
- **Homing Ping:** Manually fired submarine torpedoes actively home in on the selected target for the **first 2 seconds** of travel before locking onto a straight trajectory.
- **Reveal Penalty:** Firing a torpedo immediately reveals the Submarine to the entire enemy team for **15 seconds**.
- **Battleship Tracking:** torpedoes fired at a Battleship or Super Battleship keep homing for 6 seconds and turn twice as hard, so a big ship cannot simply steam out of their path. Against every other ship they home for the usual 2 seconds.
- **Base Attack Restriction:** Submarines **cannot** target, attack, or damage the enemy Home Base. Base sieges require surface artillery or Carrier air strikes.

### Carrier Planes
- **Automatic Air Wing:** A Carrier launches on its own at the nearest spotted enemy within plane range (**2028** Supercarrier, **1014** Light). Up to **5** dive-bomber squadrons stack on one target; when a target sinks, its squadrons go straight to another target in range. Select the Carrier and **right-click an enemy** to pick the target yourself; **X** hands the air wing back to automatic targeting.
- **Torpedo Bombers:** every **10 seconds** a flight goes after a spotted Battlecruiser, Battleship, Super Battleship or Carrier (never anything smaller), drops **2 parallel torpedoes** from just off its broadside, aimed straight across it, and flies home.
- **Depth-Charge Bombers:** every **3 seconds** a flight goes after a spotted enemy Submarine, drops a depth charge (100 damage, ignores armor) and flies home.
- **Hovering Dive Bombers:** A squadron launches every **5 seconds** (up to **5** in the air) and can attack anything. It flies at **50% of standard torpedo speed**, circles its target and bombs it every **3 seconds** (**150** damage per bomb run) until the target sinks or is lost, then moves on or flies home and lands.
- **Over Islands:** Planes fly over islands and land, so a strike needs a spotted target within plane range but **no line of sight**. A Carrier spots very little itself, so it relies on the rest of the fleet for targets.
- **Armor Bypass:** High Explosive (HE) bombs **ignore armor damage reduction**, making Carriers a reliable counter to entrenched Battleships.
- **Anti-Air:** Each time a squadron bombs a Light Cruiser, Heavy Cruiser or Battleship, that ship has a **1 in 5 chance** of shooting the squadron down. The **AA Cruiser** (a Light Cruiser with all its guns swapped for flak) goes further: every 3 seconds each enemy squadron within 310 has a **1 in 3 chance** of being shot down.

**Broadsides:** when you right-click an enemy, your gun ships turn to put their broadside toward it once they are in range, so every turret can fire. Ships the computer controls do not do this.

**Battleships, Battlecruisers and Super Battleships cannot target Submarines**: their big guns are useless against a submerged boat, so escort them with Destroyers or Cruisers. Each Battleship also carries **4 secondary guns** on its citadel: destroyer-sized guns that reload at half a destroyer's rate, reach half as far as the main guns (orange range ring) and pick their own target, so a Battleship can fend off destroyers that slip inside while its main guns keep firing at range.

---

## Tech Stack & Development

- **Engine:** Godot 4.7+ (2D)
- **Language:** GDScript

### Getting Started
1. Clone this repository:
   ```bash
   git clone https://github.com/09DylanXie/Operation-Fleetfall.git
   ```
2. Open **Godot Engine 4.x** and import `project.godot`.
3. Press **F5** to run the project, pick the AI difficulty (**Easy**, **Medium** or **Hard**) and choose a map size in the start menu. You play Blue (left) against an AI opponent (Red) on a freshly generated map. **Hard** commands its whole fleet at once; **Medium** can give an order to only one ship at a time (one every 2 seconds) and plans its production less often; **Easy** gives one order every 5 seconds and builds more slowly still.

Optional command-line arguments (after `--`): `--size=small|medium|large` picks the map size, `--difficulty=easy|medium|hard` the AI level, `--seed=N` replays a specific map, `--players=2..4` adds AI fleets, `--ai-vs-ai` lets the AIs play while you spectate. Any of them (or `--skip-menu`) skips the start menu. `--host` opens a LAN lobby and `--join=ADDRESS` joins one (with `--name=NAME`, `--port=N`).

### LAN Multiplayer

Up to four players on one local network, each with a fleet of their own. One player presses **Host LAN Game**. The game appears by itself under **Games on your network** in everyone else's start menu: press its **Join** button. (Typing the host's address into the Join box still works, e.g. if the network blocks broadcasts.) In the lobby the host sets each empty seat to **Open**, **AI** or **Closed**, picks the map size and AI difficulty, and starts the game. Every player picks a **team**: seats on the same team are allies (shared vision, no friendly fire, they win together; banks are separate), so the same lobby plays as a free-for-all, a co-op game against the AI, or 2 vs 2.

- The host's computer runs the battle; the others send their orders to it and show what it sends back, about 15 times a second. Play on a wired or good Wi-Fi LAN.
- The game uses **UDP port 24567**, and **UDP port 24568** for finding games on the network. The first time you host or browse, Windows Firewall asks whether to allow Fleetfall on private networks: allow it, or nobody can join or see your game.
- If a player leaves mid-match, the computer takes over their fleet. If the host leaves, the match ends for everyone. A player whose Home Base falls can keep watching.
- After the match the host can take everyone **Back to Lobby** for another round.

### Controls

| Input | Action |
| :--- | :--- |
| **Left drag** | Box-select ships |
| **Left click** | Select a ship, your Home Base or a captured island (Shift adds to the selection) |
| **Right click** | Move · focus-fire a spotted enemy · Submarines: fire torpedoes at it · Carriers: point the air wing at it · one of your docks: sail there for repairs · with a shipyard selected: set its rally point |
| **1 – 9, 0, -, =** | Build RD / RS / DD / SS / CL / CLAA / CA / BC / BB / SBB / LCV / SCV at the selected shipyard (the shop row, smallest to largest) |
| **U** / **C** | Build or upgrade the selected shipyard / cancel the last queued order (full refund) |
| **X** / **Esc** | Stop the selected ships (a Carrier's air wing goes back to picking its own targets) / clear the selection |
| **P** | Pause / resume (single player only; also the **Pause** button in the top bar) |
| **M** | Sound on / off (also the **Sound** button in the top bar) |
| **R** | Toggle range rings for all your ships (also the **Ranges** switch in the top bar); selected ships always show theirs |
| **H** / **Ctrl+A** | Jump to the Home Base / select every ship |
| **WASD, arrows, middle-drag** | Pan the camera (mouse wheel zooms, click the minimap to jump) |

Neutral islands are captured by holding a ship next to them for 30 seconds with no enemy present (Minor islands sit in shallow water, so only Destroyers and Submarines can reach them). **An island someone owns is fortified** like a small base: it has a garrison with **2000 HP** (Minor) or **4000 HP** (Major) shown as a bar over the island. Shell it, torpedo it or bomb it down to zero (Submarines cannot hurt it) and the island turns neutral, destroying its shipyard; then capture it as usual. The garrison does not shoot back; on an island with a Tier 2 or 3 shipyard it rebuilds (5% of its HP per second) once it has gone 5 seconds without being hit, but a fresh owner gets it back at full strength. A captured island can then be given a shipyard: Tier 1 builds DD/SS/RS/RD, Tier 2 builds CL/CLAA/CA/LCV, Tier 3 (Major islands only) builds BC/BB/SBB/SCV. Each tier's dock looks different, from a timber jetty to a full naval base. Only one of your Resource Ships can mine any one island (another side's can share it). Build orders are paid in full when you queue them (you cannot queue what you cannot afford) and refunded in full if you cancel them, even the ship already on the slip. A yard lays down the next order the moment the previous ship launches.

**Island defenses:** a Major island with a Tier 3 shipyard becomes an **air base**: it sends up to 3 squadrons of HE dive bombers (one every 10 seconds) after enemy ships that shell it from within about a cruiser's range. Its owner can also buy **radar** for it (200 Gold / 150 Steel, from the island's panel), which lets the island spot as far as a Destroyer. Both are lost if the island falls.

**Docks and repairs.** Every island and Home Base has a small dock where its ships are launched. Right-click one of your docks with ships selected to send them in: a ship inside the dock ring regains **2% of its hull per second**, provided the shipyard there could build that class (a Battleship gets nothing from a Tier 2 yard) and the yard is **not building** anything at the moment.

**Range rings.** Selected ships show their reach as rings: gold for guns, cyan for torpedoes, violet for aircraft. Enemy ranges are never shown. The **Menu** button in the top bar (click twice) and the end screen both lead back to the start menu.

### Look and Feel

Everything is drawn in-engine, no image files. Each class has its own top-down design inspired by a WWII ship: Benson-class destroyers with four single gun houses, a Type XXI U-boat, a British light cruiser, an Admiral Hipper/Lutzow-type heavy cruiser, a Scharnhorst-style battleship (Bismarck lines, three turrets), an Italian battlecruiser with red-and-white bow stripes, a Yamato-type super battleship with its teak deck, and a Shinano-type carrier. Small ships wear dark greys; the big capital ships get lighter paint and wooden decks. Turrets turn toward their target (big turrets on slow hulls turn slowly), damaged ships burn and smoke more as they lose HP, and cruisers and larger roll over and sink when destroyed. Shells are grey AP rounds with a short fading tracer. The sea is animated, its swell rocks every hull a few pixels back and forth, islands are Pacific-style jungle islands with airfields and outposts, docks are concrete wharves built out from the shore, and storms swirl with rain, wind and lightning.

**Sound** is synthesised in code too: gunfire that grows heavier with the calibre, shell splashes, hits, torpedo and depth-charge blasts, bombs, flak, aircraft, ship explosions, a rolling ocean ambience, wind and rain when the camera is in a storm, and interface cues for clicks, captured or lost islands, launched ships and a Home Base under fire. Only what you can see is heard. **The interface** uses navy-and-brass panels with raised buttons that light up and press in, resource chips with icons that flash when your bank changes, an HP gauge for the selection, build cards showing each ship, a production bar, banner notices and an animated sea behind the menus.

### Project Layout

| Path | Contents |
| :--- | :--- |
| `data/` | All balance numbers as Godot `Resource` files: `balance.tres`, `map_config.tres` (medium map), `maps/small.tres`, `maps/large.tres`, `ships/*.tres` |
| `scripts/` | `core`, `resources`, `map`, `combat`, `ships`, `projectiles`, `economy`, `environment`, `match`, `ai`, `net` (LAN session and snapshots), `audio` (synthesised sound), `ui` |
| `scenes/` | `menu.tscn` (start menu, the project's main scene), `lobby.tscn` (LAN lobby), `main.tscn` (the match) plus `ships/`, `environment/`, `projectiles/`, `ui/` |
| `tests/` | Headless rule tests, an AI-vs-AI soak test and a windowed screenshot/performance check |

### Tests

```bash
# Rule tests: every design-document rule driven through the live simulation
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn

# Full AI-vs-AI match, fast-forwarded (fails on rule violations or if nobody wins)
godot --headless --path . --fixed-fps 60 res://tests/sim_match.tscn -- --seed=3 --size=large
# ...with per-side difficulty (also --difficulty=X for both)
godot --headless --path . --fixed-fps 60 res://tests/sim_match.tscn -- --seed=3 --difficulty0=hard --difficulty1=easy

# Game flow: start menu -> Medium -> victory -> New Match -> defeat -> Main Menu -> Small -> Large
godot --headless --path . --fixed-fps 60 res://tests/match_flow.tscn

# Balance duel: two squads fight it out on open water (add --pass to make A sail past B)
godot --headless --path . --fixed-fps 60 res://tests/duel.tscn -- --a=DD:5 --b=CL:2

# Three or four AI fleets on one round sea
godot --headless --path . --fixed-fps 60 res://tests/sim_match.tscn -- --seed=1 --players=4

# LAN over real sockets on one machine: one host and two clients (separate processes)
godot --headless --path . res://tests/net_check.tscn -- --role=host --clients=2 --ai=1 --seconds=80
godot --headless --path . res://tests/net_check.tscn -- --role=client --name=Ann --seconds=75
godot --headless --path . res://tests/net_check.tscn -- --role=client --name=Bob --quit-at=40
# Options: --rounds=2 (back to the lobby and play again), --team=N (client picks a team),
# --via-menu with --host / --join=127.0.0.1 (go through the real start menu), --coop,
# --discover (client finds the game in the menu's LAN list and presses Join)

# Windowed 30-vs-30 battle: saves screenshots and prints frame times
godot --path . --resolution 1920x1080 res://tests/visual_check.tscn -- --out=C:/some/folder
```

---

## License

Copyright © Dylan Xie. All Rights Reserved.

This project and its source code, assets, and design documents are proprietary and confidential. Unauthorized copying, modification, distribution, or commercial use is strictly prohibited without prior written permission from the author.
