panel("display", "Display", function()
  setting({
    id = "nightlight",
    type = "bool",
    label = "Night light",
    backend = "omarchy",
    mode = "toggle",
    command = "omarchy toggle nightlight",
    status = "omarchy toggle nightlight --status | jq -r .enabled",
  })
end)
