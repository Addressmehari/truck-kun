@tool
extends Area2D

@export var trigger_x := 1800.0:
	set(val):
		trigger_x = val
		position.x = trigger_x
		snap_to_road()

@export var auto_snap_to_road := true:
	set(val):
		auto_snap_to_road = val
		snap_to_road()

var triggered := false
var visual_rotation := 0.0
var pulse_time := 0.0

func snap_to_road() -> void:
	if not auto_snap_to_road or not is_inside_tree():
		return
	var road = get_parent() if get_parent().name == "Road" else get_parent().get_node_or_null("Road")
	if not road and has_node("/root/main/Road"):
		road = get_node("/root/main/Road")
	if road and road.has_method("get_road_height"):
		var target_y = road.call("get_road_height", position.x)
		if position.y != target_y:
			position.y = target_y

func _ready() -> void:
	snap_to_road()
	if Engine.is_editor_hint():
		return
		
	# Connect collision detection
	body_entered.connect(_on_body_entered)
	
	# Setup vertical line trigger collision shape if not already present
	var collision = get_node_or_null("CollisionShape2D")
	if not collision:
		collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(40.0, 600.0)
		collision.shape = shape
		collision.position = Vector2(0, -300) # Centered around road surface level
		add_child(collision)

func _on_body_entered(body: Node2D) -> void:
	if triggered:
		return
	
	# Check if truck body or wheels entered
	if body.name in ["chassis", "container_body"] or body.name.begins_with("tyre"):
		triggered = true
		trigger_event_wheel()

func trigger_event_wheel() -> void:
	# Load the event popup
	var popup_script = load("res://ui/event_wheel_popup.gd")
	if not popup_script:
		return
		
	var popup = Control.new()
	popup.set_script(popup_script)
	popup.name = "EventWheelPopup"
	
	# Connect to event selected signal
	popup.connect("event_selected", _on_event_selected)
	
	# Add to HUD
	var hud = get_node_or_null("/root/main/truck/HUD")
	if hud:
		hud.add_child(popup)
	else:
		get_parent().add_child(popup)

func _on_event_selected(event_name: String) -> void:
	print("Event selected in trigger: ", event_name)
	match event_name:
		"Convoy":
			trigger_convoy_event()
		"Storm":
			trigger_storm_event()
		"Mines":
			trigger_mines_event()
			
	# Queue free after executing the event setup
	# (We don't want the trigger to fire again)
	# Wait a small delay so we don't disrupt popup signals
	await get_tree().create_timer(1.0).timeout
	queue_free()

func trigger_convoy_event() -> void:
	# Spawn a cluster of crates falling from sky ahead of truck
	var crate_scene = load("res://obstacles/crate.tscn")
	if not crate_scene:
		return
		
	var truck = get_node_or_null("/root/main/truck")
	var spawn_base_x = 2200.0
	if truck:
		var chassis = truck.get_node_or_null("chassis")
		if chassis:
			spawn_base_x = chassis.global_position.x + 450.0
			
	var road = get_node_or_null("/root/main/Road")
	
	# Spawn 3 crates with horizontal offsets and random heights
	for i in range(3):
		var x_offset = spawn_base_x + (i * 120.0)
		var road_y = 0.0
		if road and road.has_method("get_road_height"):
			road_y = road.call("get_road_height", x_offset)
			
		var crate = crate_scene.instantiate()
		crate.global_position = Vector2(x_offset, road_y - 300.0 - (i * 50.0))
		
		# Randomize size type to make it visually interesting
		var types = ["1x1", "2x1", "1x2", "2x2"]
		crate.size_type = types[randi() % types.size()]
		
		var main_node = get_node_or_null("/root/main")
		if main_node:
			main_node.add_child(crate)
		else:
			get_parent().add_child(crate)

