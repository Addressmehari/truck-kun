@tool
extends RigidBody2D

@export var issensor: bool = false:
	set(val):
		issensor = val
		_update_physics_state()

@export_enum("1x1", "2x1", "1x2", "2x2") var size_type: String = "1x1":
	set(val):
		size_type = val
		_update_dimensions()

@export var width: float = 40.0:
	set(val):
		width = max(10.0, val)
		queue_redraw()
		_update_collision_shape()

@export var height: float = 40.0:
	set(val):
		height = max(10.0, val)
		queue_redraw()
		_update_collision_shape()

@export var color: Color = Color(0.82, 0.53, 0.28): # wood brown
	set(val):
		color = val
		queue_redraw()

var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var unloaded_from_slot: int = -1
var drag_start_position: Vector2 = Vector2.ZERO

var original_collision_layer: int = 1
var original_collision_mask: int = 1

func _ready() -> void:
	_update_dimensions()
	if Engine.is_editor_hint():
		return
		
	add_to_group("crates")
	input_pickable = true
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	
	# Make sure the CollisionShape2D exists and is unique/ready
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape:
		shape_node.shape = shape_node.shape.duplicate()
	_update_collision_shape()
	_update_physics_state()

func _update_dimensions() -> void:
	match size_type:
		"1x1":
			width = 40.0
			height = 40.0
		"2x1":
			width = 80.0
			height = 40.0
		"1x2":
			width = 40.0
			height = 80.0
		"2x2":
			width = 80.0
			height = 80.0

func _update_collision_shape() -> void:
	if not is_node_ready():
		await ready
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is RectangleShape2D:
		shape_node.shape.size = Vector2(width, height)

func _update_physics_state() -> void:
	if Engine.is_editor_hint() or not is_node_ready():
		return
		
	if is_dragging:
		freeze = true
		# Act as a sensor (pass through all objects) while dragging
		collision_layer = 0
		collision_mask = 0
		z_index = 5
	else:
		if issensor:
			freeze = true
			collision_layer = 0
			collision_mask = 0
			z_index = 0
		else:
			freeze = false
			collision_layer = original_collision_layer
			collision_mask = original_collision_mask
			gravity_scale = 1.0
			z_index = 0
	
	queue_redraw()

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Check if inventory mode is open (E pressed)
			var parent_node = get_parent()
			if parent_node:
				var truck = parent_node.get_node_or_null("truck")
				if truck and "is_e_toggled" in truck and not truck.is_e_toggled:
					return # Only allow dragging if inventory zoom is opened via 'E' key
					
			is_dragging = true
			drag_offset = global_position - get_global_mouse_position()
			drag_start_position = global_position
			unloaded_from_slot = -1
			_update_physics_state()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and is_dragging:
			is_dragging = false
			_update_physics_state()
			_check_drop_on_container()
			
	# Rotate / Flip crate if 'R' or Right-Click is pressed while dragging
	if is_dragging:
		var request_rotation = false
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			request_rotation = true
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			request_rotation = true
			
		if request_rotation:
			if size_type == "2x1":
				size_type = "1x2"
				_update_dimensions()
				get_viewport().set_input_as_handled()
			elif size_type == "1x2":
				size_type = "2x1"
				_update_dimensions()
				get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_dragging:
		global_position = get_global_mouse_position() + drag_offset
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0

func _check_drop_on_container() -> void:
	var parent_node = get_parent()
	if not parent_node:
		return
	var truck = parent_node.get_node_or_null("truck")
	if not truck:
		return
	var container_body = truck.get_node_or_null("container_body")
	if not container_body or not container_body.has_method("try_add_to_slot"):
		return
		
	# 1. Try placing in a slot first
	if truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
		var local_pos = container_body.to_local(global_position)
		
		# Sort slots by distance from local_pos to slot center
		var slots_with_dist = []
		for i in range(6):
			var slot_center = container_body.slot_rects[i].get_center()
			var dist = local_pos.distance_to(slot_center)
			slots_with_dist.append({"index": i, "dist": dist})
			
		slots_with_dist.sort_custom(func(a, b): return a.dist < b.dist)
		
		# Try adding to the closest valid slot within range
		for slot_info in slots_with_dist:
			if slot_info.dist < 60.0:
				if container_body.try_add_to_slot(slot_info.index, self):
					queue_free()
					return
					
	# 2. Check if we drop-overlapped the truck to prevent damage
	if _is_overlapping_truck(truck):
		if unloaded_from_slot != -1:
			# Try putting it back in its original slot
			if container_body.try_add_to_slot(unloaded_from_slot, self):
				queue_free()
				return
			# Fallback: try any empty slot
			for i in range(6):
				if container_body.try_add_to_slot(i, self):
					queue_free()
					return
		
		# Teleport back to safe starting position (on ground or initial drag start)
		global_position = drag_start_position

