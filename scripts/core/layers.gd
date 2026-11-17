class_name Layers
extends RefCounted
## Physics layer bitmasks. Layer N in the editor is bit value 1 << (N - 1).
## Layers 1-6 follow AGENTS.md; 7-8 are per-team hitboxes so a projectile ray
## can ignore friendly hulls without building an exclusion list.

const WATER: int = 1 << 0
const SHALLOW: int = 1 << 1
const ISLANDS: int = 1 << 2
const SHIPS: int = 1 << 3
const PROJECTILES: int = 1 << 4
const VISION: int = 1 << 5
const TEAM_0_HITBOX: int = 1 << 6
const TEAM_1_HITBOX: int = 1 << 7


static func team_hitbox(team: int) -> int:
	return TEAM_0_HITBOX if team == 0 else TEAM_1_HITBOX


static func enemy_hitbox(team: int) -> int:
	return TEAM_1_HITBOX if team == 0 else TEAM_0_HITBOX
