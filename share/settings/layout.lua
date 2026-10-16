panel("layout", "Tiling Layout", function()
  section("Workspaces", function()
    setting({
      id = "workspace_layout",
      type = "enum",
      label = "Workspace layout",
      description = "Tiling layout for one workspace (dwindle, master, or scrolling).",
      backend = "workspace-layout",
      keyed = true,
      key_label = "workspace",
      key_type = "int",
      options = { "dwindle", "master", "scrolling" },
    })

    setting({
      id = "default_layout",
      type = "enum",
      label = "Default layout (new workspaces)",
      description = "Layout applied to newly opened workspaces.",
      backend = "hypr-lua",
      file = "looknfeel",
      path = "general.layout",
      options = { "dwindle", "master", "scrolling" },
    })
  end)

  section("Dwindle", function()
    setting({
      id = "dwindle_force_split",
      type = "int",
      label = "Dwindle force split",
      description = "Force dwindle splits: 0 off, 1 always, 2 unless a window is solo.",
      backend = "hypr-lua",
      file = "looknfeel",
      path = "dwindle.force_split",
      min = 0,
      max = 2,
    })

    setting({
      id = "preserve_split",
      type = "bool",
      label = "Preserve split",
      description = "Keep the dwindle split direction when a window is removed.",
      backend = "hypr-lua",
      file = "looknfeel",
      path = "dwindle.preserve_split",
    })
  end)

  section("Scrolling", function()
    setting({
      id = "scrolling_column_width",
      type = "float",
      label = "Scrolling column width",
      description = "Fraction of the screen taken by the scrolling layout's main column.",
      backend = "hypr-lua",
      file = "looknfeel",
      path = "scrolling.column_width",
      min = 0,
      max = 1,
    })
  end)

  section("Master", function()
    setting({
      id = "master_new_status",
      type = "enum",
      label = "Master new status",
      description = "Whether new windows open as master or join the stack.",
      backend = "hypr-lua",
      file = "looknfeel",
      path = "master.new_status",
      options = { "master", "slave" },
    })
  end)
end)
