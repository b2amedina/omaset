panel("power", "Power & Idle", function()
  setting({
    id = "idle_screensaver",
    type = "int",
    label = "Screen timeout (seconds)",
    backend = "shell-json",
    path = "idle.screensaver",
    min = 0,
    max = 3600,
  })

  setting({
    id = "idle_lock",
    type = "int",
    label = "Lock timeout (seconds)",
    backend = "shell-json",
    path = "idle.lock",
    min = 0,
    max = 3600,
  })
end)
