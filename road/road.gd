@tool
extends StaticBody2D

enum TerrainType { RUGGED, SMOOTH, BOTH, CUSTOM }
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
		clear_road_geometry_caches()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var flat_height := 42.0:
	set(val):
		flat_height = val
		clear_road_geometry_caches()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var hill_amplitude_multiplier := 1.0:
	set(val):
		hill_amplitude_multiplier = val
		clear_road_geometry_caches()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var terrain_type: TerrainType = TerrainType.RUGGED:
	set(val):
		terrain_type = val
		_apply_terrain_preset()
		clear_road_geometry_caches()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export_subgroup("Terrain Wave Amplitudes")
@export var mountain_amplitude := 220.0:
	set(val):
		mountain_amplitude = val
		if terrain_type != TerrainType.CUSTOM:
			terrain_type = TerrainType.CUSTOM
		_on_terrain_param_changed()
@export var long_hills_amplitude := 85.0:
	set(val):
		long_hills_amplitude = val
		if terrain_type != TerrainType.CUSTOM:
			terrain_type = TerrainType.CUSTOM
		_on_terrain_param_changed()
@export var medium_waves_amplitude := 50.0:
	set(val):
		medium_waves_amplitude = val
		if terrain_type != TerrainType.CUSTOM:
			terrain_type = TerrainType.CUSTOM
		_on_terrain_param_changed()
@export var smooth_spikes_amplitude := 65.0:
	set(val):
		smooth_spikes_amplitude = val
		if terrain_type != TerrainType.CUSTOM:
			terrain_type = TerrainType.CUSTOM
		_on_terrain_param_changed()
@export var sharp_dips_amplitude := 25.0:
	set(val):
		sharp_dips_amplitude = val
		if terrain_type != TerrainType.CUSTOM:
			terrain_type = TerrainType.CUSTOM
		_on_terrain_param_changed()
@export var lil_spikes_amplitude := 18.0:
	set(val):
		lil_spikes_amplitude = val
		if terrain_type != TerrainType.CUSTOM:
			terrain_type = TerrainType.CUSTOM
		_on_terrain_param_changed()
@export var small_bumps_amplitude := 12.0:
	set(val):
		small_bumps_amplitude = val
		if terrain_type != TerrainType.CUSTOM:
			terrain_type = TerrainType.CUSTOM
		_on_terrain_param_changed()


@export var road_seed := 12345:
	set(val):
		road_seed = val
		update_seed_offsets()
		clear_road_geometry_caches()
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
		if _suppress_regen:
			return
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

@export_group("Block Settings")
@export var enable_blocks := true:
	set(val):
		enable_blocks = val
		clear_road_geometry_caches()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var block_height := 250.0:
	set(val):
		block_height = val
		clear_road_geometry_caches()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var block_flat_before := 500.0:
	set(val):
		block_flat_before = val
		clear_road_geometry_caches()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

## Flat zone length AFTER a downward drop so the truck has room to land
@export var block_flat_after := 1000.0:
	set(val):
		block_flat_after = val
		clear_road_geometry_caches()
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
var block_cache := {}
var cumulative_offset_cache := {}
var tunnel_cache := {}
var wave_physics_tick := 0
# Guard: when true the road_color / terrain setters skip regenerate_runtime_chunks()
# so that apply_active_biome() only triggers a single rebuild at the end.
var _suppress_regen := false

func clear_road_geometry_caches() -> void:
	block_cache.clear()
	cumulative_offset_cache.clear()
	tunnel_cache.clear()

func _on_terrain_param_changed() -> void:
	clear_road_geometry_caches()
	if Engine.is_editor_hint():
		generate_road()
	else:
		regenerate_runtime_chunks()

func _apply_terrain_preset() -> void:
	if terrain_type == TerrainType.RUGGED:
		mountain_amplitude = 220.0
		long_hills_amplitude = 85.0
		medium_waves_amplitude = 50.0
		smooth_spikes_amplitude = 65.0
		sharp_dips_amplitude = 25.0
		lil_spikes_amplitude = 18.0
		small_bumps_amplitude = 12.0
	elif terrain_type == TerrainType.SMOOTH:
		mountain_amplitude = 130.0
		long_hills_amplitude = 60.0
		medium_waves_amplitude = 35.0
		smooth_spikes_amplitude = 15.0
		sharp_dips_amplitude = 8.0
		lil_spikes_amplitude = 0.0
		small_bumps_amplitude = 6.0
	# BOTH does not set static parameters on the sliders, as they vary dynamically by distance.


const TUNNEL_MIN_SPACING := 30000.0

# Dynamic tunnel spawning tracking
var next_planned_tunnel_x: float = 30000.0
var _tunnel_is_queued: bool = false
var _tunnel_positions: Array[float] = []
var _was_mission_active: bool = false
var _mission_end_x: float = -1.0
var queued_next_biome_index: int = -1

var ground_material: ShaderMaterial = null
var water_material: ShaderMaterial = null

# Captured styles for runtime chunk styling
var template_fill_color := Color(0.12, 0.12, 0.14, 1)

# Convoy event variables for smooth flat road transition
var is_convoy_active := false
var convoy_start_x := 0.0
var convoy_end_x := 0.0
var has_convoy_ended := false
# When a delivery/tow mission is active, convoy auto-ends at this X
var convoy_auto_end_x := -1.0

# Crusher event variables for flat road transition
var crusher_flat_start_x := 0.0
var crusher_flat_end_x := 0.0

# Delivery Contract State
var delivery_target_chunk: int = -1
var delivery_crate_count: int = 0
var delivery_crates_delivered: int = 0
var delivery_reward: int = 0
var used_house_chunks: Array[int] = []

# Racing Contract State
var racing_target_chunk: int = -1
var racing_reward: int = 0
var is_racing_active: bool = false
var active_opponent: RigidBody2D = null
var opponent_finished: bool = false
var active_opponent_name: String = "Opponent"

# Towing Contract State
var towing_target_chunk: int = -1
var towing_reward: int = 0
var is_towing_active: bool = false


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
	clear_road_geometry_caches()
	
	# --- Reset cached shader materials so the new biome always gets fresh parameters ---
	# Without this, toggling between biomes reuses a stale material from a prior biome.
	ground_material = null
	water_material = null
	
	var biome = get_current_biome()
	if not biome:
		return
		
	# Update road colors — suppress the setter's auto-regeneration so we only
	# fire a single regenerate_runtime_chunks() at the bottom of this function.
	_suppress_regen = true
	road_color = biome.road_color
	_suppress_regen = false
	template_fill_color = biome.road_fill_color
	
	# Update sky background
	var sky = get_node_or_null("../ParallaxBackground/ParallaxLayer")
	if sky and sky.has_method("apply_biome_settings"):
		sky.call("apply_biome_settings", biome.sky_texture, biome.sky_modulate, biome.sky_shader, biome.sky_shader_params)
		
	# Update truck — always clear silhouette FIRST so no stale shader lingers
	# when transitioning from Silhouette → Grass or Silhouette → Water.
	var truck = get_node_or_null("../truck")
	if truck:
		if truck.has_method("set_silhouette_mode"):
			truck.call("set_silhouette_mode", false)          # clear first
			if biome.use_silhouette_truck:
				truck.call("set_silhouette_mode", true, biome.truck_silhouette_color)
		if truck.has_method("set_headlight_enabled"):
			truck.call("set_headlight_enabled", biome.enable_headlight if "enable_headlight" in biome else false)
		if truck.has_method("set_water_mode"):
			truck.call("set_water_mode", biome.is_water)
		
	# Regenerate visuals (single call — road_color setter fires regenerate too,
	# but only at runtime and only when the value changes, so we skip the double
	# by setting the backing var above when already at runtime.)
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

func select_next_biome_index() -> int:
	var cur = active_biome_index
	var roll = randf()
	if cur == 0: # Current is Grass
		# Choose Silhouette (1) or Water (2) - 50% each
		return 1 if roll < 0.5 else 2
	elif cur == 1: # Current is Silhouette
		# 80% chance to return to Grass (0), 20% chance to transition to Water (2)
		return 0 if roll < 0.8 else 2
	else: # Current is Water
		# 80% chance to return to Grass (0), 20% chance to transition to Silhouette (1)
		return 0 if roll < 0.8 else 1

func prepare_next_biome() -> void:
	if biomes.size() < 3:
		initialize_default_biomes()
		
	if queued_next_biome_index == -1:
		queued_next_biome_index = select_next_biome_index()
		
	var next_biome_name = biomes[queued_next_biome_index].biome_name
	show_next_biome_announcement(next_biome_name)

