# Tests

```
tests/run.sh
```

Every `tests/test_*.sh` is a black-box test that drives `bin/omaset` against
fixture configs, reporting a pass/fail summary.

They are pointed at scratch directories through environment variables —
`OMARCHY_PATH`, `OMASET_HYPR_DIR`, `OMASET_SHELL_CONFIG`, and `OMASET_NO_APPLY` —
so a test run never touches the real system or reloads your compositor. Because
they assert on the public CLI only, they are safe to run while refactoring
internals: a behavior change that matters shows up here, and one that does not
stays invisible.

Coverage is one file per area — the schema and its sections, each backend
(`hypr_lua`, `hypr_window`, `shell_json`, `hyprsunset`, `omarchy`,
`workspace_layout`), the journal and revert path, type coercion, help output, and
the MCP server and its installer.
