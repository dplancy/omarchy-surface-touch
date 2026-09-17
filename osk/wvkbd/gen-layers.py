#!/usr/bin/env python3
"""Generate the AZERTY, QWERTY and symbol layers of layout.surface.h from xkb.

Labels come from the keymaps wvkbd uploads (fr for AZERTY, us(altgr-intl) for
QWERTY, see xkb-to-wvkbd.py) so every character a key can type is shown: the
base and Shift levels as the key label, AltGr and Shift+AltGr as altgr_label /
altgr_shift_label. Symbol layers find each character on the keymap and force
the modifiers it needs. Copy keys are avoided: their temporary keymaps get lost
through fcitx5.
Usage: gen-layers.py > layers.inc   (then paste the arrays into layout.surface.h)
"""
import ctypes
import sys

xkb = ctypes.CDLL("libxkbcommon.so.0")
xkb.xkb_context_new.restype = ctypes.c_void_p
xkb.xkb_keymap_new_from_names.restype = ctypes.c_void_p
xkb.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
xkb.xkb_keymap_key_get_syms_by_level.argtypes = [
    ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
xkb.xkb_keysym_to_utf8.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
xkb.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]


class RuleNames(ctypes.Structure):
    _fields_ = [(f, ctypes.c_char_p) for f in ("rules", "model", "layout", "variant", "options")]


CONTEXT = xkb.xkb_context_new(0)

# dead keys have no character of their own: show the accent they add
DEAD = {
    "dead_circumflex": "^", "dead_diaeresis": "¨", "dead_abovering": "˚", "dead_macron": "¯",
    "dead_ogonek": "˛", "dead_hook": "◌̉", "dead_horn": "◌̛", "dead_caron": "ˇ", "dead_grave": "`",
    "dead_breve": "˘", "dead_acute": "´", "dead_doubleacute": "˝", "dead_belowdot": "◌̣",
    "dead_abovedot": "˙", "dead_tilde": "~", "dead_cedilla": "¸",
}

# evdev names of the printable keys, by xkb position
KEYS = {
    "TLDE": ("KEY_GRAVE", 41), "LSGT": ("KEY_102ND", 86), "BKSL": ("KEY_BACKSLASH", 43),
    **{f"AE{i:02}": (f"KEY_{n}", c) for i, (n, c) in enumerate(
        [("1", 2), ("2", 3), ("3", 4), ("4", 5), ("5", 6), ("6", 7), ("7", 8), ("8", 9), ("9", 10), ("0", 11),
         ("MINUS", 12), ("EQUAL", 13)], 1)},
    **{f"AD{i:02}": (f"KEY_{n}", c) for i, (n, c) in enumerate(
        [("Q", 16), ("W", 17), ("E", 18), ("R", 19), ("T", 20), ("Y", 21), ("U", 22), ("I", 23), ("O", 24),
         ("P", 25), ("LEFTBRACE", 26), ("RIGHTBRACE", 27)], 1)},
    **{f"AC{i:02}": (f"KEY_{n}", c) for i, (n, c) in enumerate(
        [("A", 30), ("S", 31), ("D", 32), ("F", 33), ("G", 34), ("H", 35), ("J", 36), ("K", 37), ("L", 38),
         ("SEMICOLON", 39), ("APOSTROPHE", 40)], 1)},
    **{f"AB{i:02}": (f"KEY_{n}", c) for i, (n, c) in enumerate(
        [("Z", 44), ("X", 45), ("C", 46), ("V", 47), ("B", 48), ("N", 49), ("M", 50), ("COMMA", 51),
         ("DOT", 52), ("SLASH", 53)], 1)},
}
MODS = ["0", "Shift", "AltGr", "Shift | AltGr"]


