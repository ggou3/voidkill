class_name BPMSystem
extends Node

## BPM-система (сердцебиение) и боевой моментум — единственный владелец BPM.
## Рост BPM от убийств/хедшотов, пассивный спад, штраф за урон, тиры (CALM/PUMPING/SURGING/OVERDRIVE),
## производные правила: доля BPM для движения, снижение входящего урона, бесконечные патроны в OVERDRIVE.

# --- BPM SYSTEM (Сердцебиение) & COMBAT MOMENTUM ---
const MIN_BPM: float = 50.0
const MAX_BPM: float = 200.0
var bpm: float = MIN_BPM
var time_since_bpm_gain: float = 0.0
var last_kill_weapon: String = ""

var combat_momentum: float = 1.0
var time_since_momentum_gain: float = 0.0

signal bpm_changed(value: float)
signal tier_changed(tier: GameTypes.BPMTier)
signal momentum_changed(value: float)
signal hud_popup_requested(text: String)

var player: Player

func setup(p: Player) -> void:
	player = p

func _process(delta):
	# BPM: прогрессивный пассивный спад при отсутствии событий роста:
	# decay_rate = lerp(1.5, 7.0, (bpm - 50) / 150), задержка 2.0с (или 5.0с на пике bpm >= 195)
	time_since_bpm_gain += delta
	var decay_delay: float = 5.0 if bpm >= 195.0 else 2.0
	if time_since_bpm_gain >= decay_delay and bpm > MIN_BPM:
		var bpm_ratio: float = clampf((bpm - MIN_BPM) / (MAX_BPM - MIN_BPM), 0.0, 1.0)
		var decay_rate: float = lerp(1.5, 7.0, bpm_ratio)
		var old_tier = get_bpm_tier()
		bpm = max(MIN_BPM, bpm - decay_rate * delta)
		bpm_changed.emit(bpm)
		var new_tier = get_bpm_tier()
		if new_tier != old_tier:
			tier_changed.emit(new_tier)

	# Combat Momentum: источники роста в реальном времени
	var gained_momentum_continuous: bool = false
	if is_instance_valid(player):
		# 1. Активный кровавый сёрф (слайд по луже крови): +0.04 к моментуму/сек
		if player.is_sliding and player.is_on_blood:
			add_combat_momentum(0.04 * delta)
			gained_momentum_continuous = true

		# 2. Нахождение в воздухе на высокой скорости (не coyote-time, скорость >= WALK_SPEED): +0.015 к моментуму/сек
		var horiz_spd = Vector2(player.velocity.x, player.velocity.z).length()
		var in_air_speed = not player.is_on_floor() and player.coyote_timer <= 0.0 and horiz_spd >= player.WALK_SPEED
		if in_air_speed:
			add_combat_momentum(0.015 * delta)
			gained_momentum_continuous = true

	if not gained_momentum_continuous:
		time_since_momentum_gain += delta

	# Combat Momentum: пассивный спад при отсутствии приращений за последние 1.5 секунды: -0.1/сек (не ниже 1.0)
	if time_since_momentum_gain >= 1.5 and combat_momentum > 1.0:
		combat_momentum = max(1.0, combat_momentum - 0.1 * delta)
		momentum_changed.emit(combat_momentum)

# --- BPM API ---

func add_combat_momentum(amount: float):
	if amount <= 0.0:
		return
	combat_momentum = clampf(combat_momentum + amount, 1.0, 2.0)
	time_since_momentum_gain = 0.0
	momentum_changed.emit(combat_momentum)

func force_max_bpm():
	var old_tier = get_bpm_tier()
	bpm = MAX_BPM
	time_since_bpm_gain = 0.0
	bpm_changed.emit(bpm)
	var new_tier = get_bpm_tier()
	if new_tier != old_tier:
		tier_changed.emit(new_tier)
	GameTypes.debug_log(&"bpm", "[DEBUG] Max BPM (%.1f) forced via 'T' key! Peak delay set to 5.0s." % MAX_BPM)

func add_bpm(amount: float):
	if amount <= 0.0:
		return
	var old_tier = get_bpm_tier()
	bpm = clamp(bpm + amount, MIN_BPM, MAX_BPM)
	time_since_bpm_gain = 0.0
	bpm_changed.emit(bpm)
	var new_tier = get_bpm_tier()
	if new_tier != old_tier:
		tier_changed.emit(new_tier)

func record_kill_bpm(weapon_type: String, is_shockwave: bool = false) -> float:
	var base_bpm: float = 8.0 if is_shockwave else 5.5
	var bonus_bpm: float = 0.0

	# Бонус за разнообразие (+2 BPM), если оружие отличается от предыдущего убийства
	if last_kill_weapon != "" and weapon_type != "" and weapon_type != last_kill_weapon:
		bonus_bpm = 2.0
		GameTypes.debug_log(&"bpm", "[BPM VARIETY BONUS] +2.0 BPM! Killer: '%s' != previous: '%s' (Total: +%.1f BPM)" % [
			weapon_type, last_kill_weapon, base_bpm + bonus_bpm
		])
		_show_combo_popup(bonus_bpm)
	elif last_kill_weapon != "" and weapon_type == last_kill_weapon:
		GameTypes.debug_log(&"bpm", "[BPM KILL] Same weapon '%s' (Total: +%.1f BPM, no variety bonus)" % [weapon_type, base_bpm])
	else:
		GameTypes.debug_log(&"bpm", "[BPM KILL] First kill with '%s' (Total: +%.1f BPM)" % [weapon_type, base_bpm])

	if weapon_type != "":
		last_kill_weapon = weapon_type

	var total_bpm = (base_bpm + bonus_bpm) * combat_momentum
	if combat_momentum > 1.0:
		GameTypes.debug_log(&"bpm", "[COMBAT MOMENTUM] x%.2f applied: +%.1f -> +%.1f BPM" % [
			combat_momentum, base_bpm + bonus_bpm, total_bpm
		])
	add_bpm(total_bpm)
	return total_bpm

func _show_combo_popup(bonus_amount: float):
	hud_popup_requested.emit("★ VARIETY +%d ★" % int(round(bonus_amount)))

func drop_bpm_on_damage():
	# Резкое падение при получении урона игроком: -25% от текущего значения (не фиксированное число)
	var old_tier = get_bpm_tier()
	var drop = bpm * 0.25
	bpm = max(MIN_BPM, bpm - drop)
	bpm_changed.emit(bpm)
	var new_tier = get_bpm_tier()
	if new_tier != old_tier:
		tier_changed.emit(new_tier)
	GameTypes.debug_log(&"bpm", "[BPM] Damage penalty: -%.1f -> %.1f (%s)" % [drop, bpm, GameTypes.tier_to_string(get_bpm_tier())])

func get_bpm_tier() -> GameTypes.BPMTier:
	if bpm < 90.0:
		return GameTypes.BPMTier.CALM
	elif bpm < 140.0:
		return GameTypes.BPMTier.PUMPING
	elif bpm < 180.0:
		return GameTypes.BPMTier.SURGING
	else:
		return GameTypes.BPMTier.OVERDRIVE

## Доля BPM в диапазоне [50..200] -> [0..1] (скейлинг движения)
func get_bpm_ratio() -> float:
	return clampf((bpm - 50.0) / 150.0, 0.0, 1.0)

## Снижение входящего урона игроку от BPM: 0% .. 30%
func get_bpm_damage_reduction() -> float:
	return lerp(0.0, 0.30, get_bpm_ratio())

## Бесконечные патроны в тире OVERDRIVE
func has_infinite_ammo() -> bool:
	return get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE
