extends Area3D

@export var speed: float = 14.0
@export var damage: int = 12
@export var lifetime: float = 6.0

var direction: Vector3 = Vector3.FORWARD
var shooter: Node = null
var is_destroyed: bool = false

func _ready():
	add_to_group("enemy_projectile")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float):
	if is_destroyed:
		return
		
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
		
	var move_dist = speed * delta
	var prev_pos = global_position
	var next_pos = prev_pos + direction * move_dist
	
	# Непрерывный raycast sweep от prev_pos к next_pos (гарантирует отсутствие туннелирования)
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(prev_pos, next_pos)
		var exclude: Array[RID] = [get_rid()]
		if is_instance_valid(shooter) and shooter is CollisionObject3D:
			exclude.append(shooter.get_rid())
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy is CollisionObject3D:
				exclude.append(enemy.get_rid())
		query.exclude = exclude
		query.collide_with_bodies = true
		query.collide_with_areas = false
		
		var hit = space_state.intersect_ray(query)
		if not hit.is_empty():
			_handle_impact(hit.collider, hit.position)
			return
			
	global_position = next_pos

func _on_body_entered(body: Node3D):
	if is_destroyed or body == shooter or body.is_in_group("enemy"):
		return
	_handle_impact(body, global_position)

func _on_area_entered(area: Area3D):
	# Будет задействовано в следующем шаге при отбивании/парировании melee-ударом игрока
	if is_destroyed:
		return
	if area.is_in_group("player_melee"):
		pass

func _handle_impact(collider: Node, hit_pos: Vector3):
	if is_destroyed:
		return
	is_destroyed = true
	
	if is_instance_valid(collider):
		var target: Node = collider
		if target.is_in_group("player") or target.has_method("take_damage"):
			var impact_impulse = direction * 5.0 + Vector3.UP * 1.5
			target.take_damage(damage, impact_impulse, hit_pos)
		elif target.get_parent() and (target.get_parent().is_in_group("player") or target.get_parent().has_method("take_damage")):
			var impact_impulse = direction * 5.0 + Vector3.UP * 1.5
			target.get_parent().take_damage(damage, impact_impulse, hit_pos)
		# При попадании в статичную геометрию — уничтожается без эффекта
	
	queue_free()
