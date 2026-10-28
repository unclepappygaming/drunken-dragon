# =====================================================================
# tavern_grid.gd  —  the tavern floor. Attached to the TavernGrid node.
#
# The floor is a grid of squares, 8 x 10 to start, shown ISOMETRIC:
# every square is drawn as a diamond, so the room is seen from a corner.
# The grid underneath is still plain squares (x across, y down); only
# where they appear on screen changes (see iso() and _cell_at()). Expansions add
# columns on the right and rows at the bottom, so existing squares keep
# their coordinates. Each square can hold one piece of furniture.
# This script:
#   * draws the floor, back walls and door; tables, Hearths and the low
#     front walls are FloorProp nodes so people can walk behind them
#   * handles taps to build/remove furniture and move the door
#   * finds walking routes around the furniture (pathfinding)
#   * tracks which tables are taken
#   * holds the KITCHEN: a zone 2 squares deep. Cooks work from the back
#     row (the aisle), facing the room; the front row is the line, with
#     Hearths and, at the right end, the expo counter ("the pass")
#   * runs the Hearths: each cooks one order at a time while its cook
#     stands behind it; the cook then carries the plate to the pass,
#     where waiters pick it up from the front
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
# One square on screen: a diamond this wide and tall (2:1, the classic
# isometric shape).
const TILE_W: float = 96.0
const TILE_H: float = 48.0
const WALL_HEIGHT: float = 76.0       # the tall back walls
const LOW_WALL_HEIGHT: float = 16.0   # the front walls you can see over
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

# THE KITCHEN: kitchen_pos is the aisle's left square. The zone is
# kitchen_width squares wide and KITCHEN_DEPTH (2) deep:
#   row kitchen_pos.y      the aisle: cooks stand here, facing the room
#   row kitchen_pos.y + 1  the line: Hearths, gaps, and the pass (expo)
#                          at the right end
const KITCHEN_DEPTH: int = 2
const KITCHEN_START_WIDTH: int = 4
const KITCHEN_MAX_WIDTH: int = 8
const KITCHEN_WIDEN_COST: int = 150
const EXPO_CAPACITY: int = 3      # plates the pass can hold
# Walking through the kitchen counts as this many squares, so guests and
# waiters go around it unless there's truly no other way.
const KITCHEN_WEIGHT: float = 8.0
var kitchen_pos: Vector2i = Vector2i(4, 0)
var kitchen_width: int = KITCHEN_START_WIDTH
# Plates waiting on the pass, oldest first: {"guest": Customer, "taker": Waiter or null}
var expo_plates: Array = []

# Vector2i(column, row) -> furniture ID ("table", "kitchen" for a Hearth,
# or "expo" for the pass, which comes with the kitchen)
var furniture: Dictionary = {}
# table cell -> the Customer sitting there, or null if free
var table_owner: Dictionary = {}
# hearth cell -> {
#   "cook":        the Cook working it, or null
#   "job":         {} when not cooking, or {"customer", "time_left", "total"}
# }
var hearths: Dictionary = {}

# AStarGrid2D is Godot's built-in pathfinder for square grids. We mark
# furniture squares as "solid" and it finds the shortest way around them.
var _astar := AStarGrid2D.new()

# The y-sorted node that holds every FloorProp (see main.tscn).
@onready var _props_node: Node2D = get_node("../Props")
var _props: Dictionary = {}          # furniture cell -> its FloorProp
var _wall_props: Array[FloorProp] = []


func _ready() -> void:
	_astar.cell_size = Vector2.ONE   # only the square numbers matter
	# Diagonal steps are allowed, but never squeezing between two pieces
	# of furniture or cutting a corner.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_apply_size()

	# A free starter layout so Day 1 works right away: the kitchen along
	# the back wall with one Hearth, and two tables.
	_place(expo_cell(), "expo")
	_place(Vector2i(5, 1), "kitchen")
	_place(Vector2i(1, 3), "table")
	_place(Vector2i(3, 5), "table")
	_mark_kitchen()


# The camera tells us about taps (drags just move the view), already
# converted to a point in the world, so zooming doesn't change which
# square you hit.
func handle_tap(world_pos: Vector2) -> void:
	if build_type == "":
		return
	var cell: Vector2i = cell_at_world(world_pos)
	if cell != NO_CELL:
		_try_build(cell)


