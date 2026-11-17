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
- **Fleet Cap:** Maximum **30 ships** per player at any time.
- **Vulnerable Construction:** Ships under construction cannot defend themselves.

### Map, Vision & Environment
- **Procedural Archipelagos:** Map layout is procedurally generated each match.
- **Hard Cover (Line of Sight):** Islands physically block **both** spotting vision and artillery projectiles. Ships can use islands to break spotting or limit how many enemy turrets have a firing angle.
- **Fog of War:** The entire map is covered in fog. Ships only reveal enemies within their intrinsic spotting range (unless revealed by a penalty, such as a Submarine firing a torpedo).
- **Spotting Ranges (`spotting_range`):** `DD 720`, `CL`/`CA 360` (half a DD), `BB 240` (two thirds of a cruiser), `CV 80` (one third of a BB), `SS 0` (submarines spot nothing and are not vision sources). The local player's own low-vision ships still clear a small fog disc (`VisionSystem.OWN_SHIP_FOG_RADIUS`) so they are never drawn under fog; that disc reveals no enemies.
- **Map Sizes:** `MapConfig.Size { SMALL, MEDIUM, LARGE }`, chosen in the start menu and held in `GameSettings.map_size`. Presets: `data/maps/small.tres`, `data/map_config.tres` (medium) and `data/maps/large.tres`, loaded with `GameData.map_config_for(size)`. Never mutate a cached config.
- **Range Rings:** Ships draw their weapon reach (gold guns, cyan torpedoes, violet aircraft) only for the local player's own ships: when selected, or for all of them while `Match.show_all_ranges` is on (top-bar switch / `R`). Enemy ranges are never drawn.
- **Dynamic Weather:** Roaming weather fronts (e.g., cyclones) drastically reduce the spotting range of any ships inside them.
- **Island Access Restrictions:**
  - **Shallow Water Islands (Minor):** Accessible **only** by Destroyers (`DD`) and Submarines (`SS`).
  - **Deep Water Islands (Major):** Required to construct Tier 3 Shipyards for capital ships (`BB`, `CV`).

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
| **Destroyer** | `DD` | 100 | 50 | 15.0s | 100% | 0% | 2x Single + Auto Torps + Depth Charges | 4.0s | Low / Low |
| **Submarine** | `SS` | 150 | 75 | 20.0s | 50% | 0% | Manual Torps Only | 20.0s | N/A |
| **Light Cruiser** | `CL` | 250 | 150 | 30.0s | 70% | 5% | 3x Triple | 4.0s | High / Medium |
| **Heavy Cruiser** | `CA` | 400 | 250 | 45.0s | 50% | 15% | 4x Double | 5.333s | High / High |
| **Battleship** | `BB` | 800 | 600 | 90.0s | 30% | 25% | 3x Double | 8.0s | Massive / Extreme |
| **Carrier** | `CV` | 1000 | 400 | 120.0s | 90% | 0% | Plane Squadrons | 10.0s | High (HE Bombs) |

Battleships cannot target Submarines (`ShipStats.can_target_submarines = false`; `Ship.can_engage()`): their guns never pick a sub and attack orders on one are refused. A stray BB shell can still hit one.

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

### Destroyer (`DD`) Depth Charges
- Dropped **automatically** on the nearest spotted enemy Submarine within `depth_charge_range` (`180`): `depth_charge_damage` (`100`, ignores armor) every `depth_charge_interval` (`2.5s`). Hulls under construction do not drop them.
- A DD with an attack order on a Submarine closes to inside depth-charge range instead of holding at gun range.

### Submarine (`SS`) Stealth & Restrictions
- **Stealth State:** Invisible to enemies unless within detection range of an enemy **Destroyer (`DD`)** or **Island Shipyard** (or during the 15s torpedo reveal penalty).
- **Base Attack Restriction:** Submarines **cannot** target, attack, or damage the enemy Home Base.

