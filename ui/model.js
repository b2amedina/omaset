.pragma library

// Pure transforms over the `omaset schema` JSON. No QML singletons here — the
// panel owns Process/state; this file just reshapes schema into a flat list of
// rows the content view can render with a Repeater.
//
// Row kinds:
//   title    panel title header (non-interactive)
//   section  presentational section header (non-interactive)
//   group    group setting header (non-interactive)
//   keyed    keyed setting header (non-interactive)
//   bool     boolean toggle
//   slider   int/float with a bounded range
//   number   int with a wide range (coarse slider fallback: still a slider)
//   enum     enum (segmented ButtonGroup)
//   time     time-of-day (HH:MM stored, shown per the time format preference)
//
// `tr(key, fallback)` localizes user-facing text: the key is a stable catalog
// id, the fallback is the English string from the schema. It is threaded
// through every function that emits a label.

// A numeric setting may declare labelled choices (options = [{value,label}]),
// which the UI renders as a segmented control while storing the numeric value.
function hasChoices(spec) {
  return !!spec && Array.isArray(spec.options) && spec.options.length > 0
    && spec.options[0] !== null && typeof spec.options[0] === "object"
}

// Look up a catalog key, falling back to the English string when `tr` is
// absent (engine-side use) or the key is untranslated.
function L(tr, key, fallback) {
  return tr ? tr(key, fallback) : fallback
}

function settingKey(id, sub, key) {
  if (sub !== undefined && sub !== null && sub !== "") return id + "." + sub
  if (key !== undefined && key !== null && key !== "") return id + "@" + key
  return id
}

// ---- time helpers -------------------------------------------------------
// A shared JS parse of the stored canonical HH:MM value. The Lua engine is the
// authority for input validation; these exist only to display, step, and
// validate local edits so the row can react before round-tripping to the CLI.

function pad2(n) { return (n < 10 ? "0" : "") + n }

function parseTime(value) {
  if (value === undefined || value === null) return null
  var s = String(value).replace(/^\s+|\s+$/g, "")
  var m = s.match(/^(\d{1,2}):(\d{2})$/)
  if (m) {
    var h = Number(m[1]), mi = Number(m[2])
    if (h >= 0 && h <= 23 && mi >= 0 && mi <= 59) return { h: h, m: mi }
  }
  m = s.match(/^(\d{1,2}):(\d{2})\s*([AaPp])\.?[Mm]\.?$/)
  if (m) {
    var h12 = Number(m[1]), mi2 = Number(m[2])
    if (h12 >= 1 && h12 <= 12 && mi2 >= 0 && mi2 <= 59) {
      var pm = (m[3] === "p" || m[3] === "P")
      var hh = (h12 === 12) ? (pm ? 12 : 0) : (pm ? h12 + 12 : h12)
      return { h: hh, m: mi2 }
    }
  }
  return null
}

function canonicalTime(value) {
  var t = parseTime(value)
  return t ? pad2(t.h) + ":" + pad2(t.m) : null
}

function formatTime(value, timeFormat) {
  var t = parseTime(value)
  if (!t) return (value === undefined || value === null) ? "" : String(value)
  if (timeFormat === "12h") {
    var h = t.h % 12
    if (h === 0) h = 12
    return h + ":" + pad2(t.m) + (t.h < 12 ? " AM" : " PM")
  }
  return pad2(t.h) + ":" + pad2(t.m)
}

function stepTime(value, minutes) {
  var t = parseTime(value)
  if (!t) return null
  var total = ((t.h * 60 + t.m + minutes) % 1440 + 1440) % 1440
  return pad2(Math.floor(total / 60)) + ":" + pad2(total % 60)
}

// A human duration for a seconds value that is not one of the clean presets
// (e.g. 150 -> "2 min 30 sec"), so a legacy value still reads clearly.
function formatDuration(seconds, tr) {
  var s = Number(seconds)
  if (!isFinite(s)) return ""
  if (s <= 0) return L(tr, "unit.never", "Never")
  if (s < 60) return L(tr, "unit.sec", "%1 sec").replace("%1", String(s))
  if (s < 3600) {
    var m = Math.floor(s / 60)
    var r = s % 60
    if (r === 0) return L(tr, "unit.min", "%1 min").replace("%1", String(m))
    return L(tr, "unit.minSec", "%1 min %2 sec").replace("%1", String(m)).replace("%2", String(r))
  }
  var h = Math.floor(s / 3600)
  var m = Math.round((s % 3600) / 60)
  if (m === 0)
    return L(tr, h === 1 ? "unit.hour" : "unit.hours", h === 1 ? "%1 hour" : "%1 hours").replace("%1", String(h))
  return L(tr, "unit.hrMin", "%1 hr %2 min").replace("%1", String(h)).replace("%2", String(m))
}

