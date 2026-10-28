# =====================================================================
# hud.gd  —  all on-screen UI. Attached to the HUD node (a CanvasLayer).
#
# A CanvasLayer draws on top of the game world and never moves with it,
# which is exactly what you want for menus and score bars.
#
# Layout (portrait, 720 x 1280):
#   top bar:     gold, fame, clock, staff, and a hint/message line
#   bottom bar:  [Build] [Staff] [Recipes] [Open Day]
#   tray:        a row of options that pops up above the bottom bar when
#                Build or Staff is tapped, and hides again when done
#   cards:       the day summary (closes with Continue, so you can build
#                between days), the recipe book and the expansion card
#
# The UI is built in code here so you don't have to click together
# dozens of nodes in the editor. A later milestone moves it into a
# proper .tscn so you can restyle it visually.
# =====================================================================
class_name TavernHUD
extends CanvasLayer

signal build_selected(type: String)     # "table", "kitchen", "remove" or ""
signal day_start_requested
signal staff_change_requested(role: String, change: int)   # "cook"/"waiter", +1 or -1
signal new_game_requested
signal expand_requested

const TOP_HEIGHT: int = 150
const BAR_HEIGHT: int = 120
const TRAY_HEIGHT: int = 110
const HIGHLIGHT := Color(1.0, 0.85, 0.45)   # tint for the selected button

var _gold_label: Label
var _fame_label: Label
var _clock_label: Label
var _staff_label: Label
var _hint_label: Label

# Bottom bar and trays
var _build_button: Button
var _staff_button: Button
var _day_button: Button
var _build_tray: Control
var _staff_tray: Control
var _tool_buttons: Dictionary = {}   # build type -> its tray button
var _open_tray: String = ""          # "build", "staff" or ""

# Cards
var _summary_panel: PanelContainer
var _summary_label: Label
var _new_game_button: Button
var _new_game_armed: bool = false   # true after the first tap
var _recipe_panel: PanelContainer
var _recipe_header: Label
var _recipe_list: VBoxContainer
var _expand_panel: PanelContainer
var _expand_label: Label
var _expand_button: Button

var _current_hint: String = "Drag to look around. Pinch to zoom."
var _message_time_left: float = 0.0


func _ready() -> void:
	_build_top_bar()
	_build_trays()
	_build_bottom_bar()
	_build_summary_panel()
	_build_recipe_panel()
	_build_expand_panel()

	# CONNECTING SIGNALS: "when GameManager emits gold_changed, run my
	# _on_gold_changed function". The signal passes along the new amount.
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.fame_changed.connect(_on_fame_changed)
	GameManager.clock_changed.connect(_on_clock_changed)
	GameManager.shop_opened.connect(_on_shop_opened)
	GameManager.recipes_changed.connect(_refresh_recipes)
	# Gold decides whether the expansion can be afforded.
	GameManager.gold_changed.connect(_refresh_expand_panel.unbind(1))

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
func show_message(text: String, seconds: float = 2.0) -> void:
	_hint_label.text = text
	_message_time_left = seconds


func set_staff(cooks: int, waiters: int, wages: int) -> void:
	_staff_label.text = "Cooks %d  Waiters %d  Wages %dg/day" % [cooks, waiters, wages]


# The summary card. Continue just closes it; the day starts from the
# Open Day button, so you can build and hire first.
func show_summary(text: String, allow_new_game: bool = false) -> void:
	_summary_label.text = text
	_new_game_button.visible = allow_new_game
	_new_game_armed = false
	_new_game_button.text = "New Game"
	_recipe_panel.visible = false
	_expand_panel.visible = false
	_summary_panel.visible = true


func close_expand_panel() -> void:
	_expand_panel.visible = false


# The fourth bottom button: "Open Day 3" between days, greyed out while open.
func set_day_button(text: String, enabled: bool) -> void:
	_day_button.text = text
	_day_button.disabled = not enabled


# ---------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------
func _on_gold_changed(amount: int) -> void:
	_gold_label.text = "Gold: %d" % amount
	# Red when in debt.
	_gold_label.modulate = Color(1.0, 0.45, 0.45) if amount < 0 else Color.WHITE


func _on_fame_changed(amount: int) -> void:
	_fame_label.text = "Fame: %d" % amount


func _on_clock_changed(hour: int, minute: int) -> void:
	# %02d = pad with zeros to 2 digits, so 9:5 shows as 09:05
	_clock_label.text = "Day %d   %02d:%02d" % [GameManager.day, hour, minute]