# The floor and back walls, in Main's space: the box around the diamond.
func play_rect() -> Rect2:
	var top: Vector2 = iso(Vector2(0, 0))
	var right: Vector2 = iso(Vector2(cols, 0))
	var bottom: Vector2 = iso(Vector2(cols, rows))
	var left: Vector2 = iso(Vector2(0, rows))
	var box := Rect2(Vector2(left.x, top.y - WALL_HEIGHT), Vector2(right.x - left.x, bottom.y - top.y + WALL_HEIGHT))
	return Rect2(position + box.position, box.size)


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
	if is_node_ready():
		_rebuild_front_walls()   # the doorway is a gap in the front wall
		queue_redraw()


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
	_mark_kitchen()
	_rebuild_front_walls()
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
	# Plates nobody will eat any more get cleared off the pass.
	expo_plates = expo_plates.filter(func(plate): return _wants_food(plate["guest"]))

	for cell in hearths:
		# Dictionaries are shared, not copied: changing `h` changes hearths[cell].
		var h: Dictionary = hearths[cell]

		# The fire only cooks with a cook standing behind it.
		var cook = h["cook"]
		if not is_instance_valid(cook) or not cook.is_at_hearth():
			continue

		var job: Dictionary = h["job"]
		if job.is_empty():
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
				cook.take_dish(job["customer"])   # they carry it to the pass
				h["job"] = {}
	queue_redraw()
	# Hearths and the pass show progress and plates, so redraw them every frame.
	for cell in hearths:
		_props[cell].queue_redraw()
	if _props.has(expo_cell()):
		_props[expo_cell()].queue_redraw()


# ---------------------------------------------------------------------
# Helpers the other scripts use. Positions are in Main's space
# (we add our own `position` because the grid is offset on screen).
# ---------------------------------------------------------------------
# ISOMETRIC PROJECTION: turns a grid position (in squares, can be
# fractional) into a screen offset from the grid's top corner. One
# square right goes down-right on screen; one square down goes down-left.
func iso(grid_pos: Vector2) -> Vector2:
	return Vector2((grid_pos.x - grid_pos.y) * TILE_W / 2.0, (grid_pos.x + grid_pos.y) * TILE_H / 2.0)


func cell_center(cell: Vector2i) -> Vector2:
	return position + iso(Vector2(cell) + Vector2(0.5, 0.5))


# Just outside the front door, where people appear and disappear.
func door_position() -> Vector2:
	return cell_center(door_cell) + iso(OUTWARD[door_side]) * 0.95


# Which way the waiting line runs along the outside wall (a screen
# direction): toward the longer stretch of wall, so it has room.
func line_direction() -> Vector2:
	var along: Vector2
	if door_side in ["top", "bottom"]:
		along = Vector2(-1, 0) if door_index >= cols / 2.0 else Vector2(1, 0)
	else:
		along = Vector2(0, 1) if door_index < rows / 2.0 else Vector2(0, -1)
	return iso(along).normalized()


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
	# Kitchen pieces have fixed spots: cooks always stand behind the line,
	# waiters always collect from in front of the pass.
	match furniture.get(furniture_cell, ""):
		"kitchen":
			return furniture_cell + Vector2i(0, -1)
		"expo":
			return expo_back() if asker is Cook else expo_front()
	var start: Vector2i = cell_at_world(from_pos)
	if start == NO_CELL:
		start = door_cell
	var in_use: Dictionary = _cells_in_use(asker)

	var best: Vector2i = NO_CELL
	var best_score: float = INF
	for side in SIDES:
		var spot: Vector2i = furniture_cell + side
		# Nobody sits in the kitchen or on the waiters' pickup spot.
		if not _in_bounds(spot) or furniture.has(spot) or in_kitchen(spot) or spot == expo_front():
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
	# Spare cooks wait in the kitchen aisle; waiters wait near the pass,
	# outside the kitchen.
	var cook: bool = asker is Cook
	var anchor: Vector2 = Vector2(expo_front())
	var in_use: Dictionary = _cells_in_use(asker)
	var choices: Array = []
	for x in cols:
		for y in rows:
			var spot := Vector2i(x, y)
			if furniture.has(spot) or spot == door_cell or in_use.has(spot) or spot == expo_front():
				continue
			if cook != (in_kitchen(spot) and spot.y == kitchen_pos.y):
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


# ---------------------------------------------------------------------
# The pass (expo counter)
# ---------------------------------------------------------------------
func expo_cell() -> Vector2i:
	return kitchen_pos + Vector2i(kitchen_width - 1, 1)


# Where a cook stands to put a plate down, and where a waiter picks it up.
func expo_back() -> Vector2i:
	return expo_cell() + Vector2i(0, -1)


func expo_front() -> Vector2i:
	return expo_cell() + Vector2i(0, 1)


func expo_has_room() -> bool:
	return expo_plates.size() < EXPO_CAPACITY


# A cook sets a finished dish down on the pass.
func put_on_expo(guest: Customer) -> void:
	expo_plates.append({"guest": guest, "taker": null})


# A Waiter asks for a plate on the pass that nobody is fetching yet.
func claim_ready_plate(waiter: Waiter) -> bool:
	for plate in expo_plates:
		if _wants_food(plate["guest"]) and not is_instance_valid(plate["taker"]):
			plate["taker"] = waiter
			return true
	return false


# Is the plate this waiter claimed still there?
func is_plate_waiting(waiter: Waiter) -> bool:
	return expo_plates.any(func(plate): return plate["taker"] == waiter and _wants_food(plate["guest"]))


# The waiter takes their plate. Returns the guest it's for, or null.
func pick_up_plate(waiter: Waiter) -> Customer:
	for plate in expo_plates:
		if plate["taker"] == waiter:
			expo_plates.erase(plate)
			if _wants_food(plate["guest"]):
				return plate["guest"]
			return null
	return null


# ---------------------------------------------------------------------
# The kitchen zone
# ---------------------------------------------------------------------
func kitchen_rect() -> Rect2i:
	return Rect2i(kitchen_pos, Vector2i(kitchen_width, KITCHEN_DEPTH))


func in_kitchen(cell: Vector2i) -> bool:
	return kitchen_rect().has_point(cell)


# The front row of the kitchen, where Hearths go (the pass is there too).
func on_line(cell: Vector2i) -> bool:
	return in_kitchen(cell) and cell.y == kitchen_pos.y + 1


# The kitchen as plain data for the save file.
func get_kitchen() -> Array:
	return [kitchen_pos.x, kitchen_pos.y, kitchen_width]


# Makes the kitchen squares expensive to walk through (see KITCHEN_WEIGHT).
func _mark_kitchen() -> void:
	for x in cols:
		for y in rows:
			_astar.set_point_weight_scale(Vector2i(x, y), KITCHEN_WEIGHT if in_kitchen(Vector2i(x, y)) else 1.0)
	queue_redraw()


# Checks whether a kitchen could go at `pos` with `width`, given the
# furniture in `solid` (with the current kitchen's pieces already taken
# out). Returns "" if it fits, otherwise what's wrong.
func _kitchen_fits(pos: Vector2i, width: int, solid: Dictionary) -> String:
	var zone := Rect2i(pos, Vector2i(width, KITCHEN_DEPTH))
	if zone.position.x < 0 or zone.position.y < 0 or zone.end.x > cols or zone.end.y > rows:
		return "The kitchen doesn't fit there."
	var front: Vector2i = pos + Vector2i(width - 1, 2)
	if not _in_bounds(front):
		return "Waiters need room in front of the pass."
	for x in range(zone.position.x, zone.end.x):
		for y in range(zone.position.y, zone.end.y):
			var spot := Vector2i(x, y)
			if spot == door_cell:
				return "The kitchen can't cover the doorway."
			if solid.has(spot):
				return "Clear the tables out of the way first."
	if solid.has(front) or front == door_cell:
		return "Waiters need room in front of the pass."
	return ""


# The kitchen's pieces (Hearths and the pass) as they'd be at a new
# position or width: furniture minus the old kitchen, plus the new one.
func _layout_with_kitchen(pos: Vector2i, width: int) -> Dictionary:
	var solid: Dictionary = {}
	for cell in furniture:
		if furniture[cell] == "table":
			solid[cell] = "table"
	for cell in hearths:
		var slot: int = cell.x - kitchen_pos.x
		solid[Vector2i(pos.x + slot, pos.y + 1)] = "kitchen"
	solid[pos + Vector2i(width - 1, 1)] = "expo"
	return solid


# Moves the whole kitchen (Hearths, pass and all) so its aisle starts at
# `cell`. Only between days, like moving the door.
func _try_move_kitchen(cell: Vector2i) -> void:
	if GameManager.is_open or not get_tree().get_nodes_in_group("customers").is_empty():
		build_message.emit("Move the kitchen after closing time.")
		return
	if cell == kitchen_pos:
		build_message.emit("The kitchen is already here.")
		return
	var tables: Dictionary = {}
	for spot in furniture:
		if furniture[spot] == "table":
			tables[spot] = true
	var problem: String = _kitchen_fits(cell, kitchen_width, tables)
	if problem != "":
		build_message.emit(problem)
		return
	var solid: Dictionary = _layout_with_kitchen(cell, kitchen_width)
	if not _people_clear_of(solid) or not _layout_works(solid, door_cell, cell, kitchen_width):
		build_message.emit("That would block someone's way!")
		return
	_rebuild_kitchen(cell, kitchen_width)
	layout_changed.emit()
	build_message.emit("Moved the kitchen.")


