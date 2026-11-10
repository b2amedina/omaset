import QtQuick
import qs.Ui

// Single-line editor for numeric and time values. Wraps qs.Ui.TextField and
// blocks the native paste paths before Qt can reach the clipboard: the Wayland
// clipboard transfer in Qt's paste is a synchronous, unbounded read on the
// shell's GUI thread, so pasting into these fields is consumed here rather than
// allowed to stall the window. Typing is unaffected, and the values these
// fields hold (a few digits, "20:30") never need paste.
//
// Enter still fires the inherited `accepted` signal; Escape emits `escapePressed`
// so each caller can close its editor without owning the key handler.

TextField {
  id: root

  signal escapePressed()

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    if ((ctrl && event.key === Qt.Key_V) ||
        (shift && event.key === Qt.Key_Insert)) {
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) {
      root.escapePressed()
      event.accepted = true
      return
    }
  }

  // Swallow middle-click (primary-selection paste) and right-click (any context
  // menu) so neither reaches the text input. Left clicks fall through to the
  // field for caret placement.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton | Qt.RightButton
    onPressed: function(mouse) { mouse.accepted = true }
    onClicked: function(mouse) { mouse.accepted = true }
  }
}
