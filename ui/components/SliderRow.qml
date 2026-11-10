import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Bounded int/float setting: label on the left, a PanelSlider with a live
// value readout on the right. Rows carry a subtle idle fill (no border) that
// brightens to the accent border + fill when the keyboard cursor lands on the
// row. Mouse hover does not move or highlight the cursor.
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

  function editingText() {
    var v = root.row.value
    if (v === undefined || v === null) v = root.row.min !== undefined ? root.row.min : 0
    return root.row.integer ? String(Math.round(v)) : String(v)
  }

  function commitEditing() {
    if (!root.panel) return
    var s = String(valueField.text).replace(/^\s+|\s+$/g, "")
    if (!/^-?(?:\d+(?:\.\d*)?|\.\d+)$/.test(s)) {
      valueField.selectAll()
      return
    }
    var n = Number(s)
    if (!isFinite(n)) {
      valueField.selectAll()
      return
    }
    if (root.row.integer) n = Math.round(n)
    else n = Math.round(n * 1000) / 1000
    if (root.row.min !== undefined && n < root.row.min) n = root.row.min
    if (root.row.max !== undefined && n > root.row.max) n = root.row.max
    root.panel.endEdit()
    if (n !== root.row.value) root.panel.commit(root.row, n)
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

  readonly property var sliderBar: QtObject {
    readonly property color foreground: root.fg
    readonly property color background: root.panel ? root.panel.background : Commons.Color.background
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
      id: sliderBox
      width: Style.space(210)
      height: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter

      PanelSlider {
        id: slider
        enabled: !root.editing
        anchors.left: parent.left
        anchors.right: valueBox.left
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

      // The stock slider's onWheel accepts wheel events, so this shield
      // forwards the delta to the ScrollView. Clicks still fall through
      // (acceptedButtons: Qt.NoButton) for dragging.
      MouseArea {
        anchors.fill: slider
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
          wheel.accepted = true
          var delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y
          if (root.panel) root.panel.scrollContentBy(delta)
        }
      }

      Connections {
        target: slider
        function onDraggingChanged() {
          if (root.panel) root.panel.interacting = slider.dragging
        }
      }

      Item {
        id: valueBox
        width: root.editing ? Style.space(64) : valueText.implicitWidth
        height: Style.space(22)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: valueText
          anchors.fill: parent
          visible: !root.editing
          textFormat: Text.PlainText
          text: root.row.integer
            ? String(Math.round(slider.liveValue))
            : slider.liveValue.toFixed(2)
          horizontalAlignment: root.rtl ? Text.AlignLeft : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
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
          inputMethodHints: root.row.integer ? Qt.ImhDigitsOnly : Qt.ImhFormattedNumbersOnly

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
  }
}
