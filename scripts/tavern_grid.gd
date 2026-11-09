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
#   * tracks which tables are taken. A TABLE is a row of squares:
#     chair, tabletop, chair (3 x 1, 2 seats). A LONG TABLE is two such
#     rows side by side (3 x 2, 4 seats). Guests sit on the chairs; each
#     group gets a whole table. Tables can run either way (build_dir).
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
# Fired when a waiter clears a table, so the next guest in line can sit.
signal table_freed

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

# "" = not building. Otherwise "table", "long_table", "kitchen", "remove",
# "door" or "kitchen_move".
var build_type: String = ""
# Which way new tables run: (1, 0) = chairs at the left and right ends
# along x (down-right on screen), (0, 1) = along y (down-left).
var build_dir: Vector2i = Vector2i(1, 0)

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
const HALL_KITCHEN_MAX_WIDTH: int = 12   # the Grand Hall's kitchen can grow wider
const KITCHEN_WIDEN_COST: int = 250
const EXPO_CAPACITY: int = 3      # plates the pass can hold
# Walking through the kitchen counts as this many squares, so guests and
# waiters go around it unless there's truly no other way.
const KITCHEN_WEIGHT: float = 8.0
var kitchen_pos: Vector2i = Vector2i(4, 0)
var kitchen_width: int = KITCHEN_START_WIDTH
# Plates waiting on the pass, oldest first: {"guest": Customer, "taker": Waiter or null}
var expo_plates: Array = []

# Vector2i(column, row) -> furniture ID: "table" (a tabletop square),
# "chair", "kitchen" for a Hearth, or "expo" for the pass (which comes
# with the kitchen). Every one of these squares is solid.
var furniture: Dictionary = {}
# TABLES: each is known by its first tabletop square, its "anchor".
#   tables[anchor] = {"kind": "table" or "long_table", "dir": Vector2i,
#                     "tops": [tabletop squares], "chairs": [chair squares]}
# Chairs come in pairs facing each other across a tabletop: chairs[0]
# and chairs[1] share the first tabletop, chairs[2] and [3] the second.
var tables: Dictionary = {}
var _table_of: Dictionary = {}   # every tabletop and chair square -> its table's anchor
# DECORATIONS, just for looks. A floor piece is known by its first square:
#   decor[anchor] = {"id": ..., "cells": [every square it covers],
#                    "flip": true if turned the other way (Rotate)}
# Solid pieces are also "decor" in `furniture`; a rug isn't (people walk
# over it), but nothing can be built on it. Wall pieces hang on the back
# walls: wall_decor["top:3"] or ["left:5"] = id (one piece per stretch).
var decor: Dictionary = {}
var _decor_of: Dictionary = {}   # every square a floor piece covers -> its anchor
var wall_decor: Dictionary = {}
var decor_choice: String = ""    # the piece the "decor" build tool places
# THE PRIVATE DINING ROOM (Grand Hall only): squares painted with the
# "private" tool. A table standing wholly on them is private: nobles are
# seated there first, and pay and wait more there (see customer.gd).
var private_cells: Dictionary = {}   # cell -> true
const PRIVATE_COST: int = 40         # per square
# table anchor -> the Customer who took it (the first of their group), or null if free
var table_owner: Dictionary = {}
# table cell -> {"full": plates being eaten, "dirty": empty plates left
# behind}. A table with dirty plates can't seat anyone until a Waiter
# clears it and takes the plates back to the kitchen.
var table_dishes: Dictionary = {}
var _bussers: Dictionary = {}        # table anchor -> the Waiter coming to clear it
# hearth cell -> {
#   "cook":        the Cook working it, or null
#   "job":         {} when not cooking, or {"customer", "time_left", "total"}
# }
var hearths: Dictionary = {}
# bar cell -> the Bartender working it, or null. They stand behind it.
var bars: Dictionary = {}
const DRINKS: Array[String] = ["ale", "mead", "wine"]

# AStarGrid2D is Godot's built-in pathfinder for square grids. We mark
# furniture squares as "solid" and it finds the shortest way around them.
var _astar := AStarGrid2D.new()
# Cooks get their own copy without the kitchen's extra walking cost, so
# they walk straight along the aisle to the pass instead of looping out
# through the dining room. Both always have the same solid squares.
var _cook_astar := AStarGrid2D.new()

# The y-sorted node that holds every FloorProp (see main.tscn).
@onready var _props_node: Node2D = get_node("../Props")
var _props: Dictionary = {}          # furniture cell -> its FloorProp
var _wall_props: Array[FloorProp] = []


func _ready() -> void:
	for finder in [_astar, _cook_astar]:
		finder.cell_size = Vector2.ONE   # only the square numbers matter
		# Diagonal steps are allowed, but never squeezing between two pieces
		# of furniture or cutting a corner.
		finder.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_apply_size()

	# A free starter layout so Day 1 works right away: the kitchen along
	# the back wall with one Hearth, and two tables.
	_place(expo_cell(), "expo")
	_place(Vector2i(5, 1), "kitchen")
	_place_table("table", Vector2i(2, 4), Vector2i(1, 0))
	_place_table("table", Vector2i(5, 6), Vector2i(1, 0))
	_mark_kitchen()


# The camera tells us about taps (drags just move the view), already
# converted to a point in the world, so zooming doesn't change which
# square you hit.
func handle_tap(world_pos: Vector2) -> void:
	if build_type == "":
		return
	# Wall pieces go on the back walls, above the floor.
	var wall: String = _wall_at(world_pos - position)
	if build_type == "decor" and GameManager.DECOR[decor_choice]["where"] == "wall":
		_try_hang(wall)
		return
	if build_type == "remove" and wall_decor.has(wall):
		var taken: String = wall_decor[wall]
		wall_decor.erase(wall)
		queue_redraw()
		layout_changed.emit()
		build_message.emit("Took down the %s. Hang it again from Decor." % GameManager.DECOR[taken]["name"])
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
	for finder in [_astar, _cook_astar]:
		finder.region = Rect2i(0, 0, cols, rows)
		finder.update()
	for cell in furniture:
		_set_solid(cell, true)
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
				GameManager.buy_ingredients(next.order)
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
	for anchor in decor:   # animated decorations (the fireplace)
		if _props.has(anchor) and GameManager.DECOR[decor[anchor]["id"]].get("frames", 1) > 1:
			_props[anchor].queue_redraw()


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
# for_cook: use the cooks' pathfinder (no detours around the kitchen).
# Chairs are solid, but a route may start or end on one (a guest sitting
# down or getting up): those are opened just for this search.
func find_path(from_cell: Vector2i, to_cell: Vector2i, for_cook: bool = false) -> Array[Vector2i]:
	var finder: AStarGrid2D = _cook_astar if for_cook else _astar
	var opened: Array[Vector2i] = []
	for cell in [from_cell, to_cell]:
		if furniture.get(cell, "") == "chair" and finder.is_point_solid(cell):
			finder.set_point_solid(cell, false)
			opened.append(cell)
	var route: Array[Vector2i] = []
	if not finder.is_point_solid(from_cell) and not finder.is_point_solid(to_cell):
		route = finder.get_id_path(from_cell, to_cell)
	for cell in opened:
		finder.set_point_solid(cell, true)
	return route


func _set_solid(cell: Vector2i, solid: bool) -> void:
	_astar.set_point_solid(cell, solid)
	_cook_astar.set_point_solid(cell, solid)


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
		"bar":
			return bar_back(furniture_cell)
	var start: Vector2i = cell_at_world(from_pos)
	if start == NO_CELL:
		start = door_cell
	var in_use: Dictionary = _cells_in_use(asker)

	# A table is served from beside any of its tabletop squares.
	var bases: Array = [furniture_cell]
	if _table_of.has(furniture_cell):
		bases = tables[_table_of[furniture_cell]]["tops"]
	var best: Vector2i = NO_CELL
	var best_score: float = INF
	for base in bases:
		for side in SIDES:
			var spot: Vector2i = base + side
			var score: float = _access_score(spot, start, in_use)
			if score < best_score:
				best_score = score
				best = spot
	return best


