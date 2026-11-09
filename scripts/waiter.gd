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
# The same script runs the other front-of-house jobs (profile's role):
#   host        waits by the door and greets each guest coming in
#               (IDLE -> GREETING -> IDLE); the bonus is in customer.gd
#   dishwasher  only clears tables; with one on staff, waiters don't
#   bartender   works a Bar: takes drink orders from the kitchen's queue,
#               pours, and carries the drink out:
#               IDLE -> TO_BAR -> POURING -> CARRYING -> IDLE
#
# Each waiter has a profile (see staff_profiles.gd). Traits:
#   Smooth Talker (Barkeep): guests get extra patience when ordering
#   Nimble (Serving Maid): walks faster
#   Lucky (Halfling Server): some guests tip big, but walks slower
# =====================================================================
class_name Waiter
extends Walker

enum State { IDLE, TO_GUEST, TAKING_ORDER, TO_PASS, CARRYING, TO_TABLE, CLEARING, RETURNING, TO_BAR, POURING, GREETING, LEAVING }

const WALK_SPEED: float = 220.0
const ORDER_TAKE_TIME: float = 1.0
const CLEAR_TIME: float = 0.8
const SMOOTH_TALK_PATIENCE: float = 10.0
const LUCKY_CHANCE: float = 1.0 / 3.0
const LUCKY_TIP: float = 0.5
const TRAY_SIZE: float = 0.75   # dishes on the tray are drawn a bit smaller
const POUR_TIME: float = 1.5
const GREET_TIME: float = 1.2

var state: State = State.IDLE

var _guest: Customer = null                 # who we're working for
var _table: Vector2i = TavernGrid.NO_CELL   # the table we're clearing
var _pause: float = 0.0   # after a job we couldn't reach: wait before the next
var _timer: float = 0.0
var profile: Dictionary = {}
var role: String = "waiter"                 # "waiter", "host", "dishwasher" or "bartender"
var _bar: Vector2i = TavernGrid.NO_CELL     # a bartender's Bar
var _bubble: String = ""                     # what we're saying (the host's welcome)


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
	role = StaffProfiles.role_of(profile)
	add_to_group(role + "s")   # "waiters", "hosts", "dishwashers", "bartenders"


func _process(delta: float) -> void:
	# If there's no way to where we're going, drop the job (and any plate
	# or table we'd claimed) so someone else can do it, rather than
	# standing frozen while the guest gives up.
	if _stuck and state != State.IDLE and state != State.LEAVING:
		_give_up()
		_pause = 1.0   # so another waiter gets the job first
	match state:
		State.IDLE:
			_pause -= delta
			if _pause <= 0.0:
				_find_task()
			if state == State.IDLE and not (role == "bartender" and _bar != TavernGrid.NO_CELL):
				idle_standby(delta)   # nothing to do: wait inside, out of the way
				# (a bartender with a Bar stays behind it instead)

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

		State.TO_BAR:
			if not grid.bars.has(_bar):
				release_bar_job()
			elif _walk(delta):
				face_toward(grid.cell_center(_bar))
				_guest = grid.take_drink_order()
				if _guest == null:
					state = State.IDLE
				else:
					GameManager.buy_ingredients(_guest.order)
					state = State.POURING
					_timer = POUR_TIME

		State.GREETING:
			_timer -= delta
			if _timer <= 0.0:
				_bubble = ""
				state = State.IDLE

		State.POURING:
			if not _guest_is(Customer.State.WAITING_FOR_FOOD):
				_give_up()
			else:
				_timer -= delta
				if _timer <= 0.0:
					go_to_cell(grid.access_cell(_guest.table_cell, position, self))
					state = State.CARRYING

		State.LEAVING:
			if _walk(delta):
				queue_free()

	queue_redraw()


# Called by main.gd when the player lets this waiter go.
func leave() -> void:
	remove_from_group(role + "s")
	grid.release_bar(self)
	grid.release_busser(self)
	grid.release_plate_claim(self)
	state = State.LEAVING
	go_out_door()


func _find_task() -> void:
	match role:
		"host":
			_greet_someone()   # otherwise waits by the door (see standby_cell)
			return
		"bartender":
			_find_bar_task()
			return
		"dishwasher":
			_find_dirty_table()
			return
	# Finished food first. Each job goes to whichever free waiter is
	# nearest, so the whole team shares the work.
	if grid.has_ready_plate() and _nearest_free(grid.cell_center(grid.expo_front())) \
			and grid.claim_ready_plate(self):
		end_standby()
		go_to_cell(grid.expo_front())
		state = State.TO_PASS
		return

	var waiting: Customer = GameManager.peek_order_request()
	if waiting != null and _nearest_free(waiting.position):
		var guest: Customer = GameManager.next_order_request()
		end_standby()
		_guest = guest
		go_to_cell(grid.access_cell(guest.table_cell, position, self))
		state = State.TO_GUEST
		return

	# Nothing else to do: clear a table guests have left (unless that's
	# the dishwashers' job).
	if get_tree().get_nodes_in_group("dishwashers").is_empty():
		_find_dirty_table()