func get_next_tunnel_spacing() -> float:
	var biome = get_current_biome()
	if biome:
		if biome.is_water or biome.biome_name.contains("Silhouette"):
			# 1000m to 1500m = 30000 to 45000 pixels
			return randf_range(30000.0, 45000.0)
	return 30000.0 # Default 1000m

func cycle_biome() -> void:
	# Always reinitialize if we have fewer biomes than expected
	if biomes.size() < 3:
		initialize_default_biomes()
		
	# ── Strict sequential cycle: Grass(0) → Silhouette(1) → Water(2) → Grass(0) ──
	# Queued index (from tunnel-based auto-advance) takes priority over the manual
	# B-key press so the two systems stay in sync.
	if queued_next_biome_index != -1:
		active_biome_index = queued_next_biome_index
		queued_next_biome_index = -1
	else:
		# Simple wrap-around — always step forward by one.
		active_biome_index = (active_biome_index + 1) % biomes.size()
		
	# Remove the tunnel we just crossed so it doesn't rebuild in the new biome
	var player_x = get_target_x()
	var removed_any = false
	for i in range(_tunnel_positions.size() - 1, -1, -1):
		var tx = _tunnel_positions[i]
		if abs(tx - player_x) < 3000.0:
			_tunnel_positions.remove_at(i)
			removed_any = true
			
	# Re-run geometry generation to clear the tunnel graphics in the new biome
	if removed_any:
		clear_road_geometry_caches()
		regenerate_runtime_chunks()
		
	print("Switched to biome: ", biomes[active_biome_index].biome_name)
	show_biome_banner(biomes[active_biome_index].biome_name)

func show_next_biome_announcement(biome_name: String) -> void:
	var hud = get_node_or_null("../truck/HUD")
	if not hud:
		return
		
	var old_banner = hud.get_node_or_null("BiomeBanner")
	if old_banner:
		old_banner.queue_free()
		
	var label = Label.new()
	label.name = "BiomeBanner"
	label.text = "NEXT BIOME: " + biome_name.to_upper()
	
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	label.anchors_preset = Control.PRESET_CENTER_TOP
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.position = Vector2(-250, 40)
	label.size = Vector2(500, 40)
	
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0)) # Golden warning style
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.85)
	style.border_color = Color(1.0, 0.85, 0.3, 0.3)
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
	tween.tween_interval(3.0) # Stay on screen longer inside the tunnel
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

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
	clear_road_geometry_caches()
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
	collision_layer = 3
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

# Calculate crusher road flattening factor smoothly based on coordinate distance
func get_crusher_multiplier(x: float) -> float:
	if crusher_flat_start_x == 0.0 or crusher_flat_end_x == 0.0:
		return 1.0
	
	# Transition zone of 400.0 pixels on entry and exit
	if x < crusher_flat_start_x - 400.0:
		return 1.0
	elif x < crusher_flat_start_x:
		var t = (x - (crusher_flat_start_x - 400.0)) / 400.0
		var smooth_t = t * t * (3.0 - 2.0 * t)
		return lerp(1.0, 0.0, smooth_t)
	elif x <= crusher_flat_end_x:
		return 0.0
	elif x < crusher_flat_end_x + 400.0:
		var t = (x - crusher_flat_end_x) / 400.0
		var smooth_t = t * t * (3.0 - 2.0 * t)
		return lerp(0.0, 1.0, smooth_t)
	else:
		return 1.0

# Base math function defining the height of the road without flattening or block offsets
func get_raw_base_road_height(x: float) -> float:
	if is_flat:
		return flat_height

	var base_h = 42.0
	# Water biome: flat road with gentle time-based waving
	var biome = get_current_biome()
	if biome and biome.is_water:
		var time = 0.0
		if not Engine.is_editor_hint():
			time = Time.get_ticks_msec() / 1000.0
		var wave = sin((x + seed_offset_1) * 0.005 - time * 2.0) * 12.0
		var wave2 = cos((x + seed_offset_2) * 0.012 - time * 3.5) * 4.0
		base_h = flat_height + wave + wave2
	else:
		# Make a flat starting zone around the spawn area (x = 0)
		if abs(x) < 400.0:
			base_h = 42.0
		else:
			# Smoothly transition from flat to hills using a smooth S-curve
			var raw_factor = clamp((abs(x) - 400.0) / 300.0, 0.0, 1.0)
			var factor = raw_factor * raw_factor * (3.0 - 2.0 * raw_factor)
			
			# Combine waves to create varied terrain, offset by seed
			var mult = hill_amplitude_multiplier * get_convoy_multiplier(x)
			
			var active_mountain = mountain_amplitude
			var active_long_hills = long_hills_amplitude
			var active_medium_waves = medium_waves_amplitude
			var active_smooth_spikes = smooth_spikes_amplitude
			var active_sharp_dips = sharp_dips_amplitude
			var active_lil_spikes = lil_spikes_amplitude
			var active_small_bumps = small_bumps_amplitude
			
			if terrain_type == TerrainType.BOTH:
				var dist = max(0.0, abs(x))
				# Starts smooth, but ramps up to full ruggedness potential quickly between 1000px and 7000px (~350m)
				var max_ruggedness = clamp((dist - 1000.0) / 6000.0, 0.0, 1.0)
				# Sine wave with ~25k pixel wavelength (~1.25km cycle)
				var cycle_val = sin(dist * 0.00025 + road_seed * 0.07)
				# Wide rugged peaks (stays at 1.0 for ~50% of the cycle), quick smooth breaks (~29% of the cycle)
				var raw_shift = clamp((cycle_val + 0.6) * 1.6, 0.0, 1.0)
				var blend = raw_shift * max_ruggedness
				
				active_mountain      = lerp(130.0, 220.0, blend)
				active_long_hills    = lerp(60.0, 85.0, blend)
				active_medium_waves  = lerp(35.0, 50.0, blend)
				active_smooth_spikes = lerp(15.0, 65.0, blend)
				active_sharp_dips    = lerp(8.0, 25.0, blend)
				active_lil_spikes    = lerp(0.0, 18.0, blend)
				active_small_bumps   = lerp(6.0, 12.0, blend)
			
			var mountains     = sin((x + seed_offset_3 * 0.3 + seed_offset_1 * 0.7) * 0.0003) * active_mountain * mult
			var long_hills    = sin((x + seed_offset_1) * 0.0007) * active_long_hills * mult
			var medium_waves  = cos((x + seed_offset_2) * 0.0013) * active_medium_waves * mult
			var smooth_spikes = sin((x + seed_offset_2 * 1.5 + seed_offset_3) * 0.006) * active_smooth_spikes * mult
			var sharp_dips    = sin((x + seed_offset_2 * 0.6 + seed_offset_3) * 0.003) * active_sharp_dips * mult
			var lil_spikes    = sin((x + seed_offset_1 * 2.1 + seed_offset_2) * 0.022) * active_lil_spikes * mult
			var small_bumps   = sin((x + seed_offset_3) * 0.008) * active_small_bumps * mult
			
			var height = 42.0 + (mountains + long_hills + medium_waves + smooth_spikes + sharp_dips + lil_spikes + small_bumps)
			base_h = lerp(42.0, height, factor)


	# Apply crusher flat land flattening
	var crusher_mult = get_crusher_multiplier(x)
	if crusher_mult < 1.0:
		base_h = lerp(flat_height, base_h, crusher_mult)
		
	return base_h

# Base math function defining the height of the road without flattening
func get_base_road_height(x: float) -> float:
	var target_x = x

	# Freeze height BEFORE upward cliff (approach run-up)
	var block_before = get_active_block_before(x)
	if not block_before.is_empty():
		target_x = block_before["x"] - block_flat_before
		var raw_h = get_raw_base_road_height(target_x)
		return raw_h + get_block_height_offset(x)

	# Downward drop: flat landing zone + smooth blend back to same global level
	const DOWN_TRANSITION := 700.0 # pixels over which height blends back to natural
	var down_block = _get_down_block_in_range(x, block_flat_after + DOWN_TRANSITION)
	if not down_block.is_empty():
		var bx = down_block["x"]
		var drop_amount = down_block["height"]  # How many pixels downward the cliff drops
		var flat_end = bx + block_flat_after
		# Base (UP-block-only) offset at and after the cliff — stays the same since DOWN
		# blocks no longer contribute to cumulative offset
		var base_offset = get_block_height_offset(bx)
		if x < flat_end:
			# Flat landing pad at the lower level
			var raw_h = get_raw_base_road_height(bx) + base_offset + drop_amount
			return raw_h
		else:
			# Smooth S-curve blend from lower level back to natural terrain height
			var t = clamp((x - flat_end) / DOWN_TRANSITION, 0.0, 1.0)
			var factor = t * t * (3.0 - 2.0 * t) # smoothstep
			var landing_h = get_raw_base_road_height(bx) + base_offset + drop_amount
			var natural_h  = get_raw_base_road_height(x)  + get_block_height_offset(x)
			return lerp(landing_h, natural_h, factor)

	var raw_h = get_raw_base_road_height(target_x)
	return raw_h + get_block_height_offset(x)