# How good `spot` is to stand on (lower is better), INF if it can't be used.
func _access_score(spot: Vector2i, start: Vector2i, in_use: Dictionary) -> float:
	# Nobody stands in the kitchen or on the waiters' pickup spot.
	if not _in_bounds(spot) or furniture.has(spot) or in_kitchen(spot) or spot == expo_front():
		return INF
	var route: Array[Vector2i] = find_path(start, spot)
	if route.is_empty():
		return INF
	# A taken square still works, it just scores much worse.
	return route.size() + (100.0 if in_use.has(spot) else 0.0)


# ---------------------------------------------------------------------
# Tables and chairs
# ---------------------------------------------------------------------
# The squares a table would cover: {"tops": [...], "chairs": [...]}.
# `anchor` is the first tabletop; a long table's second row is beside it.
static func table_footprint(kind: String, anchor: Vector2i, dir: Vector2i) -> Dictionary:
	var across := Vector2i(dir.y, dir.x)   # the other way from the chairs
	var tops: Array[Vector2i] = []
	var chairs: Array[Vector2i] = []
	for row in (2 if kind == "long_table" else 1):
		var top: Vector2i = anchor + across * row
		tops.append(top)
		chairs.append(top - dir)
		chairs.append(top + dir)
	return {"tops": tops, "chairs": chairs}


static func seats_at(kind: String) -> int:
	return 4 if kind == "long_table" else 2


# The chairs of the table at `anchor`, in seating order (the first two
# face each other across the table).
func table_chairs(anchor: Vector2i) -> Array[Vector2i]:
	var chairs: Array[Vector2i] = []
	if tables.has(anchor):
		chairs.assign(tables[anchor]["chairs"])
	return chairs


# The tabletop square a chair faces.
func top_for_chair(chair: Vector2i) -> Vector2i:
	var table: Dictionary = tables.get(_table_of.get(chair, NO_CELL), {})
	for top in table.get("tops", []):
		if (top - chair).length_squared() == 1:
			return top
	return chair


# Where staff with nothing to do wait: a free square near the kitchen
# (the first Hearth) or the middle of the room. Not the doorway, not a
# square someone else is using, and preferably not beside a table, since
# that's where guests sit. NO_CELL if there's nowhere to go.
func standby_cell(asker: Node) -> Vector2i:
	# Spare cooks wait in the kitchen aisle; waiters wait near the pass,
	# outside the kitchen.
	var cook: bool = asker is Cook
	var anchor: Vector2 = Vector2(expo_front())
	if asker is Waiter and asker.role == "host":
		anchor = Vector2(door_cell)   # the host waits by the door to greet guests
	var in_use: Dictionary = _cells_in_use(asker)
	var choices: Array = []
	for x in cols:
		for y in rows:
			var spot := Vector2i(x, y)
			if furniture.has(spot) or spot == door_cell or in_use.has(spot) or spot == expo_front():
				continue
			# Cooks wait in the aisle; waiters anywhere outside the kitchen.
			if cook != (in_kitchen(spot) and spot.y == kitchen_pos.y) or (not cook and in_kitchen(spot)):
				continue
			var score: float = Vector2(spot).distance_to(anchor)
			for side in SIDES:
				if furniture.get(spot + side, "") in ["table", "chair"]:
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


# A free, clean table with at least `group` seats, or NO_CELL. The
# smallest table that fits wins, so long tables stay free for parties.
# private: "only" = private tables only, "first" = private ones if any
# are free, "avoid" = ordinary guests stay out of the private room while
# an ordinary table is free.
func find_free_table(group: int = 1, private: String = "avoid") -> Vector2i:
	if private == "first":
		var vip: Vector2i = find_free_table(group, "only")
		if vip != NO_CELL:
			return vip
	elif private == "avoid":
		var plain: Vector2i = find_free_table(group, "never")
		if plain != NO_CELL:
			return plain
	var best: Array[Vector2i] = []
	var best_seats: int = 99
	for anchor in table_owner:
		var seats: int = seats_at(tables[anchor]["kind"])
		if table_owner[anchor] != null or not _is_clean(anchor) or seats < group or seats > best_seats:
			continue
		if (private == "only" and not is_private_table(anchor)) or (private == "never" and is_private_table(anchor)):
			continue
		if seats < best_seats:
			best.clear()
			best_seats = seats
		best.append(anchor)
	if best.is_empty():
		return NO_CELL
	return best.pick_random()


# The most seats any free table has right now (0 if none is free).
func biggest_free_table() -> int:
	var most: int = 0
	for anchor in table_owner:
		if table_owner[anchor] == null and _is_clean(anchor):
			most = maxi(most, seats_at(tables[anchor]["kind"]))
	return most


func reserve_table(cell: Vector2i, customer: Customer) -> void:
	table_owner[cell] = customer


func release_table(cell: Vector2i) -> void:
	if table_owner.has(cell):
		table_owner[cell] = null


# ---------------------------------------------------------------------
# Plates on tables
# ---------------------------------------------------------------------
func _is_clean(cell: Vector2i) -> bool:
	return table_dishes.get(cell, {}).is_empty()


# How many plates on a table are finished with (waiting to be cleared).
func _dirty_count(cell: Vector2i) -> int:
	var count: int = 0
	for seat in table_dishes.get(cell, {}):
		if table_dishes[cell][seat]["done"]:
			count += 1
	return count


# A Waiter sets a guest's dish down in front of their chair.
func serve_dish(cell: Vector2i, chair: Vector2i, dish: String) -> void:
	if not tables.has(cell):
		return
	var plates: Dictionary = table_dishes.get(cell, {})
	plates[maxi(tables[cell]["chairs"].find(chair), 0)] = {"dish": dish, "done": false}
	table_dishes[cell] = plates
	_props[cell].queue_redraw()


# The guest finished: their plate (or mug) is left empty.
func finish_dish(cell: Vector2i, chair: Vector2i) -> void:
	if not tables.has(cell) or not table_dishes.has(cell):
		return
	var seat: int = maxi(tables[cell]["chairs"].find(chair), 0)
	if table_dishes[cell].has(seat):
		table_dishes[cell][seat]["done"] = true
	_props[cell].queue_redraw()


# A Waiter looks for a table everyone has left that still has dirty
# plates and nobody else is coming to clear. Returns NO_CELL if none.
func claim_dirty_table(waiter: Waiter) -> Vector2i:
	for cell in table_dishes:
		if _dirty_count(cell) > 0 and table_owner.get(cell) == null \
				and not is_instance_valid(_bussers.get(cell)):
			_bussers[cell] = waiter
			return cell
	return NO_CELL


# The Waiter is at the table: they pick up every dirty plate. Returns how
# many they took (0 if the table was sold or washed meanwhile).
func clear_table(cell: Vector2i, waiter: Waiter) -> int:
	if _bussers.get(cell) == waiter:
		_bussers.erase(cell)
	if not table_dishes.has(cell):
		return 0
	var taken: int = 0
	for seat in table_dishes[cell].keys():
		if table_dishes[cell][seat]["done"]:
			table_dishes[cell].erase(seat)
			taken += 1
	if table_dishes[cell].is_empty():
		table_dishes.erase(cell)
	_props[cell].queue_redraw()
	if _is_clean(cell):
		table_freed.emit()
	return taken


func release_busser(waiter: Waiter) -> void:
	for cell in _bussers.keys():
		if _bussers[cell] == waiter:
			_bussers.erase(cell)


