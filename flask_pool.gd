extends Area3D

@export var duration: float = 5.5
@export var slow_multiplier: float = 0.5

var current_time: float = 0.0
var affected_enemies: Array[Node] = []
var player_inside: Node = null

@onready var mesh_inst: MeshInstance3D = get_node_or_null(MeshInstance3D)
@onready var col_shape: CollisionShape3D = get_node_or_null(CollisionShape3D)
var puddle_material: StandardMaterial3D = null

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if mesh_inst:
		var orig_mat = mesh_inst.get_surface_override_material(0)
		if orig_mat:
			puddle_material = orig_mat.duplicate()
			mesh_inst.set_surface_override_material(0, puddle_material)
		
		# Плавная анимация растекания лужи крови при ударе о землю
		mesh_inst.scale = Vector3(0.15, 1.0, 0.15)
		var tween = create_tween()
		tween.tween_property(mesh_inst, scale, Vector3(1.0, 1.0, 1.0), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float):
	current_time += delta
	
	# Пока игрок находится в луже — постоянно поддерживает/продлевает кровавый бафф
	if is_instance_valid(player_inside):
		if skills in player_inside and player_inside.skills:
			player_inside.skills.activate_blood_buff()
		player_inside.is_on_blood = true
		
	# За 0.9с до окончания лужа плавно растворяется
	if current_time >= duration - 0.9:
		var fade_t = (duration - current_time) / 0.9
		if puddle_material:
			puddle_material.albedo_color.a = clamp(fade_t, 0.0, 1.0)
			puddle_material.emission_energy_multiplier = clamp(fade_t * 1.5, 0.0, 1.5)
			
	if current_time >= duration:
		_cleanup_and_free()

func _on_body_entered(body: Node):
	if body.is_in_group(player) or body.name == Player:
		player_inside = body
		body.is_on_blood = true
		if skills in body and body.skills:
			body.skills.activate_blood_buff()
	elif body.is_in_group(enemy) or body.has_method(add_slow):
		if not affected_enemies.has(body):
			affected_enemies.append(body)
		if body.has_method(add_slow):
			body.add_slow(slow_multiplier)

func _on_body_exited(body: Node):
	if body == player_inside:
		if is_instance_valid(player_inside):
			player_inside.is_on_blood = false
		player_inside = null
	elif affected_enemies.has(body):
		affected_enemies.erase(body)
		if is_instance_valid(body) and body.has_method(remove_slow):
			body.remove_slow()

func _cleanup_and_free():
	# Гарантированное восстановление скорости всем врагам внутри перед удалением
	for enemy in affected_enemies:
		if is_instance_valid(enemy) and enemy.has_method(remove_slow):
			enemy.remove_slow()
	affected_enemies.clear()
	
	if is_instance_valid(player_inside):
		player_inside.is_on_blood = false
		player_inside = null
		
	queue_free()

func _exit_tree():
	for enemy in affected_enemies:
		if is_instance_valid(enemy) and enemy.has_method(remove_slow):
			enemy.remove_slow()
