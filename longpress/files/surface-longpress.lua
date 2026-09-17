-- omarchy-surface-touch: long press on the touchscreen sends a right click.
-- The plugin refuses to load when Hyprland has been updated since it was built;
-- rebuild it with ~/.local/lib/omarchy-surface-longpress/rebuild (the post-update
-- hook does that by itself after `omarchy update`).
local plugin = os.getenv("HOME") .. "/.local/lib/omarchy-surface-longpress/longpress.so"
local file = io.open(plugin, "r")
if file then
  file:close()
  hl.plugin.load(plugin)
end
