# omaset for agents

omaset is a single machine-readable interface to Omarchy's settings. An agent
(or any tool) can list, read, and change settings through one JSON protocol,
without needing to know which dotfile each setting lives in.

The contract is `docs/protocol.md`; this page is the practical guide.

## The four commands you need

```
omaset schema                # every panel + setting + current value, as JSON
omaset get <id> [--plain]    # read one setting (--plain = bare value)
omaset set <id> <value>      # write a value; validates and applies
omaset reset <id>            # revert omaset's override so the default returns
omaset changed --json        # settings that differ from Omarchy stock
omaset search <query> --json # find a setting by id or label
omaset help <id>             # type, options, range, default, current value
```

Keyed settings (per-workspace) take a key argument, e.g.
`omaset get workspace_layout 2` / `omaset set workspace_layout 3 scrolling`.

## Worked example

An agent asked to "make the gaps a bit bigger and turn on blur":

```sh
# 1. Discover what's available and its current value.
omaset schema | jq '.panels[] | select(.id=="appearance")'

# 2. Change one setting, read it back.
omaset set gaps_in 8 --plain   # prints ok
omaset get gaps_in --plain     # prints 8

# 3. Toggle a boolean.
omaset set blur true --plain

# 4. Confirm the system settled (omaset validates the Hyprland config
#    and reverts on error, so a clean "ok" means it applied).
omaset changed --json
```

## Rules agents should follow

1. **Read before you write.** `omaset get <id>` (or `schema`) first; only write
   what changed.
2. **Prefer `reset` over pinning.** If the goal is "back to default", use
   `omaset reset <id>` — it removes omaset's override so the Omarchy stock
   default re-emerges, instead of hardcoding a value that will later look
   "changed".
3. **Check the value contract first.** `omaset set <id> --help` prints the
   `<a|b|c>` enum form or `<min..max>` range; `omaset help <id>` lists options.
   An invalid enum lists its valid options in the error.
4. **Use `--plain` in scripts.** It prints just the value/`ok`, so you don't
   parse JSON for the common cases.

## Safety model

- omaset only writes into a managed `-- omaset:begin/end` block (or equivalent)
  in each config file; your hand-written config is never touched.
- Every Hyprland write is reloaded and checked with `hyprctl configerrors`; on
  error the previous content is restored.
- `reset` does not store snapshots — the default is recomputed from Omarchy's
  shipped config on every call.
- Files under `~/.local/share/omarchy/` (or `/usr/share/omarchy/`) are never
  written to.

## Extending

Every setting is declared in a small Lua DSL. Drop a `.lua` file in
`~/.config/omaset/settings/` to add or override a setting — no engine changes.
See the README's "Extending with Lua" section.
