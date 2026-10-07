// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_display_utils.dart
// Utilities for generating display names for signals with qualified prefixes.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Generates display names for signals, prepending parent module names when
/// needed.
///
/// When [selectedModulePath] is provided, signals are named relative to the
/// currently selected module's position in the hierarchy:
/// - Signals belonging to the selected module → bare signal name
/// - Signals in an immediate child → `childModule/signalName`
/// - Signals in deeper descendants → `childModule/.../signalName`
/// - Signals outside the selected module's subtree → path from divergence point
///
/// When [selectedModulePath] is null, falls back to duplicate-name
/// disambiguation: signals with unique names use the base name, and duplicates
/// get progressive parent module prefixes until all names are unique.
///
/// Example with selectedModulePath = "top.counter": Input: [
///   SignalWaveform(fullPath: 'top.counter.clk'),       // in selected
///   SignalWaveform(fullPath: 'top.counter.adder.a'),    // in child
///   SignalWaveform(fullPath: 'top.timer.clk'),          // in sibling
///   ]
///   Output: { 'sig1': 'clk', 'sig2': 'adder/a', 'sig3': 'timer/clk',
///   }
Map<String, String> generateSignalDisplayNames(
  List<SignalWaveform> signals, {
  String? selectedModulePath,
}) {
  final displayNames = <String, String>{};

  if (signals.isEmpty) {
    return displayNames;
  }

  if (selectedModulePath != null) {
    // Scope-aware naming: compute display names relative to selected module
    for (final signal in signals) {
      displayNames[signal.id] = _computeScopeAwareDisplayName(
        signal,
        selectedModulePath,
      );
    }

    // Simplify: signals whose bare name is unique among monitored signals
    // don't need scope prefixes. Only keep the scope-aware name when
    // multiple monitored signals share the same base name.
    //
    // Use _signalBaseName() to extract the leaf name robustly. When the
    // signal lookup works, signal.name is the correct leaf name. When it
    // fails, signal.name falls back to signalId (which may be a full path
    // like "testbench.clk"); _signalBaseName strips any path prefix.
    // Count how many *distinct* signals share each base name.
    // Multiple instances of the same signal (same id) should not trigger
    // disambiguation against each other.
    final baseNameUniqueIds = <String, Set<String>>{};
    final signalBaseNames = <String, String>{}; // signal.id → leaf name
    for (final signal in signals) {
      final baseName = _signalBaseName(signal);
      signalBaseNames[signal.id] = baseName;
      baseNameUniqueIds.putIfAbsent(baseName, () => {}).add(signal.id);
    }
    for (final signal in signals) {
      final baseName = signalBaseNames[signal.id]!;
      if (baseNameUniqueIds[baseName]!.length == 1) {
        displayNames[signal.id] = baseName;
      }
    }

    // Resolve any remaining duplicate display names
    _resolveDisplayNameDuplicates(signals, displayNames);
  } else {
    // Fallback: original duplicate-name disambiguation
    _generateDuplicateAwareNames(signals, displayNames);
  }

  return displayNames;
}

/// Computes a display name for a signal relative to the selected module.
///
/// - If the signal is in the selected module, returns just the signal name.
/// - If the signal is in a descendant, returns the relative path from the
///   selected module (e.g., "child/grandchild/signalName").
/// - If the signal is outside the selected module's subtree, returns the path
///   from the common ancestor's divergence point.
String _computeScopeAwareDisplayName(
  SignalWaveform signal,
  String selectedModulePath,
) {
  final fullPath = signal.fullPath ?? signal.id;
  final selectedParts = _extractPathComponents(selectedModulePath);
  final signalParts = _extractPathComponents(fullPath);

  if (signalParts.isEmpty) {
    return signal.name;
  }

  // Signal name is the last component of the full path
  final signalName = signalParts.last;

  // Signal's module path is everything except the last component
  final signalModuleParts = signalParts.length > 1
      ? signalParts.sublist(0, signalParts.length - 1)
      : <String>[];

  // Strip __internal__ marker from module path comparison
  final cleanModuleParts =
      signalModuleParts.where((p) => p != '__internal__').toList();

  // Case 1: Signal belongs to the selected module → bare name
  if (_listsEqual(cleanModuleParts, selectedParts)) {
    return signalName;
  }

  // Case 2: Signal is in a descendant of the selected module
  if (_startsWith(cleanModuleParts, selectedParts)) {
    // Relative path from selected module to the signal
    final relativeParts = signalParts
        .sublist(selectedParts.length)
        .where((p) => p != '__internal__')
        .toList();
    return relativeParts.join('/');
  }

  // Case 3: Signal is outside the selected module's subtree
  // Find the longest common prefix, then show from divergence point
  final commonLen = _commonPrefixLength(cleanModuleParts, selectedParts);
  final relevantParts =
      signalParts.sublist(commonLen).where((p) => p != '__internal__').toList();

  if (relevantParts.isNotEmpty) {
    return relevantParts.join('/');
  }

  return signalName;
}

