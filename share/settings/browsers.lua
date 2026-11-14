-- Browsers: the default browser and the browser-router configuration.

local known = { "chromium", "chrome", "brave", "brave-origin", "edge", "firefox", "zen" }

panel("browsers", "Browsers", 0xf0ac, nil, true, function()
  section("Default browser", "default", function()
    setting({
      id = "default_browser",
      type = "enum",
      label = "Default browser",
      description = "Browser for links and Omarchy's Browser action.",
      backend = "omarchy-defaults",
      mode = "value",
      default = "chromium",
      command = "omarchy-default-browser {value}",
      status = "omarchy-default-browser 2>/dev/null",
      reset = "env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings set default-web-browser chromium.desktop",
      custom_values = { "browser-router.desktop" },
      custom = { xdg = "default-web-browser", desktop = "browser-router.desktop" },
      options = {
        { value = "chromium", label = "Chromium" },
        { value = "chrome", label = "Chrome" },
        { value = "brave", label = "Brave" },
        { value = "brave-origin", label = "Brave Origin" },
        { value = "edge", label = "Edge" },
        { value = "firefox", label = "Firefox" },
        { value = "zen", label = "Zen" },
        { value = "browser-router.desktop", label = "Browser router" },
      },
    })
  end)

  section("Browser router", "router", function()
    -- Marker setting: renders the custom BrowserRouter component.
    setting({
      id = "browser_router",
      type = "string",
      label = "Browser router",
      description = "Route links to different browsers by domain (e.g. work sites to Chrome, personal to Brave). When a link doesn't match any rule, you'll be asked which browser to use. Only active when \"Browser router\" is your default browser.",
      backend = "browser",
      component = "browserRouter",
      tracked = false,
    })

    -- Hidden settings (CLI/MCP access; the component renders them in the UI).
    for _, id in ipairs(known) do
      setting({
        id = "browser_" .. id .. "_enabled",
        type = "bool",
        label = id:gsub("^%l", string.upper),
        description = "Show this browser in the router.",
        backend = "browser",
        hidden = true,
        tracked = false,
      })
      setting({
        id = "browser_" .. id .. "_label",
        type = "string",
        label = id:gsub("^%l", string.upper) .. " label",
        description = "Display label in the chooser and rules.",
        backend = "browser",
        hidden = true,
        tracked = false,
      })
    end
    setting({
      id = "browser_rules",
      type = "enum",
      label = "Routing rules",
      description = "Domain to browser mapping.",
      backend = "browser",
      keyed = true,
      tracked = false,
      key_type = "string",
      key_label = "domain",
      hidden = true,
      options = {
        { value = "chromium", label = "Chromium" },
        { value = "chrome", label = "Chrome" },
        { value = "brave", label = "Brave" },
        { value = "brave-origin", label = "Brave Origin" },
        { value = "edge", label = "Edge" },
        { value = "firefox", label = "Firefox" },
        { value = "zen", label = "Zen" },
      },
    })
  end)
end)
