//! Copyright (C) 2026 Intel Corporation
//! SPDX-License-Identifier: BSD-3-Clause
//!
//! api.rs
//! API module for wellen bridge
//!
//! This module defines the public API that will be exposed to Dart via flutter_rust_bridge.
//!
//! 2026 January 03
//! Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use wellen::{
    FileFormat, Hierarchy, Signal, SignalRef, SignalSource, TimeTable, Timescale, TimescaleUnit,
    VarType,
};

/// Error type for wellen bridge operations
#[derive(Debug, thiserror::Error)]
pub enum WellenError {
    #[error("Failed to open file: {0}")]
    FileOpen(String),
    #[error("Failed to parse header: {0}")]
    HeaderParse(String),
    #[error("Failed to parse body: {0}")]
    BodyParse(String),
    #[error("Signal not found: {0}")]
    SignalNotFound(String),
    #[error("Signal not loaded: {0}")]
    SignalNotLoaded(String),
    #[error("Waveform not loaded")]
    WaveformNotLoaded,
    #[error("Internal error: {0}")]
    Internal(String),
}

/// Metadata about the waveform file
#[derive(Debug, Clone)]
pub struct WaveformMetadata {
    pub source: String,
    pub timescale: String,
    pub timescale_factor: u32,
    pub date: Option<String>,
    pub version: Option<String>,
    pub format: String,
    pub start_time: u64,
    pub end_time: u64,
}

/// Information about a scope (module) in the hierarchy
#[derive(Debug, Clone)]
pub struct ScopeInfo {
    pub id: u64,
    pub name: String,
    pub full_path: String,
    pub scope_type: String,
}

/// Information about a signal (variable) in the hierarchy
#[derive(Debug, Clone)]
pub struct SignalInfo {
    pub id: String,
    pub name: String,
    pub full_path: String,
    pub signal_type: String,
    pub bit_width: u32,
    pub scope_id: String,
}

/// A single data point in a waveform
#[derive(Debug, Clone)]
pub struct WaveformDataPoint {
    pub time: u64,
    pub value: String,
}

/// Waveform data for a signal
#[derive(Debug, Clone)]
pub struct SignalWaveformData {
    pub signal_id: String,
    pub data: Vec<WaveformDataPoint>,
}

/// Module structure with hierarchy
#[derive(Debug, Clone)]
pub struct ModuleNode {
    pub name: String,
    pub full_path: String,
    pub scope_type: String,
    /// Component (definition) name supplied by the wave format, e.g. the
    /// instantiated module type for VHDL/SV scopes or — for ROHD-emitted
    /// FST — the Dart `Module.definitionName`.  Empty string when the
    /// underlying format does not carry this information.
    pub component_name: String,
    pub signals: Vec<SignalInfo>,
    pub sub_modules: Vec<ModuleNode>,
}

/// Complete waveform structure
#[derive(Debug, Clone)]
pub struct WaveformStructure {
    pub metadata: WaveformMetadata,
    pub modules: Vec<ModuleNode>,
    pub all_signal_ids: Vec<String>,
}

/// Internal state for a loaded waveform
struct WaveformState {
    hierarchy: Arc<Hierarchy>,
    time_table: Arc<TimeTable>,
    source: Option<SignalSource>,
    signals: HashMap<SignalRef, Arc<Signal>>,
    signal_ref_map: HashMap<String, SignalRef>,
    format: FileFormat,
}

// Global waveform container (singleton for simplicity)
lazy_static::lazy_static! {
    static ref WAVEFORM_STATE: Mutex<Option<WaveformState>> = Mutex::new(None);
}

/// Create metadata from hierarchy and format
fn create_metadata(hierarchy: &Hierarchy, format: FileFormat, source: String, time_table: &TimeTable) -> WaveformMetadata {
    let timescale = hierarchy.timescale().unwrap_or(Timescale::new(1, TimescaleUnit::NanoSeconds));
    let start_time = time_table.first().copied().unwrap_or(0);
    let end_time = time_table.last().copied().unwrap_or(0);
    WaveformMetadata {
        source,
        timescale: format!("{}{}", timescale.factor, timescale_unit_to_string(timescale.unit)),
        timescale_factor: timescale.factor,
        date: None,
        version: Some(hierarchy.version().to_string()),
        format: format_to_string(format).to_string(),
        start_time,
        end_time,
    }
}