func _is_overlapping_truck(truck) -> bool:
	var container_body = truck.get_node_or_null("container_body")
	var chassis = truck.get_node_or_null("chassis")
	
	if container_body:
		var local_to_container = container_body.to_local(global_position)
		# Container box bounds: left -117, right -5, top -80, bottom -1
		# We expand these bounds slightly for safety
		if (local_to_container.x > -140.0 and local_to_container.x < 20.0 and 
			local_to_container.y > -110.0 and local_to_container.y < 30.0):
			return true
			
	if chassis:
		var local_to_chassis = chassis.to_local(global_position)
		# Chassis box bounds: left 1, right 68, top -72, bottom 0
		# We expand these bounds slightly for safety
		if (local_to_chassis.x > -20.0 and local_to_chassis.x < 90.0 and 
			local_to_chassis.y > -90.0 and local_to_chassis.y < 20.0):
			return true
			
	return false

func _draw() -> void:
	var rect = Rect2(-width / 2.0, -height / 2.0, width, height)
	
	var current_color = color
	# Render as translucent if it acts as a sensor (due to either dragging or issensor)
	if issensor or is_dragging:
		current_color.a = 0.5
	else:
		current_color.a = 1.0
		
	# Draw background fill
	draw_rect(rect, current_color, true)
	
	# Shading (top-left highlight, bottom-right shadow)
	var shadow_color = Color(0.0, 0.0, 0.0, 0.25 * current_color.a)
	var highlight_color = Color(1.0, 1.0, 1.0, 0.2 * current_color.a)
	# Left/Top highlights
	draw_line(rect.position + Vector2(1, 1), Vector2(rect.end.x - 1, rect.position.y + 1), highlight_color, 1.5)
	draw_line(rect.position + Vector2(1, 1), Vector2(rect.position.x + 1, rect.end.y - 1), highlight_color, 1.5)
	# Right/Bottom shadows
	draw_line(Vector2(rect.end.x - 1, rect.position.y + 1), rect.end - Vector2(1, 1), shadow_color, 1.5)
	draw_line(Vector2(rect.position.x + 1, rect.end.y - 1), rect.end - Vector2(1, 1), shadow_color, 1.5)
	
	# Outer frame planks
	var frame_color = current_color.darkened(0.28)
	frame_color.a = current_color.a
	var frame_t = 3.0
	draw_rect(rect, frame_color, false, frame_t)
	
	# Diagonal crossbeam plank
	var start_pt = rect.position + Vector2(2, 2)
	var end_pt = rect.end - Vector2(2, 2)
	draw_line(start_pt, end_pt, frame_color, 3.0)
	
	# Corner Metal Plates / Brackets
	var plate_color = Color(0.18, 0.18, 0.22)
	plate_color.a = current_color.a
	var p_size = 4.0
	# Top Left
	draw_rect(Rect2(rect.position.x, rect.position.y, p_size, p_size), plate_color, true)
	# Top Right
	draw_rect(Rect2(rect.end.x - p_size, rect.position.y, p_size, p_size), plate_color, true)
	# Bottom Left
	draw_rect(Rect2(rect.position.x, rect.end.y - p_size, p_size, p_size), plate_color, true)
	# Bottom Right
	draw_rect(Rect2(rect.end.x - p_size, rect.end.y - p_size, p_size, p_size), plate_color, true)
	
	# Small iron rivets
	var rivet_color = Color(0.55, 0.55, 0.6)
	rivet_color.a = current_color.a
	draw_circle(rect.position + Vector2(2, 2), 0.8, rivet_color)
	draw_circle(Vector2(rect.end.x - 2, rect.position.y + 2), 0.8, rivet_color)
	draw_circle(Vector2(rect.position.x + 2, rect.end.y - 2), 0.8, rivet_color)
	draw_circle(rect.end - Vector2(2, 2), 0.8, rivet_color)