// `effective` maps settingKey(...) -> value for group sub-fields and keyed
// values (which `schema` can't express). Top-level values live on the schema
// setting's own `value` and are mutated by the panel.
function valueOf(effective, id, sub, key, fallback) {
  var k = settingKey(id, sub, key)
  if (effective && effective.hasOwnProperty(k)
      && effective[k] !== null && effective[k] !== undefined)
    return effective[k]
  return fallback
}

// Split a setting's `options` into parallel label/value arrays, handling both
// plain strings (label == value) and { value, label } objects. The label is
// localized against `setting.<id>.option.<value>`.
function choiceLists(spec, id, tr) {
  var labels = [], values = []
  var opts = spec.options || []
  for (var i = 0; i < opts.length; i++) {
    var o = opts[i]
    if (o && typeof o === "object" && o.label !== undefined) {
      labels.push(L(tr, "setting." + id + ".option." + o.value, String(o.label)))
      values.push(o.value)
    } else {
      labels.push(String(o))
      values.push(o)
    }
  }
  return { labels: labels, values: values }
}

function choiceRow(id, sub, key, label, spec, value, tr) {
  var lists = choiceLists(spec, id, tr)
  var labels = lists.labels
  var values = lists.values
  // A short list reads as a segmented row; many discrete choices read better
  // as a dropdown (macOS-style), e.g. idle timeouts.
  var kind = spec.options.length > 5 ? "dropdown" : "enum"

  // A value that is not one of the presets (a legacy stock default like 150s,
  // or anything hand-set) stays selectable as a labelled "custom" entry, so the
  // current value is never hidden or silently rounded.
  if (kind === "dropdown") {
    var isPreset = false
    if (value !== undefined && value !== null) {
      for (var i = 0; i < values.length; i++)
        if (String(values[i]) === String(value)) { isPreset = true; break }
      if (!isPreset) {
        labels.unshift(L(tr, "ui.custom", "Custom · %1").replace("%1", formatDuration(value, tr)))
        values.unshift(value)
      }
    }
  }

  return { kind: kind, id: id, sub: sub, label: label,
           description: L(tr, "setting." + id + ".description", spec.description),
           segmented: kind === "enum",
           options: labels, values: values, value: value }
}

function fieldRow(id, sub, key, label, type, spec, effective, timeFormat, tr) {
  var desc = L(tr, "setting." + id + "." + sub + ".description", spec.description)
  if (type === "bool")
    return { kind: "bool", id: id, sub: sub, label: label,
             description: desc,
             value: valueOf(effective, id, sub, key, spec.default) }
  if (type === "enum")
    return { kind: "enum", id: id, sub: sub, label: label,
             description: desc,
             options: spec.options || [], segmented: true,
             value: valueOf(effective, id, sub, key, spec.default) }
  if (type === "time")
    return { kind: "time", id: id, sub: sub, label: label,
             description: desc, timeFormat: timeFormat,
             value: valueOf(effective, id, sub, key, spec.default) }
  if ((type === "int" || type === "float") && hasChoices(spec))
    return choiceRow(id, sub, key, label, spec,
                     valueOf(effective, id, sub, key, spec.default), tr)
  var min = spec.min !== undefined ? spec.min : 0
  var max = spec.max !== undefined ? spec.max : 100
  var range = max - min
  return {
    kind: "slider",
    id: id, sub: sub, label: label, type: type,
    description: desc,
    value: valueOf(effective, id, sub, key, spec.default),
    min: min, max: max,
    integer: type === "int",
    step: type === "int" ? (range > 200 ? 5 : 1) : 0.01
  }
}

