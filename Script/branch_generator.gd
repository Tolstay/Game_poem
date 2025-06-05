extends Node2D

## 树枝生成器
## 简单的生成逻辑，由Fruits控制器调用

@export_group("Trunk System", "trunk_")
@export var trunk_length_min: float = 70.0  # Trunk最小长度
@export var trunk_length_max: float = 120.0  # Trunk最大长度
@export var trunk_length_randomness: float = 0.7  # Trunk长度随机化频率 (0.0=固定长度, 1.0=完全随机)
@export var trunk_angle_min_degrees: float = 30.0  # Trunk最小分支角度（度）
@export var trunk_angle_max_degrees: float = 85.0  # Trunk最大分支角度（度）
@export var trunk_angle_min_separation_degrees: float = 50.0  # Trunk同一生成点的分支之间最小角度（度）
@export var trunk_point_radius: float = 60.0  # Trunk点的碰撞半径
@export var trunk_line_width: float = 4.0  # Trunk线段宽度
@export var trunk_line_color: Color = Color.BLACK  # Trunk线段颜色

@export_group("Trunk Bend System", "trunk_bend_")
@export var trunk_bend_min_points: int = 5  # Trunk最小折线点数量
@export var trunk_bend_max_points: int = 10  # Trunk最大折线点数量
@export var trunk_bend_probability: float = 1.0  # Trunk生成折线点的概率
@export var trunk_bend_min_offset: float = 3.0  # Trunk最小垂直偏移距离
@export var trunk_bend_max_offset: float = 12.0  # Trunk最大垂直偏移距离
@export var trunk_bend_min_segment_length: float = 50.0  # Trunk生成折线点的最小线段长度
@export var trunk_bend_enable_coordinated: bool = true  # 是否启用Trunk协调弯曲（避免曲折）
@export var trunk_bend_arc_intensity: float = 1.0  # Trunk弧形强度（0.0=直线分布，1.0=完整弧形）
@export var trunk_bend_direction_consistency: float = 1.0  # Trunk方向一致性（0.0=完全随机，1.0=完全一致）
@export var trunk_bend_offset_smoothness: float = 0.8  # Trunk偏移量平滑度（0.0=完全随机，1.0=完全平滑）

@export_group("Branch Bend System", "branch_bend_")
@export var branch_bend_enabled: bool = true  # 是否启用Branch弯曲
@export var branch_bend_min_points: int = 3  # Branch最小折线点数量
@export var branch_bend_max_points: int = 10  # Branch最大折线点数量
@export var branch_bend_probability: float = 1  # Branch生成折线点的概率
@export var branch_bend_min_offset: float = 4.0  # Branch最小垂直偏移距离
@export var branch_bend_max_offset: float = 7.0  # Branch最大垂直偏移距离
@export var branch_bend_min_segment_length: float = 10.0  # Branch生成折线点的最小线段长度
@export var branch_bend_enable_coordinated: bool = true  # 是否启用Branch协调弯曲
@export var branch_bend_arc_intensity: float = 0.8  # Branch弧形强度
@export var branch_bend_direction_consistency: float = 1  # Branch方向一致性
@export var branch_bend_offset_smoothness: float = 0.7  # Branch偏移量平滑度

@export_group("Branch System", "branch_")
@export var branch_length_min: float = 40.0  # Branch最小长度
@export var branch_length_max: float = 60.0  # Branch最大长度
@export var branch_length_randomness: float = 0.8  # Branch长度随机化频率
@export var branch_min_angle_degrees: float = 40.0  # branch相对trunk的最小角度（度）
@export var branch_max_angle_degrees: float = 65.0  # branch相对trunk的最大角度（度）
@export var branch_collision_radius: float = 30.0  # branch_point的碰撞半径（决定实际可容纳数量）
@export var branch_position_min: float = 0.15  # branch_point在线段上的最小位置（0.0-1.0）
@export var branch_position_max: float = 0.85  # branch_point在线段上的最大位置（0.0-1.0）
@export var branch_line_width: float = 3.5  # Branch线段宽度
@export var branch_line_color: Color = Color.BLACK  # Branch线段颜色

# 生成点场景
const TRUNK_POINT_SCENE = preload("res://Scence/trunk_point.tscn")

# 存储已生成的线段，用于避免交叉
var existing_lines: Array[Dictionary] = []

func generate():
	# 获取父节点（Fruits）的可用生成点
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	
	_generate_branches_from_available_points(fruits_controller)

## 从单个指定点生成trunk（供严格控制数量使用）
func generate_from_single_point(point_index: int):
	# 获取父节点（Fruits）
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	
	_generate_branch_from_single_point(fruits_controller, point_index)

