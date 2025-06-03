extends Node2D

## Main场景脚本
## 负责场景初始化和petal的圆形实例化

# Petal场景引用
const PETAL_SCENE = preload("res://Scence/petal.tscn")

# Petal实例化参数
@export_group("Petal Generation", "petal_")
@export var petal_count: int = 12  # petal数量
@export var petal_radius: float = 30.0  # 实例化圆形半径
@export var petal_auto_generate: bool = true  # 是否在场景启动时自动生成

# 重要节点引用
var first_point: Node2D
var sub_viewport: SubViewport
var fruits_node: Node2D

# Fruit信号监控
var fruit_monitor_timer: Timer
var connected_fruits: Array[Node] = []  # 已连接信号的fruit列表

# Petal状态跟踪
var petal_positions: Array[Vector2] = []  # 记录所有petal的原始位置
var petal_states: Array[bool] = []  # true=存在, false=已摘除
var petal_nodes: Array[Node] = []  # 记录petal节点引用
var removed_petal_indices: Array[int] = []  # 记录已摘除的petal索引

func _ready():
	print("Main场景初始化")
	
	# 首先查找SubViewport相关节点
	_find_subviewport_nodes()
	
	# 查找First_point节点
	first_point = _find_first_point()
	if not first_point:
		print("警告：未找到First_point节点")
		return
	
	print("找到First_point，位置：", first_point.global_position)
	
	# 如果启用自动生成，则创建petal
	if petal_auto_generate:
		_generate_petals_around_first_point()
	
	# 延迟连接fruit信号（等待可能的fruit生成）
	_start_fruit_signal_monitoring()

## 查找SubViewport和相关节点
func _find_subviewport_nodes():
	var viewport_container = get_node_or_null("SubViewportContainer")
	if viewport_container:
		sub_viewport = viewport_container.get_node_or_null("SubViewport")
		if sub_viewport:
			fruits_node = sub_viewport.get_node_or_null("Fruits")
			print("成功找到SubViewport结构")
			print("  SubViewport: ", sub_viewport)
			print("  Fruits节点: ", fruits_node)
		else:
			print("警告：未找到SubViewport节点")
	else:
		print("警告：未找到SubViewportContainer节点")

## 查找First_point节点（适配SubViewport结构）
func _find_first_point() -> Node2D:
	# 优先在SubViewport结构中查找
	if fruits_node:
		var first_point_node = fruits_node.get_node_or_null("First_Point")
		if first_point_node:
			print("在SubViewport结构中找到First_Point")
			return first_point_node
	
	# 如果SubViewport结构未找到，尝试传统路径
	var fruits_traditional = get_node_or_null("Fruits")
	if fruits_traditional:
		var first_point_node = fruits_traditional.get_node_or_null("First_Point")
		if first_point_node:
			print("在传统结构中找到First_Point")
			return first_point_node
	
	# 最后尝试直接在当前节点下查找
	var direct_first_point = get_node_or_null("First_Point")
	if direct_first_point:
		print("直接找到First_Point")
		return direct_first_point
	
	print("错误：无法在任何位置找到First_Point节点")
	return null

## 在First_point周围圆形实例化petal
func _generate_petals_around_first_point():
	if not first_point:
		print("错误：First_point未找到，无法生成petal")
		return
	
	if petal_count <= 0:
		print("警告：petal_count为0或负数，跳过生成")
		return
	
	print("开始在First_point周围生成 ", petal_count, " 个petal，半径：", petal_radius)
	
	# 初始化跟踪数组
	petal_positions.clear()
	petal_states.clear()
	petal_nodes.clear()
	removed_petal_indices.clear()
	
	var center_pos = first_point.global_position
	
	# 计算每个petal之间的角度间隔
	var angle_step = 2.0 * PI / petal_count
	
	for i in range(petal_count):
		# 计算当前petal的角度（从0开始）
		var angle = i * angle_step
		
		# 计算petal的位置
		var petal_pos = center_pos + Vector2(
			cos(angle) * petal_radius,
			sin(angle) * petal_radius
		)
		
		# 创建petal并连接信号
		var petal = _create_petal_at_position(petal_pos, center_pos, i)
		
		# 记录petal状态
		petal_positions.append(petal_pos)
		petal_states.append(true)  # 初始状态为存在
		petal_nodes.append(petal)
		
		print("生成petal ", i + 1, "/", petal_count, " 位置：", petal_pos, " 索引：", i)

