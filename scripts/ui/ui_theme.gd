class_name UITheme
extends RefCounted
## The game's look: navy steel panels with brass trim, raised buttons that light up on hover
## and sink when pressed, gauges and drawn icons. `build()` makes the Theme every screen
## uses; `liven()` adds the hover / press animation and interface sounds to buttons.
## Cosmetic only.

const NAVY: Color = Color(0.045, 0.085, 0.14, 0.94)
const NAVY_LIGHT: Color = Color(0.09, 0.16, 0.25, 0.96)
const BRASS: Color = Color(0.86, 0.68, 0.34)
const BRASS_DIM: Color = Color(0.55, 0.43, 0.22)
const STEEL: Color = Color(0.32, 0.47, 0.62)
const TEXT: Color = Color(0.92, 0.95, 0.99)
const TEXT_DIM: Color = Color(0.66, 0.73, 0.8)
const GOLD: Color = Color(1.0, 0.84, 0.36)
const STEEL_TEXT: Color = Color(0.74, 0.86, 0.98)
const GOOD: Color = Color(0.42, 0.9, 0.5)
const BAD: Color = Color(1.0, 0.42, 0.36)
## Tier colours for shipyard tiers 1-3.
const TIER_COLORS: Array[Color] = [Color(0.4, 0.72, 0.95), Color(0.4, 0.86, 0.55), Color(0.98, 0.62, 0.3)]




static func build() -> Theme:
	var theme: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Helvetica Neue", "Arial", "Noto Sans"])
	font.font_weight = 600
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	theme.default_font = font
	theme.default_font_size = 16

	var panel: StyleBoxFlat = box(NAVY, BRASS_DIM, 2, 8)
	panel.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	panel.shadow_size = 8
	panel.shadow_offset = Vector2(0.0, 3.0)
	pad(panel, 12, 10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	# Raised buttons: a dark lip along the bottom that flips to the top when pressed.
	_button_styles(theme, "Button", Color(0.13, 0.27, 0.42), Color(0.04, 0.1, 0.18), STEEL)
	theme.set_type_variation("AccentButton", "Button")
	_button_styles(theme, "AccentButton", Color(0.6, 0.4, 0.12), Color(0.3, 0.18, 0.04), Color(1.0, 0.8, 0.45))
	theme.set_type_variation("DangerButton", "Button")
	_button_styles(theme, "DangerButton", Color(0.5, 0.15, 0.13), Color(0.24, 0.05, 0.05), Color(0.9, 0.42, 0.36))
	for type: String in ["Button", "AccentButton", "DangerButton", "OptionButton", "CheckButton"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color(1.0, 0.95, 0.78))
		theme.set_color("font_pressed_color", type, Color(1.0, 0.88, 0.55))
		theme.set_color("font_hover_pressed_color", type, Color(1.0, 0.9, 0.6))
		theme.set_color("font_focus_color", type, TEXT)
		theme.set_color("font_disabled_color", type, Color(0.48, 0.52, 0.57))
		theme.set_color("font_outline_color", type, Color(0.0, 0.0, 0.0, 0.6))
		theme.set_constant("outline_size", type, 2)
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	_button_styles(theme, "OptionButton", Color(0.13, 0.27, 0.42), Color(0.04, 0.1, 0.18), STEEL)
	# Flat, see-through buttons for the in-game shop panel.
	theme.set_type_variation("FlatButton", "Button")
	_flat_button_styles(theme, "FlatButton", Color(0.12, 0.24, 0.38), STEEL)
	theme.set_type_variation("FlatAccentButton", "Button")
	_flat_button_styles(theme, "FlatAccentButton", Color(0.5, 0.34, 0.1), Color(1.0, 0.8, 0.45))
	theme.set_type_variation("FlatDangerButton", "Button")
	_flat_button_styles(theme, "FlatDangerButton", Color(0.45, 0.13, 0.11), Color(0.9, 0.42, 0.36))
	# Toggle buttons that are switched on look pressed in and glow brass.
	var on: StyleBoxFlat = box(Color(0.5, 0.36, 0.12), BRASS, 2, 6)
	on.border_width_top = 3
	on.border_width_bottom = 1
	pad(on, 12, 6)
	theme.set_stylebox("pressed", "Button", on)
	theme.set_stylebox("hover_pressed", "Button", on)

	var check: StyleBoxFlat = box(Color(0.1, 0.18, 0.28, 0.0), Color(0, 0, 0, 0), 0, 6)
	pad(check, 8, 4)
	var check_hover: StyleBoxFlat = box(Color(0.16, 0.28, 0.42, 0.8), STEEL, 1, 6)
	pad(check_hover, 8, 4)
	for state: String in ["normal", "pressed", "disabled"]:
		theme.set_stylebox(state, "CheckButton", check)
	theme.set_stylebox("hover", "CheckButton", check_hover)
	theme.set_stylebox("hover_pressed", "CheckButton", check_hover)
	theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	var edit: StyleBoxFlat = box(Color(0.02, 0.05, 0.09, 0.95), STEEL, 2, 6)
	pad(edit, 10, 6)
	var edit_focus: StyleBoxFlat = box(Color(0.03, 0.07, 0.12, 0.98), BRASS, 2, 6)
	pad(edit_focus, 10, 6)
	theme.set_stylebox("normal", "LineEdit", edit)
	theme.set_stylebox("focus", "LineEdit", edit_focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.58, 0.66))
	theme.set_color("caret_color", "LineEdit", BRASS)

	var bar_bg: StyleBoxFlat = box(Color(0.01, 0.03, 0.06, 0.9), Color(0.25, 0.35, 0.45, 0.9), 1, 4)
	var bar_fill: StyleBoxFlat = box(Color(0.32, 0.72, 0.95), Color(0, 0, 0, 0), 0, 4)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_color("font_color", "ProgressBar", TEXT)
	theme.set_color("font_outline_color", "ProgressBar", Color(0, 0, 0, 0.9))
	theme.set_constant("outline_size", "ProgressBar", 3)
	theme.set_font_size("font_size", "ProgressBar", 12)

	var tip: StyleBoxFlat = box(Color(0.03, 0.06, 0.1, 0.97), BRASS_DIM, 1, 5)
	pad(tip, 10, 6)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 14)

	var popup: StyleBoxFlat = box(NAVY_LIGHT, BRASS_DIM, 1, 6)
	pad(popup, 6, 6)
	theme.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover: StyleBoxFlat = box(Color(0.5, 0.36, 0.12, 0.9), Color(0, 0, 0, 0), 0, 4)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color(1.0, 0.95, 0.8))

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)
	return theme


