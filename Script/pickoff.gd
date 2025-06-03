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
		print("错误：无法找到父级RigidBody2D节点")
		return
	
	# 确定对象类型（用于调试信息）
	object_type = _determine_object_type(pickable_object.name)
	
	# 获取碰撞形状
	collision_shape = _find_collision_shape(pickable_object)
	if not collision_shape:
		print("错误：无法在 ", object_type, " 中找到碰撞形状")
		return
	
	# 查找Camera2D（用于坐标转换）
	camera = _find_camera2d()
	if camera:
		print("找到Camera2D，可以进行坐标转换")
	else:
		print("未找到Camera2D，使用默认坐标系")
	
	print("Pickoff脚本初始化完成，", object_type, " 位置: ", pickable_object.global_position)

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
			
			print("检测到鼠标左键点击")
			print("  原始鼠标位置：", event.global_position)
			print("  世界坐标位置：", mouse_world_pos)
			if camera:
				print("  Camera位置：", camera.global_position)
			
			# 检查鼠标点击是否在对象的碰撞区域内
			if _is_mouse_in_object_collision(mouse_world_pos):
				print("点击命中", object_type, "碰撞区域！")
				_pick_object()
			else:
				print("点击未命中", object_type, "碰撞区域")

## 检查鼠标位置是否在对象的碰撞区域内
func _is_mouse_in_object_collision(mouse_pos: Vector2) -> bool:
	if not pickable_object or not collision_shape:
		print("检查碰撞失败：pickable_object或collision_shape为空")
		return false
	
	# 将鼠标世界坐标转换为对象的本地坐标
	var local_mouse_pos = pickable_object.to_local(mouse_pos)
	print(object_type, " 全局位置: ", pickable_object.global_position, " 鼠标世界位置: ", mouse_pos, " 本地位置: ", local_mouse_pos)
	
	# 检查不同类型的碰撞形状
	var shape = collision_shape.shape
	
	if shape is CircleShape2D:
		var circle_shape = shape as CircleShape2D
		var distance = local_mouse_pos.length()
		print("圆形碰撞检测：距离=", distance, " 半径=", circle_shape.radius, " 结果=", distance <= circle_shape.radius)
		return distance <= circle_shape.radius
		
	elif shape is RectangleShape2D:
		var rect_shape = shape as RectangleShape2D
		var half_size = rect_shape.size / 2.0
		var in_bounds = abs(local_mouse_pos.x) <= half_size.x and abs(local_mouse_pos.y) <= half_size.y
		print("矩形碰撞检测：位置=", local_mouse_pos, " 半尺寸=", half_size, " 结果=", in_bounds)
		return in_bounds
		
	elif shape is CapsuleShape2D:
		var capsule_shape = shape as CapsuleShape2D
		# 简化为圆形检测（可以更精确实现）
		var distance = local_mouse_pos.length()
		var effective_radius = max(capsule_shape.radius, capsule_shape.height / 2.0)
		print("胶囊碰撞检测：距离=", distance, " 有效半径=", effective_radius, " 结果=", distance <= effective_radius)
		return distance <= effective_radius
	
	else:
		print("不支持的碰撞形状类型：", shape.get_class())
		return false

## 摘取对象 - 应用重力并垂直落下
func _pick_object():
	if is_picked or not pickable_object:
		return
	
	print(object_type, " 被摘取！开始下落...")
	is_picked = true
	
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
		print("发出 fruit_picked 信号")
	
	# 可以在这里添加特定对象类型的额外行为
	_handle_object_specific_pickup_behavior()

## 处理不同对象类型的特定行为
func _handle_object_specific_pickup_behavior():
	match object_type:
		"Fruit":
			print("执行Fruit特定的摘取行为")
			# 可以添加果实特有的效果，比如音效、粒子等
		"Petal":
			print("执行Petal特定的摘取行为")
			# 可以添加花瓣特有的效果，比如飘落动画等
		_:
			print("执行通用摘取行为")

## 获取对象类型（供外部调用）
func get_object_type() -> String:
	return object_type

## 检查是否已被摘取（供外部调用）
func is_object_picked() -> bool:
	return is_picked

## 手动发出fruit信号（供调试使用）
func debug_emit_fruit_signal():
	if object_type == "Fruit":
		fruit_picked.emit()
		print("手动发出fruit_picked信号") 
