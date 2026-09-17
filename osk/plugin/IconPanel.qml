import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Floating keyboard icon, shown while a text field has focus and no physical
// keyboard is attached. Tap: open or close the keyboard. Press and hold: switch
// between AZERTY and QWERTY.
Item {
  id: root

  OskState { id: osk }

  readonly property bool shown: !osk.physicalKeyboard && !osk.locked && (osk.focused || osk.keyboardVisible)
  readonly property int iconSize: Style.space(52)
  readonly property int margin: Style.space(16)

  PanelWindow {
    id: window
    visible: root.shown
    anchors { bottom: true; right: true }
    implicitWidth: root.iconSize + root.margin
    implicitHeight: root.iconSize + root.margin
    margins.bottom: osk.keyboardVisible
      ? (window.screen && window.screen.width > window.screen.height ? osk.landscapeHeight : osk.portraitHeight)
      : 0
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
        onPressed: held = false
        onPressAndHold: {
          held = true
          osk.run(["layout", "toggle"])
        }
        onReleased: if (!held) osk.run(["toggle"])
      }
    }
  }
}
