# =====================================================================
# tavern_grid.gd  —  the tavern floor. Attached to the TavernGrid node.
#
# The floor is a grid of squares, 8 x 10 to start. Expansions add
# columns on the right and rows at the bottom, so existing squares keep
# their coordinates. Each square can hold one piece of furniture.
# This script:
#   * draws the floor, walls, door and furniture
#   * handles taps to build/remove furniture and move the door
#   * finds walking routes around the furniture (pathfinding)
#   * tracks which tables are taken
#   * runs the Hearths: each one cooks one order at a time, but only
#     while a Cook stands at it, then leaves the plate for a Waiter
# =====================================================================
class_name TavernGrid
extends Node2D

# Fired when building fails or succeeds, so the HUD can show a message.
signal build_message(text: String)
# Fired after furniture is built or sold, so anyone mid-walk can plan
# a new route around it.
signal layout_changed

const START_COLS: int = 8
const START_ROWS: int = 10
const CELL_SIZE: int = 80
const NO_CELL: Vector2i = Vector2i(-1, -1)   # "nothing found" marker
const DOOR_COST: int = 100
# Which way is "outside" for each wall.
const OUTWARD: Dictionary = {
	"bottom": Vector2(0, 1), "top": Vector2(0, -1),
	"left": Vector2(-1, 0), "right": Vector2(1, 0),
}
# The four squares touching a square (no diagonals). People stand on
# one of these to use a piece of furniture.
const SIDES: Array = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]

# "" = not building. Otherwise "table", "kitchen", "remove" or "door".
var build_type: String = ""

var cols: int = START_COLS
var rows: int = START_ROWS
# The front door sits on one wall ("bottom", "top", "left" or "right"),
# `door_index` squares along it.
var door_side: String = "bottom"
var door_index: int = 4
# The square just inside the front door. Everyone comes in and goes out
# through it, so it can never be built on.
var door_cell: Vector2i = Vector2i(4, START_ROWS - 1)

# Vector2i(column, row) -> furniture ID ("table" / "kitchen")
var furniture: Dictionary = {}
# table cell -> the Customer sitting there, or null if free
var table_owner: Dictionary = {}
# hearth cell -> {
#   "cook":        the Cook working it, or null
#   "job":         {} when not cooking, or {"customer", "time_left", "total"}
#   "plate_for":   the guest whose finished dish is waiting here, or null
#   "plate_taker": the Waiter on their way to fetch it, or null
# }
var hearths: Dictionary = {}

# AStarGrid2D is Godot's built-in pathfinder for square grids. We mark
# furniture squares as "solid" and it finds the shortest way around them.
var _astar := AStarGrid2D.new()


func _ready() -> void:
	_astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	# Diagonal steps are allowed, but never squeezing between two pieces
	# of furniture or cutting a corner.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_apply_size()

	# A free starter layout so Day 1 works right away.
	_place(Vector2i(1, 2), "table")
	_place(Vector2i(4, 2), "table")
	_place(Vector2i(6, 6), "kitchen")


# The camera tells us about taps (drags just move the view), already
# converted to a point in the world, so zooming doesn't change which
# square you hit.
func handle_tap(world_pos: Vector2) -> void:
	if build_type == "":
		return
	var cell: Vector2i = cell_at_world(world_pos)
	if cell != NO_CELL:
		_try_build(cell)


# The floor itself, in Main's space.
func play_rect() -> Rect2:
	return Rect2(position, Vector2(cols * CELL_SIZE, rows * CELL_SIZE))


# The floor plus room for the doorstep on every side. The camera stays over it.
func floor_rect() -> Rect2:
	return play_rect().grow(70)


# Makes the floor bigger (or sets its size when loading a save). New
# squares are empty, so nobody can get walled in by this.
# announce = false while loading, before staff exist.
func resize(new_cols: int, new_rows: int, announce: bool = true) -> void:
	cols = new_cols
	rows = new_rows
	# The door stays on the same wall; on a wall that moved, it moves too.
	set_door(door_side, door_index)
	_apply_size()
	if announce:
		layout_changed.emit()


# Puts the door on a wall. Used when loading; the Door tool checks first.
func set_door(side: String, index: int) -> void:
	if not OUTWARD.has(side):
		side = "bottom"
	var wall_length: int = cols if side in ["top", "bottom"] else rows
	door_side = side
	door_index = clampi(index, 0, wall_length - 1)
	door_cell = _door_cell_for(door_side, door_index)


# The door as plain data for the save file.
func get_door() -> Array:
	return [door_side, door_index]


