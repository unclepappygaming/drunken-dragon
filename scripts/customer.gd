# =====================================================================
# customer.gd  —  one guest. Attached to scenes/customer.tscn.
#
# Each guest runs a small STATE MACHINE: it is always in exactly one
# state, and each frame it only does what that state says.
#
#   WALKING_IN -> ORDERING -> WAITING_FOR_FOOD -> EATING -> LEAVING
#                                    |
#                                    +-- patience runs out --> LEAVING (angry)
#
# Art is placeholder shapes drawn with _draw(); the art pass swaps these
# for sprites later.
# =====================================================================

# class_name registers "Customer" as a type the whole project knows.
# That's why GameManager can have an Array[Customer].
class_name Customer
extends Node2D

# Fired the moment a guest gets up to leave. main.gd listens so it can
# free the table and change fame. happy = paid and left satisfied.
signal left_tavern(customer: Customer, happy: bool)

enum State { WALKING_IN, ORDERING, WAITING_FOR_FOOD, EATING, LEAVING }

const WALK_SPEED: float = 170.0      # pixels per second
const MAX_PATIENCE: float = 25.0     # seconds they'll wait for food
const ORDER_THINK_TIME: float = 1.5
const EAT_TIME: float = 4.0

var state: State = State.WALKING_IN
var table_cell: Vector2i             # which grid square their table is on
var order: Dictionary = {}           # one entry from GameManager.MENU
var patience: float = MAX_PATIENCE

var _walk_target: Vector2
var _exit_point: Vector2
var _timer: float = 0.0
var _bubble: String = ""             # text shown above their head
var _color: Color


# Called by main.gd right after the guest is created. We can't pass
# arguments to instantiate(), so a setup() function is the usual pattern.
func setup(door_pos: Vector2, seat_pos: Vector2, cell: Vector2i) -> void:
	position = door_pos
	_exit_point = door_pos
	_walk_target = seat_pos
	table_cell = cell
	_color = Color.from_hsv(randf(), 0.45, 0.95)   # random shirt color

	# GROUPS are tags. Putting every guest in "customers" lets main.gd ask
	# "how many guests are still here?" with one line, without keeping
	# its own list. A node leaves its groups automatically when freed.
	add_to_group("customers")


func _process(delta: float) -> void:
	match state:
		State.WALKING_IN:
			if _walk_toward_target(delta):
				state = State.ORDERING
				_timer = ORDER_THINK_TIME
				_bubble = "..."

		State.ORDERING:
			_timer -= delta
			if _timer <= 0.0:
				order = GameManager.MENU.pick_random()
				_bubble = order["name"]
				# Join the line. A free Hearth will pick us up.
				GameManager.order_queue.append(self)
				state = State.WAITING_FOR_FOOD

		State.WAITING_FOR_FOOD:
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
			if _walk_toward_target(delta):
				# queue_free() deletes this node safely at the end of the frame.
				queue_free()

	# Ask Godot to call _draw() again so the patience bar animates.
	queue_redraw()


# Called by a Hearth when the dish is ready. Returns false if the guest
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
	_walk_target = _exit_point
	GameManager.order_queue.erase(self)   # stop waiting for a cook
	left_tavern.emit(self, happy)


# Moves a step toward the target. Returns true once we've arrived.
# (Straight lines for now — Milestone 2 adds proper pathfinding.)
func _walk_toward_target(delta: float) -> bool:
	position = position.move_toward(_walk_target, WALK_SPEED * delta)
	return position.distance_to(_walk_target) < 1.0


# _draw() paints this node using simple shapes. (0, 0) is the guest's
# own position, so everything is drawn relative to them.
func _draw() -> void:
	draw_circle(Vector2(0, 0), 18.0, _color)                    # body
	draw_circle(Vector2(0, -26), 11.0, Color(1.0, 0.85, 0.7))   # head

	if state == State.WAITING_FOR_FOOD:
		var ratio: float = patience / MAX_PATIENCE
		draw_rect(Rect2(-25, 22, 50, 7), Color(0.15, 0.15, 0.15))
		# Green when patient, fading to red.
		draw_rect(Rect2(-25, 22, 50 * ratio, 7), Color(1.0 - ratio, ratio, 0.2))

	if _bubble != "":
		draw_rect(Rect2(-75, -72, 150, 28), Color(0, 0, 0, 0.65))
		draw_string(ThemeDB.fallback_font, Vector2(-75, -51), _bubble,
				HORIZONTAL_ALIGNMENT_CENTER, 150, 20, Color.WHITE)