class Keymap:
    def __init__(self, layout, variant=""):
        names = RuleNames(b"evdev", b"pc105", layout.encode(), variant.encode(), b"")
        self.keymap = xkb.xkb_keymap_new_from_names(CONTEXT, ctypes.byref(names), 0)
        if not self.keymap:
            sys.exit(f"cannot compile xkb layout {layout}")

    def level(self, xkb_name, level):
        """(label, is_dead) of a key level, or None."""
        syms = ctypes.POINTER(ctypes.c_uint32)()
        n = xkb.xkb_keymap_key_get_syms_by_level(self.keymap, KEYS[xkb_name][1] + 8, 0, level, ctypes.byref(syms))
        if n != 1:
            return None
        name = ctypes.create_string_buffer(64)
        xkb.xkb_keysym_get_name(syms[0], name, 64)
        name = name.value.decode()
        if name in DEAD:
            return DEAD[name], True
        utf8 = ctypes.create_string_buffer(8)
        if xkb.xkb_keysym_to_utf8(syms[0], utf8, 8) <= 1:
            return None
        return utf8.value.decode(), False

    def find(self, char):
        """(xkb key name, level) typing char, preferring low levels."""
        for level in range(4):
            for xkb_name in KEYS:
                found = self.level(xkb_name, level)
                if found == (char, False):
                    return xkb_name, level
        return None


def c_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main_key(keymap, xkb_name):
    levels = [keymap.level(xkb_name, lvl) for lvl in range(4)]
    labels = [lv[0] if lv else None for lv in levels]
    code = KEYS[xkb_name][0]
    line = f"  {{{c_str(labels[0])}, {c_str(labels[1] or labels[0])}, 1.0, Code, {code}"
    if labels[2]:
        line += f", .altgr_label = {c_str(labels[2])}"
    if labels[3]:
        line += f", .altgr_shift_label = {c_str(labels[3])}"
    return line + "},"


FUNCTION_ROW = """  {"Esc", "Esc", 1.25, Code, KEY_ESC, .scheme = 1},
""" + "".join(f'  {{"F{i}", "F{i}", 1.0, Code, KEY_F{i}, .scheme = 1}},\n' for i in range(1, 13)) + """  {"Del", "Del", 1.25, Code, KEY_DELETE, .scheme = 1},
  {"", "", 0.0, EndRow},
"""

BOTTOM_ROW = """  {"%s", "%s", 1.5, %s, .scheme = 1},
  {"Ctrl", "Ctrl", 1.0, Mod, Ctrl, .scheme = 1},
  {"Super", "Super", 1.0, Mod, Super, .scheme = 1},
  {"Alt", "Alt", 1.0, Mod, Alt, .scheme = 1},
  {"", "", 5.0, Code, KEY_SPACE},
  {"AltGr", "AltGr", 1.0, Mod, AltGr, .scheme = 1},
  {"Ctrl", "Ctrl", 1.0, Mod, Ctrl, .scheme = 1},
  {"←", "←", 1.0, Code, KEY_LEFT, .scheme = 1},
  {"↓", "↓", 1.0, Code, KEY_DOWN, .scheme = 1},
  {"→", "→", 1.0, Code, KEY_RIGHT, .scheme = 1},
  /* end of layout */
  {"", "", 0.0, Last},
};
"""


AZERTY_ROWS = [
    (None, ["TLDE"] + [f"AE{i:02}" for i in range(1, 13)],
     '  {"⌫", "⌫", 1.5, Code, KEY_BACKSPACE, .scheme = 1},'),
    ('  {"Tab", "Tab", 2.5, Code, KEY_TAB, .scheme = 1},', [f"AD{i:02}" for i in range(1, 13)], None),
    ('  {"Caps", "Caps", 1.0, Mod, CapsLock, .scheme = 1},', [f"AC{i:02}" for i in range(1, 12)] + ["BKSL"],
     '  {"Enter", "Enter", 1.5, Code, KEY_ENTER, .scheme = 1},'),
    ('  {"⇧", "⇫", 1.5, Mod, Shift, .scheme = 1},', ["LSGT"] + [f"AB{i:02}" for i in range(1, 11)],
     '  {"↑", "↑", 1.0, Code, KEY_UP, .scheme = 1},\n  {"⇧", "⇫", 1.0, Mod, Shift, .scheme = 1},'),
]

