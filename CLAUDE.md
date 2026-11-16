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
  - **Class-specific weapons:** Broadside auto-torpedoes on Destroyers (`30s` cooldown), bow/stern manual homing-ping torpedoes on Submarines (`2s` homing + `15s` reveal penalty, cannot attack Home Base), and armor-bypassing HE bomb squadrons on Carriers.

Refer to [AGENTS.md](./AGENTS.md) for the complete Fleet Roster table, resource rates, and Godot 4 collision/architecture guidelines.