## 从单个指定点生成分支
func _generate_branch_from_single_point(fruits_controller, point_index: int):
	var point_positions = fruits_controller.point_positions
	var point_states = fruits_controller.point_states
	var point_directions = fruits_controller.point_directions
	var point_types = fruits_controller.point_types
	
	# 检查点索引是否有效
	if point_index >= point_positions.size():
		return

	# 检查该点是否为TRUNK_POINT类型且还有生成次数
	if point_states[point_index] <= 0 or point_types[point_index] != fruits_controller.PointType.TRUNK_POINT:
		return
	
	var original_direction = Vector2.ZERO
	if point_index < point_directions.size():
		original_direction = point_directions[point_index]
	
	# 获取该点已生成的分支方向
	var existing_branches = fruits_controller.get_point_generated_branches(point_index)
	
	# 尝试生成分支，如果成功则标记该点并记录分支方向
	var generation_result = _generate_single_branch(point_positions[point_index], fruits_controller, original_direction, existing_branches, point_index)
	if generation_result.success:
		fruits_controller._mark_point_used(point_index)
		fruits_controller._record_generated_branch(point_index, generation_result.direction)
	else:
		# 无法生成有效路径，设置为无空间状态
		fruits_controller.set_point_no_space(point_index)

## 从所有可用生成点生成分支
func _generate_branches_from_available_points(fruits_controller):
	var point_positions = fruits_controller.point_positions
	var point_states = fruits_controller.point_states
	var point_directions = fruits_controller.point_directions  # 获取每个点的原始方向
	var point_types = fruits_controller.point_types  # 获取每个点的类型
	
	for i in range(point_positions.size()):
		# 只处理TRUNK_POINT类型且还有生成次数的点
		if point_states[i] > 0 and point_types[i] == fruits_controller.PointType.TRUNK_POINT:
			var original_direction = Vector2.ZERO
			if i < point_directions.size():
				original_direction = point_directions[i]
			
			# 获取该点已生成的分支方向
			var existing_branches = fruits_controller.get_point_generated_branches(i)
			
			# 尝试生成分支，如果成功则标记该点并记录分支方向
			var generation_result = _generate_single_branch(point_positions[i], fruits_controller, original_direction, existing_branches, i)
			if generation_result.success:
				fruits_controller._mark_point_used(i)
				fruits_controller._record_generated_branch(i, generation_result.direction)
			else:
				# 无法生成有效路径，设置为无空间状态
				fruits_controller.set_point_no_space(i)

## 生成单条分支，返回生成结果
func _generate_single_branch(start_pos: Vector2, fruits_controller, original_direction: Vector2, existing_branches: Array, start_point_index: int) -> Dictionary:
	var max_attempts = 30  # 增加尝试次数，因为现在有更多角度限制
	var attempt = 0
	
	while attempt < max_attempts:
		# 生成随机方向
		var new_direction = _generate_valid_direction(original_direction, existing_branches)
		# 使用随机化的trunk长度
		var current_trunk_length = _get_random_trunk_length()
		var end_pos = start_pos + new_direction * current_trunk_length
		
		# 检查是否与现有线段交叉
		if not _check_line_intersection(start_pos, end_pos):
			# 检查新生成点是否与已有点距离过近
			if not _check_point_collision(end_pos, fruits_controller):
				# 没有交叉且不与其他点碰撞，可以生成
				var end_point_index = _create_end_point(end_pos, fruits_controller, new_direction)
				
				# 先记录trunk线段信息，获得正确的线段索引
				fruits_controller._record_trunk_segment(start_point_index, end_point_index)
				var segment_index = fruits_controller.trunk_segments.size() - 1  # 刚刚添加的线段索引
				
				# 使用带弯曲的trunk生成，传递正确的线段索引
				generate_trunk_with_bend(start_pos, end_pos, fruits_controller, segment_index)
				
				# 记录这条线段（注意：折线生成会在 generate_trunk_with_bend 内部处理）
				# existing_lines.append() 操作已在 _create_trunk_line_with_bend 中处理
				
				return {"success": true, "direction": new_direction}
		
		attempt += 1
	
	return {"success": false, "direction": Vector2.ZERO}

