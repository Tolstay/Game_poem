extends Node2D

## Main场景脚本
## 负责场景初始化、petal圆形实例化和生成交互控制

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

# Petal基础信息（仅用于生成）
var petal_positions: Array[Vector2] = []  # 记录所有petal的原始位置
var petal_nodes: Array[Node] = []  # 记录petal节点引用

# 生成控制参数
@export_group("Generation Control", "gen_")
@export var default_trunk_count: int = 1  # 默认trunk生成数量
@export var default_branch_decoration_count: int = 1  # 默认branch装饰组生成数量

# ==================== 输入处理 ====================

func _input(_event):
	# 响应generate输入映射（空格键：协调生成trunk和branch装饰）
	if Input.is_action_just_pressed("generate"):
		_execute_coordinated_generation(default_trunk_count, default_branch_decoration_count)

## 执行协调生成（trunk组 + branch装饰组）
func _execute_coordinated_generation(trunk_count: int, branch_decoration_count: int):
	if not fruits_node:
		print("错误：无法找到fruits节点")
		return
	
	# 记录生成前的统计数据
	var initial_trunk_count = _get_current_trunk_count()
	var initial_branch_count = _get_current_branch_count()
	
	# 第一阶段：生成trunk组
	_execute_trunk_generation_group(trunk_count)
	
	# 第二阶段：生成branch装饰组
	_execute_branch_decoration_group(branch_decoration_count)
	
	# 统计生成后的数据并显示结果
	var final_trunk_count = _get_current_trunk_count()
	var final_branch_count = _get_current_branch_count()
	
	var generated_trunks = final_trunk_count - initial_trunk_count
	var generated_branches = final_branch_count - initial_branch_count
	
	print("=== 生成统计 ===")
	print("本次生成trunk: ", generated_trunks, " 个，现有trunk总数: ", final_trunk_count, " 个")
	print("本次生成branch: ", generated_branches, " 个，现有branch总数: ", final_branch_count, " 个")

## 获取当前trunk数量
func _get_current_trunk_count() -> int:
	if not fruits_node or not fruits_node.has_method("get_trunk_count"):
		return 0
	return fruits_node.get_trunk_count()

## 获取当前branch数量
func _get_current_branch_count() -> int:
	if not fruits_node or not fruits_node.has_method("get_branch_count"):
		return 0
	return fruits_node.get_branch_count()

## 执行trunk生成组
func _execute_trunk_generation_group(count: int):
	if count <= 0:
		return
	
	for i in range(count):
		if fruits_node.has_method("execute_trunk_generation"):
			var success = fruits_node.execute_trunk_generation()
			if not success:
				break
		else:
			break

## 执行branch装饰组生成
func _execute_branch_decoration_group(count: int):
	if count <= 0:
		return
	
	# 记录生成前的END_BRANCH点状态
	var initial_end_branch_points = _get_current_end_branch_points()
	
	for i in range(count):
		# 执行branch生成
		if fruits_node.has_method("execute_branch_generation"):
			var branch_success = fruits_node.execute_branch_generation()
			if not branch_success:
				continue
		else:
			break
		
		# 查找新生成的END_BRANCH点
		var new_end_branch_points = _get_new_end_branch_points(initial_end_branch_points)
		
		# 在新的END_BRANCH点上生成bloodcut和fruit
		_generate_decorations_at_points(new_end_branch_points)
		
		# 更新初始状态，为下一轮准备
		initial_end_branch_points = _get_current_end_branch_points()

## 获取当前所有END_BRANCH状态的点
func _get_current_end_branch_points() -> Array[int]:
	var end_branch_points: Array[int] = []
	if fruits_node and fruits_node.has_method("get_end_branch_points"):
		end_branch_points = fruits_node.get_end_branch_points()
	return end_branch_points

## 获取新生成的END_BRANCH点
func _get_new_end_branch_points(initial_points: Array[int]) -> Array[int]:
	var current_points = _get_current_end_branch_points()
	var new_points: Array[int] = []
	
	for point in current_points:
		if point not in initial_points:
			new_points.append(point)
	
	return new_points

## 在指定点位生成装饰（bloodcut和fruit）
func _generate_decorations_at_points(point_indices: Array[int]):
	if point_indices.size() == 0:
		return
	
	for point_index in point_indices:
		# 生成bloodcut
		if fruits_node.has_method("generate_bloodcut_at_point"):
			fruits_node.generate_bloodcut_at_point(point_index)
		
		# 生成fruit
		if fruits_node.has_method("generate_fruit_at_point"):
			fruits_node.generate_fruit_at_point(point_index)

# ==================== 现有代码保持不变 ====================

func _ready():
	print("Main场景初始化")
	
	# 首先查找SubViewport相关节点
	_find_subviewport_structure()
	
	# 查找First_Point（支持SubViewport结构）
	_find_first_point()
	
	# 如果启用自动生成，在First_Point周围生成petal
	if petal_auto_generate and first_point:
		_generate_petals_around_first_point()

## 查找SubViewport结构
func _find_subviewport_structure():
	# 查找SubViewportContainer/SubViewport结构
	var subviewport_container = get_node_or_null("SubViewportContainer")
	if subviewport_container:
		sub_viewport = subviewport_container.get_node_or_null("SubViewport")
		if sub_viewport:
			# 在SubViewport中查找Fruits节点
			fruits_node = sub_viewport.get_node_or_null("Fruits")
	else:
		# 降级到传统查找方式
		fruits_node = get_node_or_null("Fruits")

## 查找First_Point（支持SubViewport结构）
func _find_first_point():
	# 优先在SubViewport结构中查找
	if sub_viewport and fruits_node:
		first_point = fruits_node.get_node_or_null("First_Point")
		if first_point:
			return
	
	# 降级到传统查找方式
	if fruits_node:
		first_point = fruits_node.get_node_or_null("First_Point")
		if first_point:
			return
	
	# 最后尝试直接查找
	first_point = get_node_or_null("First_Point")

## 在First_Point周围生成petal
func _generate_petals_around_first_point():
	if not first_point:
		return
	
	var center_pos = first_point.global_position
	
	# 清空现有记录
	petal_positions.clear()
	petal_nodes.clear()
	
	# 计算每个petal的角度间隔
	var angle_step = 2 * PI / petal_count
	
	for i in range(petal_count):
		# 计算当前petal的角度和位置
		var angle = i * angle_step
		var offset = Vector2(cos(angle), sin(angle)) * petal_radius
		var petal_pos = center_pos + offset
		
		# 实例化petal
		var petal = PETAL_SCENE.instantiate()
		petal.global_position = petal_pos
		
		# 设置petal的旋转（让sprite指向圆心）
		var sprite2d = petal.get_node("Sprite2D")
		if sprite2d:
			# 计算指向圆心的方向
			var direction_to_center = (center_pos - petal_pos).normalized()
			# 计算旋转角度（sprite的默认方向是向上，加90度调整 + 180度翻转让头指向圆心）
			var rotation_angle = direction_to_center.angle() + PI/2 + PI  # +90度 + 180度
			sprite2d.rotation = rotation_angle
		
		# 添加到正确的父节点
		_add_petal_to_correct_parent(petal)
		
		# 记录petal信息
		petal_positions.append(petal_pos)
		petal_nodes.append(petal)

## 智能选择petal的父节点
func _add_petal_to_correct_parent(petal: Node):
	# 优先添加到SubViewport
	if sub_viewport:
		sub_viewport.add_child(petal)
	# 降级到Fruits节点
	elif fruits_node:
		fruits_node.add_child(petal)
	# 最后降级到当前节点
	else:
		add_child(petal)
