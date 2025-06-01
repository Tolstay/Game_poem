extends Node2D

## Fruits控制器
## 负责管理所有生成点的坐标与状态，控制生成器的交互

# 点状态枚举
enum PointStatus {
	AVAILABLE,    # 可生成状态（紫色）
	EXHAUSTED,    # 已耗尽状态（红色）
	PATH_TRUNK,   # 路过节点：剩余次数1但无合法路径（黄色）
	END_TRUNK,    # 终点节点：剩余次数2但无合法路径（绿色）
	END_BRANCH    # branch终点节点：不可生成（绿色）
}

# 点类型枚举
enum PointType {
	TRUNK_POINT,      # trunk点
	BRANCH_POINT      # branch点
}

# 状态颜色定义
const STATUS_COLORS = {
	PointStatus.AVAILABLE: Color(0.6, 0.2, 0.8, 1.0),  # 紫色
	PointStatus.EXHAUSTED: Color(0.8, 0.2, 0.2, 1.0),  # 红色
	PointStatus.PATH_TRUNK: Color(1.0, 1.0, 0.0, 1.0), # 黄色
	PointStatus.END_TRUNK: Color(0.2, 0.8, 0.2, 1.0),  # 绿色
	PointStatus.END_BRANCH: Color(0.2, 0.8, 0.2, 1.0)  # 绿色
}

# 生成点坐标记录
var point_positions: Array[Vector2] = []
var point_states: Array[int] = []  # 记录剩余生成次数，0=已耗尽，>0=可用次数
var point_directions: Array[Vector2] = []  # 记录每个点的生长方向
var point_generated_branches: Array[Array] = []  # 记录每个点已生成的分支方向
var point_status: Array[PointStatus] = []  # 记录每个点的当前状态
var point_nodes: Array[Node2D] = []  # 直接引用每个trunk点节点
var point_types: Array[PointType] = []  # 记录每个点的类型
var point_parent_segments: Array[int] = []  # branch_point所属的线段索引（trunk_point为-1）

# 线段信息记录
var trunk_segments: Array[Dictionary] = []
# 每个Dictionary包含：
# {
#   "start_point_index": int,     # 起点在point_positions中的索引
#   "end_point_index": int,       # 终点在point_positions中的索引
#   "length": float,              # 线段长度
#   "max_branch_points": int,     # 最大branch_point数量
#   "current_branch_count": int,  # 当前已生成的branch_point数量
#   "branch_point_indices": Array[int]  # 该线段上的branch_point索引
# }

# 可视化标签节点
var segment_labels: Array[Label] = []

# 生成器引用
var generator: Node2D

# 生成参数
@export var max_generations_per_point: int = 2  # 每个生成点的最大生成次数
@export var min_branch_points_per_segment: int = 1       # 每线段最少branch_point数（物理约束的最小值）
@export var max_branch_points_per_segment: int = 4       # 每线段最多branch_point数（物理约束的最大值）

# Branch生成参数
@export var branch_position_min: float = 0.1  # branch_point在线段上的最小位置（0.0-1.0）
@export var branch_position_max: float = 0.9  # branch_point在线段上的最大位置（0.0-1.0）
@export var branch_collision_radius: float = 15.0  # branch_point的碰撞半径（决定实际可容纳数量）

# Branch角度控制参数
@export var branch_min_angle_degrees: float = 30.0  # branch相对trunk的最小角度（度）
@export var branch_max_angle_degrees: float = 80.0  # branch相对trunk的最大角度（度）

# Branch长度参数
@export var branch_min_length: float = 30.0  # branch的最小长度
@export var branch_max_length: float = 60.0  # branch的最大长度

# 记录本轮参与生成的点
var points_used_this_round: Array[int] = []

# 生成点场景
const BRANCH_POINT_SCENE = preload("res://Scence/branch_point.tscn")

func _ready():
	# 获取生成器引用
	generator = $BranchGenerator
	# 记录初始生成点
	_record_initial_points()
	# 设置初始颜色
	update_all_point_colors()

func _input(_event):
	# 响应generate输入映射
	if Input.is_action_just_pressed("generate"):
		_execute_generation()
	# 响应branch_generate输入映射（完整branch生成：点位+线段）
	elif Input.is_action_just_pressed("branch_generate"):
		_execute_complete_branch_generation()
	# 响应branch_point_generate输入映射（独立生成branch_point，保留用于精细控制）
	elif Input.is_action_just_pressed("branch_point_generate"):
		_execute_branch_point_generation()

