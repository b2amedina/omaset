import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Enum setting: label on the left, a segmented ButtonGroup on the right.
// Rows carry a subtle idle fill (no border) that brightens to the accent
// border + fill when the keyboard cursor lands on the row. Mouse hover does
// not move or highlight the cursor.
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
        text: root.row.label || ""
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        textFormat: Text.PlainText
        text: root.row.description || ""
        visible: root.row.description !== undefined && root.row.description !== ""
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }

    ButtonGroup {
      id: group
      anchors.verticalCenter: parent.verticalCenter
      options: root.row.options || []
      value: root.row.value !== undefined && root.row.value !== null ? String(root.row.value) : ""
      cursorIndex: -1
      foreground: root.fg
      background: root.panel ? root.panel.background : Commons.Color.background
      accent: root.accent
      fontFamily: root.fontFamily
      onChanged: function(v) {
        if (!root.panel) return
        root.panel.cursorTo(root.rowIndex)
        root.panel.commit(root.row, v)
      }
    }
  }
}
