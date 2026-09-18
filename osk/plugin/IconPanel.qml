import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Floating keyboard icon, shown while a text field has focus and no physical
// keyboard is attached, and whenever the keyboard itself is up. Tap: open or
// close the keyboard. Press and hold: switch between AZERTY and QWERTY. Drag it
// anywhere, so it never sits on top of something you need; where you leave it
// is remembered.
Item {
  id: root

  OskState { id: osk }

  readonly property bool shown: !osk.locked && (osk.keyboardVisible || (!osk.physicalKeyboard && osk.focused))
  readonly property int iconSize: Style.space(52)
  readonly property int margin: Style.space(16)
  readonly property int size: iconSize + margin

  readonly property int screenWidth: window.screen ? window.screen.width : 1368
  readonly property int screenHeight: window.screen ? window.screen.height : 912
  readonly property int keyboardHeight: osk.keyboardVisible
    ? (screenWidth > screenHeight ? osk.landscapeHeight : osk.portraitHeight)
    : 0

  // the position being dragged right now, -1 when the finger is not on it
  property int dragX: -1
  property int dragY: -1

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  readonly property int posX: clamp(dragX >= 0 ? dragX : (osk.iconX >= 0 ? osk.iconX : screenWidth - size),
                                    0, Math.max(0, screenWidth - size))
  // never let the icon end up under the keyboard
  readonly property int posY: clamp(dragY >= 0 ? dragY : (osk.iconY >= 0 ? osk.iconY : screenHeight - size),
                                    0, Math.max(0, screenHeight - keyboardHeight - size))

  PanelWindow {
    id: window
    visible: root.shown
    anchors { top: true; left: true }
    implicitWidth: root.size
    implicitHeight: root.size
    margins { left: root.posX; top: root.posY }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-surface-osk-icon"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: button
      width: root.iconSize
      height: root.iconSize
      anchors.left: parent.left
      anchors.top: parent.top
      radius: width / 2
      color: mouse.pressed ? Color.accent : Util.alpha(Color.background, 0.85)
      border.width: Math.max(1, Style.space(2))
      border.color: Util.alpha(Color.accent, 0.8)

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
        property bool dragging: false
        property real grabX: 0
        property real grabY: 0

        onPressed: function(event) {
          held = false
          dragging = false
          // where inside the icon the finger landed, so it stays under the finger
          grabX = event.x
          grabY = event.y
        }

        onPositionChanged: function(event) {
          if (!dragging && Math.abs(event.x - grabX) < Style.space(8) && Math.abs(event.y - grabY) < Style.space(8))
            return
          dragging = true
          root.dragX = root.posX + event.x - grabX
          root.dragY = root.posY + event.y - grabY
        }

        onReleased: {
          if (dragging) {
            osk.run(["icon", root.posX, root.posY])
            root.dragX = -1
            root.dragY = -1
          } else if (!held)
            osk.run(["toggle"])
        }

        onPressAndHold: {
          if (dragging)
            return
          held = true
          osk.run(["layout", "toggle"])
        }
      }
    }
  }
}