func has_dirty_tables() -> bool:
	for cell in table_dishes:
		if _dirty_count(cell) > 0:
			return true
	return false


# Overnight, any plates still out get washed.
func wash_all_tables() -> void:
	table_dishes.clear()
	_bussers.clear()
	for cell in table_owner:
		_props[cell].queue_redraw()


# A Cook asks for a Hearth that nobody is working. Returns its cell.
func claim_hearth(cook: Cook) -> Vector2i:
	for cell in hearths:
		if not is_instance_valid(hearths[cell]["cook"]):
			hearths[cell]["cook"] = cook
			return cell
	return NO_CELL


# ---------------------------------------------------------------------
# The Bar
# ---------------------------------------------------------------------
func bar_back(cell: Vector2i) -> Vector2i:
	return cell + Vector2i(0, -1)


# A Bartender asks for a Bar nobody is working. Returns its cell or NO_CELL.
func claim_bar(bartender: Node) -> Vector2i:
	for cell in bars:
		if bars[cell] == bartender:
			return cell
	for cell in bars:
		if not is_instance_valid(bars[cell]):
			bars[cell] = bartender
			return cell
	return NO_CELL


func release_bar(bartender: Node) -> void:
	for cell in bars:
		if bars[cell] == bartender:
			bars[cell] = null


# Is a bartender working a Bar? Then drinks go to them, not the Hearths.
func bar_open() -> bool:
	for cell in bars:
		if is_instance_valid(bars[cell]):
			return true
	return false


# Is a drink order waiting for a bartender?
func take_drink_order_peek() -> bool:
	for c in GameManager.order_queue:
		if is_instance_valid(c) and c.state == Customer.State.WAITING_FOR_FOOD and c.order.get("id", "") in DRINKS:
			return true
	return false


# The next drink order waiting, taken out of the kitchen's queue, or null.
func take_drink_order() -> Customer:
	for c in GameManager.order_queue:
		if is_instance_valid(c) and c.state == Customer.State.WAITING_FOR_FOOD and c.order.get("id", "") in DRINKS:
			GameManager.order_queue.erase(c)
			return c
	return null


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


# A waiter who can't deliver lets go of their plate, so another can take it.
func release_plate_claim(waiter: Waiter) -> void:
	for plate in expo_plates:
		if plate["taker"] == waiter:
			plate["taker"] = null


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
		if furniture[cell] in ["table", "chair", "decor"]:
			solid[cell] = furniture[cell]
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
		if furniture[spot] in ["table", "chair", "decor"]:
			tables[spot] = true
	for spot in _decor_of:   # rugs too
		tables[spot] = true
	var problem: String = _kitchen_fits(cell, kitchen_width, tables)
	if problem != "":
		build_message.emit(problem)
		return
	var solid: Dictionary = _layout_with_kitchen(cell, kitchen_width)
	if not _layout_works(solid, door_cell, cell, kitchen_width, false):
		build_message.emit("That would block someone's way!")
		return
	_rebuild_kitchen(cell, kitchen_width)
	layout_changed.emit()
	build_message.emit("Moved the kitchen.")


func kitchen_max_width() -> int:
	return HALL_KITCHEN_MAX_WIDTH if GameManager.in_hall() else KITCHEN_MAX_WIDTH


# Moving into the Grand Hall: an empty floor of the new size with a
# starter layout (a 6-wide kitchen with three Hearths, six tables and two
# long tables).
# Staff keep their jobs and find their new places.
func start_grand_hall(new_cols: int, new_rows: int) -> void:
	wash_all_tables()
	for cell in hearths:
		if is_instance_valid(hearths[cell]["cook"]):
			hearths[cell]["cook"].release_hearth()
	cols = new_cols
	rows = new_rows
	set_door("bottom", new_cols / 2)
	var layout: Array = [[5, 1, "kitchen"], [6, 1, "kitchen"], [7, 1, "kitchen"]]
	for y in [5, 9]:
		for x in [2, 6, 10]:
			layout.append([x, y, "table", "x"])
		layout.append([13, y - 1, "long_table", "x"])
	load_layout(layout, [5, 0, 6])
	_move_staff_aside()
	layout_changed.emit()


# One more square of width on the right; the pass moves to the new end.
func try_widen_kitchen() -> void:
	if GameManager.is_open or not get_tree().get_nodes_in_group("customers").is_empty():
		build_message.emit("Widen the kitchen after closing time.")
		return
	if kitchen_width >= kitchen_max_width():
		build_message.emit("The kitchen is as wide as it gets.")
		return
	var tables: Dictionary = {}
	for spot in furniture:
		if furniture[spot] in ["table", "chair", "decor"]:
			tables[spot] = true
	for spot in _decor_of:   # rugs too
		tables[spot] = true
	var problem: String = _kitchen_fits(kitchen_pos, kitchen_width + 1, tables)
	if problem != "":
		build_message.emit(problem.replace("doesn't fit there", "has no room to grow"))
		return
	var solid: Dictionary = _layout_with_kitchen(kitchen_pos, kitchen_width + 1)
	if not _layout_works(solid, door_cell, kitchen_pos, kitchen_width + 1, false):
		build_message.emit("That would block someone's way!")
		return
	if not GameManager.try_spend(KITCHEN_WIDEN_COST):
		build_message.emit("Not enough gold (%dg)." % KITCHEN_WIDEN_COST)
		return
	_rebuild_kitchen(kitchen_pos, kitchen_width + 1)
	layout_changed.emit()
	build_message.emit("The kitchen is now %d squares wide." % kitchen_width)


# Staff standing where the kitchen's new pieces go (between days, when
# moving or widening it) step onto the nearest free square instead.
func _move_staff_aside() -> void:
	for walker in get_tree().get_nodes_in_group("walkers"):
		var here: Vector2i = walker.current_cell()
		if here == NO_CELL or not furniture.has(here) or walker is Customer:
			continue
		var spot: Vector2i = nearest_open_cell(here)
		if spot != NO_CELL:
			walker.stop()
			walker.end_standby()
			walker.position = cell_center(spot)


# The closest square nobody's furniture is on (rings outward from `from`).
# Also used by walkers who find themselves standing in furniture.
func nearest_open_cell(from: Vector2i) -> Vector2i:
	for radius in range(1, maxi(cols, rows)):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var spot: Vector2i = from + Vector2i(dx, dy)
				if _in_bounds(spot) and not furniture.has(spot):
					return spot
	return NO_CELL


# Takes the kitchen's pieces off the floor and puts them back at a new
# position/width. Cooks let go of their Hearths and find them again.
func _rebuild_kitchen(pos: Vector2i, width: int) -> void:
	var slots: Array[int] = []
	for cell in hearths:
		slots.append(cell.x - kitchen_pos.x)
		if is_instance_valid(hearths[cell]["cook"]):
			hearths[cell]["cook"].release_hearth()
	for cell in furniture.keys():
		if not furniture[cell] in ["table", "chair", "decor"]:
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
	_move_staff_aside()


# Sets the kitchen from a save file. Saves from before the kitchen had
# Hearths anywhere, so a spot is found for it (see load_layout).
func set_kitchen(data) -> bool:
	if typeof(data) != TYPE_ARRAY or data.size() != 3:
		return false
	kitchen_pos = Vector2i(int(data[0]), int(data[1]))
	kitchen_width = clampi(int(data[2]), KITCHEN_START_WIDTH, kitchen_max_width())
	return _kitchen_fits(kitchen_pos, kitchen_width, {}) == ""


