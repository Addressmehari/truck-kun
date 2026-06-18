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

@export var color: Color = Color(0.4, 0.75, 0.9, 0.55): # Translucent Glass Blue
	set(val):
		color = val
		queue_redraw()

@export var health: float = 100.0:
	set(val):
		health = clamp(val, 0.0, 100.0)
		queue_redraw()

var is_glass_prop: bool = true
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var unloaded_from_slot: int = -1
var drag_start_position: Vector2 = Vector2.ZERO

var original_collision_layer: int = 1
var original_collision_mask: int = 1
var last_velocity := Vector2.ZERO
var time_alive := 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	add_to_group("crates")
	input_pickable = true
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	
	# Enable contact monitoring to check road impact
	contact_monitor = true
	max_contacts_reported = 4
	
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
			var parent_node = get_parent()
			if parent_node:
				var truck = parent_node.get_node_or_null("truck")
				if truck and "is_e_toggled" in truck and not truck.is_e_toggled:
					return # Only allow dragging if zoom is opened
					
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

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if is_dragging:
		global_position = get_global_mouse_position() + drag_offset
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
	else:
		time_alive += delta
		last_velocity = linear_velocity


func break_glass_in_world() -> void:
	# Spawn glass break shard particles
	var particles = CPUParticles2D.new()
	particles.global_position = global_position
	particles.amount = 30
	particles.lifetime = 0.8
	particles.spread = 180.0 # Burst outwards
	particles.gravity = Vector2(0, 250)
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 160.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	
	# Translucent cyan gradient ramp
	var ramp = Gradient.new()
	ramp.set_color(0, Color(0.5, 0.8, 0.95, 0.9))
	ramp.set_color(1, Color(0.5, 0.8, 0.95, 0.0))
	particles.color_ramp = ramp
	particles.one_shot = true
	particles.emitting = true
	particles.local_coords = false
	
	get_parent().add_child(particles)
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)
	
	queue_free()

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
					
	if _is_overlapping_truck(truck):
		if unloaded_from_slot != -1:
			if container_body.try_add_to_slot(unloaded_from_slot, self):
				queue_free()
				return
			for i in range(6):
				if container_body.try_add_to_slot(i, self):
					queue_free()
					return
		global_position = drag_start_position

func _is_overlapping_truck(truck) -> bool:
	var container_body = truck.get_node_or_null("container_body")
	var chassis = truck.get_node_or_null("chassis")
	
	if container_body:
		var local_to_container = container_body.to_local(global_position)
		if (local_to_container.x > -140.0 and local_to_container.x < 20.0 and 
			local_to_container.y > -110.0 and local_to_container.y < 30.0):
			return true
			
	if chassis:
		var local_to_chassis = chassis.to_local(global_position)
		if (local_to_chassis.x > -20.0 and local_to_chassis.x < 90.0 and 
			local_to_chassis.y > -90.0 and local_to_chassis.y < 20.0):
			return true
			
	return false

func _draw() -> void:
	var rect = Rect2(-width / 2.0, -height / 2.0, width, height)
	
	var current_color = color
	if issensor or is_dragging:
		current_color.a = 0.4
	else:
		current_color.a = 0.75 # semi-translucent glass look
		
	# Draw glass background tint
	draw_rect(rect, current_color, true)
	
	# Draw shine/glare diagonal lines inside glass
	var shine_color = Color(1.0, 1.0, 1.0, 0.45 * current_color.a)
	# Glare diagonal 1
	draw_line(Vector2(-width/4.0, -height/2.0), Vector2(width/2.0, height/4.0), shine_color, 2.0)
	# Glare diagonal 2
	draw_line(Vector2(-width/2.0, -height/4.0), Vector2(width/4.0, height/2.0), shine_color, 1.2)
	
	# Draw thin icy glowing border
	var border_color = Color(0.7, 0.9, 1.0, current_color.a)
	draw_rect(rect, border_color, false, 2.0)
	
	# Draw dark corners
	var corner_color = Color(0.2, 0.4, 0.6, current_color.a * 0.8)
	var c_len = 5.0
	# Top Left
	draw_line(Vector2(-width/2.0, -height/2.0), Vector2(-width/2.0 + c_len, -height/2.0), corner_color, 1.5)
	draw_line(Vector2(-width/2.0, -height/2.0), Vector2(-width/2.0, -height/2.0 + c_len), corner_color, 1.5)
	# Top Right
	draw_line(Vector2(width/2.0, -height/2.0), Vector2(width/2.0 - c_len, -height/2.0), corner_color, 1.5)
	draw_line(Vector2(width/2.0, -height/2.0), Vector2(width/2.0, -height/2.0 + c_len), corner_color, 1.5)
	# Bottom Left
	draw_line(Vector2(-width/2.0, height/2.0), Vector2(-width/2.0 + c_len, height/2.0), corner_color, 1.5)
	draw_line(Vector2(-width/2.0, height/2.0), Vector2(-width/2.0, height/2.0 - c_len), corner_color, 1.5)
	# Bottom Right
	draw_line(Vector2(width/2.0, height/2.0), Vector2(width/2.0 - c_len, height/2.0), corner_color, 1.5)
	draw_line(Vector2(width/2.0, height/2.0), Vector2(width/2.0, height/2.0 - c_len), corner_color, 1.5)

	# 3. Draw health bar above the glass crate in the world
	if not Engine.is_editor_hint():
		var bar_w = width - 4.0
		var bar_h = 3.5
		var bar_y = -height/2.0 - 9.0
		var bar_rect = Rect2(-bar_w / 2.0, bar_y, bar_w, bar_h)
		
		# Draw dark background
		draw_rect(bar_rect, Color(0.15, 0.15, 0.15, 0.8), true)
		# Draw green health line
		var health_ratio = health / 100.0
		var fill_color = Color(0.2, 0.9, 0.3, 0.9)
		if health_ratio < 0.35:
			fill_color = Color(1.0, 0.2, 0.2, 0.9) # low health is red
		elif health_ratio < 0.7:
			fill_color = Color(1.0, 0.7, 0.2, 0.9) # medium health is orange
			
		var fill_rect = Rect2(-bar_w / 2.0, bar_y, bar_w * health_ratio, bar_h)
		draw_rect(fill_rect, fill_color, true)
		# Outline
		draw_rect(bar_rect, Color(0.0, 0.0, 0.0, 0.7), false, 1.0)
