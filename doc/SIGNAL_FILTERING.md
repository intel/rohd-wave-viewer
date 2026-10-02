# Signal Filtering

The **Module Signals** filter narrows the signals displayed for the currently selected module. It supports case-insensitive text prefixes and the familiar `*` and `?` wildcard characters.

The filter is intentionally scoped to the selected module's signal list. Select a different module in the hierarchy tree to filter that module's signals.

## Quick Reference

| Query | Matches |
| --- | --- |
| `clk` | Signal names or full paths beginning with `clk` |
| `data*` | Names or paths beginning with `data` |
| `*_valid` | Names or paths ending in `_valid` |
| `?en` | Three-character names or paths ending in `en`, such as `ren` |
| `top/cpu/clk` | A signal path beginning with `top/cpu/clk` |

Matching is case-insensitive. An empty filter displays all signals that are currently visible for the selected module.

## Text Prefixes

Queries without wildcards perform a case-insensitive prefix match against both the signal name and its hierarchy path.

For example, `data` matches `data_in`, `data_out`, and a hierarchy path that starts with `data`. It does not match a name that only contains `data` later in the string, such as `my_data`.

## Wildcards

| Wildcard | Meaning |
| --- | --- |
| `*` | Matches zero or more characters |
| `?` | Matches exactly one character |

Wildcards apply to the complete signal name or hierarchy path. Use `*` on both sides when looking for a substring:

```text
*data*       Find names or paths containing data
*_valid      Find names or paths ending in _valid
data?        Find five-character names or paths beginning with data
```

Paths are treated as ordinary text by the filter. For example, `top/*/clk` can match a path with characters between `top/` and `/clk`; it does not assign a special hierarchy meaning to `*` or `**`.

## Completion and Clearing

- Press `Tab` to complete the current hierarchy path or signal name when a completion is available.
- Press `Esc` to clear the filter and leave the field.
- Use the clear button at the end of the filter field to remove the current query.

## Notes

- The filter applies after the **Internals** setting, so hidden internal signals do not appear in results.
- The filter matches the selected module's list in place; it does not search all modules in the hierarchy.
- Character classes, alternation, grouping, and other regular-expression syntax are not currently supported. Characters such as `[` and `(` are treated as literal text unless they appear with `*` or `?` in a wildcard query.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