## Returns the block if x is in the flat zone BEFORE an upward cliff
func get_active_block_before(x: float) -> Dictionary:
	if not enable_blocks:
		return {}
	var biome = get_current_biome()
	if biome and biome.is_water:
		return {}
	var interval_size = 20000.0
	var current_idx = int(floor(x / interval_size))
	for idx in range(current_idx, current_idx + 2):
		var block = get_block_at_interval(idx)
		if not block.is_empty() and block.get("type", "up") == "up":
			var block_x = block["x"]
			if x >= block_x - block_flat_before and x < block_x:
				return block
	return {}

## Returns a down-type block if x falls within search_range pixels after its cliff edge
func _get_down_block_in_range(x: float, search_range: float) -> Dictionary:
	if not enable_blocks:
		return {}
	var biome = get_current_biome()
	if biome and biome.is_water:
		return {}
	var interval_size = 20000.0
	var current_idx = int(floor(x / interval_size))
	for idx in range(max(0, current_idx - 1), current_idx + 2):
		var block = get_block_at_interval(idx)
		if not block.is_empty() and block.get("type", "up") == "down":
			var bx = block["x"]
			if x >= bx and x < bx + search_range:
				return block
	return {}

func has_tunnel_at_chunk_static(chunk_index: int) -> bool:
	var spawn_buffer_chunks = int(ceil(1500.0 / chunk_width))
	if abs(chunk_index) <= spawn_buffer_chunks:
		return false
		
	if Engine.is_editor_hint():
		var spacing_chunks = int(ceil(90000.0 / chunk_width))
		return abs(chunk_index) % spacing_chunks == 0
		
	# Check if this chunk index contains any planned tunnel position
	var chunk_start = chunk_index * chunk_width
	var chunk_end = (chunk_index + 1) * chunk_width
	for tx in _tunnel_positions:
		if tx >= chunk_start and tx < chunk_end:
			return true
			
	return false

func should_spawn_house_static(chunk_idx: int) -> bool:
	if chunk_idx <= 1:
		return false
	if has_tunnel_at_chunk_static(chunk_idx):
		return false
	var biome = get_current_biome()
	if biome and biome.is_water:
		return false
		
	var spawn_chance = clamp(0.30 * (chunk_width / 3000.0), 0.05, 0.5)
	var chunk_rng = RandomNumberGenerator.new()
	chunk_rng.seed = hash(chunk_idx + road_seed * 1109)
	if chunk_rng.randf() > spawn_chance:
		return false
		
	var min_spacing_chunks = int(ceil(5000.0 / chunk_width))
	for prev_idx in range(chunk_idx - min_spacing_chunks, chunk_idx):
		if prev_idx > 0:
			if has_tunnel_at_chunk_static(prev_idx):
				continue
			var prev_rng = RandomNumberGenerator.new()
			prev_rng.seed = hash(prev_idx + road_seed * 1109)
			var prev_chance = clamp(0.30 * (chunk_width / 3000.0), 0.05, 0.5)
			if prev_rng.randf() <= prev_chance:
				return false
	return true

func is_near_tunnel(x: float) -> bool:
	var check_dist = 2000.0
	var min_chunk = int(floor((x - check_dist) / chunk_width))
	var max_chunk = int(floor((x + check_dist) / chunk_width))
	for check_idx in range(min_chunk, max_chunk + 1):
		if has_tunnel_at_chunk_static(check_idx):
			return true
	return false

func is_near_house(x: float) -> bool:
	var check_dist = 1500.0
	var min_chunk = int(floor((x - check_dist) / chunk_width))
	var max_chunk = int(floor((x + check_dist) / chunk_width))
	for check_idx in range(min_chunk, max_chunk + 1):
		if should_spawn_house_static(check_idx):
			return true
	return false

func get_block_at_interval(idx: int) -> Dictionary:
	if not enable_blocks or idx < 0:
		return {}
		
	if block_cache.has(idx):
		return block_cache[idx]
		
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(road_seed) + "_block_" + str(idx))
	
	var interval_size = 20000.0 # 1000 meters * 20 px/m
	var start_x = idx * interval_size
	
	var min_x = start_x + 2000.0
	var max_x = start_x + interval_size - 2000.0
	if idx == 0:
		min_x = 4000.0
		
	if min_x >= max_x:
		return {}
		
	var spawn_x = 0.0
	var found = false
	
	# Attempt to find a valid location that does not conflict with houses or tunnels
	for attempt in range(15):
		var candidate_x = rng.randf_range(min_x, max_x)
		if not is_near_tunnel(candidate_x) and not is_near_house(candidate_x):
			spawn_x = candidate_x
			found = true
			break
			
	# If no clean spot was found after 15 attempts, fallback to a safe candidate
	if not found:
		spawn_x = rng.randf_range(min_x, max_x)
		
	var raw_h_before = get_raw_base_road_height(spawn_x - block_flat_before)
	var raw_h_after = get_raw_base_road_height(spawn_x)
	var adjusted_height = block_height + max(0.0, raw_h_after - raw_h_before)
	
	# Randomly roll for block type (upward wall or downward drop)
	var type_roll = rng.randf()
	var type = "down" if type_roll < 0.5 else "up"
		
	var block_data = {
		"x": spawn_x,
		"height": adjusted_height,
		"type": type
	}
	block_cache[idx] = block_data
	return block_data

func get_cumulative_offset_at_interval(interval_idx: int) -> float:
	if interval_idx < 0:
		return 0.0
	if cumulative_offset_cache.has(interval_idx):
		return cumulative_offset_cache[interval_idx]
		
	var prev_offset = get_cumulative_offset_at_interval(interval_idx - 1)
	var current_block_contrib = 0.0
	var block = get_block_at_interval(interval_idx)
	if not block.is_empty():
		# DOWN blocks are handled locally in get_base_road_height — they must NOT
		# pollute the global cumulative offset or the world drifts downward forever.
		if block.get("type", "up") == "up":
			current_block_contrib = -block["height"]
		
	var offset = prev_offset + current_block_contrib
	cumulative_offset_cache[interval_idx] = offset
	return offset

func get_block_height_offset(x: float) -> float:
	if not enable_blocks:
		return 0.0
		
	var biome = get_current_biome()
	if biome and biome.is_water:
		return 0.0
		
	if x < 0.0:
		return 0.0
		
	var interval_size = 20000.0
	var current_interval = int(floor(x / interval_size))
	
	var offset = get_cumulative_offset_at_interval(current_interval - 1)
	
	var block = get_block_at_interval(current_interval)
	if not block.is_empty():
		# DOWN blocks are excluded — their drop is handled locally in get_base_road_height
		if x >= block["x"] and block.get("type", "up") == "up":
			offset -= block["height"]
			
	return offset

func get_block_in_range(x1: float, x2: float) -> Dictionary:
	if not enable_blocks:
		return {}
		
	var biome = get_current_biome()
	if biome and biome.is_water:
		return {}
		
	var interval_size = 20000.0
	var start_idx = int(floor(x1 / interval_size))
	var end_idx = int(floor(x2 / interval_size))
	
	for idx in range(start_idx, end_idx + 1):
		var block = get_block_at_interval(idx)
		if not block.is_empty():
			if block["x"] >= x1 and block["x"] < x2:
				return block
	return {}

# Returns the world-X of the active delivery or tow destination, or -1 if none
func _get_active_mission_destination_x() -> float:
	if delivery_target_chunk != -1:
		return delivery_target_chunk * chunk_width
	if towing_target_chunk != -1:
		return towing_target_chunk * chunk_width
	return -1.0

