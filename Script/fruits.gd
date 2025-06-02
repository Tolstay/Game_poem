extends Node2D

## Fruits控制器
## 负责管理所有生成点的坐标与状态，控制生成器的交互

# 点状态枚举
enum PointStatus {
	AVAILABLE,    # 可生成状态
	EXHAUSTED,    # 已耗尽状态
	PATH_TRUNK,   # 路过节点：剩余次数1但无合法路径
	END_TRUNK,    # 终点节点：剩余次数2但无合法路径
	END_BRANCH    # branch终点节点：不可生成
}

# 点类型枚举
enum PointType {
	TRUNK_POINT,      # trunk点
	BRANCH_POINT      # branch点
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
#   "branch_point_indices": Array[int],  # 该线段上的branch_point索引
#   "curve_points": Array[Vector2]  # 完整的弯曲路径点（包括起点、折线点、终点）
# }

# 可视化标签节点
var segment_labels: Array[Label] = []

# 生成器引用
var generator: Node2D

# 生成参数
@export var max_generations_per_point: int = 2  # 每个生成点的最大生成次数
@export var min_branch_points_per_segment: int = 1       # 每线段最少branch_point数（物理约束的最小值）
@export var max_branch_points_per_segment: int = 3       # 每线段最多branch_point数（物理约束的最大值）

# 显示控制参数
@export_group("Display Controls", "display_")
@export var display_segment_labels: bool = false   # 是否显示线段剩余次数标签

# Branch生成参数
@export var branch_position_min: float = 0.15  # branch_point在线段上的最小位置（0.0-1.0）
@export var branch_position_max: float = 0.85  # branch_point在线段上的最大位置（0.0-1.0）
@export var branch_collision_radius: float = 15.0  # branch_point的碰撞半径（决定实际可容纳数量）

# Branch角度控制参数
@export var branch_min_angle_degrees: float = 40.0  # branch相对trunk的最小角度（度）
@export var branch_max_angle_degrees: float = 65.0  # branch相对trunk的最大角度（度）

# Branch长度参数
@export var branch_min_length: float = 35.0  # branch的最小长度
@export var branch_max_length: float = 45.0  # branch的最大长度

# 折线点branch生成参数
@export_group("Bend Point Branch Generation", "bend_branch_")
@export var bend_branch_enabled: bool = true  # 是否启用基于折线点的branch生成
@export var bend_branch_probability: float = 0.6  # 每个折线点生成branch_point的概率
@export var bend_branch_collision_radius: float = 25.0  # 折线点branch_point的碰撞半径

# 记录本轮参与生成的点
var points_used_this_round: Array[int] = []

# 折线点管理（为"G"键功能预留）
var stored_bend_points: Array[Vector2] = []  # 存储的折线点，等待"G"键处理
var bend_point_segments: Array[int] = []  # 记录每个折线点所属的线段索引

# 生成点场景
const BRANCH_POINT_SCENE = preload("res://Scence/branch_point.tscn")

func _ready():
	# 获取生成器引用
	generator = $BranchGenerator
	# 记录初始生成点
	_record_initial_points()

# ==================== 输入处理 ====================

func _input(_event):
	# 响应generate输入映射（空格键：生成trunk带折线）
	if Input.is_action_just_pressed("generate"):
		_execute_generation()
	# 响应branch_generate输入映射（G键：完整branch生成：点位+线段）
	elif Input.is_action_just_pressed("branch_generate"):
		_execute_complete_branch_generation()
	# 响应branch_point_generate输入映射（B键：独立生成branch_point，保留用于精细控制）
	elif Input.is_action_just_pressed("branch_point_generate"):
		_execute_branch_point_generation()
	# 响应bend_branch_generate映射（F键：在存储的折线点生成branch_point）
	elif Input.is_action_just_pressed("bend_branch_generate"):
		_execute_bend_point_branch_generation()

# ==================== 初始化和数据管理 ====================

## 记录所有生成点的坐标和状态
func _record_initial_points():
	# 遍历子节点，找到所有生成点
	for child in get_children():
		if "Point" in child.name:
			point_positions.append(child.global_position)
			
			# 检查是否为特殊的起始点，给予额外生成机会
			var initial_generations = max_generations_per_point
			if child.name == "First_Point":
				initial_generations = 3  # 起始点拥有3次生成机会
			
			point_states.append(initial_generations)  # 设置生成次数
			point_directions.append(Vector2.ZERO)  # 初始点没有方向
			point_generated_branches.append([])  # 初始化空的分支记录
			point_status.append(PointStatus.AVAILABLE)  # 初始状态为可用
			point_nodes.append(child)  # 记录节点引用
			point_types.append(PointType.TRUNK_POINT)  # 初始点都是trunk点
			point_parent_segments.append(-1)  # trunk点不属于任何线段

## 添加新生成点（trunk点）
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
	return new_point_index

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
	
