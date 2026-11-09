class_name ServiceCounter
extends Node3D
## A clerk's spot at one of Nomad-2's counters (Part 10): stand in front of
## it and press A to open the shop, the bank or the Guild. Sits in the
## "interactables" group like teleporters and items.
##
## Shops roll their stock when the hub loads, so it changes every time you
## arrive in Nomad-2 (PSO rolls its arms shop each time you enter Pioneer 2).

enum Service { WEAPONS, ARMOR, CURATIVES, BANK, GUILD }

const INTERACT_RANGE := 2.2
const NAMES := ["Weapons shop", "Armor shop", "Curatives", "Bank", "Guild"]

@export var service: Service = Service.WEAPONS

var menu: CounterMenu
var stock_weapons: Array[WeaponData] = []
var stock_armor: Array[ArmorData] = []
var stock_units: Array[StringName] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("service_counters")
	rng.randomize()
	roll_stock()


## New stock for this visit (shops only).
func roll_stock() -> void:
	match service:
		Service.WEAPONS:
			stock_weapons = Prices.roll_weapon_stock(rng)
		Service.ARMOR:
			stock_armor = Prices.roll_armor_stock(rng)
			stock_units = Prices.roll_unit_stock(rng)


func display_name() -> String:
	return NAMES[service]


func interact_point() -> Vector3:
	return global_position


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact(seeker: Player) -> bool:
	return seeker.save != null and not is_instance_valid(menu)


func interact_prompt() -> String:
	match service:
		Service.BANK:
			return "Bank"
		Service.GUILD:
			return "Guild counter"
	return "Shop: %s" % display_name()


func interact(seeker: Player) -> void:
	open_menu(seeker)


## Opens this counter's menu for the Seeker (also used by tests).
func open_menu(seeker: Player) -> CounterMenu:
	match service:
		Service.BANK:
			menu = BankMenu.new()
		Service.GUILD:
			menu = GuildMenu.new()
		_:
			var shop := ShopMenu.new()
			shop.setup(int(service) as ShopMenu.Kind, stock_weapons, stock_armor, stock_units)
			menu = shop
	get_tree().root.add_child(menu)
	menu.open(seeker)
	return menu
