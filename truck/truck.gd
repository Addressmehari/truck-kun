extends Node2D

# ─── Driving ────────────────────────────────────────────────────────────────
@export_group("Driving")
## Torque applied when tilting in the air (chassis + container)
@export var air_tilt_power := 6000.0
## Autopilot drive throttle (0–1). Full throttle when < 1.0 reduces top speed.
@export_range(0.1, 1.0, 0.05) var autopilot_throttle := 0.7

# ─── Suspension ─────────────────────────────────────────────────────────────
@export_group("Suspension")
## How far (px) the tyre rests below its anchor point at equilibrium
@export_range(2.0, 40.0, 0.5) var suspension_rest_dist := 10.0
## Spring stiffness — higher = stiffer / less sag
@export_range(10.0, 600.0, 5.0) var suspension_stiffness := 150.0
## Damping — higher = less bounce, more sluggish
@export_range(0.5, 40.0, 0.5) var suspension_damping := 8.0

# ─── Parking ────────────────────────────────────────────────────────────────
@export_group("Parking")
## Speed (km/h) below which parking is allowed
@export_range(0.0, 60.0, 1.0) var park_speed_limit := 20.0
## How long (seconds) O must be held to toggle park/drive
@export_range(0.1, 3.0, 0.05) var park_hold_threshold := 1.0

# ─── Combat / Convoy ─────────────────────────────────────────────────────────
@export_group("Combat")
## Maximum truck health during a convoy event
@export_range(10.0, 500.0, 5.0) var truck_max_health := 100.0
## Damage multiplier (incoming damage is scaled by this before applying)
@export_range(0.0, 1.0, 0.05) var damage_scale := 0.3
## Seconds between enemy spawn waves
@export_range(1.0, 15.0, 0.5) var convoy_spawn_interval := 4.0
## Maximum enemies on-screen at once
@export_range(1, 10) var max_convoy_enemies := 4
## Duration of the post-convoy velocity boost (seconds)
@export_range(0.0, 15.0, 0.5) var boost_duration := 5.0

# ─── Petrol ──────────────────────────────────────────────────────────────────
@export_group("Petrol")
## Litres per second consumed while the truck is driving (at full throttle)
@export_range(0.5, 20.0, 0.5) var petrol_drain_rate: float = 3.0
## Toggle ON to disable petrol consumption — useful for UI testing
@export var unlimited_petrol: bool = false

# ─── Internal runtime state ──────────────────────────────────────────────────
var chassis: RigidBody2D
var container_body: RigidBody2D
var tyre_1: RigidBody2D
var tyre_2: RigidBody2D
var tyre_3: RigidBody2D

@onready var park_btn: Button = $HUD/ShifterPanel/VBox/ParkBtn
@onready var rev_btn: Button = $HUD/ShifterPanel/VBox/RevBtn
@onready var drv_btn: Button = $HUD/ShifterPanel/VBox/DrvBtn
@onready var shifter_panel: PanelContainer = $HUD/ShifterPanel

enum Gear {PARK, DRIVE, REVERSE}
var current_gear: Gear = Gear.DRIVE
var is_e_toggled: bool = false

# Parking with "O" hold logic
var o_hold_time: float = 0.0
var o_trigger_locked: bool = false
var o_hold_start_ticks: int = 0
var is_o_currently_holding: bool = false

# Combat / Convoy Event State
var is_autopilot := false
var truck_health := 100.0
var cheat_buffer := ""
var convoy_spawn_timer := 0.0
var boost_timer := 0.0

var boat: RigidBody2D
var is_water_mode_active := false

func _ready() -> void:
	chassis = get_node_or_null("chassis")
	container_body = get_node_or_null("container_body")
	if chassis:
		tyre_1 = chassis.get_node_or_null("tyre-1")
	if container_body:
		tyre_2 = container_body.get_node_or_null("tyre-2")
		tyre_3 = container_body.get_node_or_null("tyre-3")

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	setup_shifter_ui()
	if shifter_panel:
		shifter_panel.visible = false
	
	# Propagate inspector-tweakable suspension values to child physics bodies
	_apply_exports()
		
	# Instantiate visual parking indicator
	var indicator_script = load("res://truck/parking_indicator.gd")
	if indicator_script:
		var indicator = Node2D.new()
		indicator.set_script(indicator_script)
		indicator.name = "ParkingIndicator"
		indicator.truck = self
		indicator.chassis = chassis
		indicator.container_body = container_body
		add_child(indicator)

