class_name Interactable
extends Node3D
## Something the player can use by looking at it and pressing Interact.
## Missions connect to [signal used].

signal used(player: Node3D)

## Text shown after the key name, e.g. "Lift the bar".
var prompt: String = "Use"
## Reach in metres.
var radius: float = 2.4
var enabled: bool = true
## Seconds the key must be held; 0 for an instant use.
var hold_seconds: float = 0.0
## Height above this node's origin that the player must look at.
var focus_height: float = 1.0


func _enter_tree() -> void:
	add_to_group(&"interactables")


## Point in the world the player aims at to use this.
func focus_point() -> Vector3:
	return global_position + Vector3(0.0, focus_height, 0.0)


## Called by the player when the use completes.
func interact(player: Node3D) -> void:
	if enabled:
		used.emit(player)
