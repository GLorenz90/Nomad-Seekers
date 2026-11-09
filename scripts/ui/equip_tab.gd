class_name EquipTab
extends VBoxContainer
## Menu tab (Part 9): everything you equip, in three sections (Grayson,
## 2026-11-09: PSO's menus with PSU's palettes):
##
## - Palette: the 8 PSU-style palettes (primary / off hand), filled from the
##   weapons in your pack.
## - Spells: the spells on each casting item in your palettes.
## - Armor: Head / Torso / Legs and the augments in their slots.
##
## LT / RT (or the buttons along the top) switch sections.

const SECTIONS := ["Palette", "Spells", "Armor"]

var menu: LoadoutMenu
var section := "Palette"
var _bar: HBoxContainer
var _buttons := {}  # section -> Button
var _pages := {}  # section -> Control


func _init(owner_menu: LoadoutMenu, palette: Control, spells: Control, armor: Control) -> void:
	menu = owner_menu
	name = "Equip"
	add_theme_constant_override("separation", 10)
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	add_child(_bar)
	for s in SECTIONS:
		var b := Button.new()
		b.text = "  %s  " % s
		b.toggle_mode = true
		b.pressed.connect(func(): show_section(s, true))
		_bar.add_child(b)
		_buttons[s] = b
	_bar.add_child(_hint("   LT / RT: sections"))
	for pair in [["Palette", palette], ["Spells", spells], ["Armor", armor]]:
		_pages[pair[0]] = pair[1]
		add_child(pair[1])
	show_section("Palette", false)


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(0.7, 0.75, 0.85)
	return l


func page(s: String) -> Control:
	return _pages.get(s)


## Shows one section; `focus` moves focus into it.
func show_section(s: String, focus: bool = true) -> void:
	section = s
	for key in _pages:
		(_pages[key] as Control).visible = key == s
		(_buttons[key] as Button).set_pressed_no_signal(key == s)
	if focus:
		menu._focus_tab.call_deferred()


func step_section(step: int) -> void:
	show_section(SECTIONS[posmod(SECTIONS.find(section) + step, SECTIONS.size())])
