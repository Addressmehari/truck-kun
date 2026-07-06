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

# ─── Dislocation Death ───────────────────────────────────────────────────────
@export_group("Dislocation Death")
## Enable dislocation death detection (if wheels/container separate too far)
@export var dislocation_death_enabled: bool = true
## Maximum distance (pixels) a wheel/trailer can deviate from its socket before triggering death
@export var max_dislocation_distance: float = 110.0

# ─── Visual Overrides ───────────────────────────────────────────────────────
@export_group("Visual Overrides")
## Enable silhouette mode on startup
@export var is_silhouette := false
## Custom color for the silhouette
@export var silhouette_color := Color.BLACK

# ─── Internal runtime state ──────────────────────────────────────────────────
var chassis: RigidBody2D
var controls_locked: bool = false
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
var is_in_tunnel_transition := false
var is_exiting_tunnel_transition := false
var is_debug_display_active := false
var tunnel_target_x := 0.0
var has_completed_journey := false
var is_cinematic_mission_complete := false
var cinematic_top_bar: ColorRect = null
var cinematic_bottom_bar: ColorRect = null
var truck_health := 100.0
var cheat_buffer := ""
var convoy_spawn_timer := 0.0
var boost_timer := 0.0

var boat: RigidBody2D
var is_water_mode_active := false

