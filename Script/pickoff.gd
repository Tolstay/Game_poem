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

# 文本显示组件引用
var text_display: Node2D

# 状态控制
var is_picked: bool = false
var is_interaction_disabled: bool = false  # 新增：控制交互是否被禁用

# 长按相关变量
@export var hold_time_required: float = 0.8  # 长按所需时间
@export var shake_start_threshold: float = 0.3  # 开始抖动的时间阈值
@export var max_shake_intensity: float = 1.0  # 最大抖动强度
@export var mouse_move_tolerance: float = 20.0  # 允许的鼠标移动距离

var is_mouse_down: bool = false
var mouse_down_timer: float = 0.0
var mouse_down_position: Vector2
var original_sprite_position: Vector2
var sprite_node: Sprite2D

# 掉落动画相关
var fall_tween: Tween
var original_sprite_rotation: float
var original_sprite_scale: Vector2

# 鼠标悬停状态
var is_mouse_hovering: bool = false

# 对象类型标识（用于调试）
var object_type: String = "Unknown"

func _ready():
	# 查找Camera2D（用于坐标转换）
	camera = _find_camera2d()
	
	# 连接signalbus的disable_pickoff_interaction信号
	call_deferred("_connect_signalbus_signals")
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

	# 查找Sprite2D节点用于抖动动画
	sprite_node = _find_sprite2d(pickable_object)
	if sprite_node:
		original_sprite_position = sprite_node.position
		original_sprite_rotation = sprite_node.rotation
		original_sprite_scale = sprite_node.scale
	
	# 查找textdisplay组件
	text_display = _find_text_display()
	if text_display:
		_hide_text_display()  # 初始时隐藏文本

## 连接signalbus的信号
func _connect_signalbus_signals():
	# 查找signalbus节点，优先使用unique_name方式

	var signalbus = get_tree().current_scene.find_child("Signalbus", true, false)
	
	if signalbus and signalbus.has_signal("disable_pickoff_interaction"):
		if not signalbus.disable_pickoff_interaction.is_connected(_on_disable_pickoff_interaction):
			signalbus.disable_pickoff_interaction.connect(_on_disable_pickoff_interaction)
			print("已连接到disable_pickoff_interaction信号")
	else:
		print("警告：未找到signalbus或disable_pickoff_interaction信号")
	
	
	if signalbus and signalbus.has_signal("able_pickoff_interaction"):
		if not signalbus.able_pickoff_interaction.is_connected(_on_able_pickoff_interaction):
			signalbus.able_pickoff_interaction.connect(_on_able_pickoff_interaction)
			print("已连接到able_pickoff_interaction信号")
	else:
		print("警告：未找到signalbus或able_pickoff_interaction信号")

## 响应禁用交互信号
func _on_disable_pickoff_interaction():
	is_interaction_disabled = true
	print("Pickoff交互已被禁用 - ", object_type)
	
func _on_able_pickoff_interaction():
	is_interaction_disabled = false
	print("解除交互禁用")

## 检查交互是否被禁用（供外部调用）
func is_interaction_enabled() -> bool:
	return not is_interaction_disabled

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

## 在指定节点中查找Sprite2D
func _find_sprite2d(target_node: Node) -> Sprite2D:
	# 直接检查是否有Sprite2D子节点
	for child in target_node.get_children():
		if child is Sprite2D:
			return child
	
	# 如果没找到，递归查找
	for child in target_node.get_children():
		var found_sprite = _find_sprite2d(child)
		if found_sprite:
			return found_sprite
	
	return null

## 查找textdisplay组件
func _find_text_display() -> Node2D:
	# 从Logic节点查找textdisplay
	var logic_node = get_parent()  # pickoff在Logic下
	if logic_node:
		for child in logic_node.get_children():
			if child.name == "textdisplay":
				return child
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
	if is_picked or is_interaction_disabled:  # 修改：同时检查是否被禁用
		return  # 如果已经被摘取或交互被禁用，不再处理输入
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 鼠标按下
				var mouse_world_pos = _get_mouse_world_position()
				if _is_mouse_in_object_collision(mouse_world_pos):
					_start_hold_interaction(mouse_world_pos)
			else:
				# 鼠标释放
				_cancel_hold_interaction()
	
	elif event is InputEventMouseMotion and is_mouse_down:
		# 检查鼠标是否移动过远
		var current_mouse_pos = _get_mouse_world_position()
		if mouse_down_position.distance_to(current_mouse_pos) > mouse_move_tolerance:
			_cancel_hold_interaction()

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

func _process(delta):
	# 检测鼠标悬停
	if not is_picked and not is_interaction_disabled:
		_check_mouse_hover()
	
	if is_mouse_down and not is_picked and not is_interaction_disabled:
		mouse_down_timer += delta
		
		# 开始抖动动画
		if mouse_down_timer >= shake_start_threshold and sprite_node:
			_apply_shake_animation()
		
		# 检查是否到达长按时间
		if mouse_down_timer >= hold_time_required:
			_complete_hold_interaction()

## 开始长按交互
func _start_hold_interaction(mouse_pos: Vector2):
	is_mouse_down = true
	mouse_down_timer = 0.0
	mouse_down_position = mouse_pos

## 取消长按交互
func _cancel_hold_interaction():
	if is_mouse_down:
		is_mouse_down = false
		mouse_down_timer = 0.0
		_reset_sprite_position()

