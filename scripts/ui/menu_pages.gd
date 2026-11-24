class_name MenuPages
extends RefCounted
## The start menu's information pages: How to Play (controls, rules, the fleet roster) and
## Credits (the soundtrack's composers, engine notice). Text is BBCode for a RichTextLabel;
## numbers come from `GameData` so the guide stays in step with the balance files.

const ROLES: Dictionary[String, String] = {
	"RD": "Unarmed radar picket. Spots surface ships very far and sees over islands.",
	"RS": "Unarmed. Anchor it beside a Minor island you do not own to mine its income (one per island).",
	"DD": "Fast scout with the best eyes. Guns, automatic broadside torpedoes, depth charges for subs. Reaches shallow water.",
	"SS": "Hidden unless enemies come close. Fires 3 homing torpedoes. Spots nothing; cannot hurt bases or garrisons.",
	"CL": "Quick, hard-hitting cruiser with anti-air guns.",
	"CLAA": "No guns: a flak barrage that shreds enemy squadrons. Escort it with your carriers or battle line.",
	"CA": "Tougher, longer-ranged cruiser with anti-air guns.",
	"BC": "Fast capital ship with many guns but thin armour and lighter shells. Cannot target submarines.",
	"BB": "Heavy armour, huge guns and secondary batteries. Cannot target submarines.",
	"SBB": "The biggest guns and thickest armour, slow, with its own flak. At most 3 at a time.",
	"LCV": "Light carrier. Its air wing strikes spotted enemies automatically, far beyond gun range.",
	"SCV": "Supercarrier: a huge air wing of dive, torpedo and depth-charge bombers. At most 2 at a time, 4 per game.",
}

const H1: String = "[font_size=26][color=#ffd65c]%s[/color][/font_size]\n"
const KEY: String = "[color=#ffe7a8][b]%s[/b][/color]"


## The How to Play page.
static func guide_bbcode() -> String:
	var b: GameBalance = GameData.balance()
	var t: String = ""
	t += H1 % "Your goal"
	t += "Sink the enemy [b]Home Base[/b]. Lose yours and you are out. Capture islands for income, build shipyards on them, and use scouting, island cover and focus fire to win the battle at sea.\n\n"

	t += H1 % "Your first minutes"
	t += "1. Press %s to select your Home Base, then build a couple of %s with the number keys or the build cards at the bottom.\n" % [KEY % "H", KEY % "Destroyers"]
	t += "2. Send ships next to a [b]neutral island[/b] and keep them there for %d seconds with no enemy close by to capture it. Minor islands sit in shallow water: only Destroyers and Submarines reach them.\n" % int(b.capture_time)
	t += "3. Select a captured island and press %s to build a shipyard on it, then %s again to upgrade it for bigger ships.\n" % [KEY % "U", KEY % "U"]
	t += "4. Build a %s and park it by a Minor island you do not own for extra income.\n" % (KEY % "Resource Ship")
	t += "5. Scout ahead with Destroyers: big ships see very little on their own. Then bring the heavy hitters.\n\n"

	t += H1 % "Controls"
	t += "[table=2]"
	for row: Array in [
		["Left click / drag", "Select a ship, base or island / box-select ships (Shift adds)"],
		["Right click", "Move; attack a spotted enemy (gun ships turn broadside); send ships to one of your docks for repairs; with a shipyard selected, set its rally point"],
		["1 - 9, 0, -, =", "Build at the selected shipyard (the build cards, smallest to largest)"],
		["U / C", "Build or upgrade the selected shipyard / cancel the last order (full refund)"],
		["X / Esc", "Stop the selected ships / clear the selection"],
		["H / Ctrl+A", "Jump to your Home Base / select every ship"],
		["R", "Range rings on all your ships (gold guns, cyan torpedoes, violet aircraft)"],
		["WASD, arrows, middle-drag", "Pan the camera (mouse wheel, trackpad two-finger scroll or pinch zooms; click the minimap to jump)"],
		["P", "Pause (single player)"],
		["M", "Mute everything (the Sound button sets music and effects volume)"],
	]:
		t += "[cell][color=#ffe7a8][b]%s[/b][/color]   [/cell][cell]%s[/cell]" % [row[0], row[1]]
	t += "[/table]\n\n"

	t += H1 % "Economy"
	t += "Gold and Steel arrive every %d seconds from what you hold. Build orders are paid in full when queued and refunded in full if cancelled.\n" % int(b.tick_interval)
	t += "[table=3]"
	t += "[cell][b]Source[/b]   [/cell][cell][b]Gold[/b]   [/cell][cell][b]Steel[/b][/cell]"
	t += "[cell]Home Base   [/cell][cell]+%d   [/cell][cell]+%d[/cell]" % [b.home_gold, b.home_steel]
	t += "[cell]Minor island (shallow)   [/cell][cell]+%d   [/cell][cell]+%d[/cell]" % [b.minor_gold, b.minor_steel]
	t += "[cell]Major island (deep)   [/cell][cell]+%d   [/cell][cell]+%d[/cell]" % [b.major_gold, b.major_steel]
	t += "[/table]\n"
	t += "Fleet cap: [b]%d ships[/b], +%d for every Major island you own.\n\n" % [b.fleet_cap, b.major_island_fleet_bonus]

	t += H1 % "Islands and shipyards"
	t += "[b]Tier 1[/b] yards build Radar Ships, Resource Ships, Destroyers and Submarines; [b]Tier 2[/b] adds cruisers and the Light Carrier; [b]Tier 3[/b] (Major islands only) adds Battlecruisers, Battleships, Super Battleships and the Supercarrier. Minor islands stop at Tier %d and your Home Base at Tier %d.\n" % [b.minor_shipyard_max_tier, b.home_shipyard_max_tier]
	t += "An owned island is [b]fortified[/b]: shell, torpedo or bomb its garrison (%d HP Minor, %d HP Major) to zero to make it neutral, then capture it. A Tier 3 island also launches dive bombers at attackers and can buy radar.\n" % [int(b.minor_garrison_hp), int(b.major_garrison_hp)]
	t += "[b]Repairs:[/b] right-click one of your docks. Ships inside regain hull while that yard is idle and able to build their class.\n\n"

	t += H1 % "Fighting"
	t += "- Ships fire on their own at any enemy that is [b]spotted[/b] and in range. Right-click a target to focus fire.\n"
	t += "- [b]Islands are hard cover:[/b] they block both sight and shells. Hide behind them to break lock-ons.\n"
	t += "- [b]Fog of war:[/b] Destroyers spot furthest, cruisers half as far, battleships less, carriers barely at all, and submarines nothing. Storms cut everyone's vision.\n"
	t += "- [b]Focus fire strips armour:[/b] every attacker beyond the first lowers the target's armour by %d%%.\n" % roundi(b.armor_strip_per_attacker * 100.0)
	t += "- Battleships, Battlecruisers and Super Battleships cannot shoot submarines: bring Destroyers or carriers.\n"
	t += "- Ships still on the slip are defenceless. Protect your yards.\n\n"

	t += H1 % "The fleet"
	t += "[table=4]"
	t += "[cell][b]Ship[/b]   [/cell][cell][b]Cost[/b]   [/cell][cell][b]Yard[/b]   [/cell][cell][b]Role[/b][/cell]"
	for ship_class: ShipStats.ShipClass in GameData.all_classes():
		var s: ShipStats = GameData.ship(ship_class)
		t += "[cell][color=#ffe7a8][b]%s[/b][/color] %s   [/cell][cell]%dG / %dS   [/cell][cell]Tier %d   [/cell][cell]%s[/cell]" % [
			s.code, s.display_name, s.gold_cost, s.steel_cost, s.required_shipyard_tier,
			ROLES.get(s.code, "")]
	t += "[/table]\n\n"

	t += H1 % "Playing with friends"
	t += "Up to four players on one local network. One player presses [b]Host LAN Game[/b]; the game then shows up under [b]Games on your network[/b] for everyone else. Players on the same team are allies. Allow the game through your firewall on private networks (UDP ports 24567 and 24568).\n"
	return t


