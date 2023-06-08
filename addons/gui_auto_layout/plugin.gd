@tool
extends EditorPlugin

var popup := preload("res://addons/gui_auto_layout/popup.gd").new(self)
var delete_without_children_button := Button.new()
var base := get_editor_interface().get_base_control()

var last_selected_nodes := []
var last_selected_nodes_rects := []
var last_selected_container : Control
var enclosing_rect : Rect2
var container_option_list := []

var free_with_self := []


func _enter_tree():
	base.add_child(popup)
	popup.item_selected.connect(_on_popup_item_selected)

	var scene_dock := find_dock("Scene")
	var delete_dialog_ok_button = scene_dock.get_child(11, true).get_child(2, true).get_child(2, true)
	var delete_dialog_button_spacing := Control.new()
	delete_dialog_button_spacing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_dialog_ok_button.add_sibling(delete_dialog_button_spacing)
	delete_dialog_ok_button.add_sibling(delete_without_children_button)
	delete_without_children_button.text = "OK + Keep children"
	delete_without_children_button.pressed.connect(_on_delete_without_children_pressed)

	free_with_self = [
		popup,
		delete_without_children_button,
		delete_dialog_button_spacing,
	]

	# pack_root.owner = null
	# children_set_owner(pack_root, pack_root, 40)
	# var packed := PackedScene.new()
	# packed.pack(pack_root)
	# ResourceSaver.save(packed, "res://test/editor_pack.tscn")


func _exit_tree():
	for x in free_with_self:
		x.free()


func children_set_owner(node : Node, new_owner : Node, depth : int = -1):
	for x in node.get_children(true):
		x.owner = new_owner
		if depth != 0:
			children_set_owner(x, new_owner, depth - 1)


func find_dock(dock_name : NodePath) -> Control:
	var dock_probe := Control.new()
	var dock : Control
	for i in DOCK_SLOT_MAX:
		add_control_to_dock(i, dock_probe)
		dock = dock_probe.get_parent().get_node_or_null(dock_name)
		remove_control_from_docks(dock_probe)
		if dock != null:
			break

	dock_probe.free()
	return dock


func selected_replace_parent(type, new_name = "Control", params = null):
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
		new_parent.alignment = BoxContainer.ALIGNMENT_CENTER

	if new_parent is VBoxContainer:
		new_parent.alignment = BoxContainer.ALIGNMENT_CENTER

	if new_parent is GridContainer:
		new_parent.columns = params[0]

	for i in last_selected_nodes.size():
		last_selected_nodes[i].position = last_selected_nodes_rects[i].position
		last_selected_nodes[i].size = last_selected_nodes_rects[i].size


func selected_dissolve_parent(replace_grandparent : bool):
	var old_parent : Node = last_selected_nodes[0].get_parent()
	var grand_parent : Node = old_parent.get_parent()
	if grand_parent == null: return

	for x in last_selected_nodes:
		x.reparent(grand_parent)
		x.owner = grand_parent.owner if grand_parent.owner != null else grand_parent

	if replace_grandparent:
		grand_parent.remove_child(old_parent)
		grand_parent.replace_by(old_parent)
		old_parent.position = grand_parent.position
		old_parent.size = grand_parent.size
		old_parent.custom_minimum_size = grand_parent.custom_minimum_size
		if !old_parent is Container:
			old_parent.custom_minimum_size = grand_parent.size

		grand_parent.queue_free()

	else:
		old_parent.queue_free()


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
	var forbidden_parents := {}
	for x in selected_nodes:
		forbidden_parents[x.get_parent()] = true

	for x in selected_nodes:
		if x is Control && !x in forbidden_parents:
			last_selected_nodes.append(x)
			last_selected_nodes_rects.append(Rect2(x.position - enclosing_rect.position, x.size))
			x.reparent(new_control)
			x.owner = new_control.owner

	if last_selected_nodes.size() == 0: return

	var layouts := _get_layouts_for_nodes(last_selected_nodes_rects, enclosing_rect, new_control.get_parent())
	var popup_filling := {}
	for x in layouts:
		popup_filling[x[0]] = x[1]
		container_option_list.append(x[2])

	popup.open(popup_filling, base.get_viewport().get_mouse_position() + Vector2(base.get_viewport().position))


func _get_layouts_for_nodes(rects : Array, enclosing : Rect2, parent : Node) -> Array:
	var result := []
	var aligned_h := _are_nodes_aligned_h(rects)
	var aligned_v := _are_nodes_aligned_v(rects)
	var grid_columns := _get_nodes_columns(rects, enclosing)

	# Opposing BoxContainer
	if parent is VBoxContainer:
		result.append(["HBoxContainer", "Perpendicular Box", selected_replace_parent.bind(HBoxContainer, "Box")])

	if parent is HBoxContainer:
		result.append(["VBoxContainer", "Perpendicular Box", selected_replace_parent.bind(VBoxContainer, "Box")])

	# Panel: if they are aligned on both axes -> overlap each other

	if aligned_h && aligned_v:
		result.append_array([
			["MarginContainer", "Margins", selected_replace_parent.bind(MarginContainer, "Margins")],
			["Panel", "Panel", selected_replace_parent.bind(PanelContainer, "Panel")],
		])
		if rects.size() == 1:
			return result

	# Grid: if they are aligned on NEITHER axis

	if !aligned_h && !aligned_v:
		result.append(["GridContainer", "Grid", selected_replace_parent.bind(GridContainer, "Grid", [grid_columns])])

	# Box/Split: if they are aligned on an axis

	if aligned_h:
		result.append(["HBoxContainer", "Box", selected_replace_parent.bind(HBoxContainer, "Box")])
		if rects.size() == 2:
			result.append(["HSplitContainer", "Split", selected_replace_parent.bind(HSplitContainer, "Split")])

	if aligned_v:
		result.append(["VBoxContainer", "Box", selected_replace_parent.bind(VBoxContainer, "Box")])
		if rects.size() == 2:
			result.append(["VSplitContainer", "Split", selected_replace_parent.bind(VSplitContainer, "Split")])

	# Flow: if they are NOT aligned on an axis

	if !aligned_h:
		result.append(["VFlowContainer", "Flow", selected_replace_parent.bind(VFlowContainer, "Flow")])

	if !aligned_v:
		result.append(["HFlowContainer", "Flow", selected_replace_parent.bind(HFlowContainer, "Flow")])

	# Freeform: always show

	result.append(["Control", "Freeform", selected_replace_parent.bind(Control, "Control")])

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


func _get_nodes_columns(rects : Array, enclosing : Rect2) -> int:
	var topmost : Rect2
	var topmost_y := enclosing.end.y
	for x in rects:
		if x.position.y < topmost_y:
			topmost_y = x.position.y
			topmost = x

	var min_b : float = topmost.position.y
	var max_b : float = topmost.position.y + topmost.size.y
	var top_row_count := 0
	for x in rects:
		if x.position.y <= max_b && x.position.y + x.size.y > min_b:
			top_row_count += 1

	return top_row_count


func _on_popup_item_selected(index : int):
	container_option_list[index].call()


func _on_delete_without_children_pressed():
	delete_without_children_button.get_parent().get_parent().hide()
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	for x in selected:
		var pt := x.get_parent()
		var i := x.get_index()
		var children_reversed := x.get_children()
		for y in children_reversed:
			y.reparent(pt)
			y.owner = pt.owner if pt.owner != null else pt
			pt.move_child(y, i)
			i += 1

		x.queue_free()