### Carrier (`CV`) Planes (HE Bombs)
- **Mechanic:** CVs do not fire shells or torpedoes. The air wing works **automatically**: with no order it picks the nearest spotted enemy within plane range (`Ship.air_target()`). The player can override it by selecting the CV and right-clicking an enemy (`Ship.order_attack` / `order_strike`); the override lasts until that target dies or is lost. Stop (`X`, `Ship.clear_strike()`) hands the wing back to automatic targeting.
- **Launch:** One squadron every `10.0` seconds while the air target is spotted and within plane range, up to `5` squadrons airborne per carrier.
- **Hover:** A squadron flies to the target, circles it and bombs every `3.0` seconds (`bomb_interval`) for `bomb_damage` (`150`) per run, follows the carrier's current air target, and returns to its carrier and lands when there is none. Squadrons are lost if their carrier sinks.
- **Speed:** `0.50 * torpedo_speed` (50% of the standard torpedo speed).
- **Terrain:** Planes fly over islands and land. A strike needs no line of sight (the target must still be spotted).
- **Armor Bypass:** HE Bombs **ignore standard armor damage reduction**, countering heavily armored Battleships.
- **Anti-Air:** After each bomb run on a `CL`, `CA` or `BB` (`aa_kill_chance = 0.2`) the squadron has a 1-in-5 chance of being shot down. Hulls under construction and the Home Base have no anti-air.

### Capture & Build Queue
- **Capture:** Only a **neutral** island is captured, by holding it uncontested for `30.0` seconds (`capture_time`).
- **Fortified islands:** An owned island is a mini base. Its `IslandGarrison` (a `Combatant` under the bases root, one per capturable island) has `minor_garrison_hp` (`2000`) or `major_garrison_hp` (`4000`), no armor, no weapons and no regeneration. Enemies cannot capture it by sitting on it: shells and torpedoes that strike the island's shore damage the garrison, and bombs hit it like any target. Submarines can neither target nor damage it (`Combatant.is_structure()`). It is spotted like a ship (its own island does not block the line of sight to it, `Combatant.los_blocker()`), and an attack order on it closes in even when unspotted, like the Home Base. At 0 HP the island turns **neutral**: its shipyard, queue and any hull on the slip are lost, and the normal 30 s hold captures it. A new owner always gets a full-HP garrison. Islands never change hands directly from one team to the other.
- **Build queue:** Orders are paid for when construction **starts**, not when queued. A yard starts the next order in the same tick the previous one finishes, and waits (keeping the order) while the bank cannot cover it. Only orders that have not started can be cancelled; they cost nothing. Queued orders count toward the fleet cap.

### Docks & Repairs
- **Dock:** Every capturable island and Home Base has a dock (`Shipyard.slip_position`, drawn by `DockArt`) where its ships are built and launched.
- **Repair:** A friendly, finished ship within `dock_radius` (`220`) of the slip regains `repair_rate` (`2%` of max HP) per second, only if **both** hold:
  - the shipyard's tier can build that ship class (a `BB` cannot repair at a Tier 2 yard; an island with no shipyard repairs nothing);
  - the shipyard is **not building** (no paid ship or upgrade order in progress; unpaid waiting orders do not block).
- **Orders:** Right-clicking an own dock sends the selected ships to `Shipyard.dock_point()` (`Match.order_group_dock`). The AI does not use docks.
- **Size:** Docks are kept small (`DockArt.BERTH_HALF_LENGTH 20`, `Match.SLIP_OFFSET 70`) so they do not get in the way.

### AI Difficulty
- `GameSettings.ai_difficulty` (`EASY`, `MEDIUM`, `HARD`; per team via `Match.ai_difficulty`). **Hard** is the original, full-strength AI and the default for headless runs and tests; the start menu preselects Medium.
- **Easy and Medium may control only one ship at a time.** Every AI ship order passes through `AIController._command`: on Hard it is sent at once; on Easy/Medium the orders wanted during a think are collected and only one is sent, to the ship that has waited longest. Medium sends one order per second (`ORDER_INTERVAL_MEDIUM`), Easy one every 3 s (`ORDER_INTERVAL_EASY`) and only plans production every 4th think. Ships still fire, launch planes and drop depth charges on their own. Never call ship order methods from the AI outside `_command`.

### Start Menu
- `scenes/menu.tscn` (`MainMenu`) is the project's main scene; it sets `GameSettings.map_size` and changes to `scenes/main.tscn` (the `Match` root). It also sets `GameSettings.ai_difficulty`. User args `--size=`, `--difficulty=`, `--seed=`, `--ai-vs-ai` or `--skip-menu` skip it (once, at launch).

---

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