# Rebuilds the pathfinder for the current size. AStarGrid2D.update()
# forgets which squares are solid, so the furniture is marked again.
func _apply_size() -> void:
	_astar.region = Rect2i(0, 0, cols, rows)
	_astar.update()
	for cell in furniture:
		_astar.set_point_solid(cell, true)
	queue_redraw()


func _door_cell_for(side: String, index: int) -> Vector2i:
	match side:
		"top": return Vector2i(index, 0)
		"left": return Vector2i(0, index)
		"right": return Vector2i(cols - 1, index)
	return Vector2i(index, rows - 1)   # bottom


# Which wall an edge square is on, or "" if it's not on the edge.
# Corner squares count as the top or bottom wall.
func _side_of(cell: Vector2i) -> String:
	if not _in_bounds(cell):
		return ""
	if cell.y == rows - 1:
		return "bottom"
	if cell.y == 0:
		return "top"
	if cell.x == 0:
		return "left"
	if cell.x == cols - 1:
		return "right"
	return ""


func _process(delta: float) -> void:
	for cell in hearths:
		# Dictionaries are shared, not copied: changing `h` changes hearths[cell].
		var h: Dictionary = hearths[cell]

		# A plate nobody will eat any more gets cleared away.
		if not _wants_food(h["plate_for"]):
			h["plate_for"] = null
			h["plate_taker"] = null

		# The fire only cooks with a cook standing at it.
		var cook = h["cook"]
		if not is_instance_valid(cook) or not cook.is_at_hearth():
			continue

		var job: Dictionary = h["job"]
		if job.is_empty():
			# Only start the next dish once the last plate has been fetched.
			if h["plate_for"] == null:
				var next: Customer = _pop_next_order()
				if next != null:
					var cook_time: float = next.order["cook_time"]
					h["job"] = {"customer": next, "time_left": cook_time, "total": cook_time}
		else:
			# The guest may have stormed out while we cooked. Bin the dish
			# and move on to the next order instead of finishing it.
			if not _wants_food(job["customer"]):
				h["job"] = {}
				continue
			# Some cooks are faster with some dishes (see cook.gd).
			job["time_left"] -= delta * cook.cook_speed(job["customer"].order)
			if job["time_left"] <= 0.0:
				job["customer"].price_bonus += cook.portion_bonus()
				h["plate_for"] = job["customer"]   # ready for a waiter
				h["job"] = {}
	queue_redraw()


# ---------------------------------------------------------------------
# Helpers the other scripts use. Positions are in Main's space
# (we add our own `position` because the grid is offset on screen).
# ---------------------------------------------------------------------
func cell_center(cell: Vector2i) -> Vector2:
	return position + Vector2(cell) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) / 2.0


# Just outside the front door, where people appear and disappear.
func door_position() -> Vector2:
	return cell_center(door_cell) + OUTWARD[door_side] * (CELL_SIZE / 2.0 + 30.0)


# Which way the waiting line runs along the outside wall: toward the
# longer stretch of wall, so it has room.
func line_direction() -> Vector2:
	if door_side in ["top", "bottom"]:
		return Vector2(-1, 0) if door_index >= cols / 2.0 else Vector2(1, 0)
	return Vector2(0, 1) if door_index < rows / 2.0 else Vector2(0, -1)


# Which square a Main-space position is on (NO_CELL if off the floor).
func cell_at_world(world_pos: Vector2) -> Vector2i:
	return _cell_at(world_pos - position)


# The squares to walk through, start and goal included.
# Empty if there's no way to get there.
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if _astar.is_point_solid(from_cell) or _astar.is_point_solid(to_cell):
		return []
	return _astar.get_id_path(from_cell, to_cell)


# The best free square beside a piece of furniture to stand on, for
# someone at from_pos: the shortest walk, preferring squares nobody else
# is using (so two people don't stand on top of each other).
# `asker` is left out when checking who is using which square.
func access_cell(furniture_cell: Vector2i, from_pos: Vector2, asker: Node = null) -> Vector2i:
	var start: Vector2i = cell_at_world(from_pos)
	if start == NO_CELL:
		start = door_cell
	var in_use: Dictionary = _cells_in_use(asker)

	var best: Vector2i = NO_CELL
	var best_score: float = INF
	for side in SIDES:
		var spot: Vector2i = furniture_cell + side
		if not _in_bounds(spot) or furniture.has(spot):
			continue
		var route: Array[Vector2i] = find_path(start, spot)
		if route.is_empty():
			continue
		# A taken square still works, it just scores much worse.
		var score: float = route.size() + (100.0 if in_use.has(spot) else 0.0)
		if score < best_score:
			best_score = score
			best = spot
	return best


