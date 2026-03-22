import 'dart:typed_data';

/// A tiny tokenizer for plain text bytes.
///
/// It treats a "token" as a run of ASCII letters and/or digits.
/// Non-alphanumeric bytes are treated as token boundaries.
class TokenSpan {
  final String token;
  final int offset;

  TokenSpan(this.token, this.offset);
}

List<TokenSpan> tokenizeBytes(Uint8List bytes, {bool caseInsensitive = true}) {
  final results = <TokenSpan>[];
  final buffer = <int>[];
  int tokenStart = -1;

  void flushToken(int end) {
    if (buffer.isEmpty) return;
    var token = String.fromCharCodes(buffer);
    if (caseInsensitive) token = token.toLowerCase();
    results.add(TokenSpan(token, tokenStart));
    buffer.clear();
    tokenStart = -1;
  }

  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    final isAlphaNum =
        (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122);
    if (isAlphaNum) {
      if (tokenStart == -1) {
        tokenStart = i;
      }
      buffer.add(b);
    } else {
      flushToken(i);
    }
  }

  // flush at end.
  flushToken(bytes.length);
  return results;
}
