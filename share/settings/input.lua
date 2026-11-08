panel("input", "Input", 0xf11c, function()
  section("Mouse", "mouse", function()
    setting({
      id = "follow_mouse",
      type = "int",
      label = "Follow mouse",
      description = "Move focus to the window under the cursor.",
      backend = "hypr-lua",
      file = "input",
      path = "input.follow_mouse",
      options = {
        { value = 0, label = "None" },
        { value = 1, label = "Full" },
        { value = 2, label = "Tight" },
        { value = 3, label = "Loose" },
      },
    })

    setting({
      id = "mouse_sensitivity",
      type = "float",
      label = "Mouse sensitivity",
      description = "Pointer sensitivity multiplier (-1..1).",
      backend = "hypr-lua",
      file = "input",
      path = "input.sensitivity",
      min = -1,
      max = 1,
    })
  end)

  section("Keyboard", "keyboard", function()
    setting({
      id = "key_repeat_rate",
      type = "int",
      label = "Key repeat rate",
      description = "Keystrokes repeated per second while a key is held.",
      backend = "hypr-lua",
      file = "input",
      path = "input.repeat_rate",
      min = 10,
      max = 1000,
    })

    setting({
      id = "key_repeat_delay",
      type = "int",
      label = "Key repeat delay",
      description = "Delay in milliseconds before a held key starts repeating.",
      backend = "hypr-lua",
      file = "input",
      path = "input.repeat_delay",
      min = 100,
      max = 1000,
    })

    setting({
      id = "numlock_by_default",
      type = "bool",
      label = "Numlock by default",
      description = "Enable Num Lock on login.",
      backend = "hypr-lua",
      file = "input",
      path = "input.numlock_by_default",
    })
  end)

  section("Touchpad", "touchpad", function()
    setting({
      id = "natural_scroll",
      type = "bool",
      label = "Natural scroll",
      description = "Invert the touchpad scroll direction.",
      backend = "hypr-lua",
      file = "input",
      path = "input.touchpad.natural_scroll",
    })

    setting({
      id = "clickfinger_behavior",
      type = "bool",
      label = "Clickfinger behavior",
      description = "Treat a two-finger tap as a right click.",
      backend = "hypr-lua",
      file = "input",
      path = "input.touchpad.clickfinger_behavior",
    })

    setting({
      id = "touchpad_scroll_factor",
      type = "float",
      label = "Touchpad scroll factor",
      description = "Touchpad scroll speed multiplier.",
      backend = "hypr-lua",
      file = "input",
      path = "input.touchpad.scroll_factor",
      min = -5,
      max = 5,
    })
  end)
end)
