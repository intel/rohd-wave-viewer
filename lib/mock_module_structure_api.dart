// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mock_module_structure_api.dart
// A mock implementation of the ModuleStructureApi class.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:convert';
import 'package:module_structure_api/module_structure_api.dart';

class MockModuleStructureApi extends ModuleStructureApi {
  @override
  Future<ModuleStructure> getModuleStructure() {
    String jsonString = '''
  {
    "metadata": {
      "source": "Source1",
      "timescale": "1ns",
      "date": "2022-01-01"
    },
    "modules": [
      {
        "name": "Counter",
        "subModules": [
          {
            "name": "counter_sub_module",
            "subModules": [],
            "signals": [
              {
                "name": "SubSignal1",
                "type": "hex",
                "data": [
                  {
                    "time": 1,
                    "value": "1"
                  },
                  {
                    "time": 2,
                    "value": "0"
                  },
                  {
                    "time": 3,
                    "value": "ABCD102"
                  },
                  {
                    "time": 4,
                    "value": "1"
                  },
                  {
                    "time": 5,
                    "value": "1"
                  }
                ]
              }
            ]
          }
        ],
        "signals": [
          {
            "name": "Signal1",
            "type": "bin",
            "data": [
              {
                "time": 1,
                "value": "XXXXX"
              },
              {
                "time": 5,
                "value": "1"
              },
              {
                "time": 12,
                "value": "ZZZZZ"
              },
              {
                "time": 18,
                "value": "1"
              }
            ]
          },
          {
            "name": "Signal2",
            "type": "bin",
            "data": [
              {
                "time": 1,
                "value": "1"
              },
              {
                "time": 2,
                "value": "0"
              },
              {
                "time": 4,
                "value": "1"
              },
              {
                "time": 9,
                "value": "1"
              },
              {
                "time": 10,
                "value": "0"
              },
              {
                "time": 11,
                "value": "1"
              },
              {
                "time": 12,
                "value": "0"
              },
              {
                "time": 13,
                "value": "1"
              }
            ]
          },
          {
            "name": "Signal3",
            "type": "hex",
            "data": [
              {
                "time": 5,
                "value": "ZZZ"
              },
              {
                "time": 7,
                "value": "1"
              },
              {
                "time": 9,
                "value": "XXX"
              },
              {
                "time": 14,
                "value": "1"
              },
              {
                "time": 17,
                "value": "ZZ"
              }
            ]
          }
        ]
      }
    ]
  }
  ''';

    // Parse the JSON string into a Map.
    Map<String, dynamic> jsonMap = jsonDecode(jsonString);

    // Use the fromJson factory constructor to create a WaveformNode object.
    return Future<ModuleStructure>.value(ModuleStructure.fromJson(jsonMap));
  }
}
