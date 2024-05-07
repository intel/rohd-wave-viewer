// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module.dart
// An entity that describes a module and its submodules and signals.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:module_structure_api/src/models/signal.dart';

/// A class that represents a module.
///
/// It contains a name, a list of submodules, and a list of signals.
class Module {
  /// The name of the module.
  String name;

  /// The list of submodules in the module.
  List<Module> subModules;

  /// The list of signals in the module.
  List<Signal> signals;

  /// Creates a new instance of [Module].
  ///
  /// Requires [name], [subModules], and [signals] as parameters.
  Module({required this.name, required this.subModules, required this.signals});

  /// Converts the [Module] instance into a JSON Map.
  ///
  /// The [Module] and [Signal] instances are also converted into their
  /// respective JSON representation.
  Map<String, dynamic> toJson() => {
        'name': name,
        'subModules': subModules.map((e) => e.toJson()).toList(),
        'signals': signals.map((e) => e.toJson()).toList(),
      };

  /// Creates a new instance of [Module] from a JSON Map.
  ///
  /// The [Module] and [Signal] instances are created from their respective
  /// JSON representation.
  factory Module.fromJson(Map<String, dynamic> json) {
    var subModulesJson = json['subModules'] as List;
    var signalsJson = json['signals'] as List;

    return Module(
      name: json['name'],
      subModules: subModulesJson.map((e) => Module.fromJson(e)).toList(),
      signals: signalsJson.map((e) => Signal.fromJson(e)).toList(),
    );
  }
}
