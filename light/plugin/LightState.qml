import QtQuick
import Quickshell
import Quickshell.Io

// State published by the omarchy-surface-light daemon.
Item {
  id: root

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  property bool running: false
  property bool enabled: false
  property bool paused: false
  property bool sensor: false
  property int lux: 0
  property int percent: 0

  function run(args) {
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-surface-light"].concat(args))
  }

  function apply(raw) {
    try {
      var s = JSON.parse(raw)
      enabled = s.enabled === true
      paused = s.paused === true
      sensor = s.sensor === true
      lux = s.lux || 0
      percent = s.percent || 0
      running = true
    } catch (e) {
      running = false
    }
  }

  FileView {
    id: file
    path: root.runtimeDir + "/omarchy-surface-light/state.json"
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
