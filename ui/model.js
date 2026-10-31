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

// A numeric setting may declare labelled choices (options = [{value,label}]),
// which the UI renders as a segmented control while storing the numeric value.
function hasChoices(spec) {
  return !!spec && Array.isArray(spec.options) && spec.options.length > 0
    && spec.options[0] !== null && typeof spec.options[0] === "object"
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

function choiceRow(id, sub, key, label, spec, value) {
  var labels = [], values = []
  for (var i = 0; i < spec.options.length; i++) {
    labels.push(String(spec.options[i].label))
    values.push(spec.options[i].value)
  }
  return { kind: "enum", id: id, sub: sub, label: label,
           description: spec.description, segmented: true,
           options: labels, values: values, value: value }
}

function fieldRow(id, sub, key, label, type, spec, effective, timeFormat) {
  if (type === "bool")
    return { kind: "bool", id: id, sub: sub, label: label,
             description: spec.description,
             value: valueOf(effective, id, sub, key, spec.default) }
  if (type === "enum")
    return { kind: "enum", id: id, sub: sub, label: label,
             description: spec.description,
             options: spec.options || [], segmented: true,
             value: valueOf(effective, id, sub, key, spec.default) }
  if (type === "time")
    return { kind: "time", id: id, sub: sub, label: label,
             description: spec.description, timeFormat: timeFormat,
             value: valueOf(effective, id, sub, key, spec.default) }
  if ((type === "int" || type === "float") && hasChoices(spec))
    return choiceRow(id, sub, key, label, spec,
                     valueOf(effective, id, sub, key, spec.default))
  var min = spec.min !== undefined ? spec.min : 0
  var max = spec.max !== undefined ? spec.max : 100
  var range = max - min
  return {
    kind: "slider",
    id: id, sub: sub, label: label, type: type,
    description: spec.description,
    value: valueOf(effective, id, sub, key, spec.default),
    min: min, max: max,
    integer: type === "int",
    step: type === "int" ? (range > 200 ? 5 : 1) : 0.01
  }
}

function rowsFor(panel, effective, keyedMap, timeFormat) {
  var fmt = (timeFormat === "12h") ? "12h" : "24h"
  var rows = []
  if (!panel) return rows
  rows.push({ kind: "title", id: panel.id, title: panel.title })
  var settings = panel.settings || []
  var currentSection = ""
  for (var i = 0; i < settings.length; i++) {
    var s = settings[i]
    if (!s) continue

    var sec = (s.section !== undefined && s.section !== null) ? s.section : ""
    if (sec !== currentSection) {
      currentSection = sec
      if (sec !== "")
        rows.push({ kind: "section", label: sec })
    }

    if (s.type === "group") {
      rows.push({ kind: "group", id: s.id, label: s.label })
      var subs = s.subsettings || {}
      for (var sub in subs)
        rows.push(fieldRow(s.id, sub, undefined, subs[sub].label, subs[sub].type, subs[sub], effective, fmt))
      continue
    }

    if (s.keyed) {
      rows.push({ kind: "keyed", id: s.id, label: s.label })
      var keys = (keyedMap && keyedMap[s.id]) || []
      for (var k = 0; k < keys.length; k++) {
        var key = keys[k]
        rows.push({
          kind: "enum", id: s.id, key: key,
          label: "Workspace " + key,
          options: s.options || [], segmented: true,
          value: valueOf(effective, s.id, undefined, key)
        })
      }
      continue
    }

    if (s.type === "bool") {
      rows.push({ kind: "bool", id: s.id, label: s.label,
                  description: s.description, value: s.value })
    } else if (s.type === "enum") {
      rows.push({ kind: "enum", id: s.id, label: s.label,
                  description: s.description,
                  options: s.options || [], segmented: true, value: s.value })
    } else if (s.type === "time") {
      rows.push({ kind: "time", id: s.id, label: s.label,
                  description: s.description, timeFormat: fmt, value: s.value })
    } else if ((s.type === "int" || s.type === "float") && hasChoices(s)) {
      rows.push(choiceRow(s.id, undefined, undefined, s.label, s, s.value))
    } else if (s.type === "int" || s.type === "float") {
      var min = s.min !== undefined ? s.min : 0
      var max = s.max !== undefined ? s.max : 100
      var range = max - min
      rows.push({
        kind: "slider",
        id: s.id, label: s.label, type: s.type, value: s.value,
        description: s.description,
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
              || row.kind === "time")
}