# ─── Death / Retry State ──────────────────────────────────────────────────────
var is_dead := false
var _flip_death_timer   := 0.0   # seconds chassis has been upside-down
var _fuel_empty_timer   := 0.0   # seconds fuel has been at 0
const FLIP_DEATH_DELAY  := 3.0   # upside-down for this long = death
const FUEL_DEATH_DELAY  := 2.5   # empty for this long = death
var _dislocation_grace_timer := 1.0 # grace period timer (seconds) to prevent dislocation checks on spawns/transitions

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

	if is_silhouette:
		set_silhouette_mode(true, silhouette_color)

	# Initialize mock tunnel visibility and exit autopilot on biome transitions
	var gs = get_node_or_null("/root/GameState")
	var mock_tunnel = get_parent().get_node_or_null("MockTunnel")
	if mock_tunnel:
		if gs and gs.get("is_biome_transition") == true:
			mock_tunnel.visible = true
		else:
			# Hide mock tunnel at start of game
			mock_tunnel.visible = false
			
	if gs and gs.get("is_biome_transition") == true:
		start_tunnel_exit_transition()
		gs.set("is_biome_transition", false)

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
	if _dislocation_grace_timer > 0.0:
		_dislocation_grace_timer -= delta

	var active_body = boat if is_water_mode_active else chassis

	var forward_pressed = false
	var backward_pressed = false
	var is_braking = false
	
	if not controls_locked:
		forward_pressed = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_RIGHT)
		backward_pressed = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_LEFT)
	
	if is_in_tunnel_transition:
		var current_px = active_body.global_position.x if is_instance_valid(active_body) else 0.0
		# Trigger scene transition when player drives past the center of the tunnel
		if current_px >= tunnel_target_x:
			is_in_tunnel_transition = false
			controls_locked = true
			forward_pressed = false
			backward_pressed = false
			is_braking = true
			
			# Zero out linear and angular velocities to stop the truck completely
			if is_instance_valid(chassis):
				chassis.linear_velocity = Vector2.ZERO
				chassis.angular_velocity = 0.0
			if is_instance_valid(boat):
				boat.linear_velocity = Vector2.ZERO
				boat.angular_velocity = 0.0
			if is_instance_valid(container_body):
				container_body.linear_velocity = Vector2.ZERO
				container_body.angular_velocity = 0.0
			if is_instance_valid(tyre_1):
				tyre_1.linear_velocity = Vector2.ZERO
				tyre_1.angular_velocity = 0.0
			if is_instance_valid(tyre_2):
				tyre_2.linear_velocity = Vector2.ZERO
				tyre_2.angular_velocity = 0.0
			if is_instance_valid(tyre_3):
				tyre_3.linear_velocity = Vector2.ZERO
				tyre_3.angular_velocity = 0.0
				
			if not has_completed_journey:
				has_completed_journey = true
				var gs = get_node_or_null("/root/GameState")
				if gs:
					var hud_stats = get_node_or_null("HUD/HudStats")
					if hud_stats:
						gs.carryover_coins = hud_stats.coins
						gs.carryover_distance_m = hud_stats.get("_distance_m")
						gs.is_continuing = true
						gs.is_biome_transition = true
					
					# Assign a new random seed for the next scene
					gs.pending_road_seed = randi()
				
				# Roll a 50/50 dice to select between Grass (main.tscn) and Silhouette (silhouette_main.tscn)
				var target_scene = "res://main.tscn"
				if randf() < 0.5:
					target_scene = "res://silhouette_main.tscn"
				
				if gs:
					gs.transition_to_scene(target_scene)
				else:
					get_tree().change_scene_to_file(target_scene)
	elif is_exiting_tunnel_transition:
		var current_px = active_body.global_position.x if is_instance_valid(active_body) else 0.0
		# Once the player drives the truck out of the mock tunnel
		if current_px >= 800.0:
			is_exiting_tunnel_transition = false
			stop_tunnel_transition()
	
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
	
	if controls_locked:
		is_braking = true
	else:
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
	if not controls_locked:
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

	# ── Death checks (skip during convoy/autopilot/tunnel events) ─────────────
	if not is_autopilot and not is_in_tunnel_transition and not is_exiting_tunnel_transition and not is_dead:
		_check_death(delta)

	# ── Debug Tunnel Distance Display ─────────────────────────────────────────
	var hud = get_node_or_null("HUD")
	if hud:
		if is_debug_display_active:
			var label = hud.get_node_or_null("DebugTunnelLabel")
			if not label:
				label = Label.new()
				label.name = "DebugTunnelLabel"
				label.anchor_left = 1.0
				label.anchor_right = 1.0
				label.anchor_top = 0.0
				label.anchor_bottom = 0.0
				label.offset_left = -320
				label.offset_right = -20
				label.offset_top = 20
				label.offset_bottom = 60
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				label.add_theme_font_size_override("font_size", 20)
				label.add_theme_color_override("font_shadow_color", Color.BLACK)
				label.add_theme_constant_override("shadow_offset_x", 2)
				label.add_theme_constant_override("shadow_offset_y", 2)
				hud.add_child(label)
			
			var road = get_node_or_null("/root/main/Road")
			var player_x = active_body.global_position.x if is_instance_valid(active_body) else 0.0
			var target_tunnel_x = INF
			
			if road:
				# 1. First, check if there's any already spawned tunnel ahead of us
				var tunnel_positions = road.get("_tunnel_positions")
				if tunnel_positions is Array:
					for tx in tunnel_positions:
						if tx > player_x:
							target_tunnel_x = min(target_tunnel_x, tx)
				
				# 2. If no spawned tunnel is ahead, estimate when the upcoming tunnel will spawn
				if target_tunnel_x == INF:
					var plan_x = road.get("next_planned_tunnel_x")
					if plan_x is float:
						var tunnel_is_queued = road.get("_tunnel_is_queued") == true
						var mission_active = road.call("is_mission_or_event_active") == true
						var chunk_width = road.get("chunk_width") if road.get("chunk_width") != null else 3000.0
						
						if tunnel_is_queued or (mission_active and player_x + 4500.0 >= plan_x):
							var dest_x = road.call("_get_active_mission_destination_x")
							if dest_x > 0.0:
								# Spawns after mission ends plus 300m safety gap + view distance
								var estimated_x = dest_x + 9000.0 + 4500.0
								var chunk_idx = int(ceil(estimated_x / chunk_width))
								target_tunnel_x = (chunk_idx + 0.5) * chunk_width
							else:
								var mission_end_x = road.get("_mission_end_x")
								if mission_end_x is float and mission_end_x > 0.0:
									var estimated_x = mission_end_x + 9000.0 + 4500.0
									var chunk_idx = int(ceil(estimated_x / chunk_width))
									target_tunnel_x = (chunk_idx + 0.5) * chunk_width
						
						# Fallback to standard planned coordinate if not queued
						if target_tunnel_x == INF:
							var chunk_idx = int(round(plan_x / chunk_width))
							target_tunnel_x = (chunk_idx + 0.5) * chunk_width
			
			if target_tunnel_x == INF or target_tunnel_x <= player_x:
				label.text = "Tunnel: -- m"
			else:
				var dist_meters = int(round((target_tunnel_x - player_x) / 30.0))
				label.text = "Tunnel: %d m" % dist_meters
		else:
			var label = hud.get_node_or_null("DebugTunnelLabel")
			if label:
				label.queue_free()

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
			elif cheat_buffer.ends_with("stats"):
				cheat_buffer = ""
				is_debug_display_active = not is_debug_display_active
				print("Cheat activated: debug tunnel distance (Active: ", is_debug_display_active, ")")
			
			elif cheat_buffer.ends_with("crusher"):
				cheat_buffer = "" # clear buffer
				print("Cheat activated: crusher!")
				var road = get_node_or_null("/root/main/Road")
				if road and road.has_method("spawn_crusher_on_next_chunk"):
					road.call("spawn_crusher_on_next_chunk")
			elif cheat_buffer.ends_with("housetow"):
				cheat_buffer = "" # clear buffer
				print("Cheat activated: housetow!")
				var road = get_node_or_null("/root/main/Road")
				if road and road.has_method("spawn_tow_house_at_player"):
					road.call("spawn_tow_house_at_player")
			elif cheat_buffer.ends_with("house"):
				# Debounce "house" cheat to allow typing "housetow" without instant trigger
				var current_seq = cheat_buffer
				get_tree().create_timer(0.35).timeout.connect(func():
					if cheat_buffer == current_seq:
						cheat_buffer = "" # clear buffer
						print("Cheat activated: house!")
						var road = get_node_or_null("/root/main/Road")
						if road and road.has_method("spawn_house_at_player"):
							road.call("spawn_house_at_player")
				)
			elif cheat_buffer.ends_with("mystery"):
				cheat_buffer = "" # clear buffer
				print("Cheat activated: mystery!")
				var road = get_node_or_null("/root/main/Road")
				if road and road.has_method("spawn_mystery_box_at_player"):
					road.call("spawn_mystery_box_at_player")


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
		# Dramatic explosion shake first
		var dashboard = get_node_or_null("HUD/Dashboard")
		if dashboard and "shake_intensity" in dashboard:
			dashboard.shake_intensity = 35.0

		# End the timer bar UI immediately
		var timer_bar = get_node_or_null("HUD/EventTimerBar")
		if timer_bar and timer_bar.has_method("end_event"):
			timer_bar.call("end_event")

		# Brief pause so the shake registers visually, then trigger death.
		# trigger_death() guards against double-calls via is_dead, so it's safe
		# even if called while the convoy-end cleanup is still running.
		get_tree().create_timer(0.45).timeout.connect(func():
			trigger_death("CONVOY DESTROYED")
		)

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
			
		# Disable collision immediately on chassis, container_body, tyres
		if is_instance_valid(chassis):
			chassis.collision_layer = 0
			chassis.collision_mask = 0
			var t1 = chassis.get_node_or_null("tyre-1")
			if is_instance_valid(t1):
				t1.collision_layer = 0
				t1.collision_mask = 0
			chassis.queue_free()
		chassis = null
		tyre_1 = null
		
		if is_instance_valid(container_body):
			container_body.collision_layer = 0
			container_body.collision_mask = 0
			var t2 = container_body.get_node_or_null("tyre-2")
			if is_instance_valid(t2):
				t2.collision_layer = 0
				t2.collision_mask = 0
			var t3 = container_body.get_node_or_null("tyre-3")
			if is_instance_valid(t3):
				t3.collision_layer = 0
				t3.collision_mask = 0
			container_body.queue_free()
		container_body = null
		tyre_2 = null
		tyre_3 = null
		
		var joint = get_node_or_null("PinJoint2D")
		if joint:
			joint.queue_free()
			
		# Align boat Y coordinate to the water surface
		var road = get_node_or_null("/root/main/Road")
		if road and road.has_method("get_road_height"):
			var road_y = road.call("get_road_height", pos.x)
			pos.y = road_y - 10.0
			
		rot = clamp(rot, -0.4, 0.4)
			
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
		_dislocation_grace_timer = 1.0
		
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
			
			# Disable collision immediately on transition to prevent overlapping forces
			boat.collision_layer = 0
			boat.collision_mask = 0
			boat.queue_free()
		boat = null
		
		# Align truck height to the new land road height to prevent spawning inside it or falling
		var road = get_node_or_null("/root/main/Road")
		if road and road.has_method("get_road_height"):
			var road_y = road.call("get_road_height", pos.x)
			pos.y = road_y - 40.0
			
		rot = clamp(rot, -0.4, 0.4)
		
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
			
		# Spawn new PinJoint2D at the correct world space pivot position
		var joint = PinJoint2D.new()
		joint.name = "PinJoint2D"
		add_child(joint)
		joint.global_position = pos + Vector2(1, -28).rotated(rot)
		
		joint.node_a = joint.get_path_to(chassis)
		joint.node_b = joint.get_path_to(container_body)
		joint.disable_collision = false
		
		# Propagate suspension values to newly spawned chassis and container
		_apply_exports()
		
	# Re-link towed vehicle if towing is active
	var road_ref = get_node_or_null("/root/main/Road")
	if road_ref and road_ref.has_method("relink_towed_car"):
		road_ref.call("relink_towed_car")

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


