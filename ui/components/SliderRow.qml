import QtQuick
import qs.Ui
import qs.Commons

// Bounded int/float setting: label on the left, a PanelSlider with a live
// value readout on the right. Rows carry a subtle idle fill (no border) that
// brightens to the accent border + fill when the keyboard cursor lands on the
// row. Mouse hover does not move or highlight the cursor.
BorderSurface {
  id: root

  property var panel: null
  property var row: ({})
  property int rowIndex: -1

  readonly property color fg: panel ? panel.foreground : Color.foreground
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property bool hasCursor: panel ? (panel.focusPane === "content" && panel.selectedRow === rowIndex) : false
  readonly property bool hot: hasCursor

  readonly property var cursorSpec: Border.controlSpec("hover-cursor", fg, accent)
  readonly property var idleSpec: ({
    color: "transparent",
    widths: cursorSpec.widths,
    gradient: { colors: [], angle: 0, enabled: false },
  })

  readonly property var sliderBar: QtObject {
    readonly property color foreground: root.fg
    readonly property color background: root.panel ? root.panel.background : Color.background
    readonly property color urgent: root.accent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }

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
      width: parent.width - sliderBox.width - parent.spacing
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
      id: sliderBox
      width: Style.space(210)
      height: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter

      PanelSlider {
        id: slider
        anchors.left: parent.left
        anchors.right: valueText.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        bar: root.sliderBar
        value: root.row.value !== undefined && root.row.value !== null ? root.row.value : (root.row.min || 0)
        minimum: root.row.min !== undefined ? root.row.min : 0
        maximum: root.row.max !== undefined ? root.row.max : 100
        step: root.row.step !== undefined ? root.row.step : 1
        integer: root.row.integer === true
        onReleased: function(v) {
          if (!root.panel) return
          root.panel.cursorTo(root.rowIndex)
          var out = root.row.integer ? Math.round(v) : Math.round(v * 1000) / 1000
          root.panel.commit(root.row, out)
        }
      }

      Text {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.row.integer
          ? String(Math.round(slider.liveValue))
          : slider.liveValue.toFixed(2)
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
