@tool
extends RigidBody2D

# 6 slots inside the container
var inventory = [
	{"type": "glass", "color": Color(0.4, 0.75, 0.9, 0.55), "width": 40.0, "height": 40.0, "health": 100.0},
	null,
	null,
	null,
	null,
	null
]
var glass_break_particles: CPUParticles2D
var last_linear_velocity := Vector2.ZERO
var time_alive := 0.0

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
@onready var tyre_2: RigidBody2D = get_node_or_null("tyre-2")
@onready var tyre_3: RigidBody2D = get_node_or_null("tyre-3")

var backdoor_blocked: bool = false
var dust_particles_2: CPUParticles2D
var dust_particles_3: CPUParticles2D
var bounce_offset := Vector2.ZERO
var backdoor_start_pos := Vector2.ZERO

# Suspension configuration
var suspension_rest_dist := 10.0
var suspension_stiffness := 150.0
var suspension_damping := 8.0

func _ready() -> void:
	# Hide default placeholder rectangles
	var container_rect = get_node_or_null("container")
	if container_rect:
		container_rect.visible = false
	var rim_rect = get_node_or_null("rim_back")
	if rim_rect:
		rim_rect.visible = false
		
	if backdoor:
		backdoor_start_pos = backdoor.position
		
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

	# Setup glass break particles
	glass_break_particles = CPUParticles2D.new()
	glass_break_particles.position = Vector2(-120, -38)
	glass_break_particles.amount = 40
	glass_break_particles.lifetime = 1.0
	glass_break_particles.direction = Vector2(-1.0, 0.4)
	glass_break_particles.spread = 40.0
	glass_break_particles.gravity = Vector2(0, 240)
	glass_break_particles.initial_velocity_min = 100.0
	glass_break_particles.initial_velocity_max = 220.0
	glass_break_particles.scale_amount_min = 1.5
	glass_break_particles.scale_amount_max = 4.0
	
	var glass_ramp = Gradient.new()
	glass_ramp.set_color(0, Color(0.5, 0.85, 0.95, 0.85))
	glass_ramp.set_color(0.6, Color(0.5, 0.8, 0.95, 0.6))
	glass_ramp.set_color(1, Color(0.5, 0.8, 0.95, 0.0))
	glass_break_particles.color_ramp = glass_ramp
	glass_break_particles.one_shot = true
	glass_break_particles.emitting = false
	glass_break_particles.local_coords = false
	add_child(glass_break_particles)

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
	time_alive += delta
	# Refresh visuals
	queue_redraw()
	
	# Process fake programmatic suspension for the tyres
	_process_custom_suspension(tyre_2, Vector2(-31, -8), delta)
	_process_custom_suspension(tyre_3, Vector2(-91, -8), delta)
	
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

	# Dynamic damage to glass items inside inventory due to vibration/shake and hard landings
	var on_ground = false
	if (is_instance_valid(tyre_2) and tyre_2.get_colliding_bodies().size() > 0) or \
	   (is_instance_valid(tyre_3) and tyre_3.get_colliding_bodies().size() > 0):
		on_ground = true
		
	# 1. Bumpy road/vibration damage based on speed limits (km/h)
	var speed_dmg_rate = 0.0
	var speed_kmh = speed * 0.08
	
	if on_ground:
		if speed_kmh >= 40.0 and speed_kmh < 60.0:
			# Slowly reduce health (approx 0.15% to 3.0% per second)
			speed_dmg_rate = (speed_kmh - 40.0) * 0.15
		elif speed_kmh >= 60.0:
			# Fast health reduction (approx 3% to 33%+ per second)
			speed_dmg_rate = 3.0 + (speed_kmh - 60.0) * 1.5
		
	# 2. Swaying/flipping damage (less sensitive, triggers on extreme sway)
	if abs(angular_velocity) > 1.2:
		speed_dmg_rate += (abs(angular_velocity) - 1.2) * 5.0
		
	# Apply continuous speed/sway damage (after startup grace period)
	if time_alive > 1.5 and speed_dmg_rate > 0.0:
		for i in range(6):
			if inventory[i] != null and inventory[i].get("type") == "glass":
				inventory[i]["health"] -= speed_dmg_rate * delta
				if inventory[i]["health"] <= 0.0:
					inventory[i] = null
					emit_glass_break()
					
	# 3. Bump & Landing damage (sudden vertical acceleration/deceleration - after startup grace period)
	if delta > 0.0:
		var accel = (linear_velocity - last_linear_velocity) / delta
		# Raised threshold to 800.0 to prevent normal driving vibrations from cracking glass
		if time_alive > 1.5 and accel.length() > 800.0:
			# Decreased multiplier to 0.00015 (100x less damage) to make glass extremely resilient to bumps
			var landing_dmg = (accel.length() - 800.0) * 0.00006
			for i in range(6):
				if inventory[i] != null and inventory[i].get("type") == "glass":
					inventory[i]["health"] -= landing_dmg
					if inventory[i]["health"] <= 0.0:
						inventory[i] = null
						emit_glass_break()
	last_linear_velocity = linear_velocity