func _on_shop_opened(day: int) -> void:
	_clock_label.text = "Day %d   %02d:00" % [day, GameManager.OPEN_HOUR]


# Build and Staff open their tray; tapping the same one again closes it.
func _on_tray_button(tray: String) -> void:
	_set_tray("" if _open_tray == tray else tray)


func _set_tray(tray: String) -> void:
	_open_tray = tray
	_build_tray.visible = tray == "build"
	_staff_tray.visible = tray == "staff"
	_build_button.modulate = HIGHLIGHT if tray == "build" else Color.WHITE
	_staff_button.modulate = HIGHLIGHT if tray == "staff" else Color.WHITE
	# Leaving the build tray always stops building.
	if tray != "build":
		_select_tool("")
	if tray == "build":
		_set_hint("Pick something to build, then tap a square.")
	elif tray == "staff":
		_set_hint("Hire and fire staff between days.")
	else:
		_set_hint("Drag to look around. Pinch to zoom.")


func _select_tool(type: String) -> void:
	build_selected.emit(type)
	for tool in _tool_buttons:
		_tool_buttons[tool].modulate = HIGHLIGHT if tool == type else Color.WHITE
	match type:
		"table":   _set_hint("Tap a square: Table (50g)")
		"kitchen": _set_hint("Tap a square: Hearth (120g)")
		"remove":  _set_hint("Tap furniture to sell it (half price)")
		"door":    _set_hint("Tap a square along a wall to move the door (%dg)" % TavernGrid.DOOR_COST)


func _set_hint(text: String) -> void:
	_current_hint = text
	_hint_label.text = text
	_message_time_left = 0.0


func _on_day_button() -> void:
	_summary_panel.visible = false
	_recipe_panel.visible = false
	_expand_panel.visible = false
	day_start_requested.emit()


func _on_expand_tool() -> void:
	_select_tool("")
	_summary_panel.visible = false
	_recipe_panel.visible = false
	_expand_panel.visible = true
	_refresh_expand_panel()


func _on_continue_button() -> void:
	_summary_panel.visible = false


func _on_recipes_button() -> void:
	_set_tray("")
	_summary_panel.visible = false
	_expand_panel.visible = false
	_recipe_panel.visible = not _recipe_panel.visible
	_refresh_recipes()


func _on_recipes_back() -> void:
	_recipe_panel.visible = false


func _on_menu_toggle_pressed(id: String) -> void:
	var message: String = GameManager.toggle_menu(id)
	if message != "":
		show_message(message)


# Erasing a save can't be undone, so it takes two taps.
func _on_new_game_button() -> void:
	if not _new_game_armed:
		_new_game_armed = true
		_new_game_button.text = "Tap again to erase your tavern"
		return
	new_game_requested.emit()


# ---------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------
func _make_label(font_size: int) -> Label:
	var label := Label.new()
	# Theme overrides change one property on one node, like inline CSS.
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, font_size: int, parent: Control, height: int = 100) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, height)
	parent.add_child(button)
	return button


# A solid background. The default panel is see-through, which is hard
# to read over the busy floor. A StyleBoxFlat is a plain colored box.
func _solid(panel: PanelContainer, color: Color = Color(0.14, 0.11, 0.09)) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = color
	background.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", background)


# Pins a panel across the bottom of the screen, `from_bottom` pixels up,
# `height` pixels tall.
func _pin_bottom(panel: Control, from_bottom: int, height: int) -> void:
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = -(from_bottom + height)
	panel.offset_bottom = -from_bottom


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

	var row2 := HBoxContainer.new()
	vbox.add_child(row2)
	_clock_label = _make_label(30)
	_clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_clock_label)
	_staff_label = _make_label(22)
	row2.add_child(_staff_label)

	_hint_label = _make_label(24)
	_hint_label.text = _current_hint
	_hint_label.modulate = Color(1.0, 0.9, 0.6)
	vbox.add_child(_hint_label)


func _build_bottom_bar() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	_pin_bottom(panel, 0, BAR_HEIGHT)
	_solid(panel)

	var row := HBoxContainer.new()
	panel.add_child(row)
	_build_button = _make_button("Build", 28, row)
	# .bind() attaches an extra argument, so one function can handle
	# both buttons and still know which one was pressed.
	_build_button.pressed.connect(_on_tray_button.bind("build"))
	_staff_button = _make_button("Staff", 28, row)
	_staff_button.pressed.connect(_on_tray_button.bind("staff"))
	var recipes := _make_button("Recipes", 28, row)
	recipes.pressed.connect(_on_recipes_button)
	_day_button = _make_button("Open\nDay 1", 26, row)
	_day_button.pressed.connect(_on_day_button)