# Where staff with nothing to do wait: a free square near the kitchen
# (the first Hearth) or the middle of the room. Not the doorway, not a
# square someone else is using, and preferably not beside a table, since
# that's where guests sit. NO_CELL if there's nowhere to go.
func standby_cell(asker: Node) -> Vector2i:
	var anchor: Vector2 = Vector2(cols, rows) / 2.0
	if not hearths.is_empty():
		anchor = Vector2(hearths.keys()[0])
	var in_use: Dictionary = _cells_in_use(asker)
	var choices: Array = []
	for x in cols:
		for y in rows:
			var spot := Vector2i(x, y)
			if furniture.has(spot) or spot == door_cell or in_use.has(spot):
				continue
			var score: float = Vector2(spot).distance_to(anchor)
			for side in SIDES:
				if furniture.get(spot + side, "") == "table":
					score += 10.0
			choices.append([score, spot])
	choices.sort_custom(func(a, b): return a[0] < b[0])
	var start: Vector2i = asker.current_cell()
	if start == NO_CELL:
		start = door_cell
	# The closest one we can actually walk to.
	for choice in choices:
		if not find_path(start, choice[1]).is_empty():
			return choice[1]
	return NO_CELL


func find_free_table() -> Vector2i:
	var free: Array[Vector2i] = []
	for cell in table_owner:
		if table_owner[cell] == null:
			free.append(cell)
	if free.is_empty():
		return NO_CELL
	return free.pick_random()


func reserve_table(cell: Vector2i, customer: Customer) -> void:
	table_owner[cell] = customer


func release_table(cell: Vector2i) -> void:
	if table_owner.has(cell):
		table_owner[cell] = null


# A Cook asks for a Hearth that nobody is working. Returns its cell.
func claim_hearth(cook: Cook) -> Vector2i:
	for cell in hearths:
		if not is_instance_valid(hearths[cell]["cook"]):
			hearths[cell]["cook"] = cook
			return cell
	return NO_CELL


func release_hearth(cook: Cook) -> void:
	for cell in hearths:
		if hearths[cell]["cook"] == cook:
			hearths[cell]["cook"] = null


# A Waiter asks for a finished plate nobody is fetching yet.
func claim_ready_plate(waiter: Waiter) -> Vector2i:
	for cell in hearths:
		var h: Dictionary = hearths[cell]
		if _wants_food(h["plate_for"]) and not is_instance_valid(h["plate_taker"]):
			h["plate_taker"] = waiter
			return cell
	return NO_CELL


# Is the plate this waiter claimed still there?
func is_plate_waiting(cell: Vector2i, waiter: Waiter) -> bool:
	return hearths.has(cell) and hearths[cell]["plate_taker"] == waiter \
			and _wants_food(hearths[cell]["plate_for"])


# The waiter takes the plate. Returns the guest it's for, or null.
func pick_up_plate(cell: Vector2i) -> Customer:
	if not hearths.has(cell):
		return null
	var h: Dictionary = hearths[cell]
	var guest = h["plate_for"]
	h["plate_for"] = null
	h["plate_taker"] = null
	if not _wants_food(guest):
		return null
	return guest


# The furniture as plain data for the save file: [[column, row, type], ...]
# (JSON can't store a Vector2i, but it can store a list of numbers.)
func get_layout() -> Array:
	var layout: Array = []
	for cell in furniture:
		layout.append([cell.x, cell.y, furniture[cell]])
	return layout


# Replaces all furniture with a saved layout. Called before any staff
# or guests exist, so nobody needs a new route.
func load_layout(layout: Array) -> void:
	furniture.clear()
	table_owner.clear()
	hearths.clear()
	_astar.fill_solid_region(_astar.region, false)   # clear every square
	for entry in layout:
		# Skip anything that doesn't make sense rather than crash.
		if typeof(entry) != TYPE_ARRAY or entry.size() != 3:
			continue
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if _in_bounds(cell) and cell != door_cell and GameManager.FURNITURE.has(entry[2]):
			_place(cell, entry[2])


