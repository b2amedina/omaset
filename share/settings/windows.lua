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

  setting({
    id = "window_no_gaps",
    type = "bool",
    label = "No window gaps",
    description = "Remove the gaps between tiled windows.",
    backend = "omarchy",
    mode = "toggle",
    command = "omarchy hyprland toggle window-no-gaps",
    status = "omarchy hyprland toggle enabled window-no-gaps && echo true || echo false",
  })

  setting({
    id = "single_window_square",
    type = "bool",
    label = "Single window square",
    description = "Keep a single tiled window in a square aspect ratio.",
    backend = "omarchy",
    mode = "toggle",
    command = "omarchy hyprland toggle single-window-aspect-ratio",
    status = "omarchy hyprland toggle enabled single-window-aspect-ratio && echo true || echo false",
  })
end)
