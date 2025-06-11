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

# 音频播放器引用
var fruit_pickoff_audio: AudioStreamPlayer
var petal_pickoff_audio: AudioStreamPlayer

# 状态控制
var is_picked: bool = false
var is_interaction_disabled: bool = false  # 新增：控制交互是否被禁用
var gameover: bool = false  # 游戏结束状态，禁用所有交互

# 长按相关变量
@export var hold_time_required: float = 0.8  # 长按所需时间
@export var shake_start_threshold: float = 0.3  # 开始抖动的时间阈值
@export var max_shake_intensity: float = 1.0  # 最大抖动强度
@export var mouse_move_tolerance: float = 20.0  # 允许的鼠标移动距离

# 风抖动参数
@export_group("Wind Shake Effect", "wind_")
@export var wind_shake_enabled: bool = true              # 是否启用风抖动
@export var wind_shake_intensity: float = 0.5           # 风抖动强度（像素）
@export var wind_shake_frequency: float = 0.3           # 抖动频率（秒）
@export var wind_shake_duration: float = 7            # 持续时间（秒，-1为无限）
@export var wind_shake_fade_in_time: float = 3.0        # 渐入时间
@export var wind_shake_fade_out_time: float = 5.0       # 渐出时间
@export var wind_horizontal_bias: float = 0.2           # 水平抖动偏向（0.0-1.0）
@export var wind_randomness: float = 0.5                # 随机性（0.0-1.0）

var is_mouse_down: bool = false
var mouse_down_timer: float = 0.0
var mouse_down_position: Vector2
var original_sprite_position: Vector2
var sprite_node: Sprite2D

# 掉落动画相关
var fall_tween: Tween
var original_sprite_rotation: float
var original_sprite_scale: Vector2

# 风抖动相关变量
var wind_shake_tween: Tween
var is_wind_shaking: bool = false
var wind_shake_start_time: float = 0.0  # 使用全局时间基准
var current_wind_intensity: float = 0.0
var is_wind_fading_out: bool = false

# 对象类型标识（用于调试）
var object_type: String = "Unknown"

# 鼠标悬停抖动效果相关变量
@export var hover_shake_enabled: bool = true  # 是否启用悬停抖动效果
@export var hover_shake_intensity: float = 1.0  # 悬停抖动强度（像素，向下移动距离）
@export var hover_shake_duration: float = 0.8  # 单次抖动持续时间（秒）
var is_mouse_hovering: bool = false
var hover_shake_tween: Tween
var hover_played_this_session: bool = false  # 标记本次悬停是否已播放过抖动

func _ready():
	# 查找Camera2D（用于坐标转换）
	camera = _find_camera2d()
	
	# 查找fruit音频播放器
	var fruit_possible_names = ["fruit_pickoff", "AudioStreamPlayer", "fruit_audio"]
	for audio_name in fruit_possible_names:
		fruit_pickoff_audio = get_node_or_null(audio_name)
		if fruit_pickoff_audio:
			break
	
	# 查找petal音频播放器
	var petal_possible_names = ["petal_pickoff", "petal_audio"]
	for audio_name in petal_possible_names:
		petal_pickoff_audio = get_node_or_null(audio_name)
		if petal_pickoff_audio:
			break
	

	
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

## 连接signalbus的信号
func _connect_signalbus_signals():
	# 查找signalbus节点，优先使用unique_name方式

	var signalbus = get_tree().current_scene.find_child("Signalbus", true, false)
	
	if signalbus and signalbus.has_signal("disable_pickoff_interaction"):
		if not signalbus.disable_pickoff_interaction.is_connected(_on_disable_pickoff_interaction):
			signalbus.disable_pickoff_interaction.connect(_on_disable_pickoff_interaction)
		
	
	if signalbus and signalbus.has_signal("able_pickoff_interaction"):
		if not signalbus.able_pickoff_interaction.is_connected(_on_able_pickoff_interaction):
			signalbus.able_pickoff_interaction.connect(_on_able_pickoff_interaction)

## 响应禁用交互信号
func _on_disable_pickoff_interaction():
	is_interaction_disabled = true
	
	# 通过SignalBus发送风抖动信号（只有第一个接收到的对象发送，避免重复）
	if wind_shake_enabled:
		var signalbus = get_tree().current_scene.find_child("Signalbus", true, false)
		if signalbus and signalbus.has_signal("wind_shake_start"):
			signalbus.wind_shake_start.emit(wind_shake_duration, wind_shake_intensity, wind_shake_frequency, wind_horizontal_bias, wind_randomness)
		
		# 启动本地风抖动效果
		_start_wind_shake()

	
