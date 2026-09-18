# Surface touchscreen on Omarchy

Get the touchscreen of older Microsoft Surface devices working on [Omarchy](https://omarchy.org)'s
default `linux-omarchy` kernel, without switching to the `linux-surface` kernel.

[Version française](README.fr.md)

## Status

Tested on:

| What | Version |
|---|---|
| Device | Surface Pro 6 |
| Omarchy | 4.0.4 |
| Kernel | `linux-omarchy` 7.2.5-3 |
| iptsd | 3.1.0 |
| dkms | 3.4.3 |

Tap, double-tap, long press, 2-finger scroll, pinch and 5 simultaneous fingers work.
The pen was not tested.

These devices use the same touch controller and should work, but are **untested**. Please open
an issue with the output of `verify.sh` if you try one:
Surface Pro 4, Surface Pro 5, Surface Book 1, Surface Book 2, Surface Laptop 1, Surface Laptop 2.

**Not supported:** Surface Pro 7 and newer. Their touch controller needs other kernel patches.

## Why this is needed

On a Surface Pro 6, touch input needs three things that `linux-omarchy` does not provide:

1. **A driver.** The IPTS driver is not in the mainline kernel, only in the
   [linux-surface](https://github.com/linux-surface/linux-surface) patches. This project builds
   it as an out-of-tree module with DKMS, so it is rebuilt automatically on kernel updates.
2. **A fix for Linux 7.2.** Linux 7.2 rejects HID input reports shorter than their descriptor.
   The linux-surface 6.19 driver sends such reports, so every touch frame fails with
   `Failed to process buffer: -22`. [The patch](patches/0001-ipts-adapt-to-linux-7.2-hid-input-report-checks.patch)
   passes the real buffer size to `hid_safe_input_report()`, so the kernel pads the report instead.
   On older kernels the module builds without this change.
3. **IOMMU passthrough for the touch controller.** `linux-omarchy` turns the Intel IOMMU on by
   default, which blocks the controller's memory buffers (DMAR faults). linux-surface patches the
   kernel for this. Here, a `modprobe` hook sets only the touch controller's IOMMU group to
   `identity` right before its `mei_me` driver loads.

Touch data is then processed by [iptsd](https://github.com/linux-surface/iptsd), the
linux-surface user-space daemon.

## Installation

```bash
git clone https://github.com/dplancy/omarchy-surface-touch.git
cd omarchy-surface-touch
sudo ./install.sh --dry-run   # optional: show what will be done
sudo ./install.sh
```

Then reboot into `linux-omarchy` and check that everything works:

```bash
sudo ./verify.sh
```

`verify.sh` checks the boot state, then asks you to perform a few gestures for 6 seconds each and
reports what libinput received. Use `--no-gestures` to skip the gestures. Logs are saved in `logs/`.

### What the installer does

1. Installs `dkms`, `linux-omarchy-headers` and `libinput-tools`.
2. Installs `iptsd`. It only exists in the linux-surface repository: if needed, the installer asks
   before adding it. It checks the signing key fingerprint
   (`87DEFA4AB94A99A4C8C3112556C464BAAC421453`) and adds the repository to `/etc/pacman.conf`, as in the
   [linux-surface instructions](https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup#arch).
   Then it runs `pacman -Syu iptsd`, a full system upgrade, because partial upgrades are not supported on Arch.
   Only `iptsd` is installed from that repository, your kernel stays `linux-omarchy`.
3. Installs an Omarchy hook in `~/.config/omarchy/hooks/pre-refresh-pacman.d/linux-surface-repo`.
   `omarchy refresh pacman` rewrites `/etc/pacman.conf`, and the hook adds the linux-surface
   repository back so `iptsd` keeps getting updates.
4. Copies the driver to `/usr/src/ipts-6.19.8.2` and builds it with DKMS for `linux-omarchy`.
   Older `ipts` DKMS versions are removed only once the new build has succeeded.
5. Installs the IOMMU hook: `/etc/modprobe.d/ipts-iommu.conf` and `/usr/local/sbin/ipts-iommu-passthrough`.
6. Checks that `mei_me` is not in the initramfs, where the hook could not run.

Options: `--yes` (no questions), `--force` (skip the device and OS checks), `--dry-run`.

## On-screen keyboard (optional)

Without the Type Cover there is no way to type, so `osk/` adds an on-screen keyboard:

- When a text field gets focus and no physical keyboard is attached, a small keyboard icon
  appears bottom right. **Tap** it to open or close the keyboard, **press and hold** it to switch
  between **AZERTY** and **QWERTY**. The keyboard closes when the text field goes away.
- A keyboard button in the bar does the same (right click switches the layout). Use it for apps
  that do not report their text fields.
- On the **lock screen** the keyboard opens directly, so the password can be typed by touch.
- Every key shows what it types: the Shift character top left, the AltGr character top right.
  Latching AltGr (or Shift) turns the keys into those characters. The **123** key opens digits,
  symbols and Home/End/PgUp/PgDn.
- Keeping a finger on a key repeats it, like holding a key on a physical keyboard.
- **Tap** a modifier (Shift, Ctrl, Super, Alt, AltGr) to apply it to the next key only,
  **tap it twice** to hold it down (a dot marks it), tap again to release it.
- Colors follow the current Omarchy theme.

```bash
./osk/install.sh      # as your user, not with sudo
```

How it works: Omarchy already runs fcitx5 (for Compose sequences), and fcitx5 knows which text field
has focus. The `omarchy-surface-osk` user service registers as the fcitx5 virtual keyboard, watches
whether a keyboard is attached, and drives [wvkbd](https://github.com/jjsullivan5196/wvkbd) built
with AZERTY and QWERTY layouts generated from the real xkb keymaps (`fr` and `us(altgr-intl)`, see
`osk/wvkbd/gen-layers.py`) and a small patch that draws the Shift and AltGr characters on the keys. The
icon and bar button are an Omarchy shell plugin.

The installer changes, for your user only:

| What | Where |
|---|---|
| wvkbd build and daemon | `~/.local/lib/omarchy-surface-osk/`, `~/.local/bin/omarchy-surface-osk` |
| user service | `~/.config/systemd/user/omarchy-surface-osk.service` |
| shell plugin `surface-touch.osk` | `~/.config/omarchy/plugins/surface-touch.osk/` |
| layer rule so the keyboard works on the lock screen | `~/.config/hypr/surface-osk.lua`, one `require` line in `hyprland.lua` |
| IME flags so Chromium reports text fields, only if that file already exists | `~/.config/chromium-flags.conf` (restart Chromium) |
| the flags it added, so the uninstaller removes only those | `~/.config/omarchy-surface-osk/added-chromium-flags` |

Settings live in `~/.config/omarchy-surface-osk/config.json`: `layout`, `height`,
`landscape_height`, `hide_on_blur`, `ignore_keyboards` (regex of keyboard names to ignore).
Commands: `omarchy-surface-osk show|hide|toggle|status`, `omarchy-surface-osk layout azerty|qwerty|toggle`.
Starting the service with `OSK_DEBUG=1` logs focus events and keystrokes to the journal.

Things to know:
- The Type Cover folded behind the screen still counts as attached (Linux cannot see the fold
  without another linux-surface patch). Use the bar button in that position.
- While the keyboard mode is active, fcitx5 candidate popups (emoji or unicode pickers) are not shown.
- Any program can name its surface `wvkbd` and would then also be drawn above the lock screen.
- The disk encryption passphrase at boot still needs a physical keyboard.

Remove it with `./osk/uninstall.sh`.

## Screen rotation (optional)

`rotate/` turns the screen to match how the tablet is held, from the built-in accelerometer:

- The screen follows the tablet through all four orientations, and stays put while it lies flat.
- Touch and pen input turn with it.
- Rotation pauses while a physical keyboard is attached (laptop mode) and comes back when you
  detach it.
- A bar button locks the rotation, or turns it on while the keyboard is attached. Right click on
  it goes back to landscape.

```bash
./rotate/install.sh   # as your user, not with sudo
```

How it works: the `omarchy-surface-rotate` user service reads the HID accelerometer through sysfs
(`/sys/bus/iio/devices/*/name` = `accel_3d`), so neither root nor `iio-sensor-proxy` is needed. It
writes the rotation, and the matching touch and pen transform, into
`~/.config/hypr/surface-rotate.lua` and reloads Hyprland; `hyprctl keyword` and runtime
`hl.monitor()` / `hl.config()` calls do not stick on Omarchy's Lua configuration.

The installer changes, for your user only:

| What | Where |
|---|---|
| daemon | `~/.local/lib/omarchy-surface-rotate/`, `~/.local/bin/omarchy-surface-rotate` |
| user service | `~/.config/systemd/user/omarchy-surface-rotate.service` |
| bar button | `~/.config/omarchy/plugins/surface-touch.rotate/` |
| current rotation | `~/.config/hypr/surface-rotate.lua`, one `require` line in `hyprland.lua` |

Settings live in `~/.config/omarchy-surface-rotate/config.json`: `output`, `mode`, `position`,
`scale` (they must match your monitor configuration), `allow` (orientations to use),
`tilt_threshold`, `settle_ms`, `poll_ms`, `suspend_with_keyboard`, `ignore_keyboards`,
`transform_touch` (Hyprland only turns the picture, so touch and pen are turned as well),
`touch_transforms` (if touch ends up turned the wrong way) and `quarters`.
Commands: `omarchy-surface-rotate status|toggle|enable|disable`,
`omarchy-surface-rotate normal|left|right|inverted` (turn there and lock),
`omarchy-surface-rotate sensor` (print what the accelerometer reports).
Starting the service with `ROTATE_DEBUG=1` logs every decision to the journal.

**Calibration.** `quarters` says how the tablet is held for each edge the accelerometer finds
gravity on, in the order `[-y, +x, +y, -x]`. Run `omarchy-surface-rotate sensor` and hold the tablet in each
orientation: it prints the three axes and the orientation it settles on, so you can see which
reading belongs to which way of holding it. If the screen turns the wrong way, reorder that list.

Remove it with `./rotate/uninstall.sh`.

## Automatic brightness (optional)

`light/` follows the ambient light sensor with the backlight:

- The screen brightens outdoors and dims in the dark, along a curve you can tune.
- Setting the brightness by hand wins: the daemon then keeps quiet until the light around you
  really changes (a factor of two by default), the way phones behave.
- A bar button turns the whole thing off and on.

```bash
./light/install.sh   # as your user, not with sudo
```

How it works: the `omarchy-surface-light` user service reads the light sensor through sysfs
(`/sys/bus/iio/devices/*/name` = `als`) and drives the backlight with `brightnessctl`, so neither
root nor `iio-sensor-proxy` is needed. Brightness moves in small steps, which keeps it from
flickering on passing shadows.

The installer changes, for your user only:

| What | Where |
|---|---|
| daemon | `~/.local/lib/omarchy-surface-light/`, `~/.local/bin/omarchy-surface-light` |
| user service | `~/.config/systemd/user/omarchy-surface-light.service` |
| bar button | `~/.config/omarchy/plugins/surface-touch.light/` |

Settings live in `~/.config/omarchy-surface-light/config.json`: `curve` (a list of
`[lux, percent]` points), `bias` (shifts the whole curve, to taste), `min_percent`, `max_percent`,
`device`, `poll_ms`, `smoothing`, `jump_ratio`, `step_percent`, `deadband_percent` and
`resume_ratio` (how much the light must change before the daemon takes over again).
Commands: `omarchy-surface-light status|toggle|enable|disable`, and `omarchy-surface-light sensor`
to see the light level next to the brightness the curve asks for — the way to check the curve.
Starting the service with `LIGHT_DEBUG=1` logs every decision to the journal.

Remove it with `./light/uninstall.sh`.

## Touch gestures (optional)

Hyprland's own gestures (`hl.gesture`, three fingers and so on) are **trackpad only**. On a
touchscreen it offers exactly one: swiping in from the left or right edge to change workspace. Turn
that on in `~/.config/hypr/input.lua`:

```lua
hl.config({
  gestures = {
    workspace_swipe_touch = true,
    workspace_swipe_distance = 400,
    workspace_swipe_cancel_ratio = 0.3,
    workspace_swipe_forever = true,
  },
})
```

`gestures/` adds the two a tablet misses, as thin strips along the edges:

- **Swipe up from the bottom edge**: call the on-screen keyboard. While it is up the strip rides
  just above it, and a swipe **down** there puts the keyboard away again.
- **Swipe down from the top left corner**: open the Omarchy menu.

```bash
./gestures/install.sh   # as your user, not with sudo
```

The strips are 12 px thick and only react to a swipe of at least 40 px, so a tap near an edge still
reaches the application underneath. They are a shell plugin, installed in
`~/.config/omarchy/plugins/surface-touch.gestures/`; edit `EdgeGestures.qml` there (or in
`gestures/plugin/`) to change the thickness, the distance or what the swipes do.

Remove them with `./gestures/uninstall.sh`.

## Long press as a right click (optional)

A touchscreen has no second button, and Hyprland offers nothing for this: its gestures are trackpad
only and `input.touchdevice` carries just `enabled`, `output` and `transform`. Outside the
compositor it would mean reading `/dev/input` and writing to `/dev/uinput`, which needs the `input`
group — that is, letting every program you run read your keyboard. So `longpress/` is a small
Hyprland plugin instead, where the touch events already are.

- One finger held still for half a second becomes a right click where the finger rests.
- Moving more than about 2% of the screen, or putting a second finger down, cancels it, so
  scrolling, swiping and pinching are untouched.

```bash
./longpress/install.sh   # as your user, not with sudo
```

Hyprland passes C++ objects to its plugins and guarantees no ABI stability, so the plugin is
**built on your machine, against the Hyprland you are running**, and has to be rebuilt when
Hyprland is updated. The installer takes care of that: it keeps the source next to the build and
installs a `post-update` hook that rebuilds it after every `omarchy update`, telling you how it
went. Until it is rebuilt the plugin simply refuses to load (it compares the build hash), so a
mismatch can never crash the compositor.

The installer changes, for your user only:

| What | Where |
|---|---|
| plugin, its source and its build script | `~/.local/lib/omarchy-surface-longpress/` |
| rebuild after an update | `~/.config/omarchy/hooks/post-update.d/omarchy-surface-longpress` |
| loading it at startup | `~/.config/hypr/surface-longpress.lua`, one `require` line in `hyprland.lua` |

The delay and the tolerance are `LONG_PRESS_MS` and `MOVE_TOLERANCE` at the top of
`longpress/src/main.cpp`; change them and run the installer again.

Remove it with `./longpress/uninstall.sh`.

## Things to know

- **Security.** The IOMMU normally protects memory from buggy or malicious devices. Only the touch
  controller's group is switched to `identity`, every other device keeps its protection. This is
  what the linux-surface kernel does too.
- **Kernel taint.** The kernel logs `module verification failed ... tainting kernel` when the
  module loads. This is expected for any out-of-tree module and has no effect.
- **Secure Boot.** DKMS signs the module with its own key. With Secure Boot enabled, the module only
  loads if that key is enrolled (for example with `mokutil --import /var/lib/dkms/mok.pub`).
- **Kernel updates.** DKMS rebuilds the module automatically when `linux-omarchy` is updated. If a future
  kernel changes an API the driver uses, the build fails and touch stops working until this
  project is updated. You can still boot a previous snapshot from the Limine menu in the meantime.
- **Touch sensitivity.** iptsd settings are in `/etc/iptsd.conf`. If a finger is briefly lost during
  pinches (the `drops` column of `verify.sh`), lowering `ActivationThreshold` and
  `DeactivationThreshold` in the `[Contacts]` section may help.

## Troubleshooting

| Symptom | Where to look |
|---|---|
| Module not built | `dkms status ipts`, then `/var/lib/dkms/ipts/6.19.8.2/build/make.log` |
| Module not loaded | `modinfo -n ipts` should point to `updates/dkms` |
| IOMMU group not `identity` | `cat /sys/bus/pci/devices/0000:00:16.4/iommu_group/type` (address on a Surface Pro 6), `sudo dmesg \| grep DMAR` |
| `Failed to process buffer: -22` | the running module does not contain the Linux 7.2 fix, reinstall and reboot |
| No touch events | `journalctl -b -u 'iptsd@*'` |

## Uninstall

```bash
sudo ./uninstall.sh
```

This removes the module, the IOMMU hook and the Omarchy hook. `iptsd` and the linux-surface
repository are kept, the script prints how to remove them. Reboot afterwards.

## Repository layout

```
install.sh, uninstall.sh, verify.sh
src/ipts/     driver sources, Makefile and dkms.conf
patches/      changes made to the linux-surface driver
files/        IOMMU hook, modprobe rule, Omarchy pacman hook
osk/          optional on-screen keyboard (install.sh, uninstall.sh, daemon, plugin, wvkbd layout)
rotate/       optional screen rotation (install.sh, uninstall.sh, daemon, bar button)
light/        optional automatic brightness (install.sh, uninstall.sh, daemon, bar button)
gestures/     optional edge gestures (install.sh, uninstall.sh, shell plugin)
longpress/    optional long press as a right click (install.sh, uninstall.sh, Hyprland plugin)
```

## Credits and license

- IPTS driver by Dorian Stoll and the [linux-surface](https://github.com/linux-surface/linux-surface)
  project, taken from `patches/6.19/0005-ipts.patch`.
- The IOMMU passthrough idea comes from the linux-surface patch by Liban Hannan.
- [iptsd](https://github.com/linux-surface/iptsd) by the linux-surface project.
- [wvkbd](https://github.com/jjsullivan5196/wvkbd) (GPL-3.0), built by `osk/wvkbd/build.sh` with the layout files in `osk/wvkbd/`, which are derived from its `deskintl` layout.

The driver is GPL-2.0-or-later. The rest of this repository is released under the same license,
see [LICENSE](LICENSE), except the wvkbd layout files in `osk/wvkbd/`, which follow wvkbd's GPL-3.0.

This project is not affiliated with Microsoft, Omarchy or linux-surface.