## 记录所有生成点的坐标和状态
func _record_initial_points():
	# 遍历子节点，找到所有生成点
	for child in get_children():
		if "Point" in child.name:
			point_positions.append(child.global_position)
			point_states.append(max_generations_per_point)  # 初始生成次数
			point_directions.append(Vector2.ZERO)  # 初始点没有方向
			point_generated_branches.append([])  # 初始化空的分支记录
			point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
			point_nodes.append(child)  # 记录节点引用
			point_types.append(PointType.TRUNK_POINT)  # 初始点都是trunk点
			point_parent_segments.append(-1)  # trunk点不属于任何线段
			print("记录生成点: ", child.name, " 位置: ", child.global_position, " 剩余次数: ", max_generations_per_point)

## 执行trunk生成操作
func _execute_generation():
	print("执行trunk生成操作")
	# 检查是否有可用的生成点
	if get_available_points_count() == 0:
		print("没有可用的生成点")
		return
	
	# 清空本轮使用记录
	points_used_this_round.clear()
	
	# 调用生成器的生成方法
	_call_generator_generate()
	
	# 生成完成后，减少参与生成的点的剩余次数
	_decrease_generation_counts()

## 执行完整的branch生成操作（点位生成 + branch线段生成）
func _execute_complete_branch_generation():
	print("执行完整branch生成操作")
	
	# 第一步：检查是否有可用的trunk线段
	if not _has_available_trunk_segments():
		print("没有可用的trunk线段用于生成branch")
		return
	
	var available_segments = _get_available_trunk_segments()
	if available_segments.size() == 0:
		print("没有找到可用的trunk线段")
		return
	
	# 第二步：尝试生成branch_point
	var new_branch_point_index = _try_generate_branch_point_anywhere(available_segments)
	if new_branch_point_index == -1:
		print("无法生成branch_point")
		return
	
	# 第三步：立即从新生成的branch_point生成branch线段
	if generator and generator.has_method("generate_branch_from_specific_point"):
		generator.generate_branch_from_specific_point(new_branch_point_index)
		print("完整branch生成成功：从点位 ", new_branch_point_index, " 生成了完整的branch")
	else:
		print("生成器不支持指定点位的branch生成")

## 执行branch_point生成操作
func _execute_branch_point_generation():
	print("执行branch_point生成操作")
	# 检查是否有可用的trunk线段
	if not _has_available_trunk_segments():
		print("没有可用的trunk线段用于生成branch_point")
		return
	
	# 获取所有可用的trunk线段
	var available_segments = _get_available_trunk_segments()
	if available_segments.size() == 0:
		print("没有找到可用的trunk线段")
		return
	
	# 尝试在可用线段上生成branch_point，直到成功为止
	var generation_successful = false
	var attempts = 0
	var max_attempts = available_segments.size() * 3  # 每个线段最多尝试3次
	
	while not generation_successful and attempts < max_attempts:
		# 随机选择一个可用的trunk线段
		var random_segment_index = available_segments[randi() % available_segments.size()]
		
		# 尝试在该线段上生成branch_point
		if _try_generate_branch_point_on_segment(random_segment_index):
			generation_successful = true
			print("成功在线段 ", random_segment_index, " 上生成branch_point")
		else:
			print("在线段 ", random_segment_index, " 上生成失败，尝试下一个线段")
			attempts += 1
	
	if not generation_successful:
		print("警告：尝试了 ", max_attempts, " 次仍无法生成branch_point")

## 获取所有可用的branch_point索引
func _get_available_branch_points() -> Array[int]:
	var available_points: Array[int] = []
	for i in range(point_positions.size()):
		if point_types[i] == PointType.BRANCH_POINT and point_states[i] > 0:
			available_points.append(i)
	return available_points

