extends Node2D

## TextDisplay组件
## 负责检测鼠标悬停并显示文本

# 节点引用
@onready var label: Label = $Label

# 父对象引用
var parent_rigidbody: RigidBody2D
var collision_shape: CollisionShape2D
var camera: Camera2D
var pickoff_controller: Node2D  # 新增：控制此textdisplay的pickoff节点

# 状态控制
var is_mouse_hovering: bool = false
var is_parent_picked: bool = false
var is_interaction_disabled: bool = false  # 新增：交互禁用状态

# 打字机效果相关
@export var typing_speed: float = 0.05  # 每个字符的显示间隔（秒）
@export var backspace_speed: float = 0.03  # 每个字符的消失间隔（秒，通常比打字快一点）
var full_text: String = ""  # 完整的文本内容
var current_char_index: int = 0  # 当前显示到的字符索引
var typing_timer: Timer
var is_typing: bool = false  # 正在打字
var is_backspacing: bool = false  # 正在backspace消失

func _ready():
	# 查找父层级的RigidBody2D
	parent_rigidbody = _find_parent_rigidbody()
	if not parent_rigidbody:
		return
	
	# 查找碰撞形状
	collision_shape = _find_collision_shape(parent_rigidbody)
	if not collision_shape:
		return
	
	# 查找Camera2D
	camera = _find_camera2d()
	
	# 查找控制此textdisplay的pickoff节点
	pickoff_controller = _find_pickoff_controller()
	
	# 连接signalbus的交互控制信号
	call_deferred("_connect_interaction_signals")
	
	# 初始隐藏文本
	label.visible = false
	
	# 设置文本样式：固定宽度，允许自动换行
	if label:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 100  # 固定宽度80像素
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	
	# 从SignalBus或pickoff获取初始文本内容
	_update_text_content()
	
	# 创建打字机计时器
	typing_timer = Timer.new()
	typing_timer.wait_time = typing_speed
	typing_timer.timeout.connect(_on_typing_timer_timeout)
	add_child(typing_timer)

func _process(_delta):
	# 检测鼠标悬停（只在对象未被摘取且交互未被禁用时）
	if not is_parent_picked and not is_interaction_disabled and parent_rigidbody and collision_shape:
		_check_mouse_hover()

## 查找父层级中的RigidBody2D节点
func _find_parent_rigidbody() -> RigidBody2D:
	var current_node = get_parent()  # Logic节点
	
	# 向上查找直到找到RigidBody2D
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

## 查找场景中的Camera2D节点
func _find_camera2d() -> Camera2D:
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
		return camera.get_global_mouse_position()
	else:
		return get_global_mouse_position()

## 检测鼠标悬停
func _check_mouse_hover():
	var mouse_world_pos = _get_mouse_world_position()
	var is_hovering = _is_mouse_in_object_collision(mouse_world_pos)
	
	# 检查悬停状态是否改变
	if is_hovering != is_mouse_hovering:
		is_mouse_hovering = is_hovering
		
		if is_mouse_hovering:
			_show_text()
		else:
			_hide_text()

## 检查鼠标位置是否在对象的碰撞区域内
func _is_mouse_in_object_collision(mouse_pos: Vector2) -> bool:
	if not parent_rigidbody or not collision_shape:
		return false
	
	# 将鼠标世界坐标转换为对象的本地坐标
	var local_mouse_pos = parent_rigidbody.to_local(mouse_pos)
	
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
		var distance = local_mouse_pos.length()
		var effective_radius = max(capsule_shape.radius, capsule_shape.height / 2.0)
		return distance <= effective_radius
	
	else:
		return false

## 查找控制此textdisplay的pickoff节点
func _find_pickoff_controller() -> Node2D:
	# 在同级Logic节点下查找pickoff节点
	var logic_parent = get_parent()  # Logic节点
	if logic_parent:
		for child in logic_parent.get_children():
			if child.name == "pickoff":
				return child
	return null

## 连接signalbus的交互控制信号
func _connect_interaction_signals():
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
	# 立即隐藏文本
	_hide_text()

## 响应启用交互信号
func _on_able_pickoff_interaction():
	is_interaction_disabled = false
	# 不自动显示文本，等待鼠标悬停

