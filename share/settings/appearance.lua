panel("appearance", "Appearance", function()
  setting({
    id = "gaps_in",
    type = "int",
    label = "Gaps in",
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
    backend = "hypr-lua",
    file = "looknfeel",
    path = "decoration.blur.enabled",
  })

  setting({
    id = "shadow",
    type = "bool",
    label = "Shadow",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "decoration.shadow.enabled",
  })
end)
