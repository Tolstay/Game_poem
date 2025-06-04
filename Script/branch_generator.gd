extends Node2D

## 树枝生成器
## 简单的生成逻辑，由Fruits控制器调用

# 生成参数
@export var branch_length: float = 100.0
@export var min_branch_length: float = 60.0  # 分支长度下限
@export var max_branch_length: float = 80.0  # 分支长度上限
@export var length_randomness: float = 0.8  # 长度随机化频率 (0.0=固定长度, 1.0=完全随机)
@export var line_width: float = 3.0

@export_group("Line Colors", "line_")
@export var line_trunk_color: Color = Color(0.6, 0.4, 0.2, 1.0)  # trunk线段颜色
@export var line_branch_color: Color = Color(0.2, 0.7, 0.3, 1.0)  # branch线段颜色

@export_group("Generation Angles", "angle_")
@export var angle_min_degrees: float = 30.0  # 最小分支角度（度）
@export var angle_max_degrees: float = 85.0  # 最大分支角度（度）
@export var angle_min_branch_separation_degrees: float = 60.0  # 同一生成点的分支之间最小角度（度）

@export var trunk_point_radius: float = 60.0  # trunk点的碰撞半径

@export_group("Bend System", "bend_")
@export var bend_min_points: int = 1  # 最小折线点数量
@export var bend_max_points: int = 1     # 最大折线点数量
@export var bend_probability: float = 1  # 生成折线点的概率
@export var bend_min_offset: float = 3.0  # 最小垂直偏移距离
@export var bend_max_offset: float = 5.0  # 最大垂直偏移距离
@export var bend_min_segment_length: float = 50.0  # 生成折线点的最小线段长度

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
		# 使用随机化的分支长度
		var current_branch_length = _get_random_branch_length()
		var end_pos = start_pos + new_direction * current_branch_length
		
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
	var min_angle_rad = deg_to_rad(angle_min_degrees)
	var max_angle_rad = deg_to_rad(angle_max_degrees)
	
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
	var min_separation_rad = deg_to_rad(angle_min_branch_separation_degrees)
	
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

## 创建分支线条
func _create_branch_line(start_pos: Vector2, end_pos: Vector2):
	var line = Line2D.new()
	line.add_point(to_local(start_pos))
	line.add_point(to_local(end_pos))
	line.width = line_width
	line.default_color = line_branch_color
	
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

## 计算随机化的分支长度
func _get_random_branch_length() -> float:
	if randf() < length_randomness:
		# 使用随机长度
		return randf_range(min_branch_length, max_branch_length)
	else:
		# 使用固定长度
		return branch_length

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
		var current_branch_length = randf_range(fruits_controller.branch_min_length, fruits_controller.branch_max_length)
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
	
	# 生成随机角度偏移
	var min_angle_rad = deg_to_rad(fruits_controller.branch_min_angle_degrees)
	var max_angle_rad = deg_to_rad(fruits_controller.branch_max_angle_degrees)
	var angle_offset = randf_range(min_angle_rad, max_angle_rad)
	
	# 计算新角度
	var new_angle = trunk_angle + (angle_offset if turn_left else -angle_offset)
	
	return Vector2(cos(new_angle), sin(new_angle))

## 检查branch线段是否与现有对象碰撞
func _check_branch_line_collision(start_pos: Vector2, end_pos: Vector2, fruits_controller) -> bool:
	# 检查与已有点的碰撞
	for pos in fruits_controller.point_positions:
		if (pos - end_pos).length() < fruits_controller.branch_collision_radius:
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
	return _sample_curve_at_ratio(curve_points, randf_range(fruits_controller.branch_position_min, fruits_controller.branch_position_max))

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

## 在曲线上按比例采样位置
func _sample_curve_at_ratio(curve_points: Array[Vector2], ratio: float) -> Vector2:
	if curve_points.size() < 2:
		return Vector2.ZERO
	
	if curve_points.size() == 2:
		# 只有两个点，直接插值
		return curve_points[0].lerp(curve_points[1], ratio)
	
	# 计算曲线总长度
	var total_length = 0.0
	var segment_lengths: Array[float] = []
	
	for i in range(curve_points.size() - 1):
		var segment_length = curve_points[i].distance_to(curve_points[i + 1])
		segment_lengths.append(segment_length)
		total_length += segment_length
	
	# 根据比例计算目标距离
	var target_distance = total_length * ratio
	
	# 查找目标点所在的线段
	var accumulated_distance = 0.0
	for i in range(segment_lengths.size()):
		var segment_length = segment_lengths[i]
		if accumulated_distance + segment_length >= target_distance:
			# 目标点在这个线段上
			var local_distance = target_distance - accumulated_distance
			var local_ratio = local_distance / segment_length if segment_length > 0 else 0.0
			
			var sampled_pos = curve_points[i].lerp(curve_points[i + 1], local_ratio)
			return sampled_pos
		
		accumulated_distance += segment_length
	
	# 如果没有找到（理论上不应该发生），返回终点
	return curve_points[curve_points.size() - 1]

## 直线插值branch位置生成（降级方案）
func _generate_branch_position_linear(segment_data: Dictionary) -> Vector2:
	var fruits_controller = get_parent()
	var min_pos = fruits_controller.branch_position_min if fruits_controller else 0.15
	var max_pos = fruits_controller.branch_position_max if fruits_controller else 0.85
	
	var start_pos = segment_data.start_pos
	var end_pos = segment_data.end_pos
	var t = randf_range(min_pos, max_pos)
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

## 计算折线点（包括起点和终点）
func _calculate_bend_points(start_pos: Vector2, end_pos: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	points.append(start_pos)  # 起点
	
	# 计算线段长度和方向
	var segment_length = start_pos.distance_to(end_pos)
	var segment_direction = (end_pos - start_pos).normalized()
	var perpendicular = Vector2(-segment_direction.y, segment_direction.x)  # 垂直方向
	
	# 检查是否应该添加折线点
	if segment_length < bend_min_segment_length:
		points.append(end_pos)  # 太短的线段不添加折线点
		return points
	
	# 决定折线点数量
	var bend_count = 0
	if randf() < bend_probability:
		# 确保最小值不超过最大值
		var min_count = max(0, bend_min_points)
		var max_count = max(min_count, bend_max_points)
		bend_count = randi_range(min_count, max_count)  # bend_min_points到bend_max_points
	
	# 生成中间折线点
	for i in range(bend_count):
		# 计算沿线段的位置（等分）
		var t = float(i + 1) / float(bend_count + 1)
		var base_point = start_pos.lerp(end_pos, t)
		
		# 添加垂直偏移（确保至少达到最小偏移距离）
		var offset_direction = 1.0 if randf() > 0.5 else -1.0  # 随机选择偏移方向
		var offset_amount = randf_range(bend_min_offset, bend_max_offset) * offset_direction
		var offset_point = base_point + perpendicular * offset_amount
		
		points.append(offset_point)
	
	points.append(end_pos)  # 终点
	return points

## 创建带弯曲的trunk线段
func _create_trunk_line_with_bend(points: Array[Vector2]):
	if points.size() < 2:
		return
	
	var line = Line2D.new()
	line.joint_mode = Line2D.LINE_JOINT_ROUND  # 设置圆角连接
	
	# 添加所有点到Line2D
	for point in points:
		line.add_point(to_local(point))
	
	line.width = line_width
	line.default_color = line_trunk_color
	
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
