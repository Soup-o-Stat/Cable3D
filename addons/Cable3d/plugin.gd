@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type(
		"Cable3D",
		"Node3D",
		preload("Cable3D.gd"),
		preload("res://addons/Cable3d/icon.svg")
	)
func _exit_tree():
	remove_custom_type("Cable3D")
