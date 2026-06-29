extends Area2D

# House Type ("delivery" or "racing")
var house_type: String = ""

# Dialogue State
var has_declined := false
var has_accepted := false
var crate_count := 3
var reward_amount := 150

# Delivery Destination State
var is_delivery_target := false
var crates_needed := 0
var crates_delivered := 0
var delivery_reward := 0
var delivery_area: Area2D

# Racing Destination State
var is_racing_target := false
var racing_area: Area2D
var racing_reward := 0

# Font reference
var custom_font: Font


# Particles for Chimney smoke
var smoke_particles: CPUParticles2D

func _ready() -> void:
	# Load font
	if ResourceLoader.exists("res://retro_font.ttf"):
		custom_font = load("res://retro_font.ttf")

	# 1. Setup Collision Area (sensor only, no physics layer collisions)
	# Area2D is naturally a sensor. To receive mouse clicks, we just need a CollisionShape2D.
	var col_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(140, 140)
	col_shape.shape = rect
	# Offset collision shape to align with the house center
	col_shape.position = Vector2(0, -60)
	add_child(col_shape)
	
	# Make sure input pickable is true to detect mouse hover and clicks
	input_pickable = true
	
	# 2. Setup Chimney Smoke Particles
	smoke_particles = CPUParticles2D.new()
	# Position at chimney top
	smoke_particles.position = Vector2(-38, -128)
	smoke_particles.amount = 8
	smoke_particles.lifetime = 2.5
	smoke_particles.preprocess = 1.0
	smoke_particles.randomness = 0.5
	smoke_particles.direction = Vector2(0.3, -1.0)
	smoke_particles.spread = 15.0
	smoke_particles.gravity = Vector2(15, -15) # Drift slightly right and up
	smoke_particles.initial_velocity_min = 10.0
	smoke_particles.initial_velocity_max = 20.0
	smoke_particles.scale_amount_min = 3.0
	smoke_particles.scale_amount_max = 8.0
	
	# Grow smoke over time
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 1.8))
	smoke_particles.scale_amount_curve = curve
	
	# Fade smoke over time
	var ramp = Gradient.new()
	ramp.set_color(0, Color(0.8, 0.8, 0.8, 0.45))
	ramp.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	smoke_particles.color_ramp = ramp
	
	add_child(smoke_particles)
	
	# If house_type is not pre-assigned, randomize it
	if house_type == "":
		var rng_type = RandomNumberGenerator.new()
		rng_type.seed = hash(int(position.x) + 4321)
		house_type = "racing" if rng_type.randf() < 0.5 else "delivery"

	# Reposition smoke or disable it for racing garage
	if house_type == "racing":
		smoke_particles.emitting = false
		smoke_particles.visible = false
	
	# Seeded generation of contract parameters
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(int(position.x) + 4321)
	if house_type == "racing":
		reward_amount = rng.randi_range(200, 350)
	else:
		crate_count = rng.randi_range(2, 5)
		reward_amount = crate_count * rng.randi_range(60, 100)


func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		open_dialogue()

