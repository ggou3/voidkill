class_name BloodSplatter
extends GPUParticles3D

func _ready():
	# Принудительно запускаем взрыв в момент создания объекта
	emitting = true
	
	# Ждем 1 секунду (с запасом, чтобы частицы успели разлететься) и удаляем мусор
	await get_tree().create_timer(1.0).timeout
	queue_free()