/// Resolves duplicate display names that remain after scope-aware naming.
///
/// If two signals end up with the same display name (e.g., both have
/// "adder/clk" from different subtrees), this progressively adds more
/// path context to distinguish them.
void _resolveDisplayNameDuplicates(
  List<SignalWaveform> signals,
  Map<String, String> displayNames,
) {
  // Group by display name to find duplicates (only among *distinct* ids)
  final nameToIds = <String, Set<String>>{};
  for (final signal in signals) {
    final name = displayNames[signal.id] ?? signal.name;
    nameToIds.putIfAbsent(name, () => {}).add(signal.id);
  }

  // For each group of duplicates, use fullPath-based disambiguation
  for (final entry in nameToIds.entries) {
    if (entry.value.length <= 1) {
      continue;
    }

    // Get one representative per unique id
    final seenIds = <String>{};
    final conflicting = signals
        .where((s) => entry.value.contains(s.id) && seenIds.add(s.id))
        .toList();

    // Progressively add more parent context until unique
    _resolveNameConflicts(conflicting, displayNames);
  }
}

/// Original duplicate-name disambiguation (used when no selected module).
void _generateDuplicateAwareNames(
  List<SignalWaveform> signals,
  Map<String, String> displayNames,
) {
  // Group signals by their base (leaf) name.
  // Use _signalBaseName() to robustly extract the leaf name even when
  // the signal lookup isn't available and signal.name returns the full path.
  final nameToSignals = <String, List<SignalWaveform>>{};

  for (final signal in signals) {
    final baseName = _signalBaseName(signal);
    nameToSignals.putIfAbsent(baseName, () => []).add(signal);
  }

  // Process each group — only disambiguate when *distinct* signals (by id)
  // share the same base name. Multiple instances of the same signal don't
  // need disambiguation.
  for (final entry in nameToSignals.entries) {
    final signalsWithName = entry.value;
    final uniqueIds = signalsWithName.map((s) => s.id).toSet();

    if (uniqueIds.length == 1) {
      // All instances are the same signal — use bare name for all
      for (final s in signalsWithName) {
        displayNames[s.id] = entry.key;
      }
    } else {
      // Deduplicate before resolving: pass only one representative per id
      final deduped = <SignalWaveform>[];
      final seenIds = <String>{};
      for (final s in signalsWithName) {
        if (seenIds.add(s.id)) {
          deduped.add(s);
        }
      }
      _resolveNameConflicts(deduped, displayNames);
    }
  }
}

