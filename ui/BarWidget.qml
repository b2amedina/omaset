import QtQuick
import qs.Ui

// Optional bar icon. It is not installed anywhere by default — add
// `b2amedina.omaset` to shell.json's bar layout to show it. Clicking it
// toggles the same floating window the CLI summons.
BarWidget {
  id: root
  moduleName: "b2amedina.omaset"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf013"
    tooltipText: "omaset Settings"
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) return
      root.bar.run("omarchy-shell shell toggle b2amedina.omaset '{}'")
    }
  }
}