## 从指定的branch_point生成branch线段
func _generate_branch_from_point(branch_point_index: int):
	if branch_point_index >= point_positions.size():
		print("错误：branch_point索引超出范围")
		return
	
	var branch_start_pos = point_positions[branch_point_index]
	var parent_segment_index = point_parent_segments[branch_point_index]
	
	# 计算trunk的方向
	var trunk_direction = _calculate_trunk_direction(parent_segment_index)
	if trunk_direction == Vector2.ZERO:
		print("无法计算trunk方向")
		return
	
	# 尝试生成branch线段
	var max_attempts = 20
	for attempt in range(max_attempts):
		# 生成随机的branch方向和长度
		var branch_direction = _generate_branch_direction(trunk_direction)
		var branch_length = randf_range(branch_min_length, branch_max_length)
		var branch_end_pos = branch_start_pos + branch_direction * branch_length
		
		# 检查碰撞
		if not _check_branch_line_collision(branch_start_pos, branch_end_pos):
			# 没有碰撞，创建完整的branch
			_create_complete_branch(branch_point_index, branch_start_pos, branch_end_pos, branch_direction)
			return
		else:
			print("Branch生成尝试 ", attempt + 1, " 发生碰撞，重新尝试")
	
	print("无法为branch_point ", branch_point_index, " 找到有效的branch生成位置")

## 计算trunk的生长方向
func _calculate_trunk_direction(segment_index: int) -> Vector2:
	if segment_index < 0 or segment_index >= trunk_segments.size():
		print("错误：无效的trunk线段索引")
		return Vector2.ZERO
	
	var segment = trunk_segments[segment_index]
	var start_pos = point_positions[segment.start_point_index]
	var end_pos = point_positions[segment.end_point_index]
	
	return (end_pos - start_pos).normalized()

## 基于trunk方向生成branch方向
func _generate_branch_direction(trunk_direction: Vector2) -> Vector2:
	var trunk_angle = trunk_direction.angle()
	
	# 随机选择左转或右转
	var turn_left = randf() > 0.5
	
	# 生成随机角度偏移
	var min_angle_rad = deg_to_rad(branch_min_angle_degrees)
	var max_angle_rad = deg_to_rad(branch_max_angle_degrees)
	var angle_offset = randf_range(min_angle_rad, max_angle_rad)
	
	# 计算新角度
	var new_angle = trunk_angle + (angle_offset if turn_left else -angle_offset)
	
	return Vector2(cos(new_angle), sin(new_angle))

## 检查branch线段是否与现有对象碰撞
func _check_branch_line_collision(start_pos: Vector2, end_pos: Vector2) -> bool:
	# 检查与已有点的碰撞
	if _check_branch_point_collision(end_pos):
		return true
	
	# 检查与已有线段的交叉（需要访问generator的线段数据）
	if generator and generator.has_method("_check_line_intersection"):
		if generator._check_line_intersection(start_pos, end_pos):
			return true
	
	return false

## 创建完整的branch（线段 + 终点）
func _create_complete_branch(start_point_index: int, start_pos: Vector2, end_pos: Vector2, direction: Vector2):
	# 标记起点branch_point为已使用
	point_states[start_point_index] = 0
	point_status[start_point_index] = PointStatus.EXHAUSTED
	_update_point_color(start_point_index)
	
	# 创建branch线段（通过generator）
	if generator and generator.has_method("_create_branch_line"):
		generator._create_branch_line(start_pos, end_pos)
		
		# 记录线段到generator的existing_lines中
		if generator.has_method("_record_branch_line"):
			generator._record_branch_line(start_pos, end_pos)
	
	# 创建终点branch_point
	var end_branch_point = BRANCH_POINT_SCENE.instantiate()
	end_branch_point.global_position = end_pos
	add_child(end_branch_point)
	
	# 添加终点到管理系统
	var end_point_index = point_positions.size()
	point_positions.append(end_pos)
	point_states.append(0)  # 终点没有生成次数
	point_directions.append(direction)
	point_generated_branches.append([])
	point_status.append(PointStatus.END_BRANCH)  # 设置为END_BRANCH状态
	point_nodes.append(end_branch_point)
	point_types.append(PointType.BRANCH_POINT)
	point_parent_segments.append(-1)  # 终点不属于任何trunk线段
	
	# 立即更新终点颜色
	_update_point_color(end_point_index)
	
	print("成功生成branch：从点 ", start_point_index, " 到点 ", end_point_index)
	print("Branch方向: ", direction, " 长度: ", start_pos.distance_to(end_pos))

## 检查branch_point位置是否与已有点碰撞
func _check_branch_point_collision(new_pos: Vector2) -> bool:
	for pos in point_positions:
		if (pos - new_pos).length() < branch_collision_radius:
			return true
	return false

