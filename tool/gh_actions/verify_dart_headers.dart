// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// verify_dart_headers.dart
// Verifies repository copyright headers in authored and generated Dart files.
//
// 2026 October 01
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

final _copyrightPattern = RegExp(
  r'^// Copyright \(C\) (\d{4})(?:-(\d{4}))? Intel Corporation$',
);
final _datePattern = RegExp(r'^// \d{4} [A-Za-z]+(?: \d{1,2})?$');
final _authorPattern = RegExp(r'^// Author(?:\(s\))?: .+$');
final _authorContinuationPattern = RegExp(r'^//\s{2,}\S.+$');

Future<void> main() async {
  final gitResult = await Process.run('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    '*.dart',
  ]);

  if (gitResult.exitCode != 0) {
    stderr.write(gitResult.stderr);
    exitCode = gitResult.exitCode;
    return;
  }

  final pathSet = const LineSplitter()
      .convert(gitResult.stdout as String)
      .where((path) => path.isNotEmpty)
      .toSet();
  final generatedDirectory = Directory(
    'packages/dart_wellen/lib/src/rust',
  );
  if (generatedDirectory.existsSync()) {
    for (final entry in generatedDirectory.listSync()) {
      if (entry is File && entry.path.endsWith('.dart')) {
        pathSet.add(entry.path);
      }
    }
  }
  final paths = pathSet.toList()..sort();

  final errors = <String>[];
  var generatedCount = 0;
  var authoredCount = 0;

  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final lines = file.readAsLinesSync();
    final generated = lines.take(12).any(
          (line) =>
              line.contains('automatically generated') ||
              line.contains('@generated') ||
              line.contains('GENERATED CODE'),
        );

    if (generated) {
      generatedCount++;
      _validateGeneratedHeader(path, lines, errors);
    } else {
      authoredCount++;
      _validateAuthoredHeader(path, lines, errors);
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Dart header verification failed:');
    for (final error in errors) {
      stderr.writeln('  - $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Verified full headers in $authoredCount authored Dart files and '
    'copyright preambles in $generatedCount generated Dart files.',
  );
}

void _validateGeneratedHeader(
  String path,
  List<String> lines,
  List<String> errors,
) {
  final header = lines.take(12).toList();
  final copyrightIndex = header.indexWhere(_copyrightPattern.hasMatch);
  if (copyrightIndex < 0) {
    errors.add('$path: generated file is missing a copyright preamble');
    return;
  }

  if (copyrightIndex + 1 >= header.length ||
      header[copyrightIndex + 1] !=
          '// SPDX-License-Identifier: BSD-3-Clause') {
    errors.add('$path: generated copyright is not followed by the SPDX line');
  }

  _validateCopyrightYears(path, header[copyrightIndex], errors);
}

void _validateAuthoredHeader(
  String path,
  List<String> lines,
  List<String> errors,
) {
  if (lines.length < 9) {
    errors.add('$path: file is too short to contain the full header');
    return;
  }

  if (!_copyrightPattern.hasMatch(lines[0])) {
    errors.add('$path: line 1 is not the repository copyright line');
  } else {
    _validateCopyrightYears(path, lines[0], errors);
  }

  if (lines[1] != '// SPDX-License-Identifier: BSD-3-Clause') {
    errors.add('$path: line 2 is not the BSD-3-Clause SPDX identifier');
  }
  if (lines[2] != '//') {
    errors.add('$path: line 3 must be the header separator');
  }

  final fileName = path.replaceAll(r'\', '/').split('/').last;
  if (lines[3] != '// $fileName') {
    errors.add('$path: line 4 must identify the file as "$fileName"');
  }
  if (!lines[4].startsWith('// ') || lines[4].length <= 3) {
    errors.add('$path: line 5 must describe the file');
  }

  final headerLimit = lines.length < 40 ? lines.length : 40;
  final authorIndex = _indexWhere(
    lines,
    _authorPattern.hasMatch,
    start: 5,
    end: headerLimit,
  );
  if (authorIndex < 0) {
    errors.add('$path: header is missing an author line');
    return;
  }

  final dateIndex = _indexWhere(
    lines,
    _datePattern.hasMatch,
    start: 5,
    end: authorIndex,
  );
  if (dateIndex < 0) {
    errors.add('$path: header is missing a creation date');
  } else if (dateIndex == 0 || lines[dateIndex - 1] != '//') {
    errors.add('$path: creation date must follow a comment separator');
  }

  var headerEnd = authorIndex + 1;
  while (headerEnd < lines.length &&
      _authorContinuationPattern.hasMatch(lines[headerEnd])) {
    headerEnd++;
  }
  if (headerEnd >= lines.length || lines[headerEnd].isNotEmpty) {
    errors.add('$path: header must end with a blank line after its authors');
  }
}

void _validateCopyrightYears(
  String path,
  String copyright,
  List<String> errors,
) {
  final match = _copyrightPattern.firstMatch(copyright);
  if (match == null) {
    return;
  }

  final firstYear = int.parse(match.group(1)!);
  final lastYear = int.parse(match.group(2) ?? match.group(1)!);
  final currentYear = DateTime.now().year;
  if (lastYear < firstYear ||
      firstYear > currentYear ||
      lastYear > currentYear) {
    errors.add('$path: copyright year range is invalid');
  }
}

int _indexWhere(
  List<String> lines,
  bool Function(String line) predicate, {
  required int start,
  required int end,
}) {
  for (var index = start; index < end; index++) {
    if (predicate(lines[index])) {
      return index;
    }
  }
  return -1;
}