func _apply_exports() -> void:
	# Push suspension settings to chassis and container so they match the inspector
	for body in [chassis, container_body]:
		if is_instance_valid(body):
			if "suspension_rest_dist" in body:
				body.suspension_rest_dist = suspension_rest_dist
			if "suspension_stiffness" in body:
				body.suspension_stiffness = suspension_stiffness
			if "suspension_damping" in body:
				body.suspension_damping = suspension_damping

func setup_shifter_ui() -> void:
	# Style Shifter Panel (wooden panel backboard)
	var style_panel = StyleBoxFlat.new()
	style_panel.bg_color = Color(0.24, 0.15, 0.10) # Dark mahogany
	style_panel.border_color = Color(0.35, 0.22, 0.12) # Oak trim
	style_panel.border_width_left = 3
	style_panel.border_width_top = 3
	style_panel.border_width_right = 3
	style_panel.border_width_bottom = 3
	style_panel.corner_radius_top_left = 0
	style_panel.corner_radius_top_right = 0
	style_panel.corner_radius_bottom_left = 0
	style_panel.corner_radius_bottom_right = 0
	shifter_panel.add_theme_stylebox_override("panel", style_panel)
	
	# Connect signals for cursor-only click
	park_btn.pressed.connect(_on_gear_button_pressed.bind(Gear.PARK))
	rev_btn.pressed.connect(_on_gear_button_pressed.bind(Gear.REVERSE))
	drv_btn.pressed.connect(_on_gear_button_pressed.bind(Gear.DRIVE))
	
	update_shifter_visuals()

func update_shifter_visuals() -> void:
	# Active Style (glowing, bright pine wood block)
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.65, 0.46, 0.28) # Warm golden pine
	active_style.border_color = Color(0.92, 0.72, 0.05) # Gold highlight
	active_style.border_width_left = 2
	active_style.border_width_top = 2
	active_style.border_width_right = 2
	active_style.border_width_bottom = 6 # 3D look
	active_style.corner_radius_top_left = 0
	active_style.corner_radius_top_right = 0
	active_style.corner_radius_bottom_left = 0
	active_style.corner_radius_bottom_right = 0
	
	# Inactive Style (flat, dark oak wood block)
	var inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.42, 0.28, 0.15) # Dark oak
	inactive_style.border_color = Color(0.25, 0.15, 0.08)
	inactive_style.border_width_left = 2
	inactive_style.border_width_top = 2
	inactive_style.border_width_right = 2
	inactive_style.border_width_bottom = 2
	inactive_style.corner_radius_top_left = 0
	inactive_style.corner_radius_top_right = 0
	inactive_style.corner_radius_bottom_left = 0
	inactive_style.corner_radius_bottom_right = 0
	
	# Apply overrides
	park_btn.add_theme_stylebox_override("normal", active_style if current_gear == Gear.PARK else inactive_style)
	rev_btn.add_theme_stylebox_override("normal", active_style if current_gear == Gear.REVERSE else inactive_style)
	drv_btn.add_theme_stylebox_override("normal", active_style if current_gear == Gear.DRIVE else inactive_style)
	
	# Color overrides for active/inactive text
	var active_color = Color(1.0, 0.95, 0.8)
	var inactive_color = Color(0.65, 0.55, 0.45)
	
	park_btn.add_theme_color_override("font_color", active_color if current_gear == Gear.PARK else inactive_color)
	rev_btn.add_theme_color_override("font_color", active_color if current_gear == Gear.REVERSE else inactive_color)
	drv_btn.add_theme_color_override("font_color", active_color if current_gear == Gear.DRIVE else inactive_color)
	
	# Hover style
	var hover_style = active_style.duplicate()
	hover_style.bg_color = Color(0.72, 0.52, 0.32)
	
	park_btn.add_theme_stylebox_override("hover", hover_style)
	rev_btn.add_theme_stylebox_override("hover", hover_style)
	drv_btn.add_theme_stylebox_override("hover", hover_style)
	
	# Font sizes
	park_btn.add_theme_font_size_override("font_size", 22)
	rev_btn.add_theme_font_size_override("font_size", 22)
	drv_btn.add_theme_font_size_override("font_size", 22)

