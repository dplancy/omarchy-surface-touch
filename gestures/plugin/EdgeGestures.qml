import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Two thin strips along the screen edges, for gestures a touchscreen cannot do
// on its own (Hyprland's own gestures are trackpad only, apart from the
// workspace swipe). Swipe up from the bottom edge for the on-screen keyboard,
// swipe down from the top left corner for the Omarchy menu.
Item {
  id: root

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  // how thick the strips are, and how far a finger must travel to count
  readonly property int edge: 12
  readonly property int travel: 40

  // the keyboard covers the bottom edge, so the strip rides just above it
  property bool keyboardVisible: false
  property int keyboardHeight: 300
  property int keyboardLandscapeHeight: 280

  function osk(args) {
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-surface-osk"].concat(args))
  }

  FileView {
    id: oskState
    path: root.runtimeDir + "/omarchy-surface-osk/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var s = JSON.parse(text())
        root.keyboardVisible = s.visible === true
        root.keyboardHeight = s.height || 300
        root.keyboardLandscapeHeight = s.landscapeHeight || 280
      } catch (e) {
        root.keyboardVisible = false
      }
    }
    onLoadFailed: root.keyboardVisible = false
  }

  // the keyboard daemon may start after the shell, and rewriting the file can drop the watch
  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: oskState.reload()
  }

  PanelWindow {
    id: bottom
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.edge
    // sit on top of the keyboard while it is up, so the same edge can close it again
    margins.bottom: root.keyboardVisible
      ? (screen && screen.width > screen.height ? root.keyboardLandscapeHeight : root.keyboardHeight)
      : 0
    color: "transparent"
    WlrLayershell.namespace: "omarchy-surface-gestures"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      property real startY: 0

      onPressed: function(mouse) { startY = mouse.y }
      onReleased: function(mouse) {
        // swipe up to call the keyboard, swipe down (from above it) to put it away
        var travelled = root.keyboardVisible ? mouse.y - startY : startY - mouse.y
        if (travelled > root.travel)
          root.osk([root.keyboardVisible ? "hide" : "show"])
      }
    }
  }

  PanelWindow {
    id: top
    anchors { top: true; left: true }
    implicitWidth: (screen ? screen.width : 1000) / 3
    implicitHeight: root.edge
    color: "transparent"
    WlrLayershell.namespace: "omarchy-surface-gestures"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      property real startY: 0

      onPressed: function(mouse) { startY = mouse.y }
      onReleased: function(mouse) {
        if (mouse.y - startY > root.travel)
          Quickshell.execDetached(["omarchy", "menu", "toggle"])
      }
    }
  }
}