static func box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


static func pad(style: StyleBox, horizontal: float, vertical: float) -> void:
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical


static func _button_styles(theme: Theme, type: String, face: Color, lip: Color, rim: Color) -> void:
	var normal: StyleBoxFlat = box(face, rim.darkened(0.25), 1, 6)
	normal.border_width_bottom = 4
	normal.border_color = lip
	normal.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0.0, 2.0)
	pad(normal, 12, 6)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = face.lightened(0.18)
	hover.border_color = BRASS
	hover.set_border_width_all(2)
	hover.border_width_bottom = 4
	hover.shadow_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.25)
	hover.shadow_size = 6
	hover.shadow_offset = Vector2.ZERO
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = face.darkened(0.2)
	pressed.border_width_bottom = 1
	pressed.border_width_top = 4
	pressed.shadow_size = 0
	var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.12, 0.14, 0.17, 0.85)
	disabled.border_color = Color(0.08, 0.09, 0.11)
	disabled.shadow_size = 0
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)


## A flat, translucent button: no lip or shadow, a thin rim that turns brass on hover.
static func _flat_button_styles(theme: Theme, type: String, face: Color, rim: Color) -> void:
	var normal: StyleBoxFlat = box(Color(face.r, face.g, face.b, 0.5), Color(rim.r, rim.g, rim.b, 0.35), 1, 4)
	pad(normal, 8, 4)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(face.r, face.g, face.b, 0.75).lightened(0.15)
	hover.border_color = BRASS
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(face.r, face.g, face.b, 0.85).darkened(0.25)
	pressed.border_color = BRASS
	var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.1, 0.12, 0.15, 0.35)
	disabled.border_color = Color(0.3, 0.33, 0.37, 0.25)
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)


## Hover and press animation plus interface sounds for every button under `root`
## (call again after adding buttons).
static func liven(root: Node) -> void:
	if root is BaseButton and not root.has_meta("livened"):
		var button: BaseButton = root as BaseButton
		button.set_meta("livened", true)
		button.mouse_entered.connect(_on_hover.bind(button, true))
		button.mouse_exited.connect(_on_hover.bind(button, false))
		button.button_down.connect(_on_down.bind(button))
		button.pressed.connect(func() -> void: Sfx.ui("ui_click"))
	for child: Node in root.get_children():
		liven(child)


static func _on_hover(button: BaseButton, inside: bool) -> void:
	if not button.is_inside_tree():
		return
	if inside and not button.disabled:
		Sfx.ui("ui_hover")
	button.pivot_offset = button.size * 0.5
	var tween: Tween = button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * (1.04 if inside and not button.disabled else 1.0), 0.08)