# ---------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------
func _try_build(cell: Vector2i) -> void:
	if build_type == "remove":
		_try_remove(cell)
		return
	if build_type == "door":
		_try_move_door(cell)
		return
	if furniture.has(cell):
		build_message.emit("That square is taken.")
		return
	if cell == door_cell:
		build_message.emit("Keep the doorway clear!")
		return
	if _cells_in_use(null).has(cell):
		build_message.emit("Someone's in the way!")
		return
	if not _layout_works_with(cell):
		build_message.emit("That would block someone's way!")
		return
	var info: Dictionary = GameManager.FURNITURE[build_type]
	if not GameManager.try_spend(info["cost"]):
		build_message.emit("Not enough gold!")
		return
	_place(cell, build_type)
	layout_changed.emit()
	build_message.emit("Built a %s." % info["name"])


func _place(cell: Vector2i, type: String) -> void:
	furniture[cell] = type
	_astar.set_point_solid(cell, true)   # nobody can walk through it now
	if type == "table":
		table_owner[cell] = null
	elif type == "kitchen":
		hearths[cell] = {"cook": null, "job": {}, "plate_for": null, "plate_taker": null}


func _try_remove(cell: Vector2i) -> void:
	if not furniture.has(cell):
		return
	var type: String = furniture[cell]
	if type == "table" and table_owner[cell] != null:
		build_message.emit("Someone's sitting there!")
		return
	if type == "kitchen":
		var h: Dictionary = hearths[cell]
		if not h["job"].is_empty() or _wants_food(h["plate_for"]):
			build_message.emit("That Hearth is busy!")
			return
		# Send its cook off to find another Hearth.
		if is_instance_valid(h["cook"]):
			h["cook"].release_hearth()
	# Dividing by 2.0 (not 2) avoids Godot's integer-division warning;
	# floori() then rounds down to whole gold.
	var refund: int = floori(GameManager.FURNITURE[type]["cost"] / 2.0)
	GameManager.refund(refund)
	furniture.erase(cell)
	table_owner.erase(cell)
	hearths.erase(cell)
	_astar.set_point_solid(cell, false)
	layout_changed.emit()
	build_message.emit("Sold for %dg." % refund)


# Moving the door is only allowed between days, with everyone inside,
# so nobody is caught walking to the old doorway.
func _try_move_door(cell: Vector2i) -> void:
	if GameManager.is_open or not get_tree().get_nodes_in_group("customers").is_empty():
		build_message.emit("Move the door after closing time.")
		return
	var side: String = _side_of(cell)
	if side == "":
		build_message.emit("The door has to go on an outside wall.")
		return
	if cell == door_cell:
		build_message.emit("The door is already here.")
		return
	if furniture.has(cell):
		build_message.emit("Clear that square first.")
		return
	if _cells_in_use(null).has(cell):
		build_message.emit("Someone's in the way!")
		return
	for walker in get_tree().get_nodes_in_group("walkers"):
		if walker.current_cell() == NO_CELL:
			build_message.emit("Wait until everyone is inside.")
			return
	if not _layout_works(furniture, cell):
		build_message.emit("That would block someone's way!")
		return
	if not GameManager.try_spend(DOOR_COST):
		build_message.emit("Not enough gold!")
		return
	set_door(side, cell.x if side in ["top", "bottom"] else cell.y)
	layout_changed.emit()
	build_message.emit("Moved the door.")


# Would the tavern still work with furniture on new_cell?
func _layout_works_with(new_cell: Vector2i) -> bool:
	# Pretend the new piece is already there.
	var solid: Dictionary = furniture.duplicate()
	solid[new_cell] = true
	return _layout_works(solid, door_cell)


# Every piece of furniture needs a side people can reach from the door,
# and nobody may get walled in.
func _layout_works(solid: Dictionary, door: Vector2i) -> bool:
	# FLOOD FILL outward from the door: visit every square we can walk
	# to, one step at a time, until there's nowhere new to go.
	var reachable: Dictionary = {door: true}
	var to_visit: Array[Vector2i] = [door]
	while not to_visit.is_empty():
		var here: Vector2i = to_visit.pop_back()
		for side in SIDES:
			var next: Vector2i = here + side
			if _in_bounds(next) and not solid.has(next) and not reachable.has(next):
				reachable[next] = true
				to_visit.append(next)

	for piece in solid:
		var usable: bool = false
		for side in SIDES:
			if reachable.has(piece + side):
				usable = true
				break
		if not usable:
			return false

	for person_cell in _cells_in_use(null):
		if not reachable.has(person_cell):
			return false
	return true


