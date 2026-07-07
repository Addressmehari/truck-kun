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

# Towing Destination State
var is_towing_target := false
var towing_area: Area2D
var towing_reward := 0

# Font reference
var custom_font: Font
var opponent_name: String = ""


# Notification bubble instance
var active_bubble: Control = null

# Particles for Chimney smoke
var smoke_particles: CPUParticles2D

# Responsiveness state
var is_hovered := false
var hover_progress := 0.0
var click_timer := 0.0
var was_ahead := true
var cross_shake_timer := 0.0
var approach_intensity := 0.0
var elapsed_time := 0.0

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
		rng_type.seed = hash(str(position.x) + "_housetype")
		var val = rng_type.randf()
		if val < 0.33:
			house_type = "racing"
		elif val < 0.66:
			house_type = "delivery"
		else:
			house_type = "towing"

	# Reposition smoke or disable it for racing garage and towing station
	if house_type == "racing" or house_type == "towing":
		smoke_particles.emitting = false
		smoke_particles.visible = false
	
	# Seeded generation of contract parameters
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(position.x) + "_houseparams")
	if house_type == "racing":
		reward_amount = rng.randi_range(200, 350)
	elif house_type == "towing":
		reward_amount = rng.randi_range(250, 400)
	else:
		crate_count = rng.randi_range(2, 5)
		reward_amount = crate_count * rng.randi_range(60, 100)
		
	# Connect mouse signals for responsiveness
	mouse_entered.connect(func(): is_hovered = true)
	mouse_exited.connect(func(): is_hovered = false)


func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_timer = 0.25
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
		if opponent_name == "":
			opponent_name = "Kyrie" if randf() < 0.5 else "Hopps"
			
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
				"distance": distance_m,
				"opponent_name": opponent_name
			}
			
			var on_accept = func():
				print("[House] Racing Contract Accepted: $%d reward" % reward_amount)
				has_accepted = true
				if is_instance_valid(active_bubble):
					active_bubble.trigger_accept_vanish()
					active_bubble = null
				
				# Setup racing target in road script
				if road:
					var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
					if not road.get("used_house_chunks").has(current_chunk):
						road.get("used_house_chunks").append(current_chunk)
					var target_chunk = road.call("get_next_house_chunk", current_chunk)
					road.set("racing_target_chunk", target_chunk)
					road.set("racing_reward", reward_amount)
					road.set("is_racing_active", true)
					road.set("active_opponent_name", opponent_name)
					road.call("start_racing_event")
					
					# If target chunk is already active, initialize it immediately
					if road.get("active_chunks").has(target_chunk):
						var chunk_data = road.get("active_chunks")[target_chunk]
						if "house" in chunk_data and is_instance_valid(chunk_data.house):
							chunk_data.house.call("setup_racing_target", reward_amount)
							
				dialogue_box.call("close_dialogue")
				
			var on_decline = func():
				has_declined = true
				if is_instance_valid(active_bubble):
					active_bubble.trigger_decline_vanish()
					active_bubble = null
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
		elif house_type == "towing":
			var offer_text = "[ TOWING CONTRACT ]\n\nDistance: %d meters\nReward: $%d\n\nAccept towing contract?" % [distance_m, reward_amount]
			
			var contract_meta = {
				"type": "towing_contract",
				"reward": reward_amount,
				"distance": distance_m,
				"opponent_name": opponent_name
			}
			
			var on_accept = func():
				print("[House] Towing Contract Accepted: $%d reward" % reward_amount)
				has_accepted = true
				if is_instance_valid(active_bubble):
					active_bubble.trigger_accept_vanish()
					active_bubble = null
				
				# Setup towing target in road script
				if road:
					var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
					if not road.get("used_house_chunks").has(current_chunk):
						road.get("used_house_chunks").append(current_chunk)
					var target_chunk = road.call("get_next_house_chunk", current_chunk)
					road.set("towing_target_chunk", target_chunk)
					road.set("towing_reward", reward_amount)
					road.set("is_towing_active", true)
					
					# Spawn the towed car at the current house position
					if road.has_method("spawn_and_link_towed_car"):
						road.call("spawn_and_link_towed_car", global_position)
					
					# If target chunk is already active, initialize it immediately
					if road.get("active_chunks").has(target_chunk):
						var chunk_data = road.get("active_chunks")[target_chunk]
						if "house" in chunk_data and is_instance_valid(chunk_data.house):
							chunk_data.house.call("setup_towing_target", reward_amount)
							
				dialogue_box.call("close_dialogue")
				
			var on_decline = func():
				has_declined = true
				if is_instance_valid(active_bubble):
					active_bubble.trigger_decline_vanish()
					active_bubble = null
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
				"distance": distance_m,
				"opponent_name": opponent_name
			}
			
			var on_accept = func():
				print("[House] Contract Accepted: %d crates, $%d reward" % [crate_count, reward_amount])
				has_accepted = true
				if is_instance_valid(active_bubble):
					active_bubble.trigger_accept_vanish()
					active_bubble = null
				
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
					road.set("active_opponent_name", opponent_name)
					
					# If target chunk is already active, initialize it immediately
					if road.get("active_chunks").has(target_chunk):
						var chunk_data = road.get("active_chunks")[target_chunk]
						if "house" in chunk_data and is_instance_valid(chunk_data.house):
							chunk_data.house.call("setup_delivery_target", crate_count, reward_amount)
							
				spawn_crates(crate_count)
				dialogue_box.call("close_dialogue")
				
			var on_decline = func():
				has_declined = true
				if is_instance_valid(active_bubble):
					active_bubble.trigger_decline_vanish()
					active_bubble = null
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
			if is_instance_valid(active_bubble):
				active_bubble.trigger_glitch_vanish()
				active_bubble = null
			dialogue_box.call("close_dialogue")
			
		var closing_text = "No more races." if house_type == "racing" else ("No tow jobs." if house_type == "towing" else "No more orders.")
		dialogue_box.call("setup", closing_text, [
			{
				"text": "Close",
				"callback": on_close
			}
		])
		
	hud.add_child(dialogue_box)

