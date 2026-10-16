panel("animations", "Animations", function()
  setting({
    id = "animations_enabled",
    type = "bool",
    label = "Animations",
    description = "Animate window movement, resizing, and fades.",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "animations.enabled",
  })
end)