# The furniture as plain data for the save file: [[column, row, type], ...]
# (JSON can't store a Vector2i, but it can store a list of numbers.)
# Tables are saved once, at their anchor, with the way they run:
# [column, row, "table" or "long_table", "x" or "y"].
func get_layout() -> Array:
	var layout: Array = []
	for cell in furniture:
		if furniture[cell] in ["kitchen", "bar"]:   # the pass comes with the kitchen
			layout.append([cell.x, cell.y, furniture[cell]])
	for anchor in tables:
		var table: Dictionary = tables[anchor]
		layout.append([anchor.x, anchor.y, table["kind"], "x" if table["dir"] == Vector2i(1, 0) else "y"])
	return layout


# Replaces all furniture with a saved layout. Called before any staff
# or guests exist, so nobody needs a new route. `kitchen` is the saved
# kitchen ([x, y, width]) or null for saves from before the kitchen.
func load_layout(layout: Array, kitchen = null) -> void:
	for cell in _props.keys():
		_remove_prop(cell)
	furniture.clear()
	bars.clear()
	tables.clear()
	_table_of.clear()
	private_cells.clear()
	decor.clear()          # decorations are loaded separately (load_decor);
	_decor_of.clear()      # moving to the Grand Hall leaves them behind
	wall_decor.clear()
	table_owner.clear()
	hearths.clear()
	expo_plates.clear()
	_apply_size()
	var saved_hearths: Array[Vector2i] = []
	var saved_bars: Array[Vector2i] = []
	var old_tables: Dictionary = {}   # tables from saves before chairs: one square each
	var new_tables: Array = []        # [kind, anchor, dir]
	for entry in layout:
		# Skip anything that doesn't make sense rather than crash.
		if typeof(entry) != TYPE_ARRAY or entry.size() < 3:
			continue
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if not _in_bounds(cell) or cell == door_cell:
			continue
		if entry[2] == "kitchen":
			saved_hearths.append(cell)
		elif entry[2] == "bar":
			saved_bars.append(cell)
		elif entry[2] in ["table", "long_table"] and entry.size() >= 4:
			new_tables.append([entry[2], cell, Vector2i(1, 0) if entry[3] == "x" else Vector2i(0, 1)])
		elif entry[2] == "table":
			old_tables[cell] = true

	var known: bool = set_kitchen(kitchen) if kitchen != null else false
	if not known:
		_place_kitchen_for_old_save(saved_hearths.size(), old_tables)
	_place(expo_cell(), "expo")
	for t in new_tables:
		if _table_fits(t[0], t[1], t[2]):
			_place_table(t[0], t[1], t[2])
	# Saves from before chairs: each old one-square table becomes a table
	# with chairs, running whichever way fits; if neither does, it's sold.
	for cell in old_tables:
		var placed: bool = false
		for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
			if _table_fits("table", cell, dir) and _layout_works_with_table("table", cell, dir):
				_place_table("table", cell, dir)
				placed = true
				break
		if not placed:
			GameManager.refund(floori(GameManager.FURNITURE["table"]["cost"] / 2.0))
	for cell in saved_bars:
		if not _blocked(cell) and not in_kitchen(cell) and cell != expo_front():
			_place(cell, "bar")

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
	kitchen_width = clampi(hearth_count + 2, KITCHEN_START_WIDTH, kitchen_max_width())
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
	if build_type in ["table", "long_table"]:
		_try_build_table(cell)
		return
	if build_type == "decor":
		_try_place_decor(cell)
		return
	if build_type == "private":
		_try_paint_private(cell)
		return
	if _blocked(cell):
		build_message.emit("That square is taken.")
		return
	if build_type == "bar" and in_kitchen(cell):
		build_message.emit("The Bar goes in the dining room.")
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


# A table centred on the tapped square (a long table's second row goes
# beside it), running the way build_dir says.
func _try_build_table(anchor: Vector2i) -> void:
	var problem: String = _table_problem(build_type, anchor, build_dir)
	if problem != "":
		build_message.emit(problem)
		return
	if not _layout_works_with_table(build_type, anchor, build_dir):
		build_message.emit("That would block someone's way!")
		return
	var info: Dictionary = GameManager.FURNITURE[build_type]
	if not GameManager.try_spend(info["cost"]):
		build_message.emit("Not enough gold!")
		return
	_place_table(build_type, anchor, build_dir)
	layout_changed.emit()
	build_message.emit("Built a %s." % info["name"])


# Why a table can't go there, or "" if every square it needs is free.
func _table_problem(kind: String, anchor: Vector2i, dir: Vector2i) -> String:
	var foot: Dictionary = table_footprint(kind, anchor, dir)
	var in_use: Dictionary = _cells_in_use(null)
	for cell in foot["tops"] + foot["chairs"]:
		if not _in_bounds(cell):
			return "Not enough room for the %s there." % GameManager.FURNITURE[kind]["name"]
		if _blocked(cell):
			return "Something's in the way."
		if in_kitchen(cell):
			return "Tables can't go in the kitchen."
		if cell == expo_front():
			return "Keep the spot in front of the pass clear for waiters."
		if cell == door_cell:
			return "Keep the doorway clear!"
		if in_use.has(cell):
			return "Someone's in the way!"
	return ""


func _table_fits(kind: String, anchor: Vector2i, dir: Vector2i) -> bool:
	return _table_problem(kind, anchor, dir) == ""


# Would the tavern still work with this table added?
func _layout_works_with_table(kind: String, anchor: Vector2i, dir: Vector2i) -> bool:
	var solid: Dictionary = furniture.duplicate()
	var foot: Dictionary = table_footprint(kind, anchor, dir)
	for cell in foot["tops"]:
		solid[cell] = "table"
	for cell in foot["chairs"]:
		solid[cell] = "chair"
	return _layout_works(solid, door_cell, kitchen_pos, kitchen_width)


func _place_table(kind: String, anchor: Vector2i, dir: Vector2i) -> void:
	var foot: Dictionary = table_footprint(kind, anchor, dir)
	tables[anchor] = {"kind": kind, "dir": dir, "tops": foot["tops"], "chairs": foot["chairs"]}
	table_owner[anchor] = null
	for cell in foot["tops"]:
		furniture[cell] = "table"
		_table_of[cell] = anchor
		_set_solid(cell, true)
	# One prop draws the whole tabletop, standing at its middle for y-sorting.
	var middle := Vector2.ZERO
	for cell in foot["tops"]:
		middle += cell_center(cell)
	_props[anchor] = _new_prop(kind, anchor, middle / foot["tops"].size())
	for chair in foot["chairs"]:
		furniture[chair] = "chair"
		_table_of[chair] = anchor
		_set_solid(chair, true)
		var prop: FloorProp = _new_prop("chair", chair, cell_center(chair))
		prop.facing = top_for_chair(chair) - chair   # towards the table
		# A chair whose backrest is towards us goes in front of whoever sits
		# on it (it draws a little higher to make up for it), others behind.
		var lift: float = 2.0 if prop.facing.x + prop.facing.y < 0 else -2.0
		prop.position.y += lift
		prop.lift = lift
		_props[chair] = prop


func _remove_table(anchor: Vector2i) -> void:
	var table: Dictionary = tables[anchor]
	for cell in table["tops"] + table["chairs"]:
		furniture.erase(cell)
		_table_of.erase(cell)
		_remove_prop(cell)
		_set_solid(cell, false)
	tables.erase(anchor)
	table_owner.erase(anchor)
	table_dishes.erase(anchor)
	_bussers.erase(anchor)


