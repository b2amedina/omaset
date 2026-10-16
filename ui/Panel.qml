import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "components"
import "model.js" as Model

// omaset settings window. A keyboard-first, schema-driven frontend for the
// omaset JSON protocol: `omaset schema` renders the panels, and `omaset
// get/set/reset` read and write each value. Launched from the CLI via
// `omarchy-shell shell toggle b2amedina.omaset '{}'` or an optional bar icon.
Item {
  id: root

  // ---- plugin lifecycle ------------------------------------------------
  property bool closingFromHost: false
  property var shell: null

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    loadSchema()
    refreshChanged()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("b2amedina.omaset")
    else window.visible = false
  }

  // ---- theme -----------------------------------------------------------
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: Style.font.family
  readonly property color sidebarColor: Qt.darker(background, 1.12)
  readonly property color recessedColor: Qt.darker(background, 1.35)

  // ---- omaset binary ---------------------------------------------------
  readonly property string omasetBin: {
    var e = Quickshell.env("OMASET_BIN")
    return (e && e.length > 0) ? e : "omaset"
  }

  // ---- process runner (serialized command queue) -----------------------
  property var queue: []
  property var pendingCb: null
  property bool runningCmd: false

  Process {
    id: cmd
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onCmdDone(text)
    }
  }

  function exec(args, cb) {
    queue.push({ args: args, cb: cb })
    pump()
  }

  function pump() {
    if (runningCmd || queue.length === 0) return
    runningCmd = true
    var job = queue.shift()
    pendingCb = job.cb
    cmd.command = job.args
    cmd.running = true
  }

  function onCmdDone(text) {
    runningCmd = false
    var cb = pendingCb
    pendingCb = null
    if (cb) cb(text)
    pump()
  }

  function parseJson(t) {
    try { return JSON.parse(t) } catch (e) { return null }
  }

  function cloneObj(o) {
    var n = {}
    for (var k in o) n[k] = o[k]
    return n
  }

  function coercePlain(t) {
    var s = String(t).replace(/\s+$/, "")
    if (s === "") return null
    if (s === "true") return true
    if (s === "false") return false
    var n = Number(s)
    if (isFinite(n) && String(n) === s) return n
    return s
  }

  // ---- model state -----------------------------------------------------
  property var schema: null
  property var panels: []
  property string activePanelId: ""
  property var effective: ({})   // group sub-fields + keyed values (schema can't express them)
  property var keyed: ({})       // id -> [keys]
  property var rows: []
  property int changedCount: -1

  property int selectedSidebar: 0
  property int selectedRow: -1
  property string focusPane: "content"

  // search
  property bool searchMode: false
  property string searchQuery: ""
  property var searchResults: []
  property int searchSel: 0

  // ---- data loading ----------------------------------------------------
  function loadSchema() {
    exec([omasetBin, "schema"], function(text) {
      var obj = parseJson(text)
      root.schema = obj
      if (obj && obj.panels && obj.panels.length) {
        root.panels = obj.panels
        if (root.activePanelId === "")
          root.activePanelId = obj.panels[0].id
      }
      root.rebuildRows()
      root.loadPanelExtras()
    })
  }

  function activePanel() {
    if (!schema || !schema.panels) return null
    for (var i = 0; i < schema.panels.length; i++)
      if (schema.panels[i].id === activePanelId) return schema.panels[i]
    return schema.panels[0] || null
  }

  function loadPanelExtras() {
    var p = activePanel()
    if (!p) return
    for (var i = 0; i < p.settings.length; i++) {
      var s = p.settings[i]
      if (s.type === "group") {
        var subs = s.subsettings || {}
        for (var sub in subs) loadGroupValue(s.id, sub)
      } else if (s.keyed) {
        loadKeyed(s.id)
      }
    }
  }

  function loadGroupValue(id, sub) {
    exec([omasetBin, "get", id, sub, "--plain"], function(text) {
      var v = coercePlain(text)
      var n = cloneObj(root.effective)
      n[Model.settingKey(id, sub)] = v
      root.effective = n
      root.rebuildRows()
    })
  }

  function loadKeyed(id) {
    exec([omasetBin, "keys", id, "--json"], function(text) {
      var keys = []
      var o = parseJson(text)
      if (o && o.keys) keys = o.keys
      var n = cloneObj(root.keyed)
      n[id] = keys
      root.keyed = n
      for (var i = 0; i < keys.length; i++) loadKeyedValue(id, keys[i])
      root.rebuildRows()
    })
  }

  function loadKeyedValue(id, key) {
    exec([omasetBin, "get", id, String(key), "--plain"], function(text) {
      var v = coercePlain(text)
      var n = cloneObj(root.effective)
      n[Model.settingKey(id, undefined, key)] = v
      root.effective = n
      root.rebuildRows()
    })
  }

  function refreshChanged() {
    exec([omasetBin, "changed", "--json"], function(text) {
      var n = 0
      var o = parseJson(text)
      if (o && o.changed) n = o.changed.length
      root.changedCount = n
    })
  }

  property Timer changedTimer: Timer {
    interval: 500
    repeat: false
    onTriggered: root.refreshChanged()
  }
  function scheduleChanged() { changedTimer.restart() }

  // ---- row model -------------------------------------------------------
  function rebuildRows() {
    root.rows = Model.rowsFor(activePanel(), effective, keyed)
    clampRow()
  }

  function iconFor(id) {
    var map = {
      "appearance": "\uf1fc",
      "layout": "\uf009",
      "windows": "\uf0c8",
      "power": "\uf011",
      "display": "\uf108"
    }
    return map[id] || "\uf013"
  }

  // ---- writes ----------------------------------------------------------
  function setEffective(key, v) {
    var n = cloneObj(effective)
    n[key] = v
    root.effective = n
    rebuildRows()
  }

  function setSchemaValue(id, v) {
    var p = activePanel()
    if (p) for (var i = 0; i < p.settings.length; i++)
      if (p.settings[i].id === id) p.settings[i].value = v
    rebuildRows()
  }

  function commit(row, v) {
    if (!row) return
    if (row.sub !== undefined && row.sub !== null) {
      var k1 = Model.settingKey(row.id, row.sub)
      setEffective(k1, v)
      exec([omasetBin, "set", row.id, row.sub, String(v)], function(text) {
        var o = parseJson(text)
        if (o && o.value !== undefined && o.value !== null) setEffective(k1, o.value)
        root.scheduleChanged()
      })
    } else if (row.key !== undefined && row.key !== null) {
      var k2 = Model.settingKey(row.id, undefined, row.key)
      setEffective(k2, v)
      exec([omasetBin, "set", row.id, String(row.key), String(v)], function(text) {
        var o = parseJson(text)
        if (o && o.value !== undefined && o.value !== null) setEffective(k2, o.value)
        root.scheduleChanged()
      })
    } else {
      setSchemaValue(row.id, v)
      exec([omasetBin, "set", row.id, String(v)], function(text) {
        var o = parseJson(text)
        if (o && o.value !== undefined && o.value !== null) setSchemaValue(row.id, o.value)
        root.scheduleChanged()
      })
    }
  }

  function resetRow(row) {
    if (!row) return
    var key = Model.settingKey(row.id, row.sub, row.key)
    var args
    if (row.sub !== undefined && row.sub !== null) args = [omasetBin, "reset", row.id, row.sub]
    else if (row.key !== undefined && row.key !== null) args = [omasetBin, "reset", row.id, String(row.key)]
    else args = [omasetBin, "reset", row.id]
    exec(args, function(text) {
      var n = {}
      for (var k in root.effective) if (k !== key) n[k] = root.effective[k]
      root.effective = n
      root.loadSchema()
      root.scheduleChanged()
    })
  }

  // ---- cursor model ----------------------------------------------------
  function interactiveIndices() {
    var out = []
    for (var i = 0; i < rows.length; i++)
      if (Model.isInteractive(rows[i])) out.push(i)
    return out
  }

  function currentRow() {
    if (selectedRow >= 0 && selectedRow < rows.length && Model.isInteractive(rows[selectedRow]))
      return rows[selectedRow]
    return null
  }

  function clampRow() {
    var idx = interactiveIndices()
    if (idx.length === 0) { selectedRow = -1; return }
    if (idx.indexOf(selectedRow) < 0) selectedRow = idx[0]
  }

  function clampSidebar() {
    if (selectedSidebar < 0) selectedSidebar = 0
    if (panels.length > 0 && selectedSidebar >= panels.length) selectedSidebar = panels.length - 1
  }

  function cursorTo(i) { focusPane = "content"; selectedRow = i }
  function cursorToSidebar(i) { focusPane = "sidebar"; selectedSidebar = i }

  function moveV(dy) {
    if (searchMode) {
      if (searchResults.length === 0) return
      searchSel = Math.max(0, Math.min(searchResults.length - 1, searchSel + dy))
      return
    }
    if (focusPane === "sidebar") {
      clampSidebar()
      selectedSidebar = Math.max(0, Math.min(panels.length - 1, selectedSidebar + dy))
      return
    }
    var idx = interactiveIndices()
    if (idx.length === 0) return
    var pos = idx.indexOf(selectedRow)
    if (pos < 0) pos = dy > 0 ? -1 : 0
    var np = Math.max(0, Math.min(idx.length - 1, pos + dy))
    selectedRow = idx[np]
  }

  function moveH(dx) {
    if (searchMode) return
    if (focusPane === "sidebar") {
      if (dx > 0) { focusPane = "content"; clampRow() }
      return
    }
    var row = currentRow()
    if (row && row.kind === "slider") { stepSlider(row, dx); return }
    if (row && row.kind === "enum") { cycleEnum(row, dx); return }
    if (dx < 0) { focusPane = "sidebar"; clampSidebar() }
  }

  function switchPane(dir) {
    if (searchMode) return
    if (dir > 0) { if (focusPane === "sidebar") { focusPane = "content"; clampRow() } }
    else { if (focusPane === "content") { focusPane = "sidebar"; clampSidebar() } }
  }

  function stepSlider(row, dx) {
    var v = row.value
    if (v === undefined || v === null) v = row.min || 0
    var step = row.step !== undefined ? row.step : 1
    var nv = v + dx * step
    if (row.min !== undefined && nv < row.min) nv = row.min
    if (row.max !== undefined && nv > row.max) nv = row.max
    if (row.integer) nv = Math.round(nv)
    else nv = Math.round(nv * 1000) / 1000
    commit(row, nv)
  }

  function cycleEnum(row, dx) {
    var opts = row.options || []
    if (opts.length === 0) return
    var v = row.value
    var pos = opts.indexOf(v)
    if (pos < 0) pos = 0
    var np = (pos + dx + opts.length) % opts.length
    commit(row, opts[np])
  }

  function activate() {
    if (searchMode) { openSearchResult(); return }
    if (focusPane === "sidebar") {
      selectPanel(selectedSidebar)
      focusPane = "content"
      clampRow()
      return
    }
    var row = currentRow()
    if (!row) return
    if (row.kind === "bool") commit(row, !row.value)
    else if (row.kind === "enum") cycleEnum(row, 1)
    else if (row.kind === "slider") stepSlider(row, row.step)
  }

  function resetCurrent() {
    if (searchMode) return
    resetRow(currentRow())
  }

  // ---- panel switching -------------------------------------------------
  function selectPanel(i) {
    if (i < 0 || i >= panels.length) return
    selectedSidebar = i
    if (panels[i].id === activePanelId) { rebuildRows(); return }
    activePanelId = panels[i].id
    rebuildRows()
    loadPanelExtras()
  }

  function selectRowById(id) {
    var idx = interactiveIndices()
    for (var i = 0; i < idx.length; i++) {
      var r = rows[idx[i]]
      if (r && r.id === id) { selectedRow = idx[i]; return }
    }
    clampRow()
  }

  // ---- search ----------------------------------------------------------
  function enterSearch() {
    searchMode = true
    searchQuery = ""
    searchResults = []
    searchSel = 0
  }

  function exitSearch() {
    searchMode = false
    searchQuery = ""
    searchResults = []
  }

  function scheduleSearch() { searchTimer.restart() }

  function runSearch() {
    if (!searchMode) return
    var q = searchQuery
    if (q.replace(/\s+$/, "") === "") { searchResults = []; return }
    exec([omasetBin, "search", q, "--json"], function(text) {
      if (!root.searchMode) return
      var o = parseJson(text)
      root.searchResults = (o && o.results && Array.isArray(o.results)) ? o.results : []
      if (root.searchSel >= root.searchResults.length)
        root.searchSel = Math.max(0, root.searchResults.length - 1)
    })
  }

  property Timer searchTimer: Timer {
    interval: 180
    repeat: false
    onTriggered: root.runSearch()
  }

  function moveSearch(dy) {
    if (searchResults.length === 0) return
    searchSel = Math.max(0, Math.min(searchResults.length - 1, searchSel + dy))
  }

  function openSearchResult() {
    if (searchResults.length === 0) return
    var r = searchResults[searchSel]
    if (!r) return
    var targetPanel = r.panel
    exitSearch()
    if (targetPanel) {
      var found = -1
      for (var i = 0; i < panels.length; i++) if (panels[i].id === targetPanel) { found = i; break }
      if (found >= 0) selectedSidebar = found
      activePanelId = targetPanel
      rebuildRows()
      loadPanelExtras()
    }
    selectRowById(r.id)
    focusPane = "content"
    refreshChanged()
  }

  // ---- scroll ----------------------------------------------------------
  function ensureRowVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 12
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin) flick.contentY = bottom + margin - flick.height
  }

  // ---- footer ----------------------------------------------------------
  readonly property string footerHints: searchMode
    ? "\u2191\u2193 move · \u23ce open · esc clear"
    : "j k move · h l pane · \u2423/\u23ce select · x reset · / search · esc close"
  readonly property string footerContext: searchMode
    ? (searchResults.length > 0 ? searchResults.length + " settings found" : "")
    : (changedCount > 0 ? changedCount + " changed" : "")
  readonly property color footerContextColor: searchMode ? accent : urgent

  // ---- window ----------------------------------------------------------
  FloatingWindow {
    id: window
    title: "omaset Settings"
    color: root.background
    implicitWidth: 720
    implicitHeight: 560
    minimumSize: Qt.size(480, 360)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("b2amedina.omaset")
    }

    FocusScope {
      id: windowFocus
      anchors.fill: parent
      focus: true

      // While search is open the key catcher is blocked, so this outermost
      // handler owns every key: type characters into the query, backspace,
      // arrow-key navigation, Enter to open, Esc to close. Outside search it
      // only claims "/" and lets PanelKeyCatcher keep its normal keys.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.searchMode) {
          if (event.key === Qt.Key_Escape) { root.exitSearch(); event.accepted = true; return }
          if (event.key === Qt.Key_Backspace) {
            if (root.searchQuery.length > 0) root.searchQuery = root.searchQuery.slice(0, -1)
            root.scheduleSearch()
            event.accepted = true; return
          }
          if (event.key === Qt.Key_Down) { root.moveSearch(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up) { root.moveSearch(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openSearchResult(); event.accepted = true; return }
          if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
              && !(event.modifiers & Qt.ControlModifier)
              && !(event.modifiers & Qt.AltModifier)
              && !(event.modifiers & Qt.MetaModifier)) {
            root.searchQuery += event.text
            root.scheduleSearch()
            event.accepted = true
          }
          return
        }
        if (event.text === "/") { root.enterSearch(); event.accepted = true }
      }

        PanelKeyCatcher {
          id: keyCatcher
          anchors.fill: parent
          blocked: root.searchMode

        onMoveRequested: function(dx, dy) {
          if (dy !== 0) root.moveV(dy)
          else if (dx !== 0) root.moveH(dx)
        }
        onActivateRequested: root.activate()
        onCloseRequested: root.requestClose()
        onDeleteRequested: root.resetCurrent()
        onTabRequested: function(dir) { root.switchPane(dir) }

        Column {
          anchors.fill: parent

          Row {
            id: mainRow
            width: parent.width
            height: parent.height - footer.height

            // ---- sidebar ------------------------------------------------
            Rectangle {
              id: sidebar
              width: Style.space(190)
              height: parent.height
              color: root.sidebarColor

              Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Style.normalBorderColor
              }

              Column {
                anchors.fill: parent
                anchors.margins: Style.spacing.md
                anchors.topMargin: Style.spacing.panelPadding
                spacing: Style.spacing.xs

                Repeater {
                  model: root.panels
                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: sidebar.width - Style.spacing.md * 2
                    height: Style.space(28)

                    readonly property bool active: root.activePanelId === modelData.id
                    readonly property bool cursor: root.focusPane === "sidebar" && root.selectedSidebar === index

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: cursor
                        ? Style.hoverFillFor(root.foreground, root.accent)
                        : (active ? Color.menu.selectedBackground : "transparent")
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.spacing.controlPaddingX
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: root.iconFor(modelData.id)
                      color: active ? Color.menu.selectedText : Qt.darker(root.foreground, 1.3)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(30)
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: modelData.title
                      color: active ? root.foreground : Qt.darker(root.foreground, 1.3)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: active
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectPanel(index)
                      onContainsMouseChanged: if (containsMouse) root.cursorToSidebar(index)
                    }
                  }
                }
              }
            }

            // ---- content -----------------------------------------------
            Column {
              id: content
              width: parent.width - sidebar.width
              height: parent.height

              Item {
                width: parent.width
                height: Style.space(44)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.panelPadding
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.sm

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.searchMode ? "\uf002" : root.iconFor(root.activePanelId)
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconLarge
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.searchMode ? "Search" : (root.activePanel() ? root.activePanel().title : "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }
                }
              }

              Item {
                width: parent.width
                height: parent.height - Style.space(44)

                ScrollView {
                  id: scrollArea
                  anchors.fill: parent
                  anchors.margins: Style.spacing.panelPadding
                  anchors.topMargin: 0
                  clip: true
                  visible: !root.searchMode
                  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                  ScrollBar.vertical.policy: ScrollBar.AsNeeded

                  Column {
                    id: rowsColumn
                    width: scrollArea.availableWidth - Style.space(12)
                    spacing: Style.space(8)

                    Repeater {
                      model: root.rows
                      delegate: Column {
                        required property var modelData
                        required property int index
                        width: rowsColumn.width
                        spacing: Style.space(6)

                        PanelSectionHeader {
                          visible: modelData.kind === "group" || modelData.kind === "keyed" || modelData.kind === "section"
                          width: parent.width
                          text: (modelData.kind === "group" ? "\uf2d0 "
                               : modelData.kind === "keyed" ? "\uf24d " : "")
                              + (modelData.label || "")
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          topPadding: Style.spacing.md + Math.ceil(Style.font.caption * 0.15)
                        }

                        BoolRow {
                          visible: modelData.kind === "bool"
                          panel: root; row: modelData; rowIndex: index
                          width: parent.width
                        }
                        SliderRow {
                          visible: modelData.kind === "slider"
                          panel: root; row: modelData; rowIndex: index
                          width: parent.width
                        }
                        EnumRow {
                          visible: modelData.kind === "enum"
                          panel: root; row: modelData; rowIndex: index
                          width: parent.width
                        }
                      }
                    }
                  }
                }

                FocusScope {
                  id: searchScope
                  anchors.fill: parent
                  anchors.margins: Style.spacing.panelPadding
                  anchors.topMargin: 0
                  visible: root.searchMode

                  Column {
                    anchors.fill: parent
                    spacing: Style.space(8)

                    BorderSurface {
                      width: parent.width
                      height: Style.space(34)
                      radius: Style.cornerRadius
                      color: root.recessedColor
                      borderSpec: Border.flat(root.accent, 1)

                      Text {
                        anchors.fill: parent
                        anchors.leftMargin: Style.spacing.controlPaddingX
                        anchors.rightMargin: Style.spacing.controlPaddingX
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                        text: root.searchQuery !== "" ? (root.searchQuery + "\u258f") : ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }
                    }

                    ListView {
                      id: resultsList
                      width: parent.width
                      height: parent.height - Style.space(42)
                      clip: true
                      spacing: Style.space(4)
                      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                      model: root.searchResults
                      delegate: BorderSurface {
                        required property var modelData
                        required property int index
                        width: resultsList.width - Style.space(12)
                        height: Style.space(40)
                        radius: Style.cornerRadius
                        readonly property bool sel: root.searchSel === index
                        color: sel ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                        borderSpec: Border.none()

                        Column {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          anchors.leftMargin: Style.spacing.controlPaddingX
                          anchors.rightMargin: Style.spacing.controlPaddingX
                          spacing: 0

                          Text {
                            textFormat: Text.PlainText
                            text: modelData.label
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: modelData.panel + " · " + modelData.id
                            color: Qt.darker(root.foreground, 1.5)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            width: parent.width
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: { root.searchSel = index; root.openSearchResult() }
                          onContainsMouseChanged: if (containsMouse) root.searchSel = index
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          BottomBar {
            id: footer
            width: parent.width
            panel: root
            hints: root.footerHints
            context: root.footerContext
            contextColor: root.footerContextColor
          }
        }
      }
    }
  }
}
