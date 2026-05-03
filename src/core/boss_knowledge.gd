extends RefCounted
class_name BossKnowledge

const DEFAULT_STALE_SECONDS := 75.0

var stale_seconds := DEFAULT_STALE_SECONDS
var observations: Array[Dictionary] = []
var zone_observations: Dictionary = {}
var worker_observations: Dictionary = {}

func add_observation(zone_id: String, facts: Array[String], confidence: float, timestamp: float) -> void:
	var entry := {
		"zone": zone_id,
		"timestamp": timestamp,
		"confidence": clampf(confidence, 0.0, 1.0),
		"facts": facts.duplicate(),
	}
	observations.append(entry)
	zone_observations[zone_id] = entry
	while observations.size() > 40:
		observations.pop_front()

func add_worker_observation(worker_name: String, inferred_facts: Array[String], confidence: float, timestamp: float) -> void:
	if worker_name.is_empty():
		return
	worker_observations[worker_name] = {
		"worker": worker_name,
		"timestamp": timestamp,
		"confidence": clampf(confidence, 0.0, 1.0),
		"facts": inferred_facts.duplicate(),
	}

func get_latest_observations(limit: int = 5) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(0, observations.size() - limit)
	for i in range(start, observations.size()):
		result.append(observations[i])
	return result

func get_known_zone_ids() -> PackedStringArray:
	var known := PackedStringArray()
	for key in zone_observations.keys():
		known.append(String(key))
	known.sort()
	return known

func get_stale_zone_ids(route_zone_ids: PackedStringArray, now: float) -> PackedStringArray:
	var stale := PackedStringArray()
	for zone_id in route_zone_ids:
		var entry: Dictionary = zone_observations.get(zone_id, {})
		if entry.is_empty() or _is_stale(entry, now):
			stale.append(zone_id)
	return stale

func get_prompt_memory(route_zone_ids: PackedStringArray, now: float) -> Dictionary:
	var zones: Array[Dictionary] = []
	for zone_id in route_zone_ids:
		var entry: Dictionary = zone_observations.get(zone_id, {})
		if entry.is_empty():
			zones.append({
				"zone": zone_id,
				"status": "unknown",
				"facts": [],
			})
			continue
		var age := maxf(0.0, now - float(entry.get("timestamp", now)))
		zones.append({
			"zone": zone_id,
			"status": "stale" if age >= stale_seconds else "known",
			"age_seconds": roundi(age),
			"confidence": float(entry.get("confidence", 0.0)),
			"facts": entry.get("facts", []),
		})

	var workers: Array[Dictionary] = []
	for worker_name in worker_observations.keys():
		var worker_entry: Dictionary = worker_observations[worker_name]
		var worker_age := maxf(0.0, now - float(worker_entry.get("timestamp", now)))
		workers.append({
			"worker": String(worker_name),
			"status": "stale" if worker_age >= stale_seconds else "known",
			"age_seconds": roundi(worker_age),
			"confidence": float(worker_entry.get("confidence", 0.0)),
			"inferred_facts": worker_entry.get("facts", []),
		})
	workers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("worker", "")).naturalnocasecmp_to(String(b.get("worker", ""))) < 0
	)

	return {
		"zones": zones,
		"workers": workers,
		"latest_observations": get_latest_observations(6),
	}

func _is_stale(entry: Dictionary, now: float) -> bool:
	return now - float(entry.get("timestamp", now)) >= stale_seconds