func start_active_event(event_name: String) -> void:
	if event_name == "Convoy":
		is_convoy_active = true
		has_convoy_ended = false
		convoy_start_x = get_target_x()
		convoy_auto_end_x = -1.0
		# If delivery or tow is active, auto-end convoy before the destination
		var dest_x = _get_active_mission_destination_x()
		if dest_x > 0.0:
			# End convoy 5000px (250m) before destination so road has time to un-flatten
			convoy_auto_end_x = dest_x - 5000.0
			print("[Road] Convoy capped: will auto-end at X=", convoy_auto_end_x, " (destination at X=", dest_x, ")")
		clear_road_geometry_caches()
		regenerate_runtime_chunks()

func end_active_event(event_name: String) -> void:
	if event_name == "Convoy":
		is_convoy_active = false
		has_convoy_ended = true
		convoy_end_x = get_target_x()
		convoy_auto_end_x = -1.0
		clear_road_geometry_caches()
		regenerate_runtime_chunks()

func is_event_active() -> bool:
	if Engine.is_editor_hint():
		return false
		
	# Check local convoy active state
	if get("is_convoy_active") == true:
		return true
		
	# Check local racing active state
	if get("is_racing_active") == true:
		return true
		
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
			var crusher_bar = hud.get_node_or_null("CrusherProgressBar")
			if crusher_bar and is_instance_valid(crusher_bar):
				return true
	return false

# Deterministically get tunnel details for a given chunk
func get_tunnel_at_chunk(chunk_index: int) -> Dictionary:
	if tunnel_cache.has(chunk_index):
		return tunnel_cache[chunk_index]
		
	# Avoid tunnels too close to spawn (within 1500 units)
	var spawn_buffer_chunks = int(ceil(1500.0 / chunk_width))
	if abs(chunk_index) <= spawn_buffer_chunks:
		return {}
		
	var found_tx: float = -1.0
	if Engine.is_editor_hint():
		var spacing_chunks = int(ceil(90000.0 / chunk_width))
		if abs(chunk_index) % spacing_chunks == 0:
			found_tx = (chunk_index + 0.5) * chunk_width
	else:
		# Use the dynamic planned positions at runtime
		for tx in _tunnel_positions:
			if tx >= chunk_index * chunk_width and tx < (chunk_index + 1) * chunk_width:
				found_tx = tx
				break
				
	if found_tx != -1.0:
		var base_y = get_base_road_height(found_tx)
		var tunnel_data = {
			"x": found_tx,
			"y": base_y,
			"width": 2000.0,
			"height": 320.0
		}
		tunnel_cache[chunk_index] = tunnel_data
		return tunnel_data
		
	return {}

# Returns true when the terrain at world-x is in a smooth (low-ruggedness) zone.
# Works for SMOOTH, and for BOTH mode by reading the same blend formula used in get_raw_base_road_height.
func is_smooth_zone_at_x(x: float) -> bool:
	if terrain_type == TerrainType.SMOOTH:
		return true
	if terrain_type == TerrainType.BOTH:
		var dist = max(0.0, abs(x))
		var max_ruggedness = clamp((dist - 1000.0) / 6000.0, 0.0, 1.0)
		var cycle_val = sin(dist * 0.00025 + road_seed * 0.07)
		var raw_shift = clamp((cycle_val + 0.6) * 1.6, 0.0, 1.0)
		var blend = raw_shift * max_ruggedness
		# blend < 0.25 is considered a smooth zone
		return blend < 0.25
	return false

# Deterministically get bridge details for a given chunk
func get_bridge_at_chunk(chunk_index: int) -> Dictionary:
	# Avoid bridge spawn near start
	if abs(chunk_index) <= 2:
		return {}
	
	# Avoid bridge in water biome
	var biome = get_current_biome()
	if biome and biome.is_water:
		return {}
	
	# Only spawn bridges during smooth terrain zones (SMOOTH mode, or BOTH mode in a smooth window)
	var center_x = (chunk_index + 0.5) * chunk_width
	if not is_smooth_zone_at_x(center_x):
		return {}
		
	# Spawn a bridge every 8 chunks (e.g. chunk index % 8 == 5)
	if abs(chunk_index) % 8 == 5:
		# Check if there is an elevator or a tunnel at this chunk (to avoid overlap)
		var tunnel = get_tunnel_at_chunk(chunk_index)
		if not tunnel.is_empty():
			return {}
		var elev = get_elevator_data_for_chunk(chunk_index)
		if not elev.is_empty():
			return {}
			
		var base_y = get_base_road_height(center_x)
		return {
			"x": center_x,
			"y": base_y,
			"width": 700.0
		}
	return {}

# Math function defining the height of the road at any X coordinate, flattened inside tunnels and paddings, smoothed in transitions
func get_road_height(x: float) -> float:
	# Check for bridge canyons first
	var min_chunk_idx = int(floor((x - 1000.0) / chunk_width))
	var max_chunk_idx = int(floor((x + 1000.0) / chunk_width))
	for check_idx in range(min_chunk_idx, max_chunk_idx + 1):
		var bridge = get_bridge_at_chunk(check_idx)
		if not bridge.is_empty():
			var bx = bridge["x"]
			var by = bridge["y"]
			var bw = bridge["width"]
			var half_w = bw / 2.0
			var dist = x - bx
			if abs(dist) < half_w:
				# Smooth parabolic canyon profile
				var factor = (cos((dist / half_w) * PI) + 1.0) / 2.0
				return by + factor * 260.0

	# Determine range of chunk indices that can physically influence the height at x
	var max_influence = 2500.0 # Safe upper bound for half width (1000) + padding (200) + transition (800)
	min_chunk_idx = int(floor((x - max_influence) / chunk_width))
	max_chunk_idx = int(floor((x + max_influence) / chunk_width))
	
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
	return step_size * 2.0 # Spaced twice as far apart for 2x fewer polygons and smoother physics rendering

func get_current_view_distance() -> float:
	var biome = get_current_biome()
	if biome and biome.is_water:
		return 3000.0 # Only load chunks near the camera to keep CPU usage low
	return view_distance * 0.5 # Load 50% fewer chunks offscreen to optimize memory and CPU usage


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
		var block = get_block_in_range(x, min(end_x, x + step))
		if not block.is_empty():
			var block_x = block["x"]
			var y_before = get_road_height(block_x - 0.01)
			surface_points.append(Vector2(block_x, y_before))
			var y_after = get_road_height(block_x)
			surface_points.append(Vector2(block_x, y_after))
			x = block_x + 0.01
		else:
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

func is_mission_or_event_active() -> bool:
	if is_event_active():
		return true
	if delivery_target_chunk != -1:
		return true
	if racing_target_chunk != -1 or is_racing_active:
		return true
	if towing_target_chunk != -1 or is_towing_active:
		return true
	return false

func _update_tunnel_spawning(current_x: float) -> void:
	var mission_active = is_mission_or_event_active()
	
	if _was_mission_active and not mission_active:
		_mission_end_x = current_x
		
	_was_mission_active = mission_active
	
	if _tunnel_is_queued:
		if not mission_active:
			if _mission_end_x == -1.0:
				_mission_end_x = current_x
			# 300 meters = 9000 pixels
			if current_x >= _mission_end_x + 9000.0:
				# Spawn the tunnel in the next chunk ahead
				var current_view_dist = get_current_view_distance()
				var spawn_chunk = int(ceil((current_x + current_view_dist) / chunk_width))
				var tx = (spawn_chunk + 0.5) * chunk_width
				
				_tunnel_positions.append(tx)
				_tunnel_is_queued = false
				next_planned_tunnel_x = tx + get_next_tunnel_spacing()
				_mission_end_x = -1.0
				
				# Regenerate chunks immediately to apply the new tunnel
				clear_road_geometry_caches()
				regenerate_runtime_chunks()
	else:
		var current_view_dist = get_current_view_distance()
		if current_x + current_view_dist >= next_planned_tunnel_x:
			if mission_active:
				_tunnel_is_queued = true
				_mission_end_x = -1.0
			else:
				var chunk_idx = int(round(next_planned_tunnel_x / chunk_width))
				var tx = (chunk_idx + 0.5) * chunk_width
				_tunnel_positions.append(tx)
				next_planned_tunnel_x = tx + get_next_tunnel_spacing()
				
				# Regenerate chunks immediately to apply the new tunnel
				clear_road_geometry_caches()
				regenerate_runtime_chunks()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	# Auto-end convoy before mission destination if a cap was set
	if is_convoy_active and convoy_auto_end_x > 0.0:
		if get_target_x() >= convoy_auto_end_x:
			print("[Road] Convoy auto-ended before mission destination.")
			end_active_event("Convoy")
	
	# Throttle chunk updates (check every 8 frames instead of every frame)
	if Engine.get_physics_frames() % 8 == 0:
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
	var player_x = get_target_x()
	var current_view_dist = get_current_view_distance()
	
	for i in active_chunks.keys():
		var chunk = active_chunks[i]
		var start_x = i * chunk_width
		var end_x = (i + 1) * chunk_width
		
		# Optimization: Only update dynamic wave geometry for chunks that are close to the screen/camera
		if abs(start_x + chunk_width * 0.5 - player_x) > current_view_dist * 0.75:
			continue
		
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

