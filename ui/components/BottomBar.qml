import QtQuick
import qs.Ui
import qs.Commons

// Footer bar: keyboard hints on the left, a contextual badge on the right
// ("N changed" when edits differ from stock, "N settings found" while
// searching). The badge slot is shared so any future context can reuse it.
Rectangle {
  id: root

  property var panel: null
  property string hints: ""
  property string context: ""
  property color contextColor: Color.accent

  readonly property bool contextVisible: context !== ""
  readonly property color fg: panel ? panel.foreground : Color.foreground
  readonly property color bg: panel ? panel.background : Color.background

  height: Style.space(26)
  color: Qt.darker(bg, 1.15)

  Rectangle {
    anchors.top: parent.top
    width: parent.width
    height: 1
    color: Style.normalBorderColor
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.hints
    color: Qt.darker(root.fg, 1.3)
    font.family: panel ? panel.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    width: parent.width - (contextVisible ? badge.width + Style.spacing.lg : 0) - Style.spacing.rowPaddingX * 2
  }

  BorderSurface {
    id: badge
    visible: root.contextVisible
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(16)
    width: badgeText.implicitWidth + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.fg, root.contextColor)
    borderSpec: Border.flat(Style.normalBorderColor, 1)

    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.context
      color: root.contextColor
      font.family: panel ? panel.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
