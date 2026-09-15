extends Area3D

@export var speed: float = 18.0
@export var damage: int = 12
@export var lifetime: float = 6.0

var direction: Vector3 = Vector3.FORWARD
var shooter: Node = null
var is_destroyed: bool = false
var is_deflected: bool = false

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
		if is_deflected:
			# Отражённый снаряд НЕ сталкивается с игроком
			var player = get_tree().get_first_node_in_group("player")
			if is_instance_valid(player) and player is CollisionObject3D:
				exclude.append(player.get_rid())
		else:
			# Обычный вражеский снаряд игнорирует стрелка и других врагов
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
	if is_destroyed:
		return
	if is_deflected:
		if body.is_in_group("player"):
			return
	else:
		if body == shooter or body.is_in_group("enemy"):
			return
	_handle_impact(body, global_position)

func _on_area_entered(area: Area3D):
	if is_destroyed:
		return
	if is_deflected:
		if area.is_in_group("enemy") or (area.get_parent() and area.get_parent().is_in_group("enemy")):
			var target = area if area.is_in_group("enemy") else area.get_parent()
			_handle_impact(target, global_position)

func deflect(new_dir: Vector3, new_speed: float = 27.0, new_damage: int = 24):
	if is_destroyed or is_deflected:
		return
	is_deflected = true
	direction = new_dir.normalized()
	speed = new_speed if new_speed > 0.0 else speed * 1.5
	damage = new_damage if new_damage > 0 else damage * 2
	lifetime = 6.0
	
	# Смещаем снаряд чуть вперед по новому направлению, чтобы он не застрял рядом с игроком
	global_position += direction * 0.45
	
	# Переводим в группу отражённых снарядов игрока
	remove_from_group("enemy_projectile")
	add_to_group("player_projectile")
	
	_apply_deflected_visuals()
	print("[DEFLECT] Projectile parried! New speed: %.1f, New dmg: %d, Dir: %s" % [speed, damage, direction])

func _apply_deflected_visuals():
	var mesh_inst: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if is_instance_valid(mesh_inst):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.85, 1.0, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.95, 1.0, 1.0)
		mat.emission_energy_multiplier = 4.5
		mesh_inst.material_override = mat
		
	var core_mesh: MeshInstance3D = get_node_or_null("CoreMesh")
	if is_instance_valid(core_mesh):
		var core_mat = StandardMaterial3D.new()
		core_mat.albedo_color = Color(0.9, 1.0, 1.0, 1.0)
		core_mat.emission_enabled = true
		core_mat.emission = Color(1.0, 1.0, 1.0, 1.0)
		core_mat.emission_energy_multiplier = 6.0
		core_mesh.material_override = core_mat
		
	var light: OmniLight3D = get_node_or_null("OmniLight3D")
	if is_instance_valid(light):
		light.light_color = Color(0.2, 0.9, 1.0, 1.0)
		light.light_energy = 2.2

func _handle_impact(collider: Node, hit_pos: Vector3):
	if is_destroyed:
		return
	is_destroyed = true
	
	if is_instance_valid(collider):
		var target: Node = collider
		if is_deflected:
			var enemy_target: Node = null
			if target.is_in_group("enemy") and target.has_method("take_damage"):
				enemy_target = target
			elif target.get_parent() and target.get_parent().is_in_group("enemy") and target.get_parent().has_method("take_damage"):
				enemy_target = target.get_parent()
				
			if enemy_target:
				var impact_impulse = direction * 15.0 + Vector3.UP * 2.5
				enemy_target.take_damage(damage, impact_impulse, hit_pos, false, false, false, false, -1, "deflect")
		else:
			if target.is_in_group("player") or target.has_method("take_damage"):
				var impact_impulse = direction * 5.0 + Vector3.UP * 1.5
				target.take_damage(damage, impact_impulse, hit_pos)
			elif target.get_parent() and (target.get_parent().is_in_group("player") or target.get_parent().has_method("take_damage")):
				var impact_impulse = direction * 5.0 + Vector3.UP * 1.5
				target.get_parent().take_damage(damage, impact_impulse, hit_pos)
				
	_spawn_impact_vfx(hit_pos)
	queue_free()

func _spawn_impact_vfx(hit_pos: Vector3):
	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if not scene_root:
		return
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	flash.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.9, 1.0, 0.8) if is_deflected else Color(1.0, 0.4, 0.1, 0.8)
	flash.material_override = mat
	scene_root.add_child(flash)
	flash.global_position = hit_pos
	var tween = flash.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3(2.5, 2.5, 2.5), 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)
