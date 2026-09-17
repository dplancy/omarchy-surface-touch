import QtQuick
import Quickshell
import Quickshell.Io

// State published by the omarchy-surface-osk daemon.
Item {
  id: root

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  property bool physicalKeyboard: true
  property bool focused: false
  property bool locked: false
  property bool keyboardVisible: false
  property string layout: "azerty"
  property int portraitHeight: 300
  property int landscapeHeight: 280

  function run(args) {
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-surface-osk"].concat(args))
  }

  function apply(raw) {
    try {
      var s = JSON.parse(raw)
      physicalKeyboard = s.physicalKeyboard === true
      focused = s.focused === true
      locked = s.locked === true
      keyboardVisible = s.visible === true
      layout = s.layout === "qwerty" ? "qwerty" : "azerty"
      portraitHeight = s.height || 300
      landscapeHeight = s.landscapeHeight || 280
    } catch (e) {
      physicalKeyboard = true
    }
  }

  FileView {
    id: file
    path: root.runtimeDir + "/omarchy-surface-osk/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    // no daemon: behave as if a keyboard were attached, show nothing
    onLoadFailed: root.physicalKeyboard = true
  }

  // the daemon may start after the shell, and rewriting the file can drop the watch
  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: file.reload()
  }
}
