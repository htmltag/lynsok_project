import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_mupdf_donut/dart_mupdf.dart';

class _PdfIsolateRequest {
  final SendPort sendPort;
  final TransferableTypedData data;
  final int maxPages;

  _PdfIsolateRequest(this.sendPort, this.data, this.maxPages);
}

/// Uses a dedicated PDF parser to extract text with Unicode mapping.
/// Returns an empty list when parsing fails so callers can apply fallback logic.
Uint8List extractPdfTextWithLibrary(Uint8List pdfBytes) {
  return _extractPdfTextSync(pdfBytes, maxPages: 400);
}

Future<Uint8List> extractPdfTextWithLibraryWithTimeout(
  Uint8List pdfBytes, {
  Duration timeout = const Duration(seconds: 15),
  int maxPages = 400,
}) async {
  final responsePort = ReceivePort();
  Isolate? isolate;

  try {
    isolate = await Isolate.spawn<_PdfIsolateRequest>(
      _pdfExtractIsolateEntry,
      _PdfIsolateRequest(
        responsePort.sendPort,
        TransferableTypedData.fromList([pdfBytes]),
        maxPages,
      ),
      errorsAreFatal: true,
    );

    final dynamic message = await responsePort.first.timeout(timeout);
    if (message is TransferableTypedData) {
      return message.materialize().asUint8List();
    }

    return Uint8List(0);
  } on TimeoutException {
    return Uint8List(0);
  } catch (_) {
    return Uint8List(0);
  } finally {
    responsePort.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}

void _pdfExtractIsolateEntry(_PdfIsolateRequest request) {
  try {
    final bytes = request.data.materialize().asUint8List();
    final extracted = _extractPdfTextSync(bytes, maxPages: request.maxPages);
    Isolate.exit(request.sendPort, TransferableTypedData.fromList([extracted]));
  } catch (_) {
    Isolate.exit(
      request.sendPort,
      TransferableTypedData.fromList([Uint8List(0)]),
    );
  }
}

Uint8List _extractPdfTextSync(Uint8List pdfBytes, {required int maxPages}) {
  dynamic document;
  try {
    document = DartMuPDF.openBytes(pdfBytes);
    final int pageCount = document.pageCount as int;
    final int pagesToExtract = pageCount < maxPages ? pageCount : maxPages;
    final buffer = StringBuffer();

    for (int i = 0; i < pagesToExtract; i++) {
      try {
        final page = document.getPage(i);
        final String text = (page.getText() as String?)?.trim() ?? '';
        if (text.isNotEmpty) {
          buffer.writeln(text);
        }
      } catch (_) {
        // Keep extracting other pages when one page is malformed.
      }
    }

    final normalized = _normalizeExtractedText(buffer.toString());
    if (normalized.isEmpty) {
      return Uint8List(0);
    }

    return Uint8List.fromList(utf8.encode(normalized));
  } catch (_) {
    return Uint8List(0);
  } finally {
    try {
      document?.close();
    } catch (_) {
      // noop
    }
  }
}

String _normalizeExtractedText(String input) {
  final noCtl = input.replaceAll(
    RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
    ' ',
  );
  return noCtl.replaceAll(RegExp(r'\s+'), ' ').trim();
}
