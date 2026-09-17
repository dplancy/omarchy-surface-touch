import QtQuick
import qs.Ui

// Bar button for automatic brightness. Click: follow the light sensor, or leave
// the brightness alone. Setting the brightness by hand also pauses it until the
// light really changes.
BarWidget {
  id: root
  moduleName: "surface-touch.light"

  LightState { id: light }

  visible: light.running && light.sensor
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: light.enabled ? "󰃡" : "󰃞"
    active: light.enabled && !light.paused
    tooltipText: (light.enabled
        ? (light.paused ? "Brightness set by hand, waiting for the light to change"
                        : "Brightness follows the light")
        : "Automatic brightness off")
      + "\n" + light.lux + " lux, " + light.percent + "%"
    onPressed: light.run(["toggle"])
  }
}