func open_dialogue() -> void:
	if has_accepted:
		return
		
	# Find HUD CanvasLayer under truck
	var hud = get_node_or_null("/root/main/truck/HUD")
	if not hud:
		push_error("House: HUD not found!")
		return
		
	# Check if a dialogue box is already open
	if hud.has_node("DialogueBox"):
		return
		
	var dialogue_script = load("res://ui/dialogue_box.gd")
	if not dialogue_script:
		push_error("House: Failed to load DialogueBox script")
		return
		
	var dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.set_script(dialogue_script)
	
	# Configure dialogue text and options based on current state
	if not has_declined:
		var road = get_node_or_null("/root/main/Road")
		var distance_m = 1800
		if road:
			var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
			var target_chunk = road.call("get_next_house_chunk", current_chunk)
			distance_m = int(abs(target_chunk - current_chunk) * road.get("chunk_width") / 30.0)

		if house_type == "racing":
			var offer_text = "[ STREET RACE ]\n\nDistance: %d meters\nReward: $%d\n\nAccept race challenge?" % [distance_m, reward_amount]
			
			var contract_meta = {
				"type": "racing_contract",
				"reward": reward_amount,
				"distance": distance_m
			}
			
			var on_accept = func():
				print("[House] Racing Contract Accepted: $%d reward" % reward_amount)
				has_accepted = true
				
				# Setup racing target in road script
				if road:
					var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
					if not road.get("used_house_chunks").has(current_chunk):
						road.get("used_house_chunks").append(current_chunk)
					var target_chunk = road.call("get_next_house_chunk", current_chunk)
					road.set("racing_target_chunk", target_chunk)
					road.set("racing_reward", reward_amount)
					road.set("is_racing_active", true)
					road.call("start_racing_event")
					
					# If target chunk is already active, initialize it immediately
					if road.get("active_chunks").has(target_chunk):
						var chunk_data = road.get("active_chunks")[target_chunk]
						if "house" in chunk_data and is_instance_valid(chunk_data.house):
							chunk_data.house.call("setup_racing_target", reward_amount)
							
				dialogue_box.call("close_dialogue")
				
			var on_decline = func():
				has_declined = true
				dialogue_box.call("close_dialogue")
				
			dialogue_box.call("setup", offer_text, [
				{
					"text": "Accept",
					"callback": on_accept
				},
				{
					"text": "Decline",
					"callback": on_decline
				}
			], contract_meta)
		else:
			var offer_text = "[ DELIVERY CONTRACT ]\n\nCrates: %d\nReward: $%d\n\nAccept contract?" % [crate_count, reward_amount]
			
			var contract_meta = {
				"type": "delivery_contract",
				"crates": crate_count,
				"reward": reward_amount,
				"distance": distance_m
			}
			
			var on_accept = func():
				print("[House] Contract Accepted: %d crates, $%d reward" % [crate_count, reward_amount])
				has_accepted = true
				
				# Setup delivery target in road script
				if road:
					var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
					if not road.get("used_house_chunks").has(current_chunk):
						road.get("used_house_chunks").append(current_chunk)
					var target_chunk = road.call("get_next_house_chunk", current_chunk)
					road.set("delivery_target_chunk", target_chunk)
					road.set("delivery_crate_count", crate_count)
					road.set("delivery_crates_delivered", 0)
					road.set("delivery_reward", reward_amount)
					
					# If target chunk is already active, initialize it immediately
					if road.get("active_chunks").has(target_chunk):
						var chunk_data = road.get("active_chunks")[target_chunk]
						if "house" in chunk_data and is_instance_valid(chunk_data.house):
							chunk_data.house.call("setup_delivery_target", crate_count, reward_amount)
							
				spawn_crates(crate_count)
				dialogue_box.call("close_dialogue")
				
			var on_decline = func():
				has_declined = true
				dialogue_box.call("close_dialogue")
				
			dialogue_box.call("setup", offer_text, [
				{
					"text": "Accept",
					"callback": on_accept
				},
				{
					"text": "Decline",
					"callback": on_decline
				}
			], contract_meta)
	else:
		var on_close = func():
			dialogue_box.call("close_dialogue")
			
		var closing_text = "No more races." if house_type == "racing" else "No more orders."
		dialogue_box.call("setup", closing_text, [
			{
				"text": "Close",
				"callback": on_close
			}
		])
		
	hud.add_child(dialogue_box)

func _process(_delta: float) -> void:
	if is_delivery_target or is_racing_target:
		queue_redraw()

