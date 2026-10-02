// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_overlay.dart
// Auto-hiding overlay wrapper for the hierarchy navigation panel.
//
// The panel slides in from the left edge when the mouse approaches, and
// slides out when the mouse leaves.  A pin icon lets the user lock the
// panel open, converting it from an overlay into a normal pane that shifts
// the main content rightward.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Inherited widget that lets descendants temporarily hold the overlay open
/// (e.g. while a context menu is visible).
///
/// Call [hold] before opening a popup and [release] when it closes.
class HierarchyOverlayHold extends InheritedWidget {
  final VoidCallback _hold;
  final VoidCallback _release;

  /// Creates an inherited widget that exposes overlay hold callbacks.
  const HierarchyOverlayHold({
    required VoidCallback hold,
    required VoidCallback release,
    required super.child,
    super.key,
  })  : _hold = hold,
        _release = release;

  /// Returns the nearest overlay hold controller, if any.
  static HierarchyOverlayHold? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HierarchyOverlayHold>();

  /// Increment the hold count – prevents the overlay from auto-hiding.
  VoidCallback get hold => _hold;

  /// Decrement the hold count – allows auto-hiding again.
  VoidCallback get release => _release;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ObjectFlagProperty<VoidCallback>.has('hold', hold))
      ..add(ObjectFlagProperty<VoidCallback>.has('release', release));
  }

  @override
  bool updateShouldNotify(HierarchyOverlayHold oldWidget) => false;
}

/// Inherited widget that exposes the pin state to descendants.
///
/// The module-tree header in module_tree_panel.dart reads this to
/// render the pin icon inline with the expand/collapse buttons.
class HierarchyPinState extends InheritedWidget {
  final bool _isPinned;
  final ValueChanged<bool>? _onPinChanged;

  /// Creates an inherited widget that exposes hierarchy pin state.
  const HierarchyPinState({
    required bool isPinned,
    required super.child,
    super.key,
    ValueChanged<bool>? onPinChanged,
  })  : _isPinned = isPinned,
        _onPinChanged = onPinChanged;

  /// Look up the nearest [HierarchyPinState], or null if not provided.
  static HierarchyPinState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HierarchyPinState>();

  /// Whether the panel is currently pinned open.
  bool get isPinned => _isPinned;

  /// Callback to toggle the pin state.
  ValueChanged<bool>? get onPinChanged => _onPinChanged;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(FlagProperty('isPinned', value: isPinned, ifFalse: 'not pinned'))
      ..add(
        ObjectFlagProperty<ValueChanged<bool>?>.has(
          'onPinChanged',
          onPinChanged,
        ),
      );
  }

  @override
  bool updateShouldNotify(HierarchyPinState oldWidget) =>
      _isPinned != oldWidget._isPinned;
}

/// Wraps `child` in an auto-hiding overlay that slides in from the left
/// when the mouse enters a thin trigger zone along the left edge.
///
/// When pinned, the overlay becomes a permanent pane that pushes the
/// main content to the right.
class HierarchyOverlay extends StatefulWidget {
  final Widget _child;
  final double _panelWidth;
  final double _triggerWidth;
  final double _panelOpacity;
  final Duration _animationDuration;
  final bool _isPinned;
  final ValueChanged<bool>? _onPinChanged;

  /// Creates an auto-hiding hierarchy overlay.
  const HierarchyOverlay({
    required Widget child,
    super.key,
    double panelWidth = 320,
    double triggerWidth = 18,
    double panelOpacity = 0.92,
    Duration animationDuration = const Duration(milliseconds: 200),
    bool isPinned = false,
    ValueChanged<bool>? onPinChanged,
  })  : _child = child,
        _panelWidth = panelWidth,
        _triggerWidth = triggerWidth,
        _panelOpacity = panelOpacity,
        _animationDuration = animationDuration,
        _isPinned = isPinned,
        _onPinChanged = onPinChanged;

  @override
  State<HierarchyOverlay> createState() => _HierarchyOverlayState();
}

class _HierarchyOverlayState extends State<HierarchyOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  /// Number of active holds (e.g. open context menus) preventing auto-hide.
  int _holdCount = 0;

  /// Whether the mouse pointer is currently inside the panel region.
  bool _mouseInside = false;

  void _holdOpen() => _holdCount++;

  void _releaseHold() {
    _holdCount--;
    if (_holdCount <= 0) {
      _holdCount = 0;
      // Only hide if the mouse is actually outside the panel.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_mouseInside) {
          _hide();
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget._animationDuration,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1, 0), // fully off-screen left
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    // If initially pinned, snap open.
    if (widget._isPinned) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant HierarchyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When pinned externally, ensure panel is visible.
    if (widget._isPinned && !oldWidget._isPinned) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show() {
    _controller.forward();
  }

  void _hide() {
    // Don't hide if pinned or if something is holding it open.
    if (widget._isPinned || _holdCount > 0) {
      return;
    }
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelWidth = widget._panelWidth;

    // ── Wrap child in HierarchyPinState so descendants (e.g.
    //    _ModuleTreeHeader) can render the pin icon inline. ──
    final childWithPinState = HierarchyOverlayHold(
      hold: _holdOpen,
      release: _releaseHold,
      child: HierarchyPinState(
        isPinned: widget._isPinned,
        onPinChanged: widget._onPinChanged,
        child: widget._child,
      ),
    );

    // ── Panel content ──
    final panelContent = ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          boxShadow: widget._isPinned
              ? [] // No shadow when pinned (it's a normal pane)
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(2, 0),
                  ),
                ],
        ),
        child: childWithPinState,
      ),
    );

    // ── When pinned: no animation, no trigger zone ──
    // The parent layout handles showing this as a real pane.
    if (widget._isPinned) {
      return SizedBox(width: panelWidth, child: panelContent);
    }

    // ── When unpinned: sliding overlay ──
    return Stack(
      fit: StackFit.expand,
      children: [
        // Trigger zone: thin invisible strip along the left edge
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: widget._triggerWidth,
          child: MouseRegion(
            onEnter: (_) => _show(),
            opaque: false, // let clicks through when panel is hidden
            child: const SizedBox.expand(),
          ),
        ),

        // Sliding overlay panel (always mounted to preserve state)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: panelWidth,
          child: SlideTransition(
            position: _slideAnimation,
            child: MouseRegion(
              onEnter: (_) => _mouseInside = true,
              onExit: (_) {
                // Ignore exit events caused by dialog barriers while held.
                if (_holdCount > 0) {
                  return;
                }
                _mouseInside = false;
                _hide();
              },
              child: Opacity(
                opacity: widget._panelOpacity,
                child: panelContent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