/// Convert wellen timescale unit to string
fn timescale_unit_to_string(unit: TimescaleUnit) -> &'static str {
    match unit {
        TimescaleUnit::ZeptoSeconds => "zs",
        TimescaleUnit::AttoSeconds => "as",
        TimescaleUnit::FemtoSeconds => "fs",
        TimescaleUnit::PicoSeconds => "ps",
        TimescaleUnit::NanoSeconds => "ns",
        TimescaleUnit::MicroSeconds => "us",
        TimescaleUnit::MilliSeconds => "ms",
        TimescaleUnit::Seconds => "s",
        TimescaleUnit::Unknown => "?",
    }
}

/// Convert wellen file format to string
fn format_to_string(format: FileFormat) -> &'static str {
    match format {
        FileFormat::Vcd => "VCD",
        FileFormat::Fst => "FST",
        FileFormat::Ghw => "GHW",
        FileFormat::Unknown => "Unknown",
    }
}

/// Convert wellen var type to string
fn var_type_to_string(var_type: VarType) -> &'static str {
    match var_type {
        VarType::Wire => "wire",
        VarType::Reg => "reg",
        VarType::Parameter => "parameter",
        VarType::Integer => "integer",
        VarType::Real => "real",
        VarType::Event => "event",
        VarType::Supply0 => "supply0",
        VarType::Supply1 => "supply1",
        VarType::Time => "time",
        VarType::Tri => "tri",
        VarType::TriAnd => "triand",
        VarType::TriOr => "trior",
        VarType::TriReg => "trireg",
        VarType::Tri0 => "tri0",
        VarType::Tri1 => "tri1",
        VarType::WAnd => "wand",
        VarType::WOr => "wor",
        VarType::Port => "port",
        VarType::Bit => "bit",
        VarType::Logic => "logic",
        VarType::Int => "int",
        VarType::ShortInt => "shortint",
        VarType::LongInt => "longint",
        VarType::Byte => "byte",
        VarType::ShortReal => "shortreal",
        VarType::RealTime => "realtime",
        VarType::Enum => "enum",
        VarType::SparseArray => "sparse_array",
        VarType::String => "string",
        _ => "unknown",
    }
}

/// Convert wellen scope type to string
fn scope_type_to_string(scope_type: wellen::ScopeType) -> &'static str {
    match scope_type {
        wellen::ScopeType::Module => "module",
        wellen::ScopeType::Task => "task",
        wellen::ScopeType::Function => "function",
        wellen::ScopeType::Begin => "begin",
        wellen::ScopeType::Fork => "fork",
        wellen::ScopeType::Generate => "generate",
        wellen::ScopeType::Struct => "struct",
        wellen::ScopeType::Union => "union",
        wellen::ScopeType::Class => "class",
        wellen::ScopeType::Interface => "interface",
        wellen::ScopeType::Package => "package",
        wellen::ScopeType::Program => "program",
        wellen::ScopeType::VhdlArchitecture => "architecture",
        wellen::ScopeType::VhdlProcedure => "procedure",
        wellen::ScopeType::VhdlFunction => "function",
        wellen::ScopeType::VhdlRecord => "record",
        wellen::ScopeType::VhdlProcess => "process",
        wellen::ScopeType::VhdlBlock => "block",
        wellen::ScopeType::VhdlForGenerate => "for_generate",
        wellen::ScopeType::VhdlIfGenerate => "if_generate",
        wellen::ScopeType::VhdlGenerate => "generate",
        wellen::ScopeType::VhdlPackage => "package",
        _ => "unknown",
    }
}

/// Load a waveform file (VCD, FST, or GHW) from a file path
///
/// This function parses both the header and body of the waveform file.
/// After calling this, use `get_waveform_structure` to get the hierarchy
/// and `get_waveform_data` to get signal values.
///
/// Note: This function is only available on native platforms (not WASM).
/// For web/WASM, use `load_waveform_from_bytes` instead.
#[flutter_rust_bridge::frb(sync)]
pub fn load_waveform(_file_path: String) -> Result<WaveformMetadata, String> {
    #[cfg(target_family = "wasm")]
    {
        Err("load_waveform is not available on WASM. Use load_waveform_from_bytes instead.".to_string())
    }
    
    #[cfg(not(target_family = "wasm"))]
    {
        load_waveform_native(_file_path)
    }
}

