extends Node
## Autoload "Sfx": placeholder until the synthesised sound bank is built.


## Plays a named sound at a world position (no-op for now).
func play_at(_id: StringName, _pos: Vector3, _volume_db: float = 0.0) -> void:
	pass


## Plays a named non-positional sound (no-op for now).
func play(_id: StringName, _volume_db: float = 0.0) -> void:
	pass


## Starts a named piece of music, replacing any other (no-op for now).
func music(_id: StringName) -> void:
	pass
