extends CharacterBody2D

## 简单的移动控制器
## 支持鼠标跟随移动，无重力影响

# 移动参数
@export var move_speed: float = 180.0  # 移动速度
@export var acceleration: float = 600.0  # 加速度
@export var friction: float = 1000.0  # 摩擦力/减速度

# 鼠标跟随参数
@export_group("Mouse Following", "mouse_")
@export var mouse_follow_enabled: bool = true  # 启用鼠标跟随
@export var mouse_min_distance: float = 88.0  # 最小跟随距离，小于此距离不移动
@export var wasd_control_enabled: bool = false  # WASD控制开关（默认禁用）

# 移动输入向量
var input_vector: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO

# 游戏状态控制
var gameover: bool = false  # 游戏结束状态，禁用移动跟随


func _physics_process(delta):
	# 如果游戏结束，禁用所有移动
	if gameover:
		# 应用减速使角色停止
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return
	
	# 获取输入
	_handle_input()
	
	# 应用移动
	_apply_movement(delta)
	
	# 执行移动
	move_and_slide()

## 处理输入
func _handle_input():
	input_vector = Vector2.ZERO
	
	# 如果游戏结束，不处理任何输入
	if gameover:
		return
	
	# 鼠标跟随逻辑
	if mouse_follow_enabled:
		var mouse_world_pos = _get_mouse_world_position()
		var distance_to_mouse = global_position.distance_to(mouse_world_pos)
		
		# 只有当距离大于最小距离时才移动
		if distance_to_mouse > mouse_min_distance:
			target_position = mouse_world_pos
			input_vector = (target_position - global_position).normalized()
	
	# WASD控制（如果启用）
	if wasd_control_enabled:
		var wasd_input = Vector2.ZERO
		
		if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			wasd_input.x += 1
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			wasd_input.x -= 1
		if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			wasd_input.y += 1
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			wasd_input.y -= 1
		
		# 如果有WASD输入，优先使用WASD（覆盖鼠标输入）
		if wasd_input != Vector2.ZERO:
			input_vector = wasd_input.normalized()

## 获取鼠标在世界坐标系中的位置
func _get_mouse_world_position() -> Vector2:
	# 直接使用get_global_mouse_position()
	# 在SubViewport中这应该返回正确的坐标
	return get_global_mouse_position()

## 应用移动逻辑
func _apply_movement(delta):
	if input_vector != Vector2.ZERO:
		# 有输入时加速
		velocity = velocity.move_toward(input_vector * move_speed, acceleration * delta)
	else:
		# 无输入时减速
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	
	# 确保无重力影响（如果有任何垂直重力，将其清除）
	# CharacterBody2D默认不受重力影响，但为了确保我们明确设置
	# 不需要额外处理重力，因为我们完全控制了velocity

## 调试信息（可选，用于测试坐标转换）
func _get_debug_info() -> String:
	var mouse_world = _get_mouse_world_position()
	var distance = global_position.distance_to(mouse_world)
	return "Mouse: %s, Player: %s, Distance: %.1f" % [mouse_world, global_position, distance]

## 设置游戏结束状态（供外部调用）
func set_gameover(state: bool):
	gameover = state
	if gameover:
		print("🎮 [Movement] 游戏结束，移动跟随已禁用")

## 获取游戏结束状态（供外部调用）
func is_gameover() -> bool:
	return gameover
