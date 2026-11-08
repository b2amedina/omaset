import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Monitor selector for monitor-grouped keyed settings (4.5 workspace layouts):
// a segmented control over the connected monitors. Picking one switches which
// monitor's workspaces the rows below show. Selection is the connector name
// (`row.selected`); the buttons show the make/model label.
BorderSurface {
  id: root

  property var panel: null
  property var row: ({})
  property int rowIndex: -1

  readonly property color fg: panel ? panel.foreground : Commons.Color.foreground
  readonly property color accent: panel ? panel.accent : Commons.Color.accent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property bool hasCursor: panel ? (panel.focusPane === "content" && panel.selectedRow === rowIndex) : false
  readonly property bool hot: hasCursor

  readonly property var monitors: row.monitors || []
  readonly property string selectedName: row.selected || ""

  function labels() {
    var out = []
    for (var i = 0; i < root.monitors.length; i++) out.push(String(root.monitors[i].label))
    return out
  }

  function selectedLabel() {
    for (var i = 0; i < root.monitors.length; i++)
      if (root.monitors[i].name === root.selectedName) return String(root.monitors[i].label)
    return ""
  }

  onHasCursorChanged: {
    if (root.hasCursor && root.visible && root.panel)
      root.panel.ensureRowVisible(root)
  }

  readonly property var cursorSpec: Border.controlSpec("hover-cursor", fg, accent)
  readonly property var idleSpec: ({
    color: "transparent",
    widths: cursorSpec.widths,
    gradient: { colors: [], angle: 0, enabled: false },
  })

  radius: Style.cornerRadius
  color: Style.controlFill(false, hot, fg, accent)
  borderSpec: hot ? cursorSpec : idleSpec
  implicitHeight: Math.max(44, content.implicitHeight + Style.spacing.controlGap * 2)

  MouseArea {
    anchors.fill: parent
    onClicked: if (root.panel) root.panel.cursorTo(root.rowIndex)
  }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.borderLeft + Style.spacing.rowPaddingX
    anchors.rightMargin: root.borderRight + Style.spacing.rowPaddingX
    spacing: Style.spacing.rowPaddingX

    Column {
      width: parent.width - group.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Text {
        textFormat: Text.PlainText
        text: "Monitor"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
    }

    ButtonGroup {
      id: group
      anchors.verticalCenter: parent.verticalCenter
      options: root.labels()
      value: root.selectedLabel()
      cursorIndex: -1
      foreground: root.fg
      background: root.panel ? root.panel.background : Commons.Color.background
      accent: root.accent
      fontFamily: root.fontFamily
      onChanged: function(v) {
        if (!root.panel) return
        root.panel.cursorTo(root.rowIndex)
        for (var i = 0; i < root.monitors.length; i++)
          if (String(root.monitors[i].label) === String(v)) {
            root.panel.selectMonitor(root.row.id, root.monitors[i].name)
            break
          }
      }
    }
  }
}
