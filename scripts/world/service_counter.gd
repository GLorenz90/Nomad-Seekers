class_name ServiceCounter
extends Node3D
## A clerk's spot at one of Nomad-2's counters (Part 10): stand in front of
## it and press A to open the shop, the bank or the Guild. Sits in the
## "interactables" group like teleporters and items.
##
## Shops roll their stock once per visit (the first time you open them), so it
## changes every time you arrive in Nomad-2 (PSO rolls its arms shop each time
## you enter Pioneer 2), at tiers for the Seeker's level (Part 11).

enum Service { WEAPONS, ARMOR, CURATIVES, BANK, GUILD }

const INTERACT_RANGE := 2.2
const NAMES := ["Weapons shop", "Armor shop", "Curatives", "Bank", "Guild"]

@export var service: Service = Service.WEAPONS

var menu: CounterMenu
var stock_weapons: Array[WeaponData] = []
var stock_armor: Array[ArmorData] = []
var stock_units: Array[StringName] = []
var rng := RandomNumberGenerator.new()
var _rolled := false


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("service_counters")
	rng.randomize()


## New stock for this visit (shops only), for a Seeker of `level`.
func roll_stock(level: int = 1) -> void:
	_rolled = true
	match service:
		Service.WEAPONS:
			stock_weapons = Prices.roll_weapon_stock(rng, level)
		Service.ARMOR:
			stock_armor = Prices.roll_armor_stock(rng, level)
			stock_units = Prices.roll_unit_stock(rng, level)


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
	if not _rolled:
		roll_stock(seeker.save.character.level() if seeker.save else 1)
	match service:
		Service.BANK:
			menu = BankMenu.new()
		Service.GUILD:
			menu = GuildMenu.new()
		_:
			var shop := ShopMenu.new()
			shop.setup(int(service) as ShopMenu.Kind, stock_weapons, stock_armor, stock_units)
			menu = shop
	seeker.ui_root().add_child(menu)
	menu.open(seeker)
	return menu
