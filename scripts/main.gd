# =====================================================================
# main.gd  —  the "director". Attached to the root Main node.
#
# It doesn't do much itself; it wires the other pieces together:
#   * spawns guests on a timer, seating them or lining them up outside
#   * moves the waiting line along whenever a table frees up
#   * hires and lets go of staff (only between days)
#   * tells the grid which build tool the HUD selected
#   * decides which guests are nobles
#   * frees tables, changes fame and records stats when guests leave
#   * announces recipes earned from quests and patron ideas
#   * shows the end-of-day summary once the last guest is gone
#   * loads the saved game at startup and saves between days
# =====================================================================
extends Node2D

# preload() loads the customer scene once, when the game starts.
# A PackedScene is a "blueprint"; instantiate() stamps out a new copy.
const CUSTOMER_SCENE: PackedScene = preload("res://scenes/customer.tscn")
const COOK_SCENE: PackedScene = preload("res://scenes/cook.tscn")
const WAITER_SCENE: PackedScene = preload("res://scenes/waiter.tscn")
const MAX_STAFF: int = 6   # per role
const MAX_LINE: int = 5    # guests who will wait outside for a table
const LINE_GAP: float = 46.0   # pixels between people in the line

# @onready waits until this node and its children exist, then fills in
# the variable. Without it, $TavernGrid would be looked up too early
# (before the children are ready) and come back empty.
# $TavernGrid is shorthand for get_node("TavernGrid") — a child by name.
@onready var grid: TavernGrid = $TavernGrid
@onready var customers_node: Node2D = $Customers
@onready var staff_node: Node2D = $Staff
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hud: TavernHUD = $HUD
@onready var camera: TavernCamera = $Camera

var _waiting_for_last_guests: bool = false
# Guests waiting outside for a table, first in line first.
var _line: Array[Customer] = []


func _ready() -> void:
	hud.build_selected.connect(_on_build_selected)
	hud.day_start_requested.connect(_on_day_start_requested)
	hud.staff_change_requested.connect(_on_staff_change_requested)
	hud.new_game_requested.connect(_on_new_game_requested)
	# You can connect a signal straight to another node's function.
	grid.build_message.connect(hud.show_message)
	camera.tapped.connect(grid.handle_tap)
	camera.bounds = grid.floor_rect()
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	GameManager.shop_closed.connect(_on_shop_closed)
	# Building or selling between days changes the save, so save again.
	grid.layout_changed.connect(_save_if_closed)
	GameManager.recipes_changed.connect(_save_if_closed)
	# A newly built table can seat whoever is first in line.
	grid.layout_changed.connect(_seat_from_line)

	var save: Dictionary = GameManager.load_game()
	if save.is_empty():
		# New game: one cook and one waiter. They walk in through the door.
		_hire("cook")
		_hire("waiter")
		hud.show_summary(
			"Welcome to\nThe Drunken Dragon!\n\nGuests sit at Tables. Waiters take orders and carry food; Cooks work the Hearths. Staff get paid every night.\n\nHappy patrons share recipe ideas, and quests teach you more. See Recipes.\n\nDrag to look around and pinch to zoom.")
	else:
		grid.load_layout(save.get("furniture", []))
		# clampi keeps a number within limits, in case the file was edited.
		for i in clampi(int(save.get("cooks", 1)), 1, MAX_STAFF):
			_hire("cook")
		for i in clampi(int(save.get("waiters", 1)), 1, MAX_STAFF):
			_hire("waiter")
		# Day 0 means they built or hired before ever opening.
		var progress: String = "Day %d is done." % GameManager.day if GameManager.day > 0 \
				else "Your tavern is ready for its first day."
		hud.show_summary(
			"Welcome back to\nThe Drunken Dragon!\n\n%s\nGold: %d\nFame: %d" % [progress, GameManager.gold, GameManager.fame],
			true)
	_update_staff_display()
	hud.set_day_button("Open\nDay %d" % (GameManager.day + 1), true)


func _process(_delta: float) -> void:
	# After closing, wait until every guest has walked out the door.
	# get_nodes_in_group asks for every node tagged "customers".
	if _waiting_for_last_guests and get_tree().get_nodes_in_group("customers").is_empty():
		_waiting_for_last_guests = false
		_show_day_summary()


