// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_format_menu.dart
// Shared display-format menu for signal occurrence surfaces.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show SignalValueFormat, SignalValueFormatRegistry, buildRohdPopupMenuItem;
import 'package:rohd_hierarchy/rohd_hierarchy.dart' show OccurrenceAddress;
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Popup-menu value used to open the signal display-format submenu.
const signalFormatMenuValue = 'signal_format_as';

/// Builds the top-level command that opens the display-format submenu.
PopupMenuItem<String> buildSignalFormatMenuItem({required int count}) =>
    buildRohdPopupMenuItem<String>(
      value: signalFormatMenuValue,
      icon: const Icon(Icons.numbers, size: 16),
      label: count == 1 ? 'Format As' : 'Format $count Signals As',
      textStyle: const TextStyle(fontSize: 13),
    );

/// Displays display-format choices and applies the selected occurrence format.
///
/// [signalPaths] identifies the affected rows for the local monitor-list
/// update. [addresses] supplies the corresponding hierarchy occurrence
/// addresses (in the same order/cardinality as available) so the shared
/// [SignalValueFormatRegistry] can be updated; occurrences without a
/// resolvable address (e.g. synthesized bit-field rows) are skipped for the
/// shared registry but still get the local monitor-list update.
Future<void> showSignalFormatMenu(
  BuildContext context, {
  required Offset globalPosition,
  required Set<String> signalPaths,
  Iterable<OccurrenceAddress?> addresses = const [],
  ValueChanged<MonitorValueFormat>? onFormatSelected,
}) async {
  if (signalPaths.isEmpty) {
    return;
  }
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final selectedFormat = await showMenu<SignalValueFormat>(
    context: context,
    position: RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlay.size.width - local.dx,
      overlay.size.height - local.dy,
    ),
    items: SignalValueFormat.values
        .map(
          (format) => buildRohdPopupMenuItem<SignalValueFormat>(
            value: format,
            icon: Icon(_iconFor(format), size: 16),
            label: _labelFor(format),
            textStyle: const TextStyle(fontSize: 13),
          ),
        )
        .toList(),
  );
  if (selectedFormat == null || !context.mounted) {
    return;
  }
  final resolvedAddresses = addresses.whereType<OccurrenceAddress>().toList();
  if (resolvedAddresses.isNotEmpty) {
    SignalValueFormatRegistry.setFormatFor(
      resolvedAddresses,
      selectedFormat,
    );
  }
  final monitorFormat = MonitorValueFormat.values.singleWhere(
    (format) => format.name == selectedFormat.name,
  );
  final callback = onFormatSelected;
  if (callback != null) {
    callback(monitorFormat);
    return;
  }
  context.read<SignalBloc>().add(
        SignalSetOccurrenceValueFormatEvent(
          signalPaths: signalPaths,
          valueFormat: monitorFormat,
        ),
      );
}

String _labelFor(SignalValueFormat format) => switch (format) {
      SignalValueFormat.waveform => 'Waveform Default',
      SignalValueFormat.binary => 'Binary',
      SignalValueFormat.hexadecimal => 'Hexadecimal',
      SignalValueFormat.unsignedDecimal => 'Unsigned Decimal',
      SignalValueFormat.signedDecimal => 'Signed Decimal',
      SignalValueFormat.octal => 'Octal',
      SignalValueFormat.ascii => 'ASCII',
    };

IconData _iconFor(SignalValueFormat format) => switch (format) {
      SignalValueFormat.waveform => Icons.timeline,
      SignalValueFormat.binary => Icons.looks_one,
      SignalValueFormat.hexadecimal => Icons.tag,
      SignalValueFormat.unsignedDecimal => Icons.pin,
      SignalValueFormat.signedDecimal => Icons.plus_one,
      SignalValueFormat.octal => Icons.filter_8,
      SignalValueFormat.ascii => Icons.text_fields,
    };