## 完成长按交互
func _complete_hold_interaction():
	if is_mouse_down:
		is_mouse_down = false
		mouse_down_timer = 0.0
		_reset_sprite_position()
		_pick_object()

## 应用抖动动画
func _apply_shake_animation():
	if not sprite_node:
		return
	
	# 计算抖动强度（随时间增加）
	var progress = (mouse_down_timer - shake_start_threshold) / (hold_time_required - shake_start_threshold)
	progress = clamp(progress, 0.0, 1.0)
	var shake_intensity = progress * max_shake_intensity
	
	# 生成随机偏移
	var shake_offset = Vector2(
		randf_range(-shake_intensity, shake_intensity),
		randf_range(-shake_intensity, shake_intensity)
	)
	
	sprite_node.position = original_sprite_position + shake_offset

## 重置Sprite位置和属性
func _reset_sprite_position():
	if sprite_node:
		sprite_node.position = original_sprite_position
		sprite_node.rotation = original_sprite_rotation
		sprite_node.scale = original_sprite_scale
	
	# 停止掉落动画
	_stop_falling_animation()

## 停止掉落动画
func _stop_falling_animation():
	if fall_tween:
		fall_tween.kill()
		fall_tween = null

## 摘取对象 - 应用重力并垂直落下
func _pick_object():
	if is_picked or not pickable_object:
		return
	
	is_picked = true
	
	# 如果是petal，从对应的位置group中移除
	if object_type == "Petal":
		_remove_petal_from_position_group()
	
	# 设置羽毛般的轻柔掉落效果
	_apply_feather_like_falling()
	
	# 发出基础信号
	if object_type == "Fruit":
		fruit_picked.emit()
	
	# 可以在这里添加特定对象类型的额外行为
	_handle_object_specific_pickup_behavior()

## 应用羽毛般的轻柔掉落效果
func _apply_feather_like_falling():
	if not pickable_object:
		return
	
	# 设置轻柔的重力
	pickable_object.gravity_scale = 0.15  # 大幅降低重力影响
	
	# 清除之前的速度
	pickable_object.linear_velocity = Vector2.ZERO
	pickable_object.angular_velocity = 0.0
	
	# 设置空气阻力，让对象像羽毛一样慢慢下落
	pickable_object.linear_damp = 3.0  # 线性阻尼，减缓下落速度
	pickable_object.angular_damp = 2.0  # 角度阻尼，减缓旋转
	
	# 设置碰撞层和碰撞掩码
	pickable_object.collision_layer = 1
	pickable_object.collision_mask = 1
	
	# 给一个非常轻柔的初始下落速度
	pickable_object.linear_velocity.y = 15.0  # 很小的初始下落速度
	
	# 添加一点随机的横向飘动，模拟空气流动
	var random_horizontal = randf_range(-10.0, 10.0)
	pickable_object.linear_velocity.x = random_horizontal
	
	# 添加轻微的随机旋转，增加飘落真实感
	var random_rotation = randf_range(-0.5, 0.5)
	pickable_object.angular_velocity = random_rotation
	
	# 启动掉落动画（旋转和缩放）
	_start_falling_animation()

## 启动掉落动画
func _start_falling_animation():
	if not sprite_node:
		return
	
	# 创建Tween节点
	if fall_tween:
		fall_tween.kill()
	fall_tween = create_tween()
	fall_tween.set_loops()  # 设置为循环动画
	
	# 旋转动画 - 缓慢旋转一整圈
	var rotation_tween = create_tween()
	rotation_tween.set_loops()
	rotation_tween.tween_property(sprite_node, "rotation", 
		original_sprite_rotation + TAU, 8.0)  # 8秒转一圈
	rotation_tween.set_ease(Tween.EASE_IN_OUT)
	rotation_tween.set_trans(Tween.TRANS_SINE)
	
	# 缩放动画 - 缓慢缩小到消失
	var scale_tween = create_tween()
	scale_tween.tween_property(sprite_node, "scale", 
		original_sprite_scale * 0.1, 8.0)  # 8秒内缩小到10%
	scale_tween.set_ease(Tween.EASE_OUT)
	scale_tween.set_trans(Tween.TRANS_QUAD)
	
	# 缩放动画完成后销毁对象
	scale_tween.tween_callback(_destroy_pickable_object)

## 销毁pickable对象
func _destroy_pickable_object():
	if pickable_object and is_instance_valid(pickable_object):
		print("销毁掉落对象: ", object_type)
		pickable_object.queue_free()

## 检测鼠标悬停
func _check_mouse_hover():
	var mouse_world_pos = _get_mouse_world_position()
	var is_hovering = _is_mouse_in_object_collision(mouse_world_pos)
	
	# 检查悬停状态是否改变
	if is_hovering != is_mouse_hovering:
		is_mouse_hovering = is_hovering
		
		if is_mouse_hovering:
			_show_text_display()
		else:
			_hide_text_display()

## 显示文本
func _show_text_display():
	if text_display:
		text_display.visible = true

## 隐藏文本
func _hide_text_display():
	if text_display:
		text_display.visible = false

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

## 手动发出fruit信号（供调试使用）
func debug_emit_fruit_signal():
	if object_type == "Fruit":
		fruit_picked.emit()
