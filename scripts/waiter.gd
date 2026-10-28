# =====================================================================
# waiter.gd  —  one waiter. Attached to scenes/waiter.tscn.
#
# Waiters do three jobs, in this order (a full pass makes cooks wait,
# and a dirty table can't seat the next guest):
#
#   serve food:     IDLE -> TO_PASS -> CARRYING -> IDLE
#   take an order:  IDLE -> TO_GUEST -> TAKING_ORDER -> IDLE
#   clear a table:  IDLE -> TO_TABLE -> CLEARING -> RETURNING -> IDLE
#
# Clearing means picking up the empty plates a table's guests left, and
# taking them back to the pass for washing.
#
# Waiters never go into the kitchen: they collect plates from the square
# in front of the pass (the expo counter).
#
# If the guest storms out halfway, the waiter gives up and goes back to
# IDLE (any food they were carrying is wasted). LEAVING is used when
# the player lets them go.
#
# Each waiter has a profile (see staff_profiles.gd). Traits:
#   Smooth Talker (Barkeep): guests get extra patience when ordering
#   Nimble (Serving Maid): walks faster
#   Lucky (Halfling Server): some guests tip big, but walks slower
# =====================================================================
class_name Waiter
extends Walker

enum State { IDLE, TO_GUEST, TAKING_ORDER, TO_PASS, CARRYING, TO_TABLE, CLEARING, RETURNING, LEAVING }

const WALK_SPEED: float = 220.0
const ORDER_TAKE_TIME: float = 1.0
const CLEAR_TIME: float = 0.8
const SMOOTH_TALK_PATIENCE: float = 10.0
const LUCKY_CHANCE: float = 1.0 / 3.0
const LUCKY_TIP: float = 0.5

var state: State = State.IDLE

var _guest: Customer = null                 # who we're working for
var _table: Vector2i = TavernGrid.NO_CELL   # the table we're clearing
var _timer: float = 0.0
var profile: Dictionary = {}


func setup(tavern_grid: TavernGrid, start_pos: Vector2, who: Dictionary) -> void:
	_setup_walker(tavern_grid, start_pos)
	profile = who
	match profile["type"]:
		"maid": speed = WALK_SPEED * 1.25
		"halfling": speed = WALK_SPEED * 0.9
		_: speed = WALK_SPEED
	sprite_sheet = StaffProfiles.SHEETS[profile["type"]]
	material = StaffProfiles.material_for(profile)
	# Pixel art stays crisp instead of blurry when scaled up.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("waiters")


func _process(delta: float) -> void:
	match state:
		State.IDLE:
			_find_task()
			if state == State.IDLE:
				idle_standby(delta)   # nothing to do: wait inside, out of the way

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
					if profile["type"] == "barkeep":
						_guest.calm(SMOOTH_TALK_PATIENCE)
					_guest = null
					state = State.IDLE

		State.TO_PASS:
			# The grid clears a plate if its guest leaves before we get there.
			if not grid.is_plate_waiting(self):
				_give_up()
			elif _walk(delta):
				_guest = grid.pick_up_plate(self)
				if _guest == null:
					state = State.IDLE
				else:
					go_to_cell(grid.access_cell(_guest.table_cell, position, self))
					state = State.CARRYING

		State.CARRYING:
			if not _guest_is(Customer.State.WAITING_FOR_FOOD):
				_give_up()   # they left; the plate is wasted
			elif _walk(delta):
				if _guest.serve_food() and profile["type"] == "halfling" and randf() < LUCKY_CHANCE:
					_guest.add_tip(LUCKY_TIP, "Lucky me! Big tip!")
				_guest = null
				state = State.IDLE

		State.TO_TABLE:
			if _walk(delta):
				state = State.CLEARING
				_timer = CLEAR_TIME

		State.CLEARING:
			_timer -= delta
			if _timer <= 0.0:
				if grid.clear_table(_table, self) > 0:
					go_to_cell(grid.expo_front())   # plates go back to the kitchen
					state = State.RETURNING
				else:
					state = State.IDLE   # the table was sold or washed meanwhile
				_table = TavernGrid.NO_CELL

		State.RETURNING:
			if _walk(delta):
				state = State.IDLE   # handed in at the pass for washing

		State.LEAVING:
			if _walk(delta):
				queue_free()

	queue_redraw()


# Called by main.gd when the player lets this waiter go.
func leave() -> void:
	remove_from_group("waiters")
	grid.release_busser(self)
	state = State.LEAVING
	go_out_door()


func _find_task() -> void:
	# Finished food first.
	if grid.claim_ready_plate(self):
		end_standby()
		go_to_cell(grid.expo_front())
		state = State.TO_PASS
		return

	var guest: Customer = GameManager.next_order_request()
	if guest != null:
		end_standby()
		_guest = guest
		go_to_cell(grid.access_cell(guest.table_cell, position, self))
		state = State.TO_GUEST
		return

	# Nothing else to do: clear a table guests have left.
	var table: Vector2i = grid.claim_dirty_table(self)
	if table != TavernGrid.NO_CELL:
		end_standby()
		_table = table
		go_to_cell(grid.access_cell(table, position, self))
		state = State.TO_TABLE


func _give_up() -> void:
	_guest = null
	stop()
	state = State.IDLE


# is_instance_valid: the guest may already be deleted, and touching a
# deleted node crashes.
func _guest_is(guest_state: Customer.State) -> bool:
	return is_instance_valid(_guest) and _guest.state == guest_state


func _draw() -> void:
	draw_sprite(state == State.CARRYING or state == State.RETURNING)
