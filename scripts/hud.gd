# =====================================================================
# hud.gd  —  all on-screen UI. Attached to the HUD node (a CanvasLayer).
#
# A CanvasLayer draws on top of the game world and never moves with it,
# which is exactly what you want for menus and score bars.
#
# The UI is built in code here so you don't have to click together
# dozens of nodes in the editor. Milestone 4 moves it into a proper
# .tscn so you can restyle it visually.
# =====================================================================
class_name TavernHUD
extends CanvasLayer

signal build_selected(type: String)     # "table", "kitchen", "remove" or ""
signal day_start_requested

var _gold_label: Label
var _fame_label: Label
var _clock_label: Label
var _hint_label: Label
var _summary_panel: PanelContainer
var _summary_label: Label
var _summary_button: Button

var _current_hint: String = "Tap a build button to place furniture."
var _message_time_left: float = 0.0


func _ready() -> void:
	_build_top_bar()
	_build_bottom_bar()
	_build_summary_panel()

	# CONNECTING SIGNALS: "when GameManager emits gold_changed, run my
	# _on_gold_changed function". The signal passes along the new amount.
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.fame_changed.connect(_on_fame_changed)
	GameManager.clock_changed.connect(_on_clock_changed)
	GameManager.shop_opened.connect(_on_shop_opened)

	# Show the starting values.
	_on_gold_changed(GameManager.gold)
	_on_fame_changed(GameManager.fame)
	_clock_label.text = "Closed"


func _process(delta: float) -> void:
	# Temporary messages ("Not enough gold!") fade back to the hint.
	if _message_time_left > 0.0:
		_message_time_left -= delta
		if _message_time_left <= 0.0:
			_hint_label.text = _current_hint


# ---------------------------------------------------------------------
# Public functions main.gd calls
# ---------------------------------------------------------------------
func show_message(text: String) -> void:
	_hint_label.text = text
	_message_time_left = 2.0


func show_summary(text: String, button_text: String) -> void:
	_summary_label.text = text
	_summary_button.text = button_text
	_summary_panel.visible = true


# ---------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------
func _on_gold_changed(amount: int) -> void:
	_gold_label.text = "Gold: %d" % amount


func _on_fame_changed(amount: int) -> void:
	_fame_label.text = "Fame: %d" % amount


func _on_clock_changed(hour: int, minute: int) -> void:
	# %02d = pad with zeros to 2 digits, so 9:5 shows as 09:05
	_clock_label.text = "Day %d   %02d:%02d" % [GameManager.day, hour, minute]


func _on_shop_opened(day: int) -> void:
	_clock_label.text = "Day %d   %02d:00" % [day, GameManager.OPEN_HOUR]


func _on_build_button(type: String) -> void:
	build_selected.emit(type)
	match type:
		"table":   _current_hint = "Tap a square: Table (50g)"
		"kitchen": _current_hint = "Tap a square: Hearth (120g)"
		"remove":  _current_hint = "Tap furniture to sell it (half price)"
		_:         _current_hint = "Tap a build button to place furniture."
	_hint_label.text = _current_hint
	_message_time_left = 0.0


func _on_summary_button() -> void:
	_summary_panel.visible = false
	day_start_requested.emit()


# ---------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------
func _make_label(font_size: int) -> Label:
	var label := Label.new()
	# Theme overrides change one property on one node, like inline CSS.
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	# Anchors pin a Control to the screen edges. TOP_WIDE = stretch across
	# the top. Offsets then set the exact pixel edges.
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 150

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var row := HBoxContainer.new()
	vbox.add_child(row)
	_gold_label = _make_label(34)
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_gold_label)
	_fame_label = _make_label(34)
	row.add_child(_fame_label)

	_clock_label = _make_label(30)
	vbox.add_child(_clock_label)

	_hint_label = _make_label(24)
	_hint_label.text = _current_hint
	_hint_label.modulate = Color(1.0, 0.9, 0.6)
	vbox.add_child(_hint_label)


func _build_bottom_bar() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = -190
	panel.offset_bottom = 0

	var row := HBoxContainer.new()
	panel.add_child(row)

	# [button text, build type]
	var buttons: Array = [
		["Table\n50g", "table"],
		["Hearth\n120g", "kitchen"],
		["Sell", "remove"],
		["Done", ""],
	]
	for entry in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.add_theme_font_size_override("font_size", 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 150)
		row.add_child(button)
		# .bind() attaches an extra argument, so one function can handle
		# all four buttons and still know which one was pressed.
		button.pressed.connect(_on_build_button.bind(entry[1]))


func _build_summary_panel() -> void:
	_summary_panel = PanelContainer.new()
	add_child(_summary_panel)
	_summary_panel.set_anchors_preset(Control.PRESET_CENTER)
	_summary_panel.offset_left = -290
	_summary_panel.offset_right = 290
	_summary_panel.offset_top = -260
	_summary_panel.offset_bottom = 260
	_summary_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	_summary_panel.add_child(vbox)

	_summary_label = _make_label(30)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_summary_label)

	_summary_button = Button.new()
	_summary_button.add_theme_font_size_override("font_size", 34)
	_summary_button.custom_minimum_size = Vector2(0, 110)
	_summary_button.pressed.connect(_on_summary_button)
	vbox.add_child(_summary_button)