## 在指定位置创建petal
func _create_petal_at_position(petal_pos: Vector2, center_pos: Vector2, petal_index: int) -> Node:
	# 实例化petal
	var petal = PETAL_SCENE.instantiate()
	petal.global_position = petal_pos
	
	# 计算petal的旋转：尾部朝向圆心
	var rotation_angle = _calculate_petal_rotation(petal_pos, center_pos)
	
	# 设置petal的旋转
	_set_petal_rotation(petal, rotation_angle)
	
	# 连接petal的pickoff信号
	_connect_petal_signals(petal, petal_index)
	
	# 确定正确的父节点并添加petal
	_add_petal_to_correct_parent(petal)
	
	return petal

## 将petal添加到正确的父节点
func _add_petal_to_correct_parent(petal: Node):
	# 如果有SubViewport结构，添加到SubViewport下
	if sub_viewport:
		sub_viewport.add_child(petal)
		print("将petal添加到SubViewport")
	else:
		# 否则添加到Main节点下
		add_child(petal)
		print("将petal添加到Main节点")

## 连接petal的pickoff信号
func _connect_petal_signals(petal: Node, petal_index: int):
	# 查找petal的pickoff节点
	var logic_node = petal.get_node_or_null("Logic")
	if logic_node:
		var pickoff_node = logic_node.get_node_or_null("Pick_Off")
		if pickoff_node:
			# 连接petal被摘除的信号 - 使用Callable.bind包装参数
			if pickoff_node.has_signal("object_picked"):
				var callback = func(object_type: String, object_node: Node):
					_on_petal_object_picked_with_index(petal_index, object_type, object_node)
				pickoff_node.object_picked.connect(callback)
				print("连接petal ", petal_index, " 的pickoff信号")

## 计算petal的旋转角度，使尾部朝向圆心
func _calculate_petal_rotation(petal_pos: Vector2, center_pos: Vector2) -> float:
	# 计算从petal位置指向圆心的方向向量
	var direction_to_center = (center_pos - petal_pos).normalized()
	
	# petal的头部朝向正y轴，尾部朝向负y轴
	# 我们希望尾部朝向圆心，即负y轴指向direction_to_center
	# 这意味着正y轴应该指向direction_to_center的反方向
	var desired_head_direction = -direction_to_center
	
	# 计算从默认方向（正y轴，即Vector2.UP）到desired_head_direction的旋转角度
	var rotation_angle = desired_head_direction.angle() - Vector2.UP.angle()
	
	return rotation_angle

## 设置petal的旋转
func _set_petal_rotation(petal: Node, rotation_angle: float):
	# 查找petal的Sprite2D节点并设置旋转
	var sprite = petal.get_node_or_null("Sprite2D")
	if sprite:
		sprite.rotation = rotation_angle
		print("设置petal Sprite2D旋转：", rad_to_deg(rotation_angle), "度")
	else:
		print("警告：未找到petal的Sprite2D节点")

## 当petal对象被摘除时的回调（包含petal索引）
func _on_petal_object_picked_with_index(petal_index: int, object_type: String, object_node: Node):
	# 只处理petal类型的对象
	if object_type == "Petal" and petal_index < petal_states.size() and petal_states[petal_index]:
		print("Petal ", petal_index, " 被摘除，添加到重新生成列表")
		petal_states[petal_index] = false
		removed_petal_indices.append(petal_index)
		
		# 清空节点引用（节点会被pickoff脚本处理）
		if petal_index < petal_nodes.size():
			petal_nodes[petal_index] = null
		
		print("当前已摘除的petal索引：", removed_petal_indices)

