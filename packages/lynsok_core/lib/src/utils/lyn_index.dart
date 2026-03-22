import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tokenizer.dart';

/// A single posting in the inverted index.
///
/// The `firstOffset` is the byte offset relative to the start of the record body
/// where the first occurrence of the token was found. This can be used to
/// extract a snippet around the match.
class Posting {
  final int docId;
  int tf;
  final List<int> offsets;

  Posting(this.docId, {required this.tf, required this.offsets});

  Map<String, dynamic> toJson() => {
    'docId': docId,
    'tf': tf,
    'offsets': offsets,
  };

  factory Posting.fromJson(Map<String, dynamic> json) => Posting(
    json['docId'] as int,
    tf: json['tf'] as int,
    offsets: (json['offsets'] as List<dynamic>).cast<int>().toList(
      growable: false,
    ),
  );
}

class DocumentInfo {
  final int docId;
  final String path;
  final int bodyOffset;
  final int bodyLength;
  final int tokenCount;

  DocumentInfo({
    required this.docId,
    required this.path,
    required this.bodyOffset,
    required this.bodyLength,
    required this.tokenCount,
  });

  Map<String, dynamic> toJson() => {
    'docId': docId,
    'path': path,
    'bodyOffset': bodyOffset,
    'bodyLength': bodyLength,
    'tokenCount': tokenCount,
  };

  factory DocumentInfo.fromJson(Map<String, dynamic> json) => DocumentInfo(
    docId: json['docId'] as int,
    path: json['path'] as String,
    bodyOffset: json['bodyOffset'] as int,
    bodyLength: json['bodyLength'] as int,
    tokenCount: json['tokenCount'] as int,
  );
}

/// A simple inverted index built from a `.lyn` archive.
///
/// This is intentionally a simple JSON-friendly structure for a first iteration.
class LynIndex {
  final List<DocumentInfo> docs = [];
  final Map<String, List<Posting>> inverted = {};
  int totalTokenCount = 0;

  /// Add a document by providing its extracted text bytes (already normalized).
  void addDocument({
    required String path,
    required int bodyOffset,
    required int bodyLength,
    required Uint8List bodyBytes,
  }) {
    final docId = docs.length;
    final tokens = tokenizeBytes(bodyBytes, caseInsensitive: true);
    final tokenCount = tokens.length;

    docs.add(
      DocumentInfo(
        docId: docId,
        path: path,
        bodyOffset: bodyOffset,
        bodyLength: bodyLength,
        tokenCount: tokenCount,
      ),
    );

    totalTokenCount += tokenCount;

    final termSeen = <String, Posting>{};
    for (final span in tokens) {
      final token = span.token;
      final offset = span.offset;
      final posting = termSeen[token];
      if (posting == null) {
        termSeen[token] = Posting(docId, tf: 1, offsets: [offset]);
      } else {
        posting.tf += 1;
        if (posting.offsets.length < 128) {
          posting.offsets.add(offset);
        }
      }
    }

    for (final entry in termSeen.entries) {
      final token = entry.key;
      final posting = entry.value;
      inverted.putIfAbsent(token, () => []).add(posting);
    }
  }

  double get avgDocLength {
    if (docs.isEmpty) return 0.0;
    return docs.map((d) => d.tokenCount).reduce((a, b) => a + b) / docs.length;
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'docs': docs.map((d) => d.toJson()).toList(),
      'totalTokenCount': totalTokenCount,
      'inverted': inverted.map(
        (token, postings) =>
            MapEntry(token, postings.map((p) => p.toJson()).toList()),
      ),
    };
  }

  Future<void> saveTo(File file) async {
    final jsonStr = jsonEncode(toJson());
    await file.writeAsString(jsonStr, flush: true);
  }

  static Future<LynIndex> loadFrom(File file) async {
    final jsonStr = await file.readAsString();
    final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;

    final idx = LynIndex();
    final docsJson = (jsonMap['docs'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final docJson in docsJson) {
      idx.docs.add(DocumentInfo.fromJson(docJson));
    }
    idx.totalTokenCount = jsonMap['totalTokenCount'] as int? ?? 0;

    final invertedJson = (jsonMap['inverted'] as Map<String, dynamic>);
    for (final token in invertedJson.keys) {
      final postingsJson = (invertedJson[token] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      idx.inverted[token] = postingsJson
          .map((p) => Posting.fromJson(p))
          .toList();
    }

    return idx;
  }
}