func _process(delta: float) -> void:
	if is_delivery_target or is_racing_target or is_towing_target or hover_progress > 0.01 or click_timer > 0.0 or cross_shake_timer > 0.0 or approach_intensity > 0.0:
		queue_redraw()

	if Engine.is_editor_hint():
		return

	elapsed_time += delta

	# Smoothly interpolate hover progress
	var target_hover = 1.0 if is_hovered else 0.0
	hover_progress = lerp(hover_progress, target_hover, delta * 15.0)
	
	# Apply click squish
	var target_scale = Vector2(1.0, 1.0)
	if hover_progress > 0.0:
		target_scale = Vector2(1.0 + hover_progress * 0.05, 1.0 + hover_progress * 0.05)
		
	if click_timer > 0.0:
		click_timer -= delta
		var t = click_timer / 0.25
		target_scale.y -= sin(t * PI) * 0.12
		target_scale.x += sin(t * PI) * 0.08

	# Check truck distance for approach rumble and crossing trigger
	var local_approach_intensity := 0.0
	var truck = get_node_or_null("/root/main/truck")
	if is_instance_valid(truck):
		var active_body = truck.boat if truck.get("is_water_mode_active") else truck.chassis
		if is_instance_valid(active_body):
			var truck_x = active_body.global_position.x
			var dist_x = global_position.x - truck_x
			
			# Ground rumble shake builds up from 600px (20m) down to 0px
			if dist_x > 0.0 and dist_x <= 600.0:
				local_approach_intensity = (600.0 - dist_x) / 600.0 # 0.0 to 1.0
			
			# Handle tracking crossing triggers (supporting multi-cross by reversing)
			if dist_x > 0.0:
				was_ahead = true
			elif dist_x <= 0.0 and was_ahead:
				was_ahead = false
				cross_shake_timer = 1.0
				if is_instance_valid(active_bubble):
					print("[House] Crossed house. Triggering glitch vanish for bubble.")
					active_bubble.trigger_glitch_vanish()
					active_bubble = null

			# Handle screen-space notification bubble spawning
			# 100 meters = 3000 pixels (since 30 pixels = 1 meter)
			if dist_x > 0.0 and dist_x <= 3000.0:
				var should_show = false
				if not has_accepted and not has_declined:
					should_show = true
				elif is_delivery_target or is_racing_target or is_towing_target:
					should_show = true
					
				if should_show and not is_instance_valid(active_bubble):
					var hud = truck.get_node_or_null("HUD")
					if hud:
						active_bubble = HouseNotificationBubble.new()
						active_bubble.house_type = house_type
						active_bubble.house = self
						active_bubble.custom_font = custom_font
						hud.add_child(active_bubble)
						print("[House] Spawned notification bubble for house_type: ", house_type, " at dist: ", dist_x)
			
			if is_instance_valid(active_bubble):
				active_bubble.distance_m = dist_x / 30.0

	approach_intensity = local_approach_intensity

	# Apply shake/rumble physical offsets
	if cross_shake_timer > 0.0:
		cross_shake_timer -= delta
		var t = 1.0 - cross_shake_timer
		# Wobble rotation and wind compression (decaying)
		rotation = sin(t * PI * 10.0) * 0.06 * exp(-t * 3.5)
		var scale_wobble = sin(t * PI * 8.0) * 0.08 * exp(-t * 4.0)
		target_scale.y += scale_wobble
		target_scale.x -= scale_wobble
	elif approach_intensity > 0.0:
		# Approach ground rumble: builds up frequency and amplitude as truck approaches
		var speed_factor = lerp(8.0, 24.0, approach_intensity)
		var amp_factor = approach_intensity * 0.035
		rotation = sin(elapsed_time * speed_factor) * amp_factor
		
		var scale_amp = approach_intensity * 0.04
		target_scale.y += sin(elapsed_time * speed_factor * 1.2) * scale_amp
		target_scale.x -= sin(elapsed_time * speed_factor * 1.2) * scale_amp
	else:
		rotation = 0.0
		
	scale = lerp(scale, target_scale, delta * 20.0)

func _exit_tree() -> void:
	if is_instance_valid(active_bubble):
		active_bubble.queue_free()

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
	var road = get_node_or_null("/root/main/Road")
	var actual_payout = delivery_reward
		
	print("[House] Delivery complete! Payout: $", actual_payout)
	
	var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
	if hud_stats:
		hud_stats.call("add_coin", actual_payout)
		
	is_delivery_target = false
	if is_instance_valid(delivery_area):
		delivery_area.queue_free()
		
	if road:
		road.set("delivery_target_chunk", -1)
		road.set("delivery_crates_delivered", 0)
		var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
		if not road.get("used_house_chunks").has(current_chunk):
			road.get("used_house_chunks").append(current_chunk)
		
	var truck = get_node_or_null("/root/main/truck")
	if truck and truck.has_method("trigger_cinematic_mission_complete"):
		truck.call("trigger_cinematic_mission_complete", "delivery", "Crates successfully delivered! | Earned: $%d" % actual_payout)
	queue_redraw()

func show_delivery_completion_dialogue(payout: int) -> void:
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
	
	var title = "[ DELIVERY COMPLETED ]"
	var desc = "Crates successfully delivered!\n\nEarned full reward:\nReward: $%d" % payout
	var completion_text = "%s\n\n%s" % [title, desc]
	
	var on_ok = func():
		dialogue_box.call("close_dialogue")
		
	dialogue_box.call("setup", completion_text, [
		{
			"text": "Awesome!",
			"callback": on_ok
		}
	], {
		"type": "delivery_complete",
		"reward": payout
	})
	hud.add_child(dialogue_box)

