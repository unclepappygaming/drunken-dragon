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
# Each guest has a type (guest_type, see guest_types.gd) that changes
# their patience, speed, what they order and what they pay. Anyone who
# finds nothing they like on today's menu leaves unhappy. Adventurers
# come as a party sharing one table; if one storms off, they all go.
#
# Guests sit on a free square NEXT TO their table. A Waiter comes to
# take the order, a Cook cooks it, and a Waiter carries it over. When
# they finish, their empty plate stays on the table for a Waiter to clear.
# Walking around furniture comes from walker.gd (see "extends Walker").
#
# Each guest is drawn from their type's pixel-art sheet, recolored with
# their own skin and hair (see guest_types.gd).
# =====================================================================

# class_name registers "Customer" as a type the whole project knows.
# That's why GameManager can have an Array[Customer].
class_name Customer
extends Walker

# Fired the moment a guest gets up to leave. main.gd listens so it can
# free the table and change fame. happy = paid and left satisfied;
# leave_reason says exactly why they left.
signal left_tavern(customer: Customer, happy: bool)

# FINISHED: done (fed, or nothing they wanted) but still sitting, waiting
# for the rest of their group so they can all leave together.
enum State { IN_LINE, WALKING_IN, DECIDING, WAITING_FOR_WAITER, WAITING_FOR_FOOD, EATING, LEAVING, FINISHED }

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
var guest_type: String = "farmer"
var is_noble: bool = false
# Adventurers: everyone in the party, this guest included (shared Array).
var party: Array = []
var patience: float = MAX_PATIENCE
# Why they left: "served", "impatient", "no_dish", "gave_up_line" or "closed".
var leave_reason: String = ""

var _patience_max: float = MAX_PATIENCE   # what the patience bar counts down from
# Extra share of the price they'll pay: from a Tavern Cook's portions or
# a lucky tip. Nobles also tip on top (GameManager.NOBLE_TIP).
var price_bonus: float = 0.0
var _timer: float = 0.0
var _bubble: String = ""             # text shown above their head
var _patience_scale: float = 1.0     # from the guest type
var _patience_at_serve: float = 0.0  # for the Town Guard's quick-service tip
var _second_helping: bool = false    # a Dwarf Miner already ordered their second dish
const BARD_REACH: int = 3            # squares around a playing bard
const BARD_CALM: float = 0.5         # nearby guests lose patience this much slower
# Speech bubble and patience bar live on their own layer above every
# character, so one guest's bubble never darkens the guest behind it.
var _overlay: Node2D
var _seat: Vector2i = TavernGrid.NO_CELL   # our chair
var greeted: bool = false                  # the host has welcomed us


# Called by main.gd right after the guest is created. We can't pass
# arguments to instantiate(), so a setup() function is the usual pattern.
# Then main.gd either seats them (take_table) or lines them up (wait_in_line).
func setup(tavern_grid: TavernGrid, type: String = "farmer") -> void:
	_setup_walker(tavern_grid, tavern_grid.door_position())
	guest_type = type
	is_noble = type == "noble"
	var info: Dictionary = GuestTypes.TYPES[type]
	speed = WALK_SPEED * info["speed"]
	_patience_scale = info["patience"]
	# A random look for their type, recolored with their own skin and hair.
	var look: Dictionary = GuestTypes.random_look(type)
	sprite_sheet = GuestTypes.SHEETS[look["sheet"]]
	material = GuestTypes.material_for(type, look)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Guests always show at least their profile, never the back of their head.
	show_back = false

	# z_index puts the overlay above all the characters (z_index 0). It
	# has no material of its own, so the color swap doesn't touch it.
	_overlay = Node2D.new()
	_overlay.z_index = 5
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)

	# GROUPS are tags. Putting every guest in "customers" lets main.gd ask
	# "how many guests are still here?" with one line, without keeping
	# its own list. A node leaves its groups automatically when freed.
	add_to_group("customers")