func spawn_crates(count: int) -> void:
	var crate_scene = load("res://obstacles/crate.tscn")
	if not crate_scene:
		push_error("House: Crate scene not found!")
		return
		
	var target_x = global_position.x
	var target_y = global_position.y - 450.0
	
	var truck = get_node_or_null("/root/main/truck")
	if truck:
		var active_body = truck.boat if truck.get("is_water_mode_active") else truck.chassis
		if is_instance_valid(active_body):
			target_x = active_body.global_position.x
			target_y = active_body.global_position.y - 450.0
			
	for i in range(count):
		var crate = crate_scene.instantiate()
		
		var offset_x = randf_range(-60.0, 60.0)
		var offset_y = -i * 50.0
		
		var main_scene = get_node_or_null("/root/main")
		if main_scene:
			main_scene.add_child(crate)
		else:
			get_parent().add_child(crate)
			
		crate.global_position = Vector2(target_x + offset_x, target_y + offset_y)
		crate.size_type = "1x1"
		crate.width = 40.0
		crate.height = 40.0
		
		var r_factor = randf_range(-0.05, 0.05)
		crate.color = Color(0.82 + r_factor, 0.53 + r_factor, 0.28)
		
		print("[House] Spawned crate ", i + 1, "/", count, " at ", crate.global_position)

func setup_delivery_target(crates_req: int, reward: int) -> void:
	is_delivery_target = true
	has_accepted = true # Destination house cannot offer orders
	crates_needed = crates_req
	crates_delivered = 0
	delivery_reward = reward
	
	# Connect to current progress if already stored globally
	var road = get_node_or_null("/root/main/Road")
	if road:
		crates_delivered = road.get("delivery_crates_delivered")
		
	# Create Area2D detector
	delivery_area = Area2D.new()
	delivery_area.name = "DeliveryArea"
	
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(240, 80) # Wide landing pad area
	col.shape = rect
	# Align on the road surface relative to house center (which is 0 vertically)
	col.position = Vector2(0, 0)
	delivery_area.add_child(col)
	
	add_child(delivery_area)
	
	# Connect signal
	delivery_area.body_entered.connect(_on_delivery_area_body_entered)
	
	queue_redraw()

func _on_delivery_area_body_entered(body: Node2D) -> void:
	if not is_delivery_target:
		return
	if body.is_in_group("crates"):
		# Ignore if player is currently dragging the crate
		if "is_dragging" in body and body.get("is_dragging"):
			return
			
		# Increment progress both locally and globally
		var road = get_node_or_null("/root/main/Road")
		if road:
			var cur_delivered = road.get("delivery_crates_delivered") + 1
			road.set("delivery_crates_delivered", cur_delivered)
			crates_delivered = cur_delivered
		else:
			crates_delivered += 1
			
		print("[House] Crate delivered! Progress: %d/%d" % [crates_delivered, crates_needed])
		
		# Free the crate
		body.queue_free()
		
		queue_redraw()
		
		if crates_delivered >= crates_needed:
			complete_delivery()

func complete_delivery() -> void:
	print("[House] Delivery complete! Rewarding player with $", delivery_reward)
	
	var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
	if hud_stats:
		hud_stats.call("add_coin", delivery_reward)
		
	is_delivery_target = false
	if is_instance_valid(delivery_area):
		delivery_area.queue_free()
		
	var road = get_node_or_null("/root/main/Road")
	if road:
		road.set("delivery_target_chunk", -1)
		road.set("delivery_crates_delivered", 0)
		var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
		if not road.get("used_house_chunks").has(current_chunk):
			road.get("used_house_chunks").append(current_chunk)
		
	show_completion_dialogue()
	queue_redraw()

func show_completion_dialogue() -> void:
	var hud = get_node_or_null("/root/main/truck/HUD")
	if not hud:
		return
	if hud.has_node("DialogueBox"):
		hud.get_node("DialogueBox").queue_free()
		
	var dialogue_script = load("res://ui/dialogue_box.gd")
	if not dialogue_script:
		return
		
	var dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.set_script(dialogue_script)
	
	var on_ok = func():
		dialogue_box.call("close_dialogue")
		
	dialogue_box.call("setup", "[ CONTRACT COMPLETE ]\n\nAll crates delivered!\nEarned: $%d" % delivery_reward, [
		{
			"text": "Awesome!",
			"callback": on_ok
		}
	])
	hud.add_child(dialogue_box)

