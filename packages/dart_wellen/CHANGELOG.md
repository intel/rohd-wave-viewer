# Changelog

## 0.1.1

- Support both 0.1.x and 0.2.x releases of the shared hierarchy and waveform packages without increasing the Dart SDK lower bound.
- Update the Flutter Rust Bridge runtime and generated bindings together to 2.7.1.
- Package the matching web runtime and license notices alongside generated Dart bindings. Add checksummed release bundles and a non-building installer for Git consumers, with bridge versions determined by this package.
- Automatically distribute immutable CI bundles for every pushed branch, with Git consumers selecting the exact resolved commit rather than a branch-specific or package-release URL.

## 0.1.0

- Initial public release of the Dart bindings for the Wellen waveform library.
- Pins Flutter Rust Bridge 2.7.0 to match the generated Dart and Rust bindings.
- Uses serialized bridge responses for Dart-to-Wasm compatibility.
