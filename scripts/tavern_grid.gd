# =====================================================================
# tavern_grid.gd  —  the tavern floor. Attached to the TavernGrid node.
#
# The floor is an 8 x 10 grid of squares. Each square can hold one piece
# of furniture. This script:
#   * draws the floor, walls, door and furniture
#   * handles taps to build/remove furniture while in build mode
#   * tracks which tables are taken
#   * runs the Hearths: each one cooks one order at a time
# =====================================================================
class_name TavernGrid
extends Node2D

# Fired when building fails or succeeds, so the HUD can show a message.
signal build_message(text: String)

const COLS: int = 8
const ROWS: int = 10
const CELL_SIZE: int = 80
const NO_CELL: Vector2i = Vector2i(-1, -1)   # "nothing found" marker

# "" = not building. Otherwise "table", "kitchen" or "remove".
var build_type: String = ""

# Vector2i(column, row) -> furniture ID ("table" / "kitchen")
var furniture: Dictionary = {}
# table cell -> the Customer sitting there, or null if free
var table_owner: Dictionary = {}
# hearth cell -> {} when idle, or {"customer", "time_left", "total"}
var kitchen_jobs: Dictionary = {}


func _ready() -> void:
	# A free starter layout so Day 1 works right away.
	_place(Vector2i(1, 2), "table")
	_place(Vector2i(4, 2), "table")
	_place(Vector2i(6, 6), "kitchen")


# _unhandled_input gets taps that the HUD buttons didn't already use.
# Godot turns phone touches into mouse clicks by default, so checking
# for a left mouse click works on both PC and phone.
func _unhandled_input(event: InputEvent) -> void:
	if build_type == "":
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = _cell_at(to_local(event.position))
		if cell != NO_CELL:
			_try_build(cell)
			get_viewport().set_input_as_handled()   # nobody else needs this tap


func _process(delta: float) -> void:
	# .keys() gives a copy of the key list, so it's safe to change the
	# dictionary's values while we loop.
	for cell in kitchen_jobs.keys():
		var job: Dictionary = kitchen_jobs[cell]
		if job.is_empty():
			# Idle Hearth: grab the next waiting order, if any.
			var next: Customer = _pop_next_order()
			if next != null:
				var cook_time: float = next.order["cook_time"]
				kitchen_jobs[cell] = {"customer": next, "time_left": cook_time, "total": cook_time}
		else:
			job["time_left"] -= delta
			if job["time_left"] <= 0.0:
				var guest = job["customer"]
				# is_instance_valid: the guest may have stormed out and been
				# deleted while we cooked. Touching a deleted node crashes.
				if is_instance_valid(guest):
					guest.serve_food()
				kitchen_jobs[cell] = {}
	queue_redraw()


# ---------------------------------------------------------------------
# Helpers that main.gd uses. Positions are returned in Main's space
# (we add our own `position` because the grid is offset on screen).
# ---------------------------------------------------------------------
func cell_center(cell: Vector2i) -> Vector2:
	return position + Vector2(cell) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) / 2.0


func door_position() -> Vector2:
	return position + Vector2(COLS * CELL_SIZE / 2.0, ROWS * CELL_SIZE + 30)


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


# ---------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------
func _try_build(cell: Vector2i) -> void:
	if build_type == "remove":
		_try_remove(cell)
		return
	if furniture.has(cell):
		build_message.emit("That square is taken.")
		return
	var info: Dictionary = GameManager.FURNITURE[build_type]
	if not GameManager.try_spend(info["cost"]):
		build_message.emit("Not enough gold!")
		return
	_place(cell, build_type)
	build_message.emit("Built a %s." % info["name"])


func _place(cell: Vector2i, type: String) -> void:
	furniture[cell] = type
	if type == "table":
		table_owner[cell] = null
	elif type == "kitchen":
		kitchen_jobs[cell] = {}


func _try_remove(cell: Vector2i) -> void:
	if not furniture.has(cell):
		return
	var type: String = furniture[cell]
	if type == "table" and table_owner[cell] != null:
		build_message.emit("Someone's sitting there!")
		return
	if type == "kitchen" and not kitchen_jobs[cell].is_empty():
		build_message.emit("That Hearth is cooking!")
		return
	var refund: int = GameManager.FURNITURE[type]["cost"] / 2
	GameManager.earn(refund)
	furniture.erase(cell)
	table_owner.erase(cell)
	kitchen_jobs.erase(cell)
	build_message.emit("Sold for %dg." % refund)


func _cell_at(local_pos: Vector2) -> Vector2i:
	var cell := Vector2i(floori(local_pos.x / CELL_SIZE), floori(local_pos.y / CELL_SIZE))
	if cell.x < 0 or cell.y < 0 or cell.x >= COLS or cell.y >= ROWS:
		return NO_CELL
	return cell


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
	var floor_size := Vector2(COLS * CELL_SIZE, ROWS * CELL_SIZE)

	# Checkerboard wooden floor.
	for x in COLS:
		for y in ROWS:
			var shade: float = 0.38 if (x + y) % 2 == 0 else 0.33
			draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE),
					Color(shade, shade * 0.72, shade * 0.5))

	# Faint grid lines while building, so squares are easy to see.
	if build_type != "":
		for x in COLS + 1:
			draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, floor_size.y), Color(1, 1, 1, 0.25), 2.0)
		for y in ROWS + 1:
			draw_line(Vector2(0, y * CELL_SIZE), Vector2(floor_size.x, y * CELL_SIZE), Color(1, 1, 1, 0.25), 2.0)

	# Walls and door.
	draw_rect(Rect2(Vector2.ZERO, floor_size), Color(0.2, 0.12, 0.07), false, 8.0)
	draw_rect(Rect2(floor_size.x / 2.0 - 40, floor_size.y - 4, 80, 60), Color(0.45, 0.3, 0.15))

	# Furniture.
	for cell in furniture:
		var type: String = furniture[cell]
		var rect := Rect2(Vector2(cell) * CELL_SIZE + Vector2(8, 8), Vector2(CELL_SIZE - 16, CELL_SIZE - 16))
		draw_rect(rect, GameManager.FURNITURE[type]["color"])
		draw_string(font, rect.position + Vector2(0, 20), GameManager.FURNITURE[type]["name"],
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color.WHITE)

		# Cooking progress bar on busy Hearths.
		if type == "kitchen" and not kitchen_jobs[cell].is_empty():
			var job: Dictionary = kitchen_jobs[cell]
			var done: float = 1.0 - job["time_left"] / job["total"]
			var bar := Rect2(rect.position + Vector2(4, rect.size.y - 14), Vector2(rect.size.x - 8, 8))
			draw_rect(bar, Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * done, bar.size.y)), Color(1.0, 0.75, 0.2))