func setup_racing_target(reward: int) -> void:
	is_racing_target = true
	has_accepted = true # Destination house cannot offer orders
	racing_reward = reward
	
	# Create Area2D detector
	racing_area = Area2D.new()
	racing_area.name = "RacingArea"
	racing_area.collision_mask = 3
	
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(160, 120) # Landing pad area
	col.shape = rect
	col.position = Vector2(0, -40)
	racing_area.add_child(col)
	
	add_child(racing_area)
	
	# Connect signal
	racing_area.body_entered.connect(_on_racing_area_body_entered)
	
	queue_redraw()

func _on_racing_area_body_entered(body: Node2D) -> void:
	if not is_racing_target:
		return
		
	var truck = get_node_or_null("/root/main/truck")
	if truck and (body == truck.get("chassis") or body == truck.get("boat") or body == truck):
		complete_race(true)
		return
		
	var opponent = get_node_or_null("/root/main/OpponentCar")
	if opponent and (body == opponent or body.get_parent() == opponent):
		complete_race(false)

func complete_race(player_won: bool) -> void:
	print("[House] Race complete! Player won: ", player_won)
	
	if player_won:
		var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
		if hud_stats:
			hud_stats.call("add_coin", racing_reward)
		
	is_racing_target = false
	if is_instance_valid(racing_area):
		racing_area.queue_free()
		
	var road = get_node_or_null("/root/main/Road")
	if road:
		road.set("racing_target_chunk", -1)
		road.set("is_racing_active", false)
		road.call("end_racing_event")
		var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
		if not road.get("used_house_chunks").has(current_chunk):
			road.get("used_house_chunks").append(current_chunk)
		
	show_race_completion_dialogue(player_won)
	queue_redraw()

func show_race_completion_dialogue(player_won: bool) -> void:
	var hud = get_node_or_null("/root/main/truck/HUD")
	if not hud:
		return
	if hud.has_node("DialogueBox"):
		hud.get_node("DialogueBox").queue_free()
		
	var dialogue_script = load("res://ui/dialogue_box.gd")
	if not dialogue_script:
		return
		
	var dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.set_script(dialogue_script)
	
	var on_ok = func():
		dialogue_box.call("close_dialogue")
		
	var dialogue_text = ""
	if player_won:
		dialogue_text = "[ RACE VICTORY ]\n\nYou won the race!\nEarned: $%d" % racing_reward
	else:
		dialogue_text = "[ RACE DEFEAT ]\n\nThe opponent crossed the finish line first!\nBetter luck next time!"
		
	dialogue_box.call("setup", dialogue_text, [
		{
			"text": "Awesome!" if player_won else "OK",
			"callback": on_ok
		}
	], {
		"type": "racing_contract"
	})
	hud.add_child(dialogue_box)

