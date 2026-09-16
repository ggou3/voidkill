extends Node3D

## Пул трейсеров выстрелов (TracerPool).
## Обеспечивает циклическое переиспользование предсозданных MeshInstance3D без аллокаций
## новых мешей и материалов в куче во время интенсивной стрельбы.

const POOL_SIZE: int = 64
const SPHERE_POOL_SIZE: int = 16

const STYLES: Dictionary = {
	&"bullet": {
		"r_core": 0.035,
		"r_outer": 0.16,
		"color": Color(0.8, 0.92, 1.0, 0.85),
		"duration": 0.25,
		"min_dist": 0.2,
		"has_impact_sphere": false,
	},
	&"pellet": {
		"r_core": 0.016,
		"r_outer": 0.0,
		"color": Color(1.0, 0.72, 0.25, 0.85),
		"duration": 0.12,
		"min_dist": 0.2,
		"has_impact_sphere": false,
	},
	&"syringe": {
		"r_core": 0.022,
		"r_outer": 0.0,
		"color": Color(0.25, 1.0, 0.4, 0.95),
		"duration": 0.18,
		"min_dist": 0.2,
		"has_impact_sphere": false,
	},
	&"needle": {
		"r_core": 0.012,
		"r_outer": 0.0,
		"color": Color(0.85, 0.95, 1.0, 0.9),
		"duration": 0.10,
		"min_dist": 0.2,
		"has_impact_sphere": false,
	},
	&"piston": {
		"r_core": 0.055,
		"r_outer": 0.0,
		"color": Color(0.85, 0.95, 1.0, 0.9),
		"duration": 0.16,
		"min_dist": 0.2,
		"has_impact_sphere": true,
		"sphere_radius": 0.25,
		"sphere_height": 0.5,
		"sphere_color": Color(0.6, 0.85, 1.0, 0.75),
		"sphere_scale": Vector3(1.6, 1.6, 1.6),
		"sphere_duration": 0.18,
	},
	&"piston_self": {
		"r_core": 0.07,
		"r_outer": 0.0,
		"color": Color(1.0, 0.65, 0.25, 0.9),
		"duration": 0.16,
		"min_dist": 0.2,
		"has_impact_sphere": true,
		"sphere_radius": 0.25,
		"sphere_height": 0.5,
		"sphere_color": Color(1.0, 0.75, 0.3, 0.8),
		"sphere_scale": Vector3(2.4, 2.4, 2.4),
		"sphere_duration": 0.18,
	},
	&"piercing": {
		"r_core": 0.065,
		"r_outer": 0.26,
		"color": Color(0.85, 0.95, 1.0, 0.95),
		"duration": 0.32,
		"min_dist": 0.2,
		"has_impact_sphere": true,
		"sphere_radius": 0.28,
		"sphere_height": 0.56,
		"sphere_color": Color(0.5, 0.85, 1.0, 0.9),
		"sphere_scale": Vector3(2.6, 2.6, 2.6),
		"sphere_duration": 0.24,
	},
	&"inflate": {
		"r_core": 0.038,
		"r_outer": 0.0,
		"color": Color(1.0, 0.12, 0.18, 0.95),
		"duration": 0.25,
		"min_dist": 0.2,
		"has_impact_sphere": false,
	},
	&"shrapnel": {
		"r_core": 0.012,
		"r_outer": 0.0,
		"color": Color(0.85, 0.95, 1.0, 0.9),
		"duration": 0.14,
		"min_dist": 0.15,
		"has_impact_sphere": false,
	},
	&"shrapnel_blood": {
		"r_core": 0.016,
		"r_outer": 0.0,
		"color": Color(1.0, 0.35, 0.25, 0.95),
		"duration": 0.14,
		"min_dist": 0.15,
		"has_impact_sphere": false,
	},
}

var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _sphere_materials: Dictionary = {}
var _sphere_meshes: Dictionary = {}

var _pool: Array[MeshInstance3D] = []
var _pool_tweens: Array[Tween] = []
var _pool_index: int = 0

var _sphere_pool: Array[MeshInstance3D] = []
var _sphere_tweens: Array[Tween] = []
var _sphere_index: int = 0

func _ready() -> void:
	# 1. Предсоздание неизменяемых материалов и мешей для каждого стиля
	for key in STYLES:
		var cfg: Dictionary = STYLES[key]
		_materials[key] = _build_material(cfg["color"])
		_meshes[key] = _build_tracer_mesh(cfg["r_core"], cfg.get("r_outer", 0.0))
		if cfg.get("has_impact_sphere", false):
			_sphere_materials[key] = _build_material(cfg["sphere_color"])
			_sphere_meshes[key] = _build_sphere_mesh(cfg["sphere_radius"], cfg["sphere_height"])
			
	# 2. Предсоздание пула MeshInstance3D для трейсеров (64 слота)
	for i in range(POOL_SIZE):
		var inst = MeshInstance3D.new()
		inst.name = "Tracer_%d" % i
		inst.top_level = true
		inst.visible = false
		add_child(inst)
		_pool.append(inst)
		_pool_tweens.append(null)
		
	# 3. Предсоздание пула MeshInstance3D для сфер попадания (16 слотов)
	for i in range(SPHERE_POOL_SIZE):
		var sinst = MeshInstance3D.new()
		sinst.name = "TracerSphere_%d" % i
		sinst.top_level = true
		sinst.visible = false
		add_child(sinst)
		_sphere_pool.append(sinst)
		_sphere_tweens.append(null)