# One more square of width on the right; the pass moves to the new end.
func try_widen_kitchen() -> void:
	if GameManager.is_open or not get_tree().get_nodes_in_group("customers").is_empty():
		build_message.emit("Widen the kitchen after closing time.")
		return
	if kitchen_width >= KITCHEN_MAX_WIDTH:
		build_message.emit("The kitchen is as wide as it gets.")
		return
	var tables: Dictionary = {}
	for spot in furniture:
		if furniture[spot] == "table":
			tables[spot] = true
	var problem: String = _kitchen_fits(kitchen_pos, kitchen_width + 1, tables)
	if problem != "":
		build_message.emit(problem.replace("doesn't fit there", "has no room to grow"))
		return
	var solid: Dictionary = _layout_with_kitchen(kitchen_pos, kitchen_width + 1)
	if not _people_clear_of(solid) or not _layout_works(solid, door_cell, kitchen_pos, kitchen_width + 1):
		build_message.emit("That would block someone's way!")
		return
	if not GameManager.try_spend(KITCHEN_WIDEN_COST):
		build_message.emit("Not enough gold (%dg)." % KITCHEN_WIDEN_COST)
		return
	_rebuild_kitchen(kitchen_pos, kitchen_width + 1)
	layout_changed.emit()
	build_message.emit("The kitchen is now %d squares wide." % kitchen_width)


# Nobody may be standing where a new solid piece would go.
func _people_clear_of(solid: Dictionary) -> bool:
	var in_use: Dictionary = _cells_in_use(null)
	for cell in solid:
		if not furniture.has(cell) and in_use.has(cell):
			return false
	return true


# Takes the kitchen's pieces off the floor and puts them back at a new
# position/width. Cooks let go of their Hearths and find them again.
func _rebuild_kitchen(pos: Vector2i, width: int) -> void:
	var slots: Array[int] = []
	for cell in hearths:
		slots.append(cell.x - kitchen_pos.x)
		if is_instance_valid(hearths[cell]["cook"]):
			hearths[cell]["cook"].release_hearth()
	for cell in furniture.keys():
		if furniture[cell] != "table":
			furniture.erase(cell)
			_remove_prop(cell)
	hearths.clear()
	expo_plates.clear()
	kitchen_pos = pos
	kitchen_width = width
	_apply_size()   # resets the pathfinder, then marks furniture and kitchen
	_place(expo_cell(), "expo")
	for slot in slots:
		_place(Vector2i(pos.x + slot, pos.y + 1), "kitchen")
	_mark_kitchen()


# Sets the kitchen from a save file. Saves from before the kitchen had
# Hearths anywhere, so a spot is found for it (see load_layout).
func set_kitchen(data) -> bool:
	if typeof(data) != TYPE_ARRAY or data.size() != 3:
		return false
	kitchen_pos = Vector2i(int(data[0]), int(data[1]))
	kitchen_width = clampi(int(data[2]), KITCHEN_START_WIDTH, KITCHEN_MAX_WIDTH)
	return _kitchen_fits(kitchen_pos, kitchen_width, {}) == ""


# The furniture as plain data for the save file: [[column, row, type], ...]
# (JSON can't store a Vector2i, but it can store a list of numbers.)
func get_layout() -> Array:
	var layout: Array = []
	for cell in furniture:
		if furniture[cell] != "expo":   # the pass comes with the kitchen
			layout.append([cell.x, cell.y, furniture[cell]])
	return layout


