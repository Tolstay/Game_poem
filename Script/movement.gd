extends CharacterBody2D

## 简单的移动控制器
## 支持WASD移动，无重力影响

# 移动参数
@export var move_speed: float = 300.0  # 移动速度
@export var acceleration: float = 1500.0  # 加速度
@export var friction: float = 1200.0  # 摩擦力/减速度

# 移动输入向量
var input_vector: Vector2 = Vector2.ZERO

func _ready():
	print("Movement controller initialized")

func _physics_process(delta):
	# 获取输入
	_handle_input()
	
	# 应用移动
	_apply_movement(delta)
	
	# 执行移动
	move_and_slide()

## 处理输入
func _handle_input():
	input_vector = Vector2.ZERO
	
	# WASD移动输入
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_vector.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_vector.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_vector.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_vector.y -= 1
	
	# 标准化斜向移动
	input_vector = input_vector.normalized()

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
