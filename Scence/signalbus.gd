extends Node

## SignalBus脚本
## 用于处理全局信号通信

signal fruit_picked_now
	
func _physics_process(delta: float) -> void:
	_connect_all_pickoff_signals()

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