func spawn_tracer(start: Vector3, end: Vector3, style: StringName = &"bullet", variant: bool = false) -> void:
	var dir = end - start
	var dist = dir.length()
	
	var style_key: StringName = style
	if variant:
		if style == &"piston":
			style_key = &"piston_self"
		elif style == &"shrapnel":
			style_key = &"shrapnel_blood"
			
	var cfg: Dictionary = STYLES.get(style_key, STYLES[&"bullet"])
	var min_dist: float = cfg.get("min_dist", 0.2)
	if dist < min_dist:
		return
		
	var forward = dir / dist
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.92:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	# --- 1. Активация трейсера из пула ---
	var idx = _pool_index
	_pool_index = (_pool_index + 1) % POOL_SIZE
	
	# Если слот ещё анимируется — прерываем старый tween и переиспользуем слот
	if _pool_tweens[idx] and _pool_tweens[idx].is_valid():
		_pool_tweens[idx].kill()
		
	var mesh_inst = _pool[idx]
	mesh_inst.mesh = _meshes[style_key]
	mesh_inst.material_override = _materials[style_key]
	mesh_inst.global_transform = Transform3D(Basis(right, up, forward * dist), start)
	mesh_inst.transparency = 0.0
	mesh_inst.visible = true
	
	var tween = create_tween()
	_pool_tweens[idx] = tween
	tween.tween_property(mesh_inst, "transparency", 1.0, cfg["duration"]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): mesh_inst.visible = false)
	
	# --- 2. Вспышка / Сфера попадания (piston / piercing) ---
	if cfg.get("has_impact_sphere", false):
		_spawn_impact_sphere(end, style_key, cfg)

func _spawn_impact_sphere(pos: Vector3, style_key: StringName, cfg: Dictionary) -> void:
	var s_idx = _sphere_index
	_sphere_index = (_sphere_index + 1) % SPHERE_POOL_SIZE
	
	if _sphere_tweens[s_idx] and _sphere_tweens[s_idx].is_valid():
		_sphere_tweens[s_idx].kill()
		
	var sphere_inst = _sphere_pool[s_idx]
	sphere_inst.mesh = _sphere_meshes[style_key]
	sphere_inst.material_override = _sphere_materials[style_key]
	sphere_inst.global_position = pos
	sphere_inst.scale = Vector3.ONE
	sphere_inst.transparency = 0.0
	sphere_inst.visible = true
	
	var target_scale: Vector3 = cfg["sphere_scale"]
	var s_dur: float = cfg["sphere_duration"]
	
	var stween = create_tween().set_parallel(true)
	_sphere_tweens[s_idx] = stween
	stween.tween_property(sphere_inst, "scale", target_scale, s_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	stween.tween_property(sphere_inst, "transparency", 1.0, s_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	stween.chain().tween_callback(func(): sphere_inst.visible = false)

func _build_tracer_mesh(r_core: float, r_outer: float = 0.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	_add_quad_vertices(st, r_core)
	if r_outer > 0.0:
		_add_quad_vertices(st, r_outer)
		
	return st.commit()

func _add_quad_vertices(st: SurfaceTool, r: float) -> void:
	# Горизонтальный квад (X = [-r, +r], Y = 0, Z = [0, 1])
	st.add_vertex(Vector3(-r, 0.0, 0.0))
	st.add_vertex(Vector3( r, 0.0, 1.0))
	st.add_vertex(Vector3(-r, 0.0, 1.0))
	
	st.add_vertex(Vector3(-r, 0.0, 0.0))
	st.add_vertex(Vector3( r, 0.0, 0.0))
	st.add_vertex(Vector3( r, 0.0, 1.0))
	
	# Вертикальный квад (X = 0, Y = [-r, +r], Z = [0, 1])
	st.add_vertex(Vector3(0.0, -r, 0.0))
	st.add_vertex(Vector3(0.0,  r, 1.0))
	st.add_vertex(Vector3(0.0, -r, 1.0))
	
	st.add_vertex(Vector3(0.0, -r, 0.0))
	st.add_vertex(Vector3(0.0,  r, 0.0))
	st.add_vertex(Vector3(0.0,  r, 1.0))

func _build_sphere_mesh(radius: float, height: float) -> SphereMesh:
	var smesh = SphereMesh.new()
	smesh.radius = radius
	smesh.height = height
	return smesh

func _build_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat
