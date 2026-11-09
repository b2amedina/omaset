import QtQuick
import Quickshell.Io

// omaset's own catalog resolver for the settings window. A fresh
// implementation (not a copy of Commons.Translations) that takes its
// language from the bound `language` property — so `omaset ui --lang fr`
// previews French without changing the desktop language — while keeping
// Commons.Translations' contract: en -> base -> language merge, strings
// or CLDR plural objects, %1 holes filled by the caller.
QtObject {
  id: root

  // A filesystem path or file:// URL (Qt.resolvedUrl("../i18n") from Panel).
  property var directory: ""

  // Bound by Panel to the effective UI language (override else desktop).
  property string language: "en"

  readonly property string baseLanguage: language.split("-")[0]
  readonly property string directoryPath: String(directory).replace(/^file:\/\//, "").replace(/\/+$/, "")

  readonly property var englishStrings: parseCatalog(englishFile.text())
  readonly property var baseStrings: parseCatalog(baseFile.text())
  readonly property var languageStrings: parseCatalog(languageFile.text())
  readonly property var strings: {
    var merged = ({})
    var layers = [root.englishStrings, root.baseStrings, root.languageStrings]
    for (var i = 0; i < layers.length; i++)
      for (var key in layers[i])
        if (typeof layers[i][key] === "string" || (layers[i][key] && typeof layers[i][key] === "object")) merged[key] = layers[i][key]
    return merged
  }

  function t(key, fallback) {
    var value = root.strings[key]
    if (value && typeof value === "object") value = value.other
    if (typeof value === "string" && value.length > 0) return value
    return fallback !== undefined ? fallback : key
  }

  function tn(key, count, fallback) {
    var layers = [[root.languageStrings, root.language], [root.baseStrings, root.baseLanguage], [root.englishStrings, "en"]]
    for (var i = 0; i < layers.length; i++) {
      var value = pick(layers[i][0][key], layers[i][1], count)
      if (typeof value === "string" && value.length > 0) return value
    }
    return fallback !== undefined ? fallback : key
  }

  function parseCatalog(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function catalogPath(code) {
    return root.directoryPath !== "" ? root.directoryPath + "/" + code + ".json" : ""
  }

  // ---- plurals (CLDR cardinals, mirroring Omarchy's plural.jq/Plural.js) ---
  function within(v, lo, hi) { return v >= lo && v <= hi }

  function category(code, count) {
    var n = Math.abs(Math.trunc(Number(count) || 0))
    var n10 = n % 10
    var n100 = n % 100
    var millions = n !== 0 && n % 1000000 === 0
    switch (String(code || "")) {
    case "ja": case "ko": case "zh-CN": case "zh-TW": case "th": case "vi": case "id": case "ms":
      return "other"
    case "hi": case "bn": case "fa": case "si":
      return n <= 1 ? "one" : "other"
    case "fr": case "pt-BR":
      return n <= 1 ? "one" : millions ? "many" : "other"
    case "ca": case "es-MX": case "it": case "pt":
      return n === 1 ? "one" : millions ? "many" : "other"
    case "fil":
      return (n10 === 4 || n10 === 6 || n10 === 9) ? "other" : "one"
    case "is":
      return n10 === 1 && n100 !== 11 ? "one" : "other"
    case "cs": case "sk":
      return n === 1 ? "one" : within(n, 2, 4) ? "few" : "other"
    case "pl":
      if (n === 1) return "one"
      return within(n10, 2, 4) && !within(n100, 12, 14) ? "few" : "many"
    case "ru": case "uk":
      if (n10 === 1 && n100 !== 11) return "one"
      return within(n10, 2, 4) && !within(n100, 12, 14) ? "few" : "many"
    case "hr": case "sr":
      if (n10 === 1 && n100 !== 11) return "one"
      return within(n10, 2, 4) && !within(n100, 12, 14) ? "few" : "other"
    case "sl":
      if (n100 === 1) return "one"
      if (n100 === 2) return "two"
      return within(n100, 3, 4) ? "few" : "other"
    case "lt":
      if (within(n100, 11, 19)) return "other"
      return n10 === 1 ? "one" : n10 >= 2 ? "few" : "other"
    case "lv":
      if (n10 === 0 || within(n100, 11, 19)) return "zero"
      return n10 === 1 ? "one" : "other"
    case "ro":
      if (n === 1) return "one"
      return n === 0 || within(n100, 1, 19) ? "few" : "other"
    case "ar":
      if (n <= 2) return ["zero", "one", "two"][n]
      return within(n100, 3, 10) ? "few" : within(n100, 11, 99) ? "many" : "other"
    case "he":
      return n === 1 ? "one" : n === 2 ? "two" : "other"
    case "ga":
      if (n <= 2) return n === 0 ? "other" : n === 1 ? "one" : "two"
      return within(n, 3, 6) ? "few" : within(n, 7, 10) ? "many" : "other"
    default:
      return n === 1 ? "one" : "other"
    }
  }

  function pick(entry, code, count) {
    if (typeof entry === "string") return entry
    if (!entry || typeof entry !== "object") return undefined
    var form = entry[category(code, count)]
    if (typeof form === "string" && form.length > 0) return form
    return typeof entry.other === "string" ? entry.other : undefined
  }

  property FileView englishFile: FileView {
    path: root.catalogPath("en")
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  property FileView baseFile: FileView {
    path: root.baseLanguage !== root.language && root.baseLanguage !== "en" ? root.catalogPath(root.baseLanguage) : ""
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  property FileView languageFile: FileView {
    path: root.language !== "en" ? root.catalogPath(root.language) : ""
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }
}
