class_name BloodPool
extends Area3D

var _expand_tween: Tween = null
var _base_scale: Vector3 = Vector3.ZERO

func _ready():
	add_to_group("blood_pool")
	# Подключаем сигналы касания кодом
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	# Если в лужу наступает Игрок, включаем флаг скольжения
	if body.name == "Player" or body.is_in_group("player"):
		if "blood_pool_count" in body:
			body.blood_pool_count += 1
			body.is_on_blood = true
		else:
			body.is_on_blood = true

func _on_body_exited(body):
	# Когда Игрок покидает лужу
	if body.name == "Player" or body.is_in_group("player"):
		if "blood_pool_count" in body:
			body.blood_pool_count = max(0, body.blood_pool_count - 1)
			body.is_on_blood = (body.blood_pool_count > 0)
		else:
			body.is_on_blood = false

func expand_temporarily(multiplier: float = 1.4, duration: float = 4.0):
	if _base_scale == Vector3.ZERO:
		_base_scale = scale
		
	if _expand_tween and _expand_tween.is_valid():
		_expand_tween.kill()
		
	var target_scale = _base_scale * multiplier
	
	_expand_tween = create_tween()
	# Быстрое расплёскивание лужи наружу (0.22с)
	_expand_tween.tween_property(self, "scale", target_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Удержание увеличенного размера в течение 4 секунд
	_expand_tween.tween_interval(duration)
	# Плавное возвращение к исходному размеру (0.8с)
	_expand_tween.tween_property(self, "scale", _base_scale, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
