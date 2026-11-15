class_name SeaMission
extends Mission
## Base for the voyage home: builds a [SeaWorld] and Odysseus's [Ship] in
## place of Troy, and adds steps for the sea: board the ship, go ashore,
## sail to a point.

var sea_world: SeaWorld
var ship: Ship


func _init() -> void:
	troy = false
	hero = "odysseus"


## Override: raise the islands of this episode (see SeaWorld.add_island).
func build_islands() -> void:
	pass


func build_stage() -> void:
	sea_world = SeaWorld.new()
	add_child(sea_world)
	sea_world.setup(preset)
	build_islands()
	ship = Ship.new()
	ship.sea = sea_world.sea
	ship.ground = sea_world.ground_height
	add_child(ship)


func ground_y(x: float, z: float) -> float:
	return sea_world.ground_height(x, z)


## Puts the player aboard at [param spot] (ship.helm or ship.mast_spot).
## With [param steer] the movement controls row and steer.
func board(spot: Node3D, steer: bool) -> void:
	player.velocity = Vector3.ZERO
	player.riding = true
	player.move_enabled = false
	player.reparent(spot, false)
	player.position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	ship.controlled = steer
	ship.moored = false


## Sets the player down on land at [param pos], facing [param yaw].
func go_ashore(pos: Vector3, yaw: float) -> void:
	ship.controlled = false
	player.reparent(self, false)
	player.riding = false
	player.move_enabled = true
	place_player(pos, yaw)


## Waits until the ship is within [param radius] metres of [param pos].
## Self-playing, the ship is put there.
func sail_to(pos: Vector3, radius: float) -> void:
	_trace("sail to %s within %.0f m" % [str(pos.round()), radius])
	if autoplay:
		await wait(0.1)
		ship.place(pos, yaw_to(ship.global_position, pos))
		await wait(0.1)
		return
	await until(func() -> bool:
		var d := ship.global_position - pos
		return Vector2(d.x, d.z).length() <= radius)
