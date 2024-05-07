// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// metadata.dart
// An entity that describes the metadata of a module structure.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

/// A class that represents the metadata of a module structure.
///
/// It contains source, timescale, and date.
class MetaData {
  /// The source of the metadata.
  String source;

  /// The timescale of the metadata.
  String timescale;

  /// The date of the metadata.
  String date;

  /// Creates a new instance of [MetaData].
  ///
  /// Requires [source], [timescale], and [date] as parameters.
  MetaData({required this.source, required this.timescale, required this.date});

  /// Converts the [MetaData] instance into a JSON Map.
  Map<String, dynamic> toJson() => {
        'source': source,
        'timescale': timescale,
        'date': date,
      };

  /// Creates a new instance of [MetaData] from a JSON Map.
  factory MetaData.fromJson(Map<String, dynamic> json) {
    return MetaData(
      source: json['source'],
      timescale: json['timescale'],
      date: json['date'],
    );
  }

  factory MetaData.empty() {
    return MetaData(source: '', timescale: '', date: '');
  }
}
