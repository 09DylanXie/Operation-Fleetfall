class_name SoundPanel
extends PanelContainer
## Sound controls: soundtrack and effects volume sliders, a mute switch (also `M` in a
## match) and the track playing now with a skip button. Used by the HUD's Sound button and
## the start menu. Volumes live in `AudioMix` and are saved between sessions.

signal closed

var music_slider: HSlider = null
var sfx_slider: HSlider = null
var mute_toggle: CheckButton = null
var _music_value: Label = null
var _sfx_value: Label = null
var _now_playing: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = UITheme.box(Color(0.03, 0.07, 0.12, 0.96), UITheme.BRASS, 2, 10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 14
	UITheme.pad(style, 18, 12)
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Label.new()
	title.text = "Sound"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	_music_value = Label.new()
	music_slider = _slider_row(grid, "Music", AudioMix.MUSIC, _music_value,
		"Soundtrack volume")
	_sfx_value = Label.new()
	sfx_slider = _slider_row(grid, "Effects", AudioMix.SFX, _sfx_value,
		"Guns, explosions, ocean, interface sounds")
	mute_toggle = CheckButton.new()
	mute_toggle.text = "Mute everything (M in battle)"
	mute_toggle.focus_mode = Control.FOCUS_NONE
	mute_toggle.toggled.connect(func(on: bool) -> void: Sfx.set_muted(on))
	column.add_child(mute_toggle)
	var track_row: HBoxContainer = HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 8)
	column.add_child(track_row)
	_now_playing = Label.new()
	_now_playing.add_theme_font_size_override("font_size", 14)
	_now_playing.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_now_playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_playing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_now_playing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now_playing.custom_minimum_size = Vector2(300.0, 0.0)
	track_row.add_child(_now_playing)
	var skip: Button = Button.new()
	skip.text = "Next track"
	skip.focus_mode = Control.FOCUS_NONE
	skip.tooltip_text = "Play another soundtrack piece"
	skip.disabled = not Music.enabled
	skip.pressed.connect(Music.skip)
	track_row.add_child(skip)
	Music.track_changed.connect(_on_track_changed)
	refresh()
	UITheme.liven(self)


func _slider_row(grid: GridContainer, text: String, bus: String, value_label: Label,
		tip: String) -> HSlider:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(240.0, 24.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = tip
	slider.value = AudioMix.volume(bus)
	slider.value_changed.connect(func(v: float) -> void:
		AudioMix.set_volume(bus, v)
		value_label.text = "%d%%" % roundi(v * 100.0))
	grid.add_child(slider)
	value_label.custom_minimum_size = Vector2(48.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d%%" % roundi(slider.value * 100.0)
	grid.add_child(value_label)
	return slider


## Re-reads the volumes, mute state and current track.
func refresh() -> void:
	if music_slider == null:
		return
	music_slider.set_value_no_signal(AudioMix.volume(AudioMix.MUSIC))
	sfx_slider.set_value_no_signal(AudioMix.volume(AudioMix.SFX))
	_music_value.text = "%d%%" % roundi(music_slider.value * 100.0)
	_sfx_value.text = "%d%%" % roundi(sfx_slider.value * 100.0)
	mute_toggle.set_pressed_no_signal(Sfx.muted)
	var playing: String = Music.now_playing()
	_now_playing.text = "Now playing: %s" % playing if playing != "" else "No soundtrack loaded"


func _on_track_changed(_title: String, _artist: String) -> void:
	refresh()


func _exit_tree() -> void:
	if Music.track_changed.is_connected(_on_track_changed):
		Music.track_changed.disconnect(_on_track_changed)
