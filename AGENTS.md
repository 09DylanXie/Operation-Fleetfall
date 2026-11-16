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
| **Destroyer** | `DD` | 100 | 50 | 15.0s | 100% | 0% | 2x Single + Auto Torps | 4.0s | Low / Low |
| **Submarine** | `SS` | 150 | 75 | 20.0s | 50% | 0% | Manual Torps Only | 20.0s | N/A |
| **Light Cruiser** | `CL` | 250 | 150 | 30.0s | 70% | 5% | 3x Triple | 6.0s | High / Medium |
| **Heavy Cruiser** | `CA` | 400 | 250 | 45.0s | 50% | 15% | 4x Double | 8.0s | High / High |
| **Battleship** | `BB` | 800 | 600 | 90.0s | 30% | 25% | 3x Double | 16.0s | Massive / Extreme |
| **Carrier** | `CV` | 1000 | 400 | 120.0s | 90% | 0% | Plane Squadrons | 25.0s | High (HE Bombs) |

---

## 4. Specialty Weapon Systems

### Torpedoes
- **Damage:** `1.30 * single_battleship_shell_damage` (30% more than a single BB shell).
- **Speed:** Slightly slower than Battleship shells.
- **Destroyer (`DD`) Torpedoes:**
  - Fire **automatically** every `30.0` seconds.
  - Launch **only** from port (left) or starboard (right) broadsides. Player must position the DD broadside to the enemy.
- **Submarine (`SS`) Torpedoes:**
  - Fired **manually** by the player.
  - Launch **only** from bow (front) or stern (rear) tubes.
  - **Homing Ping:** Actively homes in on the target for the first `2.0` seconds of travel, then locks trajectory and travels in a straight line.
  - **Reveal Penalty:** Launching a torpedo immediately reveals the Submarine to the entire enemy team for `15.0` seconds.

### Submarine (`SS`) Stealth & Restrictions
- **Stealth State:** Invisible to enemies unless within detection range of an enemy **Destroyer (`DD`)** or **Island Shipyard** (or during the 15s torpedo reveal penalty).
- **Base Attack Restriction:** Submarines **cannot** target, attack, or damage the enemy Home Base.

### Carrier (`CV`) Planes (HE Bombs)
- **Mechanic:** CVs do not fire shells or torpedoes; they launch plane squadrons that act as moving projectiles.
- **Speed:** `0.50 * torpedo_speed` (50% of torpedo speed).
- **Payload:** Drop High Explosive (HE) bombs dealing slightly more damage than a Heavy Cruiser (`CA`) full salvo.
- **Armor Bypass:** HE Bombs **ignore standard armor damage reduction**, countering heavily armored Battleships.

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
