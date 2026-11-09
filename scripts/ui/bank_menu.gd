class_name BankMenu
extends CounterMenu
## Nomad-2's bank (Part 10, PSO's Check Room): deposit items from the pack
## and withdraw them, up to SaveData.BANK_SLOTS (200) items; and Oro between
## the satchel and the bank (up to 999,999,999 banked). Each character has
## their own bank, like PSO. Banked Lumidium is shown here too.


func _init() -> void:
	super()
	title = "Bank"
	greeting = "Welcome to the Check Room. What can we keep for you?"


func commands() -> Array:
	return [["Deposit", "deposit"], ["Withdraw", "withdraw"], ["Oro", "oro"]]


func header_text() -> String:
	var s := save()
	return "Oro %s  (banked %s)\nPack %d / %d    Bank %d / %d    Lumidium banked %d" % [
		_num(s.inventory.oro), _num(s.bank.oro), s.pack_used(), Inventory.PACK_SLOTS,
		s.bank_used(), SaveData.BANK_SLOTS, s.inventory.lumidium_total()]


func items_for(command_id: String) -> Array[Dictionary]:
	match command_id:
		"deposit":
			return _deposit_items()
		"withdraw":
			return _withdraw_items()
		"oro":
			return _oro_items()
	return []


func _deposit_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var s := save()
	for e in s.pack_entries():
		var count := s.inventory.count(e.id) if e.kind == "stack" else 1
		var item := {"text": ItemText.label(e, s, s.inventory), "color": ItemText.color(e),
			"detail": ItemText.detail(e, player, s.inventory), "max": count, "start": count,
			"confirm": func(n: int) -> String: return "Deposit%s" % (" %d" % n if count > 1 else ""),
			"act": func(n: int) -> String:
				var error := s.deposit(e, n)
				return error if error != "" else "Deposited."}
		if e.kind == "weapon" and not s.palettes_with(e.weapon).is_empty():
			item.error = "It's on a palette: take it off first."
		elif e.kind == "armor" and e.get("worn", false):
			item.error = "You're wearing it: take it off first."
		elif s.bank_free() <= 0 and not (e.kind == "stack" and s.bank.count(e.id) > 0):
			item.error = "The bank is full."
		list.append(item)
	return list


func _withdraw_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var s := save()
	for e in s.bank_entries():
		var count := s.bank.count(e.id) if e.kind == "stack" else 1
		var item := {"text": ItemText.label(e, s, s.bank), "color": ItemText.color(e),
			"detail": ItemText.detail(e, player, s.bank), "max": count,
			"start": mini(count, s.stack_room(e.id)) if e.kind == "stack" else 1,
			"confirm": func(n: int) -> String: return "Withdraw%s" % (" %d" % n if count > 1 else ""),
			"act": func(n: int) -> String:
				var error := s.withdraw(e, n)
				return error if error != "" else "Withdrawn: it's in your pack."}
		if e.kind == "stack" and s.stack_room(e.id) <= 0:
			item.error = "No room for more %s (%d per stack, or the pack is full)." % [Inventory.item_name(e.id), Inventory.STACK_MAX]
		elif e.kind != "stack" and s.pack_free() <= 0:
			item.error = "Your pack is full."
		list.append(item)
	return list


func _oro_items() -> Array[Dictionary]:
	var s := save()
	var deposit := {"text": "Deposit Oro   (carrying %s)" % _num(s.inventory.oro), "color": Color(1.0, 0.85, 0.35),
		"detail": "Oro in the bank is safe and doesn't count against the satchel's %s." % _num(Inventory.ORO_MAX),
		"max": mini(s.inventory.oro, SaveData.BANK_ORO_MAX - s.bank.oro), "start": s.inventory.oro, "big_steps": true,
		"confirm": func(n: int) -> String: return "Deposit %s Oro" % _num(n),
		"act": func(n: int) -> String: return "Deposited %s Oro." % _num(s.deposit_oro(n))}
	if s.inventory.oro <= 0:
		deposit.error = "You aren't carrying any Oro."
	var withdraw := {"text": "Withdraw Oro   (banked %s)" % _num(s.bank.oro), "color": Color(1.0, 0.85, 0.35),
		"detail": "You can carry up to %s Oro." % _num(Inventory.ORO_MAX),
		"max": mini(s.bank.oro, Inventory.ORO_MAX - s.inventory.oro), "start": mini(s.bank.oro, 1000), "big_steps": true,
		"confirm": func(n: int) -> String: return "Withdraw %s Oro" % _num(n),
		"act": func(n: int) -> String: return "Withdrew %s Oro." % _num(s.withdraw_oro(n))}
	if s.bank.oro <= 0:
		withdraw.error = "There's no Oro in your bank."
	elif s.inventory.oro >= Inventory.ORO_MAX:
		withdraw.error = "You can't carry more Oro."
	return [deposit, withdraw]
