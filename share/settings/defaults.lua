-- Default applications, as Omarchy's own Setup > Defaults menu sets them. Each
-- setting wraps the omarchy-default-* command; reset restores the state a
-- fresh Omarchy install is provisioned with (or removes the preference file
-- where Omarchy keeps no default).

panel("defaults", "Defaults", 0xf005, function()
  section("Default applications", "defaultApps", function()
    setting({
      id = "default_agent",
      type = "enum",
      label = "Default agent",
      description = "Coding agent Omarchy launches.",
      backend = "omarchy-defaults",
      mode = "value",
      command = "omarchy-default-agent {value}",
      status = "omarchy-default-agent 2>/dev/null",
      reset = "rm -f \"$HOME/.config/omarchy/defaults/agent\"",
      custom = { file = ".config/omarchy/defaults/agent" },
      options = {
        { value = "agy", label = "Antigravity" },
        { value = "amp", label = "Amp" },
        { value = "claude", label = "Claude" },
        { value = "codex", label = "Codex" },
        { value = "commandcode", label = "Command Code" },
        { value = "copilot", label = "Copilot" },
        { value = "crush", label = "Crush" },
        { value = "cursor-agent", label = "Cursor CLI" },
        { value = "devin", label = "Devin CLI" },
        { value = "dsh", label = "DeepSeek Harness" },
        { value = "freebuff", label = "Freebuff" },
        { value = "grok", label = "Grok" },
        { value = "hermes", label = "Hermes" },
        { value = "kilo", label = "Kilo" },
        { value = "kimi", label = "Kimi" },
        { value = "kiro-cli", label = "Kiro CLI" },
        { value = "mcode", label = "MiniMax Code" },
        { value = "muse", label = "Muse Code" },
        { value = "omp", label = "omp" },
        { value = "openclaw", label = "OpenClaw" },
        { value = "opencode", label = "OpenCode" },
        { value = "ori", label = "Ori" },
        { value = "pi", label = "Pi" },
        { value = "qwen", label = "Qwen Code" },
      },
    })

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
      custom = { xdg = "default-web-browser" },
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

    setting({
      id = "default_dictation",
      type = "enum",
      label = "Default dictation",
      description = "Dictation backend Omarchy uses.",
      backend = "omarchy-defaults",
      mode = "value",
      command = "omarchy-default-dictation {value}",
      status = "omarchy-default-dictation 2>/dev/null",
      reset = "rm -f \"$HOME/.config/omarchy/defaults/dictation\"",
      custom = { file = ".config/omarchy/defaults/dictation" },
      options = {
        { value = "superwhisper", label = "Superwhisper" },
        { value = "voxtype", label = "Voxtype" },
      },
    })

    setting({
      id = "default_editor",
      type = "enum",
      label = "Default editor",
      description = "Editor Omarchy opens for files.",
      backend = "omarchy-defaults",
      mode = "value",
      default = "nvim",
      command = "omarchy-default-editor {value}",
      status = "omarchy-default-editor 2>/dev/null",
      reset = "rm -f \"$HOME/.local/state/omarchy/defaults/editor\"",
      custom = { file = ".local/state/omarchy/defaults/editor" },
      options = {
        { value = "nvim", label = "Neovim" },
        { value = "code", label = "VSCode" },
        { value = "cursor", label = "Cursor" },
        { value = "zeditor", label = "Zed" },
        { value = "subl", label = "Sublime Text" },
        { value = "helix", label = "Helix" },
        { value = "vim", label = "Vim" },
        { value = "emacs", label = "Emacs" },
      },
    })

    setting({
      id = "default_terminal",
      type = "enum",
      label = "Default terminal",
      description = "Terminal the terminal keybinding opens.",
      backend = "omarchy-defaults",
      mode = "value",
      default = "foot",
      command = "omarchy-default-terminal {value}",
      status = "omarchy-default-terminal 2>/dev/null",
      reset = "rm -f \"$HOME/.config/xdg-terminals.list\"",
      custom = { file = ".config/xdg-terminals.list", format = "xdg-terminals" },
      options = {
        { value = "alacritty", label = "Alacritty" },
        { value = "foot", label = "Foot" },
        { value = "ghostty", label = "Ghostty" },
        { value = "kitty", label = "Kitty" },
      },
    })
  end)
end)
