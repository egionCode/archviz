extends Node3D

## The workspace itself is always 3D. Each mode changes only the camera behavior.
enum ViewMode { PLANNER_2D, PERSPECTIVE_3D, FIRST_PERSON }
enum Tool { SELECT, WALL, MEASURE }

const MODE_NAMES := ["Planta 2D", "Perspectiva 3D", "Primeira pessoa"]
const WALK_SPEED := 5.0
const MOUSE_SENSITIVITY := 0.003
const GRID_SNAP := 1.0
const ANGLE_SNAP_RADIANS := PI / 4.0
const MEASUREMENT_ANGLE_SNAP_RADIANS := deg_to_rad(12.0)
const VERTEX_SNAP_DISTANCE := 0.35
const WALL_HEIGHT := 2.7
const DEFAULT_WALL_THICKNESS := 0.15

var view_mode: ViewMode = ViewMode.PLANNER_2D
var camera: Camera3D
var mode_label: Label
var hint_label: Label
var length_label: Label
var length_input: LineEdit
var thickness_label: Label
var thickness_input: SpinBox
var select_tool_button: Button
var wall_tool_button: Button
var measure_tool_button: Button
var radial_delete_button: Button
var wall_root: Node3D
var handle_root: Node3D
var junction_root: Node3D
var floor_root: Node3D
var measurement_root: Node3D
var preview_wall: MeshInstance3D
var preview_measurement: MeshInstance3D
var walls: Array[Dictionary] = []
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var active_tool: Tool = Tool.WALL
var active_start: Variant = null
var active_measure_start: Variant = null
var active_angle_reference := Vector3.FORWARD
var active_measure_angle_reference := Vector3.FORWARD
var preview_end := Vector3.ZERO
var typed_length := 0.0
var typed_measurement_length := 0.0
var measurement_preview_end := Vector3.ZERO
var wall_thickness := DEFAULT_WALL_THICKNESS
var hovered_wall_index := -1
var selected_wall_index := -1
var hovered_measurement_index := -1
var selected_measurement_index := -1
var yaw := 0.0
var pitch := -0.12


func _ready() -> void:
	_create_world()
	_create_interface()
	_set_view_mode(ViewMode.PLANNER_2D)


func _create_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("18202b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d9e6ff")
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	_create_grid(30, GRID_SNAP)
	wall_root = Node3D.new()
	wall_root.name = "Walls"
	add_child(wall_root)
	handle_root = Node3D.new()
	handle_root.name = "WallHandles"
	add_child(handle_root)
	junction_root = Node3D.new()
	junction_root.name = "WallJunctions"
	add_child(junction_root)
	floor_root = Node3D.new()
	floor_root.name = "Floors"
	add_child(floor_root)
	measurement_root = Node3D.new()
	measurement_root.name = "Measurements"
	add_child(measurement_root)
	preview_wall = _create_wall_mesh(Color(0.32, 0.75, 1.0, 0.48), wall_thickness)
	preview_wall.name = "WallPreview"
	preview_wall.visible = false
	add_child(preview_wall)
	preview_measurement = MeshInstance3D.new()
	preview_measurement.name = "MeasurementPreview"
	preview_measurement.visible = false
	add_child(preview_measurement)

	camera = Camera3D.new()
	camera.name = "WorkspaceCamera"
	camera.current = true
	add_child(camera)


func _create_grid(half_extent: int, step: float) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for coordinate in range(-half_extent, half_extent + 1):
		var color := Color("5a6c82") if coordinate == 0 else Color("344252")
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(coordinate * step, 0.0, -half_extent * step))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(coordinate * step, 0.0, half_extent * step))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(-half_extent * step, 0.0, coordinate * step))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(half_extent * step, 0.0, coordinate * step))
	mesh.surface_end()

	var grid := MeshInstance3D.new()
	grid.name = "MetricGrid"
	grid.mesh = mesh
	add_child(grid)