## 生成符合角度要求的方向
func _generate_valid_direction(original_direction: Vector2, existing_branches: Array) -> Vector2:
	if original_direction == Vector2.ZERO:
		# 如果没有原始方向，随机生成，但要避免与已有分支冲突
		return _generate_direction_avoiding_existing(existing_branches)
	
	# 计算原始方向的角度
	var original_angle = original_direction.angle()
	
	# 生成符合角度限制的新方向
	var min_angle_rad = deg_to_rad(trunk_angle_min_degrees)
	var max_angle_rad = deg_to_rad(trunk_angle_max_degrees)
	
	var max_direction_attempts = 20
	for attempt in range(max_direction_attempts):
		# 随机选择左转或右转
		var turn_left = randf() > 0.5
		var angle_range = max_angle_rad - min_angle_rad
		var random_offset = min_angle_rad + randf() * angle_range
		
		var new_angle = original_angle + (random_offset if turn_left else -random_offset)
		var candidate_direction = Vector2(cos(new_angle), sin(new_angle))
		
		# 检查与已有分支的角度
		if _check_branch_separation(candidate_direction, existing_branches):
			return candidate_direction
	
	# 如果无法找到合适的方向，尝试完全随机的方向
	return _generate_direction_avoiding_existing(existing_branches)

## 生成避免与已有分支冲突的随机方向
func _generate_direction_avoiding_existing(existing_branches: Array) -> Vector2:
	var max_attempts = 50
	for attempt in range(max_attempts):
		var random_angle = randf() * 2 * PI
		var candidate_direction = Vector2(cos(random_angle), sin(random_angle))
		
		if _check_branch_separation(candidate_direction, existing_branches):
			return candidate_direction
	
	# 如果实在找不到，返回随机方向（可能会有角度冲突）
	var fallback_angle = randf() * 2 * PI
	return Vector2(cos(fallback_angle), sin(fallback_angle))

## 检查新方向与已有分支的角度分离是否足够
func _check_branch_separation(new_direction: Vector2, existing_branches: Array) -> bool:
	var min_separation_rad = deg_to_rad(trunk_angle_min_separation_degrees)
	
	for existing_branch in existing_branches:
		var angle_diff = abs(new_direction.angle() - existing_branch.angle())
		# 处理角度环绕（0度和360度相邻）
		if angle_diff > PI:
			angle_diff = 2 * PI - angle_diff
		
		if angle_diff < min_separation_rad:
			return false  # 角度太小，不符合要求
	
	return true  # 角度分离足够

## 检查线段是否与现有线段交叉
func _check_line_intersection(new_start: Vector2, new_end: Vector2) -> bool:
	for line in existing_lines:
		if _lines_intersect(new_start, new_end, line.start, line.end):
			return true
	return false

## 判断两条线段是否相交
func _lines_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 = _direction(p3, p4, p1)
	var d2 = _direction(p3, p4, p2)
	var d3 = _direction(p1, p2, p3)
	var d4 = _direction(p1, p2, p4)
	
	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and \
	   ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
		return true
	
	return false

## 计算方向（用于线段相交判断）
func _direction(pi: Vector2, pj: Vector2, pk: Vector2) -> float:
	return (pk.x - pi.x) * (pj.y - pi.y) - (pj.x - pi.x) * (pk.y - pi.y)

## 创建分支线条（支持弯曲）
func _create_branch_line(start_pos: Vector2, end_pos: Vector2):
	# 计算包含折线点的完整路径
	var all_points = _calculate_branch_bend_points(start_pos, end_pos)
	
	# 创建弯曲的branch线段
	_create_branch_line_with_bend(all_points)

## 在末端创建新的生成点
func _create_end_point(end_pos: Vector2, fruits_controller, direction: Vector2) -> int:
	var new_point = TRUNK_POINT_SCENE.instantiate()
	new_point.global_position = end_pos
	
	# 获取Fruitlayer节点并添加trunk点
	if fruits_controller.has_method("get_fruit_layer"):
		var fruit_layer = fruits_controller.get_fruit_layer()
		if fruit_layer:
			fruit_layer.add_child(new_point)
		else:
			fruits_controller.add_child(new_point)
	else:
		fruits_controller.add_child(new_point)
	
	# 更新Fruits控制器的记录，传入方向信息和节点引用，并获取新点的索引
	var new_point_index = fruits_controller._add_new_point(end_pos, direction, new_point)
	return new_point_index

## 检查新生成点是否与已有点距离过近
func _check_point_collision(new_pos: Vector2, fruits_controller) -> bool:
	var point_positions = fruits_controller.point_positions
	for pos in point_positions:
		if (pos - new_pos).length() < trunk_point_radius:
			return true
	return false

## 计算随机化的trunk长度
func _get_random_trunk_length() -> float:
	if randf() < trunk_length_randomness:
		# 使用随机长度
		return randf_range(trunk_length_min, trunk_length_max)
	else:
		# 使用最大长度作为固定长度
		return trunk_length_max

## 计算随机化的branch长度
func _get_random_branch_length() -> float:
	if randf() < branch_length_randomness:
		# 使用随机长度
		return randf_range(branch_length_min, branch_length_max)
	else:
		# 使用最大长度作为固定长度
		return branch_length_max

