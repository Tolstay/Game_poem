extends CharacterBody2D

## 简单的移动控制器
## 支持鼠标跟随移动，无重力影响

# 移动参数
@export var move_speed: float = 180.0  # 移动速度
@export var acceleration: float = 600.0  # 加速度
@export var friction: float = 1000.0  # 摩擦力/减速度

# 鼠标跟随参数
@export_group("Mouse Following", "mouse_")
@export var mouse_follow_enabled: bool = true  # 启用鼠标跟随
@export var mouse_min_distance: float = 88.0  # 最小跟随距离，小于此距离不移动
@export var wasd_control_enabled: bool = false  # WASD控制开关（默认禁用）

# 移动输入向量
var input_vector: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO

# 游戏状态控制
var gameover: bool = false  # 游戏结束状态，禁用移动跟随
@export var enable_zoom_out_on_gameover: bool = true # 控制游戏结束时是否启用缩放拉远效果

# 缩放拉远相关变量
var zoom_out_tween: Tween
var camera_node: Camera2D
var info_node: Label  # Info文字节点引用
var target_zoom_level: float = 0.3  # 目标缩放级别（更小的值=更远的视野）
@export var zoom_speed: float = 1.5  # 缩放速度（数值越大缩放越快）

# 边界限制
var movement_bounds: Rect2 = Rect2()  # 移动边界
var bounds_enabled: bool = false  # 是否启用边界限制


func _physics_process(delta):
	# 如果游戏结束，根据设置选择行为
	if gameover:
		if enable_zoom_out_on_gameover:
			# 启用缩放拉远效果：禁用移动，让缩放系统接管
			velocity = Vector2.ZERO
		else:
			# 传统行为：以petal相同的速度向下移动
			velocity = Vector2(0, 15.0)  # 15.0像素/秒向下，与petal掉落速度一致
		move_and_slide()
		return
	
	# 连接SignalBus的边界更新信号（延迟连接）
	_connect_signalbus_if_needed()
	
	# 获取输入
	_handle_input()
	
	# 应用移动
	_apply_movement(delta)
	
	# 执行移动
	move_and_slide()

## 处理输入
func _handle_input():
	input_vector = Vector2.ZERO
	
	# 如果游戏结束，不处理任何输入
	if gameover:
		return
	
	# 鼠标跟随逻辑
	if mouse_follow_enabled:
		var mouse_world_pos = _get_mouse_world_position()
		var distance_to_mouse = global_position.distance_to(mouse_world_pos)
		
		# 只有当距离大于最小距离时才移动
		if distance_to_mouse > mouse_min_distance:
			target_position = mouse_world_pos
			input_vector = (target_position - global_position).normalized()
	
	# WASD控制（如果启用）
	if wasd_control_enabled:
		var wasd_input = Vector2.ZERO
		
		if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			wasd_input.x += 1
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			wasd_input.x -= 1
		if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			wasd_input.y += 1
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			wasd_input.y -= 1
		
		# 如果有WASD输入，优先使用WASD（覆盖鼠标输入）
		if wasd_input != Vector2.ZERO:
			input_vector = wasd_input.normalized()

## 获取鼠标在世界坐标系中的位置
func _get_mouse_world_position() -> Vector2:
	# 直接使用get_global_mouse_position()
	# 在SubViewport中这应该返回正确的坐标
	return get_global_mouse_position()

## 应用移动逻辑
func _apply_movement(delta):
	if input_vector != Vector2.ZERO:
		# 有输入时加速
		velocity = velocity.move_toward(input_vector * move_speed, acceleration * delta)
	else:
		# 无输入时减速
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	
	# 应用边界限制
	if bounds_enabled:
		_apply_boundary_constraints()
	
	# 确保无重力影响（如果有任何垂直重力，将其清除）
	# CharacterBody2D默认不受重力影响，但为了确保我们明确设置
	# 不需要额外处理重力，因为我们完全控制了velocity

## 调试信息（可选，用于测试坐标转换）
func _get_debug_info() -> String:
	var mouse_world = _get_mouse_world_position()
	var distance = global_position.distance_to(mouse_world)
	return "Mouse: %s, Player: %s, Distance: %.1f" % [mouse_world, global_position, distance]

## 设置游戏结束状态（供外部调用）
func set_gameover(state: bool):
	gameover = state
	if gameover:
		print("🎮 [Movement] 游戏结束，移动跟随已禁用")
		if enable_zoom_out_on_gameover:
			_start_zoom_out_effect()

## 获取游戏结束状态（供外部调用）
func is_gameover() -> bool:
	return gameover

## 连接SignalBus信号（延迟连接）
func _connect_signalbus_if_needed():
	# 查找SignalBus节点
	var signalbus = get_tree().get_first_node_in_group("signalbus")
	if signalbus and signalbus.has_signal("movement_bounds_updated"):
		# 检查是否已经连接
		if not signalbus.movement_bounds_updated.is_connected(_on_movement_bounds_updated):
			signalbus.movement_bounds_updated.connect(_on_movement_bounds_updated)

## 当边界更新时调用
func _on_movement_bounds_updated(bounds: Rect2):
	movement_bounds = bounds
	bounds_enabled = bounds.size.x > 1 and bounds.size.y > 1  # 只有有效边界才启用
	
	if bounds_enabled:
		print("🎯 [Movement] 边界已更新: ", bounds)
	else:
		print("🚫 [Movement] 移动被禁用（无fruit）")