func _find_dirty_table() -> void:
	var dirty: Vector2i = grid.peek_dirty_table()
	if dirty == TavernGrid.NO_CELL or not _nearest_free(grid.cell_center(dirty)):
		return
	var table: Vector2i = grid.claim_dirty_table(self)
	if table != TavernGrid.NO_CELL:
		end_standby()
		_table = table
		go_to_cell(grid.access_cell(table, position, self))
		state = State.TO_TABLE


# Am I the nearest free colleague (same job, idle, not pausing) to `spot`?
# If not, I leave the job for them.
func _nearest_free(spot: Vector2) -> bool:
	var mine: float = position.distance_to(spot)
	for other in get_tree().get_nodes_in_group(role + "s"):
		if other == self or other.state != State.IDLE or other._pause > 0.0 or other.current_cell() == TavernGrid.NO_CELL:
			continue
		var theirs: float = other.position.distance_to(spot)
		if theirs < mine or (theirs == mine and other.get_instance_id() < get_instance_id()):
			return false
	return true


# The host greets each guest on their way to a table.
func _greet_someone() -> void:
	for guest in get_tree().get_nodes_in_group("customers"):
		if guest.state == Customer.State.WALKING_IN and not guest.greeted:
			guest.greeted = true
			face_toward(guest.position)
			_bubble = ["Welcome!", "Right this way!", "Good evening!" if GameManager.minutes_since_open > 480 else "Good day!"].pick_random()
			state = State.GREETING
			_timer = GREET_TIME
			return


# A bartender goes to their Bar and pours whatever drink is waiting.
func _find_bar_task() -> void:
	_bar = grid.claim_bar(self)
	if _bar == TavernGrid.NO_CELL:
		return   # no Bar free: waits around
	var spot: Vector2i = grid.bar_back(_bar)
	if current_cell() != spot or grid.take_drink_order_peek():
		end_standby()
		go_to_cell(spot)
		state = State.TO_BAR


# Our Bar was sold: find another (or wait).
func release_bar_job() -> void:
	grid.release_bar(self)
	_bar = TavernGrid.NO_CELL
	if state in [State.TO_BAR, State.POURING]:
		_give_up()


func _give_up() -> void:
	_guest = null
	_table = TavernGrid.NO_CELL
	grid.release_plate_claim(self)
	grid.release_busser(self)
	stop()
	end_standby()
	state = State.IDLE


# is_instance_valid: the guest may already be deleted, and touching a
# deleted node crashes.
func _guest_is(guest_state: Customer.State) -> bool:
	return is_instance_valid(_guest) and _guest.state == guest_state


func _draw() -> void:
	var carrying: bool = state == State.CARRYING or state == State.RETURNING
	draw_sprite(carrying)
	if _bubble != "":
		var font: Font = ThemeDB.fallback_font
		var width: float = font.get_string_size(_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var at := Vector2(-width / 2.0, -75)
		draw_string_outline(font, at, _bubble, HORIZONTAL_ALIGNMENT_CENTER, width, 19, 5, Color(0.12, 0.08, 0.05))
		draw_string(font, at, _bubble, HORIZONTAL_ALIGNMENT_CENTER, width, 19, Color.WHITE)
	if not carrying:
		return
	# The sheet only has an empty tray; put what we're carrying on it: the
	# guest's own dish (an ale comes in its tankard), or on the way back,
	# a stack of dirty plates. The dish pictures' plates sit 6 pixels
	# below their middle, so that's lifted onto the tray.
	var tray: Vector2 = _tray_spot()
	if state == State.RETURNING:
		grid.draw_dish(self, tray + Vector2(0, -5), "dirty", TRAY_SIZE)
		grid.draw_dish(self, tray + Vector2(0, -8), "dirty", TRAY_SIZE)
	elif is_instance_valid(_guest):
		grid.draw_dish(self, tray + Vector2(0, -5), _guest.order.get("id", "plate"), TRAY_SIZE)


# Where the top of the tray is in each pose (it matches the sprite sheet:
# held out to the right, over the shoulder from behind; lower for halflings).
func _tray_spot() -> Vector2:
	var spot: Vector2
	match _facing:
		"right": spot = Vector2(12, -8)
		"left": spot = Vector2(-12, -8)
		"back": spot = Vector2(17, -18)
		_: spot = Vector2(16, -8)
	if profile.get("type", "") == "halfling":
		spot.y += 8
	return spot
