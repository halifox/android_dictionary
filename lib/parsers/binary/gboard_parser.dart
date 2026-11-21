import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../../models/ime_format.dart';
import '../../models/parse_result.dart';
import '../../generated/dictionary_api.g.dart';
import '../base/base_parser.dart';

/// Gboard 个人词库解析器
/// 格式：zip 内包含 dictionary.txt，UTF-8 编码（允许带 BOM）
/// 词条：shortcut \t word \t language_tag \t pos_tag
class GboardParser extends BaseParser {
  GboardParser() : super(ImeFormat.gboard);

  @override
  Future<ParseResult> parseFile(String filePath) async {
    final stopwatch = Stopwatch()..start();
    final entries = <TableEntryData>[];

    // 读取 ZIP 文件
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 查找 dictionary.txt 文件
    ArchiveFile? dictionaryFile;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (name == 'dictionary.txt' || name.endsWith('/dictionary.txt')) {
        dictionaryFile = entry;
        break;
      }
    }

    if (dictionaryFile == null) {
      throw Exception('ZIP 文件中未找到 dictionary.txt');
    }

    // dictionary.txt 为 UTF-8 文本，必须按 UTF-8 解码，否则中文会乱码
    final content = _decodeUtf8(dictionaryFile.content as List<int>);
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      // 兼容 CRLF 换行
      final line = lines[i].endsWith('\r')
          ? lines[i].substring(0, lines[i].length - 1)
          : lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      try {
        final parts = line.split('\t');
        if (parts.length < 2) continue;

        final pinyin = parts[0].trim();
        final word = parts[1];

        if (word.isEmpty) continue;

        entries.add(
          TableEntryData(
            word: word,
            shortcut: pinyin.isEmpty ? null : pinyin,
            frequency: 1,
            locale: 'zh_CN',
          ),
        );
      } catch (e) {
        print('Gboard解析词条失败 (行 $i): $e');
        continue;
      }
    }

    stopwatch.stop();
    return ParseResult(
      entries: entries,
      format: format,
      totalCount: entries.length,
      parseTime: stopwatch.elapsed,
    );
  }

  String _decodeUtf8(List<int> bytes) {
    // 跳过 UTF-8 BOM
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    final data = start == 0 ? bytes : bytes.sublist(start);

    try {
      return utf8.decode(data);
    } on FormatException {
      throw Exception('dictionary.txt 解码失败：文件不是有效的 UTF-8 编码');
    }
  }

  @override
  Future<bool> canParse(String filePath) async {
    return filePath.toLowerCase().endsWith('.zip');
  }
}
