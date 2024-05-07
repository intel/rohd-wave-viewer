// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_structure_repository.dart
// Domain layer that manages the retrieval of module structures.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:module_structure_api/module_structure_api.dart';

/// A class that manages the retrieval of module structures.
///
/// It uses an instance of [ModuleStructureApi] to retrieve the data.
class ModuleStructureRepository {
  Module? _selectedModule;

  Module? get selectedModule => _selectedModule;

  /// The [ModuleStructureApi] instance used to retrieve the data.
  final ModuleStructureApi _moduleStructureApi;

  /// Creates a new instance of [ModuleStructureRepository].
  ///
  /// Requires [moduleStructureApi] as a parameter.
  ModuleStructureRepository({
    required ModuleStructureApi moduleStructureApi,
  }) : _moduleStructureApi = moduleStructureApi;

  void selectModule(Module module) {
    _selectedModule = module;
  }

  /// Retrieves the module structure.
  ///
  /// Returns a [Future] that completes with the [ModuleStructure].
  Future<ModuleStructure> getModuleStructure() =>
      _moduleStructureApi.getModuleStructure();

  List<Signal> getSignalsBySelectedModule(Module module) => module.signals;
}
