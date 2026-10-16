panel("display", "Display", function()
  setting({
    id = "nightlight",
    type = "bool",
    label = "Night light",
    description = "Tint the screen warmer in the evening.",
    backend = "omarchy",
    mode = "toggle",
    command = "omarchy toggle nightlight",
    status = "omarchy toggle nightlight --status | jq -r .enabled",
  })

  setting({
    id = "nightlight_schedule",
    type = "bool",
    label = "Night light schedule",
    description = "Automatically tint the screen warmer on a schedule.",
    backend = "hyprsunset",
    path = "schedule",
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
