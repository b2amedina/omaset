-- Dock (Omarchy 4.5+): position and auto-hide of the dock shown on floating
-- workspaces. Promoted to its own panel so it stays discoverable regardless of
-- the current workspace's layout (Omarchy's own menu only shows these options
-- while a workspace is floating).

if feature.workspace_modes() then
  panel("dock", "Dock", 0xf0db, function()
    section("Dock", "dock", function()
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
  end)
end
