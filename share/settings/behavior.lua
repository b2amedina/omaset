panel("behavior", "Behavior", function()
  setting({
    id = "resize_on_border",
    type = "bool",
    label = "Resize on border",
    description = "Allow resizing windows by dragging their border.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "general.resize_on_border",
  })

  setting({
    id = "allow_tearing",
    type = "bool",
    label = "Allow tearing",
    description = "Allow screen tearing for fullscreen apps that request it.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "general.allow_tearing",
  })

  setting({
    id = "focus_on_activate",
    type = "bool",
    label = "Focus on activate",
    description = "Focus a window when it is activated.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "misc.focus_on_activate",
  })

  setting({
    id = "hide_on_key_press",
    type = "bool",
    label = "Hide cursor on key press",
    description = "Hide the cursor while typing.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "cursor.hide_on_key_press",
  })

  setting({
    id = "hide_special_on_workspace_change",
    type = "bool",
    label = "Hide special on workspace change",
    description = "Close the special workspace when switching workspaces.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "binds.hide_special_on_workspace_change",
  })
end)
