// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wellen_waveform_api.dart
// Implementation of SignalWaveformApi using Wellen library
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:developer' as developer;

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

import 'external_library_io.dart'
    if (dart.library.js_interop) 'external_library_web.dart';
import 'rust/api.dart' as rust;
import 'rust/frb_generated.dart' show RustLib;

/// Implementation of [SignalWaveformApi] using the Wellen library.
///
/// This reads VCD, FST, and GHW through native FFI or a preloaded browser
/// WebAssembly module.
class WellenSignalWaveformApi extends SignalWaveformApi {
  static bool _initialized = false;
  rust.WaveformStructure? _cachedStructure;
  bool _isLoaded = false;

  /// Maps [OccurrenceAddress] to the Wellen signals that provide its value.
  ///
  /// Populated during [_convertToModuleStructure] so that
  /// [getWaveformData] can translate hierarchy pathnames into the
  /// identifiers that the Rust/Wellen backend expects.
  final Map<OccurrenceAddress, _WellenSignalSource> _wellenSignalSources = {};

  /// Hierarchy service for pathname → [OccurrenceAddress] resolution.
  HierarchyService? _hierarchyService;

  bool get isLoaded => _isLoaded;

  /// Initialize the Rust FFI library.
  ///
  /// This must be called once before using any WellenSignalWaveformApi instances.
  /// On web, the WASM must already be loaded via wasm_bindgen() before calling this.
  static Future<void> init() async {
    if (!_initialized) {
      // On web, pass an ExternalLibrary to skip WASM loading (already done via wasm_bindgen).
      // On native, returns null to let flutter_rust_bridge load the library normally.
      await RustLib.init(externalLibrary: createPreloadedExternalLibrary());
      _initialized = true;
    }
  }

