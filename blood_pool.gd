extends Area3D

func _ready():
	# Подключаем сигналы касания кодом
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	# Если в лужу наступает Игрок, включаем флаг скольжения
	if body.name == "Player":
		body.is_on_blood = true

func _on_body_exited(body):
	# Когда Игрок покидает лужу
	if body.name == "Player":
		body.is_on_blood = false
