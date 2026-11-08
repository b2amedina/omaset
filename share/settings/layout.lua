panel("layout", "Tiling Layout", function()
  section("Workspaces", function()
    -- Workspace modes (Omarchy 4.5+): per-workspace mode, with "floating" as
    -- a real option and no "master".
    if feature.workspace_modes() then
      setting({
        id = "workspace_layout",
        type = "enum",
        label = "Workspace layout",
        description = "Tiling layout for one workspace.",
        backend = "workspace-layout",
        keyed = true,
        key_label = "workspace",
        key_type = "int",
        options = { "dwindle", "scrolling", "floating" },
      })

      setting({
        id = "default_layout",
        type = "enum",
        label = "Default layout (new workspaces)",
        description = "Layout applied to newly opened workspaces.",
        backend = "omarchy",
        mode = "value",
        default = "dwindle",
        command = "omarchy hyprland workspace layout default {value}",
        status = "omarchy hyprland workspace layout default",
        reset = "omarchy hyprland workspace layout default dwindle",
        options = { "dwindle", "scrolling", "floating" },
      })
    else
      setting({
        id = "workspace_layout",
        type = "enum",
        label = "Workspace layout",
        description = "Tiling layout for one workspace.",
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
    end
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

  -- The master layout exists only before workspace modes (4.5).
  if not feature.workspace_modes() then
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
  end

  -- Floating workspaces are arranged by the mode; the dock shows there.
  if feature.workspace_modes() then
    section("Dock", function()
      setting({
        id = "dock_position",
        type = "enum",
        label = "Dock position",
        description = "Which edge of the screen the dock sits on.",
        backend = "omarchy",
        mode = "value",
        default = "bottom",
        command = "omarchy dock position {value}",
        status = "omarchy dock position",
        reset = "omarchy dock position bottom",
        options = { "top", "bottom", "left", "right" },
      })

      setting({
        id = "dock_autohide",
        type = "enum",
        label = "Dock autohide",
        description = "Hide the dock until the pointer reaches its edge.",
        backend = "omarchy",
        mode = "value",
        default = "off",
        command = "omarchy dock autohide {value}",
        status = "omarchy dock autohide",
        reset = "omarchy dock autohide off",
        options = { "on", "off" },
      })
    end)
  end
end)
