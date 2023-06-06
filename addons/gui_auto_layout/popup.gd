@tool
extends PopupPanel

signal item_selected(index : int)
signal other_key(keycode : int)

var button_box := HBoxContainer.new()
var label := Label.new()
var plugin : EditorPlugin

var selected_option := 0


func _init(p : EditorPlugin):
	var root_box := HBoxContainer.new()
	root_box.size = Vector2.ZERO
	root_box.add_child(button_box)
	root_box.add_child(label)
	add_child(root_box)
	root_box.resized.connect(func(): size = root_box.size)
	plugin = p


func _input(event):
	if !visible: return
	if event is InputEventKey && event.pressed:
		match event.keycode:
			KEY_A:
				var next_button := button_box.get_child((selected_option + 1) % button_box.get_child_count())
				next_button.button_pressed = true

			KEY_R:
				plugin.selected_dissolve_parent(true)
				hide()

			KEY_ESCAPE:
				plugin.selected_dissolve_parent(false)
				hide()


func open(items : Dictionary, pos : Vector2):
	popup_centered()
	grab_focus()
	position = pos

	for x in button_box.get_children():
		x.free()

	var button_group := ButtonGroup.new()
	for k in items:
		var new_button := Button.new()
		button_box.add_child(new_button)
		new_button.icon = get_theme_icon(k, "EditorIcons")
		new_button.tooltip_text = items[k]
		new_button.button_group = button_group
		new_button.toggle_mode = true
		new_button.toggled.connect(_on_button_toggled.bind(new_button))

	button_box.get_child(0).button_pressed = true


func _on_button_toggled(toggled : bool, button : Button):
	if !toggled: return
	label.text = button.tooltip_text
	label.size = Vector2.ZERO
	selected_option = button.get_index()
	item_selected.emit(selected_option)
