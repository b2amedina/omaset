import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "../model.js" as Model

// Time-of-day setting: label on the left, a value readout on the right shown
// in the preferred format (24h or 12h). Enter or a click opens an inline
// field that accepts either form ("20:30" or "8:30 PM") and stores canonical
// 24-hour "HH:MM". Left/right on the focused row step ±15 minutes. Rows carry
// a subtle idle fill (no border) that brightens to the accent border + fill
// when the keyboard cursor lands on the row.
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
  readonly property bool editing: panel ? (panel.editingRow === rowIndex) : false

  function editingText() {
    return Model.formatTime(root.row.value, root.row.timeFormat)
  }

  function commitEditing() {
    if (!root.panel) return
    var canonical = Model.canonicalTime(valueField.text)
    if (canonical === null) {
      valueField.selectAll()
      return
    }
    root.panel.endEdit()
    if (canonical !== root.row.value) root.panel.commit(root.row, canonical)
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
      width: parent.width - valueBox.width - parent.spacing
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

    Item {
      id: valueBox
      width: root.editing ? Style.space(96) : valueText.implicitWidth
      height: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: valueText
        anchors.fill: parent
        visible: !root.editing
        textFormat: Text.PlainText
        text: Model.formatTime(root.row.value, root.row.timeFormat)
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      TextField {
        id: valueField
        visible: root.editing
        anchors.fill: parent
        horizontalAlignment: Text.AlignRight
        foreground: root.fg
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: 0

        onVisibleChanged: if (visible) {
          text = root.editingText()
          Qt.callLater(function() {
            if (!valueField) return
            valueField.selectAll()
            valueField.forceActiveFocus()
          })
        }

        onAccepted: root.commitEditing()

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.panel) root.panel.endEdit()
            event.accepted = true
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        visible: !root.editing
        cursorShape: Qt.IBeamCursor
        onClicked: if (root.panel) root.panel.beginEdit(root.rowIndex)
      }
    }
  }
}