## 记录branch线段到existing_lines（供fruits.gd调用）
func _record_branch_line(start_pos: Vector2, end_pos: Vector2):
	existing_lines.append({
		"start": start_pos,
		"end": end_pos
	})

## 生成branch线段（由fruits.gd调用）
func generate_branch():
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	
	# 获取可用的branch_point
	var available_branch_points = _get_available_branch_points(fruits_controller)
	if available_branch_points.size() == 0:
		return
	
	# 随机选择一个可用的branch_point
	var random_branch_index = available_branch_points[randi() % available_branch_points.size()]
	_generate_branch_from_point(random_branch_index, fruits_controller)

## 从指定的branch_point生成branch线段（新增方法，用于完整branch生成）
func generate_branch_from_specific_point(branch_point_index: int):
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	
	_generate_branch_from_point(branch_point_index, fruits_controller)

## 获取所有可用的branch_point索引
func _get_available_branch_points(fruits_controller) -> Array[int]:
	var available_points: Array[int] = []
	for i in range(fruits_controller.point_positions.size()):
		if fruits_controller.point_types[i] == fruits_controller.PointType.BRANCH_POINT and fruits_controller.point_states[i] > 0:
			available_points.append(i)
	return available_points

## 从指定的branch_point生成branch线段
func _generate_branch_from_point(branch_point_index: int, fruits_controller):
	if branch_point_index >= fruits_controller.point_positions.size():
		return
	
	var branch_start_pos = fruits_controller.point_positions[branch_point_index]
	var parent_segment_index = fruits_controller.point_parent_segments[branch_point_index]
	
	# 计算trunk的方向
	var trunk_direction = _calculate_trunk_direction(parent_segment_index, fruits_controller)
	if trunk_direction == Vector2.ZERO:
		return
	
	# 尝试生成branch线段
	var max_attempts = 20
	for attempt in range(max_attempts):
		# 生成随机的branch方向和长度
		var branch_direction = _generate_branch_direction(trunk_direction, fruits_controller)
		var current_branch_length = _get_random_branch_length()
		var branch_end_pos = branch_start_pos + branch_direction * current_branch_length
		
		# 检查碰撞
		if not _check_branch_line_collision(branch_start_pos, branch_end_pos, fruits_controller):
			# 没有碰撞，创建完整的branch
			_create_complete_branch(branch_point_index, branch_start_pos, branch_end_pos, branch_direction, fruits_controller)
			return

## 计算trunk的生长方向
func _calculate_trunk_direction(segment_index: int, fruits_controller) -> Vector2:
	if segment_index < 0 or segment_index >= fruits_controller.trunk_segments.size():
		return Vector2.ZERO
	
	var segment = fruits_controller.trunk_segments[segment_index]
	var start_pos = fruits_controller.point_positions[segment.start_point_index]
	var end_pos = fruits_controller.point_positions[segment.end_point_index]
	
	# 检查是否有弯曲路径数据
	var curve_points = _get_segment_curve_points(segment_index, fruits_controller)
	if curve_points.size() <= 2:
		# 直线线段，返回起点到终点的方向
		return (end_pos - start_pos).normalized()
	
	# 弯曲线段，需要计算branch_point位置处的切线方向
	# 这里我们使用线段的平均方向作为近似（更精确的方法需要知道具体的branch_point位置）
	return _calculate_average_tangent_direction(curve_points)

## 计算弯曲路径的平均切线方向
func _calculate_average_tangent_direction(curve_points: Array[Vector2]) -> Vector2:
	if curve_points.size() < 2:
		return Vector2.ZERO
	
	var total_direction = Vector2.ZERO
	var segment_count = 0
	
	# 计算所有线段段落的方向向量的平均值
	for i in range(curve_points.size() - 1):
		var segment_direction = (curve_points[i + 1] - curve_points[i]).normalized()
		total_direction += segment_direction
		segment_count += 1
	
	if segment_count > 0:
		return (total_direction / segment_count).normalized()
	else:
		return Vector2.ZERO

## 基于trunk方向生成branch方向
func _generate_branch_direction(trunk_direction: Vector2, fruits_controller) -> Vector2:
	var trunk_angle = trunk_direction.angle()
	
	# 随机选择左转或右转
	var turn_left = randf() > 0.5
	
	# 生成随机角度偏移（使用本地参数）
	var min_angle_rad = deg_to_rad(branch_min_angle_degrees)
	var max_angle_rad = deg_to_rad(branch_max_angle_degrees)
	var angle_offset = randf_range(min_angle_rad, max_angle_rad)
	
	# 计算新角度
	var new_angle = trunk_angle + (angle_offset if turn_left else -angle_offset)
	
	return Vector2(cos(new_angle), sin(new_angle))