func _draw() -> void:
	if not is_instance_valid(truck):
		return
		
	# Apply visual container transform (none — physics owns motion)
	draw_set_transform(Vector2.ZERO)
		
	var container_left = -117.0
	var container_right = -5.0
	var container_top = -80.0
	var container_bottom = -1.0

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

	# --- 7.5 Draw Suspension Springs (Tyre 2 & 3) ---
	if not Engine.is_editor_hint():
		if is_instance_valid(tyre_2):
			draw_spring(Vector2(-31, -8), tyre_2.position, 5.0, 4)
			draw_rect(Rect2(-37, -14, 12, 4), Color(0.22, 0.22, 0.25), true)
			draw_rect(Rect2(tyre_2.position.x - 6, tyre_2.position.y - 2, 12, 4), Color(0.22, 0.22, 0.25), true)
		if is_instance_valid(tyre_3):
			draw_spring(Vector2(-91, -8), tyre_3.position, 5.0, 4)
			draw_rect(Rect2(-97, -14, 12, 4), Color(0.22, 0.22, 0.25), true)
			draw_rect(Rect2(tyre_3.position.x - 6, tyre_3.position.y - 2, 12, 4), Color(0.22, 0.22, 0.25), true)

	# --- 8. Draw Inventory Slots (if zoom requested) ---
	var zoom_requested = false
	if not Engine.is_editor_hint() and is_instance_valid(truck) and truck.has_method("is_zoom_requested"):
		zoom_requested = truck.is_zoom_requested()
		
	if zoom_requested:
		# Draw cargo hold dark interior recess
		draw_rect(Rect2(container_left + 2.0, container_top + 2.0, 108.0, 75.0), Color(0.08, 0.09, 0.11, 0.8), true)
		
		for i in range(6):
			var item = inventory[i]
			
			if item != null and item.get("type") == "part":
				continue # Skip, it will be drawn by the root slot
				
			var rect = slot_rects[i]
			if item != null:
				var grid_w = item.get("grid_w", 1)
				var grid_h = item.get("grid_h", 1)
				var col = i % 3
				var row = i / 3
				var end_col = col + grid_w - 1
				var end_row = row + grid_h - 1
				var end_slot = end_col + end_row * 3
				if end_slot >= 0 and end_slot < 6:
					var end_rect = slot_rects[end_slot]
					rect = Rect2(rect.position, end_rect.end - rect.position)
			
			if item == null:
				# 3D Recessed Slot Frame
				draw_rect(rect, Color(0.04, 0.04, 0.05, 0.6), true) # Slot interior
				draw_rect(rect, Color(0.25, 0.28, 0.32), false, 1.5) # Steel slot rim
				
				# Subtle inner shadow
				draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(0, 0, 0, 0.5), 1.0)
				draw_line(rect.position, Vector2(rect.position.x, rect.end.y), Color(0, 0, 0, 0.5), 1.0)
				
				# Blueprint-style dashed icon inside slot
				var inner_dash = rect.grow(-6)
				draw_rect(inner_dash, Color(0.25, 0.28, 0.32, 0.4), false, 1.0)
				
				# Empty slot LED (Soft Glowing Red/Amber)
				draw_circle(Vector2(rect.end.x - 4, rect.position.y + 4), 1.8, Color(0.95, 0.35, 0.15))
				draw_circle(Vector2(rect.end.x - 4, rect.position.y + 4), 0.8, Color(1.0, 0.7, 0.5)) # light core
			else:
				var is_glass = (item.get("type") == "glass")
				
				if is_glass:
					# Draw glass base
					var glass_color = Color(0.3, 0.7, 0.9, 0.55) # translucent blue
					draw_rect(rect, glass_color, true)
					
					# Shine diagonal lines
					var shine_color = Color(1.0, 1.0, 1.0, 0.4)
					draw_line(rect.position + Vector2(2, 6), rect.position + Vector2(24, 28), shine_color, 1.5)
					draw_line(rect.position + Vector2(2, 12), rect.position + Vector2(18, 28), shine_color, 0.8)
					
					# Shining icy borders
					var border_color = Color(0.6, 0.85, 1.0, 0.9)
					draw_rect(rect, border_color, false, 1.5)
					
					# Corners
					var corner_color = Color(0.2, 0.5, 0.8, 0.7)
					var clen = 4.0
					draw_line(rect.position, rect.position + Vector2(clen, 0), corner_color, 1.0)
					draw_line(rect.position, rect.position + Vector2(0, clen), corner_color, 1.0)
					draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - clen, rect.position.y), corner_color, 1.0)
					draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + clen), corner_color, 1.0)
					draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x + clen, rect.end.y), corner_color, 1.0)
					draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, rect.end.y - clen), corner_color, 1.0)
					draw_line(rect.end, rect.end - Vector2(clen, 0), corner_color, 1.0)
					draw_line(rect.end, rect.end - Vector2(0, clen), corner_color, 1.0)
					
					# Active LED (blue/cyan for glass!)
					draw_circle(Vector2(rect.end.x - 4, rect.position.y + 4), 1.8, Color(0.15, 0.75, 0.95))
					draw_circle(Vector2(rect.end.x - 4, rect.position.y + 4), 0.8, Color(0.7, 0.95, 1.0))
					
					# Health bar at the top of the slot
					var health_ratio = item.get("health", 100.0) / 100.0
					var bar_rect = Rect2(rect.position.x + 3, rect.position.y + 2, rect.size.x - 6, 2)
					# Dark background
					draw_rect(bar_rect, Color(0.15, 0.15, 0.15, 0.8), true)
					# Health fill
					var fill_color = Color(0.2, 0.9, 0.3, 0.9)
					if health_ratio < 0.35:
						fill_color = Color(1.0, 0.2, 0.2, 0.9)
					elif health_ratio < 0.7:
						fill_color = Color(1.0, 0.7, 0.2, 0.9)
					var fill_rect = Rect2(rect.position.x + 3, rect.position.y + 2, (rect.size.x - 6) * health_ratio, 2)
					draw_rect(fill_rect, fill_color, true)
				else:
					var inner_color = item.get("color", Color(0.82, 0.53, 0.28))
					
					# Draw base crate shape
					draw_rect(rect, inner_color, true)
					
					# Shading (top-left highlight, bottom-right shadow)
					var shadow_color = Color(0.0, 0.0, 0.0, 0.25)
					var highlight_color = Color(1.0, 1.0, 1.0, 0.2)
					# Left/Top highlights
					draw_line(rect.position + Vector2(1, 1), Vector2(rect.end.x - 1, rect.position.y + 1), highlight_color, 1.5)
					draw_line(rect.position + Vector2(1, 1), Vector2(rect.position.x + 1, rect.end.y - 1), highlight_color, 1.5)
					# Right/Bottom shadows
					draw_line(Vector2(rect.end.x - 1, rect.position.y + 1), rect.end - Vector2(1, 1), shadow_color, 1.5)
					draw_line(Vector2(rect.position.x + 1, rect.end.y - 1), rect.end - Vector2(1, 1), shadow_color, 1.5)
					
					# Outer frame planks
					var frame_color = inner_color.darkened(0.28)
					var frame_t = 3.0
					draw_rect(rect, frame_color, false, frame_t)
					
					# Diagonal crossbeam plank
					var start_pt = rect.position + Vector2(2, 2)
					var end_pt = rect.end - Vector2(2, 2)
					draw_line(start_pt, end_pt, frame_color, 3.0)
					
					# Corner Metal Plates / Brackets
					var plate_color = Color(0.18, 0.18, 0.22)
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
					draw_circle(rect.position + Vector2(2, 2), 0.8, rivet_color)
					draw_circle(Vector2(rect.end.x - 2, rect.position.y + 2), 0.8, rivet_color)
					draw_circle(Vector2(rect.position.x + 2, rect.end.y - 2), 0.8, rivet_color)
					draw_circle(rect.end - Vector2(2, 2), 0.8, rivet_color)
					
					# Active/Loaded slot LED (Glowing Emerald Green)
					draw_circle(Vector2(rect.end.x - 4, rect.position.y + 4), 1.8, Color(0.15, 0.85, 0.25))
					draw_circle(Vector2(rect.end.x - 4, rect.position.y + 4), 0.8, Color(0.7, 1.0, 0.8)) # light core


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


