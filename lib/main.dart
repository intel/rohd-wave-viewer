// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// The main entry point for ROHD Wave Viewer.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/material.dart';
import 'package:rohd_wave_viewer/app.dart';
import 'package:module_structure_repository/module_structure_repository.dart';

import 'mock_module_structure_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setGlobal(IdeTheme, getIdeTheme());
  runApp(
    App(
      moduleStructureRepository: ModuleStructureRepository(
        moduleStructureApi: MockModuleStructureApi(),
      ),
    ),
  );
}
