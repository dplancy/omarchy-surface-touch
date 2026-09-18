import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Floating keyboard icon, shown while a text field has focus and no physical
// keyboard is attached, and whenever the keyboard itself is up. Tap: open or
// close the keyboard. Press and hold: switch between AZERTY and QWERTY. Drag it
// anywhere, so it never sits on top of something you need; where you leave it
// is remembered.
//
// The window covers the whole screen and only the icon takes touches (`mask`),
// so dragging happens in a frame that does not move: moving the window itself
// under the finger makes every event arrive in a different coordinate system,
// and the icon jumps around.
Item {
  id: root

  OskState { id: osk }

  readonly property bool shown: !osk.locked && (osk.keyboardVisible || (!osk.physicalKeyboard && osk.focused))
  readonly property int iconSize: Style.space(52)
  readonly property int margin: Style.space(16)

  readonly property int screenWidth: window.screen ? window.screen.width : 1368
  readonly property int screenHeight: window.screen ? window.screen.height : 912
  readonly property int keyboardHeight: osk.keyboardVisible
    ? (screenWidth > screenHeight ? osk.landscapeHeight : osk.portraitHeight)
    : 0

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  // where the icon rests: what was dragged last time, or the bottom right corner
  readonly property int restX: clamp(osk.iconX >= 0 ? osk.iconX : screenWidth - iconSize - margin,
                                     margin, Math.max(margin, screenWidth - iconSize - margin))
  // never let it end up under the keyboard, where it could not be reached
  readonly property int restY: clamp(osk.iconY >= 0 ? osk.iconY : screenHeight - iconSize - margin,
                                     margin, Math.max(margin, screenHeight - keyboardHeight - iconSize - margin))

  PanelWindow {
    id: window
    visible: root.shown
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-surface-osk-icon"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // everything outside the icon stays with the application underneath
    mask: Region { item: button }

    Rectangle {
      id: button
      width: root.iconSize
      height: root.iconSize
      x: root.restX
      y: root.restY
      radius: width / 2
      color: mouse.pressed ? Color.accent : Util.alpha(Color.background, 0.85)
      border.width: Math.max(1, Style.space(2))
      border.color: Util.alpha(Color.accent, 0.8)

      // dragging writes x and y directly, so the binding is put back afterwards
      Binding { target: button; property: "x"; value: root.restX; when: !mouse.drag.active; restoreMode: Binding.RestoreNone }
      Binding { target: button; property: "y"; value: root.restY; when: !mouse.drag.active; restoreMode: Binding.RestoreNone }

      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Style.space(5)
        textFormat: Text.PlainText
        text: osk.keyboardVisible ? "󰌐" : "󰌌"
        color: mouse.pressed ? Color.background : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.space(24)
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(6)
        textFormat: Text.PlainText
        text: osk.layout === "azerty" ? "AZ" : "QW"
        color: mouse.pressed ? Color.background : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.bold: true
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        pressAndHoldInterval: 600
        property bool held: false
        property bool moved: false

        drag.target: button
        drag.threshold: Style.space(8)
        drag.minimumX: root.margin
        drag.maximumX: Math.max(root.margin, window.width - button.width - root.margin)
        drag.minimumY: root.margin
        drag.maximumY: Math.max(root.margin, window.height - root.keyboardHeight - button.height - root.margin)

        onPressed: {
          held = false
          moved = false
        }

        onPositionChanged: if (drag.active) moved = true

        onPressAndHold: {
          if (drag.active)
            return
          held = true
          osk.run(["layout", "toggle"])
        }

        onReleased: {
          if (moved)
            osk.run(["icon", Math.round(button.x), Math.round(button.y)])
          else if (!held)
            osk.run(["toggle"])
        }
      }
    }
  }
}
