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
end)
