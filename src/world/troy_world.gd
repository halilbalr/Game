class_name TroyWorld
extends Node3D
## The assembled city: atmosphere, terrain, fortifications, buildings and the
## navigation mesh. Built once and shared between the menu and the missions;
## only the lighting changes between them.

## Bump when the walkable geometry changes so cached navigation is rebuilt.
const NAV_VERSION := 3

var atmosphere: Atmosphere
## Locations and lists produced by [TroyBuilder] (gates, markers, torches...).
var info: Dictionary = {}
var preset: String = "day"
var night: bool = false
## Torches and hearths, lit only at night.
var fires: Array[Fire] = []
var nav_region: NavigationRegion3D
## The Achaean ships and huts on the far shore (hidden on the last night).
var camp: Node3D
## Triangle count of the built city: changes whenever the geometry does.
var _signature: int = 0
var _lamp_wait: float = 0.0


func _init() -> void:
	name = "TroyWorld"


## Builds the whole world for the given lighting preset.
func build(preset_name: String, quality: int) -> void:
	preset = preset_name
	night = preset == "night"
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.apply(preset, quality, Game.lite)
	# Phones light each mesh with at most eight lamps, so the world is cut
	# into smaller pieces there; smaller pieces also cull better.
	Mats.set_detail(0.0 if Game.lite else 1.0)
	var t0 := Time.get_ticks_msec()
	Terrain.build(self, 16 if Game.lite else 32)
	var t1 := Time.get_ticks_msec()
	var builder := TroyBuilder.new()
	builder.b.chunk_size = 48.0 if Game.lite else 96.0
	builder.build()
	info = builder.info
	Props.build_awnings(builder.b, info)
	Props.build_torch_posts(builder.b, info)
	var tris := builder.b.triangle_count()
	_signature = tris
	builder.b.commit(self, Mats.all())
	fires = Props.place(self, info, quality)
	for f in fires:
		f.set_lit(night)
	camp = Props.build_camp(self)
	# On the night of the horse the fleet has sailed.
	camp.visible = not night
	var t2 := Time.get_ticks_msec()
	print("TroyWorld: terrain %d ms, city %d ms, %d triangles, %d houses" % [t1 - t0, t2 - t1, tris,
		(info["houses"] as Array).size()])


## Re-lights the city for another hour and clears any trace of fire.
func set_preset(preset_name: String, quality: int) -> void:
	preset = preset_name
	night = preset == "night"
	atmosphere.set_fire(0.0)
	atmosphere.apply(preset, quality, Game.lite)
	Mats.set_soot(0.0)
	for f in fires:
		f.set_lit(night)
	camp.visible = not night


func _process(delta: float) -> void:
	# The browser and phone renderers draw only a few dozen lamps at once and
	# cannot fade them by distance, so torches far from the eye are put out.
	if not Game.lite or not night:
		return
	_lamp_wait -= delta
	if _lamp_wait > 0.0:
		return
	_lamp_wait = 0.3
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for f in fires:
		f.visible = f.global_position.distance_squared_to(eye) < 60.0 * 60.0


## World position of a named place, or the citadel court when unknown.
func marker(id: String) -> Vector3:
	var m: Dictionary = info.get("markers", {})
	if m.has(id):
		return m[id]
	push_warning("TroyWorld: no marker '%s'" % id)
	return TroyLayout.ground(0.0, 12.0)


## Record for a gate: pos, normal (outward), width, height, door_offset.
func gate(id: String) -> Dictionary:
	return (info.get("gates", {}) as Dictionary).get(id, {})


## Bakes (or loads from cache) the navigation mesh. The world must be in the tree.
func ensure_navigation() -> void:
	if nav_region != null:
		return
	var t0 := Time.get_ticks_msec()
	var cache := "user://troy_nav_v%d_%d.res" % [NAV_VERSION, _signature]
	var navmesh: NavigationMesh = null
	if ResourceLoader.exists(cache):
		navmesh = ResourceLoader.load(cache) as NavigationMesh
	var cached := navmesh != null
	if navmesh == null:
		navmesh = NavigationMesh.new()
		navmesh.cell_size = 0.4
		navmesh.cell_height = 0.25
		navmesh.agent_radius = 0.4
		navmesh.agent_height = 1.75
		navmesh.agent_max_climb = 0.5
		navmesh.agent_max_slope = 46.0
		navmesh.region_min_size = 6.0
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		navmesh.geometry_collision_mask = 1
		navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
		navmesh.filter_baking_aabb = AABB(Vector3(-480.0, -30.0, -100.0), Vector3(730.0, 60.0, 450.0))
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(navmesh, source, self)
		NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
		ResourceSaver.save(navmesh, cache)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	nav_region.navigation_mesh = navmesh
	add_child(nav_region)
	print("TroyWorld: navigation %s in %d ms (%d polygons)" % ["loaded" if cached else "baked",
		Time.get_ticks_msec() - t0, navmesh.get_polygon_count()])
