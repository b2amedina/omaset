import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BorderSurface {
  id: root

  property var panel: null
  property var row: ({})
  property int rowIndex: -1

  readonly property bool rtl: panel ? panel.rtl : false
  readonly property color fg: panel ? panel.foreground : Commons.Color.foreground
  readonly property color accent: panel ? panel.accent : Commons.Color.accent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property bool hasCursor: panel ? (panel.focusPane === "content" && panel.selectedRow === rowIndex) : false
  readonly property bool hot: hasCursor
  readonly property bool editing: panel ? (panel.editingRow === rowIndex) : false

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
      width: parent.width - valueArea.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Text {
        textFormat: Text.PlainText
        text: root.row.label || ""
        horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
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
        horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
        visible: root.row.description !== undefined && root.row.description !== ""
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }

    Item {
      id: valueArea
      width: Math.max(160, parent.width * 0.45)
      height: parent.height

      Text {
        id: valueText
        anchors.fill: parent
        visible: !root.editing
        textFormat: Text.PlainText
        text: (root.row.value === undefined || root.row.value === null) ? "" : String(root.row.value)
        horizontalAlignment: root.rtl ? Text.AlignLeft : Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }

      ValueField {
        id: valueField
        visible: root.editing
        anchors.fill: parent
        horizontalAlignment: root.rtl ? Text.AlignLeft : Text.AlignRight
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
        onEscapePressed: if (root.panel) root.panel.endEdit()
      }

      MouseArea {
        anchors.fill: parent
        visible: !root.editing
        cursorShape: Qt.IBeamCursor
        onClicked: if (root.panel) root.panel.beginEdit(root.rowIndex)
      }
    }
  }

  function editingText() {
    var v = root.row.value
    return (v === undefined || v === null) ? "" : String(v)
  }

  function commitEditing() {
    if (!root.panel) return
    var s = String(valueField.text)
    root.panel.endEdit()
    if (s !== root.row.value) root.panel.commit(root.row, s)
  }
}