func _process_custom_suspension(tyre: RigidBody2D, anchor_local: Vector2, delta: float) -> void:
	if not is_instance_valid(tyre): return
	var anchor_global = to_global(anchor_local)
	var tyre_global = tyre.global_position
	
	var up_dir = -global_transform.y
	var offset = tyre_global - anchor_global
	
	var r_chassis = anchor_global - global_position
	var v_chassis_anchor = linear_velocity + Vector2(-angular_velocity * r_chassis.y, angular_velocity * r_chassis.x)
	var rel_vel = tyre.linear_velocity - v_chassis_anchor
	
	# Vertical Suspension (spring on Y axis)
	var vert_dist = offset.dot(-up_dir)
	var vert_vel = rel_vel.dot(-up_dir)
	var vert_error = vert_dist - suspension_rest_dist
	
	var vert_force_mag = -(vert_error * suspension_stiffness) - (vert_vel * suspension_damping)
	var vert_force = -up_dir * vert_force_mag
	
	tyre.apply_central_force(vert_force)
	apply_force(-vert_force, r_chassis)


func emit_glass_break() -> void:
	if is_instance_valid(glass_break_particles):
		glass_break_particles.restart()
		glass_break_particles.emitting = true

func try_add_to_slot(slot_index: int, crate) -> bool:
	if slot_index < 0 or slot_index >= 6:
		return false
		
	var root_col = slot_index % 3
	var root_row = slot_index / 3
	
	var is_glass = crate.get("is_glass_prop") == true
	var size_type = "1x1"
	var grid_w = 1
	var grid_h = 1
	
	if not is_glass:
		size_type = crate.get("size_type")
		if size_type == null:
			size_type = "1x1"
		match size_type:
			"1x1":
				grid_w = 1
				grid_h = 1
			"2x1":
				grid_w = 2
				grid_h = 1
			"1x2":
				grid_w = 1
				grid_h = 2
			"2x2":
				grid_w = 2
				grid_h = 2
				
	# Check bounds
	if root_col + grid_w > 3 or root_row + grid_h > 2:
		return false
		
	# Check if all required slots are empty
	for dx in range(grid_w):
		for dy in range(grid_h):
			var idx = (root_col + dx) + (root_row + dy) * 3
			if inventory[idx] != null:
				return false
				
	# All checks passed, fill the slots
	for dx in range(grid_w):
		for dy in range(grid_h):
			var idx = (root_col + dx) + (root_row + dy) * 3
			if dx == 0 and dy == 0:
				inventory[idx] = {
					"type": "glass" if is_glass else "crate",
					"size_type": size_type,
					"color": crate.color,
					"width": crate.width,
					"height": crate.height,
					"health": crate.health if is_glass else 100.0,
					"grid_w": grid_w,
					"grid_h": grid_h,
					"root_slot": slot_index
				}
			else:
				inventory[idx] = {
					"type": "part",
					"root_slot": slot_index
				}
	return true

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
			var local_mouse = to_local(get_global_mouse_position())
			for i in range(6):
				if inventory[i] != null and slot_rects[i].has_point(local_mouse):
					# Find root slot if clicking on a part
					var unload_index = i
					if inventory[i].get("type") == "part":
						unload_index = inventory[i].get("root_slot")
					# Unload crate!
					_unload_slot(unload_index)
					get_viewport().set_input_as_handled()
					break

func _unload_slot(slot_index: int) -> void:
	var item_data = inventory[slot_index]
	if item_data == null:
		return
		
	# Clear all slots occupied by this item
	var root_col = slot_index % 3
	var root_row = slot_index / 3
	var grid_w = item_data.get("grid_w", 1)
	var grid_h = item_data.get("grid_h", 1)
	for dx in range(grid_w):
		for dy in range(grid_h):
			var idx = (root_col + dx) + (root_row + dy) * 3
			inventory[idx] = null
			
	var is_glass = (item_data.get("type") == "glass")
	var scene_path = "res://obstacles/glass.tscn" if is_glass else "res://obstacles/crate.tscn"
	var scene = load(scene_path)
	if scene:
		var new_crate = scene.instantiate()
		new_crate.color = item_data.get("color", Color(0.82, 0.53, 0.28))
		new_crate.width = item_data.get("width", 40.0)
		new_crate.height = item_data.get("height", 40.0)
		if is_glass:
			new_crate.health = item_data.get("health", 100.0)
		else:
			new_crate.size_type = item_data.get("size_type", "1x1")
		
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
