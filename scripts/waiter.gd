# =====================================================================
# waiter.gd  —  one waiter. Attached to scenes/waiter.tscn.
#
# Waiters do two jobs, always picking finished food first (a plate left
# on a Hearth stops it cooking the next dish):
#
#   take an order:  IDLE -> TO_GUEST -> TAKING_ORDER -> IDLE
#   serve food:     IDLE -> TO_HEARTH -> CARRYING -> IDLE
#
# If the guest storms out halfway, the waiter gives up and goes back to
# IDLE (any food they were carrying is wasted). LEAVING is used when
# the player lets them go.
# =====================================================================
class_name Waiter
extends Walker

enum State { IDLE, TO_GUEST, TAKING_ORDER, TO_HEARTH, CARRYING, LEAVING }

const WALK_SPEED: float = 220.0
const ORDER_TAKE_TIME: float = 1.0

var state: State = State.IDLE

var _guest: Customer = null                 # who we're working for
var _hearth: Vector2i = TavernGrid.NO_CELL  # where we're fetching food
var _timer: float = 0.0


func setup(tavern_grid: TavernGrid, start_pos: Vector2) -> void:
	_setup_walker(tavern_grid, start_pos)
	speed = WALK_SPEED
	add_to_group("waiters")


func _process(delta: float) -> void:
	match state:
		State.IDLE:
			_find_task()

		State.TO_GUEST:
			if not _guest_is(Customer.State.WAITING_FOR_WAITER):
				_give_up()
			elif _walk(delta):
				state = State.TAKING_ORDER
				_timer = ORDER_TAKE_TIME

		State.TAKING_ORDER:
			if not _guest_is(Customer.State.WAITING_FOR_WAITER):
				_give_up()
			else:
				_timer -= delta
				if _timer <= 0.0:
					_guest.take_order()
					_guest = null
					state = State.IDLE

		State.TO_HEARTH:
			# The grid clears a plate if its guest leaves before we get there.
			if not grid.is_plate_waiting(_hearth, self):
				_hearth = TavernGrid.NO_CELL
				_give_up()
			elif _walk(delta):
				_guest = grid.pick_up_plate(_hearth)
				_hearth = TavernGrid.NO_CELL
				if _guest == null:
					state = State.IDLE
				else:
					go_to_cell(grid.access_cell(_guest.table_cell, position, self))
					state = State.CARRYING

		State.CARRYING:
			if not _guest_is(Customer.State.WAITING_FOR_FOOD):
				_give_up()   # they left; the plate is wasted
			elif _walk(delta):
				_guest.serve_food()
				_guest = null
				state = State.IDLE

		State.LEAVING:
			if _walk(delta):
				queue_free()

	queue_redraw()


# Called by main.gd when the player lets this waiter go.
func leave() -> void:
	remove_from_group("waiters")
	state = State.LEAVING
	go_out_door()


func _find_task() -> void:
	# Finished food first.
	var hearth: Vector2i = grid.claim_ready_plate(self)
	if hearth != TavernGrid.NO_CELL:
		_hearth = hearth
		go_to_cell(grid.access_cell(hearth, position, self))
		state = State.TO_HEARTH
		return

	var guest: Customer = GameManager.next_order_request()
	if guest != null:
		_guest = guest
		go_to_cell(grid.access_cell(guest.table_cell, position, self))
		state = State.TO_GUEST


func _give_up() -> void:
	_guest = null
	stop()
	state = State.IDLE


# is_instance_valid: the guest may already be deleted, and touching a
# deleted node crashes.
func _guest_is(guest_state: Customer.State) -> bool:
	return is_instance_valid(_guest) and _guest.state == guest_state


func _draw() -> void:
	draw_circle(Vector2(0, 0), 18.0, Color(0.15, 0.3, 0.25))    # dark green vest
	draw_rect(Rect2(-8, -4, 16, 20), Color(0.9, 0.9, 0.85))     # apron
	draw_circle(Vector2(0, -26), 11.0, Color(1.0, 0.85, 0.7))   # head
	if state == State.CARRYING:
		draw_circle(Vector2(22, -6), 11.0, Color.WHITE)          # plate
		draw_circle(Vector2(22, -6), 7.0, Color(0.85, 0.55, 0.2))  # food
