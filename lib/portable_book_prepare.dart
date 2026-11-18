import 'dart:io';

import 'package:flutter/services.dart';

/// Public-source stand-in for the private document converter.
/// TXT and EPUB import stay on the existing book pipeline.
typedef PreparedBookDocument = ({String name, String? path, String? error});

class PortableBookPreparer {
  PortableBookPreparer({
    required this.directory,
    required this.textCodecToken,
    required this.decodeNames,
    required this.convert,
    required this.extractKindle,
    this.extractPdf,
  });

  final Directory directory;
  final RootIsolateToken textCodecToken;
  final Future<List<String>> Function(List<String> names) decodeNames;
  final Future<List<PreparedBookDocument>> Function(String name, String path)
  convert;
  final Future<int> Function(String source, String output) extractKindle;
  final Future<void> Function(String name, String source, String output)?
  extractPdf;

  static Future<void> clearPreviousRuns(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  Future<void> releasePaths(Iterable<String> paths) async {}

  Future<List<PreparedBookDocument>> prepare(String name, String path) async {
    throw const FormatException('此版本不能转换该格式，请改用 TXT 或 EPUB');
  }
}
