class_name ShopMenu
extends CounterMenu
## Nomad-2's shops (Part 10): weapons, armor (pieces and augments) and
## curatives. Buy from the stock (each listing can be bought again and
## again, like PSO); any shop buys anything from your pack back (Prices).
## Palette weapons and worn armor have to come off before they can be sold.

enum Kind { WEAPONS, ARMOR, CURATIVES }

var kind: Kind = Kind.WEAPONS
var weapons: Array[WeaponData] = []
var armors: Array[ArmorData] = []
var units: Array[StringName] = []


## Sets the shop up before open() (ServiceCounter).
func setup(shop: Kind, stock_weapons: Array[WeaponData], stock_armor: Array[ArmorData],
		stock_units: Array[StringName]) -> void:
	kind = shop
	weapons = stock_weapons
	armors = stock_armor
	units = stock_units
	title = ["Weapons shop", "Armor shop", "Curatives"][shop]
	greeting = ["Welcome! Our weapons change every time you come back aboard.",
		"Welcome! Armor and augments, fresh stock every time you're back aboard.",
		"Welcome! Gels, cells, salts and scanners."][shop]


func commands() -> Array:
	return [["Buy", "buy"], ["Sell", "sell"]]


func items_for(command_id: String) -> Array[Dictionary]:
	return _buy_items() if command_id == "buy" else _sell_items()


# --- Buying ----------------------------------------------------------------------------

func _buy_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var job := player.combat.job_code
	match kind:
		Kind.WEAPONS:
			for w in weapons:
				var price := Prices.weapon_price(w)
				var item := _gear_item("%s   %s Oro" % [w.display_name, _num(price)],
					ItemText.weapon_detail(w, job, player.combat.stats), price, func() -> String:
						return "" if save().take_weapon(w.duplicate()) else "full")
				if not w.can_be_used_by(job) or w.requirement_error(player.combat.stats) != "":
					item.color = Color(0.6, 0.6, 0.65)
				list.append(item)
		Kind.ARMOR:
			for a in armors:
				var price := Prices.armor_price(a)
				var item := _gear_item("%s (%s, %d slot%s)   %s Oro" % [a.display_name, ArmorData.SLOT_NAMES[a.slot],
					a.slots, "" if a.slots == 1 else "s", _num(price)], ItemText.armor_detail(a, save().character, false),
					price, func() -> String:
						var copy := a.duplicate(true) as ArmorData
						copy.ensure_units()
						return "" if save().take_armor(copy) else "full")
				if ArmorBook.equip_error(save().character, a) != "":
					item.color = Color(0.6, 0.6, 0.65)
				list.append(item)
			for id in units:
				var price := Prices.unit_price(id)
				var item := _gear_item("%s   %s Oro" % [UnitBook.display_name(id), _num(price)],
					"%s\n%s\nGoes in an augment slot of worn armor." % [UnitBook.display_name(id), UnitBook.describe(id)],
					price, func() -> String: return "" if save().take_unit(id) else "full")
				item.color = Color(0.95, 0.95, 0.6)
				list.append(item)
		Kind.CURATIVES:
			for id in Prices.CURATIVES:
				list.append(_curative_item(id))
	return list


## One piece of gear for `price`; `give` puts a copy in the pack ("" or "full").
func _gear_item(text: String, detail: String, price: int, give: Callable) -> Dictionary:
	var item := {"text": text, "detail": detail + "\n\nPrice: %s Oro" % _num(price), "max": 1,
		"color": Color(0.85, 0.92, 1.0),
		"confirm": func(_n: int) -> String: return "Buy for %s Oro" % _num(price),
		"act": func(_n: int) -> String:
			if save().inventory.oro < price:
				return "You don't have enough Oro."
			if give.call() != "":
				return "Your pack is full."
			save().inventory.oro -= price
			return "Thank you! It's in your pack."}
	if save().inventory.oro < price:
		item.error = "You don't have enough Oro (%s)." % _num(price)
	elif save().pack_free() <= 0:
		item.error = "Your pack is full."
	return item


func _curative_item(id: StringName) -> Dictionary:
	var price: int = Prices.CURATIVES[id]
	var have := save().inventory.count(id)
	var most := mini(save().stack_room(id), save().inventory.oro / price)
	var item := {"text": "%s   %s Oro   (have %d)" % [Inventory.item_name(id), _num(price), have],
		"detail": ItemText.stack_detail(id, save()) + "\n\nPrice: %s Oro each. Stacks hold %d." % [_num(price), Inventory.STACK_MAX],
		"color": Color(0.6, 1.0, 0.7), "max": most, "start": 1,
		"confirm": func(n: int) -> String: return "Buy %d for %s Oro" % [n, _num(n * price)],
		"act": func(n: int) -> String:
			n = mini(n, save().inventory.oro / price)
			var got := save().take_stack(id, n)
			save().inventory.oro -= got * price
			return "Thank you! %d %s." % [got, Inventory.item_name(id)]}
	if save().stack_room(id) <= 0:
		item.error = "You can't carry more %s (%d per stack, or the pack is full)." % [Inventory.item_name(id), Inventory.STACK_MAX]
	elif most <= 0:
		item.error = "You don't have enough Oro (%s)." % _num(price)
	return item


# --- Selling -------------------------------------------------------------------------------

func _sell_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var s := save()
	for e in s.pack_entries():
		var each := Prices.sell_price(e, s)
		var count := s.inventory.count(e.id) if e.kind == "stack" else 1
		var item := {"text": "%s   %s Oro%s" % [ItemText.label(e, s, s.inventory), _num(each), " each" if count > 1 else ""],
			"color": ItemText.color(e), "detail": ItemText.detail(e, player, s.inventory) + "\n\nSells for %s Oro%s." % [_num(each), " each" if count > 1 else ""],
			"max": count, "start": 1,
			"confirm": func(n: int) -> String: return "Sell %sfor %s Oro" % ["%d " % n if count > 1 else "", _num(n * each)],
			"act": func(n: int) -> String: return _sell(e, n, each)}
		if e.kind == "weapon" and not s.palettes_with(e.weapon).is_empty():
			item.error = "It's on a palette: take it off first."
		elif e.kind == "armor" and e.get("worn", false):
			item.error = "You're wearing it: take it off first."
		list.append(item)
	return list


func _sell(e: Dictionary, n: int, each: int) -> String:
	var s := save()
	var name := ItemText.label(e, s, s.inventory)
	match e.kind:
		"weapon":
			s.inventory.weapons.erase(e.weapon)
		"armor":
			s.inventory.armors.erase(e.armor)
		"unit":
			s.inventory.take_unit(e.unit)
		"disc":
			s.inventory.discs.remove_at(e.index)
		"stack":
			n = s.inventory.remove_consumable(e.id, n)
			name = "%d %s" % [n, Inventory.item_name(e.id)]
	var paid := s.inventory.add_oro(n * each)
	return "Sold %s for %s Oro." % [name, _num(paid)]