func _build_trays() -> void:
	# Build tray. [button text, build type]
	var build_panel := PanelContainer.new()
	add_child(build_panel)
	_pin_bottom(build_panel, BAR_HEIGHT, TRAY_HEIGHT)
	_solid(build_panel, Color(0.2, 0.16, 0.12))
	_build_tray = build_panel
	var build_row := HBoxContainer.new()
	build_panel.add_child(build_row)
	var tools: Array = [["Table\n50g", "table"], ["Hearth\n120g", "kitchen"], ["Sell", "remove"],
			["Door\n%dg" % TavernGrid.DOOR_COST, "door"]]
	for entry in tools:
		var button := _make_button(entry[0], 21, build_row, 86)
		button.pressed.connect(_select_tool.bind(entry[1]))
		_tool_buttons[entry[1]] = button
	var expand := _make_button("Expand", 21, build_row, 86)
	expand.pressed.connect(_on_expand_tool)
	var done := _make_button("Done", 21, build_row, 86)
	done.pressed.connect(_set_tray.bind(""))

	# Staff tray. [button text, role, +1 hire / -1 let go]
	var staff_panel := PanelContainer.new()
	add_child(staff_panel)
	_pin_bottom(staff_panel, BAR_HEIGHT, TRAY_HEIGHT)
	_solid(staff_panel, Color(0.2, 0.16, 0.12))
	_staff_tray = staff_panel
	var staff_row := HBoxContainer.new()
	staff_panel.add_child(staff_row)
	var staff_buttons: Array = [
		["Hire Cook\n%dg/day" % GameManager.STAFF["cook"]["wage"], "cook", 1],
		["Fire\nCook", "cook", -1],
		["Hire Waiter\n%dg/day" % GameManager.STAFF["waiter"]["wage"], "waiter", 1],
		["Fire\nWaiter", "waiter", -1],
	]
	for entry in staff_buttons:
		var button := _make_button(entry[0], 21, staff_row, 86)
		# You can bind more than one argument.
		button.pressed.connect(staff_change_requested.emit.bind(entry[1], entry[2]))

	_build_tray.visible = false
	_staff_tray.visible = false


func _build_summary_panel() -> void:
	_summary_panel = PanelContainer.new()
	add_child(_summary_panel)
	_summary_panel.set_anchors_preset(Control.PRESET_CENTER)
	_summary_panel.offset_left = -290
	_summary_panel.offset_right = 290
	_summary_panel.offset_top = -280
	_summary_panel.offset_bottom = 280
	# If the text needs more room, grow up and down evenly, staying centered.
	_summary_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_summary_panel.visible = false
	_solid(_summary_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	_summary_panel.add_child(vbox)

	_summary_label = _make_label(26)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_summary_label)

	var continue_button := _make_button("Continue", 30, vbox, 90)
	continue_button.pressed.connect(_on_continue_button)

	_new_game_button = _make_button("New Game", 22, vbox, 70)
	_new_game_button.pressed.connect(_on_new_game_button)
	_new_game_button.visible = false


# The recipe book: every dish, whether it's on today's menu, and for
# locked ones, the quest or patron idea that unlocks it.
func _build_recipe_panel() -> void:
	_recipe_panel = PanelContainer.new()
	add_child(_recipe_panel)
	# FULL_RECT = stretch to all four edges, then pull in from top and
	# bottom so the gold/fame bar and the bottom bar stay visible.
	_recipe_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_recipe_panel.offset_left = 10
	_recipe_panel.offset_right = -10
	_recipe_panel.offset_top = 155
	_recipe_panel.offset_bottom = -(BAR_HEIGHT + 5)
	_recipe_panel.visible = false
	_solid(_recipe_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_recipe_panel.add_child(vbox)

	_recipe_header = _make_label(26)
	_recipe_header.autowrap_mode = TextServer.AUTOWRAP_WORD
	_recipe_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_recipe_header)

	# A ScrollContainer shows part of its child and lets you drag to see
	# the rest. Horizontal scrolling is off: rows always fit the width.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_recipe_list)

	var back := _make_button("Close", 28, vbox, 80)
	back.pressed.connect(_on_recipes_back)