#[cfg(not(target_family = "wasm"))]
fn load_waveform_native(file_path: String) -> Result<WaveformMetadata, String> {
    use wellen::viewers::{read_body, read_header_from_file};
    use wellen::LoadOptions;
    #[cfg(debug_assertions)]
    eprintln!("[ROHD_DEBUG] load_waveform_native file_path={}", file_path);

    // Read header from file
    let options = LoadOptions::default();
    let header_result = read_header_from_file(&file_path, &options)
        .map_err(|e| format!("Failed to read header: {e}"))?;
    
    let hierarchy = Arc::new(header_result.hierarchy);
    let format = header_result.file_format;

    // Read body
    let body_result = read_body(header_result.body, &hierarchy, None)
        .map_err(|e| format!("Failed to read body: {e}"))?;

    let time_table = Arc::new(body_result.time_table);
    let source = Some(body_result.source);


    // Build signal_ref_map
    let signal_ref_map: HashMap<String, SignalRef> = hierarchy
        .iter_vars()
        .map(|var| (var.full_name(&hierarchy), var.signal_ref()))
        .collect();

    // Get metadata
    let metadata = create_metadata(&hierarchy, format, file_path, &time_table);

    #[cfg(debug_assertions)]
    {
        let sigs: Vec<String> = hierarchy
            .iter_vars()
            .map(|var| {
                let name = var.full_name(&hierarchy);
                let vtype = var_type_to_string(var.var_type());
                let width = var.length().unwrap_or(1);
                format!("{}:{}:{}", name, vtype, width)
            })
            .take(200)
            .collect();
        eprintln!("[ROHD_DEBUG] load_waveform_native signals (first={}): {}",
            sigs.len(), sigs.join(", "));
    }

    // Store state
    let state = WaveformState {
        hierarchy,
        time_table,
        source,
        signals: HashMap::new(),
        signal_ref_map,
        format,
    };

    *WAVEFORM_STATE.lock().unwrap() = Some(state);

    Ok(metadata)
}

/// Load a waveform from bytes (VCD, FST, or GHW)
///
/// This function parses both the header and body of the waveform from in-memory bytes.
/// This is useful for web/WASM environments where direct file access is not available.
/// After calling this, use `get_waveform_structure` to get the hierarchy
/// and `get_waveform_data` to get signal values.
///
/// # Arguments
/// * `bytes` - The waveform file contents as bytes
/// * `file_name` - Optional filename hint for format detection and metadata
#[flutter_rust_bridge::frb(sync)]
pub fn load_waveform_from_bytes(bytes: Vec<u8>, file_name: Option<String>) -> Result<WaveformMetadata, String> {
    use std::io::Cursor;
    use wellen::viewers::{read_body, read_header};
    use wellen::LoadOptions;

    // Read header from bytes
    let options = LoadOptions::default();
    let cursor = Cursor::new(bytes);
    let header_result = read_header(cursor, &options)
        .map_err(|e| format!("Failed to read header from bytes: {e}"))?;
    
    let hierarchy = Arc::new(header_result.hierarchy);
    let format = header_result.file_format;

    // Read body
    let body_result = read_body(header_result.body, &hierarchy, None)
        .map_err(|e| format!("Failed to read body: {e}"))?;

    let time_table = Arc::new(body_result.time_table);
    let source = Some(body_result.source);

    // Build signal_ref_map
    let signal_ref_map: HashMap<String, SignalRef> = hierarchy
        .iter_vars()
        .map(|var| (var.full_name(&hierarchy), var.signal_ref()))
        .collect();

    // Get metadata
    let source_name = file_name.unwrap_or_else(|| String::from("<bytes>"));
    let metadata = create_metadata(&hierarchy, format, source_name.clone(), &time_table);

    #[cfg(debug_assertions)]
    {
        eprintln!("[ROHD_DEBUG] load_waveform_from_bytes source_name={} vars={} times={} format={:?}",
            source_name,
            hierarchy.iter_vars().count(),
            time_table.len(),
            format
        );
        let sigs: Vec<String> = hierarchy
            .iter_vars()
            .map(|var| {
                let name = var.full_name(&hierarchy);
                let vtype = var_type_to_string(var.var_type());
                let width = var.length().unwrap_or(1);
                format!("{}:{}:{}", name, vtype, width)
            })
            .take(200)
            .collect();
        eprintln!("[ROHD_DEBUG] load_waveform_from_bytes signals (first={}): {}",
            sigs.len(), sigs.join(", "));
    }

    // Store state
    let state = WaveformState {
        hierarchy,
        time_table,
        source,
        signals: HashMap::new(),
        signal_ref_map,
        format,
    };

    *WAVEFORM_STATE.lock().unwrap() = Some(state);

    Ok(metadata)
}