func _draw() -> void:
	if house_type == "racing":
		# Design the racing garage house using premium vector graphics
		
		# Colors
		var wall_color = Color("#20222a")           # Dark industrial slate grey
		var beam_color = Color("#3b3f4d")           # Dark timber / iron beams
		var shutter_color = Color("#7a8296")        # Metallic shutter door base
		var shutter_line_color = Color("#4b505f")   # Darker shutter groove color
		var neon_cyan = Color("#00f0ff")            # Electric blue trim
		var neon_pink = Color("#ff007f")            # Laser pink sign glow
		var hazard_yellow = Color("#ffd200")        # Classic industrial warning yellow
		var hazard_black = Color("#15161a")         # Contrast dark black
		var tire_rubber = Color("#141416")          # Dark tire rubber
		var rim_magenta = Color("#e51b5c")          # Neon magenta alloy wheel
		
		# 1. Main Wall Body (130 wide, 90 tall)
		var wall_rect = Rect2(-65, -90, 130, 90)
		draw_rect(wall_rect, wall_color, true)
		
		# 2. Left and Right Warning Hazard Pillars
		# Left Pillar (-65 to -40), Right Pillar (40 to 65)
		draw_rect(Rect2(-65, -90, 25, 90), hazard_yellow, true)
		draw_rect(Rect2(40, -90, 25, 90), hazard_yellow, true)
		
		# Draw diagonal black stripes on pillars
		var stripe_w = 4.0
		for offset in range(-90, 0, 18):
			draw_line(Vector2(-65, offset), Vector2(-40, offset + 15), hazard_black, stripe_w)
			draw_line(Vector2(40, offset), Vector2(65, offset + 15), hazard_black, stripe_w)
			
		# Outer framing borders
		draw_rect(Rect2(-65, -90, 25, 90), beam_color, false, 2.0)
		draw_rect(Rect2(40, -90, 25, 90), beam_color, false, 2.0)
		
		# 3. Garage Roller Door (center)
		var shutter_rect = Rect2(-40, -60, 80, 60)
		draw_rect(shutter_rect, shutter_color, true)
		# Roller shutter slats (horizontal grooves)
		for y_offset in range(6, 60, 6):
			draw_line(Vector2(-40, -60 + y_offset), Vector2(40, -60 + y_offset), shutter_line_color, 2.0)
		# Shutter door frame border
		draw_rect(shutter_rect, beam_color, false, 3.0)
		
		# 4. Flat Roof with Cyan Neon Light Trim
		draw_rect(Rect2(-72, -98, 144, 8), hazard_black, true)
		draw_line(Vector2(-72, -94), Vector2(72, -94), neon_cyan, 3.0)
		
		# 5. Glowing "RACE" Neon Sign (centered above the door)
		var sign_rect = Rect2(-24, -82, 48, 16)
		draw_rect(sign_rect, hazard_black, true)
		draw_rect(sign_rect, neon_pink, false, 1.5)
		
		var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
		if font_to_use:
			var txt_sz = font_to_use.get_string_size("RACE", HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
			draw_string(font_to_use, Vector2(-txt_sz.x/2.0, -70), "RACE", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, neon_pink)
			
		# 6. Big Tyre on Top of the Roof (centered at Y=-128)
		var tire_center = Vector2(0, -128)
		# Backing radial neon glow
		draw_circle(tire_center, 34.0, Color("#ff007f", 0.22))
		# Outer rubber tire
		draw_circle(tire_center, 28.0, tire_rubber)
		# Outer white ring / lettering accent
		draw_circle(tire_center, 22.0, Color.WHITE, false, 1.2)
		# Magenta alloy rim
		draw_circle(tire_center, 18.0, rim_magenta)
		# Rim spokes (5 stars)
		for i in range(5):
			var angle = i * (TAU / 5.0)
			draw_line(tire_center, tire_center + Vector2(cos(angle) * 18.0, sin(angle) * 18.0), Color.WHITE, 2.0)
		# Center cap
		draw_circle(tire_center, 7.0, tire_rubber)
		
	else:
		# Design the traditional house using premium vector graphics
		
		# Color Palette
		var wall_color = Color(0.88, 0.84, 0.78)         # Warm plaster beige
		var dark_beam_color = Color(0.35, 0.23, 0.15)    # Tudor dark timber beam brown
		var roof_color = Color(0.72, 0.22, 0.12)         # Brick red tiles
		var roof_trim_color = Color(0.48, 0.14, 0.08)    # Darker roof eaves outline
		var door_color = Color(0.45, 0.28, 0.18)         # Warm arched wood door
		var window_glow_color = Color(1.0, 0.85, 0.35)   # Cozy interior light glow
		var chimney_color = Color(0.42, 0.42, 0.45)       # Grey stonework chimney
		
		# 1. Chimney (drawn behind the wall & roof)
		draw_rect(Rect2(-42, -125, 14, 35), chimney_color, true)
		draw_rect(Rect2(-45, -128, 20, 5), chimney_color.darkened(0.2), true) # cap
		
		# 2. Main Wall Body (120 wide, 90 tall)
		var wall_rect = Rect2(-60, -90, 120, 90)
		draw_rect(wall_rect, wall_color, true)
		
		# 3. Traditional Half-Timbered (Tudor) Wood framing Beams
		# Vertical framing
		draw_rect(Rect2(-60, -90, 6, 90), dark_beam_color, true)
		draw_rect(Rect2(54, -90, 6, 90), dark_beam_color, true)
		draw_rect(Rect2(-3, -90, 6, 90), dark_beam_color, true)
		# Horizontal framing
		draw_rect(Rect2(-60, -90, 120, 6), dark_beam_color, true)
		draw_rect(Rect2(-60, -48, 120, 6), dark_beam_color, true)
		draw_rect(Rect2(-60, -6, 120, 6), dark_beam_color, true)
		# Diagonal Tudor braces
		draw_line(Vector2(-60, -90), Vector2(-3, -48), dark_beam_color, 4.0)
		draw_line(Vector2(-3, -90), Vector2(-60, -48), dark_beam_color, 4.0)
		draw_line(Vector2(3, -90), Vector2(60, -48), dark_beam_color, 4.0)
		draw_line(Vector2(60, -90), Vector2(3, -48), dark_beam_color, 4.0)
		
		draw_line(Vector2(-60, -48), Vector2(-3, 0), dark_beam_color, 4.0)
		draw_line(Vector2(-3, -48), Vector2(-60, 0), dark_beam_color, 4.0)
		draw_line(Vector2(3, -48), Vector2(60, 0), dark_beam_color, 4.0)
		draw_line(Vector2(60, -48), Vector2(3, 0), dark_beam_color, 4.0)

		# 4. Triangular Roof
		# Base span (-72 to 72 at y=-90) and apex (0, -135)
		var roof_pts = PackedVector2Array([
			Vector2(-72, -90),
			Vector2(72, -90),
			Vector2(0, -135)
		])
		draw_polygon(roof_pts, PackedColorArray([roof_color]))
		# Overhanging roof eaves
		draw_line(Vector2(-72, -90), Vector2(0, -135), roof_trim_color, 6.0)
		draw_line(Vector2(72, -90), Vector2(0, -135), roof_trim_color, 6.0)
		draw_line(Vector2(-72, -90), Vector2(72, -90), roof_trim_color, 4.0)
		
		# 5. Arched Wooden Door (bottom center)
		var door_center_x = 0
		var door_w = 24.0
		var door_h = 42.0
		var door_y = -door_h
		# Solid body
		draw_rect(Rect2(door_center_x - door_w/2.0, door_y, door_w, door_h), door_color, true)
		draw_circle(Vector2(door_center_x, door_y), door_w/2.0, door_color)
		# Door framing border
		var door_arch_pts = PackedVector2Array()
		for step in range(11):
			var angle = PI + (PI * step / 10.0)
			door_arch_pts.append(Vector2(door_center_x + cos(angle) * door_w/2.0, door_y + sin(angle) * door_w/2.0))
		door_arch_pts.append(Vector2(door_center_x + door_w/2.0, 0))
		door_arch_pts.append(Vector2(door_center_x - door_w/2.0, 0))
		door_arch_pts.append(Vector2(door_center_x - door_w/2.0, door_y))
		draw_polyline(door_arch_pts, dark_beam_color.darkened(0.3), 2.0)
		# Brass doorknob
		draw_circle(Vector2(door_center_x + 7, door_y + door_h/2.0), 2.0, Color(0.9, 0.75, 0.15))
		
		# 6. Glowing Windows (Yellow with pane grids)
		# Left window
		var win_l_rect = Rect2(-42, -36, 20, 20)
		draw_rect(win_l_rect, window_glow_color, true)
		draw_rect(win_l_rect, dark_beam_color, false, 2.0)
		draw_line(Vector2(-32, -36), Vector2(-32, -16), dark_beam_color, 1.5)
		draw_line(Vector2(-42, -26), Vector2(-22, -26), dark_beam_color, 1.5)
		
		# Right window
		var win_r_rect = Rect2(22, -36, 20, 20)
		draw_rect(win_r_rect, window_glow_color, true)
		draw_rect(win_r_rect, dark_beam_color, false, 2.0)
		draw_line(Vector2(32, -36), Vector2(32, -16), dark_beam_color, 1.5)
		draw_line(Vector2(22, -26), Vector2(42, -26), dark_beam_color, 1.5)

		# 7. Attic Circular Window (center of roof gable)
		var attic_pos = Vector2(0, -108)
		draw_circle(attic_pos, 9.0, window_glow_color)
		draw_circle(attic_pos, 9.0, dark_beam_color, false, 2.0)
		draw_line(attic_pos - Vector2(9, 0), attic_pos + Vector2(9, 0), dark_beam_color, 1.5)
		draw_line(attic_pos - Vector2(0, 9), attic_pos + Vector2(0, 9), dark_beam_color, 1.5)

	# 8. Delivery Pad Landing Zone Overlay
	if is_delivery_target:
		var pad_w = 200.0
		var pad_h = 12.0
		# Center on the ground road level (Y=0)
		var pad_rect = Rect2(-pad_w / 2.0, -pad_h / 2.0, pad_w, pad_h)
		
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		var glow_color = Color("#00ff66", 0.2 + 0.15 * pulse)
		var line_color = Color("#00ff66", 0.7 + 0.3 * pulse)
		
		# Draw glowing pad
		draw_rect(pad_rect, glow_color, true)
		draw_rect(pad_rect, line_color, false, 2.0)
		
		# Draw target details
		var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
		if font_to_use:
			var txt = "DELIVER HERE (%d/%d)" % [crates_delivered, crates_needed]
			var txt_size = font_to_use.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			# Draw background label backing for readability
			draw_rect(Rect2(-txt_size.x / 2.0 - 6, -37, txt_size.x + 12, 18), Color(0, 0, 0, 0.6), true)
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, line_color)

	# 9. Racing Finish Zone Overlay
	if is_racing_target:
		var pad_w = 200.0
		var pad_h = 16.0
		# Center on the ground road level (Y=0)
		var pad_rect = Rect2(-pad_w / 2.0, -pad_h / 2.0, pad_w, pad_h)
		
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		var glow_color = Color("#ff007f", 0.2 + 0.15 * pulse)
		var line_color = Color("#ff007f", 0.7 + 0.3 * pulse)
		
		# Draw glowing pad
		draw_rect(pad_rect, glow_color, true)
		draw_rect(pad_rect, line_color, false, 2.0)
		
		# Draw checkered patterns inside the finish line pad
		var check_w = 10.0
		var checkers_y = -pad_h / 2.0
		for x_offset in range(-pad_w / 2.0, pad_w / 2.0, check_w):
			var idx = int((x_offset + pad_w / 2.0) / check_w)
			if idx % 2 == 0:
				draw_rect(Rect2(x_offset, checkers_y, check_w, pad_h / 2.0), Color.WHITE, true)
				draw_rect(Rect2(x_offset + check_w / 2.0, checkers_y + pad_h / 2.0, check_w / 2.0, pad_h / 2.0), Color.WHITE, true)
			else:
				draw_rect(Rect2(x_offset, checkers_y + pad_h / 2.0, check_w, pad_h / 2.0), Color.BLACK, true)
				
		# Draw target details
		var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
		if font_to_use:
			var txt = "FINISH LINE"
			var txt_size = font_to_use.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			# Draw background label backing for readability
			draw_rect(Rect2(-txt_size.x / 2.0 - 6, -37, txt_size.x + 12, 18), Color(0, 0, 0, 0.6), true)
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, line_color)
