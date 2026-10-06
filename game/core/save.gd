class_name Save
extends RefCounted
## JSON persistence helpers. Saves are written to a temporary file and
## renamed into place so a crash never leaves half a character behind.


## JSON numbers come back as floats; every number we save is an integer.
static func ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v)
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = ints(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(ints(x))
			return a
	return v


static func write_json(path: String, data: Variant) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + tmp)
		return false
	f.store_string(JSON.stringify(data, " ", false))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return ints(JSON.parse_string(FileAccess.get_file_as_string(path)))
