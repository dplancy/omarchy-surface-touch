import QtQuick
import qs.Ui

// Bar button for the on-screen keyboard, visible only without a physical
// keyboard. Left click: open or close. Right click: switch AZERTY/QWERTY.
// Also useful for apps that do not report text fields to fcitx5.
BarWidget {
  id: root
  moduleName: "surface-touch.osk"

  OskState { id: osk }

  // the edge gesture can summon the keyboard even with a keyboard attached, and
  // then this button is the way to put it away again
  visible: !osk.physicalKeyboard || osk.keyboardVisible
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    active: osk.keyboardVisible
    tooltipText: "On-screen keyboard (" + osk.layout.toUpperCase() + ")\nRight click: switch layout"
    onPressed: function(b) {
      if (b === Qt.RightButton) osk.run(["layout", "toggle"])
      else osk.run(["toggle"])
    }
  }
}
