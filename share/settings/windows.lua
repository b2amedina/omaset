panel("windows", "Windows", function()
  setting({
    id = "fullwidth_style",
    type = "group",
    label = "Full width style",
    backend = "hypr-window",
    file = "hyprland",
    match = { fullscreen_state_internal = 1 },
    subsettings = {
      border_size = { type = "int", label = "Border size", default = 2, min = 0, max = 20 },
      rounding = { type = "int", label = "Rounding", default = 0, min = 0, max = 20 },
    },
  })

  setting({
    id = "tiled_fullscreen_style",
    type = "group",
    label = "Tiled full screen style",
    backend = "hypr-window",
    file = "hyprland",
    match = { fullscreen_state_client = 2, fullscreen_state_internal = 0 },
    subsettings = {
      border_size = { type = "int", label = "Border size", default = 2, min = 0, max = 20 },
    },
  })
end)