QWERTY_ROWS = [
    (None, ["TLDE"] + [f"AE{i:02}" for i in range(1, 13)],
     '  {"⌫", "⌫", 1.5, Code, KEY_BACKSPACE, .scheme = 1},'),
    ('  {"Tab", "Tab", 1.5, Code, KEY_TAB, .scheme = 1},', [f"AD{i:02}" for i in range(1, 13)] + ["BKSL"], None),
    ('  {"Caps", "Caps", 1.75, Mod, CapsLock, .scheme = 1},', [f"AC{i:02}" for i in range(1, 12)],
     '  {"Enter", "Enter", 1.75, Code, KEY_ENTER, .scheme = 1},'),
    ('  {"⇧", "⇫", 1.75, Mod, Shift, .scheme = 1},', [f"AB{i:02}" for i in range(1, 11)],
     '  {"↑", "↑", 1.0, Code, KEY_UP, .scheme = 1},\n  {"⇧", "⇫", 1.75, Mod, Shift, .scheme = 1},'),
]


def main_layer(name, keymap, rows):
    out = [f"static struct key keys_{name}[] = {{", FUNCTION_ROW.rstrip("\n")]
    for first, keys, last in rows:
        out.append("")
        if first:
            out.append(first)
        out += [main_key(keymap, k) for k in keys]
        if last:
            out.append(last)
        out.append('  {"", "", 0.0, EndRow},')
    out.append("")
    out.append((BOTTOM_ROW % ("123", "123", "NextLayer")).rstrip("\n"))
    return "\n".join(out)


SYMBOL_ROWS = [
    list("1234567890"),
    list("@#€$£%&*()"),
    list("+-=/\\|~^`_"),
    list("<>[]{}\"'°§"),
    list("!?:;,.²µ«»"),
]


def symbols(name, keymap):
    out = [f"static struct key keys_{name}[] = {{"]
    for i, row in enumerate(SYMBOL_ROWS):
        if i:
            out.append("")
        out.append({
            0: '  {"Esc", "Esc", 1.25, Code, KEY_ESC, .scheme = 1},',
            1: '  {"Tab", "Tab", 1.25, Code, KEY_TAB, .scheme = 1},',
            2: '  {"Home", "Home", 1.25, Code, KEY_HOME, .scheme = 1},',
            3: '  {"End", "End", 1.25, Code, KEY_END, .scheme = 1},',
            4: '  {"PgUp", "PgUp", 1.25, Code, KEY_PAGEUP, .scheme = 1},',
        }[i])
        for char in row:
            found = keymap.find(char)
            if not found:
                sys.exit(f"{char} is not on the keymap of keys_{name}")
            xkb_name, level = found
            mod = f", 0, {MODS[level]}, .reset_mod = true" if level else ""
            out.append(f"  {{{c_str(char)}, {c_str(char)}, 1.0, Code, {KEYS[xkb_name][0]}{mod}}},")
        out.append({
            0: '  {"⌫", "⌫", 1.5, Code, KEY_BACKSPACE, .scheme = 1},',
            1: '  {"Del", "Del", 1.5, Code, KEY_DELETE, .scheme = 1},',
            2: '  {"Ins", "Ins", 1.5, Code, KEY_INSERT, .scheme = 1},',
            3: '  {"Enter", "Enter", 1.5, Code, KEY_ENTER, .scheme = 1},',
            4: '  {"↑", "↑", 0.75, Code, KEY_UP, .scheme = 1},\n  {"PgDn", "PgDn", 0.75, Code, KEY_PAGEDOWN, .scheme = 1},',
        }[i])
        out.append('  {"", "", 0.0, EndRow},')
    out.append("")
    out.append((BOTTOM_ROW % ("Abc", "Abc", "BackLayer")).rstrip("\n"))
    return "\n".join(out)


FR = Keymap("fr")
US = Keymap("us", "altgr-intl")
print(main_layer("azerty", FR, AZERTY_ROWS))
print()
print(main_layer("full", US, QWERTY_ROWS))
print()
print(symbols("symbols_fr", FR))
print()
print(symbols("symbols_us", US))
