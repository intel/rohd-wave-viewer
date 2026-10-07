// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// initial_waveform_source.dart
// Startup waveform source parsing shared by application entry points.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Query parameter used by the web application to load a waveform at startup.
const waveformFileQueryParameter = 'waveFormFile';

/// Query parameter used to select monitored signals at startup.
const signalListQueryParameter = 'signalList';

/// Returns the non-empty startup waveform source from [pageUri], if present.
String? waveformSourceFromUri(Uri pageUri) {
  final source = pageUri.queryParameters[waveformFileQueryParameter]?.trim();
  return source == null || source.isEmpty ? null : source;
}

/// Returns ordered signal hierarchy paths requested by [pageUri].
///
/// The parameter may be repeated and each value may contain a comma-separated
/// list. Empty entries are discarded while duplicates and ordering are
/// preserved.
List<String> signalPathsFromUri(Uri pageUri) => [
      for (final value
          in pageUri.queryParametersAll[signalListQueryParameter] ??
              const <String>[])
        for (final path in value.split(','))
          if (path.trim().isNotEmpty) path.trim(),
    ];

/// Whether [source] identifies an asset in the Flutter asset bundle.
bool isFlutterAssetSource(String source) =>
    source.startsWith('assets/') || source.startsWith('packages/');

/// Extracts the waveform file name used for format detection and display.
String waveformFileNameFromSource(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    final fileName = uri.pathSegments.last;
    if (fileName.isNotEmpty) {
      return fileName;
    }
  }

  final normalized = source.replaceAll(r'\', '/');
  final fileName = normalized.substring(normalized.lastIndexOf('/') + 1);
  if (fileName.isEmpty) {
    throw const FormatException(
      'Waveform source does not contain a file name.',
    );
  }
  return fileName;
}