# Replaces all furniture with a saved layout. Called before any staff
# or guests exist, so nobody needs a new route. `kitchen` is the saved
# kitchen ([x, y, width]) or null for saves from before the kitchen.
func load_layout(layout: Array, kitchen = null) -> void:
	for cell in _props.keys():
		_remove_prop(cell)
	furniture.clear()
	table_owner.clear()
	hearths.clear()
	expo_plates.clear()
	_apply_size()
	var saved_hearths: Array[Vector2i] = []
	var tables: Dictionary = {}
	for entry in layout:
		# Skip anything that doesn't make sense rather than crash.
		if typeof(entry) != TYPE_ARRAY or entry.size() != 3:
			continue
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if not _in_bounds(cell) or cell == door_cell:
			continue
		if entry[2] == "kitchen":
			saved_hearths.append(cell)
		elif entry[2] == "table":
			tables[cell] = true

	var known: bool = set_kitchen(kitchen) if kitchen != null else false
	if not known:
		_place_kitchen_for_old_save(saved_hearths.size(), tables)
	for cell in tables:
		if not in_kitchen(cell) and cell != expo_front():
			_place(cell, "table")
	_place(expo_cell(), "expo")

	# Hearths that were on the kitchen's line stay put; any others (old
	# saves had them anywhere) move onto free spots on the line. Ones
	# that don't fit are sold back.
	var free_slots: Array[Vector2i] = []
	for x in range(kitchen_pos.x, kitchen_pos.x + kitchen_width - 1):
		free_slots.append(Vector2i(x, kitchen_pos.y + 1))
	var leftovers: Array[Vector2i] = []
	for cell in saved_hearths:
		if free_slots.has(cell):
			_place(cell, "kitchen")
			free_slots.erase(cell)
		else:
			leftovers.append(cell)
	for cell in leftovers:
		if free_slots.is_empty():
			GameManager.refund(floori(GameManager.FURNITURE["kitchen"]["cost"] / 2.0))
		else:
			_place(free_slots.pop_front(), "kitchen")
	_mark_kitchen()


# Old saves had no kitchen: find the first spot (top rows first) where one
# fits around the tables, wide enough for every Hearth plus the pass.
func _place_kitchen_for_old_save(hearth_count: int, tables: Dictionary) -> void:
	kitchen_width = clampi(hearth_count + 2, KITCHEN_START_WIDTH, KITCHEN_MAX_WIDTH)
	for y in rows:
		for x in cols:
			var pos := Vector2i(x, y)
			if _kitchen_fits(pos, kitchen_width, tables) != "":
				continue
			var solid: Dictionary = tables.duplicate()
			solid[pos + Vector2i(kitchen_width - 1, 1)] = "expo"
			if _layout_works(solid, door_cell, pos, kitchen_width):
				kitchen_pos = pos
				return
	# No room anywhere: put it top-left and sell the tables in the way.
	kitchen_pos = Vector2i.ZERO
	for cell in tables.keys():
		if Rect2i(kitchen_pos, Vector2i(kitchen_width, KITCHEN_DEPTH + 1)).has_point(cell):
			tables.erase(cell)
			GameManager.refund(floori(GameManager.FURNITURE["table"]["cost"] / 2.0))


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
	if build_type == "kitchen_move":
		_try_move_kitchen(cell)
		return
	if furniture.has(cell):
		build_message.emit("That square is taken.")
		return
	if build_type == "table" and in_kitchen(cell):
		build_message.emit("Tables can't go in the kitchen.")
		return
	if build_type == "kitchen" and not on_line(cell):
		build_message.emit("Hearths go on the kitchen's front row.")
		return
	if cell == expo_front():
		build_message.emit("Keep the spot in front of the pass clear for waiters.")
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
		hearths[cell] = {"cook": null, "job": {}}
	# Its FloorProp stands at the square's middle, for y-sorting.
	_props[cell] = _new_prop(type, cell, cell_center(cell))


func _new_prop(kind: String, cell: Vector2i, at: Vector2) -> FloorProp:
	var prop := FloorProp.new()
	prop.grid = self
	prop.kind = kind
	prop.cell = cell
	prop.position = at
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel art
	_props_node.add_child(prop)
	return prop


func _remove_prop(cell: Vector2i) -> void:
	if _props.has(cell):
		# Hidden at once: queue_free() only deletes it at the end of the frame.
		_props[cell].visible = false
		_props[cell].queue_free()
		_props.erase(cell)


# The low front walls (bottom and right edges), one FloorProp per edge
# square, placed at the square's bottom corner so people inside are
# drawn behind the wall and people outside in front of it.
func _rebuild_front_walls() -> void:
	for prop in _wall_props:
		prop.queue_free()
	_wall_props.clear()
	for x in cols:
		for y in rows:
			var edges: Array = []
			if y == rows - 1 and not (door_side == "bottom" and door_cell == Vector2i(x, y)):
				edges.append("bottom")
			if x == cols - 1 and not (door_side == "right" and door_cell == Vector2i(x, y)):
				edges.append("right")
			if edges.is_empty():
				continue
			var prop := _new_prop("wall", Vector2i(x, y), position + iso(Vector2(x + 1, y + 1)))
			prop.edges = edges
			_wall_props.append(prop)