var is_respawning := false

## ─── Death Detection ──────────────────────────────────────────────────────────

func _check_death(delta: float) -> void:
	var active_body = boat if is_water_mode_active else chassis
	if not is_instance_valid(active_body):
		return

	# ── Flip detection (land only; boats naturally right themselves) ────────────
	if not is_water_mode_active:
		# abs(rotation) > 90 degrees (~1.57 rad) means substantially flipped
		var rot_abs = abs(fmod(active_body.global_rotation, TAU))
		# Normalise to [0, PI] so both ±180 map to the same range
		if rot_abs > PI:
			rot_abs = TAU - rot_abs
		if rot_abs > 1.65:  # ~95 degrees — clearly upside-down
			_flip_death_timer += delta
			if _flip_death_timer >= FLIP_DEATH_DELAY:
				trigger_death("FLIPPED!")
				return
		else:
			_flip_death_timer = 0.0

	# ── Out of fuel detection ─────────────────────────────────────────────────
	var hud_stats = get_node_or_null("HUD/HudStats")
	if hud_stats and "petrol" in hud_stats:
		if hud_stats.petrol <= 0.0:
			_fuel_empty_timer += delta
			if _fuel_empty_timer >= FUEL_DEATH_DELAY:
				trigger_death("OUT OF FUEL")
				return
		else:
			_fuel_empty_timer = 0.0

	# ── Dislocation detection (land only) ─────────────────────────────────────
	if not is_water_mode_active and dislocation_death_enabled and _dislocation_grace_timer <= 0.0 and not is_respawning:
		var dislocated := false
		var cause := "TRUCK DISLOCATED"

		if is_instance_valid(chassis):
			# 1. Check Container/Trailer connection
			if is_instance_valid(container_body):
				var anchor_chassis = chassis.to_global(Vector2(1, -28))
				var anchor_container = container_body.to_global(Vector2(0, -27))
				var dev_c = anchor_chassis.distance_to(anchor_container)
				if dev_c > max_dislocation_distance:
					dislocated = true
					cause = "TRAILER DETACHED"
					print("[Truck] Trailer dislocation detected (deviation: %.1f)" % dev_c)

			# 2. Check Tyre 1 connection (front tyre on chassis)
			if not dislocated and is_instance_valid(tyre_1):
				var socket = chassis.to_global(Vector2(35, 10))
				var dev_1 = tyre_1.global_position.distance_to(socket)
				if dev_1 > max_dislocation_distance:
					dislocated = true
					cause = "WHEEL BROKE OFF"
					print("[Truck] Tyre 1 dislocation detected (deviation: %.1f)" % dev_1)

		# 3. Check Tyre 2 and Tyre 3 connections (tyres on container)
		if not dislocated and is_instance_valid(container_body):
			if is_instance_valid(tyre_2):
				var socket = container_body.to_global(Vector2(-31, 10))
				var dev_2 = tyre_2.global_position.distance_to(socket)
				if dev_2 > max_dislocation_distance:
					dislocated = true
					cause = "WHEEL BROKE OFF"
					print("[Truck] Tyre 2 dislocation detected (deviation: %.1f)" % dev_2)
			
			if not dislocated and is_instance_valid(tyre_3):
				var socket = container_body.to_global(Vector2(-91, 10))
				var dev_3 = tyre_3.global_position.distance_to(socket)
				if dev_3 > max_dislocation_distance:
					dislocated = true
					cause = "WHEEL BROKE OFF"
					print("[Truck] Tyre 3 dislocation detected (deviation: %.1f)" % dev_3)

		if dislocated:
			trigger_death(cause)
			return