## 当任何对象被摘除时的回调
func _on_object_picked(object_type: String, object_node: Node):
	print("通用对象被摘除：", object_type)

## 当petal被摘除时的回调（旧函数，保留以防需要）
func _on_petal_picked(petal_index: int):
	if petal_index < petal_states.size() and petal_states[petal_index]:
		print("Petal ", petal_index, " 被摘除")
		petal_states[petal_index] = false
		removed_petal_indices.append(petal_index)
		
		# 清空节点引用（节点会被pickoff脚本处理）
		if petal_index < petal_nodes.size():
			petal_nodes[petal_index] = null

## 接收fruit摘除信号的回调
func _on_fruit_picked():
	print("收到fruit摘除信号，准备重新生成petal")
	
	# 检查是否有已摘除的petal
	if removed_petal_indices.size() == 0:
		print("没有已摘除的petal可以重新生成")
		return
	
	# 随机选择一个已摘除的petal位置
	var random_index = randi() % removed_petal_indices.size()
	var petal_index = removed_petal_indices[random_index]
	var regenerate_pos = petal_positions[petal_index]
	
	print("随机选择在位置 ", petal_index, " (", regenerate_pos, ") 重新生成petal")
	
	# 在该位置重新生成petal
	_regenerate_petal_at_index(petal_index)

## 在指定索引位置重新生成petal
func _regenerate_petal_at_index(petal_index: int):
	if petal_index >= petal_positions.size():
		print("错误：petal索引超出范围")
		return
	
	var petal_pos = petal_positions[petal_index]
	var center_pos = first_point.global_position
	
	# 创建新的petal
	var new_petal = _create_petal_at_position(petal_pos, center_pos, petal_index)
	
	# 更新状态
	petal_states[petal_index] = true
	petal_nodes[petal_index] = new_petal
	
	# 从已摘除列表中移除
	removed_petal_indices.erase(petal_index)
	
	print("在索引 ", petal_index, " 成功重新生成petal")

## 连接所有fruit的信号（适配SubViewport结构）
func _connect_fruit_signals():
	# 首先在SubViewport结构中查找fruit
	if sub_viewport:
		var all_nodes = _get_all_nodes_in_subviewport()
		for node in all_nodes:
			if node.scene_file_path.ends_with("fruit.tscn"):
				_connect_fruit_pickoff_signal(node)
	
	# 也检查传统结构（如果有的话）
	var all_nodes = _get_all_nodes_in_scene()
	for node in all_nodes:
		if node.scene_file_path.ends_with("fruit.tscn"):
			_connect_fruit_pickoff_signal(node)

## 递归获取SubViewport中所有节点
func _get_all_nodes_in_subviewport(node: Node = null) -> Array[Node]:
	if node == null:
		node = sub_viewport if sub_viewport else get_tree().current_scene
	
	var all_nodes: Array[Node] = [node]
	for child in node.get_children():
		all_nodes.append_array(_get_all_nodes_in_subviewport(child))
	
	return all_nodes

## 递归获取场景中所有节点
func _get_all_nodes_in_scene(node: Node = null) -> Array[Node]:
	if node == null:
		node = get_tree().current_scene
	
	var all_nodes: Array[Node] = [node]
	for child in node.get_children():
		all_nodes.append_array(_get_all_nodes_in_scene(child))
	
	return all_nodes

## 连接单个fruit的pickoff信号
func _connect_fruit_pickoff_signal(fruit_node: Node):
	var logic_node = fruit_node.get_node_or_null("Logic")
	if logic_node:
		var pickoff_node = logic_node.get_node_or_null("pickoff")
		if pickoff_node and pickoff_node.has_signal("fruit_picked"):
			if not pickoff_node.fruit_picked.is_connected(_on_fruit_picked):
				pickoff_node.fruit_picked.connect(_on_fruit_picked)
				print("成功连接fruit的pickoff信号：", fruit_node.name)
		else:
			print("未找到fruit的pickoff节点或信号：", fruit_node.name)