func show_completion_dialogue(player_won: bool, payout: int) -> void:
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
	
	var title = "[ RACE FINISHED: 1st ]" if player_won else "[ RACE FINISHED: 2nd ]"
	var desc = "You won the race!\nEarned full reward:\nReward: $%d" % payout if player_won else "Opponent arrived first!\nEarned 15% compensation:\nReward: $%d" % payout
	var completion_text = "%s\n\n%s" % [title, desc]
	
	var on_ok = func():
		dialogue_box.call("close_dialogue")
		
	dialogue_box.call("setup", completion_text, [
		{
			"text": "Awesome!",
			"callback": on_ok
		}
	], {
		"type": "race_complete",
		"player_won": player_won,
		"reward": payout
	})
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
	var actual_payout = racing_reward
	if not player_won:
		actual_payout = int(racing_reward * 0.15) # 15% reward
		
	print("[House] Race complete! Player won: ", player_won, " Payout: $", actual_payout)
	
	var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
	if hud_stats:
		hud_stats.call("add_coin", actual_payout)
		
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
		
	var truck = get_node_or_null("/root/main/truck")
	if truck and truck.has_method("trigger_cinematic_mission_complete"):
		var stats = "You won the race! | Earned: $%d" % actual_payout if player_won else "Opponent arrived first. | Earned: $%d" % actual_payout
		truck.call("trigger_cinematic_mission_complete", "race", stats)
	queue_redraw()

func show_race_completion_dialogue(player_won: bool, payout: int) -> void:
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
		dialogue_text = "[ RACE FINISHED: 1st ]\n\nYou won the race!\nEarned full reward:\nReward: $%d" % payout
	else:
		dialogue_text = "[ RACE FINISHED: 2nd ]\n\nOpponent arrived first!\nEarned 15% compensation:\nReward: $%d" % payout
		
	dialogue_box.call("setup", dialogue_text, [
		{
			"text": "Awesome!" if player_won else "OK",
			"callback": on_ok
		}
	], {
		"type": "race_complete",
		"player_won": player_won,
		"reward": payout
	})
	hud.add_child(dialogue_box)

func setup_towing_target(reward: int) -> void:
	is_towing_target = true
	has_accepted = true # Destination house cannot offer contracts
	towing_reward = reward
	
	# Create Area2D detector
	towing_area = Area2D.new()
	towing_area.name = "TowingArea"
	towing_area.collision_mask = 3
	
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(200, 100) # Towing drop-off zone
	col.shape = rect
	col.position = Vector2(0, -40)
	towing_area.add_child(col)
	
	add_child(towing_area)
	
	# Connect signal
	towing_area.body_entered.connect(_on_towing_area_body_entered)
	
	queue_redraw()

func _on_towing_area_body_entered(body: Node2D) -> void:
	if not is_towing_target:
		return
		
	# Check if the body entering is the TowedCar
	var main = get_node_or_null("/root/main")
	var towed_car = main.get_node_or_null("TowedCar") if main else null
	
	if is_instance_valid(towed_car) and (body == towed_car or body.get_parent() == towed_car):
		complete_towing()
		return
		
	# Check if the body entering is the player truck, and the TowedCar is close enough (within 350px)
	var truck = get_node_or_null("/root/main/truck")
	if truck and (body == truck.get("chassis") or body == truck.get("boat") or body == truck):
		if is_instance_valid(towed_car) and global_position.distance_to(towed_car.global_position) < 350.0:
			complete_towing()

func complete_towing() -> void:
	print("[House] Towing complete! Payout: $", towing_reward)
	
	var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
	if hud_stats:
		hud_stats.call("add_coin", towing_reward)
		
	is_towing_target = false
	if is_instance_valid(towing_area):
		towing_area.queue_free()
		
	var road = get_node_or_null("/root/main/Road")
	if road:
		road.set("towing_target_chunk", -1)
		road.set("is_towing_active", false)
		if road.has_method("cleanup_towed_car"):
			road.call("cleanup_towed_car")
		var current_chunk = int(floor(global_position.x / road.get("chunk_width")))
		if not road.get("used_house_chunks").has(current_chunk):
			road.get("used_house_chunks").append(current_chunk)
		
	var truck = get_node_or_null("/root/main/truck")
	if truck and truck.has_method("trigger_cinematic_mission_complete"):
		truck.call("trigger_cinematic_mission_complete", "tow job", "Successfully towed vehicle! | Earned: $%d" % towing_reward)
	queue_redraw()

func show_towing_completion_dialogue(payout: int) -> void:
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
		
	dialogue_box.call("setup", "[ TOW COMPLETED ]\n\nSuccessfully towed the vehicle!\nReward: $%d" % payout, [
		{
			"text": "Awesome!",
			"callback": on_ok
		}
	], {
		"type": "towing_complete",
		"reward": payout
	})
	hud.add_child(dialogue_box)