func trigger_death(cause: String) -> void:
	if is_dead:
		return
	is_dead = true
	controls_locked = true
	print("[Truck] DEATH — cause: ", cause)

	# Freeze physics on all truck parts
	var bodies: Array = []
	if is_water_mode_active:
		if is_instance_valid(boat):
			bodies.append(boat)
	else:
		for b in [chassis, container_body, tyre_1, tyre_2, tyre_3]:
			if is_instance_valid(b):
				bodies.append(b)
	for b in bodies:
		b.freeze = true
		b.linear_velocity  = Vector2.ZERO
		b.angular_velocity = 0.0

	# Calculate distance covered
	var hud_stats = get_node_or_null("HUD/HudStats")
	var dist_m := 0.0
	if hud_stats and "_distance_m" in hud_stats:
		dist_m = hud_stats.get("_distance_m")

	# Fade to a death tint then show menu
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.25)
	tween.tween_interval(0.35)
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)
	tween.tween_callback(func(): _spawn_retry_menu(cause, dist_m))

func _spawn_retry_menu(cause: String, distance: float) -> void:
	var retry_script = load("res://ui/retry_menu.gd")
	if not retry_script:
		push_error("[Truck] retry_menu.gd not found!")
		return
	var menu = CanvasLayer.new()
	menu.set_script(retry_script)
	menu.name = "RetryMenu"
	get_tree().root.add_child(menu)
	menu.call("show_death", cause, distance)

