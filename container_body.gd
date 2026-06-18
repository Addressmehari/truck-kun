extends RigidBody2D

# 6 slots inside the container
var inventory = [null, null, null, null, null, null]

# Local coordinates for the slots in the container space (width 112, height 79)
var slot_rects = [
	Rect2(-111, -74, 30, 30),
	Rect2(-75, -74, 30, 30),
	Rect2(-39, -74, 30, 30),
	Rect2(-111, -37, 30, 30),
	Rect2(-75, -37, 30, 30),
	Rect2(-39, -37, 30, 30)
]

@onready var truck = get_parent()
@onready var backdoor = get_node_or_null("backdoor")

var backdoor_blocked: bool = false

func _ready() -> void:
	# Force children (ColorRects) to render behind the parent's custom _draw() call.
	# This ensures the drawn slots are visible on top of the container shape.
	var container_rect = get_node_or_null("container")
	if container_rect:
		container_rect.show_behind_parent = true
	var rim_rect = get_node_or_null("rim_back")
	if rim_rect:
		rim_rect.show_behind_parent = true
		
	# Setup backdoor pivot at the bottom center and color
	if backdoor:
		backdoor.pivot_offset = Vector2(2.5, 76.0)
		backdoor.color = Color(0.25, 0.25, 0.25) # dark shutter metal color

func _physics_process(delta: float) -> void:
	# Refresh slot visuals
	queue_redraw()
	
	# Check if any physical crate is blocking the backdoor's opening path
	backdoor_blocked = false
	if backdoor:
		var backdoor_pivot_global = to_global(Vector2(-117.5, -3.0))
		for crate in get_tree().get_nodes_in_group("crates"):
			if is_instance_valid(crate) and not crate.get("is_dragging"):
				var dist = backdoor_pivot_global.distance_to(crate.global_position)
				if dist < 75.0: # door swing radius sweep
					backdoor_blocked = true
					break

		# Warn by modulating color if blocked and player is trying to open (E toggled)
		if backdoor_blocked and is_instance_valid(truck) and truck.get("is_e_toggled"):
			# Pulse modulation color between normal and warnings red
			var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)
			backdoor.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.2, 0.2), pulse)
		else:
			backdoor.modulate = Color(1.0, 1.0, 1.0)
	
	# Smoothly animate backdoor rotation to drop it backwards (rotate left)
	if backdoor and is_instance_valid(truck):
		var target_rotation = 0.0
		if truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
			# Drop backwards/downwards (approx -110 degrees = -1.92 radians)
			target_rotation = -1.92
		else:
			target_rotation = 0.0
		backdoor.rotation = lerp(backdoor.rotation, target_rotation, 8.0 * delta)



func _draw() -> void:
	if not is_instance_valid(truck):
		return
		
	# Draw slots only if zoom is requested
	if truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
		for i in range(6):
			var rect = slot_rects[i]
			var item = inventory[i]
			
			if item == null:
				# Draw a visible dark border and subtle background fill on any container background color
				draw_rect(rect, Color(0, 0, 0, 0.1), true)
				draw_rect(rect, Color(0, 0, 0, 0.4), false, 2.0)
			else:
				# Draw loaded crate representation inside the slot
				var inner_color = item.get("color", Color(0.82, 0.53, 0.28))
				var inner_rect = rect.grow(-2)
				draw_rect(inner_rect, inner_color, true)
				
				# Crate Outline & Cross (X)
				draw_rect(inner_rect, Color.BLACK, false, 2.0)
				draw_line(inner_rect.position, inner_rect.end, Color.BLACK, 2.0)
				draw_line(Vector2(inner_rect.end.x, inner_rect.position.y), Vector2(inner_rect.position.x, inner_rect.end.y), Color.BLACK, 2.0)

func try_add_to_slot(slot_index: int, crate) -> bool:
	if slot_index < 0 or slot_index >= 6:
		return false
	if inventory[slot_index] == null:
		inventory[slot_index] = {
			"color": crate.color,
			"width": crate.width,
			"height": crate.height
		}
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
			var local_mouse = to_local(get_global_mouse_position())
			for i in range(6):
				if inventory[i] != null and slot_rects[i].has_point(local_mouse):
					# Unload crate!
					_unload_slot(i)
					get_viewport().set_input_as_handled()
					break

func _unload_slot(slot_index: int) -> void:
	var item_data = inventory[slot_index]
	inventory[slot_index] = null
	
	# Spawn a new crate at the mouse position
	var crate_scene = load("res://crate.tscn")
	if crate_scene:
		var new_crate = crate_scene.instantiate()
		new_crate.color = item_data.get("color", Color(0.82, 0.53, 0.28))
		new_crate.width = item_data.get("width", 40.0)
		new_crate.height = item_data.get("height", 40.0)
		
		# Add it to the main scene
		get_tree().current_scene.add_child(new_crate)
		
		# Position it at mouse
		new_crate.global_position = get_global_mouse_position()
		
		# Enable dragging immediately
		new_crate.is_dragging = true
		new_crate.drag_offset = Vector2.ZERO
		new_crate._update_physics_state()
