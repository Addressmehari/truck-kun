@tool
extends RigidBody2D

@export var issensor: bool = false:
	set(val):
		issensor = val
		_update_physics_state()

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

var original_collision_layer: int = 1
var original_collision_mask: int = 1

func _ready() -> void:
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
	else:
		if issensor:
			freeze = true
			collision_layer = 0
			collision_mask = 0
		else:
			freeze = false
			collision_layer = original_collision_layer
			collision_mask = original_collision_mask
			gravity_scale = 1.0
	
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

		
	if truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
		var local_pos = container_body.to_local(global_position)
		for i in range(6):
			var slot_rect = container_body.slot_rects[i]
			if slot_rect.has_point(local_pos):
				if container_body.try_add_to_slot(i, self):
					queue_free()
					return

func _draw() -> void:
	var rect = Rect2(-width/2.0, -height/2.0, width, height)
	
	var current_color = color
	# Render as translucent if it acts as a sensor (due to either dragging or issensor)
	if issensor or is_dragging:
		current_color.a = 0.5
	else:
		current_color.a = 1.0
		
	# Draw background fill
	draw_rect(rect, current_color, true)
	
	# Draw outline border
	var border_color = Color.BLACK
	border_color.a = current_color.a
	draw_rect(rect, border_color, false, 2.0)
	
	# Draw diagonal lines (wooden crate look)
	draw_line(Vector2(-width/2.0, -height/2.0), Vector2(width/2.0, height/2.0), border_color, 2.0)
	draw_line(Vector2(width/2.0, -height/2.0), Vector2(-width/2.0, height/2.0), border_color, 2.0)