	return branch_point_index

# ==================== Trunk生成 ====================

## 执行trunk生成操作
func _execute_generation():
	# 检查是否有可用的生成点
	if get_available_points_count() == 0:
		return
	
	# 清空本轮使用记录
	points_used_this_round.clear()
	
	# 调用生成器的生成方法
	_call_generator_generate()
	
	# 生成完成后，减少参与生成的点的剩余次数
	_decrease_generation_counts()

## 调用生成器执行生成
func _call_generator_generate():
	if generator and generator.has_method("generate"):
		generator.generate()

## 减少参与生成的点的剩余次数
func _decrease_generation_counts():
	for point_index in points_used_this_round:
		if point_index < point_states.size():
			point_states[point_index] -= 1
			
			# 更新状态
			if point_states[point_index] <= 0:
				point_status[point_index] = PointStatus.EXHAUSTED
	
	# 生成完成后的清理
	_post_generation_cleanup()

## 记录点被使用
func _mark_point_used(point_index: int):
	if point_index not in points_used_this_round:
		points_used_this_round.append(point_index)

## 记录生成的分支方向
func _record_generated_branch(point_index: int, direction: Vector2):
	if point_index < point_generated_branches.size():
		point_generated_branches[point_index].append(direction)

## 获取点已生成的分支方向
func get_point_generated_branches(point_index: int) -> Array:
	if point_index < point_generated_branches.size():
		return point_generated_branches[point_index]
	return []

## 记录新的trunk线段（由生成器调用）
func _record_trunk_segment(start_point_index: int, end_point_index: int):
	if start_point_index >= point_positions.size() or end_point_index >= point_positions.size():
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
		"branch_point_indices": [],
		"curve_points": []
	}
	
	trunk_segments.append(segment_data)
	var segment_index = trunk_segments.size() - 1
	
	# 创建可视化标签
	if display_segment_labels:
		_create_segment_label(segment_index, start_pos, end_pos, max_branch_points)

# ==================== Branch点生成 ====================

## 执行完整的branch生成操作（点位生成 + branch线段生成）
func _execute_complete_branch_generation():
	# 检查是否有可用的trunk线段
	var available_segments = _get_available_trunk_segments()
	if available_segments.size() == 0:
		return
	
	# 尝试生成branch_point
	var new_branch_point_index = _try_generate_branch_point_anywhere(available_segments)
	if new_branch_point_index == -1:
		return
	
	# 立即从新生成的branch_point生成branch线段
	if generator and generator.has_method("generate_branch_from_specific_point"):
		generator.generate_branch_from_specific_point(new_branch_point_index)

## 执行branch_point生成操作
func _execute_branch_point_generation():
	var available_segments = _get_available_trunk_segments()
	if available_segments.size() == 0:
		return
	
	# 调用generator生成branch点
	if generator and generator.has_method("generate_branch_point"):
		generator.generate_branch_point(available_segments)

## 在任意可用线段上尝试生成branch_point（统一接口）
func _try_generate_branch_point_anywhere(available_segments: Array[int]) -> int:
	# 调用generator尝试生成branch点
	if generator and generator.has_method("try_generate_branch_point_anywhere"):
		return generator.try_generate_branch_point_anywhere(available_segments)
	else:
		return -1

## 尝试在指定线段上生成branch_point（统一接口，返回新点索引或-1）
func _try_generate_branch_point_on_segment(segment_index: int) -> int:
	# 调用generator尝试在指定线段生成branch点
	if generator and generator.has_method("try_generate_branch_point_on_segment"):
		return generator.try_generate_branch_point_on_segment(segment_index)
	else:
		return -1

## 获取线段数据（提取公共逻辑）
func _get_segment_data(segment_index: int) -> Dictionary:
	if segment_index >= trunk_segments.size():
		return {}
	
	var segment = trunk_segments[segment_index]
	var start_pos = point_positions[segment.start_point_index]
	var end_pos = point_positions[segment.end_point_index]
	
	return {
		"start_pos": start_pos,
		"end_pos": end_pos,
		"segment": segment
	}

## 在线段上生成branch位置（当前使用直线插值，后续会改为曲线采样）
func _generate_branch_position_on_segment(segment_data: Dictionary) -> Vector2:
	var start_pos = segment_data.start_pos
	var end_pos = segment_data.end_pos
	var t = randf_range(branch_position_min, branch_position_max)
	return start_pos.lerp(end_pos, t)