/// Resolves naming conflicts by prepending parent module names.
///
/// For each signal, extracts the module path from fullPath and progressively
/// adds parent module names until all names are unique.
void _resolveNameConflicts(
  List<SignalWaveform> conflictingSignals,
  Map<String, String> displayNames,
) {
  // Extract path components for each signal
  final signalPaths = <SignalWaveform, List<String>>{};

  for (final signal in conflictingSignals) {
    final fullPath = signal.fullPath ?? signal.id;
    // Split by '/' or '.' depending on the path format
    final parts = _extractPathComponents(fullPath);
    signalPaths[signal] = parts;
  }

  // Start with just the signal name and progressively add more parent levels
  var parentLevels = 1;
  var allUnique = false;

  // Try increasing numbers of parent levels until names are unique
  while (!allUnique && parentLevels <= 100) {
    final candidateNames = <String, String>{};
    final seenNames = <String>{};

    for (final signal in conflictingSignals) {
      final parts = signalPaths[signal]!;
      // Build name by going back from the end by (parentLevels + 1) positions
      // +1 for the signal name itself
      final startIdx = (parts.length - parentLevels - 1).clamp(
        0,
        parts.length - 1,
      );
      final relevantParts = parts.sublist(startIdx);
      final candidateName = relevantParts.join('/');

      candidateNames[signal.id] = candidateName;
      seenNames.add(candidateName);
    }

    // Check if all names are unique
    if (seenNames.length == conflictingSignals.length) {
      // Success - all names are unique
      displayNames.addAll(candidateNames);
      allUnique = true;
    } else {
      parentLevels++;
    }
  }

  // Fallback: if we couldn't resolve conflicts even at highest level, use full
  // path
  if (!allUnique) {
    for (final signal in conflictingSignals) {
      displayNames[signal.id] = signal.id;
    }
  }
}

/// Extracts path components from a signal's full path.
///
/// Handles both '.' and '/' as separators, preferring the most common separator.
List<String> _extractPathComponents(String path) {
  if (path.isEmpty) {
    return [];
  }

  // Determine separator - use whichever appears more frequently
  final dotCount = path.split('.').length;
  final slashCount = path.split('/').length;

  late List<String> parts;
  if (slashCount > dotCount) {
    parts = path.split('/').where((p) => p.isNotEmpty).toList();
  } else {
    parts = path.split('.').where((p) => p.isNotEmpty).toList();
  }

  return parts;
}

/// Returns true if [a] and [b] have the same elements in order.
bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Returns true if [list] starts with all elements of [prefix].
bool _startsWith(List<String> list, List<String> prefix) {
  if (list.length < prefix.length) {
    return false;
  }
  for (var i = 0; i < prefix.length; i++) {
    if (list[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

/// Returns the length of the longest common prefix between [a] and [b].
int _commonPrefixLength(List<String> a, List<String> b) {
  final minLen = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < minLen; i++) {
    if (a[i] != b[i]) {
      return i;
    }
  }
  return minLen;
}

/// Extracts the base (leaf) name for a signal.
///
/// Uses `signal.name` which, when the signal metadata lookup works, returns
/// the correct leaf name (e.g., "clk"). When the lookup fails, `signal.name`
/// falls back to the signalId which may be a full hierarchical path
/// (e.g., "testbench.clk"). In that case, this function strips any path prefix
/// to return just the leaf component.
String _signalBaseName(SignalWaveform signal) {
  final name = signal.name;
  // If the name contains path separators, it's likely the full path fallback
  // from signalId rather than a true leaf name. Extract just the leaf.
  if (name.contains('.') || name.contains('/')) {
    final parts = _extractPathComponents(name);
    return parts.isNotEmpty ? parts.last : name;
  }
  return name;
}

/// Formats a signal name with its bit width information appended.
///
/// Returns:
/// - Just the signal name for single-bit signals (e.g., "clk")
/// - `signalName [msb:lsb]` for multi-bit signals if bit range is known (e.g.,
///   "data [31:0]")
/// - `signalName (width)` for multi-bit signals if bit range is unknown (e.g.,
///   "data (32)")
///
/// This provides clear visual indication of signal width without cluttering the
/// UI.
String formatSignalNameWithWidth(
  String name,
  int width, {
  int? msbBit,
  int? lsbBit,
}) {
  // Single-bit signals don't need a size indicator
  if (width <= 1) {
    return name;
  }

  // If we have explicit bit positions, use them for multi-bit signals
  if (msbBit != null && lsbBit != null) {
    return '$name [$msbBit:$lsbBit]';
  }

  // Otherwise just append the width in parentheses
  return '$name ($width)';
}