func _spawn_journey_completed_menu() -> void:
	var journey_menu_script = load("res://ui/journey_completed_menu.gd")
	if not journey_menu_script:
		push_error("[Truck] journey_completed_menu.gd not found!")
		return
	var menu = CanvasLayer.new()
	menu.set_script(journey_menu_script)
	menu.name = "JourneyCompletedMenu"
	get_tree().root.add_child(menu)
	menu.call("show_completed")

func trigger_cinematic_mission_complete(mission_name: String, stats_text: String) -> void:
	var hud = get_node_or_null("HUD")
	if hud:
		var old_top = hud.get_node_or_null("CinematicTopBar")
		if old_top: old_top.queue_free()
		var old_bottom = hud.get_node_or_null("CinematicBottomBar")
		if old_bottom: old_bottom.queue_free()
		
		var top_bar = ColorRect.new()
		top_bar.name = "CinematicTopBar"
		top_bar.color = Color.BLACK
		top_bar.anchor_left = 0.0
		top_bar.anchor_right = 1.0
		top_bar.anchor_top = 0.0
		top_bar.anchor_bottom = 0.0
		top_bar.offset_left = 0
		top_bar.offset_right = 0
		top_bar.offset_top = 0
		top_bar.offset_bottom = 0
		hud.add_child(top_bar)
		
		var bottom_bar = ColorRect.new()
		bottom_bar.name = "CinematicBottomBar"
		bottom_bar.color = Color.BLACK
		bottom_bar.anchor_left = 0.0
		bottom_bar.anchor_right = 1.0
		bottom_bar.anchor_top = 1.0
		bottom_bar.anchor_bottom = 1.0
		bottom_bar.offset_left = 0
		bottom_bar.offset_right = 0
		bottom_bar.offset_top = 0
		bottom_bar.offset_bottom = 0
		hud.add_child(bottom_bar)
		
		var tween_bars = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween_bars.tween_property(top_bar, "offset_bottom", 90.0, 0.5)
		tween_bars.tween_property(bottom_bar, "offset_top", -90.0, 0.5)
		
		var text_container = Control.new()
		text_container.name = "CinematicMissionOverlay"
		text_container.anchor_right = 1.0
		text_container.anchor_bottom = 1.0
		hud.add_child(text_container)
		
		var title = Label.new()
		title.text = "[ %s ] COMPLETED" % mission_name.to_upper()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.anchor_left = 0.5
		title.anchor_top = 0.4
		title.anchor_right = 0.5
		title.anchor_bottom = 0.4
		title.grow_horizontal = Control.GROW_DIRECTION_BOTH
		title.grow_vertical = Control.GROW_DIRECTION_BOTH
		title.add_theme_font_size_override("font_size", 42)
		title.add_theme_color_override("font_color", Color.WHITE)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		title.add_theme_constant_override("outline_size", 8)
		title.modulate.a = 0.0
		text_container.add_child(title)
		
		var subtitle = Label.new()
		subtitle.text = stats_text
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		subtitle.anchor_left = 0.5
		subtitle.anchor_top = 0.925
		subtitle.anchor_right = 0.5
		subtitle.anchor_bottom = 0.925
		subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
		subtitle.grow_vertical = Control.GROW_DIRECTION_BOTH
		subtitle.add_theme_font_size_override("font_size", 18)
		subtitle.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		subtitle.add_theme_constant_override("outline_size", 4)
		subtitle.modulate.a = 0.0
		text_container.add_child(subtitle)
		
		var tween_text = create_tween().set_parallel(true)
		tween_text.tween_property(title, "modulate:a", 1.0, 0.6)
		tween_text.tween_property(subtitle, "modulate:a", 1.0, 0.6)
		
		is_cinematic_mission_complete = true
		
		get_tree().create_timer(2.0).timeout.connect(func():
			is_cinematic_mission_complete = false
			
			var tween_fade = create_tween().set_parallel(true)
			tween_fade.tween_property(title, "modulate:a", 0.0, 0.4)
			tween_fade.tween_property(subtitle, "modulate:a", 0.0, 0.4)
			
			var tween_retract = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween_retract.tween_property(top_bar, "offset_bottom", 0.0, 0.6)
			tween_retract.tween_property(bottom_bar, "offset_top", 0.0, 0.6)
			
			tween_retract.chain().tween_callback(func():
				if is_instance_valid(top_bar): top_bar.queue_free()
				if is_instance_valid(bottom_bar): bottom_bar.queue_free()
				if is_instance_valid(text_container): text_container.queue_free()
			)
		)

