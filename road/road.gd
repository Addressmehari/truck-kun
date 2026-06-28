@tool
extends StaticBody2D

@export var road_length := 15000.0:
	set(val):
		road_length = val
		if Engine.is_editor_hint():
			generate_road()

@export var step_size := 30.0: # Distance between points on the curve (lower is smoother)
	set(val):
		step_size = max(5.0, val) # Prevent infinite loops
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var road_bottom := 800.0: # How deep the ground polygon extends
	set(val):
		road_bottom = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export_group("Grass Settings")
@export var grass_textures: Array[Texture2D] = []:
	set(val):
		grass_textures = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var grass_frames: SpriteFrames:
	set(val):
		grass_frames = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export_group("Road Shape Settings")
@export var is_flat := true:
	set(val):
		is_flat = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var flat_height := 42.0:
	set(val):
		flat_height = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var hill_amplitude_multiplier := 1.0:
	set(val):
		hill_amplitude_multiplier = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var road_seed := 12345:
	set(val):
		road_seed = val
		update_seed_offsets()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var chunk_width := 3000.0:
	set(val):
		chunk_width = max(500.0, val)
		if not Engine.is_editor_hint():
			regenerate_runtime_chunks()

@export var view_distance := 9000.0:
	set(val):
		view_distance = max(1000.0, val)
		if not Engine.is_editor_hint():
			regenerate_runtime_chunks()

@export_group("Second Road Settings")
@export var enable_second_road := true:
	set(val):
		enable_second_road = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export_group("Road Visual Settings")
@export var road_color := Color(0.40392, 0.56863, 0.26275, 1):
	set(val):
		road_color = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var road_thickness := 8.0:
	set(val):
		road_thickness = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

# Seed offsets for waves
var seed_offset_1 := 0.0
var seed_offset_2 := 0.0
var seed_offset_3 := 0.0

# Dictionary to track runtime active chunks: { chunk_index: { "collision": Col, "fill": Fill, "line": Line } }
var active_chunks := {}
var wave_physics_tick := 0

const TUNNEL_MIN_SPACING := 6000.0

var ground_material: ShaderMaterial = null
var water_material: ShaderMaterial = null

# Captured styles for runtime chunk styling
var template_fill_color := Color(0.12, 0.12, 0.14, 1)

# Convoy event variables for smooth flat road transition
var is_convoy_active := false
var convoy_start_x := 0.0
var convoy_end_x := 0.0
var has_convoy_ended := false

@export_group("Biomes System")
@export var biomes: Array[BiomeConfig] = []
@export var active_biome_index := 0:
	set(val):
		active_biome_index = val
		if Engine.is_editor_hint():
			if is_inside_tree():
				apply_active_biome()
		else:
			apply_active_biome()

func get_current_biome() -> BiomeConfig:
	if biomes.is_empty():
		initialize_default_biomes()
	var idx = clamp(active_biome_index, 0, biomes.size() - 1)
	if idx < biomes.size():
		return biomes[idx]
	return null