func get_elevator_data_for_chunk(chunk_idx: int) -> Dictionary:
	if not enable_blocks:
		return {}
		
	var biome = get_current_biome()
	if biome and biome.is_water:
		return {}
		
	var start_x = chunk_idx * chunk_width
	var end_x = (chunk_idx + 1) * chunk_width
	
	var start_interval = int(floor((start_x - 2000.0) / 20000.0))
	var end_interval = int(floor((end_x + 2000.0) / 20000.0))
	
	for idx in range(max(0, start_interval), end_interval + 1):
		var block = get_block_at_interval(idx)
		if not block.is_empty():
			# Down-type blocks: no elevator — truck drives off the cliff freely
			if block.get("type", "up") == "down":
				continue
			var block_x = block["x"]
			var elev_x = block_x - 120.0 # Elevator sits before the upward wall
			if elev_x >= start_x and elev_x < end_x:
				var y_before = get_road_height(block_x - 0.01)
				var y_after = get_road_height(block_x)
				var cliff_height = y_before - y_after
				if abs(cliff_height) <= 10.0:
					return {}
				return {
					"x": elev_x,
					"travel_height": cliff_height
				}
	return {}

func spawn_elevator_node(elevator_data: Dictionary) -> Node2D:
	var elev_scene = load("res://road/simple_elevator.tscn")
	if not elev_scene:
		return null
		
	# Create a container node to hold both elevators so chunk cleanup works out-of-the-box
	var container = Node2D.new()
	container.name = "ElevatorsContainer"
	add_child(container)
	
	var road_y = get_road_height(elevator_data["x"])
	
	# 1. Player Elevator (Cyber Blue, layer 1)
	var player_elev = elev_scene.instantiate() as Node2D
	player_elev.name = "PlayerElevator"
	player_elev.position = Vector2(elevator_data["x"], road_y)
	player_elev.set("travel_height", elevator_data["travel_height"])
	player_elev.set("is_opponent_elevator", false)
	player_elev.set("width", 200.0)
	container.add_child(player_elev)
	
	# 2. Opponent Elevator (Neon Pink, layer 2)
	var opponent_elev = elev_scene.instantiate() as Node2D
	opponent_elev.name = "OpponentElevator"
	opponent_elev.position = Vector2(elevator_data["x"], road_y)
	opponent_elev.set("travel_height", elevator_data["travel_height"])
	opponent_elev.set("is_opponent_elevator", true)
	opponent_elev.set("width", 220.0) # Slightly wider to clearly show both layers visually
	container.add_child(opponent_elev)
	
	return container

func spawn_tunnel_node(chunk_index: int, tunnel_data: Dictionary) -> Node2D:
	var tunnel_scene = load("res://road/tunnel.tscn")
	if not tunnel_scene:
		return null
	var tunnel = tunnel_scene.instantiate() as Node2D
	tunnel.position = Vector2(tunnel_data["x"], tunnel_data["y"])
	
	# Scale tunnel horizontally based on custom width (default design width in tscn is 1000)
	var default_width = 1000.0
	var scale_factor = tunnel_data.get("width", default_width) / default_width
	tunnel.scale = Vector2(scale_factor, 1.0)
	
	add_child(tunnel)
	return tunnel

func spawn_physics_bridge(chunk_index: int, bridge_x: float, bridge_y: float, bridge_width: float) -> Node2D:
	var container = Node2D.new()
	container.name = "BridgeContainer"
	# Draw behind the road polygon and its Line2D surface so the bridge
	# appears to slot visually underneath the road endpoints.
	container.z_index = -1
	
	# Load the compiled script file for safe, clean runtime execution
	var bridge_script = load("res://road/bridge.gd")
	if bridge_script:
		container.set_script(bridge_script)
	add_child(container)
	
	var start_x = bridge_x - bridge_width / 2.0
	var end_x = bridge_x + bridge_width / 2.0
	var start_y = get_base_road_height(start_x)
	var end_y = get_base_road_height(end_x)
	
	container.set("start_pos", Vector2(start_x, start_y))
	container.set("end_pos", Vector2(end_x, end_y))
	
	var plank_count = 14
	var plank_length = bridge_width / plank_count
	container.set("plank_length", plank_length)
	container.set("N", plank_count + 1)
	
	if container.has_method("initialize_bridge"):
		container.call("initialize_bridge")
		
	return container

func spawn_house_node(chunk_index: int) -> Node2D:
	var house_script = load("res://road/house.gd")
	if not house_script:
		return null
	var house = Area2D.new()
	house.set_script(house_script)
	
	# Determine house type
	if chunk_index == delivery_target_chunk:
		house.set("house_type", "delivery")
	elif chunk_index == racing_target_chunk:
		house.set("house_type", "racing")
	elif chunk_index == towing_target_chunk:
		house.set("house_type", "towing")
	else:
		var type_rng = RandomNumberGenerator.new()
		type_rng.seed = hash(str(chunk_index) + "_" + str(road_seed) + "_housetype")
		var type_val = type_rng.randf()
		if type_val < 0.33:
			house.set("house_type", "racing")
		elif type_val < 0.66:
			house.set("house_type", "delivery")
		else:
			house.set("house_type", "towing")

	# Randomize horizontal offset within the chunk using seeded RNG
	var chunk_rng = RandomNumberGenerator.new()
	chunk_rng.seed = hash(str(chunk_index) + "_" + str(road_seed) + "_houseoffset")
	var offset_ratio = chunk_rng.randf_range(0.25, 0.75)
	var spawn_x = chunk_index * chunk_width + offset_ratio * chunk_width
	
	var road_y = get_road_height(spawn_x)
	house.position = Vector2(spawn_x, road_y)
	house.z_index = -2
	add_child(house)
	return house

func should_spawn_house_procedurally(chunk_idx: int) -> bool:
	if delivery_target_chunk != -1:
		return chunk_idx == delivery_target_chunk
	if racing_target_chunk != -1:
		return chunk_idx == racing_target_chunk
	if towing_target_chunk != -1:
		return chunk_idx == towing_target_chunk

	if chunk_idx <= 1:
		return false
		
	# Avoid tunnels
	var tunnel_data = get_tunnel_at_chunk(chunk_idx)
	if not tunnel_data.is_empty():
		return false
		
	# Avoid water biome
	var current_biome = get_current_biome()
	if current_biome and current_biome.is_water:
		return false
		
	# Spawn chance scales with chunk size
	var spawn_chance = clamp(0.30 * (chunk_width / 3000.0), 0.05, 0.5)
	
	# Seeded RNG for this specific chunk
	var chunk_rng = RandomNumberGenerator.new()
	chunk_rng.seed = hash(chunk_idx + road_seed * 1109)
	if chunk_rng.randf() > spawn_chance:
		return false
		
	# Ensure min spacing of 5000px between houses
	var min_spacing_chunks = int(ceil(5000.0 / chunk_width))
	for prev_idx in range(chunk_idx - min_spacing_chunks, chunk_idx):
		if prev_idx > 0:
			var prev_tunnel = get_tunnel_at_chunk(prev_idx)
			if not prev_tunnel.is_empty():
				continue
			var prev_rng = RandomNumberGenerator.new()
			prev_rng.seed = hash(prev_idx + road_seed * 1109)
			var prev_chance = clamp(0.30 * (chunk_width / 3000.0), 0.05, 0.5)
			if prev_rng.randf() <= prev_chance:
				return false
				
	return true


