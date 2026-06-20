@tool
extends AnimatableBody2D

var elevator_length: float = 188.0:
	set(val):
		elevator_length = val
		queue_redraw()
		# Update collision shape rect size if it exists
		var shape_node = get_node_or_null("CollisionShape2D")
		if shape_node:
			var rect = shape_node.shape as RectangleShape2D
			if rect:
				rect.size.x = elevator_length

var is_moving: bool = false:
	set(val):
		if is_moving != val:
			is_moving = val
			queue_redraw()

func _physics_process(_delta: float) -> void:
	# Keep redrawing to update scissor lift angles as position changes
	queue_redraw()

func _draw() -> void:
	# Draw Scissor Lift mechanism from elevator down to ground Y = 0 (parent coordinates)
	var current_height = -position.y # local Y of ground (relative to parent origin Y = 0)
	
	if current_height > 8.0:
		var num_stages = 2
		# Increase stages for larger travel distance
		if current_height > 300.0:
			num_stages = 3
			
		var stage_h = current_height / num_stages
		var w = elevator_length / 4.0 # scissor arm pivot offset
		var beam_color = Color(0.28, 0.28, 0.3)
		var joint_color = Color(0.65, 0.65, 0.7)
		var shadow_color = Color(0.18, 0.18, 0.2)
		
		# Ground base anchoring plate
		draw_rect(Rect2(-w - 20.0, current_height - 6.0, (w + 20.0) * 2.0, 6.0), shadow_color, true)
		
		for i in range(num_stages):
			var y_top = i * stage_h
			var y_bot = (i + 1) * stage_h
			
			# Draw drop shadow for crossing beams
			draw_line(Vector2(-w, y_top) + Vector2(2, 1), Vector2(w, y_bot) + Vector2(2, 1), shadow_color, 7.0)
			draw_line(Vector2(w, y_top) + Vector2(2, 1), Vector2(-w, y_bot) + Vector2(2, 1), shadow_color, 7.0)
			
			# Draw metal crossing beam links
			draw_line(Vector2(-w, y_top), Vector2(w, y_bot), beam_color, 5.0)
			draw_line(Vector2(w, y_top), Vector2(-w, y_bot), beam_color, 5.0)
			
			# Draw connecting pins/joints
			draw_circle(Vector2(-w, y_top), 4.5, joint_color)
			draw_circle(Vector2(w, y_top), 4.5, joint_color)
			draw_circle(Vector2(0.0, (y_top + y_bot)/2.0), 3.5, joint_color)
			
			if i == num_stages - 1:
				draw_circle(Vector2(-w, y_bot), 4.5, joint_color)
				draw_circle(Vector2(w, y_bot), 4.5, joint_color)

	# Draw Elevator Platform structure
	var plat_thick = 12.0
	# Base structural steel starting at road level (Y = 0) and extending downward
	draw_rect(Rect2(-elevator_length / 2.0, 0.0, elevator_length, plat_thick), Color(0.2, 0.2, 0.22), true)
	# Chrome top deck plate flush with road
	draw_rect(Rect2(-elevator_length / 2.0 + 2.0, 0.0, elevator_length - 4.0, 3.0), Color(0.4, 0.4, 0.45), true)
	
	# Draw structural vertical ribbing cuts along side of platform
	var num_ribs = int(elevator_length / 16.0)
	for i in range(num_ribs):
		var rx = -elevator_length / 2.0 + 8.0 + (i * 16.0)
		draw_rect(Rect2(rx - 3.0, 4.0, 6.0, plat_thick - 6.0), Color(0.12, 0.12, 0.14), true)
		
	# Flashing caution lights (beacons) on platform edges while operating
	var beacon_color = Color(0.15, 0.15, 0.18) # off
	if is_moving:
		# Flash rate 4Hz
		var pulse = int(Time.get_ticks_msec() / 250) % 2
		if pulse == 0:
			beacon_color = Color(1.0, 0.65, 0.0) # Warning Amber
			# Glowing halo just above Y = 0
			draw_circle(Vector2(-elevator_length/2.0 + 8.0, -4.0), 8.0, Color(1.0, 0.65, 0.0, 0.25))
			draw_circle(Vector2(elevator_length/2.0 - 8.0, -4.0), 8.0, Color(1.0, 0.65, 0.0, 0.25))
			
	# Left beacon casing + dome
	draw_rect(Rect2(-elevator_length/2.0 + 5.0, -4.0, 6.0, 4.0), Color(0.1, 0.1, 0.12), true)
	draw_circle(Vector2(-elevator_length/2.0 + 8.0, -4.0), 3.0, beacon_color)
	# Right beacon casing + dome
	draw_rect(Rect2(elevator_length/2.0 - 11.0, -4.0, 6.0, 4.0), Color(0.1, 0.1, 0.12), true)
	draw_circle(Vector2(elevator_length/2.0 - 8.0, -4.0), 3.0, beacon_color)
