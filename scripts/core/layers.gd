class_name Layers
extends RefCounted
## Physics layer bitmasks. Layer N in the editor is bit value 1 << (N - 1).
## Layers 1-6 follow AGENTS.md; 7-10 are per-team hitboxes so a projectile ray
## can ignore friendly hulls without building an exclusion list.

## Most sides a match can have (one hitbox layer each).
const MAX_TEAMS: int = 4

const WATER: int = 1 << 0
const SHALLOW: int = 1 << 1
const ISLANDS: int = 1 << 2
const SHIPS: int = 1 << 3
const PROJECTILES: int = 1 << 4
const VISION: int = 1 << 5
const TEAM_0_HITBOX: int = 1 << 6


static func team_hitbox(team: int) -> int:
	return TEAM_0_HITBOX << team
