panel("animations", "Animations", function()
  setting({
    id = "animations_enabled",
    type = "bool",
    label = "Animations",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "animations.enabled",
  })
end)
