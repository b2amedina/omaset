import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "components"
import "model.js" as Model

// omaset settings window. A keyboard-first, schema-driven frontend for the
// omaset RPC protocol: one long-lived `omaset rpc` process serves `schema`,
// `get`, `set`, `reset`, and the other operations. Launched from the CLI via
// `omarchy-shell shell toggle b2amedina.omaset '{}'` or an optional bar icon.
Item {
  id: root

  // ---- plugin lifecycle ------------------------------------------------
  property bool closingFromHost: false
  property var shell: null
  property var manifest: null

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    loadSchema()
    loadPreferences(function() { applyLaunchFloating() })
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
  readonly property color foreground: Commons.Color.foreground
  readonly property color background: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property string fontFamily: Style.font.family
  readonly property color sidebarColor: Qt.darker(background, 1.12)
  readonly property color recessedColor: Qt.darker(background, 1.35)

  // ---- omaset binary ---------------------------------------------------
  // The engine is bundled with the plugin (bin/omaset lives next to the QML),
  // so resolve it relative to the plugin's install directory. `omarchy plugin
  // add` always installs a plugin to <XDG_CONFIG_HOME>/omarchy/plugins/<id>/.
  // OMASET_BIN overrides for a separately-installed engine.
  readonly property string omasetBin: {
    var e = Quickshell.env("OMASET_BIN")
    if (e && e.length > 0) return e
    var id = (manifest && manifest.id) ? String(manifest.id) : "b2amedina.omaset"
    var cfg = Quickshell.env("XDG_CONFIG_HOME")
    if (!cfg || cfg.length === 0) cfg = Quickshell.env("HOME") + "/.config"
    return cfg + "/omarchy/plugins/" + id + "/bin/omaset"
  }

  // ---- RPC client ------------------------------------------------------
  // One long-lived `omaset rpc` process carries every schema/get/set call, so
  // opening a panel no longer spawns a process per setting and the UI no
  // longer has to serialize commands itself.
  RpcClient {
    id: rpc
    binary: root.omasetBin
  }

  function cloneObj(o) {
    var n = {}
    for (var k in o) n[k] = o[k]
    return n
  }

  // ---- model state -----------------------------------------------------
  // The settings-schema version this window knows how to render. The engine
  // stamps every `schema` reply with its own version; when the two differ the
  // engine and this window are out of step, so show an error rather than a
  // partial or mis-rendered list of settings.
  readonly property int supportedSchemaVersion: 1
  property string schemaError: ""
  property var schema: null
  property var panels: []
  property string activePanelId: ""
  property var effective: ({})   // group sub-fields + keyed values (schema can't express them)
  property var keyed: ({})       // id -> [keys]
  property var keyedMonitors: ({})    // id -> [monitor descriptors] (4.5 workspace layouts)
  property var selectedMonitor: ({})  // id -> connector name
  property var keyedLoaded: ({})      // id -> true once its keys/values are fetched
  property var rows: []
  property int changedCount: -1
  property var changedList: []     // `omaset changed --json` entries
  property var pendingSelect: null // deferred row selection for keyed jumps

  property int selectedSidebar: 0
  property int selectedRow: -1
  property string focusPane: "content"
  property int editingRow: -1

  // search
  property bool searchMode: false
  property string searchQuery: ""
  property var searchResults: []
  property int searchSel: 0

  // changed
  property bool changedMode: false
  property int changedSel: 0

  // help (keyboard reference, shown on "?")
  property bool helpMode: false
  // Keybinding reference: keys are literal; the action is localized by key.
  property var helpRows: [
    { keys: "j / k",         ak: "help.move",     af: "Move between settings" },
    { keys: "h / l",         ak: "help.adjust",   af: "Adjust a value" },
    { keys: "Tab",           ak: "help.pane",     af: "Switch pane" },
    { keys: "Space / Enter", ak: "help.activate", af: "Activate / edit" },
    { keys: "x",             ak: "help.reset",    af: "Reset to default" },
    { keys: "/",             ak: "help.search",   af: "Search" },
    { keys: "c",             ak: "help.changed",  af: "Changed" },
    { keys: "p",             ak: "help.prefs",    af: "Preferences" },
    { keys: "?",             ak: "help.help",     af: "This help" },
    { keys: "Esc",           ak: "help.close",    af: "Close" }
  ]

  // preferences (omaset's own config — not Omarchy settings, never in changed)
  property bool prefsMode: false
  property int prefsSel: 0
  property int prefEditing: -1
  property string prefError: ""
  property int refreshIntervalSec: 2
  property bool launchFloating: true
  property string timeFormat: "24h"   // resolved from the time_format preference
  property bool nightlightDirty: false // a night-light setting changed this session
  property bool interacting: false
  property string omasetVersion: ""   // engine version, shown under Preferences
  // Timestamp of the last completed write, used to let slow backends (the
  // nightlight toggle cold-starts hyprsunset) settle before the periodic
  // refresh re-reads their status and briefly shows a stale value.
  property double lastWrite: 0
  // The DropdownRow currently under the cursor (so activate can open it) and
  // whether its popup is open (so the keyCatcher yields keys to the list).
  property var activeDropdown: null
  property bool dropdownOpen: false

  // Plugin-local translations. Follows the language in ~/.config/omarchy/
  // language (Commons.I18n), falling back to English. Strings are in i18n/.
  readonly property var tr: i18n
  Commons.Translations {
    id: i18n
    directory: Qt.resolvedUrl("i18n")
  }

  // ---- window sizing ----------------------------------------------------
  // The window sizes to its content (widest footer hint + widest sidebar
  // title), scaled by the text size/display scale via Style.space(), and
  // capped at 90% of the focused monitor so a long translation ellipsizes
  // rather than outgrowing the screen. Logical DIP = physical / scale.
  readonly property int maxWindowWidth: {
    var m = Hyprland.focusedMonitor
    if (m && m.width && m.scale) return Math.round((m.width / m.scale) * 0.9)
    return Style.space(960)
  }
  readonly property int maxWindowHeight: {
    var m = Hyprland.focusedMonitor
    if (m && m.height && m.scale) return Math.round((m.height / m.scale) * 0.9)
    return Style.space(900)
  }

  // Widest sidebar title, measured without elision (implicitWidth of a Column
  // is its widest child).
  Column {
    id: titleMeasure
    visible: false
    Repeater {
      model: root.panels
      delegate: Text {
        required property var modelData
        text: root.tr.t("panel." + modelData.id, modelData.title)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // Sidebar width: the scale-aware default, grown to fit the widest title.
  readonly property int sidebarWidth: Math.max(Style.space(190),
    Style.space(30) + titleMeasure.implicitWidth + Style.spacing.md)

  ListModel {
    id: prefsModel
  }

  // ---- data loading ----------------------------------------------------
  // Message for a `schema` reply this window cannot render, or "" when the
  // reply is usable. An absent version means an engine older than this
  // contract; a different one means the two were built out of step.
  function schemaVersionError(v) {
    if (v === undefined || v === null)
      return "This omaset engine does not report a settings schema version, so "
        + "it is older than this window (which needs schema version "
        + supportedSchemaVersion + ")."
    if (Number(v) !== supportedSchemaVersion)
      return "This omaset engine speaks settings schema version " + v
        + ", but this window only understands version " + supportedSchemaVersion + "."
    return ""
  }

  function loadSchema() {
    rpc.call("schema", {}, function(obj, err) {
      var msg = err ? ("Could not read the settings schema from the omaset engine at "
          + omasetBin + ": " + err)
        : schemaVersionError(obj ? obj.schemaVersion : undefined)
      if (msg !== "") {
        if (root.schemaError !== msg) console.warn("omaset: " + msg)
        root.schemaError = msg
        return
      }
      root.schemaError = ""
      root.schema = obj
      if (obj && obj.panels && obj.panels.length) {
        root.panels = obj.panels
        if (root.activePanelId === "")
          root.activePanelId = obj.panels[0].id
      }
      // Seed group sub-values synchronously from the schema so their rows
      // render at the real value (not the declared default) on first paint.
      var eff = cloneObj(root.effective)
      if (obj && obj.panels) {
        for (var pi = 0; pi < obj.panels.length; pi++) {
          var settings = obj.panels[pi].settings || []
          for (var si = 0; si < settings.length; si++) {
            var s = settings[si]
            if (s.subvalues) {
              for (var sub in s.subvalues)
                eff[Model.settingKey(s.id, sub)] = s.subvalues[sub]
            }
          }
        }
      }
      root.effective = eff
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
    if (!root.schema || !root.schema.panels) return
    var pending = 0
    function done() {
      pending--
      if (pending <= 0) root.rebuildRows()
    }
    // Prefetch every keyed setting (not just the active panel) once, so
    // switching to a panel does not "fill in" its workspace rows later.
    for (var pi = 0; pi < root.schema.panels.length; pi++) {
      var settings = root.schema.panels[pi].settings || []
      for (var si = 0; si < settings.length; si++) {
        var s = settings[si]
        if (s.keyed) {
          pending++; loadKeyed(s.id, done)
        }
      }
    }
    if (pending === 0) root.rebuildRows()
  }

  function loadKeyed(id, onDone) {
    if (root.keyedLoaded[id]) { if (onDone) onDone(); return }
    root.keyedLoaded[id] = true
    rpc.call("keys", { id: id }, function(o) {
      var keys = (o && o.keys) ? o.keys : []
      var mons = (o && o.monitors) ? o.monitors : []
      var n = cloneObj(root.keyed)
      n[id] = keys
      root.keyed = n
      var nm = cloneObj(root.keyedMonitors)
      nm[id] = mons
      root.keyedMonitors = nm
      var sm = cloneObj(root.selectedMonitor)
      if (!sm[id] && mons.length > 0) sm[id] = mons[0].name
      root.selectedMonitor = sm

      var pending = null
      if (mons.length > 0) {
        var mon = null
        for (var i = 0; i < mons.length; i++)
          if (mons[i].name === root.selectedMonitor[id]) { mon = mons[i]; break }
        if (!mon) mon = mons[0]
        pending = mon.workspaces
      } else {
        pending = keys
      }
      loadKeyedValues(id, pending, onDone)
    })
  }

  function selectMonitor(id, name) {
    var sm = cloneObj(root.selectedMonitor)
    sm[id] = name
    root.selectedMonitor = sm
    root.rebuildRows()
    var mons = root.keyedMonitors[id] || []
    for (var i = 0; i < mons.length; i++) {
      if (mons[i].name === name) {
        loadKeyedValues(id, mons[i].workspaces, function() {
          root.rebuildRows()
          root.clampRow()
        })
        break
      }
    }
    root.clampRow()
  }

  // Fetch the values for a set of keyed keys, updating `effective` without
  // rebuilding, and call onDone once when all have returned. The caller
  // rebuilds once, so the rows populate atomically rather than one-by-one.
  function loadKeyedValues(id, keys, onDone) {
    if (!keys || keys.length === 0) { if (onDone) onDone(); return }
    var remaining = keys.length
    for (var i = 0; i < keys.length; i++) {
      rpc.call("get", { id: id, key: String(keys[i]) }, (function(k) {
        return function(o) {
          if (o) {
            var n = cloneObj(root.effective)
            n[Model.settingKey(id, undefined, k)] = o.value
            root.effective = n
          }
          remaining--
          if (remaining <= 0 && onDone) onDone()
        }
      })(keys[i]))
    }
  }

  function refreshChanged() {
    rpc.call("changed", {}, function(o) {
      var list = (o && o.changed && Array.isArray(o.changed)) ? o.changed : []
      root.changedList = list
      root.changedCount = list.length
      if (root.changedSel >= root.changedList.length)
        root.changedSel = Math.max(0, root.changedList.length - 1)
    })
  }

  property Timer changedTimer: Timer {
    interval: 500
    repeat: false
    onTriggered: root.refreshChanged()
  }
  function scheduleChanged() { changedTimer.restart() }

  // ---- preferences -----------------------------------------------------
  // Load preference values for display. Does NOT apply the launch_floating
  // rule — that happens on window open and on explicit change, so re-opening
  // the preferences overlay can't re-apply a stale value and clobber a toggle.
  function loadPreferences(onDone) {
    rpc.call("preferences", {}, function(o) {
      var list = (o && o.preferences && Array.isArray(o.preferences)) ? o.preferences : []
      root.omasetVersion = (o && o.version) ? String(o.version)
        : ((manifest && manifest.version) ? String(manifest.version) : "")
      prefsModel.clear()
      var newTimeFormat = root.timeFormat
      for (var i = 0; i < list.length; i++) {
        var p = list[i]
        prefsModel.append({
          key: p.key,
          type: p.type,
          label: p.label || "",
          description: p.description || "",
          value: String(p.value),
          def: String(p.default),
          min: (p.min !== undefined) ? p.min : 0,
          max: (p.max !== undefined) ? p.max : 0,
          options: (p.options && Array.isArray(p.options)) ? p.options.join(",") : "",
          resolved: (p.resolved !== undefined && p.resolved !== null) ? String(p.resolved) : "",
        })
        if (p.key === "refresh_interval_sec") root.refreshIntervalSec = Number(p.value)
        else if (p.key === "launch_floating") root.launchFloating = (p.value === true)
        else if (p.key === "time_format") {
          var r = (p.resolved !== undefined && p.resolved !== null) ? String(p.resolved) : String(p.value)
          newTimeFormat = (r === "12h") ? "12h" : "24h"
        }
      }
      if (newTimeFormat !== root.timeFormat) {
        root.timeFormat = newTimeFormat
        root.rebuildRows()
      }
      if (onDone) onDone()
    })
  }

  function applyPrefValue(key, value) {
    if (key === "refresh_interval_sec") {
      var n = Number(value)
      if (isFinite(n)) root.refreshIntervalSec = n
    }
    else if (key === "launch_floating") { root.launchFloating = (value === true); applyLaunchFloating() }
    else if (key === "time_format" && value !== "auto") {
      // "auto" needs the engine's resolved value, so it is applied through
      // loadPreferences() after the write round-trips.
      root.timeFormat = (value === "12h") ? "12h" : "24h"
      rebuildRows()
    }
  }

  function setPreference(key, value, onError) {
    // Optimistic local update so controls respond immediately; the backend
    // round-trip reconciles with the canonical value, and on an engine
    // rejection the optimistic value is rolled back and the error surfaced.
    var oldValue = ""
    for (var i = 0; i < prefsModel.count; i++) {
      if (prefsModel.get(i).key === key) {
        oldValue = String(prefsModel.get(i).value)
        prefsModel.setProperty(i, "value", String(value))
      }
    }
    applyPrefValue(key, value)

    rpc.call("preference_set", { key: key, value: value }, function(o, err) {
      if (err) {
        for (var k = 0; k < prefsModel.count; k++) {
          if (prefsModel.get(k).key === key) prefsModel.setProperty(k, "value", oldValue)
        }
        applyPrefValue(key, oldValue)
        if (onError) onError(String(err || "invalid value"))
        return
      }
      if (o && o.value !== undefined && o.value !== null) {
        for (var j = 0; j < prefsModel.count; j++) {
          if (prefsModel.get(j).key === key) prefsModel.setProperty(j, "value", String(o.value))
        }
        if (key === "time_format" && o.value === "auto") loadPreferences()
        else applyPrefValue(key, o.value)
      }
    })
  }

  // Apply the launch_floating preference by adding/removing the omaset
  // window's float rule in the managed hypr-window block. Persistent, so it
  // also governs how the window opens next time.
  function applyLaunchFloating() {
    rpc.call("ui_float", { enabled: root.launchFloating }, function() {})
  }

  // Periodic refresh while the window is visible and idle, so values changed
  // from outside omaset (hotkeys, `omarchy toggle`, file edits) don't go stale.
  property Timer refreshTimer: Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: window.visible && !root.searchMode && !root.changedMode && !root.prefsMode && !root.interacting && root.editingRow < 0 && !root.dropdownOpen
    onTriggered: root.pollRefresh()
  }
  function pollRefresh() {
    if (rpc.pendingCount() > 0) return   // never delay a user action
    if (Date.now() - root.lastWrite < 3000) return  // let a slow write settle
    loadSchema()
    loadPreferences()
    refreshChanged()
  }

  // ---- row model -------------------------------------------------------
  function rebuildRows() {
    root.rows = Model.rowsFor(activePanel(), effective, keyed, root.timeFormat, root.keyedMonitors, root.selectedMonitor,
      function(key, fallback) { return root.tr.t(key, fallback) })
    clampRow()
    applyPendingSelect()
  }

  // Panel icon glyph, declared in the panel's settings file (no hardcoded map).
  function panelIcon(p) {
    return (p && p.icon) ? p.icon : "\uf013"
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

  // Schedule settings are read by hyprsunset only at startup, so the app
  // restarts it once on close — not on every write. Remember that one of
  // them changed this session.
  function markNightlightDirty(id) {
    if (id === "nightlight_schedule" || id === "nightlight_start"
        || id === "nightlight_stop" || id === "nightlight_temperature")
      root.nightlightDirty = true
  }

  function rowKey(row) {
    if (row.sub !== undefined && row.sub !== null) return row.sub
    if (row.key !== undefined && row.key !== null) return row.key
    return undefined
  }

  function commit(row, v) {
    if (!row) return
    var key = rowKey(row)
    if (key !== undefined) {
      var k = Model.settingKey(row.id, row.sub, row.key)
      setEffective(k, v)
      rpc.call("set", { id: row.id, key: key, value: v }, function(o) {
        root.lastWrite = Date.now()
        if (o && o.value !== undefined && o.value !== null) setEffective(k, o.value)
        root.scheduleChanged()
      })
    } else {
      markNightlightDirty(row.id)
      setSchemaValue(row.id, v)
      rpc.call("set", { id: row.id, value: v }, function(o) {
        root.lastWrite = Date.now()
        if (o && o.value !== undefined && o.value !== null) setSchemaValue(row.id, o.value)
        root.scheduleChanged()
      })
    }
  }

  function resetRow(row) {
    if (!row) return
    markNightlightDirty(row.id)
    var key = Model.settingKey(row.id, row.sub, row.key)
    var keyArg = rowKey(row)
    var params = { id: row.id }
    if (keyArg !== undefined) params.key = keyArg
    rpc.call("reset", params, function() {
      root.lastWrite = Date.now()
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

  function cursorTo(i) {
    if (editingRow >= 0 && editingRow !== i) endEdit()
    focusPane = "content"; selectedRow = i
  }
  function cursorToSidebar(i) { focusPane = "sidebar"; selectedSidebar = i }

  function beginEdit(i) {
    if (i < 0 || i >= rows.length) return
    selectedRow = i
    focusPane = "content"
    editingRow = i
  }

  function endEdit() {
    if (editingRow < 0) return
    editingRow = -1
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

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
    if (focusPane === "sidebar") return
    var row = currentRow()
    if (row && row.kind === "slider") { stepSlider(row, dx); return }
    if (row && (row.kind === "enum" || row.kind === "dropdown")) { cycleEnum(row, dx); return }
    if (row && row.kind === "monitor") { cycleMonitor(row, dx); return }
    if (row && row.kind === "time") { stepTime(row, dx) }
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

  function stepTime(row, dx) {
    var nv = Model.stepTime(row.value, dx * 15)
    if (nv !== null && nv !== undefined) commit(row, nv)
  }

  function cycleEnum(row, dx) {
    var opts = row.options || []
    if (opts.length === 0) return
    var mapped = row.values && row.values.length > 0
    var vals = mapped ? row.values : opts
    var pos = -1
    if (mapped) {
      for (var i = 0; i < vals.length; i++)
        if (String(vals[i]) === String(row.value)) { pos = i; break }
    } else {
      pos = opts.indexOf(row.value)
    }
    if (pos < 0) pos = 0
    var np = (pos + dx + opts.length) % opts.length
    commit(row, vals[np])
  }

  function cycleMonitor(row, dx) {
    var mons = row.monitors || []
    if (mons.length === 0) return
    var idx = -1
    for (var i = 0; i < mons.length; i++)
      if (mons[i].name === row.selected) { idx = i; break }
    if (idx < 0) idx = 0
    var ni = (idx + dx + mons.length) % mons.length
    selectMonitor(row.id, mons[ni].name)
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
    else if (row.kind === "monitor") cycleMonitor(row, 1)
    else if (row.kind === "dropdown") { if (root.activeDropdown && root.activeDropdown.open) root.activeDropdown.open() }
    else if (row.kind === "slider") beginEdit(selectedRow)
    else if (row.kind === "time") beginEdit(selectedRow)
  }

  function resetCurrent() {
    if (searchMode) return
    resetRow(currentRow())
  }

  // ---- panel switching -------------------------------------------------
  function selectPanel(i) {
    if (i < 0 || i >= panels.length) return
    if (prefsMode) exitPrefs()
    if (changedMode) exitChanged()
    if (editingRow >= 0) endEdit()
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

  function selectRowByKey(id, sub, key) {
    var idx = interactiveIndices()
    for (var i = 0; i < idx.length; i++) {
      var r = rows[idx[i]]
      if (!r || r.id !== id) continue
      if (sub !== undefined && sub !== null && r.sub !== sub) continue
      if (key !== undefined && key !== null && r.key !== key) continue
      selectedRow = idx[i]; return true
    }
    return false
  }

  // Re-attempt a keyed jump once the panel's keys have loaded. Called from
  // rebuildRows(); clears itself when the row is found.
  function applyPendingSelect() {
    if (!pendingSelect) return
    var p = pendingSelect
    if (p.key !== undefined && p.key !== null) {
      var keys = (keyed && keyed[p.id]) || []
      if (keys.indexOf(p.key) < 0) return   // still waiting on `omaset keys`
    }
    pendingSelect = null
    if (!selectRowByKey(p.id, p.sub, p.key)) clampRow()
  }

  // ---- search ----------------------------------------------------------
  function enterSearch() {
    searchMode = true
    searchQuery = ""
    searchResults = []
    searchSel = 0
    focusPane = "content"
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
    rpc.call("search", { query: q }, function(o) {
      if (!root.searchMode) return
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

  // ---- changed ---------------------------------------------------------
  function enterChanged() {
    changedMode = true
    changedSel = 0
    focusPane = "content"
    refreshChanged()
  }

  function exitChanged() {
    changedMode = false
  }

  function moveChanged(dy) {
    if (changedList.length === 0) return
    changedSel = Math.max(0, Math.min(changedList.length - 1, changedSel + dy))
  }

  function changedLabel(r) {
    var label = r.label || r.id
    if (r.key !== undefined && r.key !== null) label += " " + r.key
    else if (r.sub !== undefined && r.sub !== null) label += " · " + r.sub
    return label
  }

  function openChangedResult() {
    if (changedList.length === 0) return
    var r = changedList[changedSel]
    if (!r) return
    var targetPanel = r.panel
    exitChanged()
    if (targetPanel) {
      var found = -1
      for (var i = 0; i < panels.length; i++) if (panels[i].id === targetPanel) { found = i; break }
      if (found >= 0) selectedSidebar = found
      activePanelId = targetPanel
      rebuildRows()
      loadPanelExtras()
    }
    if (r.key !== undefined && r.key !== null) {
      var keys = (keyed && keyed[r.id]) || []
      if (keys.indexOf(r.key) < 0) {
        pendingSelect = { id: r.id, sub: r.sub, key: r.key }
      } else if (!selectRowByKey(r.id, r.sub, r.key)) {
        clampRow()
      }
    } else if (!selectRowByKey(r.id, r.sub)) {
      clampRow()
    }
    focusPane = "content"
  }

  // ---- preferences -----------------------------------------------------
  function enterPrefs() {
    prefsMode = true
    prefsSel = 0
    prefEditing = -1
    prefError = ""
    focusPane = "content"
    loadPreferences()
  }

  function exitPrefs() {
    prefsMode = false
    prefEditing = -1
    prefError = ""
  }

  // ---- help (keyboard reference, "?") ------------------------------------
  function enterHelp() {
    helpMode = true
    focusPane = "content"
  }

  function exitHelp() {
    helpMode = false
  }

  function beginPrefEdit(i) {
    if (i < 0 || i >= prefsModel.count) return
    prefsSel = i
    prefEditing = i
    prefError = ""
  }

  function endPrefEdit() {
    prefEditing = -1
  }

  function movePrefs(dy) {
    if (prefsModel.count === 0) return
    prefsSel = Math.max(0, Math.min(prefsModel.count - 1, prefsSel + dy))
  }

  function currentPref() {
    return (prefsSel >= 0 && prefsSel < prefsModel.count) ? prefsModel.get(prefsSel) : null
  }

  function activatePref() {
    var p = currentPref()
    if (!p) return
    if (p.type === "bool") setPreference(p.key, p.value !== "true")
    else if (p.type === "enum") stepPref(1)
    else if (p.type === "int" || p.type === "float") beginPrefEdit(prefsSel)
  }

  function stepPref(dx) {
    var p = currentPref()
    if (!p) return
    if (p.type === "enum") {
      var opts = p.options || []
      if (opts.length === 0) return
      var pos = opts.indexOf(p.value !== "" ? p.value : p.def)
      if (pos < 0) pos = 0
      setPreference(p.key, opts[(pos + dx + opts.length) % opts.length])
    } else if (p.type === "int" || p.type === "float") {
      var v = (p.value === "") ? p.def : p.value
      var nv = Number(v) + dx
      if (p.min !== undefined && nv < p.min) nv = p.min
      if (p.max !== undefined && nv > p.max) nv = p.max
      setPreference(p.key, p.type === "int" ? Math.round(nv) : nv)
    }
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
  readonly property string footerHints: schemaError !== ""
    ? tr.t("footer.close", "esc close")
    : searchMode
    ? tr.t("footer.search", "esc clear")
    : (changedMode || prefsMode || helpMode)
    ? tr.t("footer.close", "esc close")
    : tr.t("footer.normal", "? help · esc close")
  readonly property string footerContext: schemaError !== ""
    ? tr.t("ui.schemaMismatch", "schema mismatch")
    : searchMode
    ? (searchResults.length > 0 ? tr.t("ui.settingsFound", "%1 settings found").replace("%1", String(searchResults.length)) : "")
    : changedMode
    ? (changedList.length > 0 ? tr.t("ui.changedCount", "%1 changed").replace("%1", String(changedList.length)) : tr.t("ui.noChanges", "no changes"))
    : prefsMode
    ? (prefError !== "" ? prefError : tr.t("ui.preferences", "Preferences"))
    : (changedCount > 0 ? tr.t("ui.changedCount", "%1 changed").replace("%1", String(changedCount)) : "")
  readonly property color footerContextColor: (searchMode || changedMode || prefsMode) ? (prefError !== "" ? urgent : accent) : urgent

  // ---- window ----------------------------------------------------------
  FloatingWindow {
    id: window
    title: "omaset Settings"
    color: root.background
    // Size to the content (sidebar titles), scale-aware, and capped at 90% of
    // the focused monitor. The footer is a short one-liner, so it no longer
    // drives width.
    implicitWidth: Math.min(root.maxWindowWidth,
      Math.max(Style.space(720),
        root.sidebarWidth + Style.space(530)))
    implicitHeight: Math.min(root.maxWindowHeight, Style.space(560))
    minimumSize: Qt.size(Style.space(480), Style.space(360))
    maximumSize: Qt.size(root.maxWindowWidth, root.maxWindowHeight)

    onVisibleChanged: {
      if (!visible) {
        if (root.nightlightDirty) {
          root.nightlightDirty = false
          rpc.call("hyprsunset_apply", {}, function() {})
        }
        if (!root.closingFromHost && root.shell && typeof root.shell.hide === "function")
          root.shell.hide("b2amedina.omaset")
      }
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
        // Nothing in the settings list is usable without a readable schema, so
        // only Esc (close) means anything here.
        if (root.schemaError !== "") {
          if (event.key === Qt.Key_Escape) root.requestClose()
          event.accepted = true
          return
        }
        if (root.editingRow >= 0) return
        if (root.prefEditing >= 0) return
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
        if (root.changedMode) {
          if (event.key === Qt.Key_Escape) { root.exitChanged(); event.accepted = true; return }
          if (event.key === Qt.Key_Down || event.text === "j") { root.moveChanged(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up || event.text === "k") { root.moveChanged(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openChangedResult(); event.accepted = true; return }
          return
        }
        if (root.prefsMode) {
          if (event.key === Qt.Key_Escape) { root.exitPrefs(); event.accepted = true; return }
          if (event.key === Qt.Key_Down || event.text === "j") { root.movePrefs(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up || event.text === "k") { root.movePrefs(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.activatePref(); event.accepted = true; return }
          if (event.key === Qt.Key_Right || event.text === "l") { root.stepPref(1); event.accepted = true; return }
          if (event.key === Qt.Key_Left || event.text === "h") { root.stepPref(-1); event.accepted = true; return }
          return
        }
        if (root.helpMode) {
          if (event.key === Qt.Key_Escape) { root.exitHelp(); event.accepted = true; return }
          return
        }
        if (event.text === "/") { root.enterSearch(); event.accepted = true; return }
        if (event.text === "c" || event.text === "C") { root.enterChanged(); event.accepted = true; return }
        if (event.text === "p" || event.text === "P") { root.enterPrefs(); event.accepted = true }
        if (event.text === "?") { root.enterHelp(); event.accepted = true }
      }

        PanelKeyCatcher {
          id: keyCatcher
          anchors.fill: parent
          blocked: root.schemaError !== "" || root.searchMode || root.changedMode || root.prefsMode || root.helpMode || root.editingRow >= 0 || root.prefEditing >= 0 || root.dropdownOpen

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
            visible: root.schemaError === ""
            width: parent.width
            height: visible ? parent.height - footer.height : 0

            // ---- sidebar ------------------------------------------------
            Rectangle {
              id: sidebar
              width: root.sidebarWidth
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

                    readonly property bool active: !root.searchMode && !root.changedMode && !root.prefsMode
                      && root.activePanelId === modelData.id
                    readonly property bool cursor: root.focusPane === "sidebar" && root.selectedSidebar === index

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: cursor
                        ? Style.hoverFillFor(root.foreground, root.accent)
                        : (active ? Commons.Color.menu.selectedBackground : "transparent")
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.spacing.controlPaddingX
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: root.panelIcon(modelData)
                      color: active ? Commons.Color.menu.selectedText : Qt.darker(root.foreground, 1.3)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(30)
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: root.tr.t("panel." + modelData.id, modelData.title)
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
                    text: root.searchMode ? "\uf002"
                      : (root.changedMode ? "\uf044"
                      : (root.prefsMode ? "\uf013" : root.panelIcon(root.activePanel())))
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconLarge
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.searchMode ? root.tr.t("ui.search", "Search")
                      : (root.changedMode ? root.tr.t("ui.changed", "Changed")
                      : (root.prefsMode ? root.tr.t("ui.preferences", "Preferences") : (root.activePanel() ? root.tr.t("panel." + root.activePanel().id, root.activePanel().title) : "")))
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
                  visible: !root.searchMode && !root.changedMode && !root.prefsMode && !root.helpMode
                  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                  ScrollBar.vertical.policy: rowsColumn.implicitHeight > scrollArea.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

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
                        DropdownRow {
                          visible: modelData.kind === "dropdown"
                          panel: root; row: modelData; rowIndex: index
                          width: parent.width
                        }
                        MonitorRow {
                          visible: modelData.kind === "monitor"
                          panel: root; row: modelData; rowIndex: index
                          width: parent.width
                        }
                        TimeRow {
                          visible: modelData.kind === "time"
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

                FocusScope {
                  id: changedScope
                  anchors.fill: parent
                  anchors.margins: Style.spacing.panelPadding
                  anchors.topMargin: 0
                  visible: root.changedMode

                  ListView {
                    id: changedResultsList
                    anchors.fill: parent
                    clip: true
                    spacing: Style.space(4)
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    model: root.changedList
                    delegate: BorderSurface {
                      required property var modelData
                      required property int index
                      width: changedResultsList.width - Style.space(12)
                      height: Style.space(48)
                      radius: Style.cornerRadius
                      readonly property bool sel: root.changedSel === index
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
                          text: root.changedLabel(modelData)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          font.bold: true
                          elide: Text.ElideRight
                          width: parent.width
                        }
                        Text {
                          textFormat: Text.PlainText
                          text: modelData.panel + " · " + modelData.value + " \u2192 " + modelData.default
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
                        onClicked: { root.changedSel = index; root.openChangedResult() }
                        onContainsMouseChanged: if (containsMouse) root.changedSel = index
                      }
                    }
                  }
                }

                FocusScope {
                  id: prefsScope
                  anchors.fill: parent
                  anchors.margins: Style.spacing.panelPadding
                  anchors.topMargin: 0
                  visible: root.prefsMode

                  // Engine version, dimmed like other secondary metadata and
                  // pinned under the preference rows.
                  Item {
                    id: versionBar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Style.space(22)

                    Rectangle {
                      anchors.top: parent.top
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: root.omasetVersion !== "" ? "omaset " + root.omasetVersion : ""
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  ListView {
                    id: prefsResultsList
                    anchors.fill: parent
                    anchors.bottomMargin: versionBar.height
                    clip: true
                    spacing: Style.space(8)
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    model: prefsModel
                    delegate: BorderSurface {
                      id: prefRow
                      required property int index
                      required property string key
                      required property string type
                      required property string label
                      required property string description
                      required property string value
                      required property string def
                      required property int min
                      required property int max
                      required property string options
                      required property string resolved

                      readonly property bool editing: root.prefEditing === index
                      readonly property string displayDescription:
                        (prefRow.key === "time_format" && prefRow.resolved !== "")
                        ? ((prefRow.description || "") + " (now " + prefRow.resolved + ")")
                        : (prefRow.description || "")

                      width: prefsResultsList.width - Style.space(12)
                      height: Style.space(64)
                      radius: Style.cornerRadius
                      readonly property bool sel: root.prefsSel === index
                      color: sel
                        ? Style.hoverFillFor(root.foreground, root.accent)
                        : Style.controlFill(false, false, root.foreground, root.accent)
                      borderSpec: sel ? Border.controlSpec("hover-cursor", root.foreground, root.accent) : Border.none()

                      MouseArea {
                        anchors.fill: parent
                        onClicked: root.prefsSel = index
                        onContainsMouseChanged: if (containsMouse) root.prefsSel = index
                      }

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.spacing.controlPaddingX
                        anchors.rightMargin: Style.spacing.controlPaddingX
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacing.rowPaddingX

                        Column {
                          width: parent.width - controlBox.width - parent.spacing
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.spacing.xs

                          Text {
                            textFormat: Text.PlainText
                            text: prefRow.label || ""
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: prefRow.displayDescription || ""
                            visible: prefRow.displayDescription !== ""
                            color: Qt.darker(root.foreground, 1.5)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                            width: parent.width
                          }
                        }

                        Item {
                          id: controlBox
                          width: Style.space(200)
                          height: Style.space(26)
                          anchors.verticalCenter: parent.verticalCenter

                          ToggleSwitch {
                            visible: prefRow.type === "bool"
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            checked: prefRow.value === "true"
                            rounded: Style.cornerRadius > 0
                            onToggled: {
                              root.prefsSel = index
                              root.setPreference(prefRow.key, prefRow.value !== "true")
                            }
                          }

                          ButtonGroup {
                            visible: prefRow.type === "enum"
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            options: prefRow.options !== "" ? prefRow.options.split(",") : []
                            value: prefRow.value !== "" ? prefRow.value : prefRow.def
                            cursorIndex: -1
                            foreground: root.foreground
                            background: root.background
                            accent: root.accent
                            fontFamily: root.fontFamily
                            onChanged: function(v) {
                              root.prefsSel = index
                              root.setPreference(prefRow.key, v)
                            }
                          }

                          PanelSlider {
                            id: prefSlider
                            visible: prefRow.type === "int" || prefRow.type === "float"
                            enabled: !prefRow.editing
                            anchors.left: parent.left
                            anchors.right: valueBox.left
                            anchors.rightMargin: Style.spacing.md
                            anchors.verticalCenter: parent.verticalCenter
                            bar: QtObject {
                              readonly property color foreground: root.foreground
                              readonly property color background: root.background
                              readonly property color urgent: root.accent
                              readonly property string fontFamily: root.fontFamily
                              readonly property string position: "top"
                              readonly property bool vertical: false
                              readonly property int barSize: 26
                            }
                            value: prefRow.value !== "" ? Number(prefRow.value) : Number(prefRow.def)
                            minimum: prefRow.min
                            maximum: prefRow.max
                            step: 1
                            integer: prefRow.type === "int"
                            onReleased: function(v) {
                              root.prefsSel = index
                              root.setPreference(prefRow.key, prefRow.type === "int" ? Math.round(v) : v)
                            }
                          }

                          Item {
                            id: valueBox
                            visible: prefRow.type === "int" || prefRow.type === "float"
                            width: prefRow.editing ? Style.space(64) : valueText.implicitWidth
                            height: Style.space(22)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                              id: valueText
                              anchors.fill: parent
                              visible: !prefRow.editing
                              textFormat: Text.PlainText
                              text: prefSlider.liveValue !== undefined
                                ? (prefRow.type === "int"
                                   ? String(Math.round(prefSlider.liveValue))
                                   : prefSlider.liveValue.toFixed(2))
                                : ""
                              horizontalAlignment: Text.AlignRight
                              verticalAlignment: Text.AlignVCenter
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                            }

                            TextField {
                              id: valueField
                              visible: prefRow.editing
                              anchors.fill: parent
                              horizontalAlignment: Text.AlignRight
                              foreground: root.foreground
                              accent: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              horizontalPadding: Style.spacing.controlGap
                              verticalPadding: 0
                              inputMethodHints: prefRow.type === "int"
                                ? Qt.ImhDigitsOnly : Qt.ImhFormattedNumbersOnly

                              onVisibleChanged: if (visible) {
                                text = prefRow.value !== "" ? prefRow.value : prefRow.def
                                Qt.callLater(function() {
                                  if (!valueField) return
                                  valueField.selectAll()
                                  valueField.forceActiveFocus()
                                })
                              }

                              onAccepted: {
                                var s = String(valueField.text).replace(/^\s+|\s+$/g, "")
                                // Reject obviously non-numeric input locally so
                                // the field stays open; the engine is still the
                                // authority for type + range validation on set.
                                if (!/^-?(?:\d+(?:\.\d*)?|\.\d+)$/.test(s)) {
                                  root.prefError = "enter a number"
                                  valueField.selectAll()
                                  return
                                }
                                var n = Number(s)
                                if (!isFinite(n)) {
                                  root.prefError = "enter a number"
                                  valueField.selectAll()
                                  return
                                }
                                if (prefRow.type === "int") n = Math.round(n)
                                else n = Math.round(n * 1000) / 1000
                                root.prefsSel = index
                                root.setPreference(prefRow.key, n, function(errMsg) {
                                  var hint = (prefRow.min !== undefined && prefRow.max !== undefined)
                                    ? "must be " + prefRow.min + ".." + prefRow.max : "invalid value"
                                  root.prefError = hint + " (" + errMsg + ")"
                                  root.beginPrefEdit(index)
                                  Qt.callLater(function() {
                                    if (valueField) { valueField.selectAll(); valueField.forceActiveFocus() }
                                  })
                                })
                              }

                              Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                  root.prefEditing = -1
                                  event.accepted = true
                                }
                              }
                            }

                            MouseArea {
                              anchors.fill: parent
                              visible: !prefRow.editing
                              cursorShape: Qt.IBeamCursor
                              onClicked: root.beginPrefEdit(index)
                            }
                          }
                        }
                      }
                    }
                  }
                }

                FocusScope {
                  id: helpScope
                  anchors.fill: parent
                  anchors.margins: Style.spacing.panelPadding
                  anchors.topMargin: 0
                  visible: root.helpMode

                  Flickable {
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: helpColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                      id: helpColumn
                      width: parent.width
                      spacing: Style.space(10)

                      Text {
                        textFormat: Text.PlainText
                        text: root.tr.t("ui.keybindings", "Keybindings")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.heading
                        font.bold: true
                      }

                      Repeater {
                        model: root.helpRows
                        delegate: Row {
                          required property var modelData
                          width: parent.width
                          spacing: Style.spacing.lg

                          Text {
                            width: Style.space(140)
                            horizontalAlignment: Text.AlignRight
                            textFormat: Text.PlainText
                            text: modelData.keys
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                          }
                          Text {
                            width: parent.width - Style.space(140) - Style.spacing.lg
                            textFormat: Text.PlainText
                            text: root.tr.t(modelData.ak, modelData.af)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Shown in place of the sidebar and settings list when the engine's
          // settings schema is one this window cannot render (see
          // supportedSchemaVersion). The window keeps its chrome and footer, so
          // a version skew reads as an error rather than an empty window.
          Item {
            id: schemaErrorView
            visible: root.schemaError !== ""
            width: parent.width
            height: visible ? parent.height - footer.height : 0

            Column {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.spacing.xl * 4, Style.space(360))
              spacing: Style.spacing.lg

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: "\uf071"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: "Unsupported settings schema"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.schemaError
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: "Update the plugin to match:\nomarchy plugin update "
                  + ((root.manifest && root.manifest.id) ? root.manifest.id : "b2amedina.omaset")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
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
