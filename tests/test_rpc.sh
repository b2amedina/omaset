#!/usr/bin/env bash
# RPC server: drive `omaset rpc` over stdio and assert the JSON-RPC responses.
# This is the transport the settings window uses, so it must expose the same
# operations and validation as the CLI and MCP server.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

OUT="$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"version"}' \
  '{"jsonrpc":"2.0","id":2,"method":"ping"}' \
  '{"jsonrpc":"2.0","id":3,"method":"schema"}' \
  '{"jsonrpc":"2.0","id":4,"method":"get","params":{"id":"nightlight_temperature"}}' \
  '{"jsonrpc":"2.0","id":5,"method":"set","params":{"id":"nightlight_temperature","value":3500}}' \
  '{"jsonrpc":"2.0","id":6,"method":"get","params":{"id":"nightlight_temperature"}}' \
  '{"jsonrpc":"2.0","id":7,"method":"changed"}' \
  '{"jsonrpc":"2.0","id":8,"method":"set","params":{"id":"nightlight_temperature","value":"warm"}}' \
  '{"jsonrpc":"2.0","id":9,"method":"reset","params":{"id":"nightlight_temperature"}}' \
  '{"jsonrpc":"2.0","id":10,"method":"keys","params":{"id":"fullwidth_style"}}' \
  '{"jsonrpc":"2.0","id":11,"method":"get","params":{"id":"fullwidth_style","key":"rounding"}}' \
  '{"jsonrpc":"2.0","id":12,"method":"set","params":{"id":"fullwidth_style","key":"rounding","value":7}}' \
  '{"jsonrpc":"2.0","id":13,"method":"get","params":{"id":"fullwidth_style","key":"rounding"}}' \
  '{"jsonrpc":"2.0","id":14,"method":"reset","params":{"id":"fullwidth_style","key":"rounding"}}' \
  '{"jsonrpc":"2.0","id":15,"method":"keys","params":{"id":"workspace_layout"}}' \
  '{"jsonrpc":"2.0","id":16,"method":"snapshot","params":{"panel":"layout"}}' \
  '{"jsonrpc":"2.0","id":17,"method":"search","params":{"query":"gap"}}' \
  '{"jsonrpc":"2.0","id":18,"method":"preferences"}' \
  '{"jsonrpc":"2.0","id":19,"method":"preference_set","params":{"key":"time_format","value":"12h"}}' \
  '{"jsonrpc":"2.0","id":20,"method":"preference_get","params":{"key":"time_format"}}' \
  '{"jsonrpc":"2.0","id":21,"method":"preference_reset","params":{"key":"time_format"}}' \
  '{"jsonrpc":"2.0","id":22,"method":"set","params":{"id":"nightlight_start","value":"8:30 PM"}}' \
  '{"jsonrpc":"2.0","id":23,"method":"get","params":{"id":"nightlight_start"}}' \
  '{"jsonrpc":"2.0","id":24,"method":"bogus"}' \
  '{"jsonrpc":"2.0","id":25,"method":"set","params":{"id":"nope","value":1}}' \
  '{"jsonrpc":"2.0","id":26,"method":"snapshot","params":{"panel":"windows"}}' \
  '{"jsonrpc":"2.0","id":27,"method":"search","params":{"query":"espacio interior","lang":"es-MX"}}' \
  '{"jsonrpc":"2.0","method":"changed"}' \
  'not json' \
  | lua5.1 "$OMASET" rpc 2>/dev/null)"

assert_contains "$OUT" '"id":1,"jsonrpc":"2.0","result":{"schemaVersion":1,"version":"0.2.3"}' "version reports engine + schema"
assert_contains "$OUT" '"id":2,"jsonrpc":"2.0","result":{}' "ping returns empty result"
assert_contains "$OUT" '"panels"' "schema has panels"
assert_contains "$OUT" '"id":"gaps_in"' "schema has setting ids"

assert_contains "$OUT" '"default":4000,"id":"nightlight_temperature","value":4000' "get returns typed value"
assert_contains "$OUT" '"id":"nightlight_temperature","ok":true,"value":3500' "set reports ok"
assert_contains "$OUT" '"default":4000,"id":"nightlight_temperature","value":3500' "get reflects set"
assert_contains "$OUT" '"id":"nightlight_temperature"' "changed includes the setting"
assert_contains "$OUT" '"code":-32602' "invalid value is an error"
assert_contains "$OUT" '"id":9,"jsonrpc":"2.0","result":{"id":"nightlight_temperature","ok":true}' "reset returns ok"
assert_contains "$OUT" '"default":4000,"id":"nightlight_temperature","value":4000' "reset restores default"

assert_contains "$OUT" '"grouped":true,"id":"fullwidth_style"' "keys reports grouped"
assert_contains "$OUT" '"sub":"rounding"' "keys lists rounding"
assert_contains "$OUT" '"id":"fullwidth_style","sub":"rounding","value":0' "grouped get returns sub value"
assert_contains "$OUT" '"id":"fullwidth_style","ok":true,"sub":"rounding","value":7' "grouped set reports sub"
assert_contains "$OUT" '"id":"fullwidth_style","sub":"rounding","value":7' "grouped get reflects set"
assert_contains "$OUT" '"id":"fullwidth_style","ok":true,"sub":"rounding"' "grouped reset reports sub"
assert_contains "$OUT" '"id":"fullwidth_style","sub":"rounding","value":0' "grouped reset restores default"
assert_contains "$OUT" '"id":"workspace_layout","keyed":true' "keys reports keyed"

# snapshot bundles the panel's extras so the window can render keyed and
# grouped rows without a follow-up call per setting.
assert_contains "$OUT" '"keys":{"workspace_layout"' "snapshot has keyed names"
assert_contains "$OUT" '"keyed":{"workspace_layout"' "snapshot has keyed values"
assert_contains "$OUT" '"groups":{}' "snapshot has empty groups for a panel without them"
assert_contains "$OUT" '"changed":[' "snapshot has changed entries"
assert_contains "$OUT" '"preferences":{"preferences":[' "snapshot has preferences"
assert_contains "$OUT" '"panel":"layout"' "snapshot echoes panel"
assert_contains "$OUT" '"schemaVersion":1' "snapshot has schema version"
assert_contains "$OUT" '"groups":{"fullwidth_style":' "snapshot has grouped values for windows"

assert_contains "$OUT" '"id":"gaps_in"' "search finds gaps_in"
assert_contains "$(echo "$OUT" | grep '"id":27')" '"id":"gaps_in"' \
  "search honors an explicit lang and matches the translated label"

assert_contains "$OUT" '"key":"time_format"' "preferences lists time_format"
assert_contains "$OUT" '"key":"time_format","ok":true,"value":"12h"' "preference_set writes"
assert_contains "$OUT" '"key":"time_format","options":["24h","12h","auto"],"type":"enum","value":"12h"' "preference_get reads"
assert_contains "$OUT" '"key":"time_format","ok":true,"value":"auto"' "preference_reset restores default"

assert_contains "$OUT" '"id":"nightlight_start","ok":true,"value":"20:30"' "set normalizes time"
assert_contains "$OUT" '"default":"20:00","id":"nightlight_start","value":"20:30"' "get reflects normalized time"

assert_contains "$OUT" '"code":-32601,"message":"method not found: bogus"' "unknown method is an error"
assert_contains "$OUT" '"code":-32602' "unknown setting is an error"
assert_contains "$OUT" '"code":-32700' "parse error is reported"

# Notifications must produce no response, so no line carries id 0.
assert_not_contains "$OUT" '"id":0' "notification has no response"

echo "ok"
