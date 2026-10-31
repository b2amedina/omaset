#!/usr/bin/env bash
# MCP server: drive `omaset mcp` over stdio and assert the JSON-RPC responses.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

OUT="$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get","arguments":{"id":"nightlight_temperature"}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"set","arguments":{"id":"nightlight_temperature","value":3500}}}' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get","arguments":{"id":"nightlight_temperature"}}}' \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"changed"}}' \
  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"set","arguments":{"id":"nightlight_temperature","value":"warm"}}}' \
  '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"reset","arguments":{"id":"nightlight_temperature"}}}' \
  '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get","arguments":{"id":"nightlight_temperature"}}}' \
  '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"search","arguments":{"query":"gap"}}}' \
  '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"schema"}}' \
  '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"bogus"}}' \
  '{"jsonrpc":"2.0","id":13,"method":"ping"}' \
  '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"keys","arguments":{"id":"fullwidth_style"}}}' \
  '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"keys","arguments":{"id":"gaps_in"}}}' \
  '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"preferences"}}' \
  '{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"preference_get","arguments":{"key":"time_format"}}}' \
  '{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"preference_set","arguments":{"key":"time_format","value":"12h"}}}' \
  '{"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"preference_reset","arguments":{"key":"time_format"}}}' \
  '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"preference_set","arguments":{"key":"time_format","value":"bogus"}}}' \
  '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"set","arguments":{"id":"nightlight_start","value":"8:30 PM"}}}' \
  '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"get","arguments":{"id":"nightlight_start"}}}' \
  | lua5.1 "$OMASET" mcp 2>/dev/null)"

assert_contains "$OUT" '"protocolVersion":"2025-11-25"' "initialize echoes version"
assert_contains "$OUT" '"serverInfo":{"name":"omaset"' "initialize reports serverInfo"

# notifications/initialized must produce no response, so no line carries id 0x.
assert_not_contains "$OUT" '"id":0' "notification has no response"

assert_contains "$OUT" '"name":"schema"' "tools/list has schema"
assert_contains "$OUT" '"name":"open_ui"' "tools/list has open_ui"

# get: structuredContent carries value + default, and the JSON is echoed in the
# text content so agents that only read text still see the data.
assert_contains "$OUT" '"default":4000,"id":"nightlight_temperature","value":4000' "get default value"
assert_contains "$OUT" '"text":"{\"default\":4000' "get data is in the text content"

assert_contains "$OUT" '"id":"nightlight_temperature","ok":true,"value":3500' "set reports ok"
assert_contains "$OUT" '"default":4000,"id":"nightlight_temperature","value":3500' "get reflects set"

assert_contains "$OUT" '"id":"nightlight_temperature"' "changed includes the setting"

assert_contains "$OUT" '"code":-32602' "invalid value is an error"

assert_contains "$OUT" '"id":8,"jsonrpc":"2.0","result":{"content"' "reset returns content"
assert_contains "$OUT" '"default":4000,"id":"nightlight_temperature","value":4000' "reset restores default"

assert_contains "$OUT" '"id":"gaps_in"' "search finds gaps_in"

assert_contains "$OUT" '"panels"' "schema has panels"
assert_contains "$OUT" '"appearance"' "schema includes appearance panel"

assert_contains "$OUT" '"code":-32602' "unknown tool is an error"

assert_contains "$OUT" '"id":13,"jsonrpc":"2.0","result":{}' "ping returns empty result"

# keys: enumerate a grouped setting's sub-settings, and reject non-keyed/grouped.
assert_contains "$OUT" '"grouped":true,"id":"fullwidth_style"' "keys reports grouped"
assert_contains "$OUT" '"sub":"border_size"' "keys lists border_size"
assert_contains "$OUT" '"sub":"rounding"' "keys lists rounding"
assert_contains "$OUT" '"message":"setting is not keyed or grouped: gaps_in"' "keys rejects non-keyed setting"

# preferences: the MCP tools expose omaset's own config with the same
# validation contract, and an invalid enum value is rejected.
assert_contains "$OUT" '"name":"preferences"' "tools/list has preferences"
assert_contains "$OUT" '"name":"preference_set"' "tools/list has preference_set"
assert_contains "$OUT" '"key":"time_format"' "preferences lists time_format"
assert_contains "$OUT" '"default":"auto","key":"time_format","options":["24h","12h","auto"],"type":"enum","value":"auto"' "preference_get reports value + type"
assert_contains "$OUT" '"options":["24h","12h","auto"]' "preference_get reports options"
assert_contains "$OUT" '"key":"time_format","ok":true,"value":"12h"' "preference_set writes"
assert_contains "$OUT" '"key":"time_format","ok":true,"value":"auto"' "preference_reset restores default"
assert_contains "$OUT" '"code":-32602' "invalid preference value is an error"

# time values are normalized to canonical 24-hour form on the way in.
assert_contains "$OUT" '"id":"nightlight_start","ok":true,"value":"20:30"' "set normalizes time"
assert_contains "$OUT" '"default":"20:00","id":"nightlight_start","value":"20:30"' "get reflects normalized time"

echo "ok"