func _try_remove(cell: Vector2i) -> void:
	if not furniture.has(cell):
		return
	var type: String = furniture[cell]
	if type == "expo":
		build_message.emit("The pass is part of the kitchen. Use Kitchen to move it.")
		return
	if type == "table" and table_owner[cell] != null:
		build_message.emit("Someone's sitting there!")
		return
	if type == "kitchen":
		var h: Dictionary = hearths[cell]
		if not h["job"].is_empty():
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
	_remove_prop(cell)
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
	if in_kitchen(cell) or cell == expo_front():
		build_message.emit("The door can't go in the kitchen.")
		return
	if _cells_in_use(null).has(cell):
		build_message.emit("Someone's in the way!")
		return
	for walker in get_tree().get_nodes_in_group("walkers"):
		if walker.current_cell() == NO_CELL:
			build_message.emit("Wait until everyone is inside.")
			return
	if not _layout_works(furniture, cell, kitchen_pos, kitchen_width):
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
	solid[new_cell] = build_type
	return _layout_works(solid, door_cell, kitchen_pos, kitchen_width)


# Every piece of furniture needs a side people can reach from the door,
# and nobody may get walled in. In the kitchen, every Hearth needs the
# aisle square behind it free and reachable (that's where its cook
# stands), and the pass needs both its back (cooks) and front (waiters).
# `solid` maps squares to what's on them.
func _layout_works(solid: Dictionary, door: Vector2i, k_pos: Vector2i, k_width: int) -> bool:
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

	for piece in solid:
		var needs: Array = []
		match solid[piece]:
			"kitchen": needs = [piece + Vector2i(0, -1)]
			"expo": needs = [piece + Vector2i(0, -1), piece + Vector2i(0, 1)]
		for spot in needs:
			if not reachable.has(spot):
				return false
	# Kitchen geometry: the aisle row must exist above the line.
	return k_pos.y >= 0 and k_pos.y + KITCHEN_DEPTH <= rows and k_width >= KITCHEN_START_WIDTH


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


# The reverse of iso(): which square a screen offset lands on.
func _cell_at(local_pos: Vector2) -> Vector2i:
	var across: float = local_pos.x / (TILE_W / 2.0)
	var down: float = local_pos.y / (TILE_H / 2.0)
	var cell := Vector2i(floori((across + down) / 2.0), floori((down - across) / 2.0))
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
# Drawing (simple shapes for now; the art pass replaces them)
# ---------------------------------------------------------------------
const FLOOR_A := Color8(237, 201, 138)
const FLOOR_B := Color8(226, 185, 118)
const FLOOR_LINE := Color8(205, 160, 98)
const PLASTER_TOP := Color8(240, 226, 194)    # back wall along the top edge
const PLASTER_LEFT := Color8(224, 208, 174)   # back wall along the left edge (shadier)
const PANEL_TOP := Color8(152, 100, 60)
const PANEL_LEFT := Color8(134, 87, 52)
const TRIM := Color8(105, 66, 38)
const KITCHEN_A := Color8(176, 178, 180)    # stone tiles in the kitchen
const KITCHEN_B := Color8(160, 163, 166)


# The four corners of a square's diamond, in this node's space.
func _diamond(cell: Vector2i) -> PackedVector2Array:
	var x: float = cell.x
	var y: float = cell.y
	return PackedVector2Array([iso(Vector2(x, y)), iso(Vector2(x + 1, y)),
			iso(Vector2(x + 1, y + 1)), iso(Vector2(x, y + 1))])