func _draw() -> void:
	# Strobe flash on crossing / approach rumble
	var flash_boost = 1.0
	if cross_shake_timer > 0.0:
		if int(cross_shake_timer * 30.0) % 2 == 0:
			flash_boost = 1.6
	elif approach_intensity > 0.0:
		# Dynamic flickering that increases in speed as the truck gets closer
		var flicker_speed = 0.01 + approach_intensity * 0.03
		var flicker = sin(Time.get_ticks_msec() * flicker_speed)
		if flicker > 0.2:
			# Light up windows slightly on flicker peak
			flash_boost = lerp(1.0, 1.3, approach_intensity)

	if house_type == "racing":
		# Design the racing garage house using premium vector graphics
		# Colors
		var wall_color = Color("#20222a") # Dark industrial slate grey
		var beam_color = Color("#3b3f4d") # Dark timber / iron beams
		var shutter_color = Color("#7a8296") # Metallic shutter door base
		var shutter_line_color = Color("#4b505f") # Darker shutter groove color
		var neon_cyan = Color("#00f0ff").lerp(Color("#e0ffff"), hover_progress * 0.3) * flash_boost # Electric blue trim
		var neon_pink = Color("#ff007f").lerp(Color("#ffb6c1"), hover_progress * 0.3) * flash_boost # Laser pink sign glow
		var hazard_yellow = Color("#ffd200") # Classic industrial warning yellow
		var hazard_black = Color("#15161a") # Contrast dark black
		var tire_rubber = Color("#141416") # Dark tire rubber
		var rim_magenta = Color("#e51b5c") # Neon magenta alloy wheel
		
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
			draw_string(font_to_use, Vector2(-txt_sz.x / 2.0, -70), "RACE", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, neon_pink)
			
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
		
	elif house_type == "towing":
		# Design the towing station house using premium vector graphics
		# Colors
		var wall_color = Color("#2c302e") # Industrial dark green-grey / asphalt
		var trim_color = Color("#ff9f00") # Safety amber/orange
		var roof_color = Color("#5a6268") # Corrugated galvanized steel
		var bay_bg = Color("#1e2120") # Dark interior bay
		var beam_color = Color("#3e4441") # Dark steel structural beams
		var neon_amber = Color("#ffaa00").lerp(Color("#fff5cc"), hover_progress * 0.35) * flash_boost # Flashing light amber glow
		var hazard_yellow = Color("#ffd200") # Yellow warning accents
		var hazard_black = Color("#15161a") # Contrast dark black
		var car_rust = Color("#8a5a44") # Rusty chassis brown-red
		
		# 1. Main Wall Body (140 wide, 85 tall)
		var wall_rect = Rect2(-70, -85, 140, 85)
		draw_rect(wall_rect, wall_color, true)
		
		# 2. Safety Hazard stripes on the foundation/trim (bottom line)
		var stripe_w = 6.0
		var ground_y = 0.0
		draw_rect(Rect2(-70, -8, 140, 8), hazard_yellow, true)
		for x_offset in range(-70, 70, 16):
			var pts = PackedVector2Array([
				Vector2(x_offset, 0),
				Vector2(x_offset + 8, 0),
				Vector2(x_offset - 4, -8),
				Vector2(x_offset - 12, -8)
			])
			draw_polygon(pts, PackedColorArray([hazard_black]))
			
		# 3. Main Work/Service Bay (on the left side)
		var bay_rect = Rect2(-55, -60, 60, 52)
		draw_rect(bay_rect, bay_bg, true)
		# Draw horizontal steel shutter slats partially rolled up
		for y_offset in range(6, 24, 6):
			draw_line(Vector2(-55, -60 + y_offset), Vector2(5, -60 + y_offset), Color("#4b505f"), 2.0)
		draw_rect(bay_rect, beam_color, false, 3.0)
		
		# 4. Service Office/Window (on the right side)
		var office_rect = Rect2(15, -55, 45, 45)
		draw_rect(office_rect, beam_color.lightened(0.1), true)
		# Cozy yellow lighting from office window (brightens on hover)
		var win_rect = Rect2(20, -50, 35, 25)
		var window_glow_color = Color("#ffea79").lerp(Color.WHITE, hover_progress * 0.45) * flash_boost
		draw_rect(win_rect, window_glow_color, true)
		draw_line(Vector2(37.5, -50), Vector2(37.5, -25), beam_color, 1.5)
		draw_line(Vector2(20, -37.5), Vector2(55, -37.5), beam_color, 1.5)
		
		# 5. Sloped Corrugated Roof
		# A slanted industrial roof higher on the left
		var roof_pts = PackedVector2Array([
			Vector2(-78, -85),
			Vector2(78, -85),
			Vector2(72, -96),
			Vector2(-72, -96)
		])
		draw_polygon(roof_pts, PackedColorArray([roof_color]))
		draw_polyline(roof_pts, beam_color, 2.0)
		
		# 6. Flashing Warning Beacon on roof (center of office side at X=37.5)
		var beacon_pos = Vector2(37.5, -96)
		# Beacon base
		draw_rect(Rect2(31.5, -100, 12, 4), Color("#333333"), true)
		# Amber glass
		draw_circle(beacon_pos + Vector2(0, -7), 5.0, neon_amber)
		# Light glow/pulses (flashes faster and glows wider on hover)
		var pulse_speed = 0.008 + hover_progress * 0.007
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * pulse_speed)
		var glow_rad = (18.0 + hover_progress * 10.0) * pulse
		var glow_strength = (0.18 + hover_progress * 0.12) * pulse
		draw_circle(beacon_pos + Vector2(0, -7), glow_rad, Color("#ff9f00", glow_strength))
		
		# 7. Big Tow Hook Sign above the service bay (X=-25, Y=-72)
		var sign_center = Vector2(-25, -72)
		draw_circle(sign_center, 12.0, Color.BLACK)
		draw_circle(sign_center, 12.0, trim_color, false, 2.0)
		# Tow hook graphic inside the sign
		draw_line(sign_center + Vector2(0, -6), sign_center + Vector2(0, 0), Color.WHITE, 2.0)
		draw_arc(sign_center + Vector2(-3, 3), 5.0, -PI / 2.0, PI * 0.8, 12, Color.WHITE, 2.0, true)
		
		# 8. Rusted Wrecked Car outside (X=-95 to -65, Y=0)
		var wreck_x = -95.0
		# Back wheel
		draw_circle(Vector2(wreck_x + 8, -6), 6.0, Color("#15161a"))
		# Front wheel
		draw_circle(Vector2(wreck_x + 24, -6), 6.0, Color("#15161a"))
		# Rusted Car Body
		var car_body = PackedVector2Array([
			Vector2(wreck_x, -6),
			Vector2(wreck_x + 32, -6),
			Vector2(wreck_x + 30, -16),
			Vector2(wreck_x + 22, -16),
			Vector2(wreck_x + 16, -24),
			Vector2(wreck_x + 8, -24),
			Vector2(wreck_x + 4, -16),
			Vector2(wreck_x, -16)
		])
		draw_polygon(car_body, PackedColorArray([car_rust]))
		draw_polyline(car_body, car_rust.darkened(0.4), 1.5)
	else:
		# Design the traditional house using premium vector graphics
		# Color Palette
		var wall_color = Color(0.88, 0.84, 0.78) # Warm plaster beige
		var dark_beam_color = Color(0.35, 0.23, 0.15) # Tudor dark timber beam brown
		var roof_color = Color(0.72, 0.22, 0.12) # Brick red tiles
		var roof_trim_color = Color(0.48, 0.14, 0.08) # Darker roof eaves outline
		var door_color = Color(0.45, 0.28, 0.18) # Warm arched wood door
		var window_glow = Color(1.0, 0.85, 0.35).lerp(Color("#fffbe0"), hover_progress * 0.5) * flash_boost # Cozy interior light glow (heats up on hover)
		var chimney_color = Color(0.42, 0.42, 0.45) # Grey stonework chimney
		
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
		var door_y = - door_h
		# Solid body
		draw_rect(Rect2(door_center_x - door_w / 2.0, door_y, door_w, door_h), door_color, true)
		draw_circle(Vector2(door_center_x, door_y), door_w / 2.0, door_color)
		# Door framing border
		var door_arch_pts = PackedVector2Array()
		for step in range(11):
			var angle = PI + (PI * step / 10.0)
			door_arch_pts.append(Vector2(door_center_x + cos(angle) * door_w / 2.0, door_y + sin(angle) * door_w / 2.0))
		door_arch_pts.append(Vector2(door_center_x + door_w / 2.0, 0))
		door_arch_pts.append(Vector2(door_center_x - door_w / 2.0, 0))
		door_arch_pts.append(Vector2(door_center_x - door_w / 2.0, door_y))
		draw_polyline(door_arch_pts, dark_beam_color.darkened(0.3), 2.0)
		# Brass doorknob
		draw_circle(Vector2(door_center_x + 7, door_y + door_h / 2.0), 2.0, Color(0.9, 0.75, 0.15))
		
		# 6. Glowing Windows (Yellow with pane grids)
		# Left window
		var win_l_rect = Rect2(-42, -36, 20, 20)
		draw_rect(win_l_rect, window_glow, true)
		draw_rect(win_l_rect, dark_beam_color, false, 2.0)
		draw_line(Vector2(-32, -36), Vector2(-32, -16), dark_beam_color, 1.5)
		draw_line(Vector2(-42, -26), Vector2(-22, -26), dark_beam_color, 1.5)
		
		# Right window
		var win_r_rect = Rect2(22, -36, 20, 20)
		draw_rect(win_r_rect, window_glow, true)
		draw_rect(win_r_rect, dark_beam_color, false, 2.0)
		draw_line(Vector2(32, -36), Vector2(32, -16), dark_beam_color, 1.5)
		draw_line(Vector2(22, -26), Vector2(42, -26), dark_beam_color, 1.5)

		# 7. Attic Circular Window (center of roof gable)
		var attic_pos = Vector2(0, -108)
		draw_circle(attic_pos, 9.0, window_glow)
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
		var line_color = Color("#00ff66", 0.7 + 0.3 * pulse)
		
		# Draw solid black shadow pad on ground
		var shadow_rect = Rect2(pad_rect.position + Vector2(3, 3), pad_rect.size)
		draw_rect(shadow_rect, Color.BLACK, true)
		
		# Draw solid delivery landing zone pad
		draw_rect(pad_rect, Color("#00ff66"), true)
		draw_rect(pad_rect, Color.BLACK, false, 3.0)
		
		# Draw target details
		var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
		if font_to_use:
			var txt = "DELIVER HERE (%d/%d)" % [crates_delivered, crates_needed]
			var txt_size = font_to_use.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			var back_rect = Rect2(-txt_size.x / 2.0 - 6, -37, txt_size.x + 12, 18)
			
			# Draw background label shadow
			var shadow_sb = StyleBoxFlat.new()
			shadow_sb.bg_color = Color.BLACK
			shadow_sb.set_corner_radius_all(6)
			draw_style_box(shadow_sb, Rect2(back_rect.position + Vector2(2, 2), back_rect.size))
			
			# Draw solid comic backing box
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color("#1e1e24")
			sb.border_color = Color.BLACK
			sb.set_border_width_all(1.5)
			sb.set_corner_radius_all(6)
			draw_style_box(sb, back_rect)
			
			# Draw text with shadow offset
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24) + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.BLACK)
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, line_color)

	# 9. Racing Finish Zone Overlay
	if is_racing_target:
		var pad_w = 200.0
		var pad_h = 16.0
		# Center on the ground road level (Y=0)
		var pad_rect = Rect2(-pad_w / 2.0, -pad_h / 2.0, pad_w, pad_h)
		
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		var line_color = Color("#ff007f", 0.7 + 0.3 * pulse)
		
		# Draw solid black shadow pad on ground
		var shadow_rect = Rect2(pad_rect.position + Vector2(3, 3), pad_rect.size)
		draw_rect(shadow_rect, Color.BLACK, true)
		
		# Draw checkered patterns inside the finish line pad
		var check_w = 10.0
		var checkers_y = - pad_h / 2.0
		for x_offset in range(-pad_w / 2.0, pad_w / 2.0, check_w):
			var idx = int((x_offset + pad_w / 2.0) / check_w)
			if idx % 2 == 0:
				draw_rect(Rect2(x_offset, checkers_y, check_w, pad_h / 2.0), Color.WHITE, true)
				draw_rect(Rect2(x_offset + check_w / 2.0, checkers_y + pad_h / 2.0, check_w / 2.0, pad_h / 2.0), Color.WHITE, true)
			else:
				draw_rect(Rect2(x_offset, checkers_y + pad_h / 2.0, check_w, pad_h / 2.0), Color.BLACK, true)
				
		# Draw thick black border
		draw_rect(pad_rect, Color.BLACK, false, 3.0)
				
		# Draw target details
		var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
		if font_to_use:
			var txt = "FINISH LINE"
			var txt_size = font_to_use.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			var back_rect = Rect2(-txt_size.x / 2.0 - 6, -37, txt_size.x + 12, 18)
			
			# Draw background label shadow
			var shadow_sb = StyleBoxFlat.new()
			shadow_sb.bg_color = Color.BLACK
			shadow_sb.set_corner_radius_all(6)
			draw_style_box(shadow_sb, Rect2(back_rect.position + Vector2(2, 2), back_rect.size))
			
			# Draw solid comic backing box
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color("#1e1e24")
			sb.border_color = Color.BLACK
			sb.set_border_width_all(1.5)
			sb.set_corner_radius_all(6)
			draw_style_box(sb, back_rect)
			
			# Draw text with shadow offset
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24) + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.BLACK)
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, line_color)

	# 10. Towing Target Zone Overlay
	if is_towing_target:
		var pad_w = 200.0
		var pad_h = 14.0
		var pad_rect = Rect2(-pad_w / 2.0, -pad_h / 2.0, pad_w, pad_h)
		
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		var line_color = Color("#ff9f00", 0.7 + 0.3 * pulse)
		
		# Draw solid black shadow pad on ground
		var shadow_rect = Rect2(pad_rect.position + Vector2(3, 3), pad_rect.size)
		draw_rect(shadow_rect, Color.BLACK, true)
		
		# Draw solid amber towing zone pad
		draw_rect(pad_rect, Color("#ff9f00"), true)
		
		# Draw tow warning stripes inside the pad (solid black comic style)
		var stripe_step = 16.0
		for x_offset in range(-pad_w / 2.0, pad_w / 2.0, stripe_step):
			var pts = PackedVector2Array([
				Vector2(x_offset, -pad_h / 2.0),
				Vector2(x_offset + 8, -pad_h / 2.0),
				Vector2(x_offset - 2, pad_h / 2.0),
				Vector2(x_offset - 10, pad_h / 2.0)
			])
			# Clip the polygon to fit within the pad limits
			var clipped_pts = PackedVector2Array()
			for pt in pts:
				clipped_pts.append(Vector2(clamp(pt.x, -pad_w / 2.0, pad_w / 2.0), pt.y))
			draw_polygon(clipped_pts, PackedColorArray([Color.BLACK]))
			
		# Draw thick black border
		draw_rect(pad_rect, Color.BLACK, false, 3.0)
			
		# Draw target details label
		var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
		if font_to_use:
			var txt = "TOW ZONE"
			var txt_size = font_to_use.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			var back_rect = Rect2(-txt_size.x / 2.0 - 6, -37, txt_size.x + 12, 18)
			
			# Draw background label shadow
			var shadow_sb = StyleBoxFlat.new()
			shadow_sb.bg_color = Color.BLACK
			shadow_sb.set_corner_radius_all(6)
			draw_style_box(shadow_sb, Rect2(back_rect.position + Vector2(2, 2), back_rect.size))
			
			# Draw solid comic backing box
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color("#1e1e24")
			sb.border_color = Color.BLACK
			sb.set_border_width_all(1.5)
			sb.set_corner_radius_all(6)
			draw_style_box(sb, back_rect)
			
			# Draw text with shadow offset
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24) + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.BLACK)
			draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -24), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, line_color)