## 应用边界约束
func _apply_boundary_constraints():
	if not bounds_enabled:
		return
	
	# 计算预期的新位置
	var next_position = global_position + velocity * get_physics_process_delta_time()
	
	# 限制在边界内
	next_position.x = clamp(next_position.x, movement_bounds.position.x, movement_bounds.position.x + movement_bounds.size.x)
	next_position.y = clamp(next_position.y, movement_bounds.position.y, movement_bounds.position.y + movement_bounds.size.y)
	
	# 如果位置被限制，调整速度
	var constrained_velocity = (next_position - global_position) / get_physics_process_delta_time()
	velocity = constrained_velocity

## 开始缩放拉远效果
func _start_zoom_out_effect():
	# 查找Camera2D节点
	camera_node = _find_camera2d_child()
	if not camera_node:
		print("⚠️ [Movement] 未找到Camera2D，缩放效果无法启动")
		return
	
	# 查找Info节点
	info_node = _find_info_node()
	if not info_node:
		print("⚠️ [Movement] 未找到Info节点，文字可能会被缩放")
	
	print("📹 [Movement] 开始缩放拉远效果")
	
	# 获取所有branchpoint的位置
	var branch_bounds = _get_all_branch_points_bounds()
	if branch_bounds == Rect2():
		print("⚠️ [Movement] 未找到任何branchpoint，使用默认缩放")
		_perform_zoom_out(target_zoom_level)
		return
	
	# 计算需要的缩放级别以显示所有branchpoint
	var required_zoom = _calculate_required_zoom_for_bounds(branch_bounds)
	print("📏 [Movement] 计算的所需缩放级别: ", required_zoom)
	
	_perform_zoom_out(required_zoom)

## 查找Camera2D子节点
func _find_camera2d_child() -> Camera2D:
	# 在当前节点的子节点中查找Camera2D
	for child in get_children():
		if child is Camera2D:
			return child as Camera2D
	return null

## 查找Info节点
func _find_info_node() -> Label:
	if camera_node:
		# Info是Camera2D的子节点
		for child in camera_node.get_children():
			if child.name == "Info" and child is Label:
				return child as Label
	return null

## 获取所有branchpoint的边界
func _get_all_branch_points_bounds() -> Rect2:
	var all_points: Array[Vector2] = []
	
	# 通过fruits脚本获取所有点的位置
	var main_scene = get_tree().current_scene
	var subviewport_container = main_scene.get_node_or_null("SubViewportContainer")
	if not subviewport_container:
		return Rect2()
	
	var subviewport = subviewport_container.get_node_or_null("SubViewport")
	if not subviewport:
		return Rect2()
	
	var fruits_node = subviewport.get_node_or_null("Fruits")
	if not fruits_node or not fruits_node.has_method("get_all_point_positions"):
		print("⚠️ [Movement] 未找到Fruits节点或get_all_point_positions方法")
		return Rect2()
	
	# 获取所有点的位置
	var point_positions = fruits_node.get_all_point_positions()
	if point_positions.size() == 0:
		return Rect2()
	
	# 计算边界
	var min_x = point_positions[0].x
	var max_x = point_positions[0].x
	var min_y = point_positions[0].y
	var max_y = point_positions[0].y
	
	for pos in point_positions:
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y)
		max_y = max(max_y, pos.y)
	
	# 添加一些边距
	var padding = 100.0
	return Rect2(
		Vector2(min_x - padding, min_y - padding),
		Vector2(max_x - min_x + padding * 2, max_y - min_y + padding * 2)
	)

## 计算显示指定边界所需的缩放级别
func _calculate_required_zoom_for_bounds(bounds: Rect2) -> float:
	if not camera_node:
		return target_zoom_level
	
	# 获取ViewPort大小
	var viewport_size = get_viewport().get_visible_rect().size
	
	# 计算所需的缩放比例
	var zoom_x = viewport_size.x / bounds.size.x
	var zoom_y = viewport_size.y / bounds.size.y
	
	# 使用较小的缩放值以确保所有内容都可见
	var required_zoom = min(zoom_x, zoom_y) * 0.8  # 0.8为安全边距
	
	# 限制最小和最大缩放
	required_zoom = clamp(required_zoom, 0.1, 1.0)
	
	return required_zoom

## 执行缩放拉远动画
func _perform_zoom_out(target_zoom: float):
	if not camera_node:
		return
	
	# 停止之前的缩放动画
	if zoom_out_tween:
		zoom_out_tween.kill()
	
	zoom_out_tween = create_tween()
	zoom_out_tween.set_ease(Tween.EASE_OUT)
	zoom_out_tween.set_trans(Tween.TRANS_CUBIC)
	
	# 计算缩放持续时间（由zoom_speed控制）
	var current_zoom = camera_node.zoom.x
	var zoom_difference = abs(current_zoom - target_zoom)
	var duration = zoom_difference / zoom_speed  # zoom_speed越大，缩放越快
	
	print("📹 [Movement] 缩放从 ", current_zoom, " 到 ", target_zoom, " 持续 ", duration, " 秒")
	
	# 创建缩放动画（同时处理相机和Info的缩放）
	zoom_out_tween.tween_method(_update_camera_and_info_zoom, current_zoom, target_zoom, duration)

## 更新相机和Info缩放（供Tween调用）
func _update_camera_and_info_zoom(zoom_value: float):
	if camera_node and is_instance_valid(camera_node):
		camera_node.zoom = Vector2(zoom_value, zoom_value)
		
		# 同时反向缩放Info节点，使其保持原始大小
		if info_node and is_instance_valid(info_node):
			var inverse_scale = 1.0 / zoom_value
			info_node.scale = Vector2(inverse_scale, inverse_scale)

## 更新相机缩放（供Tween调用，保持向后兼容）
func _update_camera_zoom(zoom_value: float):
	_update_camera_and_info_zoom(zoom_value)
