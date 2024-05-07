// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal.dart
// An entity that describes a signal and its data.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:module_structure_api/module_structure_api.dart';
import 'package:module_structure_api/src/models/data.dart';

/// A class that represents a signal.
///
/// It contains a name, a type, and a list of data.
class Signal {
  /// The name of the signal.
  String name;

  /// The type of the signal.
  String type;

  /// The list of data in the signal.
  List<Data> data;

  /// Creates a new instance of [Signal].
  ///
  /// Requires [name], [type], and [data] as parameters.
  Signal({required this.name, required this.type, required this.data});

  /// Converts the [Signal] instance into a JSON Map.
  ///
  /// The [Data] instances are also converted into their
  /// respective JSON representation.
  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'data': data.map((e) => e.toJson()).toList(),
      };

  /// Creates a new instance of [Signal] from a JSON Map.
  ///
  /// The [Data] instances are created from their respective
  /// JSON representation.
  factory Signal.fromJson(Map<String, dynamic> json) {
    return Signal(
      name: json['name'],
      type: json['type'],
      data: (json['data'] as List).map((e) => Data.fromJson(e)).toList(),
    );
  }

  factory Signal.empty() {
    return Signal(name: '', type: '', data: [Data.empty()]);
  }

  @override
  String toString() {
    return '$name-$type';
  }

  String getValueByTime(int time) {
    int low = 0;
    int high = data.length - 1;
    Data? closestBefore;

    while (low <= high) {
      int mid = low + (high - low) ~/ 2;
      Data midData = data[mid];

      if (midData.time == time) {
        return midData.value; // Exact match found, return immediately
      } else if (midData.time < time) {
        closestBefore =
            midData; // Potential closest match, keep searching right
        low = mid + 1;
      } else {
        high = mid - 1; // Search left
      }
    }

    // After the loop, check if we found a closest match
    if (closestBefore != null) {
      return closestBefore.value;
    } else {
      // This will be reached if the list is empty or no suitable value was found
      // TODO: this should be floating instead?
      return data.first.value;
    }
  }
}
