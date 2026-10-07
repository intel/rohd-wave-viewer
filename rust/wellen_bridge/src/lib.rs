//! Copyright (C) 2026 Intel Corporation
//! SPDX-License-Identifier: BSD-3-Clause
//!
//! lib.rs
//! Wellen Bridge - Rust-Dart FFI bridge for wellen waveform library
//!
//! This crate provides a Flutter-compatible API to parse and read waveform files
//! (VCD, FST, GHW) using the wellen library.
//!
//! 2026 January 03
//! Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

mod api;
mod frb_generated;

pub use api::*;
