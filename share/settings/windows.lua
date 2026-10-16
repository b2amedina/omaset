panel("windows", "Windows", function()
  section("Fullscreen styles", function()
    setting({
      id = "fullwidth_style",
      type = "group",
      label = "Full width style",
      description = "Border and rounding applied to full-width windows.",
      backend = "hypr-window",
      file = "hyprland",
      match = { fullscreen_state_internal = 1 },
      subsettings = {
        border_size = { type = "int", label = "Border size", description = "Border width for full-width windows.", default = 2, min = 0, max = 20 },
        rounding = { type = "int", label = "Rounding", description = "Corner radius for full-width windows.", default = 0, min = 0, max = 20 },
      },
    })

    setting({
      id = "tiled_fullscreen_style",
      type = "group",
      label = "Tiled full screen style",
      description = "Border applied to tiled full-screen windows.",
      backend = "hypr-window",
      file = "hyprland",
      match = { fullscreen_state_client = 2, fullscreen_state_internal = 0 },
      subsettings = {
        border_size = { type = "int", label = "Border size", description = "Border width for tiled full-screen windows.", default = 2, min = 0, max = 20 },
      },
    })
  end)

  section("Tiling", function()
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
end)
