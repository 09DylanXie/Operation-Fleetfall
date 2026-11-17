# Operation: Fleetfall

**Operation: Fleetfall** is a 2D World War II naval real-time strategy (RTS) game built in **Godot 4 (GDScript)**. It merges the macro territory control of *Star Wars: Empire at War* with the micro fleet positioning, line-of-sight mechanics, and ship class dynamics of *World of Warships*.

---

## Core Vision & Gameplay Loop

- **Objective:** Destroy the enemy's Home Base.
- **Core Loop:** Expand from your Home Base, capture strategic island resource nodes, construct tech-specific shipyards, and out-maneuver the opposing fleet using island cover, fog of war, dynamic weather, and coordinated focus fire.
- **Fleet Cap:** **30 ships maximum** per player to prevent unit spam and make every loss tactically meaningful. Ships under construction cannot defend themselves.

---

## Map & Environment

- **Procedural Archipelagos:** Every match generates a unique island layout. Islands act as **hard cover**, physically blocking both spotting vision and artillery shells.
- **Fog of War:** The entire map is shrouded in fog. Each ship class has an intrinsic spotting range—fast, lightly armored ships must scout ahead to spot targets for heavy artillery. Destroyers are the eyes of the fleet: a Cruiser spots **half** as far as a Destroyer, a Battleship **two thirds** as far as a Cruiser, a Carrier **one third** as far as a Battleship, and a Submarine spots **nothing** at all.
- **Map Sizes:** The start menu offers **Small** (4200 x 2400, 5 capturable islands), **Medium** (6400 x 3600, 7) and **Large** (9000 x 5000, 11) archipelagos.
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
| **Destroyer (DD)** | 100 G / 50 S | 15s | 100% | 0% | 2x Single Guns + Torps | 4.0s | Low / Low |
| **Submarine (SS)** | 150 G / 75 S | 20s | 50% | 0% | Torpedoes Only | 20.0s | N/A (Torpedo) |
| **Light Cruiser (CL)** | 250 G / 150 S | 30s | 70% | 5% | 3x Triple Guns | 4.0s | High / Medium |
| **Heavy Cruiser (CA)** | 400 G / 250 S | 45s | 50% | 15% | 4x Double Guns | 5.3s | High / High |
| **Battleship (BB)** | 800 G / 600 S | 90s | 30% | 25% | 3x Double Guns | 8.0s | Massive / Extreme |
| **Carrier (CV)** | 1000 G / 400 S | 120s | 90% | 0% | Plane Squadrons | 10.0s | High (HE Bombs) |

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
- **Base Attack Restriction:** Submarines **cannot** target, attack, or damage the enemy Home Base. Base sieges require surface artillery or Carrier air strikes.

### Carrier Planes (HE Bombs)
- **Automatic Air Wing:** A Carrier launches on its own at the nearest spotted enemy within plane range. Select the Carrier and **right-click an enemy** to pick the target yourself; **X** hands the air wing back to automatic targeting.
- **Hovering Squadrons:** A squadron launches every **10 seconds** (up to **5** in the air), flies at **50% of standard torpedo speed**, circles its target and bombs it every **3 seconds** (**150** damage per bomb run) until the target sinks or is lost, then moves on or flies home and lands.
- **Over Islands:** Planes fly over islands and land, so a strike needs a spotted target within plane range but **no line of sight**. A Carrier spots very little itself, so it relies on the rest of the fleet for targets.
- **Armor Bypass:** High Explosive (HE) bombs **ignore armor damage reduction**, making Carriers a reliable counter to entrenched Battleships.
- **Anti-Air:** Each time a squadron bombs a Light Cruiser, Heavy Cruiser or Battleship, that ship has a **1 in 5 chance** of shooting the squadron down.

