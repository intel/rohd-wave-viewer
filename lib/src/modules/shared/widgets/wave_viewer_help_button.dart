// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_viewer_help_button.dart
// Help button widget for the wave viewer toolbar.
//
// Content is loaded from assets/help/wave_viewer_help.md.
// Edit that markdown file to update hover tooltip and dialog content.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_wave_viewer/src/const/app_version.dart';

/// A help button for the wave viewer.
///
/// Content is driven by `assets/help/wave_viewer_help.md`.
/// Edit that file to update the hover tooltip and click-open dialog.
class WaveViewerHelpButton extends StatelessWidget {
  /// Whether the current theme is dark mode.
  final bool isDark;

  /// Whether color emoji rendering is available on this platform.
  final bool hasColorEmoji;

  /// Whether the viewer is embedded as a dependency inside a host app
  /// (e.g. the `rohd_devtools_extension`).
  ///
  /// When `true` (the default) the help asset is resolved via the
  /// package-qualified path `packages/rohd_wave_viewer/assets/help/...`,
  /// which is how Flutter bundles assets owned by a dependency package.
  ///
  /// When `false` (standalone / VS Code webview, where `rohd_wave_viewer`
  /// is the root application) the bare `assets/help/...` path is used,
  /// avoiding a spurious 404 for the non-existent package path.
  final bool isEmbedded;

  /// Create a [WaveViewerHelpButton].
  const WaveViewerHelpButton({
    required this.isDark,
    this.hasColorEmoji = true,
    this.isEmbedded = true,
    super.key,
  });

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<bool>('isDark', isDark))
      ..add(DiagnosticsProperty<bool>('hasColorEmoji', hasColorEmoji))
      ..add(DiagnosticsProperty<bool>('isEmbedded', isEmbedded));
  }

  @override
  Widget build(BuildContext context) => MarkdownHelpButton(
        assetPath: 'assets/help/wave_viewer_help.md',
        package: isEmbedded ? 'rohd_wave_viewer' : null,
        isDark: isDark,
        substitutions: {'VERSION': appVersion},
        labelIcon: hasColorEmoji
            ? null
            : Icon(
                Icons.help_outline,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
      );
}