# Floor, back walls, doormat and build-mode markings. Everything people
# can stand behind is a FloorProp instead (see draw_prop).
func _draw() -> void:
	# Floor tiles.
	for x in cols:
		for y in rows:
			var tile: PackedVector2Array = _diamond(Vector2i(x, y))
			var even: bool = (x + y) % 2 == 0
			if in_kitchen(Vector2i(x, y)):
				draw_colored_polygon(tile, KITCHEN_A if even else KITCHEN_B)
			else:
				draw_colored_polygon(tile, FLOOR_A if even else FLOOR_B)
			draw_polyline(tile + PackedVector2Array([tile[0]]), FLOOR_LINE, 1.0)

	# Doormat on the doorway square.
	var mat: PackedVector2Array = _diamond(door_cell)
	var middle: Vector2 = iso(Vector2(door_cell) + Vector2(0.5, 0.5))
	for i in mat.size():
		mat[i] = middle + (mat[i] - middle) * 0.7
	draw_colored_polygon(mat, Color8(170, 60, 50))

	# Back walls: the top edge (upper right on screen) and the left edge
	# (upper left). Each wall piece is a floor edge pushed straight up.
	for x in cols:
		_draw_back_wall(iso(Vector2(x, 0)), iso(Vector2(x + 1, 0)), PLASTER_TOP, PANEL_TOP,
				door_side == "top" and door_index == x, x % 3 == 1)
	for y in rows:
		_draw_back_wall(iso(Vector2(0, y)), iso(Vector2(0, y + 1)), PLASTER_LEFT, PANEL_LEFT,
				door_side == "left" and door_index == y, y % 3 == 1)

	# Build mode: outline every square, tint the doorway, and with the
	# Door tool, show every edge square the door could move to.
	if build_type != "":
		for x in cols:
			for y in rows:
				var spot := Vector2i(x, y)
				var tile: PackedVector2Array = _diamond(spot)
				if build_type == "door" and _side_of(spot) != "" and spot != door_cell and not furniture.has(spot):
					draw_colored_polygon(tile, Color(1.0, 0.85, 0.3, 0.3))
				draw_polyline(tile + PackedVector2Array([tile[0]]), Color(0.35, 0.2, 0.08, 0.55), 1.5)
		draw_colored_polygon(_diamond(door_cell), Color(1, 0.2, 0.2, 0.25))
		# The kitchen's outline, and the waiters' pickup spot.
		var zone := PackedVector2Array([iso(Vector2(kitchen_pos)),
				iso(Vector2(kitchen_pos + Vector2i(kitchen_width, 0))),
				iso(Vector2(kitchen_pos + Vector2i(kitchen_width, KITCHEN_DEPTH))),
				iso(Vector2(kitchen_pos + Vector2i(0, KITCHEN_DEPTH)))])
		draw_polyline(zone + PackedVector2Array([zone[0]]), Color8(230, 120, 40), 3.0)
		draw_colored_polygon(_diamond(expo_front()), Color(0.3, 0.6, 1.0, 0.25))


func _draw_back_wall(from: Vector2, to: Vector2, plaster: Color, panel: Color, door: bool, window: bool) -> void:
	var up := Vector2(0, -WALL_HEIGHT)
	draw_colored_polygon(PackedVector2Array([from, to, to + up, from + up]), plaster)
	var panel_up: Vector2 = up * 0.38                       # wood panelling along the bottom
	draw_colored_polygon(PackedVector2Array([from, to, to + panel_up, from + panel_up]), panel)
	draw_line(from + up, to + up, TRIM, 4.0)                # top trim
	draw_line(from + panel_up, to + panel_up, TRIM, 2.0)
	var along: Vector2 = to - from
	if door:
		# A wooden door in the wall.
		var a: Vector2 = from + along * 0.2
		var b: Vector2 = from + along * 0.8
		var door_up: Vector2 = up * 0.78
		draw_colored_polygon(PackedVector2Array([a, b, b + door_up, a + door_up]), Color8(120, 74, 40))
		draw_polyline(PackedVector2Array([a, a + door_up, b + door_up, b]), TRIM, 2.0)
		draw_circle(a + along * 0.5 + door_up * 0.45, 2.0, Color8(230, 190, 80))
	elif window:
		var a: Vector2 = from + along * 0.22 + up * 0.5
		var b: Vector2 = from + along * 0.78 + up * 0.5
		var win_up: Vector2 = up * 0.36
		draw_colored_polygon(PackedVector2Array([a, b, b + win_up, a + win_up]), Color8(175, 214, 236))
		draw_polyline(PackedVector2Array([a, b, b + win_up, a + win_up, a]), TRIM, 2.0)
		draw_line((a + b) / 2.0, (a + b) / 2.0 + win_up, TRIM, 2.0)


# Draws one FloorProp, in the prop's own space (its position is 0, 0).
func draw_prop(prop: FloorProp) -> void:
	if prop.kind == "kitchen" and not hearths.has(prop.cell):
		return   # just removed; it disappears at the end of the frame
	match prop.kind:
		"table": _draw_table(prop)
		"kitchen": _draw_hearth(prop)
		"expo": _draw_expo(prop)
		"wall": _draw_front_wall(prop)