## 减少参与生成的点的剩余次数
func _decrease_generation_counts():
	for point_index in points_used_this_round:
		if point_index < point_states.size() and point_states[point_index] > 0:
			point_states[point_index] -= 1
			print("生成点 ", point_index, " 剩余生成次数: ", point_states[point_index])
			if point_states[point_index] == 0:
				print("生成点 ", point_index, " 已耗尽所有生成次数")
				point_status[point_index] = PointStatus.EXHAUSTED

## 调用生成器的生成方法
func _call_generator_generate():
	if generator and generator.has_method("generate"):
		generator.generate()
	else:
		print("生成器未找到或没有generate方法")

## 标记生成点已使用（减少剩余次数）
func _mark_point_used(point_index: int):
	if point_index < point_states.size():
		point_states[point_index] -= 1
		print("生成点 ", point_index, " 剩余生成次数: ", point_states[point_index])
		
		if point_states[point_index] == 0:
			print("生成点 ", point_index, " 已耗尽所有生成次数")
			point_status[point_index] = PointStatus.EXHAUSTED
		
		# 立即更新该点的颜色
		_update_point_color(point_index)

## 记录某个点生成了新分支（由生成器调用）
func _record_generated_branch(point_index: int, branch_direction: Vector2):
	if point_index < point_generated_branches.size():
		point_generated_branches[point_index].append(branch_direction.normalized())
		print("记录生成点 ", point_index, " 的新分支方向: ", branch_direction.normalized())

## 获取某个点已生成的分支方向
func get_point_generated_branches(point_index: int) -> Array:
	if point_index < point_generated_branches.size():
		return point_generated_branches[point_index]
	return []

## 添加新的生成点（由生成器调用）
func _add_new_point(pos: Vector2, direction: Vector2 = Vector2.ZERO, node: Node2D = null):
	var new_point_index = point_positions.size()
	point_positions.append(pos)
	point_states.append(max_generations_per_point)  # 新生成的点有完整的生成次数
	point_directions.append(direction.normalized())  # 记录生长方向
	point_generated_branches.append([])  # 初始化空的分支记录
	point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
	point_nodes.append(node)  # 记录节点引用
	point_types.append(PointType.TRUNK_POINT)  # 新生成的点都是trunk点
	point_parent_segments.append(-1)  # trunk点不属于任何线段
	print("添加新生成点: ", pos, " 方向: ", direction, " 剩余次数: ", max_generations_per_point)
	return new_point_index

## 记录新的trunk线段（由生成器调用）
func _record_trunk_segment(start_point_index: int, end_point_index: int):
	if start_point_index >= point_positions.size() or end_point_index >= point_positions.size():
		print("错误：线段端点索引超出范围")
		return
	
	var start_pos = point_positions[start_point_index]
	var end_pos = point_positions[end_point_index]
	var segment_length = start_pos.distance_to(end_pos)
	
	# 根据长度计算最大branch_point数量
	var max_branch_points = _calculate_max_branch_points(segment_length)
	
	var segment_data = {
		"start_point_index": start_point_index,
		"end_point_index": end_point_index,
		"length": segment_length,
		"max_branch_points": max_branch_points,
		"current_branch_count": 0,
		"branch_point_indices": []
	}
	
	trunk_segments.append(segment_data)
	var segment_index = trunk_segments.size() - 1
	
	print("记录trunk线段 ", segment_index, ": 从点", start_point_index, "到点", end_point_index, 
		  " 长度:", segment_length, " 最大branch数:", max_branch_points)
	
	# 创建可视化标签
	_create_segment_label(segment_index, start_pos, end_pos, max_branch_points)

## 根据线段长度计算最大branch_point数量
func _calculate_max_branch_points(segment_length: float) -> int:
	# 使用物理约束计算实际可容纳的branch_point数量
	# 每个branch_point需要的空间 = collision_radius * 2（直径）
	var space_per_branch = branch_collision_radius * 2.0
	
	# 线段可用长度 = 总长度 - 两端的安全距离
	var safety_margin = branch_collision_radius  # 两端各留一个半径的安全距离
	var usable_length = segment_length - (safety_margin * 2.0)
	
	# 计算实际可容纳的数量
	var calculated = int(usable_length / space_per_branch)
	
	# 应用最小值和最大值限制
	var result = clamp(calculated, min_branch_points_per_segment, max_branch_points_per_segment)
	
	print("线段长度: ", segment_length, " 可用长度: ", usable_length, " 每branch空间: ", space_per_branch, " 计算结果: ", calculated, " 最终结果: ", result)
	
	return result