func _place(cell: Vector2i, type: String) -> void:
	furniture[cell] = type
	_set_solid(cell, true)   # nobody can walk through it now
	if type == "kitchen":
		hearths[cell] = {"cook": null, "job": {}}
	elif type == "bar":
		bars[cell] = null
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
	if _decor_of.has(cell):
		var anchor: Vector2i = _decor_of[cell]
		var info: Dictionary = GameManager.DECOR[decor[anchor]["id"]]
		var back: int = floori(info["cost"] / 2.0)
		GameManager.refund(back)
		_remove_decor(anchor)
		layout_changed.emit()
		build_message.emit("Sold the %s for %dg." % [info["name"], back])
		return
	if not furniture.has(cell):
		return
	var type: String = furniture[cell]
	if type == "expo":
		build_message.emit("The pass is part of the kitchen. Use Kitchen to move it.")
		return
	if type in ["table", "chair"]:
		var anchor: Vector2i = _table_of[cell]
		if table_owner[anchor] != null:
			build_message.emit("Someone's sitting there!")
			return
		var kind: String = tables[anchor]["kind"]
		var back: int = floori(GameManager.FURNITURE[kind]["cost"] / 2.0)
		GameManager.refund(back)
		_remove_table(anchor)
		layout_changed.emit()
		build_message.emit("Sold for %dg." % back)
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
	hearths.erase(cell)
	if bars.has(cell):
		if is_instance_valid(bars[cell]):
			bars[cell].release_bar_job()
		bars.erase(cell)
	_remove_prop(cell)
	_set_solid(cell, false)
	layout_changed.emit()
	build_message.emit("Sold for %dg." % refund)


# ---------------------------------------------------------------------
# Decorations
# ---------------------------------------------------------------------
# Painting (or unpainting) a square of the Private Dining Room.
func _try_paint_private(cell: Vector2i) -> void:
	if not GameManager.in_hall():
		build_message.emit("A Private Dining Room needs the Grand Hall.")
		return
	if private_cells.has(cell):
		private_cells.erase(cell)
		GameManager.refund(PRIVATE_COST / 2)
		queue_redraw()
		layout_changed.emit()
		return
	if in_kitchen(cell) or cell == door_cell or cell == expo_front():
		build_message.emit("The private room goes in the dining room.")
		return
	if not GameManager.try_spend(PRIVATE_COST):
		build_message.emit("Not enough gold!")
		return
	private_cells[cell] = true
	queue_redraw()
	layout_changed.emit()


# Is this table in the private room (every tabletop and chair on it)?
func is_private_table(anchor: Vector2i) -> bool:
	if not tables.has(anchor) or private_cells.is_empty():
		return false
	for cell in tables[anchor]["tops"] + tables[anchor]["chairs"]:
		if not private_cells.has(cell):
			return false
	return true


# Squares nothing new can go on: furniture, decorations and rugs.
func _blocked(cell: Vector2i) -> bool:
	return furniture.has(cell) or _decor_of.has(cell)


func _decor_cells(id: String, anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor]
	if GameManager.DECOR[id].get("size", 1) == 2:
		cells.append_array([anchor + Vector2i(1, 0), anchor + Vector2i(0, 1), anchor + Vector2i(1, 1)])
	return cells


func _try_place_decor(anchor: Vector2i) -> void:
	var id: String = decor_choice
	var info: Dictionary = GameManager.DECOR[id]
	if not GameManager.decor_available(id):
		build_message.emit("The %s isn't available yet." % info["name"])
		return
	var in_use: Dictionary = _cells_in_use(null)
	var solid: Dictionary = furniture.duplicate()
	for cell in _decor_cells(id, anchor):
		if not _in_bounds(cell):
			build_message.emit("Not enough room there.")
			return
		if _blocked(cell) or in_kitchen(cell) or cell == expo_front() or cell == door_cell:
			build_message.emit("Something's in the way.")
			return
		if in_use.has(cell) and not info.get("walk", false):
			build_message.emit("Someone's in the way!")
			return
		if not info.get("walk", false):
			solid[cell] = "decor"
	if not _layout_works(solid, door_cell, kitchen_pos, kitchen_width):
		build_message.emit("That would block someone's way!")
		return
	if not GameManager.try_spend(info["cost"]):
		build_message.emit("Not enough gold!")
		return
	# Rotate turns decorations too: the second direction mirrors the piece.
	_place_decor(id, anchor, build_dir == Vector2i(0, 1))
	layout_changed.emit()
	build_message.emit("Placed the %s." % info["name"])


func _place_decor(id: String, anchor: Vector2i, flip: bool = false) -> void:
	var cells: Array[Vector2i] = _decor_cells(id, anchor)
	decor[anchor] = {"id": id, "cells": cells, "flip": flip}
	var middle := Vector2.ZERO
	for cell in cells:
		_decor_of[cell] = anchor
		middle += cell_center(cell)
		if not GameManager.DECOR[id].get("walk", false):
			furniture[cell] = "decor"
			_set_solid(cell, true)
	# Rugs lie flat and are drawn with the floor; everything else is a prop.
	if not GameManager.DECOR[id].get("walk", false):
		var prop: FloorProp = _new_prop("decor", anchor, middle / cells.size())
		_props[anchor] = prop
	queue_redraw()


func _remove_decor(anchor: Vector2i) -> void:
	for cell in decor[anchor]["cells"]:
		_decor_of.erase(cell)
		if furniture.get(cell, "") == "decor":
			furniture.erase(cell)
			_set_solid(cell, false)
	_remove_prop(anchor)
	decor.erase(anchor)
	queue_redraw()


# The stretch of back wall at `local_pos` ("top:x" or "left:y"), or "".
func _wall_at(local_pos: Vector2) -> String:
	var up := Vector2(0, -WALL_HEIGHT)
	for x in cols:
		var a: Vector2 = iso(Vector2(x, 0))
		var b: Vector2 = iso(Vector2(x + 1, 0))
		if Geometry2D.is_point_in_polygon(local_pos, PackedVector2Array([a, b, b + up, a + up])):
			return "top:%d" % x
	for y in rows:
		var a: Vector2 = iso(Vector2(0, y))
		var b: Vector2 = iso(Vector2(0, y + 1))
		if Geometry2D.is_point_in_polygon(local_pos, PackedVector2Array([a, b, b + up, a + up])):
			return "left:%d" % y
	return ""


# Stretches of wall that already have something: the door, windows and
# (in the Grand Hall) banners.
func _wall_taken_by_building(side: String, index: int) -> bool:
	if door_side == side and door_index == index:
		return true
	return index % 3 == 1 or (GameManager.in_hall() and index % 3 == 2)


func _try_hang(wall: String) -> void:
	var id: String = decor_choice
	var info: Dictionary = GameManager.DECOR[id]
	if wall == "":
		build_message.emit("Tap a stretch of the back wall.")
		return
	var parts: PackedStringArray = wall.split(":")
	if _wall_taken_by_building(parts[0], int(parts[1])):
		build_message.emit("There's a window or door there. Try another stretch of wall.")
		return
	if wall_decor.has(wall):
		build_message.emit("Something already hangs there.")
		return
	if not GameManager.has_trophy(id):
		build_message.emit("Earn the %s first: %s." % [info["name"], info["task"]])
		return
	# Each trophy is one of a kind: hanging it again moves it.
	for spot in wall_decor.keys():
		if wall_decor[spot] == id:
			wall_decor.erase(spot)
	wall_decor[wall] = id
	queue_redraw()
	layout_changed.emit()
	build_message.emit("Hung the %s." % info["name"])


func is_hung(id: String) -> bool:
	return wall_decor.values().has(id)


# Decorations as plain data for the save file.
func get_decor() -> Dictionary:
	var floor_pieces: Array = []
	for anchor in decor:
		floor_pieces.append([anchor.x, anchor.y, decor[anchor]["id"], 1 if decor[anchor]["flip"] else 0])
	var wall_pieces: Array = []
	for wall in wall_decor:
		var parts: PackedStringArray = wall.split(":")
		wall_pieces.append([parts[0], int(parts[1]), wall_decor[wall]])
	var private: Array = private_cells.keys().map(func(c): return [c.x, c.y])
	return {"floor": floor_pieces, "wall": wall_pieces, "private": private}