func spawn_house_at_player() -> void:
	var player_x = get_target_x()
	var spawn_x = player_x + 250.0
	var chunk_index = int(floor(spawn_x / chunk_width))
	
	var house_script = load("res://road/house.gd")
	if not house_script:
		return
	var house = Area2D.new()
	house.set_script(house_script)
	var type_val = randf()
	if type_val < 0.33:
		house.set("house_type", "racing")
	elif type_val < 0.66:
		house.set("house_type", "delivery")
	else:
		house.set("house_type", "towing")
	
	var road_y = get_road_height(spawn_x)
	house.position = Vector2(spawn_x, road_y)
	house.z_index = -2
	add_child(house)
	
	if active_chunks.has(chunk_index):
		if "house" in active_chunks[chunk_index] and is_instance_valid(active_chunks[chunk_index].house):
			active_chunks[chunk_index].house.queue_free()
		active_chunks[chunk_index]["house"] = house
	print("[Road] Cheat: Spawned house at X: ", spawn_x, " in chunk ", chunk_index)


func spawn_tow_house_at_player() -> void:
	var player_x = get_target_x()
	var spawn_x = player_x + 250.0
	var chunk_index = int(floor(spawn_x / chunk_width))
	
	var house_script = load("res://road/house.gd")
	if not house_script:
		return
	var house = Area2D.new()
	house.set_script(house_script)
	house.set("house_type", "towing")
	
	var road_y = get_road_height(spawn_x)
	house.position = Vector2(spawn_x, road_y)
	house.z_index = -2
	add_child(house)
	
	if active_chunks.has(chunk_index):
		if "house" in active_chunks[chunk_index] and is_instance_valid(active_chunks[chunk_index].house):
			active_chunks[chunk_index].house.queue_free()
		active_chunks[chunk_index]["house"] = house
	print("[Road] Cheat: Spawned towing house at X: ", spawn_x, " in chunk ", chunk_index)

func spawn_mystery_box_at_player() -> void:
	if is_event_active():
		print("[Road] Cannot spawn mystery box: Event is currently active!")
		return
		
	var player_x = get_target_x()
	var spawn_x = player_x + 350.0 # Spawn a little bit away (350px ahead) so it's clearly visible in front of the truck
	
	var box_scene = load("res://obstacles/mystery_box.tscn")
	if not box_scene:
		return
	var box = box_scene.instantiate()
	
	var road_y = get_road_height(spawn_x)
	box.global_position = Vector2(spawn_x, road_y - 35.0)
	
	# Add to main scene tree
	get_parent().add_child(box)
	
	# Register in coin spawner list if spawner is active so it gets cleaned up
	var spawner = get_node_or_null("/root/main/CoinSpawner")
	if spawner and "_coins" in spawner:
		var coins_arr = spawner.get("_coins")
		if coins_arr is Array:
			coins_arr.append(box)
			
	print("[Road] Cheat: Spawned mystery box at X: ", spawn_x)


func spawn_and_link_towed_car(house_pos: Vector2) -> void:
	var use_duck = randf() < 0.5
	var script_path = "res://road/towed_duck.gd" if use_duck else "res://road/towed_car.gd"
	var towed_script = load(script_path)
	if not towed_script:
		return
		
	cleanup_towed_car()
	
	var towed = RigidBody2D.new()
	towed.set_script(towed_script)
	towed.name = "TowedCar"
	
	# Determine target node to attach to and offsets
	var truck = get_node_or_null("/root/main/truck")
	var attach_body: Node2D = null
	var local_attach_offset = Vector2.ZERO
	
	if truck:
		if truck.get("is_water_mode_active") and is_instance_valid(truck.get("boat")):
			attach_body = truck.get("boat")
			local_attach_offset = Vector2(-75, 10)
		elif is_instance_valid(truck.get("container_body")):
			attach_body = truck.get("container_body")
			local_attach_offset = Vector2(-118, 10)
		elif is_instance_valid(truck.get("chassis")):
			attach_body = truck.get("chassis")
			local_attach_offset = Vector2(-50, 10)
		else:
			attach_body = truck
			
	# Spawn relative to the truck's rear attachment point if valid, otherwise fallback
	var spawn_pos = house_pos + Vector2(-120, -10)
	if attach_body:
		spawn_pos = attach_body.global_position + (local_attach_offset + Vector2(-120, 0)).rotated(attach_body.global_rotation)
	towed.global_position = spawn_pos
	
	var main = get_node_or_null("/root/main")
	if main:
		main.add_child(towed)
		
	# Link physics bodies with a spring joint
	if attach_body:
		var joint = DampedSpringJoint2D.new()
		joint.name = "TowingJoint"
		joint.disable_collision = true
		
		joint.length = 80.0
		joint.rest_length = 65.0
		joint.stiffness = 50.0
		joint.damping = 4.0
		
		joint.global_position = attach_body.global_position + local_attach_offset.rotated(attach_body.global_rotation)
		main.add_child(joint)
		
		# Now that joint is in the scene tree, get_path_to resolves correctly
		joint.node_a = joint.get_path_to(attach_body)
		joint.node_b = joint.get_path_to(towed)
		
		# Spawn visual tow rope
		var rope_script = load("res://road/tow_rope.gd")
		if rope_script:
			var rope = Node2D.new()
			rope.set_script(rope_script)
			rope.name = "TowingRope"
			rope.set("body_a", attach_body)
			rope.set("body_b", towed)
			rope.set("offset_a", local_attach_offset)
			
			var hook_offset_b = Vector2(38, -12) if use_duck else Vector2(55, -5)
			rope.set("offset_b", hook_offset_b)
			main.add_child(rope)


func cleanup_towed_car() -> void:
	var main = get_node_or_null("/root/main")
	if main:
		var towed = main.get_node_or_null("TowedCar")
		if is_instance_valid(towed):
			towed.queue_free()
		var joint = main.get_node_or_null("TowingJoint")
		if is_instance_valid(joint):
			joint.queue_free()
		var rope = main.get_node_or_null("TowingRope")
		if is_instance_valid(rope):
			rope.queue_free()


func relink_towed_car() -> void:
	var main = get_node_or_null("/root/main")
	if not main:
		return
	var towed = main.get_node_or_null("TowedCar")
	if not is_instance_valid(towed):
		return
		
	var truck = get_node_or_null("/root/main/truck")
	var attach_body: Node2D = null
	var local_attach_offset = Vector2.ZERO
	
	if truck:
		if truck.get("is_water_mode_active") and is_instance_valid(truck.get("boat")):
			attach_body = truck.get("boat")
			local_attach_offset = Vector2(-75, 10)
		elif is_instance_valid(truck.get("container_body")):
			attach_body = truck.get("container_body")
			local_attach_offset = Vector2(-118, 10)
		elif is_instance_valid(truck.get("chassis")):
			attach_body = truck.get("chassis")
			local_attach_offset = Vector2(-50, 10)
		else:
			attach_body = truck

	var old_joint = main.get_node_or_null("TowingJoint")
	if is_instance_valid(old_joint):
		old_joint.queue_free()
	var old_rope = main.get_node_or_null("TowingRope")
	if is_instance_valid(old_rope):
		old_rope.queue_free()
		
	if attach_body:
		var joint = DampedSpringJoint2D.new()
		joint.name = "TowingJoint"
		joint.disable_collision = true
		joint.length = 80.0
		joint.rest_length = 65.0
		joint.stiffness = 50.0
		joint.damping = 4.0
		
		var attach_point = attach_body.global_position + local_attach_offset.rotated(attach_body.global_rotation)
		joint.global_position = attach_point
		main.add_child(joint)
		joint.node_a = joint.get_path_to(attach_body)
		joint.node_b = joint.get_path_to(towed)
		
		var is_duck = false
		if towed.get_script():
			is_duck = "towed_duck" in towed.get_script().resource_path
		var hook_offset_b = Vector2(38, -12) if is_duck else Vector2(55, -5)
		
		# --- Position the towed vehicle at the perfect relaxed rope distance to avoid spring yank ---
		var player_rot = attach_body.global_rotation
		var forward_dir = Vector2.RIGHT.rotated(player_rot)
		
		var target_hook_pos = attach_point - forward_dir * joint.rest_length
		var target_towed_pos = target_hook_pos - hook_offset_b.rotated(player_rot)
		
		towed.global_position = target_towed_pos
		towed.global_rotation = player_rot
		towed.linear_velocity = attach_body.linear_velocity
		towed.angular_velocity = attach_body.angular_velocity
		
		# Also reset its tyres' velocities and positions if they exist
		var t_back = towed.get("tyre_back")
		var t_front = towed.get("tyre_front")
		if is_instance_valid(t_back):
			t_back.global_position = towed.global_position + Vector2(-35, 10).rotated(player_rot)
			t_back.linear_velocity = attach_body.linear_velocity
			t_back.angular_velocity = attach_body.angular_velocity
		if is_instance_valid(t_front):
			t_front.global_position = towed.global_position + Vector2(35, 10).rotated(player_rot)
			t_front.linear_velocity = attach_body.linear_velocity
			t_front.angular_velocity = attach_body.angular_velocity
			
		var rope_script = load("res://road/tow_rope.gd")
		if rope_script:
			var rope = Node2D.new()
			rope.set_script(rope_script)
			rope.name = "TowingRope"
			rope.set("body_a", attach_body)
			rope.set("body_b", towed)
			rope.set("offset_a", local_attach_offset)
			rope.set("offset_b", hook_offset_b)
			main.add_child(rope)