func respawn_at_crusher_start() -> void:
	if is_respawning:
		return
	is_respawning = true
	controls_locked = true
	
	# Reset health to max on respawn
	truck_health = truck_max_health
	
	var main_body = boat if is_water_mode_active else chassis
	if not is_instance_valid(main_body):
		is_respawning = false
		controls_locked = false
		return
		
	# Gather all physics body parts of the truck/boat
	var bodies = []
	if is_water_mode_active:
		if is_instance_valid(boat):
			bodies.append(boat)
	else:
		if is_instance_valid(chassis):
			bodies.append(chassis)
		if is_instance_valid(container_body):
			bodies.append(container_body)
		if is_instance_valid(tyre_1):
			bodies.append(tyre_1)
		if is_instance_valid(tyre_2):
			bodies.append(tyre_2)
		if is_instance_valid(tyre_3):
			bodies.append(tyre_3)
			
	# Immediately clear collision masks/layers so the truck parts don't get pushed by physics/crushers
	var original_collisions = {}
	for body in bodies:
		if is_instance_valid(body):
			original_collisions[body] = [body.collision_layer, body.collision_mask]
			body.collision_layer = 0
			body.collision_mask = 0
			
	# Disconnect joint node paths temporarily to relax joint constraints during teleportation
	var main_joint = get_node_or_null("PinJoint2D")
	var main_joint_a = ""
	var main_joint_b = ""
	if is_instance_valid(main_joint):
		main_joint_a = main_joint.node_a
		main_joint_b = main_joint.node_b
		main_joint.node_a = ""
		main_joint.node_b = ""
		
	var c_joint = chassis.get_node_or_null("GrooveJoint2D") if is_instance_valid(chassis) else null
	var c_joint_a = ""
	var c_joint_b = ""
	if is_instance_valid(c_joint):
		c_joint_a = c_joint.node_a
		c_joint_b = c_joint.node_b
		c_joint.node_a = ""
		c_joint.node_b = ""
		
	var cb_joint1 = container_body.get_node_or_null("GrooveJoint2D") if is_instance_valid(container_body) else null
	var cb_joint1_a = ""
	var cb_joint1_b = ""
	if is_instance_valid(cb_joint1):
		cb_joint1_a = cb_joint1.node_a
		cb_joint1_b = cb_joint1.node_b
		cb_joint1.node_a = ""
		cb_joint1.node_b = ""
		
	var cb_joint2 = container_body.get_node_or_null("GrooveJoint2D2") if is_instance_valid(container_body) else null
	var cb_joint2_a = ""
	var cb_joint2_b = ""
	if is_instance_valid(cb_joint2):
		cb_joint2_a = cb_joint2.node_a
		cb_joint2_b = cb_joint2.node_b
		cb_joint2.node_a = ""
		cb_joint2.node_b = ""

	# Freeze all bodies to prevent physics updates during the fade-out
	for body in bodies:
		if is_instance_valid(body):
			body.freeze = true
			body.linear_velocity = Vector2.ZERO
			body.angular_velocity = 0.0
			
	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		var road = get_node_or_null("/root/main/Road")
		var spawn_x = 0.0
		if road:
			var start_x = road.get("crusher_flat_start_x")
			if start_x > 0.0:
				spawn_x = start_x + 100.0
				
		var spawn_y = 0.0
		if road and road.has_method("get_road_height"):
			spawn_y = road.call("get_road_height", spawn_x) - 80.0
			
		var target_pos = Vector2(spawn_x, spawn_y)
		
		# Move boat or truck parts
		if is_water_mode_active:
			if is_instance_valid(boat):
				boat.global_position = target_pos
				boat.global_rotation = 0.0
				boat.linear_velocity = Vector2.ZERO
				boat.angular_velocity = 0.0
		else:
			if is_instance_valid(chassis):
				chassis.global_position = target_pos
				chassis.global_rotation = 0.0
				chassis.linear_velocity = Vector2.ZERO
				chassis.angular_velocity = 0.0
			if is_instance_valid(container_body):
				container_body.global_position = target_pos + Vector2(1, -1)
				container_body.global_rotation = 0.0
				container_body.linear_velocity = Vector2.ZERO
				container_body.angular_velocity = 0.0
			# Position tires underneath at their correct suspension anchor offsets
			if is_instance_valid(tyre_1) and is_instance_valid(chassis):
				tyre_1.global_position = chassis.global_position + Vector2(35, 10)
				tyre_1.linear_velocity = Vector2.ZERO
				tyre_1.angular_velocity = 0.0
			if is_instance_valid(tyre_2) and is_instance_valid(container_body):
				tyre_2.global_position = container_body.global_position + Vector2(-31, 10)
				tyre_2.linear_velocity = Vector2.ZERO
				tyre_2.angular_velocity = 0.0
			if is_instance_valid(tyre_3) and is_instance_valid(container_body):
				tyre_3.global_position = container_body.global_position + Vector2(-91, 10)
				tyre_3.linear_velocity = Vector2.ZERO
				tyre_3.angular_velocity = 0.0
				
		# Update PinJoint2D's global position to prevent pull forces
		if is_instance_valid(main_joint):
			main_joint.global_position = target_pos + Vector2(1, -28)
				
		# Update camera to target instantly
		var camera = get_node_or_null("/root/main/Camera2D")
		if camera and is_instance_valid(camera):
			var cam_h = camera.get("horizontal_offset") if "horizontal_offset" in camera else 150.0
			var cam_v = camera.get("vertical_offset") if "vertical_offset" in camera else -50.0
			camera.global_position = target_pos + Vector2(cam_h, cam_v)
			
		# Handle active towing mission respawn
		if road and road.has_method("relink_towed_car"):
			var towed = get_node_or_null("/root/main/TowedCar")
			if is_instance_valid(towed):
				# Disconnect towed car joints
				var tj_back = towed.get_node_or_null("gj_back")
				var tj_front = towed.get_node_or_null("gj_front")
				var tj_back_a = ""
				var tj_back_b = ""
				var tj_front_a = ""
				var tj_front_b = ""
				if is_instance_valid(tj_back):
					tj_back_a = tj_back.node_a
					tj_back_b = tj_back.node_b
					tj_back.node_a = ""
					tj_back.node_b = ""
				if is_instance_valid(tj_front):
					tj_front_a = tj_front.node_a
					tj_front_b = tj_front.node_b
					tj_front.node_a = ""
					tj_front.node_b = ""
					
				towed.global_position = target_pos + Vector2(-150, 0)
				towed.global_rotation = 0.0
				towed.linear_velocity = Vector2.ZERO
				towed.angular_velocity = 0.0
				
				var t_back = towed.get("tyre_back")
				var t_front = towed.get("tyre_front")
				if is_instance_valid(t_back):
					t_back.global_position = towed.global_position + Vector2(-35, 10)
					t_back.linear_velocity = Vector2.ZERO
					t_back.angular_velocity = 0.0
				if is_instance_valid(t_front):
					t_front.global_position = towed.global_position + Vector2(35, 10)
					t_front.linear_velocity = Vector2.ZERO
					t_front.angular_velocity = 0.0
					
				# Reconnect towed car joints
				if is_instance_valid(tj_back):
					tj_back.node_a = tj_back_a
					tj_back.node_b = tj_back_b
				if is_instance_valid(tj_front):
					tj_front.node_a = tj_front_a
					tj_front.node_b = tj_front_b
					
			road.call("relink_towed_car")
	)
	tween.tween_interval(0.2)
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	tween.tween_callback(func():
		# Reconnect joints first so they are bound to the new relaxed coordinates
		if is_instance_valid(main_joint):
			main_joint.node_a = main_joint_a
			main_joint.node_b = main_joint_b
		if is_instance_valid(c_joint):
			c_joint.node_a = c_joint_a
			c_joint.node_b = c_joint_b
		if is_instance_valid(cb_joint1):
			cb_joint1.node_a = cb_joint1_a
			cb_joint1.node_b = cb_joint1_b
		if is_instance_valid(cb_joint2):
			cb_joint2.node_a = cb_joint2_a
			cb_joint2.node_b = cb_joint2_b
			
		# Restore original collision layers/masks
		for body in original_collisions:
			if is_instance_valid(body):
				body.collision_layer = original_collisions[body][0]
				body.collision_mask = original_collisions[body][1]
				
		for body in bodies:
			if is_instance_valid(body):
				body.freeze = false
				body.linear_velocity = Vector2.ZERO
				body.angular_velocity = 0.0
		controls_locked = false
		is_respawning = false
		_dislocation_grace_timer = 0.5
	)