func _on_day_start_requested() -> void:
	if GameManager.is_open or _waiting_for_last_guests:
		return
	GameManager.open_shop()
	hud.set_day_button("Open", false)
	spawn_timer.start(2.0)   # first guest arrives 2 seconds after opening


func _on_build_selected(type: String) -> void:
	grid.build_type = type


# ---------------------------------------------------------------------
# Guests and the waiting line
# ---------------------------------------------------------------------
func _on_spawn_timer_timeout() -> void:
	var noble: bool = randf() < GameManager.noble_chance()
	var cell: Vector2i = grid.find_free_table()
	# Nobody jumps the line: a free table goes to the line first.
	if cell != TavernGrid.NO_CELL and _line.is_empty():
		var customer: Customer = _spawn_customer(noble)
		_seat(customer, cell)
	elif _line.size() < MAX_LINE:
		var customer: Customer = _spawn_customer(noble)
		_line.append(customer)
		customer.wait_in_line(_line_spot(_line.size() - 1))
	else:
		# A long line hurts your reputation, so more fame alone can't
		# outgrow your seating.
		GameManager.today_turned_away += 1
		GameManager.change_fame(-1)
		hud.show_message("The line is full! A guest left (-1 fame)")
	# Restart with a fresh interval — higher fame means shorter waits.
	spawn_timer.start(GameManager.get_spawn_interval())


func _spawn_customer(noble: bool) -> Customer:
	# instantiate() creates a brand-new guest from the blueprint...
	var customer: Customer = CUSTOMER_SCENE.instantiate()
	# ...but it isn't in the game until it's added to the scene tree.
	customers_node.add_child(customer)
	customer.setup(grid, noble)
	customer.left_tavern.connect(_on_customer_left)
	return customer


func _seat(customer: Customer, cell: Vector2i) -> void:
	grid.reserve_table(cell, customer)
	customer.take_table(cell)


# The line runs left along the outside wall, starting beside the door.
func _line_spot(place: int) -> Vector2:
	return grid.door_position() + Vector2(-60.0 - place * LINE_GAP, 0.0)


# Give free tables to the front of the line, then shuffle everyone up.
func _seat_from_line() -> void:
	while not _line.is_empty():
		var cell: Vector2i = grid.find_free_table()
		if cell == TavernGrid.NO_CELL:
			break
		_seat(_line.pop_front(), cell)
	for i in _line.size():
		_line[i].move_up_in_line(_line_spot(i))


func _on_customer_left(customer: Customer, _happy: bool) -> void:
	grid.release_table(customer.table_cell)
	_line.erase(customer)

	match customer.leave_reason:
		"served":
			GameManager.today_served += 1
			if customer.is_noble:
				GameManager.today_nobles_served += 1
			GameManager.record_served(customer.order["id"], customer.is_noble)
			GameManager.change_fame(2 if customer.is_noble else 1)
		"impatient":
			# Nobles matter more to your reputation.
			GameManager.today_walkouts += 1
			GameManager.change_fame(-3 if customer.is_noble else -2)
		"no_dish":
			GameManager.today_disappointed += 1
			GameManager.change_fame(-1)
		"gave_up_line":
			GameManager.today_turned_away += 1
			GameManager.change_fame(-1)
		# "closed": sent home at closing time, no fame change.

	_announce_unlocks(GameManager.check_unlocks(), customer)
	_seat_from_line()


# Tells the player about recipes they just earned. A regular who shares
# an idea says it out loud on the way out.
func _announce_unlocks(ids: Array[String], speaker: Customer) -> void:
	for id in ids:
		var recipe: Dictionary = GameManager.RECIPES[id]
		var unlock: Dictionary = recipe["unlock"]
		if unlock["by"] == "patron":
			hud.show_message("%s shared a recipe: %s!" % [unlock["who"], recipe["name"]], 5.0)
			if speaker != null and unlock["stat"] == "served":
				speaker.say("Try %s!" % recipe["name"])
		else:
			hud.show_message("Quest done: %s! New recipe: %s." % [unlock["title"], recipe["name"]], 5.0)