function rowsFor(panel, effective, keyedMap, timeFormat, monitorMap, selectedMonitor, tr) {
  var fmt = (timeFormat === "12h") ? "12h" : "24h"
  var rows = []
  if (!panel) return rows
  rows.push({ kind: "title", id: panel.id, title: L(tr, "panel." + panel.id, panel.title) })
  var settings = panel.settings || []
  var currentSection = ""
  // "Workspace N" label, localized through the passed-in tr.
  function workspaceLabel(n) {
    return L(tr, "ui.workspace", "Workspace %1").replace("%1", String(n))
  }
  for (var i = 0; i < settings.length; i++) {
    var s = settings[i]
    if (!s) continue

    var sec = (s.section !== undefined && s.section !== null) ? s.section : ""
    if (sec !== currentSection) {
      currentSection = sec
      if (sec !== "") {
        var secKey = "section." + panel.id + (s.section_key ? "." + s.section_key : "")
        rows.push({ kind: "section", label: L(tr, secKey, sec) })
      }
    }

    if (s.type === "group") {
      rows.push({ kind: "group", id: s.id, label: L(tr, "setting." + s.id, s.label) })
      var subs = s.subsettings || {}
      for (var sub in subs)
        rows.push(fieldRow(s.id, sub, undefined,
          L(tr, "setting." + s.id + "." + sub, subs[sub].label),
          subs[sub].type, subs[sub], effective, fmt, tr))
      continue
    }

    if (s.keyed) {
      rows.push({ kind: "keyed", id: s.id, label: L(tr, "setting." + s.id, s.label) })
      var lists = choiceLists(s, s.id, tr)
      var optLabels = lists.labels
      var optValues = lists.values
      // Default to the first option while the value loads, so rows do not
      // flash empty before jumping to their real layout.
      var defVal = optValues.length > 0 ? optValues[0] : undefined
      var mons = (monitorMap && monitorMap[s.id]) || []
      if (mons.length > 0) {
        // Monitor-grouped: pick a monitor, then show its workspaces 1..10
        // (labelled by slot; the stored key is the global id).
        var sel = (selectedMonitor && selectedMonitor[s.id]) || mons[0].name
        rows.push({ kind: "monitor", id: s.id, monitors: mons, selected: sel })
        var mon = null
        for (var m = 0; m < mons.length; m++)
          if (mons[m].name === sel) { mon = mons[m]; break }
        if (!mon) mon = mons[0]
        for (var w = 0; w < mon.workspaces.length; w++) {
          var gid = mon.workspaces[w]
          rows.push({
            kind: "enum", id: s.id, key: gid, slot: w + 1,
            label: workspaceLabel(w + 1),
            options: optLabels, values: optValues, segmented: true,
            value: valueOf(effective, s.id, undefined, gid, defVal)
          })
        }
      } else {
        var keys = (keyedMap && keyedMap[s.id]) || []
        for (var k = 0; k < keys.length; k++) {
          var key = keys[k]
          rows.push({
            kind: "enum", id: s.id, key: key,
            label: workspaceLabel(key),
            options: optLabels, values: optValues, segmented: true,
            value: valueOf(effective, s.id, undefined, key, defVal)
          })
        }
      }
      continue
    }

    if (s.type === "bool") {
      rows.push({ kind: "bool", id: s.id, label: L(tr, "setting." + s.id, s.label),
                  description: L(tr, "setting." + s.id + ".description", s.description), value: s.value })
    } else if (s.type === "enum") {
      if (hasChoices(s)) {
        rows.push(choiceRow(s.id, undefined, undefined, L(tr, "setting." + s.id, s.label), s, s.value, tr))
      } else {
        rows.push({ kind: "enum", id: s.id, label: L(tr, "setting." + s.id, s.label),
                    description: L(tr, "setting." + s.id + ".description", s.description),
                    options: s.options || [], segmented: true, value: s.value })
      }
    } else if (s.type === "time") {
      rows.push({ kind: "time", id: s.id, label: L(tr, "setting." + s.id, s.label),
                  description: L(tr, "setting." + s.id + ".description", s.description), timeFormat: fmt, value: s.value })
    } else if ((s.type === "int" || s.type === "float") && hasChoices(s)) {
      rows.push(choiceRow(s.id, undefined, undefined, L(tr, "setting." + s.id, s.label), s, s.value, tr))
    } else if (s.type === "int" || s.type === "float") {
      var min = s.min !== undefined ? s.min : 0
      var max = s.max !== undefined ? s.max : 100
      var range = max - min
      rows.push({
        kind: "slider",
        id: s.id, label: L(tr, "setting." + s.id, s.label), type: s.type, value: s.value,
        description: L(tr, "setting." + s.id + ".description", s.description),
        min: min, max: max,
        integer: s.type === "int",
        step: s.type === "int" ? (range > 200 ? 5 : 1) : 0.01
      })
    }
  }
  return rows
}

function isInteractive(row) {
  return row && (row.kind === "bool" || row.kind === "slider"
              || row.kind === "number" || row.kind === "enum"
              || row.kind === "time" || row.kind === "monitor"
              || row.kind === "dropdown")
}