/// Get the waveform structure (hierarchy of modules and signals)
///
/// This returns the complete hierarchy without waveform data.
#[flutter_rust_bridge::frb(sync)]
pub fn get_waveform_structure() -> Result<WaveformStructure, String> {
    let state_guard = WAVEFORM_STATE.lock().unwrap();
    let state = state_guard.as_ref().ok_or("Waveform not loaded")?;

    let h = &state.hierarchy;
    let metadata = create_metadata(h, state.format, String::new(), &state.time_table);

    // Build module tree
    fn build_module_node(
        h: &Hierarchy,
        scope_ref: wellen::ScopeRef,
        path_prefix: &str,
    ) -> ModuleNode {
        let scope = &h[scope_ref];
        let name = scope.name(h).to_string();
        let full_path = if path_prefix.is_empty() {
            name.clone()
        } else {
            format!("{}.{}", path_prefix, name)
        };

        // Get signals in this scope
        let signals: Vec<SignalInfo> = scope
            .vars(h)
            .map(|var_ref| {
                let var = &h[var_ref];
                let signal_name = var.name(h).to_string();
                let signal_full_path = format!("{}.{}", full_path, signal_name);
                SignalInfo {
                    id: signal_full_path.clone(),
                    name: signal_name,
                    full_path: signal_full_path,
                    signal_type: var_type_to_string(var.var_type()).to_string(),
                    bit_width: var.length().unwrap_or(1),
                    scope_id: full_path.clone(),
                }
            })
            .collect();

        // Get sub-modules
        let sub_modules: Vec<ModuleNode> = scope
            .scopes(h)
            .map(|child_ref| build_module_node(h, child_ref, &full_path))
            .collect();

        ModuleNode {
            name,
            full_path,
            scope_type: scope_type_to_string(scope.scope_type()).to_string(),
            component_name: scope.component(h).unwrap_or("").to_string(),
            signals,
            sub_modules,
        }
    }

    // Build modules from root scopes
    let modules: Vec<ModuleNode> = h
        .scopes()
        .map(|scope_ref| build_module_node(h, scope_ref, ""))
        .collect();

    // Collect all signal IDs
    let all_signal_ids: Vec<String> = h
        .iter_vars()
        .map(|var_ref| var_ref.full_name(h))
        .collect();

    Ok(WaveformStructure {
        metadata,
        modules,
        all_signal_ids,
    })
}

/// Load waveform data for specific signals
///
/// This loads the actual waveform values for the specified signal IDs.
/// Signal IDs are the full hierarchical paths (e.g., "top.counter.clk").
#[flutter_rust_bridge::frb(sync)]
pub fn get_waveform_data(
    signal_ids: Vec<String>,
    start_time: Option<u64>,
    end_time: Option<u64>,
) -> Result<Vec<SignalWaveformData>, String> {
    let mut state_guard = WAVEFORM_STATE.lock().unwrap();
    let state = state_guard.as_mut().ok_or("Waveform not loaded")?;

    let h = &state.hierarchy;
    let time_table = &state.time_table;

    // Load signals that haven't been loaded yet
    let mut signals_to_load: Vec<SignalRef> = Vec::new();
    for signal_id in &signal_ids {
        if let Some(&signal_ref) = state.signal_ref_map.get(signal_id) {
            if !state.signals.contains_key(&signal_ref) {
                signals_to_load.push(signal_ref);
            }
        }
    }

    // Load the signals
    if !signals_to_load.is_empty() {
        if let Some(mut source) = state.source.take() {
            let loaded = source.load_signals(&signals_to_load, h, true);
            for (signal_ref, signal) in loaded {
                state.signals.insert(signal_ref, Arc::new(signal));
            }
            state.source = Some(source);
        } else {
            return Err("Signal source not available".to_string());
        }
    }

    // Extract waveform data
    let mut result = Vec::new();
    for signal_id in signal_ids {
        let signal_ref = state
            .signal_ref_map
            .get(&signal_id)
            .ok_or_else(|| format!("Signal not found: {signal_id}"))?;

        let signal = state
            .signals
            .get(signal_ref)
            .ok_or_else(|| format!("Signal not loaded: {signal_id}"))?;

        let mut data_points: Vec<WaveformDataPoint> = Vec::new();

        // Iterate through signal changes
        for (time_idx, value) in signal.iter_changes() {
            if let Some(&time) = time_table.get(time_idx as usize) {
                // Apply time filters
                if let Some(start) = start_time {
                    if time < start {
                        continue;
                    }
                }
                if let Some(end) = end_time {
                    if time > end {
                        continue;
                    }
                }

                // Convert value to string
                let value_str = format_signal_value(&value);
                data_points.push(WaveformDataPoint {
                    time,
                    value: value_str,
                });
            }
        }

        result.push(SignalWaveformData {
            signal_id,
            data: data_points,
        });
    }

    Ok(result)
}


