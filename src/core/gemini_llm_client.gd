extends Node
class_name GeminiLLMClient

signal action_received(action: Dictionary, raw_json: String)
signal request_failed(reason: String)

const CONFIG_PATH := "res://config/llm.local.json"
const DEFAULT_MODEL := "gemini-flash-latest"
const GEMINI_ENDPOINT := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

var provider := "gemini"
var model := DEFAULT_MODEL
var api_key := ""
var timeout_seconds := 12.0
var enabled := false
var raw_debug_enabled := false

var _http_request: HTTPRequest
var _pending := false

func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "GeminiHTTPRequest"
	_http_request.use_threads = true
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)
	reload_config()

func reload_config() -> void:
	provider = "gemini"
	model = DEFAULT_MODEL
	api_key = ""
	timeout_seconds = 12.0
	enabled = false
	raw_debug_enabled = false

	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		request_failed.emit("Could not read LLM config.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		request_failed.emit("LLM config is invalid JSON.")
		return
	var cfg := parsed as Dictionary
	provider = String(cfg.get("provider", "gemini")).to_lower()
	model = String(cfg.get("model", DEFAULT_MODEL))
	api_key = String(cfg.get("api_key", ""))
	timeout_seconds = maxf(float(cfg.get("timeout_seconds", 12.0)), 1.0)
	enabled = bool(cfg.get("enabled", false)) and provider == "gemini" and not api_key.is_empty()
	raw_debug_enabled = bool(cfg.get("debug_raw_json", false))

func is_available() -> bool:
	return enabled and not _pending

func request_action(prompt: String) -> bool:
	if not enabled:
		request_failed.emit("LLM disabled or config missing.")
		return false
	if _pending:
		return false

	_pending = true
	_http_request.timeout = timeout_seconds
	var url := GEMINI_ENDPOINT % model.uri_encode()
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-goog-api-key: %s" % api_key,
	])
	var body := JSON.stringify({
		"contents": [{
			"role": "user",
			"parts": [{"text": prompt}]
		}],
		"generationConfig": {
			"temperature": 0.35,
			"response_mime_type": "application/json",
		}
	})
	var error := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_pending = false
		request_failed.emit("Gemini request failed to start: %s" % error_string(error))
		return false
	return true

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Gemini request failed: result %d." % result)
		return
	if response_code < 200 or response_code >= 300:
		request_failed.emit("Gemini HTTP %d." % response_code)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		request_failed.emit("Gemini returned invalid JSON envelope.")
		return
	var envelope: Dictionary = parsed as Dictionary
	var raw_text: String = _extract_candidate_text(envelope)
	if raw_text.is_empty():
		request_failed.emit("Gemini response contained no action text.")
		return
	var action: Variant = JSON.parse_string(raw_text)
	if not (action is Dictionary):
		request_failed.emit("Gemini action was not valid JSON.")
		return
	action_received.emit(action as Dictionary, raw_text)

func _extract_candidate_text(envelope: Dictionary) -> String:
	var candidates: Variant = envelope.get("candidates", [])
	if not (candidates is Array) or candidates.is_empty():
		return ""
	var first: Variant = (candidates as Array)[0]
	if not (first is Dictionary):
		return ""
	var content: Variant = (first as Dictionary).get("content", {})
	if not (content is Dictionary):
		return ""
	var parts: Variant = (content as Dictionary).get("parts", [])
	if not (parts is Array) or parts.is_empty():
		return ""
	var text: String = ""
	for part in parts as Array:
		if part is Dictionary:
			text += String((part as Dictionary).get("text", ""))
	return text.strip_edges()
