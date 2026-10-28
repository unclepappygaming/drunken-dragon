# =====================================================================
# walker.gd  —  shared walking code for everyone who moves around.
#
# Customer, Cook and Waiter all say "extends Walker". That's
# INHERITANCE: each of them starts with everything in this file, then
# adds its own job on top. Fix walking here and all three get the fix.
#
# Walking uses the grid's pathfinder, so nobody walks through furniture.
# If the player builds or sells something while someone is walking,
# they plan a new route (see _on_layout_changed).
# =====================================================================
class_name Walker
extends Node2D

var speed: float = 170.0        # pixels per second; subclasses change it
var grid: TavernGrid

# The grid square we're heading to (or standing on, once we've arrived).
# The grid won't let the player build on it while we need it.
var destination: Vector2i = TavernGrid.NO_CELL

# Points still to walk to, in Main's space. Empty = standing still.
var _path: Array[Vector2] = []
var _leaving_by_door: bool = false
# Set when walking to a spot outside the floor (the waiting line), where
# there's no furniture and so no pathfinding.
var _outside_target: Vector2
var _going_outside: bool = false
# True when no route exists right now. We try again on the next layout change.
var _stuck: bool = false


# Subclasses call this from their own setup().
func _setup_walker(tavern_grid: TavernGrid, start_pos: Vector2) -> void:
	grid = tavern_grid
	position = start_pos
	# The grid looks through this group to see which squares people need.
	add_to_group("walkers")
	grid.layout_changed.connect(_on_layout_changed)


# Walk to a square inside the tavern.
func go_to_cell(cell: Vector2i) -> void:
	destination = cell
	_leaving_by_door = false
	_going_outside = false
	_plan_route()


# Walk to a spot outside the tavern, like a place in the waiting line.
func go_to_outside_spot(point: Vector2) -> void:
	destination = TavernGrid.NO_CELL
	_leaving_by_door = false
	_going_outside = true
	_outside_target = point
	_plan_route()


# Walk out through the front door.
func go_out_door() -> void:
	destination = TavernGrid.NO_CELL
	_leaving_by_door = true
	_going_outside = false
	_plan_route()


# Stop right here (used when a job is cancelled halfway).
func stop() -> void:
	_path.clear()
	destination = TavernGrid.NO_CELL
	_stuck = false


# The square we're on now, or NO_CELL if we're outside the door.
func current_cell() -> Vector2i:
	return grid.cell_at_world(position)


# Moves a step along the route. Returns true once we've arrived.
func _walk(delta: float) -> bool:
	if _stuck:
		return false
	var step: float = speed * delta
	# A loop, so a fast step can pass a corner and keep going.
	while not _path.is_empty() and step > 0.0:
		var next_point: Vector2 = _path[0]
		var distance: float = position.distance_to(next_point)
		if distance <= step:
			position = next_point
			step -= distance
			_path.pop_front()
		else:
			position = position.move_toward(next_point, step)
			step = 0.0
	return _path.is_empty()


func _plan_route() -> void:
	_path.clear()
	_stuck = false
	if _going_outside:
		_path.append(_outside_target)
		return
	var start: Vector2i = current_cell()
	if start == TavernGrid.NO_CELL:
		# Outside: step in front of the door first, so we don't walk
		# through the wall, then come in through the door.
		_path.append(grid.door_position())
		start = TavernGrid.DOOR_CELL
	var goal: Vector2i = TavernGrid.DOOR_CELL if _leaving_by_door else destination
	if goal == TavernGrid.NO_CELL:
		return

	# find_path gives a list of squares; we walk to the middle of each.
	var cells: Array[Vector2i] = grid.find_path(start, goal)
	if cells.is_empty():
		_stuck = true
		return
	for cell in cells:
		_path.append(grid.cell_center(cell))
	if _leaving_by_door:
		_path.append(grid.door_position())


func _on_layout_changed() -> void:
	# Only people who are on the move need a new route.
	if not _path.is_empty() or _stuck:
		_plan_route()
