// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_filter_field.dart
// Inline text and wildcard filter for the Module Signals panel.
//
// Replaces the old SignalSearchField popup approach. Instead of showing
// results in a dropdown, it filters the signal list in the panel itself.
// Supports HierarchyService paths with submodule prefixes
// (e.g. "submod/sig*") and TAB completion.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/platform_icon.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';

/// Inline text and wildcard filter for the Module Signals panel.
///
/// When the user types a pattern, the Module Signals list is filtered
/// in-place to show only matching signals.  Empty filter shows all
/// signals for the current module (default behavior).
///
/// Supports:
/// - Plain prefix matching (case-insensitive)
/// - `*` and `?` glob-style wildcard matching
/// - Submodule prefixes: `submod/signal_name`
/// - TAB completion via [HierarchyService.autocompletePaths]
class SignalFilterField extends StatefulWidget {
  final HierarchyService? _hierarchy;

  /// Creates an inline signal filter field.
  const SignalFilterField({super.key, HierarchyService? hierarchy})
      : _hierarchy = hierarchy;

  @override
  State<SignalFilterField> createState() => _SignalFilterFieldState();
}

class _SignalFilterFieldState extends State<SignalFilterField> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  /// Search controller for TAB completion only.
  HierarchySearchController<SignalSearchResult>? _searchCtrl;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onFilterChanged);
    _searchCtrl = _buildSearchController();
  }

  @override
  void didUpdateWidget(covariant SignalFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._hierarchy != widget._hierarchy) {
      _searchCtrl = _buildSearchController();
    }
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_onFilterChanged)
      ..dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  HierarchySearchController<SignalSearchResult>? _buildSearchController() {
    final h = widget._hierarchy;
    if (h == null) {
      return null;
    }
    return HierarchySearchController.forSignals(h);
  }

  void _onFilterChanged() {
    final query = _textController.text;
    context.read<SignalBloc>().add(SignalFilterEvent(query));
  }

  void _onTabComplete() {
    final current = _textController.text;
    if (current.isEmpty) {
      return;
    }

    String? expanded;

    // 1) Try hierarchical path completion first (module navigation).
    final hierarchy = widget._hierarchy;
    if (hierarchy != null) {
      final suggestions = hierarchy.autocompletePaths(current);
      if (suggestions.isNotEmpty) {
        expanded = HierarchyService.longestCommonPrefix(suggestions);
        // Only accept if it actually extends the input.
        if (expanded != null && expanded.length <= current.length) {
          expanded = null;
        }
      }
    }

    // 2) Fall back to signal search completion.
    if (expanded == null) {
      final ctrl = _searchCtrl;
      if (ctrl != null) {
        ctrl.updateQuery(current);
        expanded = ctrl.tabComplete(current);
      }
    }

    if (expanded != null && expanded != current) {
      _textController.text = expanded;
      _textController.selection = TextSelection.collapsed(
        offset: expanded.length,
      );
      // Scroll the TextField to the end so the cursor is visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  void _clearFilter() {
    // Remove the listener temporarily so .clear() doesn't fire a
    // redundant SignalFilterEvent before our explicit one.
    _textController
      ..removeListener(_onFilterChanged)
      ..clear()
      ..addListener(_onFilterChanged);
    context.read<SignalBloc>().add(SignalFilterEvent(''));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            _onTabComplete();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _clearFilter();
            _focusNode.unfocus();
          }
        }
      },
      child: SizedBox(
        height: 28,
        child: Focus(
          onKeyEvent: (node, event) {
            // Intercept TAB before Flutter's focus traversal handles it.
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.tab) {
              _onTabComplete();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _textController,
            focusNode: _focusNode,
            scrollController: _scrollController,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white : Colors.black,
            ),
            decoration: InputDecoration(
              hintText: 'Module Signals\u2026',
              hintStyle: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              prefixIcon: platformIcon(
                Icons.filter_list,
                '\u{1F50D}',
                size: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _textController,
                builder: (context, value, _) {
                  if (value.text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    icon: Icon(
                      Icons.clear,
                      size: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    onPressed: _clearFilter,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  );
                },
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03),
            ),
          ),
        ),
      ),
    );
  }
}