## 在指定位置创建branch_point（统一接口）
func _create_branch_point_at_position(branch_pos: Vector2, segment_index: int) -> int:
	# 创建branch_point实例
	var branch_point = BRANCH_POINT_SCENE.instantiate()
	branch_point.global_position = branch_pos
	add_child(branch_point)
	
	# 添加到点位管理系统
	var branch_point_index = _add_branch_point(branch_pos, segment_index, branch_point)
	
	# 更新线段数据
	_update_segment_branch_count(segment_index, branch_point_index)
	
	return branch_point_index

## 更新线段的branch计数（提取公共逻辑）
func _update_segment_branch_count(segment_index: int, branch_point_index: int):
	if segment_index < trunk_segments.size():
		trunk_segments[segment_index].current_branch_count += 1
		trunk_segments[segment_index].branch_point_indices.append(branch_point_index)
		
		# 更新可视化标签
		if display_segment_labels:
			_update_segment_label(segment_index)

# ==================== 折线点Branch生成 ====================

## 存储折线点用于后续处理
func _store_bend_points_for_future_processing(all_points: Array[Vector2], segment_index: int = -1):
	if not bend_branch_enabled or all_points.size() <= 2:
		return
	
	# 如果传入了有效的线段索引，使用它；否则使用默认逻辑
	var target_segment_index = segment_index
	if target_segment_index < 0:
		target_segment_index = trunk_segments.size() - 1
	
	if target_segment_index < 0 or target_segment_index >= trunk_segments.size():
		return
	
	# 存储完整的弯曲路径到线段数据中
	trunk_segments[target_segment_index].curve_points = all_points.duplicate()
	
	# 同时保持原有的折线点存储逻辑（用于F键功能）
	for i in range(1, all_points.size() - 1):
		var bend_point = all_points[i]
		stored_bend_points.append(bend_point)
		bend_point_segments.append(target_segment_index)

## 获取存储的折线点数据（供generator调用）
func get_stored_bend_points() -> Dictionary:
	return {
		"points": stored_bend_points,
		"segments": bend_point_segments
	}

## 获取线段的弯曲路径点（供generator调用）
func get_segment_curve_points(segment_index: int) -> Array[Vector2]:
	if segment_index < 0 or segment_index >= trunk_segments.size():
		return []
	
	var curve_points = trunk_segments[segment_index].curve_points
	if curve_points.size() > 0:
		return curve_points
	else:
		# 如果没有弯曲数据，返回直线端点
		var segment = trunk_segments[segment_index]
		var start_pos = point_positions[segment.start_point_index]
		var end_pos = point_positions[segment.end_point_index]
		return [start_pos, end_pos]

## 执行折线点branch生成操作
func _execute_bend_point_branch_generation():
	if stored_bend_points.size() == 0:
		return
	
	var generation_count = 0
	var max_generations = min(stored_bend_points.size(), 5)
	
	# 遍历所有折线点，按概率尝试生成branch_point
	for i in range(stored_bend_points.size()):
		if generation_count >= max_generations:
			break
			
		var bend_point = stored_bend_points[i]
		var segment_index = bend_point_segments[i] if i < bend_point_segments.size() else -1
		
		# 概率检查和碰撞检查
		if randf() < bend_branch_probability and not _check_bend_point_collision(bend_point):
			_create_branch_point_at_bend_position(bend_point, segment_index)
			generation_count += 1

## 在折线点位置创建branch_point
func _create_branch_point_at_bend_position(bend_pos: Vector2, segment_index: int):
	# 检查线段是否还有容量
	if segment_index >= 0 and segment_index < trunk_segments.size():
		var segment = trunk_segments[segment_index]
		if segment.current_branch_count >= segment.max_branch_points:
			return
	
	var branch_point = BRANCH_POINT_SCENE.instantiate()
	branch_point.global_position = bend_pos
	add_child(branch_point)
	
	var branch_point_index = _add_branch_point(bend_pos, segment_index, branch_point)
	
	# 更新线段的branch计数（如果线段还存在）
	if segment_index >= 0 and segment_index < trunk_segments.size():
		_update_segment_branch_count(segment_index, branch_point_index)

# ==================== 碰撞检测 ====================

## 检查branch_point位置是否与已有点碰撞
func _check_branch_point_collision(new_pos: Vector2) -> bool:
	for pos in point_positions:
		if (pos - new_pos).length() < branch_collision_radius:
			return true
	return false

## 检查折线点位置是否与现有点碰撞
func _check_bend_point_collision(bend_pos: Vector2) -> bool:
	for pos in point_positions:
		if (pos - bend_pos).length() < bend_branch_collision_radius:
			return true
	return false

# ==================== Branch线段生成相关 ====================