# `seat`: the chair we're given (pairs sit across from each other).
# Without one (shouldn't happen) we find a free square beside the table.
func take_table(cell: Vector2i, seat: Vector2i = TavernGrid.NO_CELL) -> void:
	table_cell = cell
	_seat = seat
	state = State.WALKING_IN
	_bubble = ""
	patience = MAX_PATIENCE * _patience_scale
	if GameManager.today_event == "rain":
		patience *= GameManager.RAIN_PATIENCE   # in no hurry to go back out in the rain
	if _has_host():
		patience += HOST_WELCOME
	if is_noble and grid.is_private_table(cell):
		patience *= PRIVATE_BONUS + 1.0   # nobles relax in the private room
	_patience_max = patience
	# Sit on a free square beside the table, not on top of it.
	go_to_cell(seat if seat != TavernGrid.NO_CELL else grid.access_cell(cell, position, self))


const HOST_LINE: float = 2.0      # with a host, guests wait this much longer in line
const PRIVATE_BONUS: float = 0.3  # nobles at a private table pay and wait this much more
const HOST_WELCOME: float = 10.0  # and sit down with this many more seconds of patience


func _has_host() -> bool:
	return not get_tree().get_nodes_in_group("hosts").is_empty()


func wait_in_line(spot: Vector2) -> void:
	state = State.IN_LINE
	patience = LINE_PATIENCE * _patience_scale * (HOST_LINE if _has_host() else 1.0)
	_patience_max = patience
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


# A miner's second dish: back to calling for a waiter, with fresh patience.
func _order_again() -> void:
	var next: Dictionary = GameManager.pick_order(guest_type)
	if next.is_empty():
		_start_leaving("served")
		return
	order = next
	patience = _patience_max
	_bubble = "Another one!"
	GameManager.order_requests.append(self)
	state = State.WAITING_FOR_WAITER


func _seated() -> bool:
	return state in [State.DECIDING, State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD, State.EATING, State.FINISHED]


# Guests who came together leave together: someone who's finished stays
# at the table until everyone else in their group is finished too.
func _finish(reason: String) -> void:
	for friend in party:
		if friend != self and is_instance_valid(friend) and friend.state in [
				State.WALKING_IN, State.DECIDING, State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD, State.EATING]:
			state = State.FINISHED
			leave_reason = reason
			return
	# Last one done: everybody goes.
	for friend in party:
		if friend != self and is_instance_valid(friend) and friend.state == State.FINISHED:
			friend._start_leaving(friend.leave_reason)
	_start_leaving(reason)


# A bard at their table plays for the room: guests nearby lose patience
# more slowly.
func _play_music(delta: float) -> void:
	if fmod(Time.get_ticks_msec() / 1000.0, 6.0) < delta * 1.01 and state != State.DECIDING:
		_bubble = ["La la la~", "Hey nonny!", "Fa la la!"].pick_random()
	var here: Vector2i = current_cell()
	for other in get_tree().get_nodes_in_group("customers"):
		if other != self and other._seated():
			var gap: Vector2i = other.current_cell() - here
			if absi(gap.x) <= BARD_REACH and absi(gap.y) <= BARD_REACH:
				other.calm(delta * BARD_CALM)


func _process(delta: float) -> void:
	if guest_type == "bard" and _seated() and _path.is_empty():
		_play_music(delta)
	match state:
		State.IN_LINE:
			_walk(delta)   # to our spot in the line
			patience -= delta
			if patience <= 0.0:
				_bubble = "Too long!"
				_start_leaving("gave_up_line")
				for friend in party:   # whoever they came with goes too
					if friend != self and is_instance_valid(friend) and friend.state == State.IN_LINE:
						friend._start_leaving("gave_up_line")

		State.WALKING_IN:
			if _walk(delta):
				var top: Vector2i = grid.top_for_chair(_seat) if _seat != TavernGrid.NO_CELL else table_cell
				face_toward(grid.cell_center(top))
				state = State.DECIDING
				_timer = DECIDE_TIME
				_bubble = "..."

		State.DECIDING:
			_timer -= delta
			if _timer <= 0.0:
				order = GameManager.pick_order(guest_type)
				if order.is_empty():
					_bubble = _nothing_to_order_line()
					_finish("no_dish")
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
				var share: float = 1.0 + price_bonus + GuestTypes.TYPES[guest_type]["pay"]
				if is_noble:
					share += GameManager.NOBLE_TIP   # nobles tip well
					if grid.is_private_table(table_cell):
						share += PRIVATE_BONUS
				if GameManager.in_hall():
					share += GameManager.HALL_PRICE_BONUS   # city prices
				if GameManager.today_event == "festival":
					share += GameManager.FESTIVAL_TIP
				# A guard served quickly is grateful.
				if guest_type == "guard" and _patience_at_serve > _patience_max / 2.0:
					share += GuestTypes.GUARD_TIP
				var price: int = roundi(order["price"] * share)
				GameManager.earn(price)
				grid.finish_dish(table_cell, _seat)   # leaves an empty plate behind
				_bubble = "+%dg" % price
				# A dwarf miner is always still hungry: one more dish.
				if guest_type == "miner" and not _second_helping:
					_second_helping = true
					_order_again()
					return
				_finish("served")

		State.LEAVING:
			if _walk(delta):
				# queue_free() deletes this node safely at the end of the frame.
				queue_free()

	# Ask Godot to redraw us and the overlay, so the patience bar animates.
	queue_redraw()
	_overlay.queue_redraw()


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
	grid.serve_dish(table_cell, _seat, order.get("id", "plate"))
	_patience_at_serve = patience
	_bubble = "Yum!"
	return true


