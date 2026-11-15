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
	isle.dress(self)
	islands.append(isle)


## Bakes the sea floor round the islands into a small height map for the
## water's shader (see [method Sea.set_floor]). Call once the islands are in.
func bake_shallows() -> void:
	if islands.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for isle in islands:
		var r := isle.radii * 1.4 + Vector2(20.0, 20.0)
		lo = lo.min(isle.center - r)
		hi = hi.max(isle.center + r)
	var cell := 4.0 if Game.lite else 3.0
	var w := mini(int(ceil((hi.x - lo.x) / cell)), 2048)
	var d := mini(int(ceil((hi.y - lo.y) / cell)), 2048)
	var img := Image.create(w, d, false, Image.FORMAT_R8)
	img.fill(Color(0, 0, 0))
	for isle in islands:
		var r := isle.radii * 1.4 + Vector2(20.0, 20.0)
		var i0 := maxi(int((isle.center.x - r.x - lo.x) / cell), 0)
		var i1 := mini(int((isle.center.x + r.x - lo.x) / cell), w - 1)
		var j0 := maxi(int((isle.center.y - r.y - lo.y) / cell), 0)
		var j1 := mini(int((isle.center.y + r.y - lo.y) / cell), d - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var h := isle.height(lo.x + (i + 0.5) * cell, lo.y + (j + 0.5) * cell)
				var v := clampf((h + 12.0) / 16.0, 0.0, 1.0)
				if v > img.get_pixel(i, j).r:
					img.set_pixel(i, j, Color(v, 0, 0))
	sea.set_floor(ImageTexture.create_from_image(img), Vector4(lo.x, lo.y, w * cell, d * cell))


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
