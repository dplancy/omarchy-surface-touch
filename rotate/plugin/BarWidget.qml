import QtQuick
import qs.Ui

// Bar button for automatic screen rotation. Left click: follow the tablet or
// keep the screen where it is. Right click: turn back to landscape and stay
// there. Rotation pauses by itself while a physical keyboard is attached, and
// this button turns it back on when you want it anyway.
BarWidget {
  id: root
  moduleName: "surface-touch.rotate"

  RotateState { id: rotate }

  visible: rotate.running && rotate.sensor
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: rotate.enabled ? "󰑵" : "󰌾"
    active: rotate.enabled
    tooltipText: (rotate.enabled ? "Rotation follows the tablet" : "Rotation locked")
      + (rotate.physicalKeyboard && !rotate.enabled ? " (keyboard attached)" : "")
      + "\nRight click: back to landscape"
    onPressed: function(b) {
      if (b === Qt.RightButton) rotate.run(["normal"])
      else rotate.run(["toggle"])
    }
  }
}
