@tool
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
@onready var tyre_2: RigidBody2D = get_node_or_null("../tyre-2")
@onready var tyre_3: RigidBody2D = get_node_or_null("../tyre-3")

var backdoor_blocked: bool = false
var dust_particles_2: CPUParticles2D
var dust_particles_3: CPUParticles2D

func _ready() -> void:
	# Hide default placeholder rectangles
	var container_rect = get_node_or_null("container")
	if container_rect:
		container_rect.visible = false
	var rim_rect = get_node_or_null("rim_back")
	if rim_rect:
		rim_rect.visible = false
		
	if Engine.is_editor_hint():
		return
		
	# Setup backdoor pivot at the bottom center and color
	if backdoor:
		backdoor.pivot_offset = Vector2(2.5, 76.0)
		backdoor.color = Color(0.18, 0.18, 0.2) # dark metal shutter

	# Setup dust particles for middle wheel
	dust_particles_2 = CPUParticles2D.new()
	dust_particles_2.position = Vector2(-33, 19.25)
	dust_particles_2.amount = 12
	dust_particles_2.lifetime = 0.5
	dust_particles_2.direction = Vector2(-1.0, -0.25)
	dust_particles_2.spread = 20.0
	dust_particles_2.gravity = Vector2(0, 150)
	dust_particles_2.initial_velocity_min = 40.0
	dust_particles_2.initial_velocity_max = 80.0
	dust_particles_2.scale_amount_min = 2.0
	dust_particles_2.scale_amount_max = 4.5
	
	var dust_ramp = Gradient.new()
	dust_ramp.set_color(0, Color(0.65, 0.55, 0.45, 0.7))
	dust_ramp.set_color(1, Color(0.65, 0.55, 0.45, 0.0))
	dust_particles_2.color_ramp = dust_ramp
	dust_particles_2.local_coords = false
	add_child(dust_particles_2)

	# Setup dust particles for rear wheel
	dust_particles_3 = CPUParticles2D.new()
	dust_particles_3.position = Vector2(-93, 19.25)
	dust_particles_3.amount = 12
	dust_particles_3.lifetime = 0.5
	dust_particles_3.direction = Vector2(-1.0, -0.25)
	dust_particles_3.spread = 20.0
	dust_particles_3.gravity = Vector2(0, 150)
	dust_particles_3.initial_velocity_min = 40.0
	dust_particles_3.initial_velocity_max = 80.0
	dust_particles_3.scale_amount_min = 2.0
	dust_particles_3.scale_amount_max = 4.5
	dust_particles_3.color_ramp = dust_ramp
	dust_particles_3.local_coords = false
	add_child(dust_particles_3)

	# Enable tyre contacts reporting for ground checking
	if tyre_2:
		tyre_2.contact_monitor = true
		tyre_2.max_contacts_reported = max(tyre_2.max_contacts_reported, 2)
	if tyre_3:
		tyre_3.contact_monitor = true
		tyre_3.max_contacts_reported = max(tyre_3.max_contacts_reported, 2)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Refresh visuals
	queue_redraw()
	
	# Control tyre dust emissions
	var speed = linear_velocity.length()
	var emit_2 = false
	var emit_3 = false
	if speed > 30.0:
		if is_instance_valid(tyre_2) and tyre_2.get_colliding_bodies().size() > 0:
			emit_2 = true
		if is_instance_valid(tyre_3) and tyre_3.get_colliding_bodies().size() > 0:
			emit_3 = true
	if dust_particles_2:
		dust_particles_2.emitting = emit_2
	if dust_particles_3:
		dust_particles_3.emitting = emit_3
	
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
		
	var container_left = -117.0
	var container_right = -5.0
	var container_top = -80.0
	var container_bottom = -1.0

	# --- 1. Draw Suspension Springs ---
	if is_instance_valid(tyre_2):
		var local_tyre = to_local(tyre_2.global_position)
		draw_spring(Vector2(-33, -30), local_tyre, 7.0, 5)
	if is_instance_valid(tyre_3):
		var local_tyre = to_local(tyre_3.global_position)
		draw_spring(Vector2(-93, -30), local_tyre, 7.0, 5)

	# --- 2. Draw Mudflap (Behind Rear Wheel) ---
	draw_rect(Rect2(-114, 0, 3, 14), Color(0.12, 0.12, 0.14), true)
	draw_circle(Vector2(-112.5, 11), 1.0, Color(0.9, 0.1, 0.1)) # red reflector

	# --- 3. Draw Cargo Container background (Industrial slate-grey) ---
	draw_rect(Rect2(container_left, container_top, 112.0, 79.0), Color(0.22, 0.24, 0.27), true)

	# --- 4. Draw Corrugated Steel ridges (3D ribs) ---
	var rib_w = 6.0
	var rib_gap = 5.0
	var current_x = container_left + 6.0
	while current_x + rib_w < container_right:
		# Draw shadow side of rib
		draw_rect(Rect2(current_x, container_top + 3.0, rib_w, 73.0), Color(0.14, 0.15, 0.17), true)
		# Draw highlight side of rib
		draw_rect(Rect2(current_x + 2.0, container_top + 3.0, rib_w - 2.0, 73.0), Color(0.3, 0.32, 0.36), true)
		current_x += rib_w + rib_gap

	# --- 5. Draw Yellow & Black Diagonal Hazard stripes ---
	# Yellow background bar
	draw_rect(Rect2(container_left + 3.0, container_bottom - 11.0, 106.0, 8.0), Color(0.92, 0.72, 0.05), true)
	# Black diagonal stripes
	var stripe_x = container_left + 6.0
	while stripe_x < container_right - 6.0:
		draw_line(Vector2(stripe_x, container_bottom - 11.0), Vector2(stripe_x + 6.0, container_bottom - 3.0), Color(0.1, 0.1, 0.12), 3.0)
		stripe_x += 12.0

	# --- 6. Draw Steel Frame Outline ---
	draw_rect(Rect2(container_left, container_top, 112.0, 79.0), Color(0.14, 0.15, 0.17), false, 2.5)

	# --- 7. Draw Carbon Wheel Arches ---
	for arch_x in [-33.0, -93.0]:
		var arch_center = Vector2(arch_x, -2.0)
		var arch_radius = 24.5
		var arch_points = PackedVector2Array()
		var arch_steps = 16
		for i in range(arch_steps + 1):
			var angle = PI + (PI * i / arch_steps)
			arch_points.append(arch_center + Vector2(cos(angle), sin(angle)) * arch_radius)
		draw_polyline(arch_points, Color(0.12, 0.12, 0.14), 4.5)

	# --- 8. Draw Inventory Slots (if zoom requested) ---
	var zoom_requested = false
	if not Engine.is_editor_hint() and is_instance_valid(truck) and truck.has_method("is_zoom_requested"):
		zoom_requested = truck.is_zoom_requested()
		
	if zoom_requested:
		for i in range(6):
			var rect = slot_rects[i]
			var item = inventory[i]
			
			if item == null:
				draw_rect(rect, Color(0, 0, 0, 0.25), true)
				draw_rect(rect, Color(0.92, 0.72, 0.05, 0.6), false, 1.5) # Glowing yellow slot border
			else:
				var inner_color = item.get("color", Color(0.82, 0.53, 0.28))
				var inner_rect = rect.grow(-2)
				draw_rect(inner_rect, inner_color, true)
				
				draw_rect(inner_rect, Color.BLACK, false, 2.0)
				draw_line(inner_rect.position, inner_rect.end, Color.BLACK, 2.0)
				draw_line(Vector2(inner_rect.end.x, inner_rect.position.y), Vector2(inner_rect.position.x, inner_rect.end.y), Color.BLACK, 2.0)


