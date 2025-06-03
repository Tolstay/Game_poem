extends Node2D

## 通用Pickoff脚本
## 处理任何对象（fruit、petal等）的鼠标交互和重力应用

# 基础信号定义
signal fruit_picked()  # 当fruit被摘除时发出

# 引用父节点（可以是fruit、petal或任何RigidBody2D对象）
var pickable_object: RigidBody2D
var collision_shape: CollisionShape2D

# Camera2D引用（用于坐标转换）
var camera: Camera2D

# 状态控制
var is_picked: bool = false

# 对象类型标识（用于调试）
var object_type: String = "Unknown"

func _ready():
	# 自动查找父层级中的RigidBody2D节点
	pickable_object = _find_parent_rigidbody()
	if not pickable_object:
		return
	
	# 确定对象类型（用于调试信息）
	object_type = _determine_object_type(pickable_object.name)
	
	# 获取碰撞形状
	collision_shape = _find_collision_shape(pickable_object)
	if not collision_shape:
		return
	
	# 查找Camera2D（用于坐标转换）
	camera = _find_camera2d()

## 查找场景中的Camera2D节点
func _find_camera2d() -> Camera2D:
	# 从场景根开始查找Camera2D
	var scene_root = get_tree().current_scene
	return _find_camera_recursive(scene_root)

## 递归查找Camera2D
func _find_camera_recursive(node: Node) -> Camera2D:
	if node is Camera2D:
		return node as Camera2D
	
	for child in node.get_children():
		var found_camera = _find_camera_recursive(child)
		if found_camera:
			return found_camera
	
	return null

## 获取正确的鼠标世界坐标
func _get_mouse_world_position() -> Vector2:
	if camera:
		# 使用Camera2D的get_global_mouse_position()获取真实的世界坐标
		return camera.get_global_mouse_position()
	else:
		# 如果没有Camera2D，使用默认的全局鼠标位置
		return get_global_mouse_position()

## 自动查找父层级中的RigidBody2D节点
func _find_parent_rigidbody() -> RigidBody2D:
	var current_node = get_parent()
	
	# 向上查找直到找到RigidBody2D或到达场景根
	while current_node != null:
		if current_node is RigidBody2D:
			return current_node
		current_node = current_node.get_parent()
	
	return null

## 在指定节点中查找CollisionShape2D
func _find_collision_shape(target_node: Node) -> CollisionShape2D:
	# 直接检查是否有CollisionShape2D子节点
	for child in target_node.get_children():
		if child is CollisionShape2D:
			return child
	
	# 如果没找到，递归查找
	for child in target_node.get_children():
		var found_shape = _find_collision_shape(child)
		if found_shape:
			return found_shape
	
	return null

## 根据节点名称确定对象类型
func _determine_object_type(node_name: String) -> String:
	var name_lower = node_name.to_lower()
	if "fruit" in name_lower:
		return "Fruit"
	elif "petal" in name_lower:
		return "Petal"
	else:
		# 如果节点名称不包含类型信息，检查场景文件路径
		var parent_node = pickable_object
		if parent_node and parent_node.scene_file_path:
			var scene_path = parent_node.scene_file_path.to_lower()
			if "fruit" in scene_path:
				return "Fruit"
			elif "petal" in scene_path:
				return "Petal"
		
		return "PickableObject"

func _input(event):
	if is_picked:
		return  # 如果已经被摘取，不再处理输入
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# 获取正确的鼠标世界坐标
			var mouse_world_pos = _get_mouse_world_position()
			
			# 检查鼠标点击是否在对象的碰撞区域内
			if _is_mouse_in_object_collision(mouse_world_pos):
				_pick_object()

## 检查鼠标位置是否在对象的碰撞区域内
func _is_mouse_in_object_collision(mouse_pos: Vector2) -> bool:
	if not pickable_object or not collision_shape:
		return false
	
	# 将鼠标世界坐标转换为对象的本地坐标
	var local_mouse_pos = pickable_object.to_local(mouse_pos)
	
	# 检查不同类型的碰撞形状
	var shape = collision_shape.shape
	
	if shape is CircleShape2D:
		var circle_shape = shape as CircleShape2D
		var distance = local_mouse_pos.length()
		return distance <= circle_shape.radius
		
	elif shape is RectangleShape2D:
		var rect_shape = shape as RectangleShape2D
		var half_size = rect_shape.size / 2.0
		var in_bounds = abs(local_mouse_pos.x) <= half_size.x and abs(local_mouse_pos.y) <= half_size.y
		return in_bounds
		
	elif shape is CapsuleShape2D:
		var capsule_shape = shape as CapsuleShape2D
		# 简化为圆形检测（可以更精确实现）
		var distance = local_mouse_pos.length()
		var effective_radius = max(capsule_shape.radius, capsule_shape.height / 2.0)
		return distance <= effective_radius
	
	else:
		return false

## 摘取对象 - 应用重力并垂直落下
func _pick_object():
	if is_picked or not pickable_object:
		return
	
	is_picked = true
	
	# 如果是petal，从对应的位置group中移除
	if object_type == "Petal":
		_remove_petal_from_position_group()
	
	# 启用重力
	pickable_object.gravity_scale = 1.0
	
	# 清除之前的速度，确保垂直落下
	pickable_object.linear_velocity = Vector2.ZERO
	pickable_object.angular_velocity = 0.0
	
	# 设置碰撞层和碰撞掩码，让对象可以与地面等碰撞
	pickable_object.collision_layer = 1
	pickable_object.collision_mask = 1
	
	# 可选：添加一个小的向下初始速度，确保开始下落
	pickable_object.linear_velocity.y = 50.0
	
	# 发出基础信号
	if object_type == "Fruit":
		fruit_picked.emit()
	
	# 可以在这里添加特定对象类型的额外行为
	_handle_object_specific_pickup_behavior()

## 从位置group中移除petal
func _remove_petal_from_position_group():
	if not pickable_object:
		return
	
	# 获取petal所属的所有group
	var groups = pickable_object.get_groups()
	
	# 找到并移除位置相关的group
	for group_name in groups:
		if group_name.begins_with("petal_position_"):
			pickable_object.remove_from_group(group_name)
			print("Petal从group中移除: ", group_name)
			break

## 处理不同对象类型的特定行为
func _handle_object_specific_pickup_behavior():
	match object_type:
		"Fruit":
			pass  # 可以添加果实特有的效果，比如音效、粒子等
		"Petal":
			pass  # 可以添加花瓣特有的效果，比如飘落动画等
		_:
			pass  # 执行通用摘取行为

## 获取对象类型（供外部调用）
func get_object_type() -> String:
	return object_type

## 检查是否已被摘取（供外部调用）
func is_object_picked() -> bool:
	return is_picked