func _physics_process(delta: float) -> void:
	var active_body = boat if is_water_mode_active else chassis

	# Simplified driving mechanics:
	# "D" key (and W, UP, RIGHT) drives forward
	# "A" key (and S, DOWN, LEFT) drives backward
	var forward_pressed = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_RIGHT)
	var backward_pressed = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_LEFT)
	
	# Apply dynamic reward velocity boost after convoy event completes
	if boost_timer > 0.0:
		boost_timer -= delta
		forward_pressed = true
		backward_pressed = false
		if current_gear != Gear.DRIVE:
			set_gear(Gear.DRIVE)
	
	if is_autopilot:
		forward_pressed = true
		backward_pressed = false
		if current_gear != Gear.DRIVE:
			set_gear(Gear.DRIVE)
			
		# Handle dynamic enemy spawning during active convoy
		convoy_spawn_timer -= delta
		if convoy_spawn_timer <= 0.0:
			# Roll next spawn delay with a Gaussian distribution (mean=convoy_spawn_interval, deviation=1.2s)
			convoy_spawn_timer = clamp(randfn(convoy_spawn_interval, 1.2), convoy_spawn_interval * 0.5, convoy_spawn_interval * 1.5)
			var active_enemies = 0
			for child in get_parent().get_children():
				if child.is_in_group("enemies") and not child.get("is_exploding"):
					active_enemies += 1
			
			# Roll a wave size (Gaussian mean=3, dev=0.8, clamped 2 to 4) and spawn up to the active limit
			var spawn_count = int(clamp(round(randfn(3.0, 0.8)), 2.0, 4.0))
			for i in range(spawn_count):
				if active_enemies < max_convoy_enemies:
					spawn_single_enemy_car()
					active_enemies += 1
			
	var move_input = 0.0
	var is_braking = false
	
	if forward_pressed and not backward_pressed:
		if current_gear != Gear.PARK:
			move_input = autopilot_throttle if is_autopilot else 1.0
	elif backward_pressed and not forward_pressed:
		if current_gear != Gear.PARK:
			move_input = -1.0
	elif forward_pressed and backward_pressed:
		is_braking = true

	# Long press "O" to park when speed is less than 20 (on speedometer)
	var speed_kmh = active_body.linear_velocity.length() * 0.08 if is_instance_valid(active_body) else 0.0
	var can_park = speed_kmh < park_speed_limit
	
	if can_park and not is_water_mode_active:
		if Input.is_key_pressed(KEY_O):
			if not o_trigger_locked:
				if not is_o_currently_holding:
					is_o_currently_holding = true
					o_hold_start_ticks = Time.get_ticks_msec()
				
				var held_duration = (Time.get_ticks_msec() - o_hold_start_ticks) / 1000.0
				o_hold_time = held_duration
				
				if held_duration >= park_hold_threshold:
					if current_gear == Gear.PARK:
						set_gear(Gear.DRIVE)
					else:
						set_gear(Gear.PARK)
					o_trigger_locked = true
					o_hold_time = 0.0
					is_o_currently_holding = false
		else:
			o_hold_time = 0.0
			is_o_currently_holding = false
			o_trigger_locked = false
	else:
		o_hold_time = 0.0
		is_o_currently_holding = false
		o_trigger_locked = false
		
	# Read user input for air tilting (A/D or Left/Right)
	var tilt_input = 0.0
	if is_autopilot:
		if is_instance_valid(active_body):
			tilt_input = clamp(active_body.rotation * 4.0, -1.0, 1.0)
	else:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			tilt_input -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			tilt_input += 1.0

	# Detect counter-direction braking (quick stop feel)
	var avg_vel = 0.0
	if not is_water_mode_active:
		if is_instance_valid(tyre_1) and is_instance_valid(tyre_2) and is_instance_valid(tyre_3):
			avg_vel = (tyre_1.angular_velocity + tyre_2.angular_velocity + tyre_3.angular_velocity) / 3.0
		if forward_pressed and avg_vel < -5.0:
			is_braking = true
		elif backward_pressed and avg_vel > 5.0:
			is_braking = true

	# ── Petrol gate ───────────────────────────────────────────────────────────
	if not unlimited_petrol:
		var hud_stats = get_node_or_null("HUD/HudStats")
		if hud_stats and "petrol" in hud_stats:
			# Drain fuel proportional to throttle (idle drain at 0.1x rate)
			var speed_factor = clamp(abs(move_input), 0.1, 1.0) if (forward_pressed or backward_pressed) else 0.1
			hud_stats.petrol = maxf(0.0, hud_stats.petrol - petrol_drain_rate * speed_factor * delta)

			# No fuel → cut drive input completely (truck coasts / rolls to a stop)
			if hud_stats.petrol <= 0.0:
				move_input = 0.0
				is_braking = false  # don't force-lock wheels, let it roll naturally

	# Delegate all per-wheel physics to the tyres themselves / boat
	if is_water_mode_active and is_instance_valid(boat):
		boat.drive(move_input, is_braking)
	else:
		_drive_wheels(delta, move_input, is_braking)

	# Locked differential: synchronise wheel speeds after each tyre updates
	if not is_water_mode_active:
		if is_instance_valid(tyre_1) and is_instance_valid(tyre_2) and is_instance_valid(tyre_3):
			var synced = (tyre_1.angular_velocity + tyre_2.angular_velocity + tyre_3.angular_velocity) / 3.0
			tyre_1.angular_velocity = synced
			tyre_2.angular_velocity = synced
			tyre_3.angular_velocity = synced

	# Apply air tilting torque (active in mid-air or balance controls)
	if tilt_input != 0.0 and not is_water_mode_active:
		if is_instance_valid(chassis):
			chassis.apply_torque(-tilt_input * air_tilt_power)
		if is_instance_valid(container_body):
			container_body.apply_torque(-tilt_input * air_tilt_power * 1.5)

