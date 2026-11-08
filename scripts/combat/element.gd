class_name Element
extends RefCounted
## Damage types (North Star §4.5). Every attack deals exactly one.

enum Type { GENERIC, FIRE, ICE, LIGHTNING, NATURE, LIGHT, DARK }

const COLORS := {
	Type.GENERIC: Color(1.0, 1.0, 1.0),
	Type.FIRE: Color(1.0, 0.45, 0.15),
	Type.ICE: Color(0.55, 0.85, 1.0),
	Type.LIGHTNING: Color(1.0, 0.95, 0.3),
	Type.NATURE: Color(0.45, 0.9, 0.35),
	Type.LIGHT: Color(1.0, 1.0, 0.8),
	Type.DARK: Color(0.7, 0.4, 1.0),
}


static func color_of(type: Type) -> Color:
	return COLORS.get(type, Color.WHITE)


static func name_of(type: Type) -> String:
	return Type.keys()[type].capitalize()
