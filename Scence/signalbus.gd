extends Node

## SignalBus脚本
## 用于处理全局信号通信

signal fruit_picked_now
signal fade_in_now
signal disable_pickoff_interaction  # 新增：禁用pickoff交互信号

var fading:bool = false

# 使用现有的计时器节点
@onready var windrises_timer: Timer = %Windrises
@onready var still_threshold: Timer = %StillThreshold
@onready var curtain: ColorRect = %Curtain

func _ready():
	# 连接计时器信号
	windrises_timer.timeout.connect(_on_windrises_timeout)

func _physics_process(delta: float) -> void:
	_connect_all_pickoff_signals()

## 当鼠标停止移动时的处理
func _on_mouse_stopped_moving():
	print("鼠标静止，启动windrises计时器")
	still_threshold.start()

## 当鼠标开始移动时的处理
func _on_mouse_started_moving():
	if fading == false:
		_stop_all_timers()
	else:
		return

## 停止所有计时器
func _stop_all_timers():
	if windrises_timer.time_left > 0:
		windrises_timer.stop()
	if still_threshold.time_left > 0:
		still_threshold.stop()


## windrises计时器超时处理
func _on_windrises_timeout():
	fading = true
	fade_in_now.emit()


## 连接所有pickoff节点的信号
func _connect_all_pickoff_signals():
	# 查找场景中所有的pickoff节点
	_connect_pickoff_signals_recursive(get_tree().current_scene)

## 递归查找并连接pickoff信号
func _connect_pickoff_signals_recursive(node: Node):
	# 检查当前节点是否是pickoff节点
	if node.name == "pickoff" and node.has_signal("fruit_picked"):
		# 连接fruit_picked信号
		if not node.fruit_picked.is_connected(_on_fruit_picked):
			node.fruit_picked.connect(_on_fruit_picked)
	
	# 递归处理子节点
	for child in node.get_children():
		_connect_pickoff_signals_recursive(child)

## 当接收到fruit_picked信号时的处理方法
func _on_fruit_picked():
	fruit_picked_now.emit()
	print("接收到信号")


func _on_still_threshold_timeout() -> void:
	disable_pickoff_interaction.emit()  # 发出禁用pickoff交互信号
	windrises_timer.start()
	print("启动风计时器")
	print("已发出禁用pickoff交互信号")


func _on_curtain_unlocking_pickoff() -> void:
	fading = false