func _create_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(250, 570)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.09, 0.9)
	style.border_color = Color("4b6580")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)

	var title := Label.new()
	title.text = "FERRAMENTAS"
	title.add_theme_font_size_override("font_size", 18)
	content.add_child(title)

	var drawing_label := Label.new()
	drawing_label.text = "DESENHO"
	drawing_label.add_theme_color_override("font_color", Color("84c7ff"))
	content.add_child(drawing_label)

	select_tool_button = Button.new()
	select_tool_button.text = "⌖  Selecionar"
	select_tool_button.toggle_mode = true
	select_tool_button.pressed.connect(_set_active_tool.bind(Tool.SELECT))
	content.add_child(select_tool_button)

	wall_tool_button = Button.new()
	wall_tool_button.text = "▰  Parede"
	wall_tool_button.toggle_mode = true
	wall_tool_button.button_pressed = true
	wall_tool_button.pressed.connect(_set_active_tool.bind(Tool.WALL))
	content.add_child(wall_tool_button)

	measure_tool_button = Button.new()
	measure_tool_button.text = "⌁  Medir"
	measure_tool_button.toggle_mode = true
	measure_tool_button.pressed.connect(_set_active_tool.bind(Tool.MEASURE))
	content.add_child(measure_tool_button)

	var wall_title := Label.new()
	wall_title.text = "PAREDE"
	wall_title.add_theme_color_override("font_color", Color("84c7ff"))
	content.add_child(wall_title)

	thickness_label = Label.new()
	thickness_label.text = "Espessura"
	content.add_child(thickness_label)
	thickness_input = SpinBox.new()
	thickness_input.min_value = 0.05
	thickness_input.max_value = 0.60
	thickness_input.step = 0.01
	thickness_input.value = wall_thickness
	thickness_input.suffix = " m"
	thickness_input.value_changed.connect(_set_wall_thickness)
	content.add_child(thickness_input)

	length_label = Label.new()
	length_label.text = "Comprimento: —"
	content.add_child(length_label)

	var measure_row := HBoxContainer.new()
	measure_row.add_theme_constant_override("separation", 8)
	content.add_child(measure_row)
	length_input = LineEdit.new()
	length_input.placeholder_text = "Medida em m"
	length_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	length_input.text_submitted.connect(_confirm_typed_length)
	length_input.text_changed.connect(_on_length_text_changed)
	measure_row.add_child(length_input)
	var apply_button := Button.new()
	apply_button.text = "Definir"
	apply_button.pressed.connect(_apply_length_from_field)
	measure_row.add_child(apply_button)

	var separator := HSeparator.new()
	content.add_child(separator)

	var view_label := Label.new()
	view_label.text = "VISUALIZAÇÃO"
	view_label.add_theme_color_override("font_color", Color("84c7ff"))
	content.add_child(view_label)

	mode_label = Label.new()
	mode_label.add_theme_color_override("font_color", Color("aebdcc"))
	content.add_child(mode_label)

	for index in range(MODE_NAMES.size()):
		var button := Button.new()
		button.text = "%d  ·  %s" % [index + 1, MODE_NAMES[index]]
		button.pressed.connect(_set_view_mode.bind(index))
		content.add_child(button)

	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", Color("aebdcc"))
	content.add_child(hint_label)

	radial_delete_button = Button.new()
	radial_delete_button.text = "Excluir"
	radial_delete_button.size = Vector2(84, 84)
	var delete_style := StyleBoxFlat.new()
	delete_style.bg_color = Color("a8424b")
	delete_style.set_corner_radius_all(42)
	radial_delete_button.add_theme_stylebox_override("normal", delete_style)
	radial_delete_button.visible = false
	radial_delete_button.pressed.connect(_delete_selected_item)
	layer.add_child(radial_delete_button)


func _set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	handle_root.visible = mode == ViewMode.PLANNER_2D
	match mode:
		ViewMode.PLANNER_2D:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 22.0
			camera.global_position = Vector3(0.0, 18.0, 0.0)
			camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			hint_label.text = "Clique na origem, informe uma medida opcional e clique para confirmar. Grade: 1 m."
		ViewMode.PERSPECTIVE_3D:
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 55.0
			camera.global_position = Vector3(13.0, 10.0, 13.0)
			camera.look_at(Vector3.ZERO)
			hint_label.text = "Vista livre em perspectiva para validar proporções e materiais."
		ViewMode.FIRST_PERSON:
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 60.0
			camera.global_position = Vector3(0.0, 1.7, 8.0)
			yaw = PI
			pitch = 0.0
			camera.rotation = Vector3(pitch, yaw, 0.0)
			hint_label.text = "WASD para andar. Segure o botão direito e mova o mouse para olhar."
	mode_label.text = "Modo ativo: %s" % MODE_NAMES[view_mode]
	length_input.editable = view_mode == ViewMode.PLANNER_2D


func _set_active_tool(tool: Tool) -> void:
	active_tool = tool
	_cancel_wall_chain()
	_cancel_measurement()
	_clear_wall_selection()
	select_tool_button.button_pressed = tool == Tool.SELECT
	wall_tool_button.button_pressed = tool == Tool.WALL
	measure_tool_button.button_pressed = tool == Tool.MEASURE
	length_input.editable = view_mode == ViewMode.PLANNER_2D and tool != Tool.SELECT
	length_input.visible = tool != Tool.SELECT
	length_label.visible = tool != Tool.SELECT
	thickness_label.visible = tool == Tool.WALL
	thickness_input.visible = tool == Tool.WALL
	if tool == Tool.SELECT:
		hint_label.text = "Passe o mouse sobre uma parede ou medição para selecionar."
	elif tool == Tool.WALL:
		hint_label.text = "Clique na origem, informe uma medida opcional e clique para confirmar."
	else:
		hint_label.text = "Clique nos dois pontos para criar uma guia de medida."


