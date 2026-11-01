class_name BloodSplatter
extends GPUParticles3D

func _ready():
	# Принудительно запускаем взрыв в момент создания объекта
	emitting = true
	
	# Удаляем, когда последняя капля отжила (lifetime) — с небольшим запасом
	await get_tree().create_timer(lifetime + 0.1).timeout
	queue_free()
