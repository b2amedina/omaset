panel("appearance", "Appearance", function()
  setting({
    id = "gaps_in",
    type = "int",
    label = "Gaps in",
    description = "Gap between a window and its neighbors.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "general.gaps_in",
    min = 0,
    max = 30,
  })

  setting({
    id = "gaps_out",
    type = "int",
    label = "Gaps out",
    description = "Gap between windows and the screen edge.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "general.gaps_out",
    min = 0,
    max = 100,
  })

  setting({
    id = "border_size",
    type = "int",
    label = "Border size",
    description = "Width of the window border in pixels.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "general.border_size",
    min = 0,
    max = 20,
  })

  setting({
    id = "rounding",
    type = "int",
    label = "Rounding",
    description = "Corner radius of windows in pixels.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "decoration.rounding",
    min = 0,
    max = 20,
  })

  setting({
    id = "blur",
    type = "bool",
    label = "Blur",
    description = "Blur what is behind semi-transparent windows.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "decoration.blur.enabled",
  })

  setting({
    id = "shadow",
    type = "bool",
    label = "Shadow",
    description = "Drop shadow behind windows.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "decoration.shadow.enabled",
  })

  setting({
    id = "groupbar_gaps_in",
    type = "int",
    label = "Groupbar gaps in",
    description = "Inner gap of the group bar.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "group.groupbar.gaps_in",
    min = 0,
    max = 30,
  })

  setting({
    id = "groupbar_gaps_out",
    type = "int",
    label = "Groupbar gaps out",
    description = "Outer gap of the group bar.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "group.groupbar.gaps_out",
    min = 0,
    max = 30,
  })

  setting({
    id = "groupbar_height",
    type = "int",
    label = "Groupbar height",
    description = "Height of the group bar.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "group.groupbar.height",
    min = 0,
    max = 100,
  })

  setting({
    id = "groupbar_font_size",
    type = "int",
    label = "Groupbar font size",
    description = "Font size of the group bar.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "group.groupbar.font_size",
    min = 1,
    max = 64,
  })

  setting({
    id = "groupbar_gradients",
    type = "bool",
    label = "Groupbar gradients",
    description = "Render group bar backgrounds as gradients.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "group.groupbar.gradients",
  })

  setting({
    id = "groupbar_gradient_rounding",
    type = "int",
    label = "Groupbar gradient rounding",
    description = "Corner rounding of the group bar gradient.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "group.groupbar.gradient_rounding",
    min = 0,
    max = 20,
  })
end)