func start_tunnel_exit_transition() -> void:
	if is_exiting_tunnel_transition:
		return
	is_exiting_tunnel_transition = true
	has_completed_journey = false
	
	# Stop convoy/crusher/active event early if exiting the tunnel
	if is_autopilot:
		end_active_event("Convoy")
	var timer_bar = get_node_or_null("HUD/EventTimerBar")
	if timer_bar and timer_bar.has_method("end_event"):
		timer_bar.call("end_event")
		
	var road = get_node_or_null("/root/main/Road")
	if road:
		if road.get("is_convoy_active") == true:
			road.call("end_active_event", "Convoy")
		if road.has_method("end_active_event"):
			road.call("end_active_event", "Crusher")
			
	# Trigger letterbox bars immediately at full size
	var hud = get_node_or_null("HUD")
	if hud:
		var old_top = hud.get_node_or_null("CinematicTopBar")
		if old_top: old_top.queue_free()
		var old_bottom = hud.get_node_or_null("CinematicBottomBar")
		if old_bottom: old_bottom.queue_free()
		
		cinematic_top_bar = ColorRect.new()
		cinematic_top_bar.name = "CinematicTopBar"
		cinematic_top_bar.color = Color.BLACK
		cinematic_top_bar.anchor_left = 0.0
		cinematic_top_bar.anchor_right = 1.0
		cinematic_top_bar.anchor_top = 0.0
		cinematic_top_bar.anchor_bottom = 0.0
		cinematic_top_bar.offset_left = 0
		cinematic_top_bar.offset_right = 0
		cinematic_top_bar.offset_top = 0
		cinematic_top_bar.offset_bottom = 100.0
		hud.add_child(cinematic_top_bar)
		
		cinematic_bottom_bar = ColorRect.new()
		cinematic_bottom_bar.name = "CinematicBottomBar"
		cinematic_bottom_bar.color = Color.BLACK
		cinematic_bottom_bar.anchor_left = 0.0
		cinematic_bottom_bar.anchor_right = 1.0
		cinematic_bottom_bar.anchor_top = 1.0
		cinematic_bottom_bar.anchor_bottom = 1.0
		cinematic_bottom_bar.offset_left = 0
		cinematic_bottom_bar.offset_right = 0
		cinematic_bottom_bar.offset_top = -100.0
		cinematic_bottom_bar.offset_bottom = 0
		hud.add_child(cinematic_bottom_bar)

