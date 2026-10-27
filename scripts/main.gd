# =====================================================================
# main.gd  —  the "director". Attached to the root Main node.
#
# It doesn't do much itself; it wires the other pieces together:
#   * spawns guests on a timer
#   * hires and lets go of staff (only between days)
#   * tells the grid which build tool the HUD selected
#   * decides which guests are nobles
#   * frees tables and changes fame when guests leave
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

# @onready waits until this node and its children exist, then fills in
# the variable. Without it, $TavernGrid would be looked up too early
# (before the children are ready) and come back empty.
# $TavernGrid is shorthand for get_node("TavernGrid") — a child by name.
@onready var grid: TavernGrid = $TavernGrid
@onready var customers_node: Node2D = $Customers
@onready var staff_node: Node2D = $Staff
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hud: TavernHUD = $HUD

var _waiting_for_last_guests: bool = false


func _ready() -> void:
	hud.build_selected.connect(_on_build_selected)
	hud.day_start_requested.connect(_on_day_start_requested)
	hud.staff_change_requested.connect(_on_staff_change_requested)
	hud.new_game_requested.connect(_on_new_game_requested)
	# You can connect a signal straight to another node's function.
	grid.build_message.connect(hud.show_message)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	GameManager.shop_closed.connect(_on_shop_closed)
	# Building or selling between days changes the save, so save again.
	grid.layout_changed.connect(_save_if_closed)
	GameManager.recipes_changed.connect(_save_if_closed)

	var save: Dictionary = GameManager.load_game()
	if save.is_empty():
		# New game: one cook and one waiter. They walk in through the door.
		_hire("cook")
		_hire("waiter")
		hud.show_summary(
			"Welcome to\nThe Drunken Dragon!\n\nGuests sit at Tables. Waiters take orders and carry food; Cooks work the Hearths. Staff get paid every night.\n\nLearn new dishes in Menu & Recipes.",
			"Open Day 1")
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
			"Open Day %d" % (GameManager.day + 1), true)
	_update_staff_display()


func _process(_delta: float) -> void:
	# After closing, wait until every guest has walked out the door.
	# get_nodes_in_group asks for every node tagged "customers".
	if _waiting_for_last_guests and get_tree().get_nodes_in_group("customers").is_empty():
		_waiting_for_last_guests = false
		_show_day_summary()


func _on_day_start_requested() -> void:
	GameManager.open_shop()
	spawn_timer.start(2.0)   # first guest arrives 2 seconds after opening


func _on_build_selected(type: String) -> void:
	grid.build_type = type


func _on_spawn_timer_timeout() -> void:
	var cell: Vector2i = grid.find_free_table()
	if cell == TavernGrid.NO_CELL:
		# A full tavern hurts your reputation, so more fame alone can't
		# outgrow your seating.
		GameManager.today_turned_away += 1
		GameManager.change_fame(-1)
		hud.show_message("No free table! A guest left (-1 fame)")
	else:
		_spawn_customer(cell)
	# Restart with a fresh interval — higher fame means shorter waits.
	spawn_timer.start(GameManager.get_spawn_interval())


func _spawn_customer(cell: Vector2i) -> void:
	# instantiate() creates a brand-new guest from the blueprint...
	var customer: Customer = CUSTOMER_SCENE.instantiate()
	# ...but it isn't in the game until it's added to the scene tree.
	customers_node.add_child(customer)
	var noble: bool = randf() < GameManager.noble_chance()
	customer.setup(grid, cell, noble)
	grid.reserve_table(cell, customer)
	customer.left_tavern.connect(_on_customer_left)


func _on_customer_left(customer: Customer, happy: bool) -> void:
	grid.release_table(customer.table_cell)
	# Nobles matter more to your reputation, both ways.
	if happy:
		GameManager.today_served += 1
		if customer.is_noble:
			GameManager.today_nobles_served += 1
		GameManager.change_fame(3 if customer.is_noble else 1)
	else:
		GameManager.today_walkouts += 1
		GameManager.change_fame(-3 if customer.is_noble else -2)


func _on_shop_closed(_day: int) -> void:
	spawn_timer.stop()
	hud.show_message("Closing time! Finishing last orders...")
	_waiting_for_last_guests = true


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


func _hire(role: String) -> void:
	var scene: PackedScene = COOK_SCENE if role == "cook" else WAITER_SCENE
	var person: Walker = scene.instantiate()
	staff_node.add_child(person)
	person.setup(grid, grid.door_position())


func _update_staff_display() -> void:
	var cooks: int = get_tree().get_nodes_in_group("cooks").size()
	var waiters: int = get_tree().get_nodes_in_group("waiters").size()
	hud.set_staff(cooks, waiters, GameManager.daily_wages(cooks, waiters))


func _show_day_summary() -> void:
	var wages: int = GameManager.daily_wages(
			get_tree().get_nodes_in_group("cooks").size(),
			get_tree().get_nodes_in_group("waiters").size())
	GameManager.pay_wages(wages)
	_save_if_closed()
	var text := "Day %d complete!\n\nIncome: %dg\nWages: -%dg\nProfit: %dg\n\nGuests served: %d (nobles: %d)\nWalk-outs: %d\nTurned away: %d\n\nFame: %d\nGold: %d" % [
		GameManager.day,
		GameManager.today_income,
		wages,
		GameManager.today_income - wages,
		GameManager.today_served,
		GameManager.today_nobles_served,
		GameManager.today_walkouts,
		GameManager.today_turned_away,
		GameManager.fame,
		GameManager.gold,
	]
	hud.show_summary(text, "Open Day %d" % (GameManager.day + 1), true)