## 创建线段的可视化标签
func _create_segment_label(segment_index: int, start_pos: Vector2, end_pos: Vector2, max_branch_points: int):
	var label = Label.new()
	label.text = str(max_branch_points)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	
	# 设置标签位置为线段中点
	var mid_pos = (start_pos + end_pos) / 2
	label.global_position = mid_pos - Vector2(8, 8)  # 稍微偏移以居中显示
	
	add_child(label)
	segment_labels.append(label)
	
	print("创建线段标签 ", segment_index, " 位置: ", mid_pos, " 显示: ", max_branch_points)

## 更新线段标签显示
func _update_segment_label(segment_index: int):
	if segment_index >= segment_labels.size() or segment_index >= trunk_segments.size():
		return
	
	var segment = trunk_segments[segment_index]
	var remaining = segment.max_branch_points - segment.current_branch_count
	var label = segment_labels[segment_index]
	
	if label and is_instance_valid(label):
		label.text = str(remaining)
		# 根据剩余数量改变颜色
		if remaining <= 0:
			label.add_theme_color_override("font_color", Color.RED)
		elif remaining <= 1:
			label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			label.add_theme_color_override("font_color", Color.WHITE)

## 获取当前可用的生成点数量
func get_available_points_count() -> int:
	var count = 0
	for state in point_states:
		if state > 0:
			count += 1
	return count

## 获取生成点的详细状态信息
func get_points_status():
	print("=== 生成点状态 ===")
	for i in range(point_positions.size()):
		var status = "可用" if point_states[i] > 0 else "已耗尽"
		var type_name = "TRUNK" if point_types[i] == PointType.TRUNK_POINT else "BRANCH"
		var branch_count = point_generated_branches[i].size() if i < point_generated_branches.size() else 0
		print("点 ", i, ": 类型 ", type_name, " 位置 ", point_positions[i], " 剩余次数 ", point_states[i], " 状态 ", status, " 已生成分支数: ", branch_count)

## 设置点为无空间状态
func set_point_no_space(point_index: int):
	if point_index < point_status.size():
		# 根据剩余次数决定无空间状态的类型
		if point_states[point_index] == 1:
			# 剩余次数为1且无合法路径 -> 黄色（路过节点）
			point_status[point_index] = PointStatus.PATH_TRUNK
			print("生成点 ", point_index, " 设置为路过节点状态（黄色），剩余次数: ", point_states[point_index])
		elif point_states[point_index] == 2:
			# 剩余次数为2且无合法路径 -> 绿色（终点节点）
			point_status[point_index] = PointStatus.END_TRUNK
			print("生成点 ", point_index, " 设置为终点节点状态（绿色），剩余次数: ", point_states[point_index])
		else:
			# 其他情况（剩余次数0或其他值）保持原有逻辑
			if point_states[point_index] <= 0:
				point_status[point_index] = PointStatus.EXHAUSTED
				print("生成点 ", point_index, " 设置为已耗尽状态（红色），剩余次数: ", point_states[point_index])
		_update_point_color(point_index)

## 更新所有点的颜色显示
func update_all_point_colors():
	for i in range(point_positions.size()):
		_update_point_color(i)

