import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// The Browser Router group content: the list of browsers with enable switches
// and labels, and the routing rules with remove and add. Rendered below the
// "Browser router" section header that Panel.qml provides.
//
// Keyboard navigation is driven by the panel: Panel.moveV/activate/resetCurrent
// delegate to moveVertical/activateFocus/removeFocus, so this component does
// not need (and must not fight for) its own focus.
Item {
  id: root

  property var panel: null
  property var row: ({})
  property int rowIndex: -1

  readonly property bool rtl: panel ? panel.rtl : false
  readonly property bool hasCursor: panel ? (panel.focusPane === "content" && panel.selectedRow === rowIndex) : false
  readonly property color fg: panel ? panel.foreground : Commons.Color.foreground
  readonly property color accent: panel ? panel.accent : Commons.Color.accent
  readonly property color bg: panel ? panel.background : Commons.Color.background
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  property var browsers: []
  property var rules: []
  // Disabled (greyed out, non-interactive) when the default browser is not the
  // router. Reactive so it updates as soon as the default browser changes.
  readonly property bool disabled: {
    if (!root.panel || !root.panel.schema || !root.panel.schema.panels) return false
    var panels = root.panel.schema.panels
    for (var i = 0; i < panels.length; i++) {
      var settings = panels[i].settings || []
      for (var j = 0; j < settings.length; j++) {
        if (settings[j].id === "default_browser")
          return settings[j].value !== "browser-router.desktop"
      }
    }
    return false
  }
  property string newDomain: ""
  property string newBrowser: ""
  property string pendingInstallId: ""
  property bool loading: true
  property bool hasLoaded: false
  property int focusIndex: -1
  // True while typing in a text field (the panel key catcher is blocked).
  property bool textEditing: false

  implicitWidth: contentColumn.implicitWidth
  implicitHeight: contentColumn.implicitHeight

  // True while j/k is navigating inside the component's sub-rows.
  readonly property bool active: root.focusIndex >= 0

  // ---- internal keyboard focus (driven by the panel) ---------------
  function browserCount() { return root.browsers.length }
  function ruleCount() { return root.flatRules.length }
  function focusCount() { return root.browserCount() + root.ruleCount() + 1 }

  function moveVertical(dy) {
    var total = root.focusCount()
    if (total === 0) return false
    if (root.focusIndex < 0) {
      if (dy > 0) { root.focusIndex = 0; return true }
      return false
    }
    var next = root.focusIndex + dy
    if (next < 0) return false          // top edge: leave to the panel row
    if (next >= total) return true      // bottom edge: stay (consume the move)
    root.focusIndex = next
    return true
  }

  // h / l: within a browser row, focus its label; within a rule row or the
  // add form, cycle the browser.
  function moveHorizontal(dx) {
    var i = root.focusIndex
    if (i < 0) return
    if (i < root.browserCount()) {
      var b = browserRepeater.itemAt(i)
      if (b && b.labelField) {
        b.labelField.forceActiveFocus()
        root.textEditing = true
        // Block the panel key catcher so Enter commits the label instead of
        // toggling the checkbox.
        if (root.panel && root.panel.editingRow !== root.rowIndex) root.panel.beginEdit(root.rowIndex)
      }
    } else if (i > root.browserCount()) {
      var r = root.flatRules[i - root.browserCount() - 1]
      if (r) root.cycleRuleBrowser(r.domain, r.browser)
    } else {
      root.cycleNewBrowser()
    }
  }

  function enter() { root.focusIndex = 0 }
  function leave() { root.focusIndex = -1; root.textEditing = false }

  function activateFocus() {
    var i = root.focusIndex
    if (i < 0) return
    // While editing a text field, Enter/Space belongs to the field; never
    // toggle the checkbox or cycle a rule in that state.
    if (root.textEditing) return
    if (i < root.browserCount()) {
      var b = root.browsers[i]
      if (b) root.toggleBrowser(b.id, b.enabled)
    } else if (i === root.browserCount()) {
      // Add form: focus the domain field for typing.
      if (addDomainField) { addDomainField.forceActiveFocus(); root.textEditing = true }
    } else {
      var r = root.flatRules[i - root.browserCount() - 1]
      if (r) root.cycleRuleBrowser(r.domain, r.browser)
    }
  }

  function removeFocus() {
    var i = root.focusIndex
    if (i <= root.browserCount()) return
    var r = root.flatRules[i - root.browserCount() - 1]
    if (r) root.removeDomain(r.domain)
  }

  // Keep the focused sub-row visible in the panel's scroll view. Scroll to the
  // specific sub-row, not the whole (tall) component, so the view doesn't jump
  // to the bottom/rules.
  function ensureFocusVisible() {
    if (!root.panel || root.focusIndex < 0) return
    var item = null
    if (root.focusIndex < root.browserCount())
      item = browserRepeater.itemAt(root.focusIndex)
    else if (root.focusIndex > root.browserCount())
      item = rulesRepeater.itemAt(root.focusIndex - root.browserCount() - 1)
    if (item) root.panel.ensureRowVisible(item)
  }

  onFocusIndexChanged: {
    if (root.active) root.ensureFocusVisible()
  }

  // ---- data ---------------------------------------------------------
  function reload() {
    if (!root.panel) return
    if (!root.hasLoaded) root.loading = true
    var pending = 0
    pending++
    root.panel.callService("browser_status", {}, function(o) {
      if (o && o.browsers) {
        root.browsers = o.browsers
        var opts = []
        for (var i = 0; i < o.browsers.length; i++)
          if (o.browsers[i].enabled)
            opts.push({ value: o.browsers[i].id, label: o.browsers[i].label })
        root.browserOptions = opts
        if (root.newBrowser === "") {
          for (var j = 0; j < o.browsers.length; j++)
            if (o.browsers[j].enabled) { root.newBrowser = o.browsers[j].id; break }
        }
      }
      pending--
      if (pending === 0) { root.hasLoaded = true; root.loading = false }
    })
    pending++
    root.panel.callService("browser_list", {}, function(o) {
      if (o && o.rules) root.rules = o.rules
      pending--
      if (pending === 0) { root.hasLoaded = true; root.loading = false }
    })
  }

  function toggleBrowser(id, enabled) {
    if (!root.panel || root.disabled) return
    if (enabled) {
      root.panel.callService("browser_disable", { id: id }, function(o, err) {
        if (err) { root.panel.notifyError(err); return }
        root.reload()
      })
      return
    }
    var installed = true
    for (var i = 0; i < root.browsers.length; i++)
      if (root.browsers[i].id === id) { installed = root.browsers[i].installed; break }
    if (!installed) {
      root.pendingInstallId = id
      var name = id
      for (var j = 0; j < root.browsers.length; j++)
        if (root.browsers[j].id === id) { name = root.browsers[j].name; break }
      if (root.panel) {
        root.panel.notice = (root.panel.tr.t("ui.browserRouter.installPrompt", "Install %1? (y/n)").replace("%1", name))
        root.panel.pendingInstall = root
      }
      return
    }
    root.panel.callService("browser_enable", { id: id }, function(o, err) {
      if (err) { root.panel.notifyError(err); return }
      root.reload()
    })
  }

  function installBrowser(id) {
    if (!root.panel || root.disabled) return
    root.pendingInstallId = ""
    if (root.panel) { root.panel.notice = ""; root.panel.pendingInstall = null }
    root.panel.callService("browser_install", { id: id }, function(o, err) {
      if (err) { root.panel.notifyError(err); return }
      root.reload()
    })
  }

  function cancelInstall() {
    root.pendingInstallId = ""
    if (root.panel) { root.panel.notice = ""; root.panel.pendingInstall = null }
  }

  function setLabel(id, label) {
    if (!root.panel || root.disabled) return
    root.panel.callService("browser_set_label", { id: id, label: label }, function() {
      root.reload()
    })
  }

  function removeDomain(domain) {
    if (!root.panel || root.disabled) return
    root.panel.callService("browser_rule_remove", { domains: [domain] }, function() {
      root.reload()
    })
  }

  function editRule(oldDomain, newDomain, browser) {
    if (!root.panel || root.disabled) return
    if (newDomain === "") { root.removeDomain(oldDomain); return }
    root.panel.callService("browser_rule_edit", { domain: oldDomain, newDomain: newDomain, browser: browser }, function() {
      root.reload()
    })
  }

  function addRule() {
    if (root.newDomain === "" || root.newBrowser === "") return
    if (!root.panel || root.disabled) return
    root.panel.callService("browser_rule_add", { browser: root.newBrowser, domains: [root.newDomain] }, function() {
      root.newDomain = ""
      root.textEditing = false
      root.reload()
    })
  }

  function labelFor(id) {
    for (var i = 0; i < root.browsers.length; i++) {
      var b = root.browsers[i]
      if (b.id !== id) continue
      var shown = (b.enabled && b.label && b.label !== b.name) ? b.label : b.name
      return b.enabled ? shown : shown + " (disabled)"
    }
    return id
  }

  // Options for a rule's browser selector: the enabled browsers, plus the
  // rule's own browser when it is disabled, marked "(disabled)" so the rule
  // still shows which browser it points at.
  function ruleOptions(browser) {
    var opts = []
    for (var i = 0; i < root.browserOptions.length; i++)
      opts.push(root.browserOptions[i])
    var found = false
    for (var j = 0; j < opts.length; j++)
      if (opts[j].value === browser) { found = true; break }
    if (!found)
      opts.push({ value: browser, label: root.labelFor(browser) })
    return opts
  }

  function enabledBrowserIds() {
    var out = []
    for (var i = 0; i < root.browserOptions.length; i++)
      out.push(root.browserOptions[i].value)
    return out
  }

  function cycleBrowserId(current) {
    var ids = root.enabledBrowserIds()
    if (ids.length === 0) return current
    var idx = ids.indexOf(current)
    return ids[(idx + 1) % ids.length]
  }

  function cycleNewBrowser() {
    root.newBrowser = root.cycleBrowserId(root.newBrowser)
  }

  function cycleRuleBrowser(domain, current) {
    var next = root.cycleBrowserId(current)
    if (next !== current) root.editRule(domain, domain, next)
  }

  readonly property string newBrowserLabel: {
    for (var i = 0; i < root.browserOptions.length; i++)
      if (root.browserOptions[i].value === root.newBrowser) return root.browserOptions[i].label
    return root.newBrowser === "" ? "browser" : root.newBrowser
  }

  readonly property var flatRules: {
    var out = []
    for (var i = 0; i < root.rules.length; i++) {
      var r = root.rules[i]
      out.push({ domain: r.domain, browser: r.browser })
    }
    return out
  }

  property var browserOptions: []

  onPanelChanged: {
    if (root.panel) {
      root.panel.browserComponent = root
      Qt.callLater(root.reload)
    }
  }
  Component.onCompleted: if (root.panel) Qt.callLater(root.reload)

  // ---- visual content -----------------------------------------------
  // Background click area: clicking empty space in the component takes the
  // panel cursor to this row (matches other rows).
  MouseArea {
    anchors.fill: parent
    z: -1
    onClicked: {
      if (root.panel) root.panel.cursorTo(root.rowIndex)
      if (root.focusIndex < 0) root.focusIndex = 0
    }
  }

  Column {
    id: contentColumn
    width: parent.width
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.row.description || ""
      color: Qt.darker(root.fg, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      visible: root.loading
      width: parent.width
      textFormat: Text.PlainText
      text: "…"
      color: Qt.darker(root.fg, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: !root.loading
      textFormat: Text.PlainText
      text: root.panel ? root.panel.tr.t("ui.browserRouter.browsers", "Browsers available to router") : "Browsers available to router"
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      topPadding: Style.spacing.lg
    }

    // Browser list
    Column {
      visible: !root.loading
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        id: browserRepeater
        model: root.browsers
        delegate: Item {
          required property var modelData
          required property int index
          property alias labelField: labelField
          width: parent.width
          height: Style.space(40)
          opacity: modelData.installed ? 1.0 : 0.45

          BorderSurface {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.fg, root.accent)
            borderSpec: Border.controlSpec("hover-cursor", root.fg, root.accent)
            visible: root.focusIndex === index
          }

          // Focus the row on click (does not toggle). Commits any in-progress
          // label edit first.
          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit()
              if (root.panel) root.panel.cursorTo(root.rowIndex)
              root.focusIndex = index
            }
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            spacing: Style.spacing.rowPaddingX

            // Checkbox: clicking toggles the browser.
            BorderSurface {
              id: toggle
              width: Style.space(18); height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              radius: 3
              color: modelData.enabled === true
                ? Style.selectedFillFor(root.fg, root.accent)
                : Style.normalFillFor(root.fg, root.accent)
              borderSpec: Border.controlSpec(modelData.enabled === true ? "selected" : "normal", root.fg, root.accent)
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.enabled === true ? "\u2713" : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit(); if (root.panel) root.panel.cursorTo(root.rowIndex); root.focusIndex = index; if (!root.disabled) root.toggleBrowser(modelData.id, modelData.enabled) }
              }
            }

            // Name + command (clicking gives the row focus via the background
            // click area; it does not toggle).
            Column {
              width: parent.width - toggle.width - parent.spacing - labelField.width - Style.spacing.rowPaddingX * 2
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs
              Text {
                textFormat: Text.PlainText
                text: modelData.name + (modelData.installed ? "" : " (not installed)")
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: parent.width
              }
              Text {
                textFormat: Text.PlainText
                text: modelData.command || ""
                visible: modelData.command !== undefined && modelData.command !== ""
                color: Qt.darker(root.fg, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            ValueField {
              id: labelField
              width: Style.space(120)
              height: Style.space(24)
              anchors.verticalCenter: parent.verticalCenter
              activeFocusOnPress: true
              text: (modelData.enabled && modelData.label && modelData.label !== modelData.name) ? modelData.label : ""
              placeholderText: modelData.enabled ? "(none)" : "disabled"
              foreground: root.fg
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: 0
              enabled: modelData.enabled && !root.disabled
              onEditingFinished: {
                root.setLabel(modelData.id, text)
                // Defer unblocking the key catcher: the Enter key bubbles up
                // after this handler, so editingRow must still be set when it
                // reaches the catcher, or it will toggle the checkbox.
                Qt.callLater(function() {
                  root.textEditing = false
                  if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit()
                })
              }
              onEscapePressed: { root.textEditing = false; if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit() }
              onActiveFocusChanged: {
                if (activeFocus) {
                  root.textEditing = true
                  root.focusIndex = index
                  if (root.panel) { root.panel.cursorTo(root.rowIndex); if (root.panel.editingRow !== root.rowIndex) root.panel.beginEdit(root.rowIndex) }
                } else {
                  root.textEditing = false
                  if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit()
                }
              }
            }
          }
        }
      }
    }

    Text {
      visible: !root.loading
      textFormat: Text.PlainText
      text: root.panel ? root.panel.tr.t("ui.browserRouter.rules", "Routing rules") : "Routing rules"
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      topPadding: Style.spacing.lg
    }

    Text {
      visible: !root.loading
      width: parent.width
      textFormat: Text.PlainText
      text: root.panel ? root.panel.tr.t("ui.browserRouter.rulesHint", "Enter a domain and choose the browser that opens it. Domains not listed prompt for a browser.") : "Enter a domain and choose the browser that opens it."
      color: Qt.darker(root.fg, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      bottomPadding: Style.spacing.sm
    }

    // Add rule form
    Item {
      visible: !root.loading
      width: parent.width
      height: Style.space(28)
      opacity: root.disabled ? 0.4 : 1.0

      BorderSurface {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Style.hoverFillFor(root.fg, root.accent)
            borderSpec: Border.controlSpec("hover-cursor", root.fg, root.accent)
        visible: root.focusIndex === root.browserCount()
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.rightMargin: Style.spacing.rowPaddingX
        spacing: Style.spacing.sm

        ValueField {
          id: addDomainField
          width: parent.width - addBrowser.width - addBtn.width - parent.spacing * 2
          height: Style.space(28)
          text: root.newDomain
          onTextChanged: root.newDomain = text
          onAccepted: root.addRule()
          placeholderText: "domain"
          foreground: root.fg
          accent: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalPadding: Style.spacing.controlGap
          verticalPadding: 0
          enabled: !root.disabled
          onEscapePressed: { root.textEditing = false; if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit() }
          onActiveFocusChanged: {
            if (activeFocus) {
              root.textEditing = true
              root.focusIndex = root.browserCount()
              if (root.panel) { root.panel.cursorTo(root.rowIndex); if (root.panel.editingRow !== root.rowIndex) root.panel.beginEdit(root.rowIndex) }
            } else {
              root.textEditing = false
              if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit()
            }
          }
        }

        Dropdown {
          id: addBrowser
          width: Style.space(140)
          height: Style.space(28)
          showLabel: false
          options: root.browserOptions
          value: root.newBrowser
          foreground: root.fg
          background: root.panel ? root.panel.background : Commons.Color.background
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(v) { root.newBrowser = v }
        }

        Button {
          id: addBtn
          height: Style.space(28)
          text: "+ Add"
          bordered: true
          // Text uses the background color so it stays legible on the accent
          // fill across themes (accent and foreground can be identical).
          foreground: root.bg
          background: root.accent
          accent: root.accent
          fontFamily: root.fontFamily
          onClicked: { if (root.panel) root.panel.cursorTo(root.rowIndex); if (!root.disabled) root.addRule() }
        }
      }
    }

    // Rules list
    Column {
      visible: !root.loading
      width: parent.width
      spacing: Style.spacing.sm
      opacity: root.disabled ? 0.4 : 1.0

      Repeater {
        id: rulesRepeater
        model: root.flatRules
        delegate: Item {
          required property var modelData
          required property int index
          width: parent.width
          height: Style.space(28)

          BorderSurface {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.fg, root.accent)
            borderSpec: Border.controlSpec("hover-cursor", root.fg, root.accent)
            visible: root.focusIndex === root.browserCount() + 1 + index
          }

          // Focus the row on click. Commits any in-progress field edit first.
          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit()
              if (root.panel) root.panel.cursorTo(root.rowIndex)
              root.focusIndex = root.browserCount() + 1 + index
            }
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            spacing: Style.spacing.sm

            ValueField {
              id: domainField
              width: parent.width - browserBox.width - removeBtn.width - parent.spacing * 2
              height: Style.space(24)
              anchors.verticalCenter: parent.verticalCenter
              activeFocusOnPress: true
              text: modelData.domain
              foreground: root.fg
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: 0
              enabled: !root.disabled
              onEditingFinished: { if (text !== modelData.domain) root.editRule(modelData.domain, text, modelData.browser) }
              onEscapePressed: { root.textEditing = false; if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit() }
              onActiveFocusChanged: {
                if (activeFocus) {
                  root.textEditing = true
                  root.focusIndex = root.browserCount() + 1 + index
                  if (root.panel) { root.panel.cursorTo(root.rowIndex); if (root.panel.editingRow !== root.rowIndex) root.panel.beginEdit(root.rowIndex) }
                } else {
                  root.textEditing = false
                  if (root.panel && root.panel.editingRow === root.rowIndex) root.panel.endEdit()
                }
              }
            }

            Dropdown {
              id: browserBox
              width: Style.space(140)
              height: Style.space(24)
              showLabel: false
              options: root.ruleOptions(modelData.browser)
              value: modelData.browser
              foreground: root.fg
              background: root.panel ? root.panel.background : Commons.Color.background
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(v) { if (root.panel) root.panel.cursorTo(root.rowIndex); root.focusIndex = root.browserCount() + 1 + index; root.editRule(modelData.domain, modelData.domain, v) }
            }

            Button {
              id: removeBtn
              height: Style.space(24)
              text: "\u00d7"
              bordered: true
              foreground: root.fg
              background: root.panel ? root.panel.background : Commons.Color.background
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: { if (root.panel) root.panel.cursorTo(root.rowIndex); root.focusIndex = root.browserCount() + 1 + index; if (!root.disabled) root.removeDomain(modelData.domain) }
            }
          }
        }
      }
    }
  }

  // Overlay that blocks all clicks when the section is disabled (the default
  // browser is not the router).
  MouseArea {
    anchors.fill: parent
    visible: root.disabled
    z: 10
  }
}