func start_tunnel_transition(target_x: float) -> void:
	if is_in_tunnel_transition:
		return
	is_in_tunnel_transition = true
	tunnel_target_x = target_x
	has_completed_journey = false
	
	# Stop convoy/crusher/active event early if entering the tunnel
	if is_autopilot:
		end_active_event("Convoy")
	var timer_bar = get_node_or_null("HUD/EventTimerBar")
	if timer_bar and timer_bar.has_method("end_event"):
		timer_bar.call("end_event")
		
	var road = get_node_or_null("/root/main/Road")
	if road:
		if road.get("is_convoy_active") == true:
			road.call("end_active_event", "Convoy")
		if road.has_method("end_active_event"):
			road.call("end_active_event", "Crusher")
			
	# Trigger letterbox bars slide-in
	var hud = get_node_or_null("HUD")
	if hud:
		var old_top = hud.get_node_or_null("CinematicTopBar")
		if old_top: old_top.queue_free()
		var old_bottom = hud.get_node_or_null("CinematicBottomBar")
		if old_bottom: old_bottom.queue_free()
		
		cinematic_top_bar = ColorRect.new()
		cinematic_top_bar.name = "CinematicTopBar"
		cinematic_top_bar.color = Color.BLACK
		cinematic_top_bar.anchor_left = 0.0
		cinematic_top_bar.anchor_right = 1.0
		cinematic_top_bar.anchor_top = 0.0
		cinematic_top_bar.anchor_bottom = 0.0
		cinematic_top_bar.offset_left = 0
		cinematic_top_bar.offset_right = 0
		cinematic_top_bar.offset_top = 0
		cinematic_top_bar.offset_bottom = 0
		hud.add_child(cinematic_top_bar)
		
		cinematic_bottom_bar = ColorRect.new()
		cinematic_bottom_bar.name = "CinematicBottomBar"
		cinematic_bottom_bar.color = Color.BLACK
		cinematic_bottom_bar.anchor_left = 0.0
		cinematic_bottom_bar.anchor_right = 1.0
		cinematic_bottom_bar.anchor_top = 1.0
		cinematic_bottom_bar.anchor_bottom = 1.0
		cinematic_bottom_bar.offset_left = 0
		cinematic_bottom_bar.offset_right = 0
		cinematic_bottom_bar.offset_top = 0
		cinematic_bottom_bar.offset_bottom = 0
		hud.add_child(cinematic_bottom_bar)
		
		var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(cinematic_top_bar, "offset_bottom", 100.0, 1.5)
		tween.tween_property(cinematic_bottom_bar, "offset_top", -100.0, 1.5)

func stop_tunnel_transition() -> void:
	# Retract cinematic bars
	var hud = get_node_or_null("HUD")
	if hud:
		var top_bar = hud.get_node_or_null("CinematicTopBar")
		var bottom_bar = hud.get_node_or_null("CinematicBottomBar")
		if top_bar or bottom_bar:
			var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			if top_bar:
				tween.tween_property(top_bar, "offset_bottom", 0.0, 1.5)
			if bottom_bar:
				tween.tween_property(bottom_bar, "offset_top", 0.0, 1.5)
			tween.chain().tween_callback(func():
				if top_bar and is_instance_valid(top_bar): top_bar.queue_free()
				if bottom_bar and is_instance_valid(bottom_bar): bottom_bar.queue_free()
			)
