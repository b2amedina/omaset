import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// "int/float with many labelled choices" (e.g. idle timeouts): a macOS-style
// dropdown rather than a cramped segmented row. The stored value is the
// numeric; the trigger shows the preset label when it matches and the raw
// value otherwise. Enter opens the popup (the panel routes its activate to
// this row's dropdown), and while the popup is open the panel's keyCatcher is
// blocked so j/k/Enter drive the list.
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

  readonly property bool popupOpen: dropdown.popupOpen

  function optionObjects() {
    var out = []
    var labels = root.row.options || []
    var values = root.row.values || []
    for (var i = 0; i < labels.length; i++)
      out.push({ value: String(values[i]), label: String(labels[i]) })
    return out
  }

  function currentValue() {
    var v = root.row.value
    return (v === undefined || v === null) ? "" : String(v)
  }

  Component.onCompleted: {
    // Covers the case where this row is created already under the cursor
    // (after a rebuild), so activate() can reach its dropdown immediately.
    if (root.hasCursor && root.visible && root.panel)
      root.panel.activeDropdown = dropdown
  }
  onHasCursorChanged: {
    if (root.hasCursor && root.visible && root.panel) {
      root.panel.ensureRowVisible(root)
      root.panel.activeDropdown = dropdown
    }
  }
  onPopupOpenChanged: if (root.panel) root.panel.dropdownOpen = root.popupOpen

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
      width: parent.width - dropdown.width - parent.spacing
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

    Dropdown {
      id: dropdown
      anchors.verticalCenter: parent.verticalCenter
      showLabel: false
      options: root.optionObjects()
      value: root.currentValue()
      hasCursor: root.hasCursor
      foreground: root.fg
      background: root.panel ? root.panel.background : Commons.Color.background
      accent: root.accent
      fontFamily: root.fontFamily
      onChanged: function(v) {
        if (!root.panel) return
        root.panel.cursorTo(root.rowIndex)
        root.panel.commit(root.row, Number(v))
      }
      onHovered: function(h) { if (h && root.panel) root.panel.cursorTo(root.rowIndex) }
    }
  }
}