static func _on_down(button: BaseButton) -> void:
	if not button.is_inside_tree():
		return
	button.pivot_offset = button.size * 0.5
	var tween: Tween = button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * 0.95, 0.04)
	tween.tween_property(button, "scale", Vector2.ONE * 1.04, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Briefly brightens `control` (a value changed).
static func flash(control: CanvasItem, color: Color = Color(1.6, 1.5, 1.1)) -> void:
	if not control.is_inside_tree():
		return
	control.modulate = color
	var tween: Tween = control.create_tween()
	tween.tween_property(control, "modulate", Color.WHITE, 0.45)


## A small drawn icon: coin, ingot, ship, clock or anchor.
class Icon extends Control:
	enum Shape { COIN, INGOT, SHIP, CLOCK, SPEAKER }
	var shape: Shape = Shape.COIN
	var muted: bool = false
	var progress: float = 0.0

	func _init(p_shape: Shape = Shape.COIN, side: float = 22.0) -> void:
		shape = p_shape
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.45
		match shape:
			Shape.COIN:
				draw_circle(c + Vector2(0.0, 1.5), r, Color(0.35, 0.22, 0.02))
				draw_circle(c, r, Color(0.95, 0.72, 0.2))
				draw_circle(c, r * 0.72, Color(1.0, 0.85, 0.35))
				draw_arc(c, r * 0.72, 0.0, TAU, 20, Color(0.75, 0.52, 0.1), 1.2)
				draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.18, Color(1.0, 0.97, 0.8, 0.9))
			Shape.INGOT:
				var w: float = r * 1.0
				var top: PackedVector2Array = PackedVector2Array([c + Vector2(-w * 0.6, -r * 0.45),
					c + Vector2(w * 0.6, -r * 0.45), c + Vector2(w, r * 0.5), c + Vector2(-w, r * 0.5)])
				draw_colored_polygon(PackedVector2Array([top[2] + Vector2(0, 2), top[3] + Vector2(0, 2),
					top[3], top[2]]), Color(0.2, 0.26, 0.32))
				draw_colored_polygon(top, Color(0.66, 0.76, 0.86))
				draw_colored_polygon(PackedVector2Array([top[0], top[1], c + Vector2(w * 0.45, -r * 0.1),
					c + Vector2(-w * 0.45, -r * 0.1)]), Color(0.86, 0.93, 1.0))
			Shape.SHIP:
				var hull: PackedVector2Array = PackedVector2Array([c + Vector2(-r, r * 0.05),
					c + Vector2(r, r * 0.05), c + Vector2(r * 0.7, r * 0.55), c + Vector2(-r * 0.8, r * 0.55)])
				draw_colored_polygon(hull, Color(0.62, 0.72, 0.82))
				draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.35), Vector2(r * 0.8, r * 0.4)), Color(0.8, 0.88, 0.95))
				draw_rect(Rect2(c + Vector2(-r * 0.1, -r * 0.8), Vector2(r * 0.22, r * 0.45)), Color(0.86, 0.68, 0.34))
				draw_line(c + Vector2(-r * 1.1, r * 0.75), c + Vector2(r * 1.1, r * 0.75), Color(0.4, 0.75, 1.0, 0.8), 1.5)
			Shape.CLOCK:
				draw_circle(c, r, Color(0.08, 0.16, 0.26))
				if progress > 0.0:
					var points: PackedVector2Array = PackedVector2Array([c])
					var steps: int = 24
					for i: int in steps + 1:
						points.append(c + Vector2.from_angle(-PI * 0.5 + TAU * progress * float(i) / steps) * r * 0.92)
					draw_colored_polygon(points, Color(0.32, 0.72, 0.95, 0.8))
				draw_arc(c, r, 0.0, TAU, 24, Color(0.75, 0.86, 0.95), 1.6)
				draw_line(c, c + Vector2(0.0, -r * 0.65), Color.WHITE, 1.6)
			Shape.SPEAKER:
				var col: Color = Color(0.86, 0.92, 1.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.9, -r * 0.3), c + Vector2(-r * 0.4, -r * 0.3),
					c + Vector2(0.05 * r, -r * 0.75), c + Vector2(0.05 * r, r * 0.75), c + Vector2(-r * 0.4, r * 0.3),
					c + Vector2(-r * 0.9, r * 0.3)]), col)
				if muted:
					draw_line(c + Vector2(r * 0.35, -r * 0.35), c + Vector2(r * 0.95, r * 0.35), BAD, 2.0)
					draw_line(c + Vector2(r * 0.35, r * 0.35), c + Vector2(r * 0.95, -r * 0.35), BAD, 2.0)
				else:
					draw_arc(c + Vector2(r * 0.1, 0.0), r * 0.45, -0.9, 0.9, 10, col, 1.6)
					draw_arc(c + Vector2(r * 0.1, 0.0), r * 0.8, -0.9, 0.9, 12, col, 1.6)