# Every square someone is standing on or walking to, as dictionary keys.
func _cells_in_use(ignore: Node) -> Dictionary:
	var cells: Dictionary = {}
	for walker in get_tree().get_nodes_in_group("walkers"):
		if walker == ignore:
			continue
		for cell in [walker.current_cell(), walker.destination]:
			if cell != NO_CELL:
				cells[cell] = true
	return cells


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


func _cell_at(local_pos: Vector2) -> Vector2i:
	var cell := Vector2i(floori(local_pos.x / CELL_SIZE), floori(local_pos.y / CELL_SIZE))
	if not _in_bounds(cell):
		return NO_CELL
	return cell


# A guest who is still alive and waiting for their dish.
func _wants_food(guest) -> bool:
	return is_instance_valid(guest) and guest.state == Customer.State.WAITING_FOR_FOOD


func _pop_next_order() -> Customer:
	while not GameManager.order_queue.is_empty():
		var c: Customer = GameManager.order_queue.pop_front()
		if is_instance_valid(c) and c.state == Customer.State.WAITING_FOR_FOOD:
			return c
	return null


# ---------------------------------------------------------------------
# Drawing (placeholder art)
# ---------------------------------------------------------------------
func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var floor_size := Vector2(cols * CELL_SIZE, rows * CELL_SIZE)

	# Checkerboard wooden floor.
	for x in cols:
		for y in rows:
			var shade: float = 0.38 if (x + y) % 2 == 0 else 0.33
			draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE),
					Color(shade, shade * 0.72, shade * 0.5))

	# Faint grid lines while building, so squares are easy to see,
	# and a red tint on the doorway, which can't be built on.
	if build_type != "":
		for x in cols + 1:
			draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, floor_size.y), Color(1, 1, 1, 0.25), 2.0)
		for y in rows + 1:
			draw_line(Vector2(0, y * CELL_SIZE), Vector2(floor_size.x, y * CELL_SIZE), Color(1, 1, 1, 0.25), 2.0)
		draw_rect(Rect2(Vector2(door_cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE)), Color(1, 0.2, 0.2, 0.2))
	# With the Door tool, show every square along the walls it could go.
	if build_type == "door":
		for x in cols:
			for y in rows:
				var spot := Vector2i(x, y)
				if _side_of(spot) != "" and spot != door_cell and not furniture.has(spot):
					draw_rect(Rect2(Vector2(spot) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE)), Color(1.0, 0.85, 0.3, 0.18))

	# Walls and door. The doormat sticks out through the wall.
	draw_rect(Rect2(Vector2.ZERO, floor_size), Color(0.2, 0.12, 0.07), false, 8.0)
	var door_rect := Rect2(Vector2(door_cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
	match door_side:
		"bottom": door_rect = Rect2(door_rect.position.x, floor_size.y - 4, CELL_SIZE, 60)
		"top": door_rect = Rect2(door_rect.position.x, -56, CELL_SIZE, 60)
		"left": door_rect = Rect2(-56, door_rect.position.y, 60, CELL_SIZE)
		"right": door_rect = Rect2(floor_size.x - 4, door_rect.position.y, 60, CELL_SIZE)
	draw_rect(door_rect, Color(0.45, 0.3, 0.15))

	# Furniture.
	for cell in furniture:
		var type: String = furniture[cell]
		var rect := Rect2(Vector2(cell) * CELL_SIZE + Vector2(8, 8), Vector2(CELL_SIZE - 16, CELL_SIZE - 16))
		draw_rect(rect, GameManager.FURNITURE[type]["color"])
		draw_string(font, rect.position + Vector2(0, 20), GameManager.FURNITURE[type]["name"],
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color.WHITE)

		if type != "kitchen":
			continue
		var h: Dictionary = hearths[cell]
		if not is_instance_valid(h["cook"]):
			draw_string(font, rect.position + Vector2(0, 42), "No cook",
					HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Color(1.0, 0.7, 0.7))

		# Cooking progress bar on busy Hearths.
		if not h["job"].is_empty():
			var job: Dictionary = h["job"]
			var done: float = 1.0 - job["time_left"] / job["total"]
			var bar := Rect2(rect.position + Vector2(4, rect.size.y - 14), Vector2(rect.size.x - 8, 8))
			draw_rect(bar, Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * done, bar.size.y)), Color(1.0, 0.75, 0.2))

		# A finished plate waiting for a waiter.
		if is_instance_valid(h["plate_for"]):
			draw_circle(rect.get_center() + Vector2(0, 8), 11.0, Color.WHITE)
			draw_circle(rect.get_center() + Vector2(0, 8), 7.0, Color(0.85, 0.55, 0.2))