## 更新单个点的颜色
func _update_point_color(point_index: int):
	if point_index >= point_status.size() or point_index >= point_nodes.size():
		return
	
	# 根据剩余次数更新状态（除非已经是特殊状态）
	if point_status[point_index] != PointStatus.END_TRUNK and point_status[point_index] != PointStatus.PATH_TRUNK and point_status[point_index] != PointStatus.END_BRANCH:
		if point_states[point_index] <= 0:
			point_status[point_index] = PointStatus.EXHAUSTED
		else:
			point_status[point_index] = PointStatus.AVAILABLE
	
	# 直接使用节点引用更新颜色
	var point_node = point_nodes[point_index]
	if point_node and is_instance_valid(point_node):
		var status_polygon = null
		
		# 根据点类型选择正确的状态多边形节点
		if point_types[point_index] == PointType.TRUNK_POINT:
			status_polygon = point_node.get_node_or_null("Trunk_Status")
		elif point_types[point_index] == PointType.BRANCH_POINT:
			status_polygon = point_node.get_node_or_null("Branch_Status")
		
		if status_polygon and status_polygon is Polygon2D:
			var status = point_status[point_index]
			status_polygon.color = STATUS_COLORS[status]
			print("更新点 ", point_index, " (", "TRUNK" if point_types[point_index] == PointType.TRUNK_POINT else "BRANCH", ") 颜色为: ", STATUS_COLORS[status], " 状态: ", status)
		else:
			var node_type = "Trunk_Status" if point_types[point_index] == PointType.TRUNK_POINT else "Branch_Status"
			print("警告：点 ", point_index, " 的", node_type, "节点未找到或类型不正确")

## 获取所有trunk点节点（按添加顺序）
func _get_trunk_point_nodes() -> Array:
	var trunk_nodes = []
	for child in get_children():
		if "Point" in child.name or child.name.begins_with("Trunk_Point"):
			trunk_nodes.append(child)
	return trunk_nodes

## 执行生成后的清理工作
func _post_generation_cleanup():
	# 清空本轮使用记录
	points_used_this_round.clear()
	
	# 输出当前所有点的状态
	print("=== 当前所有生成点状态 ===")
	for i in range(point_positions.size()):
		var status_name = ""
		match point_status[i]:
			PointStatus.AVAILABLE: status_name = "可用"
			PointStatus.EXHAUSTED: status_name = "已耗尽"
			PointStatus.PATH_TRUNK: status_name = "路过节点"
			PointStatus.END_TRUNK: status_name = "终点节点"
		var type_name = "TRUNK" if point_types[i] == PointType.TRUNK_POINT else "BRANCH"
		var branch_count = point_generated_branches[i].size() if i < point_generated_branches.size() else 0
		print("点 ", i, ": 类型 ", type_name, " 位置 ", point_positions[i], " 剩余次数 ", point_states[i], " 状态 ", status_name, " 已生成分支数: ", branch_count)

## 检查是否有可用的trunk线段
func _has_available_trunk_segments() -> bool:
	for segment in trunk_segments:
		if segment.current_branch_count < segment.max_branch_points:
			return true
	return false

## 获取所有可用的trunk线段索引
func _get_available_trunk_segments() -> Array[int]:
	var available_segments: Array[int] = []
	for i in range(trunk_segments.size()):
		var segment = trunk_segments[i]
		if segment.current_branch_count < segment.max_branch_points:
			available_segments.append(i)
	return available_segments

## 尝试在指定线段上生成branch_point（返回是否成功）
func _try_generate_branch_point_on_segment(segment_index: int) -> bool:
	if segment_index >= trunk_segments.size():
		print("错误：线段索引超出范围")
		return false
	
	var segment = trunk_segments[segment_index]
	
	# 检查线段是否还有可用生成次数
	if segment.current_branch_count >= segment.max_branch_points:
		print("线段 ", segment_index, " 已达到最大branch数量")
		return false
	
	var start_pos = point_positions[segment.start_point_index]
	var end_pos = point_positions[segment.end_point_index]
	
	# 在该线段上尝试多个位置
	var position_attempts = 10
	for attempt in range(position_attempts):
		# 使用参数化的位置范围
		var t = randf_range(branch_position_min, branch_position_max)
		var branch_pos = start_pos.lerp(end_pos, t)
		
		# 检查新位置是否与已有点距离过近
		if not _check_branch_point_collision(branch_pos):
			# 位置有效，创建branch_point
			_create_branch_point_at_position(branch_pos, segment_index, t)
			return true
	
	print("在线段 ", segment_index, " 上尝试了 ", position_attempts, " 个位置都发生碰撞")
	return false

