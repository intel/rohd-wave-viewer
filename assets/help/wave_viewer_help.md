# 🌊 ROHD Wave Viewer v{{VERSION}} — Help

<!-- tooltip -->

Keybindings

Waveform Navigation
  ← / →           Pan left / right
  ↑ / ↓           Scroll signals up / down
  Shift+↑ / ↓     Zoom in / out
  Shift+Scroll     Zoom at cursor
  Scroll           Pan horizontally
  F                Fit waveform to viewport
  Ctrl+Drag        Zoom to time region

Marker & Data
  Click waveform   Place time marker
  ← / → (focused)  Jump to prev / next edge

Signal List
  Click signal     Select signal
  Ctrl/Cmd+Click   Toggle selection
  Shift+Click      Select range
  Double-click     Add to monitor list
  Drag row         Reorder monitored signals
  DEL / Backspace  Remove focused signals

Search
  Type query       Filter module signals
  Tab              Complete signal path
  Esc              Clear filter

Module Tree
  Click node       Select module
  Click ▸ / ▾      Expand / collapse

<!-- details -->

## Waveform Navigation

| Key | Description |
| --- | --- |
| ← / → | Pan waveform left / right |
| ↑ / ↓ | Scroll signal list up / down |
| Shift + ↑ / ↓ | Zoom in / zoom out |
| Shift + Scroll | Zoom in / out at cursor |
| Scroll wheel | Pan horizontally |
| F | Fit entire waveform to viewport |
| Ctrl + Drag right | Draw a time region to zoom into |
| Ctrl + Drag left | Zoom out |

## Marker & Data Points

| Key | Description |
| --- | --- |
| Click waveform | Place time marker |
| ← / → (focused) | Jump to the nearest previous / next value change across focused signals |

## Signal Management

| Key | Description |
| --- | --- |
| Click signal name | Select a signal |
| Ctrl/Cmd + Click | Toggle a signal in the selection |
| Shift + Click | Select a range from the selection anchor |
| Double-click signal name | Add signal to the monitor list |
| Ctrl/Cmd + A | Select all signals in the focused signal pane |
| Drag monitored row | Reorder one signal or the selected set |
| Delete / Backspace | Remove all focused signals from the monitor list |

## Signal Search

| Key | Description |
| --- | --- |
| Type in module-signal filter | Filter by case-insensitive prefix or `*`/`?` wildcard |
| Tab | Complete the hierarchy path or signal name |
| Esc | Clear the filter and leave the field |

## Module Tree

| Key | Description |
| --- | --- |
| Click module | Select module and show signals |
| Click ▸ / ▾ | Expand or collapse sub-modules |

## Toolbar

| Key | Description |
| --- | --- |
| 📄  Load file | Open a VCD / FST / GHW file |
| 🔄  Reload | Re-read waveform from disk |
| 💾  Save list | Save monitored signal names to JSON |
| 📂  Load list | Restore monitored signals from JSON |
| Export PNG | Save the selected-signal, value, and waveform panes as an image |
| 👁  Internals | Toggle visibility of internal signals |
| ☀️/🌙  Theme | Toggle light / dark theme |

## Integrated Workflows

The following context-menu actions appear only when the embedding host or the
companion ROHD extension provides the required service:

- Send selected signals to another registered viewer.
- Navigate selected signals to ROHD or generated SystemVerilog source.
- Capture marker-time snapshots or enable live video tracking in ROHD
  DevTools.
