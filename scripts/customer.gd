# =====================================================================
# customer.gd  —  one guest. Attached to scenes/customer.tscn.
#
# Each guest runs a small STATE MACHINE: it is always in exactly one
# state, and each frame it only does what that state says.
#
#   (IN_LINE) -> WALKING_IN -> DECIDING -> WAITING_FOR_WAITER -> WAITING_FOR_FOOD -> EATING -> LEAVING
#       |                                       |                      |
#       +---------- patience runs out ----------+----------------------+--> LEAVING (angry)
#
# IN_LINE: no table was free, so they wait outside the door until
# main.gd gives them one with take_table().
#
# Nobles (is_noble) only order fancy tier 3 dishes. Anyone who finds
# nothing they like on today's menu leaves unhappy.
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
# free the table and change fame. happy = paid and left satisfied;
# leave_reason says exactly why they left.
signal left_tavern(customer: Customer, happy: bool)

enum State { IN_LINE, WALKING_IN, DECIDING, WAITING_FOR_WAITER, WAITING_FOR_FOOD, EATING, LEAVING }

const WALK_SPEED: float = 170.0      # pixels per second
# Seconds they'll wait in total, from calling the waiter to getting food.
const MAX_PATIENCE: float = 40.0
# Seconds they'll stand in the waiting line before giving up.
const LINE_PATIENCE: float = 30.0
const DECIDE_TIME: float = 1.5
const EAT_TIME: float = 4.0

var state: State = State.WALKING_IN
var table_cell: Vector2i = TavernGrid.NO_CELL   # their table (none while in line)
var order: Dictionary = {}           # one entry from GameManager.RECIPES
var is_noble: bool = false
var patience: float = MAX_PATIENCE
# Why they left: "served", "impatient", "no_dish", "gave_up_line" or "closed".
var leave_reason: String = ""

var _patience_max: float = MAX_PATIENCE   # what the patience bar counts down from
# Extra share of the price they'll pay: from a Tavern Cook's portions or
# a lucky tip. Nobles also tip on top (GameManager.NOBLE_TIP).
var price_bonus: float = 0.0
var _timer: float = 0.0
var _bubble: String = ""             # text shown above their head
var _color: Color


# Called by main.gd right after the guest is created. We can't pass
# arguments to instantiate(), so a setup() function is the usual pattern.
# Then main.gd either seats them (take_table) or lines them up (wait_in_line).
func setup(tavern_grid: TavernGrid, noble: bool = false) -> void:
	_setup_walker(tavern_grid, tavern_grid.door_position())
	speed = WALK_SPEED
	is_noble = noble
	# Nobles wear royal purple; everyone else gets a random shirt color.
	_color = Color(0.5, 0.25, 0.7) if noble else Color.from_hsv(randf(), 0.45, 0.95)

	# GROUPS are tags. Putting every guest in "customers" lets main.gd ask
	# "how many guests are still here?" with one line, without keeping
	# its own list. A node leaves its groups automatically when freed.
	add_to_group("customers")


func take_table(cell: Vector2i) -> void:
	table_cell = cell
	state = State.WALKING_IN
	_bubble = ""
	patience = MAX_PATIENCE
	_patience_max = MAX_PATIENCE
	# Sit on a free square beside the table, not on top of it.
	go_to_cell(grid.access_cell(cell, position, self))


func wait_in_line(spot: Vector2) -> void:
	state = State.IN_LINE
	patience = LINE_PATIENCE
	_patience_max = LINE_PATIENCE
	go_to_outside_spot(spot)


# Someone ahead left or got a table: step forward without resetting patience.
func move_up_in_line(spot: Vector2) -> void:
	go_to_outside_spot(spot)


# Closing time while still in line: go home, no hard feelings.
func send_home() -> void:
	_bubble = "Closed already?"
	_start_leaving("closed")


func say(text: String) -> void:
	_bubble = text


# Smooth Talker: a charming waiter buys some extra patience.
func calm(seconds: float) -> void:
	patience = minf(patience + seconds, _patience_max)


func add_tip(share: float, text: String) -> void:
	price_bonus += share
	_bubble = text


func _process(delta: float) -> void:
	match state:
		State.IN_LINE:
			_walk(delta)   # to our spot in the line
			patience -= delta
			if patience <= 0.0:
				_bubble = "Too long!"
				_start_leaving("gave_up_line")

		State.WALKING_IN:
			if _walk(delta):
				state = State.DECIDING
				_timer = DECIDE_TIME
				_bubble = "..."

		State.DECIDING:
			_timer -= delta
			if _timer <= 0.0:
				order = GameManager.pick_order(is_noble)
				if order.is_empty():
					_bubble = "Nothing fancy enough!" if is_noble else "Nothing I like!"
					_start_leaving("no_dish")
					return
				_bubble = "Waiter!"
				# Join the line. A free Waiter will come and take the order.
				GameManager.order_requests.append(self)
				state = State.WAITING_FOR_WAITER

		# Two states can share one block by listing both.
		State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD:
			patience -= delta
			if patience <= 0.0:
				_bubble = "Hmph!"
				_start_leaving("impatient")

		State.EATING:
			_timer -= delta
			if _timer <= 0.0:
				var share: float = 1.0 + price_bonus
				if is_noble:
					share += GameManager.NOBLE_TIP   # nobles tip well
				var price: int = roundi(order["price"] * share)
				GameManager.earn(price)
				_bubble = "+%dg" % price
				_start_leaving("served")

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


func _start_leaving(reason: String) -> void:
	leave_reason = reason
	state = State.LEAVING
	go_out_door()
	# Stop waiting for a waiter or a cook.
	GameManager.order_requests.erase(self)
	GameManager.order_queue.erase(self)
	left_tavern.emit(self, reason == "served")


# _draw() paints this node using simple shapes. (0, 0) is the guest's
# own position, so everything is drawn relative to them.
func _draw() -> void:
	draw_circle(Vector2(0, 0), 18.0, _color)                    # body
	draw_circle(Vector2(0, -26), 11.0, Color(1.0, 0.85, 0.7))   # head
	if is_noble:
		# A gold crown: a polygon is a shape drawn from a list of corners.
		draw_colored_polygon(PackedVector2Array([
			Vector2(-10, -34), Vector2(10, -34), Vector2(10, -45), Vector2(5, -39),
			Vector2(0, -47), Vector2(-5, -39), Vector2(-10, -45),
		]), Color(1.0, 0.8, 0.2))

	if state in [State.IN_LINE, State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD]:
		var ratio: float = patience / _patience_max
		draw_rect(Rect2(-25, 22, 50, 7), Color(0.15, 0.15, 0.15))
		# Green when patient, fading to red.
		draw_rect(Rect2(-25, 22, 50 * ratio, 7), Color(1.0 - ratio, ratio, 0.2))

	if _bubble != "":
		draw_rect(Rect2(-90, -72, 180, 28), Color(0, 0, 0, 0.65))
		draw_string(ThemeDB.fallback_font, Vector2(-90, -51), _bubble,
				HORIZONTAL_ALIGNMENT_CENTER, 180, 19, Color.WHITE)