## 显示文本（开始打字机效果）
func _show_text():
	if label and not is_typing and not is_backspacing and not is_interaction_disabled:
		# 每次显示前都更新文本内容
		_update_text_content()
		_update_text_position()
		label.visible = true
		_start_typing_effect()

## 隐藏文本（开始backspace效果）
func _hide_text():
	if label and label.visible:
		# 如果正在打字，先停止打字，然后开始backspace
		if is_typing:
			_stop_typing_effect()
		_start_backspace_effect()

## 开始打字机效果
func _start_typing_effect():
	if full_text == "" or is_typing or is_backspacing:
		return
	
	# 停止任何进行中的backspace效果
	if is_backspacing:
		_stop_backspace_effect()
	
	is_typing = true
	current_char_index = 0
	label.text = ""
	typing_timer.wait_time = typing_speed
	typing_timer.start()

## 停止打字机效果
func _stop_typing_effect():
	if is_typing:
		is_typing = false
		typing_timer.stop()

## 开始backspace效果
func _start_backspace_effect():
	if is_backspacing or not label.visible:
		return
	
	is_backspacing = true
	# 从当前显示的文本长度开始往回删
	current_char_index = label.text.length()
	typing_timer.wait_time = backspace_speed
	typing_timer.start()

## 停止backspace效果
func _stop_backspace_effect():
	if is_backspacing:
		is_backspacing = false
		typing_timer.stop()
		current_char_index = 0
		label.text = ""
		label.visible = false

## 打字机计时器回调
func _on_typing_timer_timeout():
	if is_typing:
		_handle_typing_step()
	elif is_backspacing:
		_handle_backspace_step()

## 处理打字步骤
func _handle_typing_step():
	if current_char_index >= full_text.length():
		_complete_typing_effect()
		return
	
	# 显示下一个字符
	current_char_index += 1
	label.text = full_text.substr(0, current_char_index)

## 处理backspace步骤
func _handle_backspace_step():
	if current_char_index <= 0:
		_complete_backspace_effect()
		return
	
	# 删除最后一个字符
	current_char_index -= 1
	if current_char_index > 0:
		label.text = full_text.substr(0, current_char_index)
	else:
		label.text = ""

## 完成打字机效果
func _complete_typing_effect():
	is_typing = false
	typing_timer.stop()
	typing_timer.wait_time = typing_speed  # 恢复打字速度
	if label:
		label.text = full_text

## 完成backspace效果
func _complete_backspace_effect():
	is_backspacing = false
	typing_timer.stop()
	typing_timer.wait_time = typing_speed  # 恢复打字速度
	current_char_index = 0
	if label:
		label.text = ""
		label.visible = false

## 更新文本位置
func _update_text_position():
	if not label or not parent_rigidbody:
		return
	
	# 直接设置相对于petal的偏移位置
	# Label会跟随textdisplay节点，而textdisplay在Logic下，Logic在petal下
	label.position = Vector2(10, -15)  # 在对象上方偏左显示

## 从SignalBus或pickoff更新文本内容
func _update_text_content():
	# 优先从pickoff控制器获取文本
	if pickoff_controller and pickoff_controller.has_method("get_display_text"):
		full_text = pickoff_controller.get_display_text()
	else:
		# 降级到从SignalBus获取（保持向后兼容）
		_update_text_from_signalbus()

## 从SignalBus更新文本内容
func _update_text_from_signalbus():
	var signalbus = get_tree().current_scene.find_child("Signalbus", true, false)
	if signalbus and signalbus.has_method("get_current_petal_text"):
		full_text = signalbus.get_current_petal_text()
	else:
		full_text = "yes"  # 默认文本

## 检查父对象是否被摘取（由pickoff调用）
func notify_parent_picked():
	is_parent_picked = true
	_stop_typing_effect()
	_stop_backspace_effect()

## 设置显示文本（供pickoff调用）
func set_display_text(text: String):
	full_text = text
	# 如果当前正在显示且鼠标悬停，重新开始打字机效果
	if label and label.visible and is_mouse_hovering:
		_start_typing_effect()
