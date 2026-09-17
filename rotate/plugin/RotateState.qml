import QtQuick
import Quickshell
import Quickshell.Io

// State published by the omarchy-surface-rotate daemon.
Item {
  id: root

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  property bool running: false
  property bool enabled: false
  property bool physicalKeyboard: true
  property bool sensor: false
  property string orientation: "normal"

  function run(args) {
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-surface-rotate"].concat(args))
  }

  function apply(raw) {
    try {
      var s = JSON.parse(raw)
      enabled = s.enabled === true
      physicalKeyboard = s.physicalKeyboard === true
      sensor = s.sensor === true
      orientation = s.orientation || "normal"
      running = true
    } catch (e) {
      running = false
    }
  }

  FileView {
    id: file
    path: root.runtimeDir + "/omarchy-surface-rotate/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    // no daemon: the button hides itself
    onLoadFailed: root.running = false
  }

  // the daemon may start after the shell, and rewriting the file can drop the watch
  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: file.reload()
  }
}