func initialize_default_biomes() -> void:
	biomes.clear()
	
	# 1. Bright Hills
	var b1 = BiomeConfig.new()
	b1.biome_name = "Bright Hills"
	b1.road_color = Color(0.40392, 0.56863, 0.26275, 1)
	b1.road_fill_color = Color(0.12, 0.12, 0.14, 1)
	b1.spawn_foliage = true
	b1.foliage_density_multiplier = 1.0
	b1.foliage_color = Color(0, 0, 0, 0)
	b1.use_silhouette_truck = false
	biomes.append(b1)
	
	# 2. Sunset Silhouette
	var b2 = BiomeConfig.new()
	b2.biome_name = "Sunset Silhouette"
	b2.sky_shader = load("res://road/sky_gradient.gdshader")
	b2.sky_shader_params = {
		"top_color": Color(0.015, 0.01, 0.06, 1.0),
		"bottom_color": Color(0.16, 0.06, 0.18, 1.0),
		"gradient_offset": 0.15,
		"gradient_power": 1.4,
		"show_moon": true,
		"show_stars": true
	}
	b2.road_color = Color.BLACK
	b2.road_fill_color = Color.BLACK
	b2.use_silhouette_road = true
	b2.road_silhouette_color = Color.BLACK
	b2.spawn_foliage = true
	b2.foliage_density_multiplier = 0.8
	b2.use_silhouette_truck = true
	b2.truck_silhouette_color = Color.BLACK
	b2.enable_headlight = true
	biomes.append(b2)

	# 3. Deep Water
	var b3 = BiomeConfig.new()
	b3.biome_name = "Deep Water"
	b3.road_color = Color(0.25, 0.65, 0.75, 1.0)
	b3.road_fill_color = Color(0.08, 0.28, 0.38, 1.0)
	b3.spawn_foliage = false
	b3.is_water = true
	b3.use_silhouette_truck = false
	b3.enable_headlight = false
	biomes.append(b3)

func apply_active_biome() -> void:
	var biome = get_current_biome()
	if not biome:
		return
		
	# Update road colors
	road_color = biome.road_color
	template_fill_color = biome.road_fill_color
	
	# Update sky background
	var sky = get_node_or_null("../ParallaxBackground/ParallaxLayer")
	if sky and sky.has_method("apply_biome_settings"):
		sky.call("apply_biome_settings", biome.sky_texture, biome.sky_modulate, biome.sky_shader, biome.sky_shader_params)
		
	# Update truck silhouette and headlight settings
	var truck = get_node_or_null("../truck")
	if truck:
		if truck.has_method("set_silhouette_mode"):
			truck.call("set_silhouette_mode", biome.use_silhouette_truck, biome.truck_silhouette_color)
		if truck.has_method("set_headlight_enabled"):
			truck.call("set_headlight_enabled", biome.enable_headlight if "enable_headlight" in biome else false)
		if truck.has_method("set_water_mode"):
			truck.call("set_water_mode", biome.is_water)
		
	# Regenerate visuals
	if Engine.is_editor_hint():
		generate_road()
	else:
		regenerate_runtime_chunks()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			cycle_biome()

func cycle_biome() -> void:
	# Always reinitialize if we have fewer biomes than expected (e.g. scene was saved
	# before the Water biome was added, so the exported array is stale).
	if biomes.size() < 3:
		initialize_default_biomes()
	var new_idx = (active_biome_index + 1) % biomes.size()
	active_biome_index = new_idx
	print("Switched to biome: ", biomes[active_biome_index].biome_name)
	show_biome_banner(biomes[active_biome_index].biome_name)