# Puts saved decorations back (after load_layout). Anything that no
# longer fits is skipped.
func load_decor(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	for entry in data.get("floor", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 3 or not GameManager.DECOR.has(entry[2]):
			continue
		var anchor := Vector2i(int(entry[0]), int(entry[1]))
		var fits: bool = true
		for cell in _decor_cells(entry[2], anchor):
			if not _in_bounds(cell) or _blocked(cell) or in_kitchen(cell) or cell == door_cell or cell == expo_front():
				fits = false
		if fits:
			_place_decor(entry[2], anchor, entry.size() > 3 and int(entry[3]) == 1)
	for entry in data.get("private", []):
		if typeof(entry) == TYPE_ARRAY and entry.size() == 2:
			var cell := Vector2i(int(entry[0]), int(entry[1]))
			if _in_bounds(cell) and not in_kitchen(cell):
				private_cells[cell] = true
	for entry in data.get("wall", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() != 3 or not GameManager.DECOR.has(entry[2]):
			continue
		var limit: int = cols if entry[0] == "top" else rows
		if entry[0] in ["top", "left"] and int(entry[1]) < limit and not _wall_taken_by_building(entry[0], int(entry[1])):
			wall_decor["%s:%d" % [entry[0], int(entry[1])]] = entry[2]
	queue_redraw()


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
	if _blocked(cell):
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
	# Anything hanging where the new doorway is comes down (and can be hung again).
	wall_decor.erase("%s:%d" % [side, door_index])
	layout_changed.emit()
	build_message.emit("Moved the door.")


# Would the tavern still work with furniture on new_cell? (Tables use
# _layout_works_with_table.)
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
# count_staff = false: staff will step aside (only guests are checked).
func _layout_works(solid: Dictionary, door: Vector2i, k_pos: Vector2i, k_width: int, count_staff: bool = true) -> bool:
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
		if solid[piece] == "decor":
			continue   # decorations are only looked at, nobody needs to reach them
		var usable: bool = false
		for side in SIDES:
			if reachable.has(piece + side):
				usable = true
				break
		if not usable:
			return false

	for person_cell in _cells_in_use(null, count_staff):
		# Guests sitting on a chair are fine: they'll step off it.
		if not reachable.has(person_cell) and solid.get(person_cell, "") != "chair":
			return false

	for piece in solid:
		var needs: Array = []
		match solid[piece]:
			"kitchen": needs = [piece + Vector2i(0, -1)]
			"expo": needs = [piece + Vector2i(0, -1), piece + Vector2i(0, 1)]
			"bar": needs = [piece + Vector2i(0, -1)]   # where the bartender stands
		for spot in needs:
			if not reachable.has(spot):
				return false
	# Kitchen geometry: the aisle row must exist above the line.
	return k_pos.y >= 0 and k_pos.y + KITCHEN_DEPTH <= rows and k_width >= KITCHEN_START_WIDTH


# Every square someone is standing on or walking to, as dictionary keys.
func _cells_in_use(ignore: Node, count_staff: bool = true) -> Dictionary:
	var cells: Dictionary = {}
	for walker in get_tree().get_nodes_in_group("walkers"):
		if walker == ignore or (not count_staff and not walker is Customer):
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


# The next order for a Hearth. While a Bar is open, drinks are left for
# the bartender.
func _pop_next_order() -> Customer:
	var skip_drinks: bool = bar_open()
	for c in GameManager.order_queue.duplicate():
		if not is_instance_valid(c) or c.state != Customer.State.WAITING_FOR_FOOD:
			GameManager.order_queue.erase(c)
			continue
		if skip_drinks and c.order.get("id", "") in DRINKS:
			continue
		GameManager.order_queue.erase(c)
		return c
	return null


# ---------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------
# Colors for each location: the country tavern (wood and plaster) and the
# Grand Hall (marble, stone, crimson and gold).
const THEMES: Dictionary = {
	"tavern": {
		"floor_a": Color8(237, 201, 138), "floor_b": Color8(226, 185, 118), "floor_line": Color8(205, 160, 98),
		"plaster_top": Color8(240, 226, 194),    # back wall along the top edge
		"plaster_left": Color8(224, 208, 174),   # back wall along the left edge (shadier)
		"panel_top": Color8(152, 100, 60), "panel_left": Color8(134, 87, 52), "trim": Color8(105, 66, 38),
		"kitchen_a": Color8(176, 178, 180), "kitchen_b": Color8(160, 163, 166),   # stone tiles
		"front_bottom": Color8(178, 118, 70), "front_right": Color8(156, 102, 60), "front_rail": Color8(210, 160, 105),
	},
	"grand_hall": {
		"floor_a": Color8(232, 228, 218), "floor_b": Color8(196, 190, 180), "floor_line": Color8(170, 162, 150),
		"plaster_top": Color8(205, 196, 180), "plaster_left": Color8(186, 176, 160),
		"panel_top": Color8(140, 38, 44), "panel_left": Color8(118, 32, 38), "trim": Color8(196, 156, 64),
		"kitchen_a": Color8(132, 136, 142), "kitchen_b": Color8(116, 120, 126),   # slate tiles
		"front_bottom": Color8(176, 168, 152), "front_right": Color8(152, 144, 130), "front_rail": Color8(214, 176, 82),
	},
}


func _c(key: String) -> Color:
	return THEMES[GameManager.location][key]


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
				draw_colored_polygon(tile, _c("kitchen_a") if even else _c("kitchen_b"))
			else:
				draw_colored_polygon(tile, _c("floor_a") if even else _c("floor_b"))
			draw_polyline(tile + PackedVector2Array([tile[0]]), _c("floor_line"), 1.0)

	# The private dining room: crimson carpet, with a gold rope along its
	# edges.
	for cell in private_cells:
		var tile: PackedVector2Array = _diamond(cell)
		draw_colored_polygon(tile, Color8(150, 35, 45) if (cell.x + cell.y) % 2 == 0 else Color8(138, 30, 40))
		for i in 4:
			var side: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][i]
			if not private_cells.has(cell + side):
				draw_line(tile[i], tile[(i + 1) % 4], Color8(222, 182, 70), 3.0)

	# Rugs lie on the floor, under everyone.
	for anchor in decor:
		if GameManager.DECOR[decor[anchor]["id"]].get("walk", false):
			_draw_decor_art(self, decor[anchor]["id"], iso(Vector2(anchor) + Vector2(0.5, 0.5)), decor[anchor]["flip"])

	# Doormat on the doorway square.
	var mat: PackedVector2Array = _diamond(door_cell)
	var middle: Vector2 = iso(Vector2(door_cell) + Vector2(0.5, 0.5))
	for i in mat.size():
		mat[i] = middle + (mat[i] - middle) * 0.7
	draw_colored_polygon(mat, Color8(170, 60, 50))

	# Back walls: the top edge (upper right on screen) and the left edge
	# (upper left). Each wall piece is a floor edge pushed straight up.
	for x in cols:
		_draw_back_wall(iso(Vector2(x, 0)), iso(Vector2(x + 1, 0)), _c("plaster_top"), _c("panel_top"),
				door_side == "top" and door_index == x, x % 3 == 1, GameManager.in_hall() and x % 3 == 2)
	for y in rows:
		_draw_back_wall(iso(Vector2(0, y)), iso(Vector2(0, y + 1)), _c("plaster_left"), _c("panel_left"),
				door_side == "left" and door_index == y, y % 3 == 1, GameManager.in_hall() and y % 3 == 2)

	# Decorations hanging on the back walls. The art is drawn for the top
	# wall; mirrored, it fits the left wall.
	for wall in wall_decor:
		var parts: PackedStringArray = wall.split(":")
		var i: int = int(parts[1])
		if parts[0] == "top":
			_draw_decor_art(self, wall_decor[wall], iso(Vector2(i + 0.5, 0.5)))
		else:
			_draw_decor_art(self, wall_decor[wall], iso(Vector2(0.5, i + 0.5)), true)

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


func _draw_back_wall(from: Vector2, to: Vector2, plaster: Color, panel: Color, door: bool, window: bool, banner: bool = false) -> void:
	var up := Vector2(0, -WALL_HEIGHT)
	draw_colored_polygon(PackedVector2Array([from, to, to + up, from + up]), plaster)
	var panel_up: Vector2 = up * 0.38                       # wood panelling along the bottom
	draw_colored_polygon(PackedVector2Array([from, to, to + panel_up, from + panel_up]), panel)
	draw_line(from + up, to + up, _c("trim"), 4.0)                # top trim
	draw_line(from + panel_up, to + panel_up, _c("trim"), 2.0)
	var along: Vector2 = to - from
	if door:
		# A wooden door in the wall.
		var a: Vector2 = from + along * 0.2
		var b: Vector2 = from + along * 0.8
		var door_up: Vector2 = up * 0.78
		draw_colored_polygon(PackedVector2Array([a, b, b + door_up, a + door_up]), Color8(120, 74, 40))
		draw_polyline(PackedVector2Array([a, a + door_up, b + door_up, b]), _c("trim"), 2.0)
		draw_circle(a + along * 0.5 + door_up * 0.45, 2.0, Color8(230, 190, 80))
	elif window:
		var a: Vector2 = from + along * 0.22 + up * 0.5
		var b: Vector2 = from + along * 0.78 + up * 0.5
		var win_up: Vector2 = up * 0.36
		# The sky outside: daylight blue, deepening to night blue (the tavern
		# itself stays lit; see lighting.gd).
		var night: float = Lighting.night_at(GameManager.OPEN_HOUR + GameManager.minutes_since_open / 60.0) \
				if GameManager.is_open or _candles_lit() else 0.0
		draw_colored_polygon(PackedVector2Array([a, b, b + win_up, a + win_up]), Color8(175, 214, 236).lerp(Color8(40, 50, 95), night))
		draw_polyline(PackedVector2Array([a, b, b + win_up, a + win_up, a]), _c("trim"), 2.0)
		draw_line((a + b) / 2.0, (a + b) / 2.0 + win_up, _c("trim"), 2.0)
	elif banner:
		# A crimson banner with a gold border, hanging from the top trim.
		var a: Vector2 = from + along * 0.3 + up * 0.95
		var b: Vector2 = from + along * 0.7 + up * 0.95
		var drop: Vector2 = -up * 0.5
		var tip: Vector2 = (a + b) / 2.0 + drop * 0.8   # the notch at the bottom
		var cloth := PackedVector2Array([a, b, b + drop, tip, a + drop])
		draw_colored_polygon(cloth, Color8(150, 30, 40))
		draw_polyline(cloth + PackedVector2Array([a]), _c("trim"), 2.0)
		draw_circle((a + b) / 2.0 + drop * 0.4, 4.0, _c("trim"))   # a gold emblem


# Candles come out on the tables in the evening.
func _candles_lit() -> bool:
	return GameManager.OPEN_HOUR + GameManager.minutes_since_open / 60.0 >= Lighting.LIGHT_FROM \
			and (GameManager.is_open or not get_tree().get_nodes_in_group("customers").is_empty())


# Draws one FloorProp, in the prop's own space (its position is 0, 0).
func draw_prop(prop: FloorProp) -> void:
	if prop.kind == "kitchen" and not hearths.has(prop.cell):
		return   # just removed; it disappears at the end of the frame
	if prop.kind in ["table", "long_table"] and not tables.has(prop.cell):
		return
	match prop.kind:
		"table", "long_table": _draw_table(prop)
		"chair": _draw_chair(prop)
		"decor":
			if decor.has(prop.cell):
				_draw_decor_art(prop, decor[prop.cell]["id"], Vector2.ZERO, decor[prop.cell]["flip"])
		"kitchen": _draw_hearth(prop)
		"expo": _draw_expo(prop)
		"bar": _draw_art(prop, BAR_ART)
		"wall": _draw_front_wall(prop)


# Pixel-art furniture (drawn by tools/sprites/make_furniture.py). Each
# frame is 64 x 72 with the middle of its square at (32, 58), drawn at 2x
# like the characters.
const TABLE_ART: Texture2D = preload("res://assets/sprites/furniture/table.png")
const HEARTH_ART: Texture2D = preload("res://assets/sprites/furniture/hearth.png")
const PASS_ART: Texture2D = preload("res://assets/sprites/furniture/pass.png")
const BAR_ART: Texture2D = preload("res://assets/sprites/furniture/bar.png")
# The long table is drawn over 2 squares on a taller frame (64 x 80,
# middle at (32, 62)). Chairs: "back" has its backrest away from us,
# "front" towards us.
const LONG_TABLE_ART: Texture2D = preload("res://assets/sprites/furniture/long_table.png")
const CHAIR_BACK_ART: Texture2D = preload("res://assets/sprites/furniture/chair_back.png")
const CHAIR_FRONT_ART: Texture2D = preload("res://assets/sprites/furniture/chair_front.png")
const ART_FRAME := Vector2(64, 72)
const ART_ANCHOR := Vector2(32, 58)
const LONG_FRAME := Vector2(64, 80)
const LONG_ANCHOR := Vector2(32, 62)
const ART_SCALE: float = 2.0


# mirror = true flips it left to right, which in this view turns
# something running along x into the same thing running along y.
func _draw_art(prop: FloorProp, art: Texture2D, frame: int = 0, mirror: bool = false,
		size: Vector2 = ART_FRAME, anchor: Vector2 = ART_ANCHOR) -> void:
	var source := Rect2(Vector2(size.x * frame, 0), size)
	prop.draw_set_transform(Vector2(0, -prop.lift), 0.0, Vector2(-1, 1) if mirror else Vector2.ONE)
	prop.draw_texture_rect_region(art, Rect2(-anchor * ART_SCALE, size * ART_SCALE), source)
	prop.draw_set_transform(Vector2.ZERO)


# Decorations (tools/sprites/make_decor.py and make_trophies.py): one
# strip of frames each, 64 x 72 per frame; the 2 x 2 dragon is 112 x 128
# with its footprint's middle at (56, 100).
const DECOR_ART: Dictionary = {
	"fern": preload("res://assets/sprites/decor/fern.png"),
	"barrels": preload("res://assets/sprites/decor/barrels.png"),
	"rug": preload("res://assets/sprites/decor/rug.png"),
	"armour": preload("res://assets/sprites/decor/armour.png"),
	"bookshelf": preload("res://assets/sprites/decor/bookshelf.png"),
	"fireplace": preload("res://assets/sprites/decor/fireplace.png"),
	"dragon": preload("res://assets/sprites/decor/dragon.png"),
	"painting": preload("res://assets/sprites/decor/painting.png"),
	"shield": preload("res://assets/sprites/decor/shield.png"),
	"antlers": preload("res://assets/sprites/decor/antlers.png"),
	"lantern": preload("res://assets/sprites/decor/lantern.png"),
	"wreath": preload("res://assets/sprites/decor/wreath.png"),
	"glowcap": preload("res://assets/sprites/decor/glowcap.png"),
	"wings": preload("res://assets/sprites/decor/wings.png"),
	"mirror": preload("res://assets/sprites/decor/mirror.png"),
	"crown": preload("res://assets/sprites/decor/crown.png"),
	"wyvern": preload("res://assets/sprites/decor/wyvern.png"),
	"centaur": preload("res://assets/sprites/decor/centaur.png"),
	"griffon": preload("res://assets/sprites/decor/griffon.png"),
	"unicorn": preload("res://assets/sprites/decor/unicorn.png"),
	"minotaur": preload("res://assets/sprites/decor/minotaur.png"),
	"kraken": preload("res://assets/sprites/decor/kraken.png"),
}
const BIG_FRAME := Vector2(112, 128)
const BIG_ANCHOR := Vector2(56, 100)


# Draws decoration `id` on `canvas` with its square's middle at `at`.
# Animated pieces step through their frames on their own.
func _draw_decor_art(canvas: CanvasItem, id: String, at: Vector2, mirror: bool = false) -> void:
	var info: Dictionary = GameManager.DECOR[id]
	var big: bool = info.get("size", 1) == 2
	var size: Vector2 = BIG_FRAME if big else ART_FRAME
	var anchor: Vector2 = BIG_ANCHOR if big else ART_ANCHOR
	var frame: int = (Time.get_ticks_msec() / 250) % info.get("frames", 1)
	var source := Rect2(Vector2(size.x * frame, 0), size)
	canvas.draw_set_transform(at, 0.0, Vector2(-1, 1) if mirror else Vector2.ONE)
	canvas.draw_texture_rect_region(DECOR_ART[id], Rect2(-anchor * ART_SCALE, size * ART_SCALE), source)
	canvas.draw_set_transform(Vector2.ZERO)


# A picture of a decoration's first frame, for the Decor list: just the
# part of the frame the piece is drawn in, so it shows up big enough.
func decor_icon(id: String) -> AtlasTexture:
	var big: bool = GameManager.DECOR[id].get("size", 1) == 2
	var icon := AtlasTexture.new()
	icon.atlas = DECOR_ART[id]
	icon.region = Rect2(Vector2.ZERO, BIG_FRAME) if big else Rect2(10, 8, 44, 56)
	return icon


const TABLE_TOP: float = 26.0   # how high the tabletop is, in world pixels


func _draw_table(prop: FloorProp) -> void:
	var table: Dictionary = tables[prop.cell]
	var along_y: bool = table["dir"] == Vector2i(0, 1)
	if table["kind"] == "long_table":
		_draw_art(prop, LONG_TABLE_ART, 0, along_y, LONG_FRAME, LONG_ANCHOR)
	else:
		_draw_art(prop, TABLE_ART, 0, along_y)
	if _candles_lit():   # a candle in the middle of the table
		var middle := Vector2(0, -TABLE_TOP - 2)
		prop.draw_rect(Rect2(middle + Vector2(-2, -9), Vector2(4, 9)), Color8(240, 230, 200))
		prop.draw_rect(Rect2(middle + Vector2(-1, -13), Vector2(2, 4)), Color8(255, 200, 80))
	# The table stays bare until food arrives: each guest's dish sits in
	# front of their chair. Empty plates stay until a Waiter clears them.
	var plates: Dictionary = table_dishes.get(prop.cell, {})
	var chairs: Array = table["chairs"]
	for seat in plates:
		var top: Vector2 = cell_center(table["tops"][seat / 2])
		var toward_chair: Vector2 = (cell_center(chairs[seat]) - top) * 0.3
		var dish: String = plates[seat]["dish"]
		if plates[seat]["done"]:
			dish = dish + "_empty" if FOOD_ART.has(dish + "_empty") else "dirty"
		draw_dish(prop, top - prop.position + toward_chair + Vector2(0, -TABLE_TOP), dish)


func _draw_chair(prop: FloorProp) -> void:
	if not furniture.has(prop.cell):
		return
	# Facing +x or +y, the backrest is away from us; facing -x or -y it's
	# towards us. Facing along y is the x picture mirrored.
	var art: Texture2D = CHAIR_BACK_ART if prop.facing.x + prop.facing.y > 0 else CHAIR_FRONT_ART
	_draw_art(prop, art, 0, prop.facing.y != 0)


# Dishes (tools/sprites/make_food.py): one 36 x 28 picture each, the
# middle of the plate at (18, 18). They're drawn at 1x, finer than the
# 2x furniture, so the food can show some detail. "dirty" is a cleared-
# off plate; "<drink>_empty" what a finished drink leaves.
const FOOD_ART: Dictionary = {
	"ale": preload("res://assets/sprites/food/ale.png"),
	"stew": preload("res://assets/sprites/food/stew.png"),
	"mead": preload("res://assets/sprites/food/mead.png"),
	"boar": preload("res://assets/sprites/food/boar.png"),
	"cheese": preload("res://assets/sprites/food/cheese.png"),
	"wings": preload("res://assets/sprites/food/wings.png"),
	"wine": preload("res://assets/sprites/food/wine.png"),
	"phoenix": preload("res://assets/sprites/food/phoenix.png"),
	"feast": preload("res://assets/sprites/food/feast.png"),
	"plate": preload("res://assets/sprites/food/plate.png"),
	"dirty": preload("res://assets/sprites/food/dirty.png"),
	"ale_empty": preload("res://assets/sprites/food/ale_empty.png"),
	"mead_empty": preload("res://assets/sprites/food/mead_empty.png"),
	"wine_empty": preload("res://assets/sprites/food/wine_empty.png"),
}
const FOOD_MIDDLE := Vector2(18, 18)


# Draws a dish with the middle of its plate at `at`. Also used for the
# pass, the waiters' trays and the cooks' hands (smaller `size`).
func draw_dish(canvas: CanvasItem, at: Vector2, dish: String, size: float = 1.0) -> void:
	var art: Texture2D = FOOD_ART.get(dish, FOOD_ART["plate"])
	canvas.draw_texture_rect(art, Rect2(at - FOOD_MIDDLE * size, art.get_size() * size), false)


func _draw_hearth(prop: FloorProp) -> void:
	var font: Font = ThemeDB.fallback_font
	var h: Dictionary = hearths[prop.cell]
	var cooking: bool = not h["job"].is_empty()
	# Frame 0 is the idle glow; while cooking, the fire cycles frames 1-3.
	var frame: int = 1 + (Time.get_ticks_msec() / 140) % 3 if cooking else 0
	_draw_art(prop, HEARTH_ART, frame)
	var top := Vector2(0, -38)   # just above the stew pot
	if cooking:
		var job: Dictionary = h["job"]
		var done: float = 1.0 - job["time_left"] / job["total"]
		var bar := Rect2(top + Vector2(-24, -30), Vector2(48, 7))
		prop.draw_rect(bar, Color(0.1, 0.1, 0.1))
		prop.draw_rect(Rect2(bar.position, Vector2(bar.size.x * done, bar.size.y)), Color(1.0, 0.75, 0.2))
	if not is_instance_valid(h["cook"]):
		prop.draw_string(font, top + Vector2(-40, -26), "No cook",
				HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color(1.0, 0.75, 0.75))


# The pass: a serving hatch with the waiting plates on its counter.
func _draw_expo(prop: FloorProp) -> void:
	_draw_art(prop, PASS_ART)
	for i in expo_plates.size():
		var guest = expo_plates[i]["guest"]
		var dish: String = guest.order.get("id", "plate") if is_instance_valid(guest) else "plate"
		draw_dish(prop, Vector2(-16 + i * 16, -28 + (i % 2) * 5), dish)


func _draw_front_wall(prop: FloorProp) -> void:
	# The prop sits at its square's bottom corner. The bottom edge runs to
	# the square's left corner, the right edge to its right corner.
	var up := Vector2(0, -LOW_WALL_HEIGHT)
	var corners := {"bottom": Vector2(-TILE_W / 2.0, -TILE_H / 2.0), "right": Vector2(TILE_W / 2.0, -TILE_H / 2.0)}
	for edge in prop.edges:
		var far: Vector2 = corners[edge]
		var face: Color = _c("front_bottom") if edge == "bottom" else _c("front_right")
		prop.draw_colored_polygon(PackedVector2Array([far, Vector2.ZERO, up, far + up]), face)
		prop.draw_line(far + up, up, _c("front_rail"), 3.0)   # the lighter top rail
