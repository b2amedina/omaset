panel("screenshot", "Screenshot", 0xf030, function()
  section("Editor", "editor", function()
    setting({
      id = "editor_mode",
      type = "enum",
      label = "Editor mode",
      description = "How the annotation editor is presented.",
      backend = "omasnap",
      path = "editor.mode",
      default = "overlay",
      options = { "overlay", "window" },
    })

    setting({
      id = "editor_window",
      type = "enum",
      label = "Windowed editor",
      description = "Floating or tiled when the editor opens as a window.",
      backend = "omasnap",
      path = "editor.window",
      default = "floating",
      options = { "floating", "tiled" },
    })

    setting({
      id = "editor_backdrop",
      type = "enum",
      label = "Windowed backdrop",
      description = "Solid or translucent backdrop for a windowed editor.",
      backend = "omasnap",
      path = "editor.backdrop",
      default = "opaque",
      options = { "opaque", "translucent" },
    })
  end)

  section("Output", "output", function()
    setting({
      id = "output_autosave",
      type = "bool",
      label = "Autosave captures",
      description = "Save fresh captures while still copying and showing the preview.",
      backend = "omasnap",
      path = "output.autosave",
      default = true,
    })

    setting({
      id = "output_directory",
      type = "string",
      label = "Screenshot directory",
      description = "Where saved screenshots go. `~` is allowed.",
      backend = "omasnap",
      path = "output.directory",
      default = "~/Pictures/Screenshots",
    })

    setting({
      id = "output_filename",
      type = "string",
      label = "Filename pattern",
      description = "Pattern without extension. Tokens: {date} (yyyy-MM-dd), {time} (HH-mm-ss), {app} (window class slug). Existing names get -2, -3, ...",
      backend = "omasnap",
      path = "output.filename",
      default = "screenshot-{date}_{time}-{app}",
    })
  end)
end)