func create_chunk(i: int) -> void:
	var current_biome = get_current_biome()
	var start_x = i * chunk_width
	var end_x = (i + 1) * chunk_width
	
	var surface_points = PackedVector2Array()
	var x = start_x
	var step = get_current_step_size()
	while x < end_x:
		var block = get_block_in_range(x, min(end_x, x + step))
		if not block.is_empty():
			var block_x = block["x"]
			var y_before = get_road_height(block_x - 0.01)
			surface_points.append(Vector2(block_x, y_before))
			var y_after = get_road_height(block_x)
			surface_points.append(Vector2(block_x, y_after))
			x = block_x + 0.01
		else:
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
	
	# Create Line2D (Split around bridge if present)
	var line = null
	var line_right = null
	var bridge_data = get_bridge_at_chunk(i)
	
	if not bridge_data.is_empty():
		var bx = bridge_data["x"]
		var bw = bridge_data["width"]
		var half_w = bw / 2.0
		var bridge_start = bx - half_w
		var bridge_end = bx + half_w
		
		var left_points = PackedVector2Array()
		var right_points = PackedVector2Array()
		for pt in surface_points:
			if pt.x <= bridge_start:
				left_points.append(pt)
			elif pt.x >= bridge_end:
				right_points.append(pt)
				
		line = Line2D.new()
		line.points = left_points
		line.width = 0.0 if current_biome.is_water else road_thickness
		line.default_color = road_color
		add_child(line)
		
		line_right = Line2D.new()
		line_right.points = right_points
		line_right.width = 0.0 if current_biome.is_water else road_thickness
		line_right.default_color = road_color
		add_child(line_right)
	else:
		line = Line2D.new()
		line.points = surface_points
		line.width = 0.0 if current_biome.is_water else road_thickness
		line.default_color = road_color
		add_child(line)
	
	# Create second Line2D
	var line2 = null
	var line2_right = null
	if enable_second_road:
		if not bridge_data.is_empty():
			var bx = bridge_data["x"]
			var bw = bridge_data["width"]
			var half_w = bw / 2.0
			var bridge_start = bx - half_w
			var bridge_end = bx + half_w
			
			var left_points_2 = PackedVector2Array()
			var right_points_2 = PackedVector2Array()
			for pt in surface_points_2:
				if pt.x <= bridge_start:
					left_points_2.append(pt)
				elif pt.x >= bridge_end:
					right_points_2.append(pt)
					
			line2 = Line2D.new()
			line2.points = left_points_2
			line2.width = 0.0 if current_biome.is_water else road_thickness
			line2.default_color = road_color
			add_child(line2)
			
			line2_right = Line2D.new()
			line2_right.points = right_points_2
			line2_right.width = 0.0 if current_biome.is_water else road_thickness
			line2_right.default_color = road_color
			add_child(line2_right)
		else:
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
		
		# GrassDecorator2 for the second road line
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
	
	# Suppress houses during convoy (flat-road event) and crusher events
	var convoy_running: bool = get("is_convoy_active") == true
	var crusher_running: bool = crusher_flat_start_x != 0.0 and crusher_flat_end_x != 0.0
	var suppress_houses: bool = convoy_running or crusher_running

	# Spawn house based on seeded natural random distribution (no tunnels active)
	var house_node = null
	if not suppress_houses and should_spawn_house_procedurally(i):
		house_node = spawn_house_node(i)
		if used_house_chunks.has(i):
			house_node.set("has_accepted", true)
		if i == delivery_target_chunk:
			house_node.call("setup_delivery_target", delivery_crate_count, delivery_reward)
		elif i == racing_target_chunk:
			house_node.call("setup_racing_target", racing_reward)
		elif i == towing_target_chunk:
			house_node.call("setup_towing_target", towing_reward)
	
	# Spawn elevator if present
	var elevator_node = null
	var elevator_data = get_elevator_data_for_chunk(i)
	if not elevator_data.is_empty():
		elevator_node = spawn_elevator_node(elevator_data)
		
	# Spawn physics bridge at runtime if present
	var bridge_node = null
	if not Engine.is_editor_hint():
		if not bridge_data.is_empty():
			bridge_node = spawn_physics_bridge(i, bridge_data["x"], bridge_data["y"], bridge_data["width"])
		
	active_chunks[i] = {
		"collision": col_poly,
		"fill": fill,
		"line": line,
		"line_right": line_right,
		"line2": line2,
		"line2_right": line2_right,
		"grass": grass,
		"grass2": grass2,
		"house": house_node,
		"elevator": elevator_node,
		"bridge": bridge_node
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
		if "line_right" in chunk and is_instance_valid(chunk.line_right):
			chunk.line_right.queue_free()
		if "line2" in chunk and is_instance_valid(chunk.line2):
			chunk.line2.queue_free()
		if "line2_right" in chunk and is_instance_valid(chunk.line2_right):
			chunk.line2_right.queue_free()
		if "grass" in chunk and is_instance_valid(chunk.grass):
			chunk.grass.queue_free()
		if "grass2" in chunk and is_instance_valid(chunk.grass2):
			chunk.grass2.queue_free()
		if "tunnel" in chunk and is_instance_valid(chunk.tunnel):
			chunk.tunnel.queue_free()
		if "house" in chunk and is_instance_valid(chunk.house):
			chunk.house.queue_free()
		if "elevator" in chunk and is_instance_valid(chunk.elevator):
			chunk.elevator.queue_free()
		if "bridge" in chunk and is_instance_valid(chunk.bridge):
			chunk.bridge.queue_free()
		active_chunks.erase(i)

func spawn_crusher_on_next_chunk() -> void:
	var player_x = get_target_x()
	
	# Randomize number of crushers between 3 and 8
	var num_crushers = randi_range(3, 8)
	var first_crusher_x = player_x + 800.0
	var spacing = 400.0
	
	# If delivery or tow is active, cap crushers so zone ends before destination
	var dest_x = _get_active_mission_destination_x()
	if dest_x > 0.0:
		# Leave 3000px (150m) buffer before destination for the road to recover
		var max_end_x = dest_x - 3000.0
		var max_crushers = int(floor((max_end_x - first_crusher_x) / spacing)) + 1
		num_crushers = clamp(num_crushers, 1, max(1, max_crushers))
		print("[Road] Crusher capped to ", num_crushers, " (destination at X=", dest_x, ")")
	
	# Define flat road zone boundaries to cover the entire sequence dynamically
	crusher_flat_start_x = first_crusher_x - 300.0
	crusher_flat_end_x = first_crusher_x + (num_crushers - 1) * spacing + 300.0
	
	# Regenerate the road chunks immediately to apply the flat terrain
	regenerate_runtime_chunks()
	
	# Spawn num_crushers spaced continuously
	var crusher_scene = load("res://obstacles/crusher.tscn")
	if crusher_scene:
		for i in range(num_crushers):
			var spawn_x = first_crusher_x + i * spacing
			var road_y = get_road_height(spawn_x)
			
			var crusher = crusher_scene.instantiate()
			crusher.position = Vector2(spawn_x, road_y - 40.0)
			crusher.global_position = Vector2(spawn_x, road_y - 40.0)
			crusher.start_y = road_y - 40.0
			
			# Stagger the timing phase of each crusher for cascading wave movement
			crusher.time_elapsed = i * 0.7
			crusher.initialized = true
			get_parent().add_child(crusher)
			print("[Road] Crusher ", i + 1, "/", num_crushers, " spawned at X: ", spawn_x, " Y: ", road_y)
			
	# Roll 40% chance to spawn treadmill(s)
	if randf() < 0.40:
		# Decide belt direction/speed: 75% backward (-220 px/s), 25% forward (180 px/s)
		var belt_spd = -220.0 if randf() < 0.75 else 180.0
		var treadmill_script = load("res://obstacles/treadmill.gd")
		if treadmill_script:
			# 35% chance FULL COVERAGE, 65% chance GAP-BY-GAP
			if randf() < 0.35:
				var start_x = first_crusher_x - 100.0
				var end_x = first_crusher_x + (num_crushers - 1) * spacing + 100.0
				var t_width = end_x - start_x
				var t_center_x = (start_x + end_x) / 2.0
				var road_y = get_road_height(t_center_x)
				
				var treadmill = StaticBody2D.new()
				treadmill.set_script(treadmill_script)
				treadmill.set("width", t_width)
				treadmill.set("belt_speed", belt_spd)
				treadmill.position = Vector2(t_center_x, road_y)
				treadmill.global_position = Vector2(t_center_x, road_y)
				get_parent().add_child(treadmill)
				print("[Road] Spawned Full-Length Treadmill from ", start_x, " to ", end_x, " Speed: ", belt_spd)
			else:
				for i in range(num_crushers - 1):
					# 65% chance to spawn in this specific gap
					if randf() < 0.65:
						var c1_x = first_crusher_x + i * spacing
						var c2_x = first_crusher_x + (i + 1) * spacing
						var start_x = c1_x + 90.0
						var end_x = c2_x - 90.0
						var t_width = end_x - start_x
						var t_center_x = (start_x + end_x) / 2.0
						var road_y = get_road_height(t_center_x)
						
						var treadmill = StaticBody2D.new()
						treadmill.set_script(treadmill_script)
						treadmill.set("width", t_width)
						treadmill.set("belt_speed", belt_spd)
						treadmill.position = Vector2(t_center_x, road_y)
						treadmill.global_position = Vector2(t_center_x, road_y)
						get_parent().add_child(treadmill)
						print("[Road] Spawned Gap Treadmill ", i + 1, " at X: ", t_center_x, " Width: ", t_width, " Speed: ", belt_spd)
			
	# Setup the CrusherProgressBar UI under the HUD
	var hud = get_node_or_null("../truck/HUD")
	if hud and is_instance_valid(hud):
		# Clean up any existing crusher progress bar safely
		var existing = hud.get_node_or_null("CrusherProgressBar")
		if existing:
			existing.name = "CrusherProgressBarOld"
			existing.queue_free()
			
		var pb_script = load("res://ui/crusher_progress_bar.gd")
		if pb_script:
			var pb = Control.new()
			pb.set_script(pb_script)
			hud.add_child(pb)
			
			var crusher_xs: Array[float] = []
			for i in range(num_crushers):
				crusher_xs.append(first_crusher_x + i * spacing)
			pb.call("setup", crusher_flat_start_x, crusher_flat_end_x, crusher_xs)

func get_next_house_chunk(from_chunk: int) -> int:
	var check_chunk = from_chunk + 1
	var houses_found = 0
	while check_chunk < from_chunk + 200: # Scan up to 200 chunks ahead
		if should_spawn_house_procedurally(check_chunk):
			houses_found += 1
			if houses_found >= 3: # Target the 3rd house ahead (long distance)
				return check_chunk
		check_chunk += 1
	# Fallback if none found
	return from_chunk + 18


func start_racing_event() -> void:
	opponent_finished = false
	start_race_sequence()

func end_racing_event() -> void:
	if is_instance_valid(active_opponent):
		var tween = active_opponent.create_tween()
		tween.tween_property(active_opponent, "modulate:a", 0.0, 1.2)
		tween.tween_callback(active_opponent.queue_free)
		active_opponent = null

func start_delivery_race() -> void:
	opponent_finished = false
	start_race_sequence()

func start_race_sequence() -> void:
	# 1. Locate truck and Lock player controls immediately
	var truck = get_node_or_null("/root/main/truck")
	if truck:
		truck.set("controls_locked", true)
		
		# Cancel all current momentum to freeze the truck exactly in place
		var chassis = truck.get("chassis")
		if is_instance_valid(chassis):
			chassis.linear_velocity = Vector2.ZERO
			chassis.angular_velocity = 0.0
		var container_body = truck.get("container_body")
		if is_instance_valid(container_body):
			container_body.linear_velocity = Vector2.ZERO
			container_body.angular_velocity = 0.0
		var boat = truck.get("boat")
		if is_instance_valid(boat):
			boat.linear_velocity = Vector2.ZERO
			boat.angular_velocity = 0.0
		for tyre_name in ["tyre_1", "tyre_2", "tyre_3"]:
			var tyre = truck.get(tyre_name)
			if is_instance_valid(tyre):
				tyre.linear_velocity = Vector2.ZERO
				tyre.angular_velocity = 0.0
		
	# 2. Spawn opponent car exactly at player position
	if is_instance_valid(active_opponent):
		active_opponent.queue_free()
		active_opponent = null
		
	var opponent_script = load("res://road/opponent_car.gd")
	if not opponent_script:
		push_error("[Road] Failed to load res://road/opponent_car.gd")
		return
		
	active_opponent = RigidBody2D.new()
	active_opponent.set_script(opponent_script)
	active_opponent.name = "OpponentCar"
	
	# Determine vehicle type from name (Kyrie -> sports_car, Hopps -> truck)
	var opponent_vehicle_type = "sports_car" if active_opponent_name.to_lower() == "kyrie" else "truck"
	active_opponent.set("vehicle_type", opponent_vehicle_type)
	
	var spawn_pos = Vector2.ZERO
	if truck:
		var active_body = truck.get("boat") if truck.get("is_water_mode_active") else truck.get("chassis")
		if is_instance_valid(active_body):
			spawn_pos = active_body.global_position
	else:
		spawn_pos = Vector2(get_target_x(), get_road_height(get_target_x()) - 40.0)
		
	active_opponent.position = spawn_pos
	active_opponent.global_position = spawn_pos
	
	get_parent().add_child(active_opponent)
	active_opponent.set("opponent_name", active_opponent_name)
	print("[Road] Spawned opponent car at player position: ", spawn_pos, " name: ", active_opponent_name)
	
	# 3. Create Countdown Overlay in a high-priority CanvasLayer to draw on top of everything
	var main_node = get_parent()
	var count_layer = CanvasLayer.new()
	count_layer.name = "CountdownLayer"
	count_layer.layer = 100
	main_node.add_child(count_layer)
	
	var countdown_label = Label.new()
	countdown_label.name = "RaceCountdown"
	
	# Typography
	var custom_font = null
	var font_path = "res://retro_font.ttf"
	if ResourceLoader.exists(font_path):
		custom_font = load(font_path)
	if custom_font:
		countdown_label.add_theme_font_override("font", custom_font)
	
	countdown_label.add_theme_font_size_override("font_size", 96)
	countdown_label.add_theme_color_override("font_color", Color("#ffea79")) # Neon yellow
	countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	countdown_label.add_theme_constant_override("outline_size", 12)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Positioning: Full screen center
	countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	count_layer.add_child(countdown_label)
	
	# Animate helper function
	var play_bounce = func(txt: String, color_hex: String):
		var screen_size = get_viewport().get_visible_rect().size
		countdown_label.size = screen_size
		countdown_label.pivot_offset = screen_size / 2.0
		countdown_label.text = txt
		countdown_label.add_theme_color_override("font_color", Color(color_hex))
		countdown_label.scale = Vector2(0.3, 0.3)
		var t = get_tree().create_tween().set_parallel(true)
		t.tween_property(countdown_label, "scale", Vector2(1.2, 1.2), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.chain().tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.15)
		
	play_bounce.call("3", "#ff2a6d") # Hot Pink for 3
	
	var t1 = get_tree().create_timer(1.0)
	t1.timeout.connect(func():
		if not is_instance_valid(countdown_label): return
		play_bounce.call("2", "#ffb900") # Gold for 2
		
		var t2 = get_tree().create_timer(1.0)
		t2.timeout.connect(func():
			if not is_instance_valid(countdown_label): return
			play_bounce.call("1", "#00f0ff") # Cyan for 1
			
			var t3 = get_tree().create_timer(1.0)
			t3.timeout.connect(func():
				if not is_instance_valid(countdown_label): return
				play_bounce.call("GO!", "#00e676") # Green for GO!
				
				# UNLOCK controls and START race
				if is_instance_valid(truck):
					truck.set("controls_locked", false)
				if is_instance_valid(active_opponent):
					active_opponent.call("start_race")
					
				var t4 = get_tree().create_timer(1.0)
				t4.timeout.connect(func():
					if is_instance_valid(count_layer):
						count_layer.queue_free()
				)
			)
		)
	)
