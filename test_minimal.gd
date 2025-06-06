extends Node

func _ready():
	print("最小测试版本启动成功！")
	print("Godot版本: ", Engine.get_version_info())
	print("平台: ", OS.get_name())
	
	# 创建一个简单的标签显示信息
	var label = Label.new()
	label.text = "游戏正常运行！"
	label.position = Vector2(100, 100)
	add_child(label)
	
	print("测试完成，游戏应该可以正常显示") 