**Battleships cannot target Submarines**: their big guns are useless against a submerged boat, so escort them with Destroyers or Cruisers.

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
3. Press **F5** to run the project, pick the AI difficulty (**Easy**, **Medium** or **Hard**) and choose a map size in the start menu. You play Blue (left) against an AI opponent (Red) on a freshly generated map. **Hard** commands its whole fleet at once; **Medium** can give an order to only one ship at a time (one per second); **Easy** gives one order every 3 seconds and builds more slowly.

Optional command-line arguments (after `--`): `--size=small|medium|large` picks the map size, `--difficulty=easy|medium|hard` the AI level, `--seed=N` replays a specific map, `--ai-vs-ai` lets two AIs play while you spectate. Any of them (or `--skip-menu`) skips the start menu.

### Controls

| Input | Action |
| :--- | :--- |
| **Left drag** | Box-select ships |
| **Left click** | Select a ship, your Home Base or a captured island (Shift adds to the selection) |
| **Right click** | Move · focus-fire a spotted enemy · Submarines: fire torpedoes at it · Carriers: point the air wing at it · one of your docks: sail there for repairs · with a shipyard selected: set its rally point |
| **1 – 6** | Build DD / SS / CL / CA / BB / CV at the selected shipyard |
| **U** / **C** | Build or upgrade the selected shipyard / cancel the last queued order that has not started yet |
| **X** / **Esc** | Stop the selected ships (a Carrier's air wing goes back to picking its own targets) / clear the selection |
| **R** | Toggle range rings for all your ships (also the **Ranges** switch in the top bar); selected ships always show theirs |
| **H** / **Ctrl+A** | Jump to the Home Base / select every ship |
| **WASD, arrows, middle-drag** | Pan the camera (mouse wheel zooms, click the minimap to jump) |

Neutral islands are captured by holding a ship next to them for 30 seconds with no enemy present (Minor islands sit in shallow water, so only Destroyers and Submarines can reach them). **An island someone owns is fortified** like a small base: it has a garrison with **2000 HP** (Minor) or **4000 HP** (Major) shown as a bar over the island. Shell it, torpedo it or bomb it down to zero (Submarines cannot hurt it) and the island turns neutral, destroying its shipyard; then capture it as usual. The garrison does not shoot back and does not heal, but a fresh owner gets it back at full strength. A captured island can then be given a shipyard: Tier 1 builds DD/SS, Tier 2 builds CL/CA, Tier 3 (Major islands only) builds BB/CV. Build orders are paid for when their construction starts, not when they are queued: a yard lays down the next order the moment the previous ship launches, and waits if the bank cannot cover it yet.

**Docks and repairs.** Every island and Home Base has a small dock where its ships are launched. Right-click one of your docks with ships selected to send them in: a ship inside the dock ring regains **2% of its hull per second**, provided the shipyard there could build that class (a Battleship gets nothing from a Tier 2 yard) and the yard is **not building** anything at the moment.

**Range rings.** Selected ships show their reach as rings: gold for guns, cyan for torpedoes, violet for aircraft. Enemy ranges are never shown. The **Menu** button in the top bar (click twice) and the end screen both lead back to the start menu.

### Project Layout

| Path | Contents |
| :--- | :--- |
| `data/` | All balance numbers as Godot `Resource` files: `balance.tres`, `map_config.tres` (medium map), `maps/small.tres`, `maps/large.tres`, `ships/*.tres` |
| `scripts/` | `core`, `resources`, `map`, `combat`, `ships`, `projectiles`, `economy`, `environment`, `match`, `ai`, `ui` |
| `scenes/` | `menu.tscn` (start menu, the project's main scene), `main.tscn` (the match) plus `ships/`, `environment/`, `projectiles/`, `ui/` |
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

# Windowed 30-vs-30 battle: saves screenshots and prints frame times
godot --path . --resolution 1600x900 res://tests/visual_check.tscn -- --out=C:/some/folder
```

---

## License

Copyright © Dylan Xie. All Rights Reserved.

This project and its source code, assets, and design documents are proprietary and confidential. Unauthorized copying, modification, distribution, or commercial use is strictly prohibited without prior written permission from the author.
