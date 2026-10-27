# =====================================================================
# main.gd  —  the "director". Attached to the root Main node.
#
# It doesn't do much itself; it wires the other pieces together:
#   * spawns guests on a timer
#   * tells the grid which build tool the HUD selected
#   * frees tables and changes fame when guests leave
#   * shows the end-of-day summary once the last guest is gone
# =====================================================================
extends Node2D

# preload() loads the customer scene once, when the game starts.
# A PackedScene is a "blueprint"; instantiate() stamps out a new copy.
const CUSTOMER_SCENE: PackedScene = preload("res://scenes/customer.tscn")

# @onready waits until this node and its children exist, then fills in
# the variable. Without it, $TavernGrid would be looked up too early
# (before the children are ready) and come back empty.
# $TavernGrid is shorthand for get_node("TavernGrid") — a child by name.
@onready var grid: TavernGrid = $TavernGrid
@onready var customers_node: Node2D = $Customers
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hud: TavernHUD = $HUD

var _waiting_for_last_guests: bool = false


func _ready() -> void:
	hud.build_selected.connect(_on_build_selected)
	hud.day_start_requested.connect(_on_day_start_requested)
	# You can connect a signal straight to another node's function.
	grid.build_message.connect(hud.show_message)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	GameManager.shop_closed.connect(_on_shop_closed)

	hud.show_summary(
		"Welcome to\nThe Drunken Dragon!\n\nGuests sit at Tables and wait for a Hearth to cook. Build more to serve more!",
		"Open Day 1")


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
		hud.show_message("A guest found no free table...")
	else:
		_spawn_customer(cell)
	# Restart with a fresh interval — higher fame means shorter waits.
	spawn_timer.start(GameManager.get_spawn_interval())


func _spawn_customer(cell: Vector2i) -> void:
	# instantiate() creates a brand-new guest from the blueprint...
	var customer: Customer = CUSTOMER_SCENE.instantiate()
	# ...but it isn't in the game until it's added to the scene tree.
	customers_node.add_child(customer)
	customer.setup(grid.door_position(), grid.cell_center(cell) + Vector2(0, 12), cell)
	grid.reserve_table(cell, customer)
	customer.left_tavern.connect(_on_customer_left)


func _on_customer_left(customer: Customer, happy: bool) -> void:
	grid.release_table(customer.table_cell)
	if happy:
		GameManager.today_served += 1
		GameManager.change_fame(1)
	else:
		GameManager.today_walkouts += 1
		GameManager.change_fame(-2)


func _on_shop_closed(_day: int) -> void:
	spawn_timer.stop()
	hud.show_message("Closing time! Finishing last orders...")
	_waiting_for_last_guests = true


func _show_day_summary() -> void:
	var text := "Day %d complete!\n\nIncome: %dg\nGuests served: %d\nWalk-outs: %d\n\nFame: %d\nGold: %d" % [
		GameManager.day,
		GameManager.today_income,
		GameManager.today_served,
		GameManager.today_walkouts,
		GameManager.fame,
		GameManager.gold,
	]
	hud.show_summary(text, "Open Day %d" % (GameManager.day + 1))