## The Credits page.
static func credits_bbcode() -> String:
	var t: String = ""
	t += "[center][font_size=34][color=#fff0bd]OPERATION: FLEETFALL[/color][/font_size]\n"
	t += "[color=#a8bccc]A WWII naval strategy game[/color][/center]\n\n"
	t += H1 % "Game design and development"
	t += "Dylan\n\n"
	t += H1 % "Soundtrack"
	t += "All music from [b]Pixabay[/b] (pixabay.com), used under the Pixabay Content License.\n"
	t += "[table=2]"
	for credit: Array[String] in soundtrack_credits():
		t += "[cell][color=#ffe7a8][b]%s[/b][/color]      [/cell][cell]by %s[/cell]" % [credit[0], credit[1]]
	t += "[/table]\n\n"
	t += H1 % "Sound effects and art"
	t += "Every sound effect, ship, island and the sea are generated in code: no recorded samples or image files.\n\n"
	t += H1 % "Engine"
	t += "Made with [b]Godot Engine[/b] (godotengine.org).\n"
	t += "[color=#a8bccc][font_size=13]%s[/font_size][/color]\n" % Engine.get_license_text().strip_edges()
	return t


## [title, artist] for every soundtrack piece in the game, sorted by title.
static func soundtrack_credits() -> Array[Array]:
	var seen: Dictionary[String, bool] = {}
	var out: Array[Array] = []
	for path: String in Music.find_tracks():
		var credit: Array[String] = Music.credit_for(path)
		var key: String = credit[0] + "|" + credit[1]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(credit)
	out.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	return out


## A full-screen page over the menu: a dimmed backdrop, a card with `title`, the scrolling
## `bbcode` text and a Back button. `on_close` runs when Back or Esc is pressed.
static func build_page(title: String, bbcode: String, on_close: Callable) -> Control:
	var page: Control = Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UITheme.box(Color(0.03, 0.07, 0.12, 1.0), UITheme.BRASS_DIM, 2, 14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 18
	UITheme.pad(style, 30, 18)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var heading: Label = Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", Color(1.0, 0.93, 0.74))
	heading.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02))
	heading.add_theme_constant_override("outline_size", 8)
	column.add_child(heading)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1180.0, 700.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var text: RichTextLabel = RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.selection_enabled = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 17)
	text.add_theme_constant_override("table_h_separation", 6)
	text.add_theme_constant_override("table_v_separation", 6)
	text.text = bbcode
	scroll.add_child(text)
	var holder: CenterContainer = CenterContainer.new()
	column.add_child(holder)
	var back: Button = Button.new()
	back.name = "Back"
	back.text = "Back"
	back.theme_type_variation = "AccentButton"
	back.custom_minimum_size = Vector2(200.0, 44.0)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(on_close)
	holder.add_child(back)
	back.grab_focus.call_deferred()
	UITheme.liven(page)
	return page
