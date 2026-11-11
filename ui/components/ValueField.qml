import QtQuick
import Quickshell.Io
import qs.Ui

// Single-line editor for numeric and time values. Wraps qs.Ui.TextField.
//
// Explicit paste is handled here instead of by Qt's native path: Qt's Wayland
// clipboard transfer is an unbounded, synchronous read on the GUI thread, so
// pasting is performed through a bounded `wl-paste` invocation (timeout + byte
// cap) rather than Qt's built-in paste. Typing and caret placement are
// unaffected. The background clipboard-change fetch is an upstream Qt issue
// (qt/qtdeclarative ef692a52e3, pending in the distro's Qt build) and is not
// reachable from QML; it is tracked separately.

TextField {
  id: root

  signal escapePressed()

  property string clipBuffer: ""

  Process {
    id: clipboardProc
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root.clipBuffer.length > 0) root.clipBuffer += "\n"
        root.clipBuffer += line
      }
    }
    stderr: SplitParser {
      onRead: function(line) { }
    }
    onStarted: root.clipBuffer = ""
    onExited: function(code) {
      if (code === 0 && root.clipBuffer.length > 0) {
        let text = root.clipBuffer
        if (text.length > 4096) text = text.substring(0, 4096)
        let pos = root.cursorPosition
        root.text = root.text.substring(0, pos) + text + root.text.substring(pos)
        root.cursorPosition = pos + text.length
      }
      root.clipBuffer = ""
    }
  }

  function doPaste() {
    if (clipboardProc.running) return
    clipboardProc.command = ["timeout", "2", "wl-paste", "--no-newline"]
    clipboardProc.running = true
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.matches(StandardKey.Paste)) {
      event.accepted = true
      root.doPaste()
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