class_name TestCase
extends RefCounted
## Minimal test base for the project's own runner (tests/run_tests.gd).
## A suite extends this, names its file `[system]_[feature]_test.gd` and its
## methods `test_[scenario]_[expected]`. Methods may be coroutines.

var failures: Array[String] = []
var checks: int = 0
## The running SceneTree, for suites that need nodes and physics frames.
var tree: SceneTree
var _current: String = ""


func begin(method: String) -> void:
	_current = method


## Fails the current test unless [param condition] holds.
func check(condition: bool, message: String = "") -> void:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [_current, message if message != "" else "condition was false"])


## Fails unless the two values are equal.
func eq(actual: Variant, expected: Variant, message: String = "") -> void:
	check(actual == expected, "%s (got %s, expected %s)" % [message, str(actual), str(expected)])


## Fails unless the two numbers are within [param tolerance].
func near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	check(absf(actual - expected) <= tolerance, "%s (got %f, expected %f ± %f)" % [message, actual, expected, tolerance])


## Waits [param count] physics frames.
func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
