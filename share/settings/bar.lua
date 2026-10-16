panel("bar", "Bar", function()
  section("Placement", function()
    setting({
      id = "bar_position",
      type = "enum",
      label = "Bar position",
      description = "Which edge of the screen the bar sits on.",
      backend = "shell-json",
      path = "bar.position",
      options = { "top", "bottom", "left", "right" },
    })
  end)

  section("Style", function()
    setting({
      id = "bar_transparent",
      type = "bool",
      label = "Bar transparent",
      description = "Make the bar background transparent.",
      backend = "shell-json",
      path = "bar.transparent",
    })
  end)
end)