## 获取所有可用的branch_point索引
func _get_available_branch_points() -> Array[int]:
	var available_points: Array[int] = []
	for i in range(point_positions.size()):
		if point_types[i] == PointType.BRANCH_POINT and point_states[i] > 0:
			available_points.append(i)
	return available_points

## 创建完整的branch（线段 + 终点）- 通过调用generator实现
func _create_complete_branch(start_point_index: int, start_pos: Vector2, end_pos: Vector2, direction: Vector2):
	# 调用generator创建完整branch
	if generator and generator.has_method("create_complete_branch"):
		generator.create_complete_branch(start_point_index, start_pos, end_pos, direction)

# ==================== 查询和状态管理 ====================

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

## 根据线段长度计算最大branch_point数量
func _calculate_max_branch_points(segment_length: float) -> int:
	# 基于物理约束的计算逻辑
	var ideal_count = int(segment_length / 40.0)  # 每40像素一个branch_point
	return clamp(ideal_count, min_branch_points_per_segment, max_branch_points_per_segment)

## 获取当前可用的生成点数量
func get_available_points_count() -> int:
	var count = 0
	for state in point_states:
		if state > 0:
			count += 1
	return count

## 获取生成点的详细状态信息
func get_points_status():
	for i in range(point_positions.size()):
		var _status = "可用" if point_states[i] > 0 else "已耗尽"
		var _type_name = "TRUNK" if point_types[i] == PointType.TRUNK_POINT else "BRANCH"
		var _branch_count = point_generated_branches[i].size() if i < point_generated_branches.size() else 0

## 设置点为无空间状态
func set_point_no_space(point_index: int):
	if point_index >= point_status.size():
		return
	
	# 检查剩余生成次数，设置相应的无空间状态
	var remaining_count = point_states[point_index] if point_index < point_states.size() else 0
	
	if remaining_count <= 0:
		point_status[point_index] = PointStatus.END_TRUNK  # 无剩余次数且无路径
	else:
		point_status[point_index] = PointStatus.PATH_TRUNK  # 有剩余次数但无路径

# ==================== 可视化标签管理 ====================

## 创建线段可视化标签
func _create_segment_label(segment_index: int, start_pos: Vector2, end_pos: Vector2, max_branch_points: int):
	if not display_segment_labels:
		return
		
	var label = Label.new()
	label.text = str(max_branch_points)
	label.add_theme_color_override("font_color", Color.WHITE)
	
	# 设置标签位置（线段中点）
	var mid_pos = (start_pos + end_pos) / 2.0
	label.global_position = mid_pos
	
	add_child(label)
	
	# 确保segment_labels数组有足够的空间
	while segment_labels.size() <= segment_index:
		segment_labels.append(null)
	
	segment_labels[segment_index] = label

## 更新线段标签显示
func _update_segment_label(segment_index: int):
	if not display_segment_labels:
		return
		
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

## 切换标签显示
func toggle_segment_labels():
	display_segment_labels = !display_segment_labels
	
	for label in segment_labels:
		if label and is_instance_valid(label):
			label.visible = display_segment_labels

# ==================== 清理和维护 ====================

## 生成后清理
func _post_generation_cleanup():
	# 清空本轮使用记录
	points_used_this_round.clear()

## 调试：显示所有线段状态
func print_all_segment_status():
	for i in range(trunk_segments.size()):
		var segment = trunk_segments[i]
		var _remaining = segment.max_branch_points - segment.current_branch_count

## 供generator调用的接口方法 ====================

## 获取线段数据（供generator调用）
func get_segment_data(segment_index: int) -> Dictionary:
	return _get_segment_data(segment_index)

## 检查branch点是否可以在指定位置创建（供generator调用）
func can_create_branch_point_at(pos: Vector2) -> bool:
	return not _check_branch_point_collision(pos)

## 检查线段是否还能创建branch点（供generator调用）
func can_segment_create_branch_point(segment_index: int) -> bool:
	if segment_index >= trunk_segments.size():
		return false
	var segment = trunk_segments[segment_index]
	return segment.current_branch_count < segment.max_branch_points

## 在指定位置创建branch点（供generator调用）
func create_branch_point_at_position(branch_pos: Vector2, segment_index: int) -> int:
	return _create_branch_point_at_position(branch_pos, segment_index)

## 标记branch点为已使用（供generator调用）
func mark_branch_point_exhausted(point_index: int):
	if point_index < point_states.size():
		point_states[point_index] = 0
		point_status[point_index] = PointStatus.EXHAUSTED

## 创建branch终点（供generator调用）
func create_branch_endpoint(end_pos: Vector2, direction: Vector2) -> int:
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
	
	return end_point_index
