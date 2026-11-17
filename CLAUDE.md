# CLAUDE.md — Operation: Fleetfall

Read and follow all architectural rules, game design invariants, and GDScript coding conventions in [AGENTS.md](./AGENTS.md).

## Quick Reference

- **Engine:** Godot 4.7.2 (2D, GDScript with strict static typing)
- **Concept:** 2D WWII Naval RTS combining *Empire at War* macro territory control with *World of Warships* micro positioning, turret/broadside angles, and line-of-sight island cover.
- **Key Mechanics to Respect:**
  - **30-ship fleet cap** per player; ships under construction are defenseless.
  - **15-second economy tick** granting Gold and Steel based on captured Minor (Shallow Water) and Major (Deep Water) islands.
  - **Islands block both vision and projectiles** (hard cover).
  - **Focus-Fire Armor Stripping:** `-5%` armor per additional attacker beyond the first.
  - **Class-specific weapons:** Broadside auto-torpedoes on Destroyers (`30s` cooldown, half torpedo speed), bow/stern manual homing-ping torpedoes on Submarines (`2s` homing + `15s` reveal penalty, cannot attack Home Base), Destroyer depth charges that automatically hit spotted Submarines within `180` range, and Carrier squadrons that launch **automatically** at the nearest spotted enemy in plane range (one every `10s`, up to `5` airborne; a right-click overrides the target), hover over the target bombing every `3s` with armor-bypassing HE bombs (`150` damage), fly over islands, and can be shot down by CL/CA/BB anti-air (1 in 5 per bomb run).
  - **Battleships cannot target Submarines.**
  - **Spotting:** `DD 720`, `CL`/`CA 360`, `BB 240`, `CV 80`, `SS 0` - Destroyers scout for everything else.
  - **Docks:** a ship in a friendly dock repairs `2%` HP/s only if that shipyard's tier can build its class and the yard is not building.
  - **Start menu** (`scenes/menu.tscn`) picks the Small / Medium / Large map preset; `scenes/main.tscn` is the match.
  - **Fortified islands:** an owned island has a garrison (`2000` HP Minor / `4000` Major) that must be shot to 0 (subs cannot hurt it); the island then turns neutral, losing its shipyard, and only a neutral island can be captured.
  - **AI difficulty:** Hard = original AI; Easy and Medium give an order to only one ship at a time (Medium 1/s, Easy 1 per 3s). Menu picks it; `--difficulty=easy|medium|hard`.
  - **30-second island capture** (neutral islands only); build orders are **paid when construction starts** and the next order starts the moment the previous ship launches.

Refer to [AGENTS.md](./AGENTS.md) for the complete Fleet Roster table, resource rates, and Godot 4 collision/architecture guidelines.