## 检查branch线段是否与现有对象碰撞
func _check_branch_line_collision(start_pos: Vector2, end_pos: Vector2, fruits_controller) -> bool:
	# 检查与已有点的碰撞（使用本地参数）
	for pos in fruits_controller.point_positions:
		if (pos - end_pos).length() < branch_collision_radius:
			return true
	
	# 检查与已有线段的交叉
	if _check_line_intersection(start_pos, end_pos):
		return true
	
	return false

## 创建完整的branch（线段 + 终点）
func _create_complete_branch(start_point_index: int, start_pos: Vector2, end_pos: Vector2, direction: Vector2, fruits_controller):
	# 标记起点branch_point为已使用
	fruits_controller.mark_branch_point_exhausted(start_point_index)
	
	# 创建branch线段
	_create_branch_line(start_pos, end_pos)
	
	# 记录线段到existing_lines中
	_record_branch_line(start_pos, end_pos)
	
	# 创建终点branch_point
	var end_point_index = fruits_controller.create_branch_endpoint(end_pos, direction)

## 供fruits调用的新接口方法 ====================

## 创建完整branch（供fruits调用的公共接口）
func create_complete_branch(start_point_index: int, start_pos: Vector2, end_pos: Vector2, direction: Vector2):
	var fruits_controller = get_parent()
	if not fruits_controller:
		return
	_create_complete_branch(start_point_index, start_pos, end_pos, direction, fruits_controller)

## 生成branch点（供fruits调用）
func generate_branch_point(available_segments: Array[int]) -> bool:
	var fruits_controller = get_parent()
	if not fruits_controller:
		return false
	
	var max_attempts = available_segments.size() * 3
	var attempts = 0
	
	while attempts < max_attempts:
		var random_segment_index = available_segments[randi() % available_segments.size()]
		
		var new_point_index = try_generate_branch_point_on_segment(random_segment_index)
		if new_point_index != -1:
			return true
		
		attempts += 1
	
	return false

## 在任意可用线段上尝试生成branch点（供fruits调用）
func try_generate_branch_point_anywhere(available_segments: Array[int]) -> int:
	var fruits_controller = get_parent()
	if not fruits_controller:
		return -1
	
	var max_attempts = available_segments.size() * 3
	var attempts = 0
	
	while attempts < max_attempts:
		var random_segment_index = available_segments[randi() % available_segments.size()]
		
		var new_point_index = try_generate_branch_point_on_segment(random_segment_index)
		if new_point_index != -1:
			return new_point_index
		
		attempts += 1
	
	return -1

## 在指定线段上尝试生成branch点（供fruits调用）
func try_generate_branch_point_on_segment(segment_index: int) -> int:
	var fruits_controller = get_parent()
	if not fruits_controller:
		return -1
	
	# 检查线段是否还能创建branch点
	if not fruits_controller.can_segment_create_branch_point(segment_index):
		return -1
	
	# 获取线段数据
	var segment_data = fruits_controller.get_segment_data(segment_index)
	if segment_data.is_empty():
		return -1
	
	# 在该线段上尝试多个位置（使用曲线采样）
	var position_attempts = 10
	for attempt in range(position_attempts):
		var branch_pos = _generate_branch_position_on_curve(segment_data, segment_index)
		
		# 检查位置碰撞
		if fruits_controller.can_create_branch_point_at(branch_pos):
			# 位置有效，创建branch_point
			var new_point_index = fruits_controller.create_branch_point_at_position(branch_pos, segment_index)
			return new_point_index
	
	return -1

## 曲线采样branch位置生成 ====================

## 在弯曲线段上生成branch位置（新的曲线采样方法）
func _generate_branch_position_on_curve(segment_data: Dictionary, segment_index: int) -> Vector2:
	var fruits_controller = get_parent()
	if not fruits_controller:
		# 降级到直线插值
		return _generate_branch_position_linear(segment_data)
	
	# 检查是否有该线段的弯曲路径数据
	var curve_points = _get_segment_curve_points(segment_index, fruits_controller)
	if curve_points.size() <= 2:
		# 如果没有弯曲数据，使用直线插值
		return _generate_branch_position_linear(segment_data)
	
	# 使用曲线采样
	return _sample_curve_at_ratio(curve_points, randf_range(branch_position_min, branch_position_max))

## 获取线段的弯曲路径点
func _get_segment_curve_points(segment_index: int, fruits_controller) -> Array[Vector2]:
	# 使用fruits控制器的新接口获取弯曲路径数据
	if fruits_controller.has_method("get_segment_curve_points"):
		return fruits_controller.get_segment_curve_points(segment_index)
	else:
		# 降级方案：返回直线端点
		var segment_data = fruits_controller.get_segment_data(segment_index)
		if segment_data.is_empty():
			return []
		return [segment_data.start_pos, segment_data.end_pos]

