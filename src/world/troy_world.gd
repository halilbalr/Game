class_name TroyWorld
extends Node3D
## The assembled city: atmosphere, terrain, fortifications and buildings.

var atmosphere: Atmosphere
## Locations and lists produced by [TroyBuilder] (gates, markers, torches...).
var info: Dictionary = {}
var night: bool = false
## Torches and hearths lit for the night missions.
var fires: Array[Fire] = []


## Builds the whole world for the given lighting preset.
func build(preset: String, quality: int) -> void:
	night = preset == "night"
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.apply(preset, quality)
	var t0 := Time.get_ticks_msec()
	Terrain.build(self)
	var t1 := Time.get_ticks_msec()
	var builder := TroyBuilder.new()
	builder.build()
	info = builder.info
	Props.build_awnings(builder.b, info)
	Props.build_torch_posts(builder.b, info)
	var tris := builder.b.triangle_count()
	builder.b.commit(self, Mats.all())
	fires = Props.place(self, info, night, quality)
	var t2 := Time.get_ticks_msec()
	print("TroyWorld: terrain %d ms, city %d ms, %d triangles, %d houses" % [t1 - t0, t2 - t1, tris,
		(info["houses"] as Array).size()])


## World position of a named place, or the citadel court when unknown.
func marker(id: String) -> Vector3:
	var m: Dictionary = info.get("markers", {})
	if m.has(id):
		return m[id]
	push_warning("TroyWorld: no marker '%s'" % id)
	return TroyLayout.ground(0.0, 12.0)
