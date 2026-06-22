extends Resource
class_name BiomeConfig

@export var biome_name: String = "Default"

@export_group("Sky Background")
@export var sky_texture: Texture2D = null
@export var sky_modulate: Color = Color.WHITE
@export var sky_shader: Shader = null
@export var sky_shader_params: Dictionary = {}

@export_group("Road Colors")
@export var road_color: Color = Color(0.196, 0.98, 0.34, 1)
@export var road_fill_color: Color = Color(0.12, 0.12, 0.14, 1)
@export var use_silhouette_road: bool = false
@export var road_silhouette_color: Color = Color.BLACK

@export_group("Foliage Settings")
@export var spawn_foliage: bool = true
@export var foliage_density_multiplier: float = 1.0
@export var foliage_color: Color = Color(0, 0, 0, 0)


@export_group("Truck Styling (Silhouette Filter)")
@export var use_silhouette_truck: bool = false
@export var truck_silhouette_color: Color = Color.BLACK