## 在曲线上按比例采样位置（改进版，确保branch point不脱落）
func _sample_curve_at_ratio(curve_points: Array[Vector2], ratio: float) -> Vector2:
	if curve_points.size() < 2:
		return Vector2.ZERO
	
	# 确保ratio在有效范围内
	ratio = clamp(ratio, 0.0, 1.0)
	
	if curve_points.size() == 2:
		# 只有两个点，直接插值
		return curve_points[0].lerp(curve_points[1], ratio)
	
	# 计算曲线总长度和每段长度
	var total_length = 0.0
	var segment_lengths: Array[float] = []
	
	for i in range(curve_points.size() - 1):
		var segment_length = curve_points[i].distance_to(curve_points[i + 1])
		segment_lengths.append(segment_length)
		total_length += segment_length
	
	# 防止除零错误
	if total_length <= 0.0:
		return curve_points[0]
	
	# 根据比例计算目标距离
	var target_distance = total_length * ratio
	
	# 查找目标点所在的线段
	var accumulated_distance = 0.0
	for i in range(segment_lengths.size()):
		var segment_length = segment_lengths[i]
		
		# 检查目标点是否在当前线段上
		if accumulated_distance + segment_length >= target_distance:
			# 目标点在这个线段上
			var local_distance = target_distance - accumulated_distance
			var local_ratio = local_distance / segment_length if segment_length > 0 else 0.0
			
			# 确保local_ratio在有效范围内
			local_ratio = clamp(local_ratio, 0.0, 1.0)
			
			var sampled_pos = curve_points[i].lerp(curve_points[i + 1], local_ratio)
			return sampled_pos
		
		accumulated_distance += segment_length
	
	# 如果没有找到（边界情况），返回最接近的端点
	if ratio <= 0.0:
		return curve_points[0]
	else:
		return curve_points[curve_points.size() - 1]

## 直线插值branch位置生成（降级方案）
func _generate_branch_position_linear(segment_data: Dictionary) -> Vector2:
	var start_pos = segment_data.start_pos
	var end_pos = segment_data.end_pos
	var t = randf_range(branch_position_min, branch_position_max)
	return start_pos.lerp(end_pos, t)

## 生成trunk线段（由fruits.gd调用，支持弯曲）
func generate_trunk_with_bend(start_pos: Vector2, end_pos: Vector2, fruits_controller, segment_index: int):
	# 计算包含折线点的完整路径
	var all_points = _calculate_bend_points(start_pos, end_pos)
	
	# 创建弯曲的trunk线段
	_create_trunk_line_with_bend(all_points)
	
	# 存储折线点供将来处理，传递正确的线段索引
	if fruits_controller and fruits_controller.has_method("_store_bend_points_for_future_processing"):
		fruits_controller._store_bend_points_for_future_processing(all_points, segment_index)