func show_biome_banner(biome_name: String) -> void:
	var hud = get_node_or_null("../truck/HUD")
	if not hud:
		return
		
	var old_banner = hud.get_node_or_null("BiomeBanner")
	if old_banner:
		old_banner.queue_free()
		
	var label = Label.new()
	label.name = "BiomeBanner"
	label.text = "BIOME: " + biome_name.to_upper()
	
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	label.anchors_preset = Control.PRESET_CENTER_TOP
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.position = Vector2(-200, 40)
	label.size = Vector2(400, 40)
	
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.75)
	style.border_color = Color(1, 1, 1, 0.15)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.expand_margin_left = 20
	style.expand_margin_right = 20
	style.expand_margin_top = 6
	style.expand_margin_bottom = 6
	label.add_theme_stylebox_override("normal", style)
	
	hud.add_child(label)
	
	var tween = label.create_tween()
	tween.tween_interval(1.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

# Fetch children nodes dynamically in editor (setters can run before _ready)
func _get_collision_polygon() -> CollisionPolygon2D:
	return get_node_or_null("CollisionPolygon2D")

func _get_road_fill() -> Polygon2D:
	return get_node_or_null("RoadFill")

func _get_line_2d() -> Line2D:
	return get_node_or_null("Line2D")

func update_seed_offsets() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = road_seed
	seed_offset_1 = rng.randf_range(-10000.0, 10000.0)
	seed_offset_2 = rng.randf_range(-10000.0, 10000.0)
	seed_offset_3 = rng.randf_range(-10000.0, 10000.0)

func capture_templates() -> void:
	var fill = _get_road_fill()
	if fill:
		template_fill_color = fill.color

func get_ground_vertex_colors(surface_size: int, fill_color: Color, line_color: Color) -> PackedColorArray:
	var colors = PackedColorArray()
	var top_color = fill_color.lightened(0.12).lerp(line_color, 0.12)
	var bottom_color = fill_color.darkened(0.65)
	colors.resize(surface_size + 2)
	for i in range(surface_size):
		colors[i] = top_color
	colors[surface_size] = bottom_color
	colors[surface_size + 1] = bottom_color
	return colors

func get_ground_material(fill_col: Color, line_col: Color) -> ShaderMaterial:
	var biome = get_current_biome()
	# Water biome uses the animated Voronoi water shader instead of ground shader
	if biome and biome.is_water:
		if not water_material:
			water_material = ShaderMaterial.new()
			var water_shader = load("res://road/water_voronoi.gdshader")
			if water_shader:
				water_material.shader = water_shader
		if water_material:
			# Keep player_position / player_velocity_length at default (updated each frame by truck.gd)
			water_material.set_shader_parameter("blue_bg", fill_col)
		return water_material

	if not ground_material:
		ground_material = ShaderMaterial.new()
		var shader_res = load("res://road/ground_voronoi.gdshader")
		if shader_res:
			ground_material.shader = shader_res
	if ground_material:
		ground_material.set_shader_parameter("fill_color", fill_col)
		ground_material.set_shader_parameter("line_color", line_col)
		
		# Set silhouette road parameters from current biome
		if biome:
			ground_material.set_shader_parameter("is_silhouette", biome.use_silhouette_road)
			ground_material.set_shader_parameter("silhouette_color", biome.road_silhouette_color)
	return ground_material

func _ready() -> void:
	update_seed_offsets()
	if Engine.is_editor_hint():
		apply_active_biome()
	else:
		capture_templates()
		initialize_default_biomes()
		
		# Free template nodes at runtime to avoid collision/visual duplication at the start
		var col_poly = _get_collision_polygon()
		var fill = _get_road_fill()
		var line = _get_line_2d()
		var line2 = get_node_or_null("Line2D2")
		var grass = get_node_or_null("GrassDecorator")
		var grass2 = get_node_or_null("GrassDecorator2")
		if col_poly: col_poly.queue_free()
		if fill: fill.queue_free()
		if line: line.queue_free()
		if line2: line2.queue_free()
		if grass: grass.queue_free()
		if grass2: grass2.queue_free()
		
		# Apply biome visuals before generating initial chunks
		apply_active_biome()
		
		# Initial chunk generation
		update_chunks(get_target_x())

# Calculate convoy road flattening factor smoothly based on coordinate distance
func get_convoy_multiplier(x: float) -> float:
	if convoy_start_x == 0.0:
		return 1.0
		
	if x < convoy_start_x:
		return 1.0
		
	if is_convoy_active:
		var t = clamp((x - convoy_start_x) / 800.0, 0.0, 1.0)
		var smooth_t = t * t * (3.0 - 2.0 * t)
		return lerp(1.0, 0.15, smooth_t)
		
	if has_convoy_ended:
		if x < convoy_end_x:
			var t = clamp((x - convoy_start_x) / 800.0, 0.0, 1.0)
			var smooth_t = t * t * (3.0 - 2.0 * t)
			return lerp(1.0, 0.15, smooth_t)
		else:
			var t = clamp((x - convoy_end_x) / 1200.0, 0.0, 1.0)
			var smooth_t = t * t * (3.0 - 2.0 * t)
			return lerp(0.15, 1.0, smooth_t)
			
	return 1.0

# Base math function defining the height of the road without flattening
func get_base_road_height(x: float) -> float:
	if is_flat:
		return flat_height

	# Water biome: flat road with gentle time-based waving
	var biome = get_current_biome()
	if biome and biome.is_water:
		var time = 0.0
		if not Engine.is_editor_hint():
			time = Time.get_ticks_msec() / 1000.0
		var wave = sin((x + seed_offset_1) * 0.005 - time * 2.0) * 12.0
		var wave2 = cos((x + seed_offset_2) * 0.012 - time * 3.5) * 4.0
		return flat_height + wave + wave2
		
	# Make a flat starting zone around the spawn area (x = 0)
	if abs(x) < 400.0:
		return 42.0
		
	# Smoothly transition from flat to hills using a smooth S-curve
	var raw_factor = clamp((abs(x) - 400.0) / 300.0, 0.0, 1.0)
	var factor = raw_factor * raw_factor * (3.0 - 2.0 * raw_factor)
	
	# Combine waves to create interesting rolling hills and dips, offset by seed
	var mult = hill_amplitude_multiplier * get_convoy_multiplier(x)
	var long_hills = sin((x + seed_offset_1) * 0.0015) * 140.0 * mult # Large elevations
	var medium_waves = cos((x + seed_offset_2) * 0.004) * 50.0 * mult # Medium slopes
	var small_bumps = sin((x + seed_offset_3) * 0.012) * 12.0 * mult # Small bumpy texture
	
	var height = 42.0 + (long_hills + medium_waves + small_bumps)
	return lerp(42.0, height, factor)

func start_active_event(event_name: String) -> void:
	if event_name == "Convoy":
		is_convoy_active = true
		has_convoy_ended = false
		convoy_start_x = get_target_x()
		regenerate_runtime_chunks()

func end_active_event(event_name: String) -> void:
	if event_name == "Convoy":
		is_convoy_active = false
		has_convoy_ended = true
		convoy_end_x = get_target_x()
		regenerate_runtime_chunks()

func is_event_active() -> bool:
	if Engine.is_editor_hint():
		return false
		
	var truck = get_node_or_null("../truck")
	if truck and is_instance_valid(truck):
		if truck.get("is_autopilot") == true:
			return true
		var hud = truck.get_node_or_null("HUD")
		if hud and is_instance_valid(hud):
			var timer_bar = hud.get_node_or_null("EventTimerBar")
			if timer_bar and is_instance_valid(timer_bar):
				return true
			var wheel = hud.get_node_or_null("EventWheelPopup")
			if wheel and is_instance_valid(wheel):
				return true
	return false

# Deterministically get tunnel details for a given chunk
func get_tunnel_at_chunk(chunk_index: int) -> Dictionary:
	if is_event_active():
		return {}

	# No tunnels in water biome (submerged road)
	var biome = get_current_biome()
	if biome and biome.is_water:
		return {}
		
	# Avoid tunnels too close to spawn (within 1500 units)
	var spawn_buffer_chunks = int(ceil(1500.0 / chunk_width))
	if abs(chunk_index) <= spawn_buffer_chunks:
		return {}
		
	# Enforce spacing: tunnels can only spawn at chunk indices that respect the minimum physical spacing
	var spacing_chunks = int(ceil(TUNNEL_MIN_SPACING / chunk_width))
	if abs(chunk_index) % spacing_chunks != 0:
		return {}
		
	var rng = RandomNumberGenerator.new()
	# Deterministic seed per chunk
	rng.seed = hash(str(road_seed) + "_tunnel_" + str(chunk_index))
	
	# Always spawn a tunnel in this valid chunk for guaranteed spawning
	if true:
		# Tunnel is centered in the middle of the chunk
		var tunnel_x = (chunk_index + 0.5) * chunk_width
		var base_y = get_base_road_height(tunnel_x)
		
		return {
			"x": tunnel_x,
			"y": base_y,
			"width": 1000.0,
			"height": 320.0
		}
	return {}

# Math function defining the height of the road at any X coordinate, flattened inside tunnels and paddings, smoothed in transitions
func get_road_height(x: float) -> float:
	# Determine range of chunk indices that can physically influence the height at x
	var max_influence = 1500.0 # 500 (half width) + 200 (padding) + 800 (transition)
	var min_chunk_idx = int(floor((x - max_influence) / chunk_width))
	var max_chunk_idx = int(floor((x + max_influence) / chunk_width))
	
	for check_idx in range(min_chunk_idx, max_chunk_idx + 1):
		var tunnel = get_tunnel_at_chunk(check_idx)
		if not tunnel.is_empty():
			var tunnel_x = tunnel["x"]
			var tunnel_y = tunnel["y"]
			var half_width = tunnel["width"] / 2.0
			var padding = 200.0 # 10 meters padding on front and back (1m = 20px)
			
			var flat_start = tunnel_x - half_width - padding
			var flat_end = tunnel_x + half_width + padding
			var transition_dist = 800.0
			
			var dist = x - tunnel_x
			if abs(dist) <= half_width + padding:
				return tunnel_y
			elif dist < 0 and dist >= - (half_width + padding + transition_dist):
				# Incoming transition (left side)
				var t = (x - (flat_start - transition_dist)) / transition_dist
				var smooth_t = t * t * (3.0 - 2.0 * t) # smoothstep S-curve
				return lerp(get_base_road_height(x), tunnel_y, smooth_t)
			elif dist > 0 and dist <= (half_width + padding + transition_dist):
				# Outgoing transition (right side)
				var t = (x - flat_end) / transition_dist
				var smooth_t = t * t * (3.0 - 2.0 * t) # smoothstep S-curve
				return lerp(tunnel_y, get_base_road_height(x), smooth_t)
				
	return get_base_road_height(x)

# Helper to get the height of the second line below the road
func get_second_line_height(x: float, y_base: float) -> float:
	var offset = 140.0 + sin(x * 0.005) * 30.0 + cos(x * 0.012) * 10.0
	return y_base + max(60.0, offset)

func get_current_step_size() -> float:
	var biome = get_current_biome()
	if biome and biome.is_water:
		return 450.0 # Very large step size to keep polygon count low and remove lag!
	return step_size

func get_current_view_distance() -> float:
	var biome = get_current_biome()
	if biome and biome.is_water:
		return 3500.0 # Only load chunks near the camera to keep CPU usage low
	return view_distance


func generate_road() -> void:
	var col_poly = _get_collision_polygon()
	var fill = _get_road_fill()
	var line = _get_line_2d()
	
	if not col_poly or not fill or not line:
		return
		
	var surface_points = PackedVector2Array()
	
	# Generate points along the road surface
	var start_x = -1200.0
	var end_x = road_length
	
	var x = start_x
	var step = get_current_step_size()
	while x <= end_x:
		var y = get_road_height(x)
		surface_points.append(Vector2(x, y))
		x += step
		
	# Ensure the last point is exactly at the end
	surface_points.append(Vector2(end_x, get_road_height(end_x)))
	
	var surface_points_2 = PackedVector2Array()
	for pt in surface_points:
		surface_points_2.append(Vector2(pt.x, get_second_line_height(pt.x, pt.y)))
	
	# Create a closed polygon for the ground fill and collision
	var polygon_points = PackedVector2Array(surface_points)
	polygon_points.append(Vector2(end_x, road_bottom))
	polygon_points.append(Vector2(start_x, road_bottom))
	
	# Apply to collision shape
	col_poly.polygon = polygon_points
		
	# Apply to visual ground fill
	fill.polygon = polygon_points
	fill.vertex_colors = get_ground_vertex_colors(surface_points.size(), fill.color, road_color)
	fill.material = get_ground_material(fill.color, road_color)
		
	# Apply to visual surface line
	var current_biome = get_current_biome()
	line.points = surface_points
	line.width = 0.0 if (current_biome and current_biome.is_water) else road_thickness
	line.default_color = road_color
	
	# Apply to second visual surface line
	var line2 = get_node_or_null("Line2D2")
	if not enable_second_road:
		if line2:
			line2.queue_free()
	else:
		if not line2:
			line2 = Line2D.new()
			line2.name = "Line2D2"
			add_child(line2)
			if Engine.is_editor_hint() and is_inside_tree():
				line2.owner = get_tree().edited_scene_root
		if line2:
			line2.points = surface_points_2
			line2.width = 0.0 if (current_biome and current_biome.is_water) else road_thickness
			line2.default_color = road_color
	
	# Create or update GrassDecorator in editor
	current_biome = get_current_biome()
	
	var grass = get_node_or_null("GrassDecorator")
	if not current_biome.spawn_foliage:
		if grass: grass.queue_free()
	else:
		if not grass:
			var grass_script = load("res://road/grass_decorator.gd")
			if grass_script:
				grass = grass_script.new()
				grass.name = "GrassDecorator"
				add_child(grass)
				if Engine.is_editor_hint() and is_inside_tree():
					grass.owner = get_tree().edited_scene_root
		if grass:
			grass.points = surface_points
			grass.color = current_biome.foliage_color if current_biome.foliage_color != Color(0, 0, 0, 0) else road_color
			grass.road_seed = road_seed
			grass.chunk_index = 9999
			grass.road = self
			grass.textures = grass_textures
			grass.sprite_frames = grass_frames
			grass.density_multiplier = current_biome.foliage_density_multiplier
			
	# Create or update GrassDecorator2 in editor
	var grass2 = get_node_or_null("GrassDecorator2")
	if not enable_second_road or not current_biome.spawn_foliage:
		if grass2:
			grass2.queue_free()
	else:
		if not grass2:
			var grass_script = load("res://road/grass_decorator.gd")
			if grass_script:
				grass2 = grass_script.new()
				grass2.name = "GrassDecorator2"
				add_child(grass2)
				if Engine.is_editor_hint() and is_inside_tree():
					grass2.owner = get_tree().edited_scene_root
		if grass2:
			grass2.points = surface_points_2
			grass2.color = current_biome.foliage_color if current_biome.foliage_color != Color(0, 0, 0, 0) else road_color
			grass2.road_seed = road_seed + 1
			grass2.chunk_index = 9999
			grass2.road = self
			grass2.textures = grass_textures
			grass2.sprite_frames = grass_frames
			grass2.density_multiplier = 0.4 * current_biome.foliage_density_multiplier
	
	# If running in editor, notify dependent components like elevator systems to snap
	if Engine.is_editor_hint():
		for child in get_parent().get_children():
			if child.has_method("snap_to_road"):
				child.call("snap_to_road")

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	update_chunks(get_target_x())
	update_active_chunks_geometry()

	# Feed interactive ripple uniforms into the water shader every frame
	if water_material and water_material.shader:
		var truck = get_node_or_null("../truck")
		var player_node = null
		if truck:
			player_node = truck.boat if truck.get("is_water_mode_active") else truck.chassis
		if not player_node:
			player_node = get_node_or_null("../truck/chassis")
			
		if player_node and is_instance_valid(player_node):
			water_material.set_shader_parameter("player_position", player_node.global_position)
			water_material.set_shader_parameter("player_velocity_length", player_node.linear_velocity.length())

func update_active_chunks_geometry() -> void:
	var biome = get_current_biome()
	if not biome or not biome.is_water:
		return
		
	wave_physics_tick += 1
	var update_collision = (wave_physics_tick % 5 == 0)
	
	for i in active_chunks.keys():
		var chunk = active_chunks[i]
		var start_x = i * chunk_width
		var end_x = (i + 1) * chunk_width
		
		var surface_points = PackedVector2Array()
		var x = start_x
		var step = get_current_step_size()
		while x < end_x:
			var y = get_road_height(x)
			surface_points.append(Vector2(x, y))
			x += step
		surface_points.append(Vector2(end_x, get_road_height(end_x)))
		
		# Update CollisionPolygon2D (throttled for performance)
		if update_collision and is_instance_valid(chunk.collision):
			var polygon_points = PackedVector2Array(surface_points)
			polygon_points.append(Vector2(end_x, road_bottom))
			polygon_points.append(Vector2(start_x, road_bottom))
			chunk.collision.polygon = polygon_points
			
		# Update Polygon2D
		if is_instance_valid(chunk.fill):
			var polygon_points = PackedVector2Array(surface_points)
			polygon_points.append(Vector2(end_x, road_bottom))
			polygon_points.append(Vector2(start_x, road_bottom))
			chunk.fill.polygon = polygon_points
			
		# Update Line2D
		if is_instance_valid(chunk.line):
			chunk.line.points = surface_points
			
		# Update Line2D2
		if "line2" in chunk and is_instance_valid(chunk.line2):
			var surface_points_2 = PackedVector2Array()
			for pt in surface_points:
				surface_points_2.append(Vector2(pt.x, get_second_line_height(pt.x, pt.y)))
			chunk.line2.points = surface_points_2


func get_target_x() -> float:
	if is_inside_tree():
		var viewport = get_viewport()
		if viewport:
			var camera = viewport.get_camera_2d()
			if camera and is_instance_valid(camera):
				return camera.global_position.x
		
	var truck = get_node_or_null("../truck")
	var player_node = null
	if truck:
		player_node = truck.boat if truck.get("is_water_mode_active") else truck.chassis
	if not player_node:
		player_node = get_node_or_null("../truck/chassis")
		
	if player_node and is_instance_valid(player_node):
		return player_node.global_position.x
		
	return 0.0

func regenerate_runtime_chunks() -> void:
	if not Engine.is_editor_hint():
		for key in active_chunks.keys():
			destroy_chunk(key)
		update_chunks(get_target_x())

func update_chunks(player_x: float) -> void:
	var current_view_dist = get_current_view_distance()
	var start_chunk = int(floor((player_x - current_view_dist) / chunk_width))
	var end_chunk = int(ceil((player_x + current_view_dist) / chunk_width))
	
	# Create new chunks
	for i in range(start_chunk, end_chunk + 1):
		if not active_chunks.has(i):
			create_chunk(i)
			
	# Remove old chunks
	var active_keys = active_chunks.keys()
	for i in active_keys:
		if i < start_chunk or i > end_chunk:
			destroy_chunk(i)

func spawn_tunnel_node(chunk_index: int, tunnel_data: Dictionary) -> Node2D:
	var tunnel_scene = load("res://road/tunnel.tscn")
	if not tunnel_scene:
		return null
	var tunnel = tunnel_scene.instantiate() as Node2D
	tunnel.position = Vector2(tunnel_data["x"], tunnel_data["y"])
	add_child(tunnel)
	return tunnel


func create_chunk(i: int) -> void:
	var current_biome = get_current_biome()
	var start_x = i * chunk_width
	var end_x = (i + 1) * chunk_width
	
	var surface_points = PackedVector2Array()
	var x = start_x
	var step = get_current_step_size()
	while x < end_x:
		var y = get_road_height(x)
		surface_points.append(Vector2(x, y))
		x += step
		
	# Ensure the last point is exactly at the end
	surface_points.append(Vector2(end_x, get_road_height(end_x)))
	
	var surface_points_2 = PackedVector2Array()
	for pt in surface_points:
		surface_points_2.append(Vector2(pt.x, get_second_line_height(pt.x, pt.y)))
	
	# Create the closed polygon
	var polygon_points = PackedVector2Array(surface_points)
	polygon_points.append(Vector2(end_x, road_bottom))
	polygon_points.append(Vector2(start_x, road_bottom))
	
	# Create CollisionPolygon2D
	var col_poly = CollisionPolygon2D.new()
	col_poly.polygon = polygon_points
	add_child(col_poly)
	
	# Create Polygon2D
	var fill = Polygon2D.new()
	fill.polygon = polygon_points
	fill.color = template_fill_color
	fill.vertex_colors = get_ground_vertex_colors(surface_points.size(), template_fill_color, road_color)
	fill.material = get_ground_material(template_fill_color, road_color)
	add_child(fill)
	
	# Create Line2D
	var line = Line2D.new()
	line.points = surface_points
	line.width = 0.0 if current_biome.is_water else road_thickness
	line.default_color = road_color
	add_child(line)
	
	# Create second Line2D
	var line2 = null
	if enable_second_road:
		line2 = Line2D.new()
		line2.points = surface_points_2
		line2.width = 0.0 if current_biome.is_water else road_thickness
		line2.default_color = road_color
		add_child(line2)
	
	# Create GrassDecorator
	current_biome = get_current_biome()
	var grass = null
	var grass2 = null
	var grass_script = load("res://road/grass_decorator.gd")
	if grass_script and current_biome.spawn_foliage:
		grass = grass_script.new()
		grass.points = surface_points
		grass.color = current_biome.foliage_color if current_biome.foliage_color != Color(0, 0, 0, 0) else road_color
		grass.road_seed = road_seed
		grass.chunk_index = i
		grass.chunk_width = chunk_width
		grass.road = self
		grass.textures = grass_textures
		grass.sprite_frames = grass_frames
		grass.density_multiplier = current_biome.foliage_density_multiplier
		add_child(grass)
		
		# Create GrassDecorator2 for below road
		if enable_second_road:
			grass2 = grass_script.new()
			grass2.points = surface_points_2
			grass2.color = current_biome.foliage_color if current_biome.foliage_color != Color(0, 0, 0, 0) else road_color
			grass2.road_seed = road_seed + 1
			grass2.chunk_index = i
			grass2.chunk_width = chunk_width
			grass2.road = self
			grass2.textures = grass_textures
			grass2.sprite_frames = grass_frames
			grass2.density_multiplier = 0.4 * current_biome.foliage_density_multiplier
			add_child(grass2)
	
	# Spawn tunnel if present
	var tunnel_node = null
	var tunnel_data = get_tunnel_at_chunk(i)
	if not tunnel_data.is_empty():
		tunnel_node = spawn_tunnel_node(i, tunnel_data)
		
	active_chunks[i] = {
		"collision": col_poly,
		"fill": fill,
		"line": line,
		"line2": line2,
		"grass": grass,
		"grass2": grass2,
		"tunnel": tunnel_node
	}

func destroy_chunk(i: int) -> void:
	if active_chunks.has(i):
		var chunk = active_chunks[i]
		if is_instance_valid(chunk.collision):
			chunk.collision.queue_free()
		if is_instance_valid(chunk.fill):
			chunk.fill.queue_free()
		if is_instance_valid(chunk.line):
			chunk.line.queue_free()
		if "line2" in chunk and is_instance_valid(chunk.line2):
			chunk.line2.queue_free()
		if "grass" in chunk and is_instance_valid(chunk.grass):
			chunk.grass.queue_free()
		if "grass2" in chunk and is_instance_valid(chunk.grass2):
			chunk.grass2.queue_free()
		if "tunnel" in chunk and is_instance_valid(chunk.tunnel):
			chunk.tunnel.queue_free()
		active_chunks.erase(i)
