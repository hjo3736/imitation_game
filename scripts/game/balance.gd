class_name Balance
extends RefCounted
## Game rule numbers, read by key (docs/roles/leader/outputs/13 design, section 3).
## Part of the core: it is made from a Dictionary and never reads a file.
## A number that is missing is reported as an error; there are no defaults.

var _values: Dictionary = {}


static func from_dictionary(values: Dictionary) -> Balance:
	var balance: Balance = Balance.new()
	for key: Variant in values:
		balance._values[String(key)] = values[key]
	return balance


## True when the key exists and holds a finite number.
func has_number(key: StringName) -> bool:
	if not _values.has(String(key)):
		return false
	var value: Variant = _values[String(key)]
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


func has_key(key: StringName) -> bool:
	return _values.has(String(key))


## The number for the key. A missing key or a value that is not a number is an
## error: it is reported and NAN is returned, never a default.
func get_number(key: StringName) -> float:
	if not has_number(key):
		push_error("Balance: '%s' is missing or is not a number." % key)
		return NAN
	return float(_values[String(key)])
