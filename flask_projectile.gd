extends CharacterBody3D

const GRAVITY: float = 24.0
var flask_pool_scene = preload(res://flask_pool.tscn)
var blood_splatter_scene = preload(res://blood_splatter.tscn)

var lifetime: float = 6.0
var has_shattered: bool = false

func _ready():
	# Игнорируем коллизии с игроком
	var player = get_tree().get_first_node_in_group(player)
	if is_instance_valid(player):
		add_collision_exception_with(player)

func launch(initial_velocity: Vector3):
	velocity = initial_velocity

func _physics_process(delta: float):
	if has_shattered:
		return
		
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
		
	velocity.y -= GRAVITY * delta
	
	# Вращение колбы в полете
	rotate_x(14.0 * delta)
	rotate_y(8.0 * delta)
	
	var collision = move_and_collide(velocity * delta)
	if collision:
		_shatter(collision.get_position(), collision.get_normal())

func _shatter(hit_pos: Vector3, hit_normal: Vector3):
	has_shattered = true
	set_physics_process(false)
	
	AudioManager.play_sound(flask_splash)
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if scene_root:
		# Всплеск крови и осколков
		if blood_splatter_scene:
			var splatter = blood_splatter_scene.instantiate()
			splatter.amount = 55
			splatter.scale = Vector3(1.6, 1.6, 1.6)
			var pmat = splatter.process_material.duplicate()
			pmat.spread = 75.0
			pmat.initial_velocity_min = 4.0
			pmat.initial_velocity_max = 9.0
			splatter.process_material = pmat
			scene_root.add_child(splatter)
			splatter.global_position = hit_pos
			if hit_normal != Vector3.ZERO:
				splatter.look_at(hit_pos + hit_normal, Vector3.UP)
				
		# Поиск поверхности земли для лужи крови
		var pool_pos = hit_pos
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(hit_pos + Vector3.UP * 0.25, hit_pos + Vector3.DOWN * 25.0)
		# Исключаем игрока и себя
		var player = get_tree().get_first_node_in_group(player)
		var excl = [self]
		if is_instance_valid(player):
			excl.append(player)
		query.exclude = excl
		
		var ray_res = space_state.intersect_ray(query)
		if not ray_res.is_empty():
			pool_pos = ray_res.position + Vector3(0, 0.02, 0)
			
		if flask_pool_scene:
			var pool = flask_pool_scene.instantiate()
			scene_root.add_child(pool)
			pool.global_position = pool_pos
			
	queue_free()
