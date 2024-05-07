// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_structure.dart
// An entity that describe the module structure of signals simulation.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:equatable/equatable.dart';
import 'package:module_structure_api/module_structure_api.dart';

/// A class that represents the structure of a module.
///
/// It contains metadata and a list of modules.
class ModuleStructure extends Equatable {
  /// The metadata of the module structure.
  final MetaData metadata;

  /// The list of modules in the module structure.
  final List<Module> modules;

  /// Creates a new instance of [ModuleStructure].
  ///
  /// Requires [metadata] and [modules] as parameters.
  ModuleStructure({required this.metadata, required this.modules});

  /// Converts the [ModuleStructure] instance into a JSON Map.
  ///
  /// The [MetaData] and [Module] instances are also converted into their
  /// respective JSON representation.
  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'modules': modules.map((e) => e.toJson()).toList(),
      };

  /// Creates a new instance of [ModuleStructure] from a JSON Map.
  ///
  /// The [MetaData] and [Module] instances are created from their respective
  /// JSON representation.
  factory ModuleStructure.fromJson(Map<String, dynamic> json) {
    return ModuleStructure(
      metadata: MetaData.fromJson(json['metadata']),
      modules:
          (json['modules'] as List).map((e) => Module.fromJson(e)).toList(),
    );
  }

  factory ModuleStructure.empty() {
    return ModuleStructure(metadata: MetaData.empty(), modules: []);
  }

  @override
  List<Object?> get props => [ModuleStructure];
}