# ─── Screen Space Notification Bubble Class ──────────────────────────────────
class HouseNotificationBubble extends Control:
	static var active_bubbles: Array = []

	var house_type: String = ""
	var house: Node2D = null
	var distance_m: float = 0.0
	var custom_font: Font = null
	var follow_blend: float = 0.0
	
	var vanish_state := 0 # 0: normal, 1: glitch/crossed, 2: accepted checkmark, 3: declined cross
	var vanish_timer := 0.0
	
	var is_glitching: bool:
		get:
			return vanish_state == 1
	
	var intro_progress := 0.0
	var elapsed_time := 0.0
	var shake_offset := Vector2.ZERO
	
	func _ready() -> void:
		active_bubbles.append(self)
		custom_minimum_size = Vector2(120, 120)
		size = Vector2(120, 120)
		
		# Position initially at the right-side dock (160 pixels from right for larger bubble)
		var screen_size = get_viewport_rect().size
		
		# Calculate Y offset based on position in queue to stack them
		var dock_y = screen_size.y / 2.0 - 120.0
		var idx = active_bubbles.find(self)
		if idx > 0:
			dock_y += idx * 130.0
		position = Vector2(screen_size.x - 160.0, dock_y)
		
		# Set pivot offset for bounce scale animations (centered for 120x120)
		pivot_offset = Vector2(60, 60)
		scale = Vector2.ZERO
		
	func _notification(what: int) -> void:
		if what == NOTIFICATION_EXIT_TREE:
			active_bubbles.erase(self)
		
	func _update_screen_position() -> void:
		if not is_instance_valid(house):
			return
			
		var screen_size = get_viewport_rect().size
		
		# Shift down for subsequent active bubbles in the queue to stack them
		var dock_y = screen_size.y / 2.0 - 120.0
		var idx = active_bubbles.find(self)
		if idx > 0:
			dock_y += idx * 130.0
			
		var dock_pos = Vector2(screen_size.x - 160.0, dock_y)
		
		# Convert house world coordinates to screen/canvas coordinates
		var house_screen_pos = house.get_global_transform_with_canvas().origin
		# Target position directly above the house (shifted left by 50 pixels)
		# For racing houses, float 50 pixels higher (410px offset vs 360px offset)
		var height_offset = -410.0 if house_type == "racing" else -360.0
		var house_pos = Vector2(house_screen_pos.x - 50.0, house_screen_pos.y + height_offset)
		
		# Check if the house is within the screen viewport limits
		var is_on_screen = house_screen_pos.x >= 0.0 and house_screen_pos.x < screen_size.x
		var target_blend = 1.0 if is_on_screen else 0.0
		
		# Smoothly transition the blend factor, but follow position directly to remove trailing lag
		var dt = get_process_delta_time()
		follow_blend = lerp(follow_blend, target_blend, dt * 7.5)
		
		# Calculate actual position by blending from dock to house
		position = dock_pos.lerp(house_pos, follow_blend)
		
	func trigger_glitch_vanish() -> void:
		if not visible:
			# If we are queued and not visible yet, delete immediately to avoid layout stutters
			queue_free()
			return
		if vanish_state == 0:
			vanish_state = 1
			vanish_timer = 0.3
			
	func trigger_accept_vanish() -> void:
		if not visible:
			queue_free()
			return
		if vanish_state == 0:
			vanish_state = 2
			vanish_timer = 0.5
			
	func trigger_decline_vanish() -> void:
		if not visible:
			queue_free()
			return
		if vanish_state == 0:
			vanish_state = 3
			vanish_timer = 0.5
			
	func _process(delta: float) -> void:
		if not visible:
			visible = true
			intro_progress = 0.0 # Trigger clean scale bounce on entry
			
		elapsed_time += delta
		_update_screen_position()
		
		if vanish_state == 0:
			# Alive rotation sway
			rotation = sin(elapsed_time * 3.5) * 0.05
			
			# Dynamic scale up factor when floating over the house (scale up to 1.28x)
			var scale_multiplier = lerp(1.0, 1.28, follow_blend)
			
			if intro_progress < 1.0:
				intro_progress = min(1.0, intro_progress + delta * 2.5) # Scale up over 0.4s
				var t = intro_progress
				var s = 1.0 + 0.35 * sin(t * PI * 2.5) * (1.0 - t)
				scale = Vector2(s, s) * scale_multiplier
			else:
				# Gentle heartbeat scale pulse
				var s = 1.0 + 0.04 * sin(elapsed_time * 4.0)
				scale = Vector2(s, s) * scale_multiplier
		else:
			vanish_timer -= delta
			if vanish_timer <= 0.0:
				queue_free()
				return
			
			var scale_multiplier = lerp(1.0, 1.28, follow_blend)
			if vanish_state == 1:
				# Heavy shake during glitch
				shake_offset = Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
				var gs = vanish_timer / 0.3
				scale = Vector2(gs, gs)
			elif vanish_state == 2:
				# Ticking checkmark scale pulse
				var t = (0.5 - vanish_timer) / 0.5
				var s = 1.0 - t
				if t < 0.3:
					s = 1.0 + sin(t / 0.3 * PI) * 0.25
				scale = Vector2(s, s) * scale_multiplier
				rotation = sin(elapsed_time * 15.0) * 0.02
			elif vanish_state == 3:
				# Heavy shake / rotation for decline
				shake_offset = Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
				var t = (0.5 - vanish_timer) / 0.5
				var s = 1.0 - t
				scale = Vector2(s, s) * scale_multiplier
				rotation = sin(elapsed_time * 20.0) * 0.05
			
		queue_redraw()
		
	func _draw() -> void:
		var glow_color := Color.WHITE
		var bg_color := Color("#1e1e24") # Solid comic dark slate
		match house_type:
			"racing":
				glow_color = Color("#FF2A85") # Hot Sunset Pink/Crimson
			"delivery":
				glow_color = Color("#00F5D4") # Electric Mint Teal
			"towing":
				glow_color = Color("#FF9F1C") # Cyber Apricot Orange
				
		if is_glitching:
			_draw_glitch(glow_color)
		else:
			_draw_chevron(glow_color, Vector2.ZERO, bg_color)

	func _draw_chevron(glow: Color, offset: Vector2, bg: Color) -> void:
		var bob_y = 0.0
		if not is_glitching:
			bob_y = sin(elapsed_time * 5.0) * 5.0
			
		var center = Vector2(60, 60) + offset + Vector2(0.0, bob_y)
		
		# Define chevron corners (scaled for 120x120 control dimensions)
		var p_tl = center + Vector2(-50, -42)
		var p_tr = center + Vector2(24, -42)
		var p_rp = center + Vector2(58, 0)
		var p_br = center + Vector2(24, 42)
		var p_bl = center + Vector2(-50, 42)
		var p_li = center + Vector2(-34, 0)
		var corners = [p_tl, p_tr, p_rp, p_br, p_bl, p_li]
		
		# Generate 36 points for smooth outer perimeter morphing
		var raw_chevron_pts = PackedVector2Array()
		for s in range(6):
			var p1 = corners[s]
			var p2 = corners[(s + 1) % 6]
			for j in range(6):
				raw_chevron_pts.append(p1.lerp(p2, j / 6.0))
				
		var R = 46.0
		var pts = PackedVector2Array()
		for i in range(36):
			var chev_pt = raw_chevron_pts[i]
			var circ_pt = center + (chev_pt - center).normalized() * R
			pts.append(chev_pt.lerp(circ_pt, follow_blend))
		
		# Draw solid body
		draw_colored_polygon(pts, bg)
		
		# Draw thick black outer border (comic style)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 4.0)
		
		# Define inner chevron corners (scaled)
		var inner_corners = [
			center + Vector2(-43, -35),
			center + Vector2(20, -35),
			center + Vector2(49, 0),
			center + Vector2(20, 35),
			center + Vector2(-43, 35),
			center + Vector2(-29, 0)
		]
		
		var raw_inner_pts = PackedVector2Array()
		for s in range(6):
			var p1 = inner_corners[s]
			var p2 = inner_corners[(s + 1) % 6]
			for j in range(6):
				raw_inner_pts.append(p1.lerp(p2, j / 6.0))
				
		var inner_R = R - 9.0
		var inner_pts = PackedVector2Array()
		for i in range(36):
			var chev_inner = raw_inner_pts[i]
			var circ_inner = center + (chev_inner - center).normalized() * inner_R
			inner_pts.append(chev_inner.lerp(circ_inner, follow_blend))
		
		# Draw solid inner accent border
		draw_polyline(inner_pts + PackedVector2Array([inner_pts[0]]), Color(glow.r, glow.g, glow.b, 1.0), 2.2)
		
		# Smooth pointer rotation and fade out
		var screen_size = get_viewport_rect().size
		var dock_x = screen_size.x - 160.0
		var travel_dist = abs(position.x - dock_x)
		var blend = clamp(travel_dist / 80.0, 0.0, 1.0)
		var angle = lerp(0.0, PI / 2.0, blend)
		
		var local_tip = Vector2(57, 0)
		var local_c1 = Vector2(43, -14)
		var local_c2 = Vector2(43, 14)
		
		var tip_rot = local_tip.rotated(angle)
		var c1_rot = local_c1.rotated(angle)
		var c2_rot = local_c2.rotated(angle)
		
		var arrow_pts = PackedVector2Array([
			center + c1_rot,
			center + tip_rot,
			center + c2_rot
		])
		var arrow_alpha = clamp(1.0 - follow_blend, 0.0, 1.0)
		if arrow_alpha > 0.01:
			draw_colored_polygon(arrow_pts, Color(glow.r, glow.g, glow.b, glow.a * arrow_alpha))
			draw_polyline(arrow_pts + PackedVector2Array([arrow_pts[0]]), Color(0, 0, 0, arrow_alpha), 2.5)
		
		if vanish_state == 2:
			# Draw checkmark (ticking)
			var tick_color = Color("#00FF66") if int(elapsed_time * 25.0) % 2 == 0 else Color.WHITE
			var tick_pts = PackedVector2Array([
				center + Vector2(-16, 2),
				center + Vector2(-4, 12),
				center + Vector2(18, -12)
			])
			draw_polyline(tick_pts, tick_color, 6.0, true)
		elif vanish_state == 3:
			# Draw cross (decline)
			var cross_color = Color("#FF2A85") if int(elapsed_time * 25.0) % 2 == 0 else Color.WHITE
			var c_size = 14.0
			draw_line(center + Vector2(-c_size, -c_size), center + Vector2(c_size, c_size), cross_color, 6.0, true)
			draw_line(center + Vector2(c_size, -c_size), center + Vector2(-c_size, c_size), cross_color, 6.0, true)
		else:
			_draw_symbol(glow, center)
		
		# Draw distance label (comic styled bubble tag)
		var dist_text = str(int(distance_m)) + "m"
		var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
		if font_to_use:
			var txt_size = font_to_use.get_string_size(dist_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			var text_pos = Vector2(center.x - txt_size.x / 2.0, center.y + 65)
			
			var back_rect = Rect2(center.x - txt_size.x / 2.0 - 6, center.y + 52, txt_size.x + 12, 18)
			
			var lbl_shadow = StyleBoxFlat.new()
			lbl_shadow.bg_color = Color.BLACK
			lbl_shadow.set_corner_radius_all(6)
			draw_style_box(lbl_shadow, Rect2(back_rect.position + Vector2(2, 2), back_rect.size))
			
			var lbl_sb = StyleBoxFlat.new()
			lbl_sb.bg_color = Color("#1e1e24")
			lbl_sb.border_color = Color.BLACK
			lbl_sb.set_border_width_all(1.5)
			lbl_sb.set_corner_radius_all(6)
			draw_style_box(lbl_sb, back_rect)
			
			draw_string(font_to_use, text_pos + Vector2(1, 1), dist_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.BLACK)
			draw_string(font_to_use, text_pos, dist_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

	func _draw_symbol(glow: Color, center: Vector2) -> void:
		var pulse_scale = 1.0
		if not is_glitching:
			pulse_scale = 1.0 + 0.08 * sin(elapsed_time * 6.0)
			
		match house_type:
			"racing":
				var symbol_color = Color("#FFE3EC") # Lavender blush (matching pink)
				var text_black = Color("#1A0710")
				# Flag pole
				draw_line(center + Vector2(-14, 14) * pulse_scale, center + Vector2(-14, -18) * pulse_scale, symbol_color, 2.5)
				# Checkered flag pattern
				var flag_rect = Rect2(center.x - 14 * pulse_scale, center.y - 18 * pulse_scale, 28 * pulse_scale, 18 * pulse_scale)
				draw_rect(flag_rect, symbol_color, true)
				
				var hw = 14 * pulse_scale
				var hh = 9 * pulse_scale
				draw_rect(Rect2(center.x - hw, center.y - 2 * hh, hw, hh), text_black, true)
				draw_rect(Rect2(center.x, center.y - hh, hw, hh), text_black, true)
				
				draw_rect(flag_rect, glow, false, 1.5)
			"delivery":
				var box_wood_1 = Color("#DDA15E") # Custom Warm Oak
				var box_wood_2 = Color("#BC6C25") # Custom Deep Cedar
				var outline_col = Color("#F4F6F6")
				
				# Crate 1 (bottom left)
				var c1 = Rect2(center.x - 18 * pulse_scale, center.y - 2 * pulse_scale, 16 * pulse_scale, 16 * pulse_scale)
				draw_rect(c1, box_wood_1, true)
				draw_rect(c1, outline_col, false, 1.8)
				draw_line(c1.position, c1.position + c1.size, outline_col, 1.2)
				draw_line(c1.position + Vector2(0, c1.size.y), c1.position + Vector2(c1.size.x, 0), outline_col, 1.2)
				
				# Crate 2 (top right)
				var c2 = Rect2(center.x + 2 * pulse_scale, center.y - 14 * pulse_scale, 16 * pulse_scale, 16 * pulse_scale)
				draw_rect(c2, box_wood_2, true)
				draw_rect(c2, outline_col, false, 1.8)
				draw_line(c2.position, c2.position + c2.size, outline_col, 1.2)
				draw_line(c2.position + Vector2(0, c2.size.y), c2.position + Vector2(c2.size.x, 0), outline_col, 1.2)
			"towing":
				var gold_link = Color("#FFE8A3")
				var silver_link = Color("#E3EAEB")
				var r = 10.0 * pulse_scale
				# Interlocking rings
				draw_arc(center + Vector2(-7, -2) * pulse_scale, r, 0.0, TAU, 16, gold_link, 2.5)
				draw_arc(center + Vector2(7, 2) * pulse_scale, r, 0.0, TAU, 16, silver_link, 2.5)
				draw_arc(center + Vector2(-7, -2) * pulse_scale, r, -PI/4.0, PI*0.75, 16, glow, 1.2)
				draw_arc(center + Vector2(7, 2) * pulse_scale, r, PI*0.75, PI*1.75, 16, glow, 1.2)

	func _draw_glitch(glow: Color) -> void:
		var t = vanish_timer / 0.3
		var shift_x1 = randf_range(-16.0, 16.0) * t
		var shift_y1 = randf_range(-6.0, 6.0) * t
		var shift_x2 = randf_range(-16.0, 16.0) * t
		var shift_y2 = randf_range(-6.0, 6.0) * t
		
		# Custom glitch backdrop color
		var glitch_bg = Color(0.04, 0.05, 0.07, 0.6)
		_draw_chevron(Color(0.0, 0.9, 1.0, 0.7), shift_x1 * Vector2.RIGHT + shift_y1 * Vector2.DOWN, glitch_bg)
		_draw_chevron(Color(1.0, 0.0, 0.8, 0.7), shift_x2 * Vector2.RIGHT + shift_y2 * Vector2.DOWN, glitch_bg)
		_draw_chevron(glow, shake_offset, Color("#121318"))
		
		var slice_count = randi_range(4, 9)
		for i in range(slice_count):
			var sy = randf_range(0.0, 120.0)
			var sh = randf_range(2.0, 10.0)
			var sx = randf_range(-30.0, 30.0)
			var sw = randf_range(30.0, 160.0)
			var col = Color.WHITE
			var r = randf()
			if r < 0.33:
				col = Color("#FF2A85")
			elif r < 0.66:
				col = Color("#00F5D4")
			else:
				col = Color("#FF9F1C")
			
			draw_rect(Rect2(sx + shake_offset.x, sy + shake_offset.y, sw, sh), col, true)