func _set_wall_thickness(value: float) -> void:
	wall_thickness = value
	var preview_mesh := preview_wall.mesh as BoxMesh
	preview_mesh.size.x = wall_thickness


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		_undo_last_change()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_Y:
		_redo_last_change()
		get_viewport().set_input_as_handled()
		return
	if view_mode == ViewMode.PLANNER_2D and event.keycode == KEY_ESCAPE:
		if active_start != null:
			_cancel_wall_chain()
			get_viewport().set_input_as_handled()
		elif active_measure_start != null:
			_cancel_measurement()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_undo_last_change()
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.keycode == KEY_Y:
			_redo_last_change()
			get_viewport().set_input_as_handled()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_3:
			_set_view_mode(event.keycode - KEY_1)
	if view_mode == ViewMode.PLANNER_2D:
		_handle_planner_input(event)
		return
	if view_mode != ViewMode.FIRST_PERSON:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clamp(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
		camera.rotation = Vector3(pitch, yaw, 0.0)


func _handle_planner_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if active_tool == Tool.SELECT:
			_update_selection_hover(event.position)
		elif active_tool == Tool.WALL:
			if active_start != null:
				_update_preview_from_cursor(event.position)
		else:
			if active_measure_start != null:
				_update_measurement_preview(event.position)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			var viewport_width: float = max(get_viewport().get_visible_rect().size.x, 1.0)
			camera.global_position.x -= event.relative.x * camera.size / viewport_width
			camera.global_position.z -= event.relative.y * camera.size / viewport_width
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.size = max(2.0, camera.size * 0.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.size = min(80.0, camera.size * 1.1)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if active_tool == Tool.SELECT:
					_open_selected_item_actions(event.position)
				elif active_tool == Tool.MEASURE:
					_handle_measurement_click(event.position)
				elif active_start == null:
					var raw_point := _screen_to_grid_point(event.position)
					var endpoint: Variant = _find_existing_vertex(raw_point)
					if endpoint != null:
						_start_wall_at(endpoint)
					else:
						_start_wall_at(_snap_point(raw_point))
			elif active_tool == Tool.WALL:
					_update_preview_from_cursor(event.position)
					_commit_point(preview_end)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if selected_wall_index >= 0 or selected_measurement_index >= 0 or radial_delete_button.visible:
			_clear_wall_selection()
		elif active_start != null:
			_cancel_wall_chain()
		else:
			_cancel_measurement()


func _start_wall_at(point: Vector3) -> void:
	active_start = point
	active_angle_reference = _angle_reference_at(active_start)
	preview_end = active_start
	length_label.text = "Comprimento: mova o cursor ou informe metros"
	length_input.grab_focus()


func _screen_to_grid_point(screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)
	return intersection as Vector3 if intersection != null else Vector3.ZERO


func _snap_point(point: Vector3) -> Vector3:
	var direct_vertex: Variant = _find_existing_vertex(point)
	if direct_vertex != null:
		return direct_vertex
	if active_start != null and point.distance_to(active_start) <= VERTEX_SNAP_DISTANCE:
		return active_start
	var snapped := Vector3(
		round(point.x / GRID_SNAP) * GRID_SNAP,
		0.0,
		round(point.z / GRID_SNAP) * GRID_SNAP
	)
	var existing_vertex: Variant = _find_existing_vertex(snapped)
	if existing_vertex != null:
		return existing_vertex
	if active_start != null and snapped.distance_to(active_start) <= VERTEX_SNAP_DISTANCE:
		return active_start
	return snapped


func _find_existing_vertex(point: Vector3) -> Variant:
	var closest: Variant = null
	var closest_distance := VERTEX_SNAP_DISTANCE
	for wall in walls:
		for vertex: Vector3 in [wall.start, wall.end]:
			var distance := point.distance_to(vertex)
			if distance <= closest_distance:
				closest = vertex
				closest_distance = distance
	for measurement in measurements:
		for vertex: Vector3 in [measurement.start, measurement.end]:
			var distance := point.distance_to(vertex)
			if distance <= closest_distance:
				closest = vertex
				closest_distance = distance
	return closest


func _update_wall_hover(screen_position: Vector2) -> void:
	var cursor_point := _screen_to_grid_point(screen_position)
	var closest_index := -1
	var closest_distance: float = max(0.25, camera.size * 0.012)
	for index in range(walls.size()):
		var wall: Dictionary = walls[index]
		var distance := _distance_to_segment(cursor_point, wall.start, wall.end)
		if distance <= closest_distance:
			closest_index = index
			closest_distance = distance
	if closest_index == hovered_wall_index:
		return
	if hovered_wall_index >= 0:
		_set_wall_color(hovered_wall_index, Color("d9e2ef"))
	hovered_wall_index = closest_index
	if hovered_wall_index >= 0:
		var hovered: Dictionary = walls[hovered_wall_index]
		_set_wall_color(hovered_wall_index, Color("ffd166"))
		var start: Vector3 = hovered.start
		var finish: Vector3 = hovered.end
		length_label.text = "Parede: %.2f m" % start.distance_to(finish)
		hint_label.text = "Clique para editar esta parede."


func _distance_to_segment(point: Vector3, start: Vector3, finish: Vector3) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(start)
	var t: float = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _set_wall_color(index: int, color: Color) -> void:
	if index < 0 or index >= wall_root.get_child_count():
		return
	var wall_instance := wall_root.get_child(index) as MeshInstance3D
	var mesh := wall_instance.mesh as BoxMesh
	var material := mesh.material as StandardMaterial3D
	material.albedo_color = color


func _open_wall_actions(screen_position: Vector2, wall_index: int) -> void:
	selected_wall_index = wall_index
	radial_delete_button.position = screen_position + Vector2(16, -96)
	radial_delete_button.visible = true
	hint_label.text = "Parede selecionada: use Excluir para removê-la."


func _update_selection_hover(screen_position: Vector2) -> void:
	_update_wall_hover(screen_position)
	_update_measurement_hover(screen_position)


func _update_measurement_hover(screen_position: Vector2) -> void:
	var cursor_point := _screen_to_grid_point(screen_position)
	var closest_index := -1
	var closest_distance: float = max(0.25, camera.size * 0.012)
	for index in range(measurements.size()):
		var measurement: Dictionary = measurements[index]
		var distance := _distance_to_segment(cursor_point, measurement.start, measurement.end)
		if distance <= closest_distance:
			closest_index = index
			closest_distance = distance
	if closest_index == hovered_measurement_index:
		return
	if hovered_measurement_index >= 0:
		_set_measurement_color(hovered_measurement_index, Color("f7c948"))
	hovered_measurement_index = closest_index
	if hovered_measurement_index >= 0:
		var measurement: Dictionary = measurements[hovered_measurement_index]
		_set_measurement_color(hovered_measurement_index, Color("ffffff"))
		length_label.text = "Medição: %.2f m" % (measurement.start as Vector3).distance_to(measurement.end)
		hint_label.text = "Clique para editar esta medição."


func _set_measurement_color(index: int, color: Color) -> void:
	if index < 0 or index >= measurement_root.get_child_count():
		return
	var guide := measurement_root.get_child(index) as MeshInstance3D
	var material := guide.material_override as StandardMaterial3D
	material.albedo_color = color


func _open_selected_item_actions(screen_position: Vector2) -> void:
	if hovered_wall_index >= 0:
		selected_wall_index = hovered_wall_index
		selected_measurement_index = -1
		_open_wall_actions(screen_position, selected_wall_index)
	elif hovered_measurement_index >= 0:
		selected_wall_index = -1
		selected_measurement_index = hovered_measurement_index
		radial_delete_button.position = screen_position + Vector2(16, -96)
		radial_delete_button.visible = true
		hint_label.text = "Medição selecionada: use Excluir para removê-la."


func _clear_wall_selection() -> void:
	if hovered_wall_index >= 0:
		_set_wall_color(hovered_wall_index, Color("d9e2ef"))
	hovered_wall_index = -1
	selected_wall_index = -1
	if hovered_measurement_index >= 0:
		_set_measurement_color(hovered_measurement_index, Color("f7c948"))
	hovered_measurement_index = -1
	selected_measurement_index = -1
	radial_delete_button.visible = false
	hint_label.text = "Seleção removida."


func _handle_measurement_click(screen_position: Vector2) -> void:
	var point := _snap_point(_screen_to_grid_point(screen_position))
	if active_measure_start == null:
		active_measure_start = point
		active_measure_angle_reference = _angle_reference_at(point)
		measurement_preview_end = point
		preview_measurement.visible = false
		length_label.text = "Medida: mova o cursor ou informe metros"
		length_input.grab_focus()
		hint_label.text = "Mova o cursor, informe metros ou pressione Enter para concluir."
		return
	_update_measurement_preview(screen_position)
	_commit_measurement(measurement_preview_end)


func _commit_measurement(point: Vector3) -> void:
	if active_measure_start == null or active_measure_start.distance_to(point) < 0.001:
		return
	var start: Vector3 = active_measure_start
	measurements.append({"start": start, "end": point})
	var guide := _create_measurement_line(start, point, Color("f7c948"))
	guide.name = "Measurement_%d" % measurements.size()
	measurement_root.add_child(guide)
	active_measure_start = null
	active_measure_angle_reference = Vector3.FORWARD
	typed_measurement_length = 0.0
	preview_measurement.visible = false
	length_input.clear()
	length_input.release_focus()
	length_label.text = "Comprimento: —"
	hint_label.text = "Guia de medida criada: %.2f m." % start.distance_to(point)


func _update_measurement_preview(screen_position: Vector2) -> void:
	var raw_point := _screen_to_grid_point(screen_position)
	var direct_vertex: Variant = _find_existing_vertex(raw_point)
	var point: Vector3 = direct_vertex if direct_vertex != null else _snap_point(raw_point)
	if active_measure_start.distance_to(point) < 0.001:
		return
	var start: Vector3 = active_measure_start
	var direction: Vector3 = point - start
	if direct_vertex != null:
		measurement_preview_end = direct_vertex
	else:
		var snapped_direction := _snap_direction_to_measurement(direction, active_measure_angle_reference)
		if typed_measurement_length > 0.0:
			measurement_preview_end = start + snapped_direction * typed_measurement_length
		else:
			var projected_length := direction.dot(snapped_direction)
			var snapped_distance: float = round(projected_length / GRID_SNAP) * GRID_SNAP
			measurement_preview_end = start + snapped_direction * snapped_distance
	preview_measurement.mesh = _create_measurement_line(start, measurement_preview_end, Color("ffe29a")).mesh
	preview_measurement.visible = true
	length_label.text = "Medida: %.2f m" % start.distance_to(measurement_preview_end)
	hint_label.text = "Medida: %.2f m. Clique ou Enter para concluir." % start.distance_to(measurement_preview_end)


func _cancel_measurement() -> void:
	active_measure_start = null
	active_measure_angle_reference = Vector3.FORWARD
	typed_measurement_length = 0.0
	if preview_measurement != null:
		preview_measurement.visible = false


func _create_measurement_line(start: Vector3, finish: Vector3, color: Color) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(start + Vector3.UP * 0.03)
	mesh.surface_add_vertex(finish + Vector3.UP * 0.03)
	mesh.surface_end()
	line.mesh = mesh
	line.material_override = material
	return line


func _commit_point(point: Vector3) -> void:
	if active_start == null:
		return
	if active_start.distance_to(point) < 0.001:
		return
	var start: Vector3 = active_start
	var closing_path: Array[Vector3] = _find_path(point, start, [])
	var wall := {"start": start, "end": point, "thickness": wall_thickness}
	walls.append(wall)
	var wall_mesh := _create_wall_mesh(Color("d9e2ef"), wall_thickness)
	wall_mesh.name = "Wall_%d" % walls.size()
	wall_root.add_child(wall_mesh)
	_position_wall(wall_mesh, start, point)
	active_start = null
	active_angle_reference = Vector3.FORWARD
	typed_length = 0.0
	preview_wall.visible = false
	length_input.clear()
	length_input.release_focus()
	var created_floor := false
	var floor_boundary: Array[Vector3] = []
	_refresh_handles()
	_refresh_wall_junctions()
	if closing_path.size() >= 3:
		var room_polygon: Array[Vector3] = [start]
		for index in range(closing_path.size() - 1):
			room_polygon.append(closing_path[index])
		_create_floor(room_polygon)
		created_floor = true
		floor_boundary = room_polygon.duplicate()
		hint_label.text = "Cômodo fechado: piso criado (%.2f m²)." % _polygon_area(room_polygon)
	else:
		hint_label.text = "Parede criada: %.2f m. Clique numa ponta azul para continuar." % start.distance_to(point)
	_record_change({"kind": "create", "wall": wall, "created_floor": created_floor, "floor_boundary": floor_boundary})


func _apply_length_from_field() -> void:
	if active_tool == Tool.MEASURE:
		_apply_typed_measurement_length(length_input.text)
	else:
		_apply_typed_length(length_input.text)


func _confirm_typed_length(value: String) -> void:
	if active_tool == Tool.MEASURE:
		_apply_typed_measurement_length(value)
		if active_measure_start != null and typed_measurement_length > 0.0:
			_commit_measurement(measurement_preview_end)
	else:
		_apply_typed_length(value)
		if active_start != null and typed_length > 0.0:
			_commit_point(preview_end)


func _apply_typed_length(value: String) -> void:
	if active_start == null:
		hint_label.text = "Inicie uma parede com um clique antes de informar uma medida."
		return
	typed_length = value.replace(",", ".").to_float()
	if typed_length <= 0.0:
		hint_label.text = "Informe uma medida maior que zero, em metros."
		return
	var start: Vector3 = active_start
	var direction: Vector3 = preview_end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	direction = _snap_direction_to_measurement(direction, active_angle_reference)
	preview_end = _snap_wall_to_measurement_body(start, start + direction * typed_length)
	_update_preview()
	hint_label.text = "Medida definida. Mova o cursor para orientar e clique para confirmar."


func _on_length_text_changed(value: String) -> void:
	if active_tool == Tool.MEASURE and active_measure_start != null and not value.is_empty():
		_apply_typed_measurement_length(value)
	elif active_start != null and not value.is_empty():
		_apply_typed_length(value)
	elif value.is_empty():
		typed_length = 0.0
		typed_measurement_length = 0.0


func _apply_typed_measurement_length(value: String) -> void:
	if active_measure_start == null:
		hint_label.text = "Inicie uma medição com um clique antes de informar uma medida."
		return
	typed_measurement_length = value.replace(",", ".").to_float()
	if typed_measurement_length <= 0.0:
		hint_label.text = "Informe uma medida maior que zero, em metros."
		return
	var start: Vector3 = active_measure_start
	var direction: Vector3 = measurement_preview_end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	direction = _snap_direction_to_measurement(direction, active_measure_angle_reference)
	measurement_preview_end = start + direction * typed_measurement_length
	preview_measurement.mesh = _create_measurement_line(start, measurement_preview_end, Color("ffe29a")).mesh
	preview_measurement.visible = true
	length_label.text = "Medida: %.2f m" % typed_measurement_length
	hint_label.text = "Medida definida. Mova o cursor para orientar ou pressione Enter para concluir."


func _update_preview_from_cursor(screen_position: Vector2) -> void:
	if active_start == null:
		return
	var start: Vector3 = active_start
	var raw_cursor_point := _screen_to_grid_point(screen_position)
	var direct_vertex: Variant = _find_existing_vertex(raw_cursor_point)
	if direct_vertex != null and start.distance_to(direct_vertex) > 0.001:
		preview_end = direct_vertex
		_update_preview()
		return
	var cursor_point := _snap_point(raw_cursor_point)
	var direction: Vector3 = cursor_point - start
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var snapped_direction := _snap_direction_to_measurement(direction, active_angle_reference)
	if typed_length > 0.0:
		preview_end = start + snapped_direction * typed_length
	else:
		var projected_length := direction.dot(snapped_direction)
		var snapped_distance: float = round(projected_length / GRID_SNAP) * GRID_SNAP
		preview_end = start + snapped_direction * snapped_distance
	preview_end = _snap_wall_to_measurement_body(start, preview_end)
	_update_preview()


func _snap_wall_to_measurement_body(start: Vector3, finish: Vector3) -> Vector3:
	var closest_point := finish
	var closest_t := 1.0
	for measurement in measurements:
		var intersection: Variant = _segment_intersection(start, finish, measurement.start, measurement.end)
		if intersection != null and intersection["t"] > 0.001 and intersection["t"] < closest_t:
			closest_t = intersection["t"]
			closest_point = intersection["point"]
	return closest_point


func _segment_intersection(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Variant:
	var r := Vector2(b.x - a.x, b.z - a.z)
	var s := Vector2(d.x - c.x, d.z - c.z)
	var denominator := r.x * s.y - r.y * s.x
	if abs(denominator) < 0.0001:
		return null
	var offset := Vector2(c.x - a.x, c.z - a.z)
	var t := (offset.x * s.y - offset.y * s.x) / denominator
	var u := (offset.x * r.y - offset.y * r.x) / denominator
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return null
	return {"point": a.lerp(b, t), "t": t}


func _snap_direction(direction: Vector3, reference: Vector3) -> Vector3:
	var horizontal := Vector3(direction.x, 0.0, direction.z).normalized()
	var angle := atan2(horizontal.x, horizontal.z)
	var base_angle := atan2(reference.x, reference.z)
	var relative_angle := wrapf(angle - base_angle, -PI, PI)
	var snapped_angle: float = base_angle + round(relative_angle / ANGLE_SNAP_RADIANS) * ANGLE_SNAP_RADIANS
	return Vector3(sin(snapped_angle), 0.0, cos(snapped_angle))


func _snap_direction_to_measurement(direction: Vector3, reference: Vector3) -> Vector3:
	var requested := Vector3(direction.x, 0.0, direction.z).normalized()
	var closest_direction := Vector3.ZERO
	var closest_angle := MEASUREMENT_ANGLE_SNAP_RADIANS
	for measurement in measurements:
		var start: Vector3 = measurement.start
		var finish: Vector3 = measurement.end
		var measurement_direction: Vector3 = (finish - start).normalized()
		for candidate: Vector3 in [measurement_direction, -measurement_direction]:
			var angle: float = abs(wrapf(atan2(requested.x, requested.z) - atan2(candidate.x, candidate.z), -PI, PI))
			if angle <= closest_angle:
				closest_angle = angle
				closest_direction = candidate
	if closest_direction != Vector3.ZERO:
		return closest_direction
	return _snap_direction(requested, reference)


func _angle_reference_at(vertex: Vector3) -> Vector3:
	for index in range(walls.size() - 1, -1, -1):
		var wall: Dictionary = walls[index]
		var start: Vector3 = wall.start
		var finish: Vector3 = wall.end
		if vertex.distance_to(finish) < 0.001:
			return (finish - start).normalized()
		if vertex.distance_to(start) < 0.001:
			return (start - finish).normalized()
	for index in range(measurements.size() - 1, -1, -1):
		var measurement: Dictionary = measurements[index]
		var start: Vector3 = measurement.start
		var finish: Vector3 = measurement.end
		if vertex.distance_to(finish) < 0.001:
			return (finish - start).normalized()
		if vertex.distance_to(start) < 0.001:
			return (start - finish).normalized()
	return Vector3.FORWARD


func _cancel_wall_chain() -> void:
	active_start = null
	active_angle_reference = Vector3.FORWARD
	typed_length = 0.0
	preview_wall.visible = false
	length_label.text = "Comprimento: —"
	hint_label.text = "Wall Tool cancelado. Clique para iniciar uma nova parede."


func _undo_last_change() -> void:
	if active_start != null:
		_cancel_wall_chain()
		return
	if undo_stack.is_empty():
		hint_label.text = "Não há alterações para desfazer."
		return
	var last_change: Dictionary = undo_stack.pop_back()
	redo_stack.append(last_change)
	if last_change["kind"] == "delete_measurement":
		measurements.insert(last_change["index"], last_change["measurement"])
		_rebuild_measurement_visuals()
		hint_label.text = "Exclusão de medição desfeita."
	elif last_change["kind"] == "delete":
		walls.insert(last_change["index"], last_change["wall"])
		_rebuild_wall_visuals()
		for boundary in last_change["floors"]:
			_create_floor(boundary)
		hint_label.text = "Exclusão desfeita."
	else:
		walls.pop_back()
		_rebuild_wall_visuals()
		if last_change["created_floor"] and floor_root.get_child_count() > 0:
			var last_floor := floor_root.get_child(floor_root.get_child_count() - 1)
			floor_root.remove_child(last_floor)
			last_floor.queue_free()
		hint_label.text = "Última parede desfeita."


func _redo_last_change() -> void:
	if redo_stack.is_empty():
		hint_label.text = "Não há alterações para refazer."
		return
	var change: Dictionary = redo_stack.pop_back()
	if change["kind"] == "delete_measurement":
		measurements.remove_at(change["index"])
		_rebuild_measurement_visuals()
		hint_label.text = "Exclusão de medição refeita."
	elif change["kind"] == "delete":
		walls.remove_at(change["index"])
		_remove_floors_using_wall(change["wall"].start, change["wall"].end)
		_rebuild_wall_visuals()
		hint_label.text = "Exclusão refeita."
	else:
		walls.append(change["wall"])
		_rebuild_wall_visuals()
		if change["created_floor"]:
			_create_floor(change["floor_boundary"])
		hint_label.text = "Parede refeita."
	undo_stack.append(change)


func _record_change(change: Dictionary) -> void:
	undo_stack.append(change)
	redo_stack.clear()


func _delete_selected_item() -> void:
	if selected_measurement_index >= 0:
		_delete_selected_measurement()
		return
	_delete_selected_wall()


func _delete_selected_wall() -> void:
	if selected_wall_index < 0 or selected_wall_index >= walls.size():
		return
	var removed_wall: Dictionary = walls[selected_wall_index]
	var removed_floors: Array = _remove_floors_using_wall(removed_wall.start, removed_wall.end)
	walls.remove_at(selected_wall_index)
	_record_change({"kind": "delete", "wall": removed_wall, "index": selected_wall_index, "floors": removed_floors})
	selected_wall_index = -1
	hovered_wall_index = -1
	radial_delete_button.visible = false
	_rebuild_wall_visuals()
	hint_label.text = "Parede excluída. Ctrl+Z para desfazer."


func _delete_selected_measurement() -> void:
	if selected_measurement_index < 0 or selected_measurement_index >= measurements.size():
		return
	var removed_measurement: Dictionary = measurements[selected_measurement_index]
	measurements.remove_at(selected_measurement_index)
	_record_change({"kind": "delete_measurement", "measurement": removed_measurement, "index": selected_measurement_index})
	selected_measurement_index = -1
	hovered_measurement_index = -1
	radial_delete_button.visible = false
	_rebuild_measurement_visuals()
	hint_label.text = "Medição excluída. Ctrl+Z para desfazer."


func _rebuild_measurement_visuals() -> void:
	for child in measurement_root.get_children():
		measurement_root.remove_child(child)
		child.queue_free()
	for index in range(measurements.size()):
		var measurement: Dictionary = measurements[index]
		var guide := _create_measurement_line(measurement.start, measurement.end, Color("f7c948"))
		guide.name = "Measurement_%d" % (index + 1)
		measurement_root.add_child(guide)


func _rebuild_wall_visuals() -> void:
	for child in wall_root.get_children():
		wall_root.remove_child(child)
		child.queue_free()
	for index in range(walls.size()):
		var wall: Dictionary = walls[index]
		var thickness: float = wall.get("thickness", DEFAULT_WALL_THICKNESS)
		var wall_mesh := _create_wall_mesh(Color("d9e2ef"), thickness)
		wall_mesh.name = "Wall_%d" % (index + 1)
		wall_root.add_child(wall_mesh)
		_position_wall(wall_mesh, wall.start, wall.end)
	_refresh_handles()
	_refresh_wall_junctions()


func _remove_floors_using_wall(start: Vector3, finish: Vector3) -> Array:
	var removed: Array = []
	for index in range(floor_root.get_child_count() - 1, -1, -1):
		var floor := floor_root.get_child(index) as MeshInstance3D
		var boundary: Array = floor.get_meta("boundary", [])
		if _boundary_contains_wall(boundary, start, finish):
			removed.append(boundary)
			floor_root.remove_child(floor)
			floor.queue_free()
	return removed


func _boundary_contains_wall(boundary: Array, start: Vector3, finish: Vector3) -> bool:
	for index in range(boundary.size()):
		var current: Vector3 = boundary[index]
		var following: Vector3 = boundary[(index + 1) % boundary.size()]
		if (current.distance_to(start) < 0.001 and following.distance_to(finish) < 0.001) or (current.distance_to(finish) < 0.001 and following.distance_to(start) < 0.001):
			return true
	return false


func _create_wall_mesh(color: Color, thickness: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, WALL_HEIGHT, 1.0)
	mesh.material = material
	instance.mesh = mesh
	return instance


func _find_path(from: Vector3, target: Vector3, visited: Array[Vector3]) -> Array[Vector3]:
	if from.distance_to(target) < 0.001:
		return [from]
	var explored := visited.duplicate()
	explored.append(from)
	for wall in walls:
		var neighbor: Variant = null
		if from.distance_to(wall.start) < 0.001:
			neighbor = wall.end
		elif from.distance_to(wall.end) < 0.001:
			neighbor = wall.start
		if neighbor == null:
			continue
		var next: Vector3 = neighbor
		if _contains_vertex(explored, next):
			continue
		var path: Array[Vector3] = _find_path(next, target, explored)
		if not path.is_empty():
			var complete_path: Array[Vector3] = [from]
			complete_path.append_array(path)
			return complete_path
	return []


func _contains_vertex(vertices: Array[Vector3], point: Vector3) -> bool:
	for vertex in vertices:
		if vertex.distance_to(point) < 0.001:
			return true
	return false


func _create_floor(vertices: Array[Vector3]) -> void:
	var contour := PackedVector2Array()
	for vertex in vertices:
		contour.append(Vector2(vertex.x, vertex.z))
	if _polygon_signed_area(vertices) < 0.0:
		contour.reverse()
	var triangle_indices: PackedInt32Array = Geometry2D.triangulate_polygon(contour)
	if triangle_indices.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangle_indices:
		var point := contour[index]
		surface.set_normal(Vector3.UP)
		surface.add_vertex(Vector3(point.x, 0.015, point.y))
	var floor := MeshInstance3D.new()
	floor.name = "RoomFloor_%d" % (floor_root.get_child_count() + 1)
	floor.mesh = surface.commit()
	floor.set_meta("boundary", vertices.duplicate())
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("5d9d7a")
	material.roughness = 0.9
	floor.material_override = material
	floor_root.add_child(floor)


func _polygon_signed_area(vertices: Array[Vector3]) -> float:
	var area := 0.0
	for index in range(vertices.size()):
		var current := vertices[index]
		var following := vertices[(index + 1) % vertices.size()]
		area += current.x * following.z - following.x * current.z
	return area * 0.5


func _polygon_area(vertices: Array[Vector3]) -> float:
	return abs(_polygon_signed_area(vertices))


func _refresh_handles() -> void:
	for child in handle_root.get_children():
		child.queue_free()
	var shown_vertices: Array[Vector3] = []
	for wall in walls:
		for vertex: Vector3 in [wall.start, wall.end]:
			if not shown_vertices.any(func(item: Vector3) -> bool: return item.distance_to(vertex) < 0.001):
				shown_vertices.append(vertex)
				var handle := MeshInstance3D.new()
				var mesh := SphereMesh.new()
				mesh.radius = 0.14
				mesh.height = 0.28
				var material := StandardMaterial3D.new()
				material.albedo_color = Color("4ebeff")
				material.emission_enabled = true
				material.emission = Color("176fa8")
				mesh.material = material
				handle.mesh = mesh
				handle.position = vertex + Vector3.UP * 0.14
				handle_root.add_child(handle)


func _refresh_wall_junctions() -> void:
	for child in junction_root.get_children():
		junction_root.remove_child(child)
		child.queue_free()
	var junctions: Dictionary = {}
	for wall in walls:
		var thickness: float = wall.get("thickness", DEFAULT_WALL_THICKNESS)
		for vertex: Vector3 in [wall.start, wall.end]:
			var key := "%.4f:%.4f" % [vertex.x, vertex.z]
			if not junctions.has(key):
				junctions[key] = {"point": vertex, "count": 0, "thickness": 0.0}
			var junction: Dictionary = junctions[key]
			junction["count"] = int(junction["count"]) + 1
			junction["thickness"] = max(float(junction["thickness"]), thickness)
	for value in junctions.values():
		var junction: Dictionary = value
		if int(junction["count"]) < 2:
			continue
		var connector := MeshInstance3D.new()
		connector.name = "WallJunction"
		var mesh := BoxMesh.new()
		var thickness: float = junction["thickness"]
		mesh.size = Vector3(thickness, WALL_HEIGHT, thickness)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d9e2ef")
		material.roughness = 0.82
		mesh.material = material
		connector.mesh = mesh
		var point: Vector3 = junction["point"]
		connector.position = point + Vector3.UP * (WALL_HEIGHT * 0.5)
		junction_root.add_child(connector)


func _position_wall(instance: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var direction := finish - start
	var mesh := instance.mesh as BoxMesh
	mesh.size.z = direction.length()
	instance.position = (start + finish) * 0.5 + Vector3.UP * (WALL_HEIGHT * 0.5)
	instance.rotation.y = atan2(direction.x, direction.z)


func _update_preview() -> void:
	if active_start == null:
		return
	preview_wall.visible = active_start.distance_to(preview_end) > 0.001
	if preview_wall.visible:
		_position_wall(preview_wall, active_start, preview_end)
		length_label.text = "Comprimento: %.2f m" % active_start.distance_to(preview_end)


func _process(delta: float) -> void:
	if view_mode != ViewMode.FIRST_PERSON or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): direction.z -= 1.0
	if Input.is_key_pressed(KEY_S): direction.z += 1.0
	if Input.is_key_pressed(KEY_A): direction.x -= 1.0
	if Input.is_key_pressed(KEY_D): direction.x += 1.0
	if direction != Vector3.ZERO:
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		var right := camera.global_transform.basis.x
		right.y = 0.0
		camera.global_position += (forward.normalized() * -direction.z + right.normalized() * direction.x) * WALK_SPEED * delta