## 手动连接fruit信号（在fruit生成后调用）
func connect_new_fruit_signals():
	_connect_fruit_signals()

## 手动触发petal生成（可用于调试或重新生成）
func regenerate_petals():
	# 删除现有的petal
	_clear_existing_petals()
	
	# 重新生成
	_generate_petals_around_first_point()

## 清除现有的petal（适配SubViewport结构）
func _clear_existing_petals():
	# 在SubViewport中查找并删除petal
	if sub_viewport:
		for child in sub_viewport.get_children():
			if child.name.begins_with("Petal") or child.scene_file_path.ends_with("petal.tscn"):
				child.queue_free()
				print("删除SubViewport中的petal：", child.name)
	
	# 也在Main节点中查找并删除petal（兼容性）
	for child in get_children():
		if child.name.begins_with("Petal") or child.scene_file_path.ends_with("petal.tscn"):
			child.queue_free()
			print("删除Main节点中的petal：", child.name)
	
	# 清空跟踪数组
	petal_positions.clear()
	petal_states.clear()
	petal_nodes.clear()
	removed_petal_indices.clear()

## 输入处理（用于调试）
func _input(event):
	# 按P键重新生成petal
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_P:
			print("手动重新生成petal")
			regenerate_petals()

## 设置petal生成参数
func set_petal_parameters(count: int, radius: float):
	petal_count = count
	petal_radius = radius
	print("更新petal参数 - 数量：", count, " 半径：", radius)

## 获取当前petal参数
func get_petal_parameters() -> Dictionary:
	return {
		"count": petal_count,
		"radius": petal_radius,
		"auto_generate": petal_auto_generate
	}

## 获取petal状态信息（用于调试）
func get_petal_status() -> Dictionary:
	var active_count = 0
	var removed_count = 0
	
	for state in petal_states:
		if state:
			active_count += 1
		else:
			removed_count += 1
	
	return {
		"total": petal_positions.size(),
		"active": active_count,
		"removed": removed_count,
		"removed_indices": removed_petal_indices
	}

## 添加定期检查新fruit的逻辑
func _start_fruit_signal_monitoring():
	# 创建定时器
	fruit_monitor_timer = Timer.new()
	fruit_monitor_timer.wait_time = 1.0  # 每秒检查一次
	fruit_monitor_timer.timeout.connect(_check_for_new_fruits)
	fruit_monitor_timer.autostart = true
	add_child(fruit_monitor_timer)
	
	print("启动fruit信号监控，每", fruit_monitor_timer.wait_time, "秒检查一次")
	
	# 立即执行一次检查
	_check_for_new_fruits()

## 检查并连接新生成的fruit
func _check_for_new_fruits():
	var current_fruits = _find_all_fruits()
	
	for fruit in current_fruits:
		if fruit not in connected_fruits:
			_connect_fruit_pickoff_signal(fruit)
			connected_fruits.append(fruit)

## 查找场景中所有的fruit节点（适配SubViewport结构）
func _find_all_fruits() -> Array[Node]:
	var fruits: Array[Node] = []
	
	# 在SubViewport中查找
	if sub_viewport:
		var subviewport_nodes = _get_all_nodes_in_subviewport()
		for node in subviewport_nodes:
			if node.scene_file_path.ends_with("fruit.tscn") or "fruit" in node.name.to_lower():
				fruits.append(node)
	
	# 也在主场景中查找（兼容性）
	var main_nodes = _get_all_nodes_in_scene()
	for node in main_nodes:
		if node.scene_file_path.ends_with("fruit.tscn") or "fruit" in node.name.to_lower():
			fruits.append(node)
	
	return fruits