## Calls each tyre's drive() method so the wheel handles its own physics.
func _drive_wheels(delta: float, move_input: float, braking: bool) -> void:
	var parked = (current_gear == Gear.PARK)
	var boosting = (boost_timer > 0.0)
	for tyre in [tyre_1, tyre_2, tyre_3]:
		if is_instance_valid(tyre) and tyre.has_method("drive"):
			tyre.drive(delta, move_input, braking, parked, boosting)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var c = char(event.unicode).to_lower()
		if c >= "a" and c <= "z":
			cheat_buffer += c
			if cheat_buffer.length() > 20:
				cheat_buffer = cheat_buffer.substr(cheat_buffer.length() - 20)
				
			if cheat_buffer.ends_with("convoy"):
				cheat_buffer = "" # clear buffer
				print("Cheat activated: convoy!")
				
				# Restart convoy active event if already running
				var existing = get_node_or_null("HUD/EventTimerBar")
				if existing:
					existing.queue_free()
					
				start_active_event("Convoy")
				
				# Spawn UI timer bar countdown HUD
				var timer_script = load("res://ui/event_timer_bar.gd")
				if timer_script:
					var timer_bar = Control.new()
					timer_bar.set_script(timer_script)
					var hud = get_node_or_null("HUD")
					if hud:
						hud.add_child(timer_bar)
						# Roll target distance using Gaussian distribution: mean=550.0, deviation=30.0, clamp[500, 600]
						var u1 = randf()
						if u1 < 0.0001: u1 = 0.0001
						var u2 = randf()
						var norm = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
						var event_dist = clamp(550.0 + norm * 30.0, 500.0, 600.0)
						timer_bar.call("setup", "Convoy", "🚚", Color(0.15, 0.42, 0.85), event_dist)
			
			elif cheat_buffer.ends_with("crusher"):
				cheat_buffer = "" # clear buffer
				print("Cheat activated: crusher!")
				var road = get_node_or_null("/root/main/Road")
				if road and road.has_method("spawn_crusher_on_next_chunk"):
					road.call("spawn_crusher_on_next_chunk")
			elif cheat_buffer.ends_with("house"):
				cheat_buffer = "" # clear buffer
				print("Cheat activated: house!")
				var road = get_node_or_null("/root/main/Road")
				if road and road.has_method("spawn_house_at_player"):
					road.call("spawn_house_at_player")


