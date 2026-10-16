panel("layout", "Tiling Layout", function()
  setting({
    id = "default_layout",
    type = "enum",
    label = "Default layout (new workspaces)",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "general.layout",
    options = { "dwindle", "master", "scrolling" },
  })

  setting({
    id = "dwindle_force_split",
    type = "int",
    label = "Dwindle force split",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "dwindle.force_split",
    min = 0,
    max = 2,
  })

  setting({
    id = "scrolling_column_width",
    type = "float",
    label = "Scrolling column width",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "scrolling.column_width",
    min = 0,
    max = 1,
  })

  setting({
    id = "master_new_status",
    type = "enum",
    label = "Master new status",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "master.new_status",
    options = { "master", "slave" },
  })
end)
