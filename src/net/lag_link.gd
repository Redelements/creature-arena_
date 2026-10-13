class_name LagLink
extends NetLink
## Wraps a real link and holds back the input stream to fake a slower connection, so
## rollback can be felt and tested on a LAN or one computer:  --net-lag=6 (frames)
## --net-loss=0.1. Control messages pass straight through.

var inner: NetLink
var lag := 0
var jitter := 0
var loss := 0.0
var rng := RandomNumberGenerator.new()
var _held: Array = []  ## [send_at, msg]
var _clock := 0


func _init(p_inner: NetLink, p_lag := 0, p_loss := 0.0, p_jitter := 0) -> void:
	inner = p_inner
	lag = p_lag
	loss = p_loss
	jitter = p_jitter
	status = inner.status
	rng.seed = Time.get_ticks_usec()


func send(msg: Dictionary, reliable := false) -> void:
	if reliable:
		inner.send(msg, true)
		return
	if loss > 0.0 and rng.randf() < loss:
		return
	_held.append([_clock + lag + (rng.randi_range(0, jitter) if jitter > 0 else 0), msg])


func poll() -> Array:
	_clock += 1
	var keep: Array = []
	for h in _held:
		if int(h[0]) <= _clock:
			inner.send(h[1], false)
		else:
			keep.append(h)
	_held = keep
	var out := inner.poll()
	status = inner.status
	error = inner.error
	return out


func flush() -> void:
	inner.flush()


func rtt_ms() -> float:
	return inner.rtt_ms() + 2.0 * lag * 1000.0 / SimDefs.TICK_RATE


func close() -> void:
	inner.close()
	status = Status.CLOSED
