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
  final List<String> matchedTerms;
  final List<SearchMatchRange> matchRanges;

  SearchResult({
    required this.path,
    required this.score,
    required this.snippet,
    required this.matchOffset,
    required this.matchedTerms,
    required this.matchRanges,
  });
}

class SearchMatchRange {
  final int start;
  final int end;
  final String term;

  SearchMatchRange({
    required this.start,
    required this.end,
    required this.term,
  });
}

class _SnippetMatchEvidence {
  final String snippet;
  final List<String> matchedTerms;
  final List<SearchMatchRange> matchRanges;

  const _SnippetMatchEvidence({
    required this.snippet,
    required this.matchedTerms,
    required this.matchRanges,
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
        int? earliestCharOffset;
        for (final term in terms) {
          final pos = lower.indexOf(term);
          if (pos >= 0 &&
              (earliestCharOffset == null || pos < earliestCharOffset)) {
            earliestCharOffset = pos;
          }
        }
        final matchOffset = earliestCharOffset == null
            ? 0
            : _charIndexToUtf8ByteOffset(text, earliestCharOffset);
        final snippetEvidence = _buildSnippetMatchEvidence(
          body,
          terms,
          matchOffset,
          contextWindowBytes,
        );
        results.add(
          SearchResult(
            path: record['path'] as String,
            score: score.toDouble(),
            snippet: snippetEvidence.snippet,
            matchOffset: matchOffset,
            matchedTerms: snippetEvidence.matchedTerms,
            matchRanges: snippetEvidence.matchRanges,
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

    final archiveHandle = await archiveFile.open();
    try {
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
          archiveHandle,
          doc,
          terms,
          matchOffset,
          contextWindowBytes: contextWindowBytes,
        );
        results.add(
          SearchResult(
            path: doc.path,
            score: score,
            snippet: snippet.snippet,
            matchOffset: matchOffset,
            matchedTerms: snippet.matchedTerms,
            matchRanges: snippet.matchRanges,
          ),
        );
      }
    } finally {
      await archiveHandle.close();
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

  Future<_SnippetMatchEvidence> _snippetForDoc(
    RandomAccessFile archiveHandle,
    DocumentInfo doc,
    List<String> terms,
    int? centerOffset, {
    int contextWindowBytes = 1200,
  }) async {
    await archiveHandle.setPosition(doc.bodyOffset);
    final bodyBytes = await archiveHandle.read(doc.bodyLength);
    return _buildSnippetMatchEvidence(
      bodyBytes,
      terms,
      centerOffset ?? 0,
      contextWindowBytes,
    );
  }

  _SnippetMatchEvidence _buildSnippetMatchEvidence(
    Uint8List body,
    List<String> terms,
    int centerOffset,
    int contextWindowBytes,
  ) {
    final snippet = _extractContextWindow(
      body,
      centerOffset,
      padding: contextWindowBytes,
    );
    final matchRanges = _collectMatchRanges(snippet, terms);
    final matchedTerms = matchRanges
        .map((range) => range.term)
        .toSet()
        .toList(growable: false);
    return _SnippetMatchEvidence(
      snippet: snippet,
      matchedTerms: matchedTerms,
      matchRanges: matchRanges,
    );
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
    var foundStartBoundary = false;
    while (start > 0) {
      // Prefer paragraph boundaries first.
      if (start >= 2 && body[start - 2] == 10 && body[start - 1] == 10) {
        foundStartBoundary = true;
        break;
      }
      // Prefer line boundaries.
      if (body[start - 1] == 10) {
        foundStartBoundary = true;
        break;
      }
      // Prefer sentence boundaries so that we return a complete thought.
      if (body[start - 1] == 46 ||
          body[start - 1] == 33 ||
          body[start - 1] == 63) {
        // '.', '!', '?'
        foundStartBoundary = true;
        break;
      }
      start--;
    }

    // If no boundary exists behind the start candidate, find one ahead of it
    // but still before the match so snippets stay centered on relevant text.
    if (!foundStartBoundary) {
      var forward = startCandidate;
      final forwardLimit = matchOffset.clamp(0, len);
      while (forward < forwardLimit) {
        if (forward + 1 < len && body[forward] == 10 && body[forward + 1] == 10) {
          start = forward + 2;
          foundStartBoundary = true;
          break;
        }
        if (body[forward] == 10) {
          start = forward + 1;
          foundStartBoundary = true;
          break;
        }
        if (body[forward] == 46 || body[forward] == 33 || body[forward] == 63) {
          start = forward + 1;
          while (start < len && _isWhitespace(body[start])) {
            start++;
          }
          foundStartBoundary = true;
          break;
        }
        forward++;
      }
    }

    // If we didn't find a good boundary, avoid cutting mid-word.
    if (!foundStartBoundary && start > 0 && start < len) {
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

  List<SearchMatchRange> _collectMatchRanges(String text, List<String> terms) {
    final ranges = <SearchMatchRange>[];
    for (final term in terms) {
      final regex = RegExp(RegExp.escape(term), caseSensitive: false);
      final matches = regex.allMatches(text);
      for (final match in matches) {
        ranges.add(
          SearchMatchRange(start: match.start, end: match.end, term: term),
        );
      }
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  int _charIndexToUtf8ByteOffset(String text, int charIndex) {
    if (charIndex <= 0) {
      return 0;
    }
    if (charIndex >= text.length) {
      return utf8.encode(text).length;
    }
    return utf8.encode(text.substring(0, charIndex)).length;
  }

  bool _isWhitespace(int byte) {
    return byte == 9 || byte == 10 || byte == 13 || byte == 32;
  }
}
