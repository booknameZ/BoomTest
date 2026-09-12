extends SceneTree

func _initialize() -> void:
	var res := ResourceLoader.load("res://scripts/main.gd")
	if res == null:
		print("MAIN_LOAD_FAILED")
	else:
		print("MAIN_LOADED_OK: ", res.resource_path)
	quit()
