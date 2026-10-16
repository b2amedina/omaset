.pragma library

// Pure transforms over the `omaset schema` JSON. No QML singletons here — the
// panel owns Process/state; this file just reshapes schema into a flat list of
// rows the content view can render with a Repeater.
//
// Row kinds:
//   title    panel title header (non-interactive)
//   group    group setting header (non-interactive)
//   keyed    keyed setting header (non-interactive)
//   bool     boolean toggle
//   slider   int/float with a bounded range
//   number   int with a wide range (coarse slider fallback: still a slider)
//   enum     enum (segmented ButtonGroup)

function settingKey(id, sub, key) {
  if (sub !== undefined && sub !== null && sub !== "") return id + "." + sub
  if (key !== undefined && key !== null && key !== "") return id + "@" + key
  return id
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

function fieldRow(id, sub, key, label, type, spec, effective) {
  if (type === "bool")
    return { kind: "bool", id: id, sub: sub, label: label,
             value: valueOf(effective, id, sub, key, spec.default) }
  if (type === "enum")
    return { kind: "enum", id: id, sub: sub, label: label,
             options: spec.options || [], segmented: true,
             value: valueOf(effective, id, sub, key, spec.default) }
  var min = spec.min !== undefined ? spec.min : 0
  var max = spec.max !== undefined ? spec.max : 100
  var range = max - min
  return {
    kind: "slider",
    id: id, sub: sub, label: label, type: type,
    value: valueOf(effective, id, sub, key, spec.default),
    min: min, max: max,
    integer: type === "int",
    step: type === "int" ? (range > 200 ? 5 : 1) : 0.01
  }
}

function rowsFor(panel, effective, keyedMap) {
  var rows = []
  if (!panel) return rows
  rows.push({ kind: "title", id: panel.id, title: panel.title })
  var settings = panel.settings || []
  for (var i = 0; i < settings.length; i++) {
    var s = settings[i]
    if (!s) continue

    if (s.type === "group") {
      rows.push({ kind: "group", id: s.id, label: s.label })
      var subs = s.subsettings || {}
      for (var sub in subs)
        rows.push(fieldRow(s.id, sub, undefined, subs[sub].label, subs[sub].type, subs[sub], effective))
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
      rows.push({ kind: "bool", id: s.id, label: s.label, value: s.value })
    } else if (s.type === "enum") {
      rows.push({ kind: "enum", id: s.id, label: s.label,
                  options: s.options || [], segmented: true, value: s.value })
    } else if (s.type === "int" || s.type === "float") {
      var min = s.min !== undefined ? s.min : 0
      var max = s.max !== undefined ? s.max : 100
      var range = max - min
      rows.push({
        kind: "slider",
        id: s.id, label: s.label, type: s.type, value: s.value,
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
              || row.kind === "number" || row.kind === "enum")
}