# Helper function to draw dynamic coil springs
func draw_spring(from_pos: Vector2, to_pos: Vector2, width: float, coils: int) -> void:
	var dir = (to_pos - from_pos).normalized()
	var length = from_pos.distance_to(to_pos)
	if length < 8.0:
		return
	var perpendicular = Vector2(-dir.y, dir.x)
	
	# Draw shock absorber center shaft
	draw_line(from_pos, to_pos, Color(0.2, 0.2, 0.22), 4.0)
	draw_line(from_pos + dir * 3.0, to_pos - dir * 3.0, Color(0.65, 0.65, 0.7), 2.0)
	
	# Coil springs wrap around the shaft
	var start_spring = from_pos + dir * 6.0
	var end_spring = to_pos - dir * 6.0
	var coil_len = start_spring.distance_to(end_spring)
	
	var points = PackedVector2Array()
	points.append(from_pos)
	points.append(start_spring)
	
	var steps = coils * 2
	for i in range(steps + 1):
		var t = float(i) / steps
		var p = start_spring + dir * (t * coil_len)
		if i > 0 and i < steps:
			var offset = perpendicular * (width * (-1.0 if i % 2 == 0 else 1.0))
			points.append(p + offset)
		else:
			points.append(p)
			
	points.append(end_spring)
	points.append(to_pos)
	
	draw_polyline(points, Color(0.9, 0.15, 0.15), 2.8)

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
	if Engine.is_editor_hint():
		return
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
		
		# Enable dragging immediately and track initial slot/safe position
		new_crate.is_dragging = true
		new_crate.drag_offset = Vector2.ZERO
		new_crate.drag_start_position = new_crate.global_position
		new_crate.unloaded_from_slot = slot_index
		new_crate._update_physics_state()