  /// Loads a waveform file from the given path.
  ///
  /// This must be called before any other methods.
  /// Supports VCD, FST, and GHW formats.
  Future<void> loadFile(String filePath) async {
    await init();
    try {
      // Ask the Rust library to load the waveform file first so internal
      // WAVEFORM_STATE is populated. The generated API exposes `loadWaveform`.
      rust.loadWaveform(filePath: filePath);

      // After loading, request the structure from Rust and cache it locally.
      _cachedStructure = rust.getWaveformStructure();

      if (_cachedStructure == null) {
        throw StateError('Failed to retrieve waveform structure after loading');
      }

      _isLoaded = true;
    } catch (e, stackTrace) {
      developer.log(
        '[WellenSignalWaveformApi] Error loading waveform: $e',
        name: 'WellenSignalWaveformApi',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  double _computeTimescaleToPsFromMetadata(rust.WaveformStructure? structure) {
    if (structure == null) return 1.0;
    final tsStr = structure.metadata.timescale; // e.g. "1ps" or "1ns"
    final int tsFactor = structure.metadata.timescaleFactor;
    String unit = 'ps';
    final match = RegExp(r'\d+(.*)').firstMatch(tsStr);
    if (match != null) {
      unit = match.group(1) ?? 'ps';
    }
    double unitToPs;
    switch (unit) {
      case 's':
        unitToPs = 1e12;
      case 'ms':
        unitToPs = 1e9;
      case 'us':
        unitToPs = 1e6;
      case 'ns':
        unitToPs = 1e3;
      case 'ps':
        unitToPs = 1.0;
      case 'fs':
        unitToPs = 1e-3;
      case 'as':
        unitToPs = 1e-6;
      case 'zs':
        unitToPs = 1e-9;
      default:
        unitToPs = 1.0;
    }
    return tsFactor * unitToPs;
  }

  /// Loads a waveform from bytes.
  ///
  /// This is useful for web environments or when the file is already in memory.
  /// [fileName] is optional and used for format detection hints.
  Future<void> loadBytes(List<int> bytes, {String? fileName}) async {
    await init();
    try {
      rust.loadWaveformFromBytes(bytes: bytes, fileName: fileName);
      _cachedStructure = rust.getWaveformStructure();

      if (_cachedStructure == null) {
        throw StateError(
          'Failed to retrieve waveform structure after loading bytes',
        );
      }

      _isLoaded = true;
    } catch (e, stackTrace) {
      developer.log(
        '[WellenSignalWaveformApi] Error in loadBytes: $e',
        name: 'WellenSignalWaveformApi',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // @override
  // Future<ModuleStructure> getModuleStructure() async {
  //   if (!_isLoaded || _cachedStructure == null) {
  //     throw StateError('No waveform loaded. Call loadFile() first.');
  //   }

  //   // Get all signal IDs and load their waveform data
  //   final signalIds = _cachedStructure!.modules
  //       .expand((m) => m.signals)
  //       .map((s) => s.id)
  //       .toList();

  //   if (signalIds.isEmpty) {
  //     return _convertToModuleStructure(_cachedStructure!, []);
  //   }

  //   // Load waveform data for all signals
  //   List<rust.SignalWaveformData> waveformData;
  //   try {
  //     waveformData = rust.getWaveformData(
  //       signalIds: signalIds,
  //       startTime: null,
  //       endTime: null,
  //     );
  //   } catch (e, st) {
  //     developer.log(
  //       '[WellenSignalWaveformApi] Error loading waveform data: $e',
  //       name: 'WellenSignalWaveformApi',
  //       error: e,
  //       stackTrace: st,
  //     );
  //     rethrow;
  //   }

  //   // Return module structure with waveform data
  //   return _convertToModuleStructure(_cachedStructure!, waveformData);
  // }

  /// Returns the module hierarchy extracted from the loaded waveform file.
  ///
  /// This is a Wellen-specific convenience for feeding hierarchy data into
  /// the hierarchy API.  It does NOT load waveform data — use [getWaveformData]
  /// for that.
  Future<ModuleStructure> getModuleStructureOnly() async {
    if (!_isLoaded || _cachedStructure == null) {
      throw StateError('No waveform loaded. Call loadFile() first.');
    }

    return _convertToModuleStructure(_cachedStructure!, []);
  }

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async {
    if (!_isLoaded) {
      throw StateError('No waveform loaded. Call loadFile() first.');
    }

    final requests = [
      for (final signalId in signalIds)
        (
          signalId: signalId,
          source: _resolveWellenSignalSource(signalId),
        ),
    ];
    final wellenIds = requests
        .expand((request) => request.source.fields)
        .map((field) => field.id)
        .toSet()
        .toList();

    final rustWaveformData = rust.getWaveformData(
      signalIds: wellenIds,
      startTime: startTime != null
          ? BigInt.from(_picosecondsToNativeStart(startTime))
          : null,
      endTime: endTime != null
          ? BigInt.from(_picosecondsToNativeEnd(endTime))
          : null,
    );

    final dataByWellenId = {
      for (final waveform in rustWaveformData)
        waveform.signalId: _convertWaveformData(
          waveform,
          startTime: startTime,
          endTime: endTime,
        ).data,
    };

    return requests
        .map(
          (request) => _buildRequestedWaveform(
            request.signalId,
            request.source,
            dataByWellenId,
          ),
        )
        .toList();
  }

  int _picosecondsToNativeStart(int timePs) {
    final multiplier = _computeTimescaleToPsFromMetadata(_cachedStructure);
    return (timePs / multiplier).ceil();
  }

  int _picosecondsToNativeEnd(int timePs) {
    final multiplier = _computeTimescaleToPsFromMetadata(_cachedStructure);
    return (timePs / multiplier).floor();
  }

  @override
  Stream<WaveformData> streamWaveformData({
    required List<String> signalIds,
    int? startTime,
  }) async* {
    // For now, get all data at once and yield
    // In the future, this could stream in chunks for large waveforms
    final waveformDataList = await getWaveformData(
      signalIds: signalIds,
      startTime: startTime,
    );

    for (final waveformData in waveformDataList) {
      yield waveformData;
    }
  }

  /// Converts Wellen's WaveformStructure to viewer's ModuleStructure.
  ModuleStructure _convertToModuleStructure(
    rust.WaveformStructure wellenStructure,
    List<rust.SignalWaveformData> waveformData,
  ) {
    // Build a map of signal ID to waveform data for quick lookup
    final dataMap = <String, List<Data>>{};
    // Compute timescale multiplier to convert native units -> picoseconds
    final double timescaleToPs = _computeTimescaleToPsFromMetadata(
      wellenStructure,
    );
    for (final signalData in waveformData) {
      final list = signalData.data.map((dp) {
        final int tPs = (dp.time.toDouble() * timescaleToPs).round();
        return Data(time: tPs, value: dp.value);
      }).toList();
      // Ensure data is sorted ascending by time for painters and lookups
      list.sort((a, b) => a.time.compareTo(b.time));
      dataMap[signalData.signalId] = list;
    }

    // Convert metadata start/end to picoseconds as well
    final int startTimePs =
        (wellenStructure.metadata.startTime.toDouble() * timescaleToPs).round();
    final int endTimePs =
        (wellenStructure.metadata.endTime.toDouble() * timescaleToPs).round();
    final metadata = MetaData(
      source: wellenStructure.metadata.source,
      timescale: wellenStructure.metadata.timescale,
      date: wellenStructure.metadata.date ?? '',
      startTime: startTimePs,
      endTime: endTimePs,
      timescaleFactor: wellenStructure.metadata.timescaleFactor,
      version: wellenStructure.metadata.version,
      format: WaveFormat.fromString(wellenStructure.metadata.format),
    );

    // Convert module tree
    final modules = wellenStructure.modules
        .map((moduleNode) => _convertModuleNode(moduleNode, dataMap))
        .toList();

    _wellenSignalSources.clear();
    if (modules.isEmpty) {
      _hierarchyService = null;
      return ModuleStructure(metadata: metadata, modules: const []);
    }

    final root = modules.length == 1
        ? modules.single
        : HierarchyOccurrence(
            name: 'root',
            definition: 'waveform',
            children: modules,
          );
    // Assign OccurrenceAddresses and build the Wellen signal ID map.
    // Assign OccurrenceAddresses and build the Wellen signal ID map.
    root.buildAddresses();
    for (var i = 0; i < modules.length; i++) {
      _buildWellenIdMap(modules[i], wellenStructure.modules[i]);
    }
    // Create a HierarchyService for pathname → address resolution.
    _hierarchyService = BaseHierarchyAdapter.fromTree(root);

    return ModuleStructure(
      metadata: metadata,
      modules: [root],
      hierarchyService: _hierarchyService,
    );
  }

  /// Recursively converts a ModuleNode to HierarchyOccurrence.
  HierarchyOccurrence _convertModuleNode(
    rust.ModuleNode moduleNode,
    Map<String, List<Data>> dataMap,
  ) {
    final ports = <SignalOccurrence>[];
    final signalNames = <String>{};
    for (final signalInfo in moduleNode.signals) {
      if (!signalNames.add(signalInfo.name)) {
        continue;
      }
      ports.add(
        SignalOccurrence(
          name: signalInfo.name,
          direction: _inferDirection(signalInfo.name),
          width: signalInfo.bitWidth,
        ),
      );
    }

    for (final structScope in moduleNode.subModules
        .where((scope) => scope.scopeType == 'struct')) {
      final direction = _inferDirection(structScope.name);
      var startBit = 0;
      final fields = <Map<String, dynamic>>[];
      for (final field in structScope.signals) {
        fields.add({
          'name': field.name,
          'width': field.bitWidth,
          'bits': List.generate(
            field.bitWidth,
            (index) => startBit + index,
          ),
        });
        startBit += field.bitWidth;
      }
      if (fields.isNotEmpty && signalNames.add(structScope.name)) {
        ports.add(
          SignalOccurrence(
            name: structScope.name,
            direction: direction,
            width: startBit,
            logicType: {
              'typeName': structScope.componentName.isEmpty
                  ? structScope.name
                  : structScope.componentName,
              'fields': fields,
            },
          ),
        );
      }
    }

    final children = moduleNode.subModules
        .where((subModule) => subModule.scopeType != 'struct')
        .map((subModule) => _convertModuleNode(subModule, dataMap))
        .toList();

    return HierarchyOccurrence(
      name: moduleNode.name,
      // Prefer the FST/wellen `component` name (Dart `definitionName` for
      // ROHD-emitted FSTs) over the bare scope-type keyword so that
      // collateral lookups (FLC, schematic, cross-probe) get the exact
      // module definition identifier.  Falls back to the scope type when
      // the format does not provide a component name.
      definition: moduleNode.componentName.isNotEmpty
          ? moduleNode.componentName
          : moduleNode.scopeType,
      signals: ports,
      children: children,
    );
  }

  /// Infer port direction from signal name conventions.
  String _inferDirection(String signalName) {
    final lower = signalName.toLowerCase();
    if (lower.startsWith('i_') || lower.contains('_in')) {
      return 'input';
    } else if (lower.startsWith('o_') || lower.contains('_out')) {
      return 'output';
    } else if (lower.startsWith('io_') || lower.contains('_inout')) {
      return 'inout';
    }
    return 'inout'; // Default to inout if unclear
  }

  /// Maps real and recovered struct signals to their Wellen sources.
  void _buildWellenIdMap(
    HierarchyOccurrence occurrence,
    rust.ModuleNode moduleNode,
  ) {
    final rawSignalsByName = <String, rust.SignalInfo>{};
    for (final signal in moduleNode.signals) {
      rawSignalsByName.putIfAbsent(signal.name, () => signal);
    }
    for (final signal in occurrence.signals) {
      final rawSignal = rawSignalsByName[signal.name];
      if (rawSignal != null && signal.address != null) {
        _wellenSignalSources[signal.address!] = _WellenSignalSource([
          _WellenSignalField(rawSignal.fullPath, rawSignal.bitWidth),
        ]);
      }
    }

    for (final structScope in moduleNode.subModules
        .where((scope) => scope.scopeType == 'struct')) {
      final structIndex = occurrence.signalIndexByName(structScope.name);
      if (structIndex >= 0) {
        final structSignal = occurrence.signals[structIndex];
        if (structSignal.address != null) {
          _wellenSignalSources[structSignal.address!] = _WellenSignalSource([
            for (final field in structScope.signals)
              _WellenSignalField(field.fullPath, field.bitWidth),
          ]);
        }
      }
    }

    final childModules = moduleNode.subModules
        .where((subModule) => subModule.scopeType != 'struct')
        .toList();
    for (var i = 0;
        i < occurrence.children.length && i < childModules.length;
        i++) {
      _buildWellenIdMap(occurrence.children[i], childModules[i]);
    }
  }

  _WellenSignalSource _resolveWellenSignalSource(String pathname) {
    final addr = _hierarchyService?.pathnameToAddress(pathname);
    if (addr != null) {
      final source = _wellenSignalSources[addr];
      if (source != null) {
        return source;
      }
    }
    return _WellenSignalSource([_WellenSignalField(pathname, 1)]);
  }

  WaveformData _buildRequestedWaveform(
    String signalId,
    _WellenSignalSource source,
    Map<String, List<Data>> dataByWellenId,
  ) {
    if (source.fields.length == 1) {
      return WaveformData(
        signalId: signalId,
        data: dataByWellenId[source.fields.single.id] ?? const [],
      );
    }

    final events = <int, Map<int, String>>{};
    for (var fieldIndex = 0; fieldIndex < source.fields.length; fieldIndex++) {
      final field = source.fields[fieldIndex];
      for (final datum in dataByWellenId[field.id] ?? const <Data>[]) {
        events.putIfAbsent(datum.time, () => {})[fieldIndex] = datum.value;
      }
    }

    final fieldValues = [
      for (final field in source.fields) 'x' * field.width,
    ];
    final packedData = <Data>[];
    final times = events.keys.toList()..sort();
    for (final time in times) {
      for (final entry in events[time]!.entries) {
        fieldValues[entry.key] = _normalizeBits(
          entry.value,
          source.fields[entry.key].width,
        );
      }
      final packedValue = fieldValues.reversed.join();
      if (packedData.isEmpty || packedData.last.value != packedValue) {
        packedData.add(Data(time: time, value: packedValue));
      }
    }
    return WaveformData(signalId: signalId, data: packedData);
  }

  String _normalizeBits(String value, int width) {
    if (value.length == width) {
      return value;
    }
    if (value.length == 1 && (value == 'x' || value == 'z')) {
      return value * width;
    }
    if (value.length < width) {
      return value.padLeft(width, '0');
    }
    return value.substring(value.length - width);
  }

  /// Converts Rust SignalWaveformData to viewer's WaveformData.
  WaveformData _convertWaveformData(
    rust.SignalWaveformData rustData, {
    int? startTime,
    int? endTime,
  }) {
    // Convert rust-native timestamps to picoseconds using metadata
    final double timescaleToPs = _computeTimescaleToPsFromMetadata(
      _cachedStructure,
    );
    final data = rustData.data
        .map((dp) {
          final int tPs = (dp.time.toDouble() * timescaleToPs).round();
          return Data(time: tPs, value: dp.value);
        })
        .where(
          (data) =>
              (startTime == null || data.time >= startTime) &&
              (endTime == null || data.time <= endTime),
        )
        .toList();
    // Ensure data is sorted ascending by time
    data.sort((a, b) => a.time.compareTo(b.time));

    return WaveformData(signalId: rustData.signalId, data: data);
  }
}

class _WellenSignalSource {
  final List<_WellenSignalField> fields;

  const _WellenSignalSource(this.fields);
}

class _WellenSignalField {
  final String id;
  final int width;

  const _WellenSignalField(this.id, this.width);
}