func trigger_storm_event() -> void:
	# 1. Darken sky background
	var sky = get_node_or_null("/root/main/ParallaxBackground/ParallaxLayer")
	var original_modulate = Color.WHITE
	var sprite = null
	if sky:
		sprite = sky.get_node_or_null("Sprite2D")
		if sprite:
			original_modulate = sprite.modulate
			var tween = create_tween()
			tween.tween_property(sprite, "modulate", Color(0.2, 0.15, 0.35), 1.5)
			
	# 2. Add rain particle effect attached to the camera or truck
	var main_node = get_node_or_null("/root/main")
	if not main_node:
		main_node = get_parent()
	var truck = get_node_or_null("/root/main/truck")
	var parent_to_attach = main_node
	if truck:
		var chassis = truck.get_node_or_null("chassis")
		if chassis:
			parent_to_attach = chassis
			
	var rain = CPUParticles2D.new()
	rain.name = "StormRainParticles"
	rain.amount = 180
	rain.lifetime = 1.5
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(800, 10)
	rain.direction = Vector2(-0.8, 1.0) # Blown by wind leftwards
	rain.spread = 5.0
	rain.gravity = Vector2(0, 150)
	rain.initial_velocity_min = 350.0
	rain.initial_velocity_max = 550.0
	rain.scale_amount_min = 2.0
	rain.scale_amount_max = 4.0
	rain.color = Color(0.65, 0.75, 0.9, 0.5)
	
	# Place high above
	rain.position = Vector2(0, -400)
	parent_to_attach.add_child(rain)
	
	# 3. Storm timer to clean up and restore sky
	var timer = get_tree().create_timer(12.0)
	await timer.timeout
	
	if is_instance_valid(sprite):
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", original_modulate, 2.5)
		
	if is_instance_valid(rain):
		# Fade out rain
		var tween_rain = create_tween()
		tween_rain.tween_property(rain, "modulate:a", 0.0, 2.0)
		await tween_rain.finished
		if is_instance_valid(rain):
			rain.queue_free()

func trigger_mines_event() -> void:
	# Spawn a land mine directly on the road surface ahead of the truck
	var truck = get_node_or_null("/root/main/truck")
	var spawn_x = 2200.0
	if truck:
		var chassis = truck.get_node_or_null("chassis")
		if chassis:
			spawn_x = chassis.global_position.x + 500.0
			
	var road = get_node_or_null("/root/main/Road")
	var road_y = 0.0
	if road and road.has_method("get_road_height"):
		road_y = road.call("get_road_height", spawn_x)
		
	var mine_script = load("res://obstacles/land_mine.gd")
	if not mine_script:
		return
		
	var mine = Area2D.new()
	mine.set_script(mine_script)
	mine.name = "ActiveLandMine"
	mine.global_position = Vector2(spawn_x, road_y)
	
	var main_node = get_node_or_null("/root/main")
	if main_node:
		main_node.add_child(mine)
	else:
		get_parent().add_child(mine)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		snap_to_road()
		
	visual_rotation += delta * 1.8
	pulse_time += delta * 5.0
	queue_redraw()

func _draw() -> void:
	if triggered:
		return
		
	# Large vector spinning wheel representation
	var center = Vector2(0, -55) # Float 55px above road height
	var pulse = sin(pulse_time) * 2.5
	var base_r = 44.0 + pulse
	
	# Define pastel colors & outlines
	var pastel_tire := Color(0.25, 0.28, 0.33)   # Dark slate pastel tyre
	var pastel_rim := Color(0.65, 0.88, 0.82)    # Mint rim face
	var pastel_spoke := Color(0.8, 0.75, 0.95)   # Lavender spokes
	var pastel_hub := Color(0.98, 0.88, 0.65)    # Yellow center hub
	var outline_color := Color(0.1, 0.11, 0.14)  # Deep slate outline
	
	# 1. Draw Outer Tire (filled circle + outline)
	draw_circle(center, base_r, outline_color)
	draw_circle(center, base_r - 3.0, pastel_tire)
	
	# Draw Tire Treads (notches) on the outer rim
	var tread_count := 12
	for t in range(tread_count):
		var angle = visual_rotation + t * (2.0 * PI / tread_count)
		var dir = Vector2(cos(angle), sin(angle))
		var p1 = center + dir * (base_r - 3.0)
		var p2 = center + dir * base_r
		draw_line(p1, p2, outline_color, 4.0)
		
	# 2. Draw Inner Rim face (filled circle + outline)
	draw_circle(center, base_r - 11.0, outline_color)
	draw_circle(center, base_r - 14.0, pastel_rim)
	
	# 3. Draw 6 Spokes inside the rim
	var spoke_r = base_r - 14.0
	for i in range(6):
		var angle = visual_rotation + i * (PI / 3.0)
		var dir = Vector2(cos(angle), sin(angle))
		draw_line(center, center + dir * spoke_r, outline_color, 8.0)
	for i in range(6):
		var angle = visual_rotation + i * (PI / 3.0)
		var dir = Vector2(cos(angle), sin(angle))
		draw_line(center, center + dir * spoke_r, pastel_spoke, 4.0)
		
	# 4. Draw Center Hub
	draw_circle(center, 15.0, outline_color)
	draw_circle(center, 12.0, pastel_hub)
	
	# Inner hub pin
	draw_circle(center, 7.5, outline_color)
	draw_circle(center, 4.5, pastel_spoke)
	
	# Draw label above it in editor
	if Engine.is_editor_hint():
		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(-60, -100), "EVENT WHEEL", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.3, 0.88, 1.0, 0.95))