## 计算折线点（包括起点和终点）- 支持协调弯曲
func _calculate_bend_points(start_pos: Vector2, end_pos: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	points.append(start_pos)  # 起点
	
	# 计算线段长度和方向
	var segment_length = start_pos.distance_to(end_pos)
	var segment_direction = (end_pos - start_pos).normalized()
	var perpendicular = Vector2(-segment_direction.y, segment_direction.x)  # 垂直方向
	
	# 检查是否应该添加折线点
	if segment_length < trunk_bend_min_segment_length:
		points.append(end_pos)  # 太短的线段不添加折线点
		return points
	
	# 决定折线点数量
	var bend_count = 0
	if randf() < trunk_bend_probability:
		# 确保最小值不超过最大值
		var min_count = max(0, trunk_bend_min_points)
		var max_count = max(min_count, trunk_bend_max_points)
		bend_count = randi_range(min_count, max_count)
	
	# 生成中间折线点
	if bend_count > 0:
		if trunk_bend_enable_coordinated:
			# 协调弯曲模式：所有点向协调的方向弯曲
			_generate_coordinated_bend_points(points, start_pos, end_pos, perpendicular, bend_count)
		else:
			# 传统随机弯曲模式（保持向后兼容）
			_generate_random_bend_points(points, start_pos, end_pos, perpendicular, bend_count)
	
	points.append(end_pos)  # 终点
	return points

## 生成协调弯曲点（新方法）
func _generate_coordinated_bend_points(points: Array[Vector2], start_pos: Vector2, end_pos: Vector2, perpendicular: Vector2, bend_count: int):
	# 为整条trunk选择一个主弯曲方向
	var main_bend_direction = 1.0 if randf() > 0.5 else -1.0
	
	# 为整条trunk选择一个基础偏移量（用于平滑模式）
	var base_trunk_offset = randf_range(trunk_bend_min_offset, trunk_bend_max_offset)
	
	# 生成中间折线点
	for i in range(bend_count):
		# 计算沿线段的位置（等分）
		var t = float(i + 1) / float(bend_count + 1)
		var base_point = start_pos.lerp(end_pos, t)
		
		# 计算弧形强度因子（创造自然的弧形效果）
		var arc_factor = 1.0
		if trunk_bend_arc_intensity > 0.0:
			# 使用正弦函数创造弧形分布，中间最强，两端较弱
			var progress = float(i) / float(bend_count - 1) if bend_count > 1 else 0.5
			arc_factor = sin(progress * PI) * trunk_bend_arc_intensity + (1.0 - trunk_bend_arc_intensity)
		
		# 计算偏移量（应用平滑度控制）
		var base_offset: float
		if trunk_bend_offset_smoothness >= 1.0:
			# 完全平滑：所有点使用相同的基础偏移
			base_offset = base_trunk_offset
		else:
			# 混合模式：在平滑偏移和随机偏移之间插值
			var smooth_offset = base_trunk_offset
			var random_offset = randf_range(trunk_bend_min_offset, trunk_bend_max_offset)
			base_offset = lerp(random_offset, smooth_offset, trunk_bend_offset_smoothness)
		
		# 应用方向一致性
		var final_direction = main_bend_direction
		if trunk_bend_direction_consistency < 1.0:
			# 允许一些随机性，但仍然倾向于主方向
			var random_factor = (randf() - 0.5) * 2.0 * (1.0 - trunk_bend_direction_consistency)
			final_direction = main_bend_direction + random_factor
			# 确保方向在合理范围内
			final_direction = clamp(final_direction, -1.0, 1.0)
		
		# 应用所有因子计算最终偏移
		var offset_amount = base_offset * arc_factor * final_direction
		var offset_point = base_point + perpendicular * offset_amount
		
		points.append(offset_point)

## 生成传统随机弯曲点（保持向后兼容）
func _generate_random_bend_points(points: Array[Vector2], start_pos: Vector2, end_pos: Vector2, perpendicular: Vector2, bend_count: int):
	for i in range(bend_count):
		# 计算沿线段的位置（等分）
		var t = float(i + 1) / float(bend_count + 1)
		var base_point = start_pos.lerp(end_pos, t)
		
		# 添加垂直偏移（原始随机方法）
		var offset_direction = 1.0 if randf() > 0.5 else -1.0  # 随机选择偏移方向
		var offset_amount = randf_range(trunk_bend_min_offset, trunk_bend_max_offset) * offset_direction
		var offset_point = base_point + perpendicular * offset_amount
		
		points.append(offset_point)

## 创建带弯曲的trunk线段
func _create_trunk_line_with_bend(points: Array[Vector2]):
	if points.size() < 2:
		return
	
	var line = Line2D.new()
	line.joint_mode = Line2D.LINE_JOINT_ROUND  # 设置圆角连接
	
	# 添加所有点到Line2D
	for point in points:
		line.add_point(to_local(point))
	
	line.width = trunk_line_width
	line.default_color = trunk_line_color
	
	# 应用trunk1贴图
	var trunk_texture = preload("res://Asset/trunk/trunk1.png")
	line.texture = trunk_texture
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	
	# 获取Fruitlayer节点并添加Line2D
	var fruits_controller = get_parent()
	if fruits_controller and fruits_controller.has_method("get_fruit_layer"):
		var fruit_layer = fruits_controller.get_fruit_layer()
		if fruit_layer:
			fruit_layer.add_child(line)
		else:
			add_child(line)
	else:
		add_child(line)
	
	# 记录所有线段段落
	for i in range(points.size() - 1):
		existing_lines.append({
			"start": points[i],
			"end": points[i + 1]
		})

## ==================== Branch弯曲系统 ====================

## 计算branch折线点（专用于branch的弯曲）
func _calculate_branch_bend_points(start_pos: Vector2, end_pos: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	points.append(start_pos)  # 起点
	
	# 如果branch弯曲未启用，直接返回直线
	if not branch_bend_enabled:
		points.append(end_pos)
		return points
	
	# 计算线段长度和方向
	var segment_length = start_pos.distance_to(end_pos)
	var segment_direction = (end_pos - start_pos).normalized()
	var perpendicular = Vector2(-segment_direction.y, segment_direction.x)  # 垂直方向
	
	# 检查是否应该添加折线点
	if segment_length < branch_bend_min_segment_length:
		points.append(end_pos)  # 太短的线段不添加折线点
		return points
	
	# 决定折线点数量
	var bend_count = 0
	if randf() < branch_bend_probability:
		# 确保最小值不超过最大值
		var min_count = max(0, branch_bend_min_points)
		var max_count = max(min_count, branch_bend_max_points)
		bend_count = randi_range(min_count, max_count)
	
	# 生成中间折线点
	if bend_count > 0:
		if branch_bend_enable_coordinated:
			# 协调弯曲模式：所有点向协调的方向弯曲
			_generate_coordinated_branch_bend_points(points, start_pos, end_pos, perpendicular, bend_count)
		else:
			# 传统随机弯曲模式
			_generate_random_branch_bend_points(points, start_pos, end_pos, perpendicular, bend_count)
	
	points.append(end_pos)  # 终点
	return points

## 生成协调branch弯曲点
func _generate_coordinated_branch_bend_points(points: Array[Vector2], start_pos: Vector2, end_pos: Vector2, perpendicular: Vector2, bend_count: int):
	# 为整条branch选择一个主弯曲方向
	var main_bend_direction = 1.0 if randf() > 0.5 else -1.0
	
	# 为整条branch选择一个基础偏移量（用于平滑模式）
	var base_branch_offset = randf_range(branch_bend_min_offset, branch_bend_max_offset)
	
	# 生成中间折线点
	for i in range(bend_count):
		# 计算沿线段的位置（等分）
		var t = float(i + 1) / float(bend_count + 1)
		var base_point = start_pos.lerp(end_pos, t)
		
		# 计算弧形强度因子（创造自然的弧形效果）
		var arc_factor = 1.0
		if branch_bend_arc_intensity > 0.0:
			# 使用正弦函数创造弧形分布，中间最强，两端较弱
			var progress = float(i) / float(bend_count - 1) if bend_count > 1 else 0.5
			arc_factor = sin(progress * PI) * branch_bend_arc_intensity + (1.0 - branch_bend_arc_intensity)
		
		# 计算偏移量（应用平滑度控制）
		var base_offset: float
		if branch_bend_offset_smoothness >= 1.0:
			# 完全平滑：所有点使用相同的基础偏移
			base_offset = base_branch_offset
		else:
			# 混合模式：在平滑偏移和随机偏移之间插值
			var smooth_offset = base_branch_offset
			var random_offset = randf_range(branch_bend_min_offset, branch_bend_max_offset)
			base_offset = lerp(random_offset, smooth_offset, branch_bend_offset_smoothness)
		
		# 应用方向一致性
		var final_direction = main_bend_direction
		if branch_bend_direction_consistency < 1.0:
			# 允许一些随机性，但仍然倾向于主方向
			var random_factor = (randf() - 0.5) * 2.0 * (1.0 - branch_bend_direction_consistency)
			final_direction = main_bend_direction + random_factor
			# 确保方向在合理范围内
			final_direction = clamp(final_direction, -1.0, 1.0)
		
		# 应用所有因子计算最终偏移
		var offset_amount = base_offset * arc_factor * final_direction
		var offset_point = base_point + perpendicular * offset_amount
		
		points.append(offset_point)

## 生成传统随机branch弯曲点（保持向后兼容）
func _generate_random_branch_bend_points(points: Array[Vector2], start_pos: Vector2, end_pos: Vector2, perpendicular: Vector2, bend_count: int):
	for i in range(bend_count):
		# 计算沿线段的位置（等分）
		var t = float(i + 1) / float(bend_count + 1)
		var base_point = start_pos.lerp(end_pos, t)
		
		# 添加垂直偏移（原始随机方法）
		var offset_direction = 1.0 if randf() > 0.5 else -1.0  # 随机选择偏移方向
		var offset_amount = randf_range(branch_bend_min_offset, branch_bend_max_offset) * offset_direction
		var offset_point = base_point + perpendicular * offset_amount
		
		points.append(offset_point)

## 创建带弯曲的branch线段
func _create_branch_line_with_bend(points: Array[Vector2]):
	if points.size() < 2:
		return
	
	var line = Line2D.new()
	line.joint_mode = Line2D.LINE_JOINT_ROUND  # 设置圆角连接
	
	# 添加所有点到Line2D
	for point in points:
		line.add_point(to_local(point))
	
	line.width = branch_line_width  # 使用branch专用宽度
	line.default_color = branch_line_color
	
	# 应用branch贴图
	var branch_texture = preload("res://Asset/trunk/branch.png")
	line.texture = branch_texture
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	
	# 获取Fruitlayer节点并添加Line2D
	var fruits_controller = get_parent()
	if fruits_controller and fruits_controller.has_method("get_fruit_layer"):
		var fruit_layer = fruits_controller.get_fruit_layer()
		if fruit_layer:
			fruit_layer.add_child(line)
		else:
			add_child(line)
	else:
		add_child(line)
	
	# 记录所有线段段落
	for i in range(points.size() - 1):
		existing_lines.append({
			"start": points[i],
			"end": points[i + 1]
		})