func _on_gear_button_pressed(gear_type: Gear) -> void:
	set_gear(gear_type)

func set_gear(new_gear: Gear) -> void:
	current_gear = new_gear
	is_e_toggled = (current_gear == Gear.PARK)
	
	if current_gear != Gear.PARK:
		_drop_all_dragging_crates()
	
	update_shifter_visuals()

func _drop_all_dragging_crates() -> void:
	for crate in get_tree().get_nodes_in_group("crates"):
		if crate.get("is_dragging"):
			crate.set("is_dragging", false)
			if crate.has_method("_update_physics_state"):
				crate.call("_update_physics_state")
			if crate.has_method("_check_drop_on_container"):
				crate.call("_check_drop_on_container")

func is_any_crate_dragged_near() -> bool:
	if not is_instance_valid(container_body):
		return false
	for crate in get_tree().get_nodes_in_group("crates"):
		if crate.get("is_dragging"):
			var dist = container_body.global_position.distance_to(crate.global_position)
			if dist < 250.0:
				return true
	return false

func is_zoom_requested() -> bool:
	if is_autopilot:
		return false
	if is_instance_valid(container_body) and container_body.get("backdoor_blocked"):
		return false
	return (current_gear == Gear.PARK) or is_any_crate_dragged_near()

func set_silhouette_mode(enabled: bool, color: Color = Color.BLACK) -> void:
	var mat: ShaderMaterial = null
	if enabled:
		var shader = load("res://road/silhouette.gdshader")
		if shader:
			mat = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("active", true)
			mat.set_shader_parameter("silhouette_color", color)
			
	if is_instance_valid(chassis):
		chassis.material = mat
	if is_instance_valid(container_body):
		container_body.material = mat
		var backdoor_rect = container_body.get_node_or_null("backdoor")
		if backdoor_rect:
			backdoor_rect.material = mat
	if is_instance_valid(tyre_1):
		tyre_1.material = mat
	if is_instance_valid(tyre_2):
		tyre_2.material = mat
	if is_instance_valid(tyre_3):
		tyre_3.material = mat

func set_headlight_enabled(enabled: bool) -> void:
	if is_instance_valid(chassis):
		var beam = chassis.get_node_or_null("HeadlightBeam")
		if beam:
			beam.set("enabled", enabled)

func start_active_event(event_name: String) -> void:
	print("Truck starting active event: ", event_name)
	if event_name == "Convoy":
		is_autopilot = true
		truck_health = truck_max_health
		
		# Force gear to DRIVE to close the backdoor and stop cargo dragging
		set_gear(Gear.DRIVE)
		
		# Notify Road node
		var road = get_node_or_null("/root/main/Road")
		if road and road.has_method("start_active_event"):
			road.call("start_active_event", "Convoy")
		
		# Move camera
		var camera = get_node_or_null("/root/main/Camera2D")
		if camera:
			camera.set("target_horizontal_offset", -250.0)
			
		# Spawn Health Bar on top of truck chassis so it moves physically with the vehicle
		var health_bar_script = load("res://truck/truck_health_bar.gd")
		if health_bar_script and chassis:
			var old_hb = chassis.get_node_or_null("TruckHealthBar")
			if old_hb:
				old_hb.queue_free()
			var hb = Node2D.new()
			hb.set_script(health_bar_script)
			hb.name = "TruckHealthBar"
			chassis.add_child(hb)
			
		# Clean existing enemies
		for child in get_parent().get_children():
			if child.is_in_group("enemies"):
				child.queue_free()
				
		# Spawn initial enemies using dynamic helper with a Gaussian wave size (2-4)
		var initial_count = int(clamp(round(randfn(3.0, 0.8)), 2.0, 4.0))
		for i in range(initial_count):
			spawn_single_enemy_car(i)
			
		convoy_spawn_timer = convoy_spawn_interval