## 在指定位置创建branch_point
func _create_branch_point_at_position(branch_pos: Vector2, segment_index: int, t_value: float):
	# 创建branch_point实例
	var branch_point = BRANCH_POINT_SCENE.instantiate()
	branch_point.global_position = branch_pos
	add_child(branch_point)
	
	# 添加到点位管理系统
	var branch_point_index = _add_branch_point(branch_pos, segment_index, branch_point)
	
	# 更新线段的branch计数
	trunk_segments[segment_index].current_branch_count += 1
	trunk_segments[segment_index].branch_point_indices.append(branch_point_index)
	
	# 更新可视化标签
	_update_segment_label(segment_index)
	
	print("在线段 ", segment_index, " 上生成branch_point，位置: ", branch_pos, " 参数t: ", t_value)
	print("线段当前branch数: ", trunk_segments[segment_index].current_branch_count, "/", trunk_segments[segment_index].max_branch_points)

## 添加新的branch_point到管理系统
func _add_branch_point(pos: Vector2, parent_segment_index: int, node: Node2D) -> int:
	var branch_point_index = point_positions.size()
	point_positions.append(pos)
	point_states.append(1)  # branch_point只有1次生成机会
	point_directions.append(Vector2.ZERO)  # branch_point初始没有方向
	point_generated_branches.append([])  # 初始化空的分支记录
	point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
	point_nodes.append(node)  # 记录节点引用
	point_types.append(PointType.BRANCH_POINT)  # 标记为branch点
	point_parent_segments.append(parent_segment_index)  # 记录所属线段
	
	# 立即更新branch_point的颜色
	_update_point_color(branch_point_index)
	
	print("添加新branch_point: ", pos, " 所属线段: ", parent_segment_index, " 剩余次数: 1")
	return branch_point_index

## 在任意可用线段上尝试生成branch_point（返回新点索引）
func _try_generate_branch_point_anywhere(available_segments: Array[int]) -> int:
	var max_attempts = available_segments.size() * 3
	var attempts = 0
	
	while attempts < max_attempts:
		var random_segment_index = available_segments[randi() % available_segments.size()]
		
		var new_point_index = _try_generate_branch_point_on_segment_return_index(random_segment_index)
		if new_point_index != -1:
			print("成功在线段 ", random_segment_index, " 上生成branch_point，索引：", new_point_index)
			return new_point_index
		
		attempts += 1
	
	print("警告：尝试了 ", max_attempts, " 次仍无法生成branch_point")
	return -1

## 尝试在指定线段上生成branch_point并返回索引（返回新点索引或-1）
func _try_generate_branch_point_on_segment_return_index(segment_index: int) -> int:
	if segment_index >= trunk_segments.size():
		print("错误：线段索引超出范围")
		return -1
	
	var segment = trunk_segments[segment_index]
	
	# 检查线段是否还有可用生成次数
	if segment.current_branch_count >= segment.max_branch_points:
		print("线段 ", segment_index, " 已达到最大branch数量")
		return -1
	
	var start_pos = point_positions[segment.start_point_index]
	var end_pos = point_positions[segment.end_point_index]
	
	# 在该线段上尝试多个位置
	var position_attempts = 10
	for attempt in range(position_attempts):
		# 使用参数化的位置范围
		var t = randf_range(branch_position_min, branch_position_max)
		var branch_pos = start_pos.lerp(end_pos, t)
		
		# 检查新位置是否与已有点距离过近
		if not _check_branch_point_collision(branch_pos):
			# 位置有效，创建branch_point并返回索引
			return _create_branch_point_at_position_return_index(branch_pos, segment_index, t)
	
	print("在线段 ", segment_index, " 上尝试了 ", position_attempts, " 个位置都发生碰撞")
	return -1

## 在指定位置创建branch_point并返回索引
func _create_branch_point_at_position_return_index(branch_pos: Vector2, segment_index: int, t_value: float) -> int:
	# 创建branch_point实例
	var branch_point = BRANCH_POINT_SCENE.instantiate()
	branch_point.global_position = branch_pos
	add_child(branch_point)
	
	# 添加到点位管理系统
	var branch_point_index = _add_branch_point(branch_pos, segment_index, branch_point)
	
	# 更新线段的branch计数
	trunk_segments[segment_index].current_branch_count += 1
	trunk_segments[segment_index].branch_point_indices.append(branch_point_index)
	
	# 更新可视化标签
	_update_segment_label(segment_index)
	
	print("在线段 ", segment_index, " 上生成branch_point，位置: ", branch_pos, " 参数t: ", t_value, " 索引: ", branch_point_index)
	print("线段当前branch数: ", trunk_segments[segment_index].current_branch_count, "/", trunk_segments[segment_index].max_branch_points)
	
	return branch_point_index