func _nothing_to_order_line() -> String:
	match guest_type:
		"noble": return "Nothing fancy enough!"
		"merchant": return "Nothing worth my coin!"
		"regular": return "No %s today?" % GameManager.RECIPES[GameManager.regular_favorite()]["name"]
	return "Nothing I like!"


func _start_leaving(reason: String) -> void:
	leave_reason = reason
	state = State.LEAVING
	go_out_door()
	# Stop waiting for a waiter or a cook.
	GameManager.order_requests.erase(self)
	GameManager.order_queue.erase(self)
	left_tavern.emit(self, reason == "served")
	# A group sticks together: if one storms off, so does everyone still
	# waiting, and anyone already finished gets up to go with them.
	if reason == "impatient":
		for friend in party:
			if friend != self and is_instance_valid(friend) and friend.state in [
					State.WALKING_IN, State.DECIDING, State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD]:
				friend.say("We're leaving!")
				friend._start_leaving("impatient")
	# Whoever's still eating finishes, then leaves (see _finish); anyone
	# finished and waiting on us can go now.
	for friend in party:
		if friend != self and is_instance_valid(friend) and friend.state == State.FINISHED \
				and not _anyone_still_busy():
			friend._start_leaving(friend.leave_reason)


func _anyone_still_busy() -> bool:
	for friend in party:
		if is_instance_valid(friend) and friend.state in [
				State.WALKING_IN, State.DECIDING, State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD, State.EATING]:
			return true
	return false


# _draw() paints this node. (0, 0) is the guest's own position, so
# everything is drawn relative to them.
func _draw() -> void:
	# On our chair we're drawn sitting (legs hidden by the chair).
	var seated: bool = _seated() \
			and _seat != TavernGrid.NO_CELL and current_cell() == _seat and _path.is_empty()
	draw_sprite(false, seated)


# The patience bar under their feet and the speech bubble above their
# head, drawn on the overlay (see setup).
func _draw_overlay() -> void:
	if state in [State.IN_LINE, State.WAITING_FOR_WAITER, State.WAITING_FOR_FOOD]:
		var ratio: float = patience / _patience_max
		_overlay.draw_rect(Rect2(-25, 22, 50, 7), Color(0.15, 0.15, 0.15))
		# Green when patient, fading to red.
		_overlay.draw_rect(Rect2(-25, 22, 50 * ratio, 7), Color(1.0 - ratio, ratio, 0.2))

	if _bubble != "":
		# Just the words, no box: white text with a dark outline so it reads
		# on any floor, and covers as little of the room as possible.
		var font: Font = ThemeDB.fallback_font
		var width: float = font.get_string_size(_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var at := Vector2(-width / 2.0, -75)
		_overlay.draw_string_outline(font, at, _bubble, HORIZONTAL_ALIGNMENT_CENTER, width, 19, 5, Color(0.12, 0.08, 0.05))
		_overlay.draw_string(font, at, _bubble, HORIZONTAL_ALIGNMENT_CENTER, width, 19, Color.WHITE)