func end_active_event(event_name: String) -> void:
	print("Truck ending active event: ", event_name)
	if event_name == "Convoy":
		is_autopilot = false
		
		# Trigger reward velocity boost
		boost_timer = boost_duration
		
		# Restore camera
		var camera = get_node_or_null("/root/main/Camera2D")
		if camera:
			camera.set("target_horizontal_offset", 220.0)
				
		# Clean up Health Bar
		if chassis:
			var hb = chassis.get_node_or_null("TruckHealthBar")
			if hb:
				hb.queue_free()
			
		# Fade/Clean up remaining enemies
		for child in get_parent().get_children():
			if child.is_in_group("enemies"):
				var tween = child.create_tween()
				tween.tween_property(child, "modulate:a", 0.0, 1.0)
				tween.tween_callback(child.queue_free)

func take_damage(amount: float) -> void:
	if not is_autopilot:
		return
	# Scale damage by inspector-configurable multiplier
	truck_health = max(0.0, truck_health - amount * damage_scale)
	if truck_health <= 0.0:
		# Dramatic explosion shake
		var dashboard = get_node_or_null("HUD/Dashboard")
		if dashboard and "shake_intensity" in dashboard:
			dashboard.shake_intensity = 35.0
			
		# Force end the timer bar UI event early (failed, but no cargo spill)
		var timer_bar = get_node_or_null("HUD/EventTimerBar")
		if timer_bar and timer_bar.has_method("end_event"):
			timer_bar.call("end_event")

func spill_all_cargo() -> void:
	if not container_body:
		return
	for i in range(6):
		var item_data = container_body.inventory[i]
		if item_data != null and item_data.get("type") != "part":
			# Clear inventory slots
			container_body.inventory[i] = null
			var root_col = i % 3
			var root_row = i / 3
			var grid_w = item_data.get("grid_w", 1)
			var grid_h = item_data.get("grid_h", 1)
			for dx in range(grid_w):
				for dy in range(grid_h):
					var idx = (root_col + dx) + (root_row + dy) * 3
					container_body.inventory[idx] = null
					
			# Physically spawn the crate/glass
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
					
				get_parent().add_child(new_crate)
				new_crate.global_position = container_body.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 10))
				
				# Apply physical forces
				if new_crate is RigidBody2D:
					new_crate.linear_velocity = container_body.linear_velocity + Vector2(randf_range(-150, 150), randf_range(-200, -50))
					new_crate.angular_velocity = randf_range(-10, 10)

func spawn_single_enemy_car(slot_index: int = -1) -> void:
	var enemy_scene = load("res://obstacles/enemy_car.tscn")
	if not enemy_scene:
		return
		
	var target_dist = 550.0
	if slot_index >= 0 and slot_index <= 2:
		# Use deterministic spacing for initial spawn layout
		target_dist = 480.0 + slot_index * 70.0
	else:
		# Use Gaussian distribution for dynamic target distances (mean=550.0, deviation=70.0)
		var attempts = 0
		while attempts < 10:
			var candidate = randfn(550.0, 70.0)
			candidate = clamp(candidate, 450.0, 680.0)
			
			# Ensure we are not overlapping too closely with other active enemies
			var too_close = false
			for child in get_parent().get_children():
				if child.is_in_group("enemies") and not child.get("is_exploding"):
					var active_dist = child.get("target_distance")
					if active_dist != null and abs(active_dist - candidate) < 55.0:
						too_close = true
						break
			if not too_close:
				target_dist = candidate
				break
			attempts += 1
			
		if attempts >= 10:
			target_dist = clamp(randfn(550.0, 70.0), 450.0, 680.0)

	var enemy = enemy_scene.instantiate()
	enemy.name = "EnemyCar_Dynamic_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 100)
	enemy.set("target_distance", target_dist)
	
	# Spawn position is behind the screen/player
	var active_body = boat if is_water_mode_active else chassis
	if not is_instance_valid(active_body):
		return
	var spawn_x = active_body.global_position.x - target_dist - 250.0
	var road = get_node_or_null("/root/main/Road")
	var spawn_y = 0.0
	if road and road.has_method("get_road_height"):
		spawn_y = road.call("get_road_height", spawn_x)
		
	get_parent().add_child(enemy)
	enemy.global_position = Vector2(spawn_x, spawn_y)

