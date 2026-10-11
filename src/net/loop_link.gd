class_name LoopLink
extends NetLink
## Two links joined in memory, for tests: what one sends, the other receives a few
## polls later. Unreliable messages can be delayed with jitter and lost; reliable ones
## always arrive, in order.

var other: LoopLink = null
var lag := 0  ## polls before a message arrives
var jitter := 0  ## extra random polls on unreliable messages
var loss := 0.0  ## chance an unreliable message is lost
var rng := RandomNumberGenerator.new()
var _clock := 0
var _inbox: Array = []  ## [arrive_at, order, msg]
var _order := 0


static func pair(p_lag := 0, p_jitter := 0, p_loss := 0.0, p_seed := 1) -> Array:
	var a := LoopLink.new()
	var b := LoopLink.new()
	a.other = b
	b.other = a
	for l in [a, b]:
		l.lag = p_lag
		l.jitter = p_jitter
		l.loss = p_loss
		l.status = Status.CONNECTED
	a.rng.seed = p_seed
	b.rng.seed = p_seed + 1
	return [a, b]


func send(msg: Dictionary, reliable := false) -> void:
	if status != Status.CONNECTED or other == null or other.status != Status.CONNECTED:
		return
	if not reliable and loss > 0.0 and rng.randf() < loss:
		return
	var at := other._clock + lag + (0 if reliable or jitter == 0 else rng.randi_range(0, jitter))
	_order += 1
	# Through the encoder, as on the wire, so tests catch anything that won't survive it.
	other._inbox.append([at, _order, NetLink.decode(NetLink.encode(msg))])


func poll() -> Array:
	_clock += 1
	var out: Array = []
	var keep: Array = []
	_inbox.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	for m in _inbox:
		if int(m[0]) <= _clock:
			out.append(m[2])
		else:
			keep.append(m)
	_inbox = keep
	return out


func close() -> void:
	status = Status.CLOSED
	if other != null and other.status == Status.CONNECTED:
		other.status = Status.CLOSED
		other.error = "The other player left or the connection dropped"


## Cuts the connection without a goodbye, as when a cable is pulled.
func drop() -> void:
	status = Status.CLOSED