/// Format a signal value to a string
fn format_signal_value(value: &wellen::SignalValue) -> String {
    match value {
        wellen::SignalValue::Binary(bits, len) => {
            // Interpret `bits` as big-endian byte sequence. Build an MSB-first
            // bit string of length `len`.
            let mut s = String::new();
            let total_bits = bits.len() * 8;
            // If bits buffer contains more bits than `len`, assume the value is
            // right-aligned in the provided bytes (big-endian). Compute a start
            // offset so we read the most-significant `len` bits of the buffer.
            let start = total_bits.saturating_sub(*len as usize);
            for p in 0..(*len as usize) {
                let bit_pos = start + p;
                let byte_idx = bit_pos / 8;
                let bit_idx_in_byte = 7 - (bit_pos % 8);
                let bit = if byte_idx < bits.len() {
                    (bits[byte_idx] >> bit_idx_in_byte) & 0x01
                } else {
                    0
                };
                s.push(if bit == 0 { '0' } else { '1' });
            }

            if s.is_empty() {
                "0".to_string()
            } else {
                s
            }
        }
        wellen::SignalValue::FourValue(_, _) | wellen::SignalValue::NineValue(_, _) => {
            let s = value
                .to_bit_string()
                .expect("four- and nine-state values always have a bit-string representation");
            if s.is_empty() {
                "0".to_string()
            } else {
                s
            }
        }
        wellen::SignalValue::String(s) => s.to_string(),
        wellen::SignalValue::Real(r) => r.to_string(),
        wellen::SignalValue::Event => "event".to_string(),
    }
}

/// Get the maximum timestamp in the waveform
#[flutter_rust_bridge::frb(sync)]
pub fn get_max_timestamp() -> Result<Option<u64>, String> {
    let state_guard = WAVEFORM_STATE.lock().unwrap();
    let state = state_guard.as_ref().ok_or("Waveform not loaded")?;
    Ok(state.time_table.last().copied())
}

/// Get all timestamps in the waveform
#[flutter_rust_bridge::frb(sync)]
pub fn get_all_timestamps() -> Result<Vec<u64>, String> {
    let state_guard = WAVEFORM_STATE.lock().unwrap();
    let state = state_guard.as_ref().ok_or("Waveform not loaded")?;
    Ok(state.time_table.iter().copied().collect())
}

/// Check if a waveform is currently loaded
#[flutter_rust_bridge::frb(sync)]
pub fn is_waveform_loaded() -> bool {
    WAVEFORM_STATE.lock().unwrap().is_some()
}

/// Unload the current waveform and free resources
#[flutter_rust_bridge::frb(sync)]
pub fn unload_waveform() {
    *WAVEFORM_STATE.lock().unwrap() = None;
}

#[cfg(test)]
mod tests {
    use super::format_signal_value;
    use wellen::SignalValue;

    #[test]
    fn formats_four_state_values_in_wellen_packed_order() {
        let cases: &[(&[u8], u32, &str)] = &[
            (&[0b0001_1011], 4, "01xz"),
            (&[0b0000_0011, 0b0001_1011], 5, "z01xz"),
            (&[0b0000_1011, 0b0001_1110], 6, "xz01zx"),
            (&[0b0001_1011, 0b1110_0100], 8, "01xzzx10"),
        ];

        for &(data, width, expected) in cases {
            assert_eq!(
                format_signal_value(&SignalValue::FourValue(data, width)),
                expected,
                "width={width}"
            );
        }
        assert_eq!(format_signal_value(&SignalValue::FourValue(&[], 0)), "0");
    }

    #[test]
    fn formats_all_nine_state_symbols_in_wellen_packed_order() {
        let cases: &[(&[u8], u32, &str)] = &[
            (&[0x23], 2, "xz"),
            (&[0x04, 0x23], 3, "hxz"),
            (&[0x45, 0x67], 4, "huwl"),
            (&[0x00, 0x12, 0x34, 0x56, 0x78], 9, "01xzhuwl-"),
        ];

        for &(data, width, expected) in cases {
            assert_eq!(
                format_signal_value(&SignalValue::NineValue(data, width)),
                expected,
                "width={width}"
            );
        }
        assert_eq!(format_signal_value(&SignalValue::NineValue(&[], 0)), "0");
    }

    #[test]
    fn preserves_other_signal_value_output_conventions() {
        assert_eq!(
            format_signal_value(&SignalValue::Binary(&[0b0000_0101], 3)),
            "101"
        );
        assert_eq!(format_signal_value(&SignalValue::Real(1.25)), "1.25");
        assert_eq!(format_signal_value(&SignalValue::String("ready")), "ready");
        assert_eq!(format_signal_value(&SignalValue::Event), "event");
    }
}