func set_water_mode(enabled: bool) -> void:
	if is_water_mode_active == enabled:
		return
	is_water_mode_active = enabled
	
	if enabled:
		print("Swapping to Boat vehicle (Water Biome)")
		
		# Capture position/velocity from chassis
		var pos = Vector2.ZERO
		var rot = 0.0
		var lin_vel = Vector2.ZERO
		var ang_vel = 0.0
		if is_instance_valid(chassis):
			pos = chassis.global_position
			rot = chassis.global_rotation
			lin_vel = chassis.linear_velocity
			ang_vel = chassis.angular_velocity
			
		# Completely destroy truck nodes
		if is_instance_valid(chassis):
			chassis.queue_free()
		chassis = null
		tyre_1 = null
		
		if is_instance_valid(container_body):
			container_body.queue_free()
		container_body = null
		tyre_2 = null
		tyre_3 = null
		
		var joint = get_node_or_null("PinJoint2D")
		if joint:
			joint.queue_free()
			
		# Spawn new boat scene
		var boat_scene = load("res://truck/boat.tscn")
		if boat_scene:
			boat = boat_scene.instantiate()
			boat.name = "boat"
			add_child(boat)
			
			boat.global_position = pos
			boat.global_rotation = rot
			boat.linear_velocity = lin_vel
			boat.angular_velocity = ang_vel
			boat.set("is_active", true)
	else:
		print("Swapping to Truck vehicle (Land Biome)")
		
		# Capture position/velocity from boat
		var pos = Vector2.ZERO
		var rot = 0.0
		var lin_vel = Vector2.ZERO
		var ang_vel = 0.0
		if is_instance_valid(boat):
			pos = boat.global_position
			rot = boat.global_rotation
			lin_vel = boat.linear_velocity
			ang_vel = boat.angular_velocity
			
			# Completely destroy boat scene
			boat.queue_free()
		boat = null
		
		# Spawn new truck chassis scene
		var chassis_scene = load("res://truck/chassis.tscn")
		if chassis_scene:
			chassis = chassis_scene.instantiate()
			chassis.name = "chassis"
			add_child(chassis)
			
			chassis.global_position = pos
			chassis.global_rotation = rot
			chassis.linear_velocity = lin_vel
			chassis.angular_velocity = ang_vel
			
			tyre_1 = chassis.get_node_or_null("tyre-1")
			
		# Spawn new container scene
		var container_scene = load("res://truck/container_body.tscn")
		if container_scene:
			container_body = container_scene.instantiate()
			container_body.name = "container_body"
			add_child(container_body)
			
			container_body.global_position = pos + Vector2(1, -1).rotated(rot)
			container_body.global_rotation = rot
			container_body.linear_velocity = lin_vel
			container_body.angular_velocity = ang_vel
			
			tyre_2 = container_body.get_node_or_null("tyre-2")
			tyre_3 = container_body.get_node_or_null("tyre-3")
			
		# Spawn new PinJoint2D
		var joint = PinJoint2D.new()
		joint.name = "PinJoint2D"
		joint.position = Vector2(0, -28)
		add_child(joint)
		
		joint.node_a = joint.get_path_to(chassis)
		joint.node_b = joint.get_path_to(container_body)
		joint.disable_collision = false
		
		# Propagate suspension values to newly spawned chassis and container
		_apply_exports()

	# --- Update HUD, Camera, CoinSpawner references ---
	var active_body = boat if enabled else chassis
	
	var camera = get_node_or_null("/root/main/Camera2D")
	if camera:
		camera.target = active_body
		if enabled:
			camera.set("target_horizontal_offset", 340.0) # Move boat more to the left side of the screen
		else:
			camera.set("target_horizontal_offset", -250.0 if is_autopilot else 220.0)
		
	var coin_spawner = get_node_or_null("/root/main/CoinSpawner")
	if coin_spawner:
		coin_spawner.set("_chassis", active_body)
		
	var hud_stats = get_node_or_null("HUD/HudStats")
	if hud_stats and "chassis" in hud_stats:
		hud_stats.chassis = active_body
		
	var dashboard = get_node_or_null("HUD/Dashboard")
	if dashboard and "chassis" in dashboard:
		dashboard.chassis = active_body
		
	var indicator = get_node_or_null("ParkingIndicator")
	if indicator:
		indicator.chassis = active_body
		indicator.container_body = container_body
