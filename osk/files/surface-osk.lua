-- omarchy-surface-touch: on-screen keyboard.
-- Draw the keyboard (wvkbd) above the lock screen and let it take touch input
-- there, so the password can be typed without a physical keyboard.
hl.layer_rule({
  name = "surface-osk-above-lock",
  match = { namespace = "^wvkbd$" },
  above_lock = 2,
})
