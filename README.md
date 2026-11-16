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
- **Fog of War:** The entire map is shrouded in fog. Each ship class has an intrinsic spotting range—fast, lightly armored ships must scout ahead to spot targets for heavy artillery.
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
| **Light Cruiser (CL)** | 250 G / 150 S | 30s | 70% | 5% | 3x Triple Guns | 6.0s | High / Medium |
| **Heavy Cruiser (CA)** | 400 G / 250 S | 45s | 50% | 15% | 4x Double Guns | 8.0s | High / High |
| **Battleship (BB)** | 800 G / 600 S | 90s | 30% | 25% | 3x Double Guns | 16.0s | Massive / Extreme |
| **Carrier (CV)** | 1000 G / 400 S | 120s | 90% | 0% | Plane Squadrons | 25.0s | High (HE Bombs) |

---

## Specialty Weapon Systems

### Torpedoes
- **Payload & Speed:** Deal **30% more damage** than a single Battleship shell and travel slightly slower than Battleship shells.
- **Destroyer Deployment:** Fire automatically every **30 seconds**, launching only from the port (left) or starboard (right) broadsides—requiring players to angle the Destroyer broadside to the target.
- **Submarine Deployment:** Fired manually by the player from bow (front) or stern (rear) tubes.

### Submarine Stealth & Restrictions
- **Stealth State:** Completely invisible to the enemy unless they approach too close to an enemy **Destroyer** or **Island Shipyard**.
- **Homing Ping:** Manually fired submarine torpedoes actively home in on the selected target for the **first 2 seconds** of travel before locking onto a straight trajectory.
- **Reveal Penalty:** Firing a torpedo immediately reveals the Submarine to the entire enemy team for **15 seconds**.
- **Base Attack Restriction:** Submarines **cannot** target, attack, or damage the enemy Home Base. Base sieges require surface artillery or Carrier air strikes.

### Carrier Planes (HE Bombs)
- **Squadron Projectiles:** Aircraft Carriers launch plane squadrons that travel at **50% of torpedo speed**.
- **Armor Bypass:** Planes drop High Explosive (HE) bombs dealing slightly more damage than a Heavy Cruiser's full salvo and **ignoring standard armor damage reduction**, making Carriers a reliable counter to entrenched Battleships.

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
3. Press **F5** to run the project.

---

## License

Copyright © Dylan Xie. All Rights Reserved.

This project and its source code, assets, and design documents are proprietary and confidential. Unauthorized copying, modification, distribution, or commercial use is strictly prohibited without prior written permission from the author.
