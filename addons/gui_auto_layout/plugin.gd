@tool
extends EditorPlugin

var popup := preload("res://addons/gui_auto_layout/popup.gd").new()
var base := get_editor_interface().get_base_control()

var last_selected_nodes := []
var last_selected_nodes_rects := []
var last_selected_container : Control
var enclosing_rect : Rect2
var container_option_list := []


func _enter_tree():
	base.add_child(popup)
	popup.item_selected.connect(_on_popup_item_selected)


func _exit_tree():
	popup.queue_free()


func _shortcut_input(event):
	if event is InputEventKey:
		if event.pressed && event.shift_pressed && event.keycode == KEY_A:
			_open_auto_layout_popup()


func _open_auto_layout_popup():
	var selected_nodes := get_editor_interface().get_selection().get_selected_nodes()
	last_selected_nodes.clear()
	last_selected_nodes_rects.clear()
	container_option_list.clear()
	if selected_nodes.size() == 0: return

	var new_control := Control.new()
	enclosing_rect = selected_nodes.reduce(func(acc, cur): return acc.merge(cur.get_rect()), selected_nodes[0].get_rect())
	new_control.position = enclosing_rect.position
	new_control.size = enclosing_rect.size
	new_control.name = "Control"
	new_control.owner = selected_nodes[0].owner
	selected_nodes[0].replace_by(new_control)
	new_control.add_child(selected_nodes[0])
	for x in selected_nodes:
		if x is Control:
			last_selected_nodes.append(x)
			last_selected_nodes_rects.append(Rect2(x.position - enclosing_rect.position, x.size))
			x.reparent(new_control)
			x.owner = new_control.owner

	if last_selected_nodes.size() == 0: return

	var layouts := _get_layouts_for_nodes(last_selected_nodes_rects)
	var popup_filling := {}
	for x in layouts:
		popup_filling[x[0]] = x[1]
		container_option_list.append(x[2])

	popup.open(popup_filling, base.get_viewport().get_mouse_position() + Vector2(base.get_viewport().position))


func _get_layouts_for_nodes(rects : Array) -> Array:
	var result := []
	var aligned_h := _are_nodes_aligned_h(rects)
	var aligned_v := _are_nodes_aligned_v(rects)
	var grid_columns := 4  # TODO: properly calculate this

	# Panel: if they are aligned on both axes -> overlap each other

	if aligned_h && aligned_v:
		result.append_array([
			["MarginContainer", "Margins", _set_sel_parent.bind(MarginContainer, "Margins")],
			["Panel", "Panel", _set_sel_parent.bind(PanelContainer, "Panel")],
			["Control", "Freeform", _set_sel_parent.bind(Control, "Control")],
		])
		if rects.size() == 1:
			return result

	# Grid: if they are aligned on NEITHER axis

	if !aligned_h && !aligned_v:
		result.append(["GridContainer", "Grid", _set_sel_parent.bind(GridContainer, "Grid", [grid_columns])])

	# Box/Split: if they are aligned on an axis

	if aligned_h:
		result.append(["HBoxContainer", "Box", _set_sel_parent.bind(HBoxContainer, "Box")])
		if rects.size() == 2:
			result.append(["HSplitContainer", "Split", _set_sel_parent.bind(HSplitContainer, "Split")])

	if aligned_v:
		result.append(["VBoxContainer", "Box", _set_sel_parent.bind(VBoxContainer, "Box")])
		if rects.size() == 2:
			result.append(["VSplitContainer", "Split", _set_sel_parent.bind(VSplitContainer, "Split")])

	# Flow: if they are NOT aligned on an axis

	if !aligned_h:
		result.append(["VFlowContainer", "Flow", _set_sel_parent.bind(VFlowContainer, "Flow")])

	if !aligned_v:
		result.append(["HFlowContainer", "Flow", _set_sel_parent.bind(HFlowContainer, "Flow")])

	# Freeform: "what in the world do I even put here???"

	result.append(["Control", "Freeform", _set_sel_parent.bind(Control, "Control")])

	return result


func _are_nodes_aligned_h(rects : Array) -> bool:
	var first := rects.front()
	var min_b : float = first.position.y
	var max_b : float = first.position.y + first.size.y
	for x in rects:
		if x.position.y > max_b || x.position.y + x.size.y < min_b:
			return false

		if x.position.y < min_b:
			min_b = x.position.y

		if x.position.y + x.size.y > max_b:
			max_b = x.position.y + x.size.y

	return true


func _are_nodes_aligned_v(rects : Array) -> bool:
	var first := rects.front()
	var min_b : float = first.position.x
	var max_b : float = first.position.x + first.size.x
	for x in rects:
		if x.position.x > max_b || x.position.x + x.size.x < min_b:
			return false

		if x.position.x < min_b:
			min_b = x.position.x

		if x.position.x + x.size.x > max_b:
			max_b = x.position.x + x.size.x

	return true


func _set_sel_parent(type, new_name = "Control", params = null):
	if last_selected_nodes.size() == 0: return
	var old_parent : Control = last_selected_nodes[0].get_parent()
	var new_parent : Control = type.new()
	new_parent.position = old_parent.position
	new_parent.size = old_parent.size

	old_parent.replace_by(new_parent)
	new_parent.name = new_name
	old_parent.queue_free()

	if type == Control:
		new_parent.custom_minimum_size = enclosing_rect.size

	if new_parent is HBoxContainer:
		for x in last_selected_nodes:
			x.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if new_parent is VBoxContainer:
		for x in last_selected_nodes:
			x.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if new_parent is GridContainer:
		new_parent.columns = params[0]

	for i in last_selected_nodes.size():
		last_selected_nodes[i].position = last_selected_nodes_rects[i].position
		last_selected_nodes[i].size = last_selected_nodes_rects[i].size


func _on_popup_item_selected(index : int):
	container_option_list[index].call()
