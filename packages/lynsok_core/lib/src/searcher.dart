import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'utils/lyn_index.dart';
import 'utils/lyn_reader.dart';
import 'utils/tokenizer.dart';

class SearchResult {
  final String path;
  final double score;
  final String snippet;
  final int matchOffset;

  SearchResult({
    required this.path,
    required this.score,
    required this.snippet,
    required this.matchOffset,
  });
}

class _TermOffset {
  final int offset;
  final int termIndex;

  _TermOffset(this.offset, this.termIndex);
}

class LynSokSearcher {
  final File archiveFile;
  final File? indexFile;
  LynIndex? _index;

  LynSokSearcher({
    required this.archiveFile,
    File? indexFile,
    required String indexPath,
  }) : indexFile = indexFile ?? File(indexPath);

  /// Loads an index from disk (if provided). If no index is provided, searches must be done via [rawSearch].
  Future<void> loadIndex() async {
    if (indexFile == null) return;
    _index = await LynIndex.loadFrom(indexFile!);
  }

  /// Raw scan search: reads the entire archive and looks for matches.
  /// This is slower but works even without an index.
  Future<List<SearchResult>> rawSearch(
    String query, {
    int maxResults = 10,
    int contextWindowBytes = 1200,
  }) async {
    final terms = _tokenizeQuery(query);
    if (terms.isEmpty) return [];

    final records = await parseLyn(archiveFile);
    final results = <SearchResult>[];
    for (final record in records) {
      final body = record['body'] as Uint8List;
      final text = utf8.decode(body, allowMalformed: true);
      final lower = text.toLowerCase();
      int score = 0;
      for (final term in terms) {
        score += RegExp(RegExp.escape(term)).allMatches(lower).length;
      }
      if (score > 0) {
        // Find the first match offset so the snippet is centered on an actual hit.
        int matchOffset = 0;
        for (final term in terms) {
          final pos = lower.indexOf(term);
          if (pos >= 0 && (matchOffset == 0 || pos < matchOffset)) {
            matchOffset = pos;
          }
        }
        final snippet = _highlightTerms(
          _extractContextWindow(body, matchOffset, padding: contextWindowBytes),
          terms,
        );
        results.add(
          SearchResult(
            path: record['path'] as String,
            score: score.toDouble(),
            snippet: snippet,
            matchOffset: matchOffset,
          ),
        );
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(maxResults).toList();
  }

  /// Indexed search (fast) using the sidecar index.
  /// Requires [loadIndex] to be called first.
  Future<List<SearchResult>> indexedSearch(
    String query, {
    int maxResults = 10,
    bool useBm25 = true,
    double k1 = 1.2,
    double b = 0.75,
    double proximityWeight = 0.3,
    int contextWindowBytes = 1200,
  }) async {
    final index = _index;
    if (index == null) {
      throw StateError('Index not loaded. Call loadIndex() first');
    }

    final terms = _tokenizeQuery(query);
    if (terms.isEmpty) return [];

    // Collect document scores by term according to BM25 or TF-IDF.
    // Also collect per-doc per-term offsets for proximity scoring.
    final docScores = <int, double>{};
    final docOffsets = <int, List<_TermOffset>>{};

    final totalDocs = index.docs.length;
    final avgDocLen = index.avgDocLength;

    for (var termIndex = 0; termIndex < terms.length; termIndex++) {
      final term = terms[termIndex];
      final postings = index.inverted[term];
      if (postings == null) continue;
      final df = postings.length;
      final idf = df == 0 ? 0.0 : log(1 + (totalDocs - df + 0.5) / (df + 0.5));

      for (final p in postings) {
        final doc = index.docs[p.docId];
        final docLen = doc.tokenCount.toDouble();
        final tf = p.tf.toDouble();

        final score = useBm25
            ? _bm25Score(tf, idf, docLen, avgDocLen, k1, b)
            : _tfIdfScore(tf, idf, docLen);

        docScores[p.docId] = (docScores[p.docId] ?? 0) + score;

        // Collect offsets to compute proximity between query terms.
        final list = docOffsets.putIfAbsent(p.docId, () => []);
        for (final offset in p.offsets) {
          list.add(_TermOffset(offset, termIndex));
        }
      }
    }

    // Compute best term proximity for each document.
    final docProximity = <int, double>{};
    final docCenterOffset = <int, int>{};
    for (final entry in docOffsets.entries) {
      final docId = entry.key;
      final offsets = entry.value;
      if (offsets.length < 2) continue;
      offsets.sort((a, b) => a.offset.compareTo(b.offset));

      double bestDist = double.infinity;
      int bestCenter = 0;
      for (var i = 1; i < offsets.length; i++) {
        if (offsets[i].termIndex != offsets[i - 1].termIndex) {
          final dist = (offsets[i].offset - offsets[i - 1].offset).abs();
          if (dist < bestDist) {
            bestDist = dist.toDouble();
            bestCenter = ((offsets[i].offset + offsets[i - 1].offset) / 2)
                .round();
          }
        }
      }

      if (bestDist.isFinite) {
        docProximity[docId] = bestDist;
        docCenterOffset[docId] = bestCenter;
      }
    }

    final sorted = docScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final results = <SearchResult>[];

    for (final entry in sorted.take(maxResults)) {
      final docId = entry.key;
      var score = entry.value;
      final doc = index.docs[docId];

      final distance = docProximity[docId] ?? double.infinity;
      final proximity = distance.isFinite ? 1 / (1 + log(1 + distance)) : 0.0;
      score = score * (1 + proximityWeight * proximity);

      // Center snippet around the best-known term location.
      // Fall back to the first known offset if we couldn't compute proximity.
      final matchOffset =
          docCenterOffset[docId] ?? (docOffsets[docId]?.first.offset ?? 0);
      final snippet = await _snippetForDoc(
        doc,
        terms,
        matchOffset,
        contextWindowBytes: contextWindowBytes,
      );
      results.add(
        SearchResult(
          path: doc.path,
          score: score,
          snippet: snippet,
          matchOffset: matchOffset,
        ),
      );
    }

    return results;
  }

  double _tfIdfScore(double tf, double idf, double docLen) {
    return tf * idf / (docLen == 0 ? 1 : docLen);
  }

  double _bm25Score(
    double tf,
    double idf,
    double docLen,
    double avgDocLen,
    double k1,
    double b,
  ) {
    final denom =
        tf + k1 * (1 - b + b * (docLen / (avgDocLen == 0 ? 1 : avgDocLen)));
    return idf * ((tf * (k1 + 1)) / (denom == 0 ? 1 : denom));
  }

  List<String> _tokenizeQuery(String query) {
    final bytes = utf8.encode(query);
    final tokens = tokenizeBytes(
      Uint8List.fromList(bytes),
      caseInsensitive: true,
    );
    return tokens.map((t) => t.token).toList();
  }

  Future<String> _snippetForDoc(
    DocumentInfo doc,
    List<String> terms,
    int? centerOffset, {
    int contextWindowBytes = 1200,
  }) async {
    final raf = await archiveFile.open();
    try {
      await raf.setPosition(doc.bodyOffset);
      final bodyBytes = await raf.read(doc.bodyLength);
      final snippet = _extractContextWindow(
        bodyBytes,
        centerOffset ?? 0,
        padding: contextWindowBytes,
      );
      return _highlightTerms(snippet, terms);
    } finally {
      await raf.close();
    }
  }

  /// Extracts a "smart" context window around [matchOffset] from [body].
  ///
  /// The goal is to return a complete thought (sentence/paragraph) rather than
  /// a hard byte slice that may cut words in half.
  String _extractContextWindow(
    Uint8List body,
    int matchOffset, {
    int padding = 1200,
  }) {
    final len = body.length;
    final startCandidate = (matchOffset - padding).clamp(0, len);
    final endCandidate = (matchOffset + padding).clamp(0, len);

    int start = startCandidate;
    while (start > 0) {
      // Prefer paragraph boundaries first.
      if (start >= 2 && body[start - 2] == 10 && body[start - 1] == 10) {
        break;
      }
      // Prefer line boundaries.
      if (body[start - 1] == 10) {
        break;
      }
      // Prefer sentence boundaries so that we return a complete thought.
      if (body[start - 1] == 46 ||
          body[start - 1] == 33 ||
          body[start - 1] == 63) {
        // '.', '!', '?'
        break;
      }
      start--;
    }

    // If we didn't find a good boundary, avoid cutting mid-word.
    if (start == startCandidate && start > 0 && start < len) {
      while (start < len && !_isWhitespace(body[start])) {
        start++;
      }
    }

    int end = endCandidate;
    while (end < len) {
      if (end + 1 < len && body[end] == 10 && body[end + 1] == 10) {
        end += 2;
        break;
      }
      if (body[end] == 10) {
        end++;
        break;
      }
      if (body[end] == 46 || body[end] == 33 || body[end] == 63) {
        end++;
        break;
      }
      end++;
    }

    // If we didn't wrap at a boundary, avoid ending mid-word.
    if (end == endCandidate && end < len && !_isWhitespace(body[end - 1])) {
      while (end < len && !_isWhitespace(body[end])) {
        end++;
      }
    }

    final slice = body.sublist(start, end.clamp(0, len));
    return utf8.decode(slice, allowMalformed: true).trim();
  }

  String _highlightTerms(String text, List<String> terms) {
    var snippet = text;
    for (final term in terms) {
      final regex = RegExp(RegExp.escape(term), caseSensitive: false);
      snippet = snippet.replaceAllMapped(
        regex,
        (m) => '\x1b[33m${m[0]}\x1b[0m',
      );
    }
    return snippet;
  }

  bool _isWhitespace(int byte) {
    return byte == 9 || byte == 10 || byte == 13 || byte == 32;
  }
}
