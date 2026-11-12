extends Node3D
## Mission "Kräne": boeiger Seewind fuer die Ballistik (Level.sniper_wind()) und sichtbare Hinweise:
## Windsaecke (game/levels/windsock.gd) an den Lichtmasten/am Kran richten sich aus, fuellen sich je nach
## Staerke und flattern, Regen treibt mit (Weather.wind).
## Grundwind von Westsued (blaest nach Ostnord), Boeen aus Rauschen: +-35 % Staerke, +-15 Grad Richtung.

const BASE_DIR := Vector3(0.92, 0.0, -0.38)
const BASE_SPEED := 4.2            ## m/s -> auf 250 m gut 1 mil Abdrift
const GUST_AMP := 0.35
const GUST_DIR := 0.26
const Windsock := preload("res://game/levels/windsock.gd")

var weather: Node = null
var _t: float = 0.0
var _noise := FastNoiseLite.new()
var _cur := BASE_DIR.normalized() * BASE_SPEED
var _socks: Array = []

func _ready() -> void:
	_noise.seed = 4711
	_noise.frequency = 0.05

func current() -> Vector3:
	return _cur

func strength() -> float:
	return _cur.length()

func _process(delta: float) -> void:
	_t += delta
	var g := _noise.get_noise_1d(_t * 6.0)
	var d := _noise.get_noise_1d(_t * 4.0 + 300.0)
	var dir := BASE_DIR.normalized().rotated(Vector3.UP, d * GUST_DIR * 2.0)
	_cur = dir * BASE_SPEED * (1.0 + g * GUST_AMP * 2.0)
	if weather != null and is_instance_valid(weather):
		weather.set("wind", _cur * 0.9)
	for sk in _socks:
		if is_instance_valid(sk):
			(sk as Node).call("set_wind", _cur, delta)

## Windsack (game/levels/windsock.gd) an einem Lichtmast/am Kran. base = Weltpunkt der Befestigung
## (Mastschelle bzw. Fusspunkt), opts siehe Windsock.setup().
func add_sock(parent: Node3D, base: Vector3, opts: Dictionary = {}) -> Node3D:
	var sk: Node3D = Windsock.new()
	sk.name = "Windsock"
	sk.call("setup", opts)
	parent.add_child(sk)
	sk.global_position = base
	sk.call("set_wind", _cur, 0.0)
	_socks.append(sk)
	return sk
