panel("display", "Display", 0xf108, function()
  section("Night light", "nightlight", function()
    setting({
      id = "nightlight",
      type = "bool",
      label = "Night light",
      description = "Tint the screen warmer in the evening.",
      backend = "omarchy",
      mode = "toggle",
      default = false,
      command = "omarchy toggle nightlight",
      status = "omarchy toggle nightlight --status | jq -r .enabled",
    })

    setting({
      id = "nightlight_temperature",
      type = "int",
      label = "Night light temperature",
      description = "Color temperature (Kelvin) applied when the night light is on.",
      backend = "hyprsunset",
      path = "temperature",
      min = 1000,
      max = 6500,
    })
  end)

  section("Schedule", "schedule", function()
    setting({
      id = "nightlight_schedule",
      type = "bool",
      label = "Night light schedule",
      description = "Automatically tint the screen warmer on a schedule.",
      backend = "hyprsunset",
      path = "schedule",
    })

    setting({
      id = "nightlight_start",
      type = "time",
      label = "Starts at",
      description = "Time the night light schedule starts (24h or AM/PM). Editing a time enables the schedule.",
      backend = "hyprsunset",
      path = "start",
      format = "HH:MM",
      hint = "HH:MM or h:mm AM/PM",
    })

    setting({
      id = "nightlight_stop",
      type = "time",
      label = "Ends at",
      description = "Time the schedule ends and the screen returns to normal. Editing a time enables the schedule.",
      backend = "hyprsunset",
      path = "stop",
      format = "HH:MM",
      hint = "HH:MM or h:mm AM/PM",
    })
  end)
end)
