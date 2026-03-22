import 'dart:convert';
import 'dart:io';

import 'package:lynsok_core/lynsok_runner.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main(List<String> args) async {
  final config = await LynSokConfig.load();
  final port = config.restPort;

  final lynPath = config.lynPath ?? _argValue(args, '--lyn');
  if (lynPath == null) {
    stderr.writeln('Error: missing lyn path. Provide via config or --lyn');
    exit(2);
  }

  final archiveFile = File(lynPath);
  if (!archiveFile.existsSync()) {
    stderr.writeln('Error: LYN file not found: $lynPath');
    exit(2);
  }

  final indexPath =
      config.indexPath ?? _argValue(args, '--index') ?? '$lynPath.idx';
  final indexFile = File(indexPath);

  final searcher = LynSokSearcher(
    archiveFile: archiveFile,
    indexPath: indexPath,
  );
  if (indexFile.existsSync()) {
    await searcher.loadIndex();
  }

  final router = Router()
    ..get('/health', (Request request) => Response.ok('ok'))
    ..get('/search', (Request request) async {
      final query =
          request.url.queryParameters['q'] ??
          request.url.queryParameters['query'];
      if (query == null || query.trim().isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'missing query parameter'}),
        );
      }

      final maxResults =
          int.tryParse(request.url.queryParameters['max_results'] ?? '10') ??
          10;
      final contextWindow =
          int.tryParse(
            request.url.queryParameters['context_window'] ?? '1200',
          ) ??
          1200;

      final results = await searcher.indexedSearch(
        query,
        maxResults: maxResults,
        contextWindowBytes: contextWindow,
      );

      final payload = {
        'query': query,
        'results': results
            .map(
              (r) => {'path': r.path, 'score': r.score, 'snippet': r.snippet},
            )
            .toList(),
      };

      return Response.ok(
        jsonEncode(payload),
        headers: {'content-type': 'application/json'},
      );
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Server listening on http://localhost:${server.port}');
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index != -1 && index + 1 < args.length) {
    return args[index + 1];
  }
  return null;
}
