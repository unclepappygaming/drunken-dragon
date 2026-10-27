# =====================================================================
# customer.gd  —  one guest. Attached to scenes/customer.tscn.
#
# Each guest runs a small STATE MACHINE: it is always in exactly one
# state, and each frame it only does what that state says.
#
#   WALKING_IN -> DECIDING -> WAITING_FOR_WAITER -> WAITING_FOR_FOOD -> EATING -> LEAVING
#                                    |                      |
#                                    +-- patience runs out -+--> LEAVING (angry)
#
# Guests sit on a free square NEXT TO their table. A Waiter comes to
# take the order, a Cook cooks it, and a Waiter carries it over.
# Walking around furniture comes from walker.gd (see "extends Walker").
#
# Art is placeholder shapes drawn with _draw(); the art pass swaps these
# for sprites later.
# =====================================================================

# class_name registers "Customer" as a type the whole project knows.
# That's why GameManager can have an Array[Customer].
class_name Customer
extends Walker

# Fired the moment a guest gets up to leave. main.gd listens so it can
# free the table and change fame. happy = paid and left satisfied.
signal left_tavern(customer: Customer, happy: bool)

enum State { WALKING_IN, DECIDING, WAITING_FOR_WAITER, WAITING_FOR_FOOD, EATING, LEAVING }

const WALK_SPEED: float = 170.0      # pixels per second
# Seconds they'll wait in total, from calling the waiter to getting food.
const MAX_PATIENCE: float = 40.0
const DECIDE_TIME: float = 1.5
const EAT_TIME: float = 4.0

var state: State = State.WALKING_IN
var table_cell: Vector2i             # which grid square their table is on
var order: Dictionary = {}           # one entry from GameManager.MENU
var patience: float = MAX_PATIENCE

var _timer: float = 0.0
var _bubble: String = ""             # text shown above their head
var _color: Color


# Called by main.gd right after the guest is created. We can't pass
# arguments to instantiate(), so a setup() function is the usual pattern.
func setup(tavern_grid: TavernGrid, cell: Vector2i) -> void:
	_setup_walker(tavern_grid, tavern_grid.door_position())
	speed = WALK_SPEED
	table_cell = cell
	_color = Color.from_hsv(randf(), 0.45, 0.95)   # random shirt color

	# GROUPS are tags. Putting every guest in "customers" lets main.gd ask
	# "how many guests are still here?" with one line, without keeping
	# its own list. A node leaves its groups automatically when freed.
	add_to_group("customers")

	# Sit on a free square beside the table, not on top of it.
	go_to_cell(grid.access_cell(cell, position, self))


func _process(delta: float) -> void:
	match state:
		State.WALKING_IN:
			if _walk(delta):
				state = State.DECIDING
				_timer = DECIDE_TIME
				_bubble = "..."

		State.DECIDING:
			_timer -= delta
			if _timer <= 0.0:
				order = GameManager.MENU.pick_random()
				_bubble = "Waiter!"
				# Join the line. A free Waiter will come and take the order.
				GameManager.order_requests.append(self)
				state = State.WAITING_FOR_WAITER

		# Two states can share one block by listing both.
		State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD:
			patience -= delta
			if patience <= 0.0:
				_bubble = "Hmph!"
				_start_leaving(false)

		State.EATING:
			_timer -= delta
			if _timer <= 0.0:
				var price: int = order["price"]
				GameManager.earn(price)
				_bubble = "+%dg" % price
				_start_leaving(true)

		State.LEAVING:
			if _walk(delta):
				# queue_free() deletes this node safely at the end of the frame.
				queue_free()

	# Ask Godot to call _draw() again so the patience bar animates.
	queue_redraw()


# Called by a Waiter once they've written the order down. The order
# then joins the kitchen's line for a Hearth to cook.
func take_order() -> void:
	if state != State.WAITING_FOR_WAITER:
		return
	_bubble = order["name"]
	GameManager.order_queue.append(self)
	state = State.WAITING_FOR_FOOD


# Called by a Waiter arriving with the dish. Returns false if the guest
# already gave up (the food is simply wasted).
func serve_food() -> bool:
	if state != State.WAITING_FOR_FOOD:
		return false
	state = State.EATING
	_timer = EAT_TIME
	_bubble = "Yum!"
	return true


func _start_leaving(happy: bool) -> void:
	state = State.LEAVING
	go_out_door()
	# Stop waiting for a waiter or a cook.
	GameManager.order_requests.erase(self)
	GameManager.order_queue.erase(self)
	left_tavern.emit(self, happy)


# _draw() paints this node using simple shapes. (0, 0) is the guest's
# own position, so everything is drawn relative to them.
func _draw() -> void:
	draw_circle(Vector2(0, 0), 18.0, _color)                    # body
	draw_circle(Vector2(0, -26), 11.0, Color(1.0, 0.85, 0.7))   # head

	if state == State.WAITING_FOR_WAITER or state == State.WAITING_FOR_FOOD:
		var ratio: float = patience / MAX_PATIENCE
		draw_rect(Rect2(-25, 22, 50, 7), Color(0.15, 0.15, 0.15))
		# Green when patient, fading to red.
		draw_rect(Rect2(-25, 22, 50 * ratio, 7), Color(1.0 - ratio, ratio, 0.2))

	if _bubble != "":
		draw_rect(Rect2(-90, -72, 180, 28), Color(0, 0, 0, 0.65))
		draw_string(ThemeDB.fallback_font, Vector2(-90, -51), _bubble,
				HORIZONTAL_ALIGNMENT_CENTER, 180, 19, Color.WHITE)