# A box sitting on the middle of a square: `inset` is its size compared
# to the square, `height` how tall it is, starting `from_height` above
# the floor. Returns the middle of its top face.
func _draw_block(prop: FloorProp, inset: float, height: float, top: Color, left: Color, right: Color, from_height: float = 0.0) -> Vector2:
	var hw: float = TILE_W / 2.0 * inset
	var hh: float = TILE_H / 2.0 * inset
	var lift := Vector2(0, -height)
	var base := Vector2(0, -from_height)
	var n := Vector2(0, -hh)
	var e := Vector2(hw, 0)
	var s := Vector2(0, hh)
	var w := Vector2(-hw, 0)
	prop.draw_colored_polygon(PackedVector2Array([w + base, s + base, s + lift, w + lift]), left)
	prop.draw_colored_polygon(PackedVector2Array([s + base, e + base, e + lift, s + lift]), right)
	prop.draw_colored_polygon(PackedVector2Array([n + lift, e + lift, s + lift, w + lift]), top)
	return lift


# Pixel-art furniture (drawn by tools/sprites/make_furniture.py). Each
# frame is 64 x 72 with the middle of its square at (32, 58), drawn at 2x
# like the characters.
const TABLE_ART: Texture2D = preload("res://assets/sprites/furniture/table.png")
const HEARTH_ART: Texture2D = preload("res://assets/sprites/furniture/hearth.png")
const ART_FRAME := Vector2(64, 72)
const ART_ANCHOR := Vector2(32, 58)
const ART_SCALE: float = 2.0


func _draw_art(prop: FloorProp, art: Texture2D, frame: int = 0) -> void:
	var source := Rect2(Vector2(ART_FRAME.x * frame, 0), ART_FRAME)
	prop.draw_texture_rect_region(art, Rect2(-ART_ANCHOR * ART_SCALE, ART_FRAME * ART_SCALE), source)


func _draw_table(prop: FloorProp) -> void:
	_draw_art(prop, TABLE_ART)


func _draw_hearth(prop: FloorProp) -> void:
	var font: Font = ThemeDB.fallback_font
	var h: Dictionary = hearths[prop.cell]
	var cooking: bool = not h["job"].is_empty()
	# Frame 0 is the idle glow; while cooking, the fire cycles frames 1-3.
	var frame: int = 1 + (Time.get_ticks_msec() / 140) % 3 if cooking else 0
	_draw_art(prop, HEARTH_ART, frame)
	var top := Vector2(0, -50)   # just above the stew pot
	if cooking:
		var job: Dictionary = h["job"]
		var done: float = 1.0 - job["time_left"] / job["total"]
		var bar := Rect2(top + Vector2(-24, -30), Vector2(48, 7))
		prop.draw_rect(bar, Color(0.1, 0.1, 0.1))
		prop.draw_rect(Rect2(bar.position, Vector2(bar.size.x * done, bar.size.y)), Color(1.0, 0.75, 0.2))
	if not is_instance_valid(h["cook"]):
		prop.draw_string(font, top + Vector2(-40, -26), "No cook",
				HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color(1.0, 0.75, 0.75))


# The pass: a low counter with the waiting plates on it.
func _draw_expo(prop: FloorProp) -> void:
	var top: Vector2 = _draw_block(prop, 0.85, 26.0, Color8(214, 200, 176), Color8(150, 110, 70), Color8(128, 92, 58))
	for i in expo_plates.size():
		var spot: Vector2 = top + Vector2(-14 + i * 14, -2 + (i % 2) * 4)
		prop.draw_circle(spot, 7.0, Color.WHITE)
		prop.draw_circle(spot, 4.0, Color8(190, 110, 50))


func _draw_front_wall(prop: FloorProp) -> void:
	# The prop sits at its square's bottom corner. The bottom edge runs to
	# the square's left corner, the right edge to its right corner.
	var up := Vector2(0, -LOW_WALL_HEIGHT)
	var corners := {"bottom": Vector2(-TILE_W / 2.0, -TILE_H / 2.0), "right": Vector2(TILE_W / 2.0, -TILE_H / 2.0)}
	for edge in prop.edges:
		var far: Vector2 = corners[edge]
		var face: Color = Color8(178, 118, 70) if edge == "bottom" else Color8(156, 102, 60)
		prop.draw_colored_polygon(PackedVector2Array([far, Vector2.ZERO, up, far + up]), face)
		prop.draw_line(far + up, up, Color8(210, 160, 105), 3.0)   # the lighter top rail