func _on_able_pickoff_interaction():
	is_interaction_disabled = false
	
	# 不再通过信号停止风抖动，完全依赖duration参数


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
	if is_picked or is_interaction_disabled or gameover:  # 修改：检查gameover状态
		return  # 如果已经被摘取、交互被禁用或游戏结束，不再处理输入
	
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
	# 检查鼠标悬停状态（不受gameover影响，但受interaction_disabled影响）
	if hover_shake_enabled and not is_interaction_disabled and not is_picked:
		_check_mouse_hover()
	
	if is_mouse_down and not is_picked and not is_interaction_disabled and not gameover:
		mouse_down_timer += delta
		
		# 开始抖动动画
		if mouse_down_timer >= shake_start_threshold and sprite_node:
			_apply_shake_animation()
		
		# 检查是否到达长按时间
		if mouse_down_timer >= hold_time_required:
			_complete_hold_interaction()
	
	# 更新风抖动（风抖动不受gameover影响）
	if is_wind_shaking:
		_update_wind_shake(delta)
	
	# 悬停抖动不需要手动更新计时器，由Tween系统管理

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
		# 只有在没有风抖动和悬停抖动时才重置位置
		if not is_wind_shaking and not is_mouse_hovering:
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
	
	# 停止所有抖动效果
	is_mouse_hovering = false  # 重置悬停状态
	_stop_hover_shake()
	
	# 根据对象类型播放相应的摘除音效
	if object_type == "Fruit":
		if fruit_pickoff_audio:
			fruit_pickoff_audio.play()
	elif object_type == "Petal":
		if petal_pickoff_audio:
			petal_pickoff_audio.play()
	
	# 如果是petal，从对应的位置group中移除
	if object_type == "Petal":
		_remove_petal_from_position_group()
	
	# 设置羽毛般的轻柔掉落效果
	_apply_feather_like_falling()
	
	# 发出基础信号
	if object_type == "Fruit":
		fruit_picked.emit()
		# 通知对应位置的bloodcut该fruit已被摘除
		_notify_bloodcut_fruit_removed()
	elif object_type == "Petal":
		# 通知SignalBus花瓣被摘除
		var signalbus = get_tree().current_scene.find_child("Signalbus", true, false)
		if signalbus and signalbus.has_method("on_petal_picked"):
			signalbus.on_petal_picked()
	
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
		original_sprite_scale * 0.1, 15.0)  # 8秒内缩小到10%
	scale_tween.set_ease(Tween.EASE_OUT)
	scale_tween.set_trans(Tween.TRANS_QUAD)
	
	# 缩放动画完成后销毁对象
	scale_tween.tween_callback(_destroy_pickable_object)

## 销毁pickable对象
func _destroy_pickable_object():
	if pickable_object and is_instance_valid(pickable_object):

		pickable_object.queue_free()

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

## 设置游戏结束状态（供外部调用）
func set_gameover(state: bool):
	gameover = state
	if gameover:
		# 游戏结束时取消当前的交互
		_cancel_hold_interaction()
		print("🎮 [Pickoff] 游戏结束，所有交互已禁用")

## 获取游戏结束状态（供外部调用）
func is_gameover() -> bool:
	return gameover

# ==================== 风抖动效果 ====================

## 启动风抖动效果
func _start_wind_shake():
	if not sprite_node:
		return
	
	
	# 允许重复播放，重置状态
	if is_wind_shaking:
		_force_stop_wind_shake()
	
	is_wind_shaking = true
	is_wind_fading_out = false
	wind_shake_start_time = Time.get_ticks_msec() / 1000.0  # 统一时间基准
	current_wind_intensity = 0.0
	
	# 创建渐入Tween
	if wind_shake_tween:
		wind_shake_tween.kill()
	wind_shake_tween = create_tween()
	wind_shake_tween.tween_property(self, "current_wind_intensity", wind_shake_intensity, wind_shake_fade_in_time)
	wind_shake_tween.set_ease(Tween.EASE_OUT)
	wind_shake_tween.set_trans(Tween.TRANS_SINE)

# 注意：已移除_stop_wind_shake方法，使用_start_wind_fade_out方法替代

## 完成风抖动停止
func _complete_wind_shake_stop():
	is_wind_shaking = false
	is_wind_fading_out = false
	current_wind_intensity = 0.0
	if sprite_node:
		sprite_node.position = original_sprite_position

