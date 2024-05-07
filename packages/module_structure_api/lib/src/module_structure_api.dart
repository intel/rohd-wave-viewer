// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_structure_api.dart
// An abstract class that defines the API for module structure.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:module_structure_api/module_structure_api.dart';

/// An abstract class that defines the API for module structure.
///
/// It contains a method to get the module structure.
abstract class ModuleStructureApi {
  /// Creates a new instance of [ModuleStructureApi].
  const ModuleStructureApi();

  /// Retrieves the module structure.
  ///
  /// Returns a [Future] that completes with the [ModuleStructure].
  Future<ModuleStructure> getModuleStructure();
}