func _on_shop_closed(_day: int) -> void:
	spawn_timer.stop()
	hud.show_message("Closing time! Finishing last orders...")
	# Nobody new gets in, so the line goes home.
	for customer in _line.duplicate():
		customer.send_home()
	_line.clear()
	_waiting_for_last_guests = true


# ---------------------------------------------------------------------
# Staff
# ---------------------------------------------------------------------
func _on_staff_change_requested(role: String, change: int) -> void:
	# Changing staff mid-shift would leave orders half-done, so it's
	# only allowed while the tavern is closed.
	if GameManager.is_open or _waiting_for_last_guests:
		hud.show_message("Hire or fire staff after closing time.")
		return
	var group: String = role + "s"   # "cooks" or "waiters"
	var staff: Array[Node] = get_tree().get_nodes_in_group(group)
	var info: Dictionary = GameManager.STAFF[role]
	if change > 0:
		if staff.size() >= MAX_STAFF:
			hud.show_message("That's plenty of %ss!" % info["name"].to_lower())
			return
		_hire(role)
		hud.show_message("Hired a %s (%dg/day)." % [info["name"], info["wage"]])
	else:
		# Without at least one of each, nobody could ever be served.
		if staff.size() <= 1:
			hud.show_message("You need at least one %s." % info["name"].to_lower())
			return
		staff.back().leave()   # the newest one walks out
		hud.show_message("Let a %s go." % info["name"].to_lower())
	_update_staff_display()
	_save_if_closed()


func _hire(role: String) -> void:
	var scene: PackedScene = COOK_SCENE if role == "cook" else WAITER_SCENE
	var person: Walker = scene.instantiate()
	staff_node.add_child(person)
	person.setup(grid, grid.door_position())


func _update_staff_display() -> void:
	var cooks: int = get_tree().get_nodes_in_group("cooks").size()
	var waiters: int = get_tree().get_nodes_in_group("waiters").size()
	hud.set_staff(cooks, waiters, GameManager.daily_wages(cooks, waiters))


# ---------------------------------------------------------------------
# Saving, new game, end of day
# ---------------------------------------------------------------------
func _on_new_game_requested() -> void:
	GameManager.delete_save()
	GameManager.reset()
	# Throw away the whole scene and build it fresh, like starting the game.
	get_tree().reload_current_scene()


func _save_if_closed() -> void:
	# Mid-day changes are saved at the end of the day instead.
	if GameManager.is_open or _waiting_for_last_guests:
		return
	GameManager.save_game(grid.get_layout(),
			get_tree().get_nodes_in_group("cooks").size(),
			get_tree().get_nodes_in_group("waiters").size())


func _show_day_summary() -> void:
	var wages: int = GameManager.daily_wages(
			get_tree().get_nodes_in_group("cooks").size(),
			get_tree().get_nodes_in_group("waiters").size())
	GameManager.pay_wages(wages)
	GameManager.finish_day()
	_announce_unlocks(GameManager.check_unlocks(), null)
	_save_if_closed()

	var text := "Day %d complete!\n\nIncome: %dg\nWages: -%dg\nProfit: %dg\n\nGuests served: %d (nobles: %d)\nWalk-outs: %d\nTurned away: %d" % [
		GameManager.day,
		GameManager.today_income,
		wages,
		GameManager.today_income - wages,
		GameManager.today_served,
		GameManager.today_nobles_served,
		GameManager.today_walkouts,
		GameManager.today_turned_away,
	]
	if GameManager.today_disappointed > 0:
		text += "\nNothing they liked: %d" % GameManager.today_disappointed
	text += "\n\nFame: %d\nGold: %d" % [GameManager.fame, GameManager.gold]
	if not GameManager.today_unlocked.is_empty():
		var names: Array[String] = []
		for id in GameManager.today_unlocked:
			names.append(GameManager.RECIPES[id]["name"])
		text += "\n\nNew recipes: %s" % ", ".join(names)
	hud.show_summary(text, true)
	hud.set_day_button("Open\nDay %d" % (GameManager.day + 1), true)
