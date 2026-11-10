class_name EquipTab
extends VBoxContainer
## Menu tab (Part 9): everything you equip, in sections (Grayson, 2026-11-09:
## PSO's menus with PSU's palettes):
##
## - Palette: the 8 PSU-style palettes (primary / off hand), filled from the
##   weapons in your pack.
## - Spells: the spells on each casting item in your palettes (not Goluman).
## - Traps (Goluman, in place of Spells) or D-pad (everyone else): the d-pad
##   palette, 8 slots of items, and traps for Goluman (QuickTab).
## - Armor: Head / Torso / Legs and the augments in their slots.
##
## LT / RT (or the buttons along the top) switch sections. Up from the top of
## a section reaches these buttons; down from them goes back into the section.

## Every section name (Traps and D-pad are the same page).
const SECTIONS := ["Palette", "Spells", "Traps", "Armor", "D-pad"]

var menu: LoadoutMenu
var section := "Palette"
var _bar: HBoxContainer
var _buttons := {}  # section -> Button
var _pages := {}  # section -> Control
var _goluman := false


func _init(owner_menu: LoadoutMenu, palette: Control, spells: Control, armor: Control, quick: Control) -> void:
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
		b.gui_input.connect(func(event: InputEvent):
			if event.is_action_pressed("ui_down"):
				b.accept_event()
				menu._focus_tab())
		_bar.add_child(b)
		_buttons[s] = b
	_bar.add_child(_hint("   LT / RT: sections"))
	_pages = {"Palette": palette, "Spells": spells, "Traps": quick, "D-pad": quick, "Armor": armor}
	for page in [palette, spells, quick, armor]:
		add_child(page)
	set_goluman(false)
	show_section("Palette", false)


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(0.7, 0.75, 0.85)
	return l


## The sections this Seeker has: Goluman get Traps in place of Spells.
func sections() -> Array:
	return ["Palette", "Traps", "Armor"] if _goluman else ["Palette", "Spells", "Armor", "D-pad"]


func set_goluman(on: bool) -> void:
	_goluman = on
	for s in _buttons:
		(_buttons[s] as Button).visible = s in sections()
	if not section in sections():
		section = "Traps" if section == "Spells" or section == "D-pad" else ("D-pad" if section == "Traps" else "Palette")
		if not section in sections():
			section = "Palette"
	if is_inside_tree():
		show_section(section, false)


func page(s: String) -> Control:
	return _pages.get(s)


## Shows one section; `focus` moves focus into it.
func show_section(s: String, focus: bool = true) -> void:
	if not s in sections():
		s = {"Spells": "Traps", "Traps": "D-pad", "D-pad": "Traps"}.get(s, "Palette")
		if not s in sections():
			s = "Palette"
	section = s
	var shown: Control = _pages[s]
	for key in _pages:
		(_pages[key] as Control).visible = _pages[key] == shown
	for key in _buttons:
		(_buttons[key] as Button).set_pressed_no_signal(key == s)
	if focus:
		menu._focus_tab.call_deferred()


func step_section(step: int) -> void:
	var list := sections()
	show_section(list[posmod(list.find(section) + step, list.size())])


func bar_button() -> Button:
	return _buttons.get(section)


## Focuses the current section's button (when a section has nothing to focus).
func focus_bar() -> void:
	bar_button().grab_focus.call_deferred()


## Up from `control` goes to the section buttons.
func link_up(control: Control) -> void:
	if control and bar_button():
		control.focus_neighbor_top = control.get_path_to(bar_button())
