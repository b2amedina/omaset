panel("power", "Power & Idle", 0xf011, function()
  section("Idle", "idle", function()
    -- Friendly discrete time presets (macOS-style), so a raw-seconds slider
    -- is never shown. The stored value stays seconds in shell.json; the UI and
    -- CLI accept the labels too ("omaset set idle_lock '5 min'").
    local idle_options = {
      { value = 0, label = "Never" },
      { value = 60, label = "1 min" },
      { value = 300, label = "5 min" },
      { value = 600, label = "10 min" },
      { value = 900, label = "15 min" },
      { value = 1800, label = "30 min" },
      { value = 3600, label = "1 hour" },
    }

    setting({
      id = "idle_screensaver",
      type = "int",
      label = "Screen timeout",
      description = "Inactivity before the screensaver starts.",
      backend = "shell-json",
      path = "idle.screensaver",
      unit = "sec",
      min = 0,
      max = 86400,
      options = idle_options,
    })

    setting({
      id = "idle_lock",
      type = "int",
      label = "Lock timeout",
      description = "Inactivity before the screen locks.",
      backend = "shell-json",
      path = "idle.lock",
      unit = "sec",
      min = 0,
      max = 86400,
      options = idle_options,
    })
  end)
end)