# Rebuilds every row. Simple, and with nine recipes it's instant.
func _refresh_recipes() -> void:
	if not _recipe_panel.visible:
		return
	for child in _recipe_list.get_children():
		# remove_child first so the old row vanishes right away;
		# queue_free deletes it safely once this button press is over.
		_recipe_list.remove_child(child)
		child.queue_free()

	var header: String = "Today's menu: %d of %d dishes" % [GameManager.menu.size(), GameManager.MAX_MENU]
	if not GameManager.menu_suits(false):
		header += "\nCommon folk have nothing to order!"
	if GameManager.fame >= GameManager.NOBLE_FAME and not GameManager.menu_suits(true):
		header += "\nNobles are visiting, but nothing fancy is on the menu."
	_recipe_header.text = header

	for id in GameManager.RECIPES:
		var recipe: Dictionary = GameManager.RECIPES[id]
		var known: bool = GameManager.known_recipes.has(id)
		var row := HBoxContainer.new()
		_recipe_list.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_label := _make_label(26)
		name_label.text = recipe["name"] if known else recipe["name"] + " (locked)"
		name_label.modulate = Color.WHITE if known else Color(0.75, 0.75, 0.75)
		info.add_child(name_label)
		var who: String = "Nobles only" if recipe["tier"] == 3 else "Common folk"
		var details := _make_label(20)
		details.text = "%dg   %.1fs to cook   %s" % [recipe["price"], recipe["cook_time"], who]
		details.modulate = Color(0.8, 0.8, 0.8)
		info.add_child(details)

		if not known:
			# How to earn it, with progress, e.g. "Serve 12 Mushroom Stews (7/12)".
			var unlock: Dictionary = recipe["unlock"]
			var how := _make_label(20)
			how.autowrap_mode = TextServer.AUTOWRAP_WORD
			how.modulate = Color(1.0, 0.85, 0.5)
			var lead: String = "Quest: %s. " % unlock["title"] if unlock["by"] == "quest" else "Patron idea: "
			how.text = "%s%s (%d/%d)" % [lead, unlock["task"], GameManager.unlock_progress(id), unlock["goal"]]
			info.add_child(how)
			continue

		var button := Button.new()
		button.add_theme_font_size_override("font_size", 22)
		button.custom_minimum_size = Vector2(170, 76)
		var on_menu: bool = GameManager.menu.has(id)
		button.text = "On menu" if on_menu else "Add to menu"
		button.modulate = Color(0.6, 1.0, 0.6) if on_menu else Color.WHITE
		button.pressed.connect(_on_menu_toggle_pressed.bind(id))
		row.add_child(button)


# The expansion card: what the next expansion adds, its quest, the cost,
# and a button to build it once the quest is done.
func _build_expand_panel() -> void:
	_expand_panel = PanelContainer.new()
	add_child(_expand_panel)
	_expand_panel.set_anchors_preset(Control.PRESET_CENTER)
	_expand_panel.offset_left = -290
	_expand_panel.offset_right = 290
	_expand_panel.offset_top = -230
	_expand_panel.offset_bottom = 230
	_expand_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_expand_panel.visible = false
	_solid(_expand_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	_expand_panel.add_child(vbox)

	_expand_label = _make_label(26)
	_expand_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_expand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_expand_label)

	_expand_button = _make_button("Build", 28, vbox, 90)
	_expand_button.pressed.connect(expand_requested.emit)
	var close := _make_button("Close", 24, vbox, 70)
	close.pressed.connect(close_expand_panel)


func _refresh_expand_panel() -> void:
	if not _expand_panel.visible:
		return
	var next: Dictionary = GameManager.next_expansion()
	if next.is_empty():
		_expand_label.text = "Expand the Tavern\n\nYour tavern is as big as it gets!"
		_expand_button.visible = false
		return
	var size: Vector2i = GameManager.floor_size()
	var done: bool = GameManager.expansion_quest_done()
	_expand_label.text = "Expand the Tavern\n\nFloor: %d x %d  ->  %d x %d\n\nQuest: %s\n%s (%d/%d)%s\n\nCost: %dg" % [
		size.x, size.y, next["cols"], next["rows"],
		next["title"], next["task"], GameManager.expansion_progress(), next["goal"],
		"  Done!" if done else "",
		next["cost"],
	]
	_expand_button.visible = true
	_expand_button.text = "Build (%dg)" % next["cost"] if done else "Finish the quest first"
	_expand_button.disabled = not done or GameManager.gold < next["cost"]
