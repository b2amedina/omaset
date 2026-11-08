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
    -- The bar model changed with workspace modes (Omarchy 4.5+): the old
    -- `bar.transparent` bool became `bar.background` (opaque/glassy/none).
    if feature.workspace_modes() then
      setting({
        id = "bar_background",
        type = "enum",
        label = "Bar background",
        description = "How the bar background renders (opaque, glassy, or none).",
        backend = "omarchy",
        mode = "value",
        default = "opaque",
        command = "omarchy bar background {value}",
        status = "omarchy bar background",
        reset = "omarchy bar background opaque",
        options = { "opaque", "glassy", "none" },
      })
    else
      setting({
        id = "bar_transparent",
        type = "bool",
        label = "Bar transparent",
        description = "Make the bar background transparent.",
        backend = "shell-json",
        path = "bar.transparent",
      })
    end
  end)
end)