## 开始风抖动渐出效果
func _start_wind_fade_out(fade_duration: float):
	if not is_wind_shaking or is_wind_fading_out:
		return
	
	is_wind_fading_out = true
	
	# 创建渐出Tween
	if wind_shake_tween:
		wind_shake_tween.kill()
	wind_shake_tween = create_tween()
	wind_shake_tween.tween_property(self, "current_wind_intensity", 0.0, fade_duration)
	wind_shake_tween.set_ease(Tween.EASE_IN)
	wind_shake_tween.set_trans(Tween.TRANS_SINE)
	
	# 渐出完成后重置状态
	wind_shake_tween.tween_callback(_complete_wind_shake_stop)

## 强制停止风抖动（用于重复播放）
func _force_stop_wind_shake():
	if wind_shake_tween:
		wind_shake_tween.kill()
		wind_shake_tween = null
	is_wind_shaking = false
	is_wind_fading_out = false
	current_wind_intensity = 0.0
	if sprite_node:
		sprite_node.position = original_sprite_position

## 更新风抖动
func _update_wind_shake(_delta: float):
	if not sprite_node:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed_time = current_time - wind_shake_start_time
	
	# 计算何时开始渐出（确保在总时长内完成渐出）
	var fade_out_start_time = max(0.0, wind_shake_duration - wind_shake_fade_out_time)
	
	# 检查是否应该开始渐出
	if wind_shake_duration > 0 and elapsed_time >= fade_out_start_time and current_wind_intensity > 0:
		var remaining_time = wind_shake_duration - elapsed_time
		if remaining_time <= wind_shake_fade_out_time and not is_wind_fading_out:
			_start_wind_fade_out(remaining_time)
			return
	
	# 检查是否完全结束
	if wind_shake_duration > 0 and elapsed_time >= wind_shake_duration:
		_force_stop_wind_shake()
		return
	
	# 应用风抖动
	_apply_wind_shake_animation(elapsed_time)

## 应用风抖动动画
func _apply_wind_shake_animation(elapsed_time: float):
	if not sprite_node or current_wind_intensity <= 0:
		return
	
	# 基于统一时间基准的正弦波抖动
	var time_factor = elapsed_time / wind_shake_frequency
	var base_shake_x = sin(time_factor * TAU) * current_wind_intensity
	var base_shake_y = sin(time_factor * TAU * 0.7) * current_wind_intensity
	
	# 应用水平偏向
	base_shake_x *= wind_horizontal_bias
	base_shake_y *= (1.0 - wind_horizontal_bias * 0.5)
	
	# 添加随机性（基于对象唯一性，确保每个对象的随机性一致但不同）
	var object_hash = hash(get_instance_id())
	var random_seed = int(elapsed_time * 10.0) + object_hash
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	
	var random_factor_x = rng.randf_range(-wind_randomness, wind_randomness)
	var random_factor_y = rng.randf_range(-wind_randomness, wind_randomness)
	
	var final_shake_x = base_shake_x + (random_factor_x * current_wind_intensity)
	var final_shake_y = base_shake_y + (random_factor_y * current_wind_intensity)
	
	# 应用抖动偏移
	var shake_offset = Vector2(final_shake_x, final_shake_y)
	sprite_node.position = original_sprite_position + shake_offset

# ==================== Bloodcut通知系统 ====================

## 通知对应位置的bloodcut该fruit已被摘除
func _notify_bloodcut_fruit_removed():
	if not pickable_object:
		return
	
	var fruit_position = pickable_object.global_position
	print("🍎 [DEBUG] 通知bloodcut fruit被摘除，位置:", fruit_position)
	
	# 通知SignalBus fruit已被移除
	_notify_signalbus_fruit_removed(fruit_position)
	
	# 查找相同位置的bloodcut
	var bloodcut = _find_bloodcut_at_position(fruit_position)
	if bloodcut and bloodcut.has_method("on_fruit_removed"):
		print("🍎 [DEBUG] 找到bloodcut，调用on_fruit_removed")
		bloodcut.on_fruit_removed()
	else:
		print("🍎 [DEBUG] 未找到对应位置的bloodcut")

