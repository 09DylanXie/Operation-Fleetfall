class_name GameSettings
extends RefCounted
## Choices made in the start menu. They outlive scene changes, so "New Match" keeps them.

const MENU_SCENE: String = "res://scenes/menu.tscn"
const MATCH_SCENE: String = "res://scenes/main.tscn"

enum Difficulty { EASY, MEDIUM, HARD }

static var map_size: MapConfig.Size = MapConfig.Size.MEDIUM
## Skill of the computer opponent. Hard is the full-strength AI; Easy and Medium may only
## give an order to one ship at a time. Headless runs and tests default to Hard; the start
## menu preselects Medium.
static var ai_difficulty: Difficulty = Difficulty.HARD
## True once the start menu has been shown. From then on the menu owns the map size and
## the command line no longer skips it, so "Main Menu" really returns to the menu.
static var menu_shown: bool = false


## Parses "small" / "medium" / "large" (as used by the --size= command-line argument).
static func size_from_name(text: String) -> MapConfig.Size:
	match text.to_lower():
		"small", "s":
			return MapConfig.Size.SMALL
		"large", "l":
			return MapConfig.Size.LARGE
	return MapConfig.Size.MEDIUM


## Parses "easy" / "medium" / "hard" (the --difficulty= command-line argument).
static func difficulty_from_name(text: String) -> Difficulty:
	match text.to_lower():
		"easy", "e":
			return Difficulty.EASY
		"medium", "m", "normal":
			return Difficulty.MEDIUM
	return Difficulty.HARD


static func difficulty_name(level: Difficulty) -> String:
	match level:
		Difficulty.EASY:
			return "Easy"
		Difficulty.MEDIUM:
			return "Medium"
	return "Hard"


static func size_name(size: MapConfig.Size) -> String:
	match size:
		MapConfig.Size.SMALL:
			return "Small"
		MapConfig.Size.LARGE:
			return "Large"
	return "Medium"
