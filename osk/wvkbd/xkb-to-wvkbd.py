#!/usr/bin/env python3
"""Turn an xkb layout into a wvkbd keymap template (a C string literal).

wvkbd fills the <COMP> key with the character of "Copy" keys through sprintf,
so that key gets two U%08X placeholders and every other % is escaped.
Usage: xkb-to-wvkbd.py <layout> [variant]
"""
import re
import subprocess
import sys

cmd = ["xkbcli", "compile-keymap", "--layout", sys.argv[1]]
if len(sys.argv) > 2:
    cmd += ["--variant", sys.argv[2]]
keymap = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout

keymap = keymap.replace("%", "%%")
keymap, count = re.subn(r"key <COMP>\s*\{[^}]*\};", "key <COMP> { [ U%08X, U%08X ] };", keymap)
if count == 0:
    # no <COMP> symbols in this layout: add them to the symbols section
    keymap, count = re.subn(r"(xkb_symbols\s+\"[^\"]*\"\s*\{)", r'\1\n\tkey <COMP> { [ U%08X, U%08X ] };', keymap)
if count != 1 or "<COMP>" not in keymap.split("xkb_types")[0]:
    sys.exit("cannot place the <COMP> placeholder")

lines = keymap.rstrip("\n").split("\n")
escaped = [line.replace("\\", "\\\\").replace('"', '\\"') for line in lines]
print('"' + "\\n\"\n\"".join(escaped) + '\\n"')
