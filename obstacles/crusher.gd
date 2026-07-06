extends AnimatableBody2D

# Crusher types
enum CrusherType { CLASSIC, SAWBLADE }
@export var crusher_type: CrusherType = CrusherType.CLASSIC

@export var up_wait_time := 1.5
@export var slam_time := 0.25
@export var down_wait_time := 1.0
@export var rise_time := 0.75
@export var travel_distance := 180.0

var time_elapsed := 0.0
var start_y := 0.0
var initialized := false
var rotation_angle := 0.0

var _chassis: Node2D = null
var truck_node: Node2D = null
var sawblade_visuals: Node2D = null

# Precompiled inner class for sawblade drawing (removes dynamic compilation lag)
class SawbladeVisualsClass extends Node2D:
	var blade_color := Color(0.78, 0.8, 0.83)
	var highlight_color := Color(0.95, 0.96, 0.98)
	var shadow_color := Color(0.38, 0.4, 0.43)
	var core_color := Color(0.12, 0.13, 0.16)
	var hazard_glow := Color(1.0, 0.38, 0.0)

	func _draw() -> void:
		var center := Vector2.ZERO
		var teeth_count := 6
		var outer_radius := 45.0
		var inner_radius := 24.0
		var center_radius := 11.0
		for i in range(teeth_count):
			var angle_start = i * (TAU / teeth_count)
			var angle_tip = angle_start + 0.42
			var angle_dip = (i + 1) * (TAU / teeth_count) - 0.08
			var p_start = center + Vector2(cos(angle_start), sin(angle_start)) * inner_radius
			var p_tip = center + Vector2(cos(angle_tip), sin(angle_tip)) * outer_radius
			var p_dip = center + Vector2(cos(angle_dip), sin(angle_dip)) * inner_radius
			draw_colored_polygon(PackedVector2Array([p_start, p_tip, p_dip]), blade_color)
			draw_polyline(PackedVector2Array([p_start, p_tip]), highlight_color, 2.0)
			draw_polyline(PackedVector2Array([p_tip, p_dip]), shadow_color, 1.2)
		draw_circle(center, inner_radius, blade_color)
		draw_arc(center, inner_radius, 0.0, TAU, 32, shadow_color, 1.8)
		draw_circle(center, center_radius, core_color)
		draw_arc(center, center_radius, 0.0, TAU, 16, Color(0.08, 0.08, 0.12), 2.0)
		draw_circle(center, 4.0, Color(hazard_glow.r, hazard_glow.g, hazard_glow.b, 0.35))
		draw_circle(center, 3.2, hazard_glow)
		draw_circle(center, 1.2, Color.WHITE)

func _ready() -> void:
	# Add to group so we can manage or find crushers easily if needed
	add_to_group("crushers")
	
	# Randomize type: 80% CLASSIC (the box ones), 20% SAWBLADE
	var r = randf()
	if r < 0.80:
		crusher_type = CrusherType.CLASSIC
	else:
		crusher_type = CrusherType.SAWBLADE
	
	# Hide or show flat rectangular block based on type
	var block = get_node_or_null("Block")
	if block:
		block.visible = (crusher_type == CrusherType.CLASSIC)
		
	# Adjust the shaft length to connect perfectly with the visual center of the head
	var shaft = get_node_or_null("Shaft")
	if shaft:
		if crusher_type == CrusherType.CLASSIC:
			shaft.offset_bottom = -40.0
		else:
			shaft.offset_bottom = -20.0
		
	# Update the collision shape to match the selected crusher type
	var col_shape = get_node_or_null("CollisionShape2D")
	if col_shape:
		if crusher_type == CrusherType.CLASSIC:
			# Keep original RectangleShape2D layout
			var rect = RectangleShape2D.new()
			rect.size = Vector2(100.0, 80.0)
			col_shape.shape = rect
			col_shape.position = Vector2.ZERO
		elif crusher_type == CrusherType.SAWBLADE:
			# Circular sawblade collision shape
			var circle = CircleShape2D.new()
			circle.radius = 45.0
			col_shape.shape = circle
			col_shape.position = Vector2.ZERO
			
			# Create static sawblade visual child using precompiled inner class
			var sawblade = SawbladeVisualsClass.new()
			sawblade.name = "SawbladeVisuals"
			add_child(sawblade)
			sawblade_visuals = sawblade