## 查找指定位置的bloodcut
func _find_bloodcut_at_position(target_position: Vector2) -> Node:
	# 查找Fruitlayer或场景中的所有bloodcut
	var search_nodes: Array[Node] = []
	
	# 优先在Fruitlayer中查找
	var fruit_layer = get_tree().current_scene.find_child("Fruitlayer", true, false)
	if fruit_layer:
		search_nodes.append(fruit_layer)
	else:
		# 如果没有Fruitlayer，在整个场景中查找
		search_nodes.append(get_tree().current_scene)
	
	# 在指定节点中递归查找bloodcut
	for search_node in search_nodes:
		var found_bloodcut = _find_bloodcut_recursive(search_node, target_position)
		if found_bloodcut:
			return found_bloodcut
	
	return null

## 递归查找bloodcut
func _find_bloodcut_recursive(node: Node, target_position: Vector2) -> Node:
	# 检查当前节点是否是bloodcut（通过名称或类型判断）
	if _is_bloodcut_node(node):
		# 检查位置是否匹配（允许小的误差）
		var node_position = node.global_position
		var distance = node_position.distance_to(target_position)
		print("🍎 [DEBUG] 检查bloodcut位置匹配 - bloodcut:", node_position, " fruit:", target_position, " distance:", distance)
		if distance < 25.0:  # 增加到25像素误差范围
			print("🍎 [DEBUG] 位置匹配成功!")
			return node
	
	# 递归检查子节点
	for child in node.get_children():
		var found_bloodcut = _find_bloodcut_recursive(child, target_position)
		if found_bloodcut:
			return found_bloodcut
	
	return null

## 判断节点是否是bloodcut
func _is_bloodcut_node(node: Node) -> bool:
	# 检查节点名称或场景文件路径
	if "bloodcut" in node.name.to_lower():
		return true
	
	# 检查场景文件路径
	if node.scene_file_path and "bloodcut" in node.scene_file_path.to_lower():
		return true
	
	return false

## 通知SignalBus fruit已被移除
func _notify_signalbus_fruit_removed(fruit_position: Vector2):
	# 只有fruit类型才通知SignalBus
	if object_type != "Fruit":
		return
	
	# 查找SignalBus节点并发出信号
	var signalbus = get_tree().get_first_node_in_group("signalbus")
	if signalbus and signalbus.has_signal("fruit_removed"):
		signalbus.fruit_removed.emit(fruit_position)
		print("🍎 [Pickoff] 已通知SignalBus fruit被移除: ", fruit_position)
	else:
		print("⚠️ [Pickoff] 未找到SignalBus或fruit_removed信号")

# ==================== 鼠标悬停抖动效果 ====================

## 检查鼠标悬停状态
func _check_mouse_hover():
	var mouse_world_pos = _get_mouse_world_position()
	var is_hovering = _is_mouse_in_object_collision(mouse_world_pos)
	
	# 如果悬停状态发生变化
	if is_hovering != is_mouse_hovering:
		is_mouse_hovering = is_hovering
		
		if is_mouse_hovering:
			# 鼠标进入，重置播放标记并播放抖动
			hover_played_this_session = false
			_start_hover_shake()
		else:
			# 鼠标离开，停止抖动
			_stop_hover_shake()

## 开始悬停抖动效果
func _start_hover_shake():
	if not sprite_node or not hover_shake_enabled or hover_played_this_session:
		return
	
	# 标记本次悬停已播放过抖动
	hover_played_this_session = true
	
	# 停止之前的悬停抖动
	if hover_shake_tween:
		hover_shake_tween.kill()
	
	# 创建向下移动动画，并保持在该位置
	hover_shake_tween = create_tween()
	hover_shake_tween.set_ease(Tween.EASE_OUT)
	hover_shake_tween.set_trans(Tween.TRANS_BACK)
	
	# 向下移动到目标位置并停留
	var target_position = original_sprite_position + Vector2(0, hover_shake_intensity)
	hover_shake_tween.tween_property(sprite_node, "position", target_position, hover_shake_duration)

## 停止悬停抖动效果
func _stop_hover_shake():
	if not sprite_node:
		return
	
	# 停止当前的抖动动画
	if hover_shake_tween:
		hover_shake_tween.kill()
	
	# 创建回归原位的动画
	hover_shake_tween = create_tween()
	hover_shake_tween.set_ease(Tween.EASE_OUT)
	hover_shake_tween.set_trans(Tween.TRANS_QUART)
	
	# 从当前位置回到原位
	hover_shake_tween.tween_property(sprite_node, "position", original_sprite_position, hover_shake_duration * 0.3)
	
	# 动画完成后清理tween引用
	hover_shake_tween.tween_callback(func(): hover_shake_tween = null)

# 移除了旧的循环抖动方法，现在使用单次向下抖动
