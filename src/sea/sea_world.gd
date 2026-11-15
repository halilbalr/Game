class_name SeaWorld
extends Node3D
## The world of a voyage: sky and weather, the open [Sea], islands, and a
## navigation mesh for men who go ashore. Built fresh by each voyage
## mission (see [method Mission.build_stage]).

var atmosphere: Atmosphere
var sea: Sea
var islands: Array[Island] = []
var preset: String = "day"
var nav_region: NavigationRegion3D


## Sets up sky and sea for [param preset_name] ("day", "evening", "night").
func setup(preset_name: String) -> void:
	name = "SeaWorld"
	atmosphere = Atmosphere.new()
	atmosphere.fog_floor = 0.0
	add_child(atmosphere)
	sea = Sea.new()
	add_child(sea)
	set_preset(preset_name)


func set_preset(preset_name: String) -> void:
	preset = preset_name
	var q := int(Game.settings["quality"])
	atmosphere.apply(preset, q, Game.lite, Game.lite_tier() if Game.lite else {})


## Raises an island and keeps it for [method ground_height].
func add_island(isle: Island) -> void:
	isle.build(self)
	islands.append(isle)


## Ground height at (x, z): the highest island there, or deep water.
func ground_height(x: float, z: float) -> float:
	var h := -30.0
	for isle in islands:
		h = maxf(h, isle.height(x, z))
	return h


## Bakes where men can walk ashore, within [param area].
func bake_navigation(area: AABB) -> void:
	var t0 := Time.get_ticks_msec()
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = 0.4
	navmesh.cell_height = 0.25
	navmesh.agent_radius = 0.4
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.5
	navmesh.agent_max_slope = 40.0
	navmesh.region_min_size = 6.0
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	navmesh.filter_baking_aabb = area
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	nav_region = NavigationRegion3D.new()
	nav_region.navigation_mesh = navmesh
	add_child(nav_region)
	print("SeaWorld: navigation baked in %d ms (%d polygons)" % [Time.get_ticks_msec() - t0, navmesh.get_polygon_count()])