func initialize_crusher_position(spawn_x: float, road_y: float) -> void:
	# Keep bottom alignments touching the road when fully slammed
	global_position = Vector2(spawn_x, road_y - 40.0)
	start_y = global_position.y
	initialized = true

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if not initialized:
		start_y = global_position.y
		initialized = true
		
	# Cache truck reference
	if not is_instance_valid(truck_node):
		truck_node = get_node_or_null("/root/main/truck")
		
	var active_body: Node2D = null
	if is_instance_valid(truck_node):
		active_body = truck_node.boat if truck_node.get("is_water_mode_active") else truck_node.chassis
		
	if is_instance_valid(active_body):
		# Despawn when left far behind the player's active body,
		# but only if the player is actually past the end of the active gauntlet zone
		if global_position.x < active_body.global_position.x - 1200.0:
			var road = get_node_or_null("/root/main/Road")
			var end_x = road.get("crusher_flat_end_x") if road else 0.0
			if end_x == 0.0 or active_body.global_position.x > end_x:
				queue_free()
				return
			
		# Optimization: only check collision if player is near the crusher (within 300.0 px)
		var dist_to_player = abs(global_position.x - active_body.global_position.x)
		if dist_to_player < 300.0:
			# Check if the player is crushed
			if truck_node.has_method("respawn_at_crusher_start") and not truck_node.get("is_respawning"):
				var bodies_to_check = [active_body]
				if not truck_node.get("is_water_mode_active") and is_instance_valid(truck_node.container_body):
					bodies_to_check.append(truck_node.container_body)
					
				for body in bodies_to_check:
					var dx = abs(global_position.x - body.global_position.x)
					var dy = abs(global_position.y - body.global_position.y)
					
					# Get body specific half-sizes
					var body_w = 34.0
					var body_h = 36.0
					if body == truck_node.container_body:
						body_w = 56.0
						body_h = 39.5
					elif truck_node.get("is_water_mode_active"):
						body_w = 40.0
						body_h = 20.0
						
					var crusher_w = 50.0
					var crusher_h = 40.0 if crusher_type == CrusherType.CLASSIC else 45.0
					
					# Check AABB overlap with a small buffer to avoid false triggers
					if dx < (crusher_w + body_w - 5.0) and dy < (crusher_h + body_h - 5.0):
						var is_crushing = false
						if crusher_type == CrusherType.CLASSIC:
							# For classic crusher, it only crushes if the bottom of the crusher block
							# descends below the top of the body (with a small buffer)
							var bottom_y = global_position.y + 40.0
							var body_top_y = body.global_position.y - body_h
							if bottom_y > body_top_y + 10.0:
								is_crushing = true
						else:
							# Sawblade slices/crushes on any overlap
							is_crushing = true
							
						if is_crushing:
							print("[Crusher] Player crushed! Triggering death.")
							if truck_node.has_method("trigger_death"):
								truck_node.call("trigger_death", "CRUSHED!")
							break
		
	# Spin the sawblade angle
	if crusher_type == CrusherType.SAWBLADE:
		if is_instance_valid(sawblade_visuals):
			sawblade_visuals.rotation += delta * 15.0
	
	time_elapsed += delta
	var cycle_duration = up_wait_time + slam_time + down_wait_time + rise_time
	var local_time = fmod(time_elapsed, cycle_duration)
	
	var y_offset := 0.0
	
	if local_time < up_wait_time:
		y_offset = travel_distance
	elif local_time < up_wait_time + slam_time:
		var t = (local_time - up_wait_time) / slam_time
		y_offset = lerp(travel_distance, 0.0, t * t)
	elif local_time < up_wait_time + slam_time + down_wait_time:
		y_offset = 0.0
	else:
		var t = (local_time - (up_wait_time + slam_time + down_wait_time)) / rise_time
		y_offset = lerp(0.0, travel_distance, t * (2.0 - t))
		
	global_position.y = start_y - y_offset
