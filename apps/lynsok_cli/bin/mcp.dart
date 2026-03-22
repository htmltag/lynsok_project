import 'dart:convert';
import 'dart:io';

import 'package:lynsok_core/lynsok_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// MCP server for LynSok.
///
/// Uses mcp_dart to provide an MCP-compliant stdin/stdout JSON-RPC transport.
Future<void> main(List<String> args) async {
  final config = await LynSokConfig.load();
  final lynPath = config.lynPath ?? _argValue(args, '--lyn');
  final indexPath = config.indexPath ?? _argValue(args, '--index');

  if (lynPath == null) {
    stderr.writeln('Error: --lyn must be provided via CLI or config.');
    exit(2);
  }

  final archiveFile = File(lynPath);
  if (!archiveFile.existsSync()) {
    stderr.writeln('Error: LYN file not found: $lynPath');
    exit(2);
  }

  final indexPathStr = indexPath ?? '$lynPath.idx';
  final indexFile = File(indexPathStr);
  final searcher = LynSokSearcher(
    archiveFile: archiveFile,
    indexPath: indexPathStr,
  );
  if (indexFile.existsSync()) {
    await searcher.loadIndex();
  }

  final server = McpServer(
    const Implementation(name: 'lynsok', version: '0.1.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      instructions: 'Search a LynSok archive and return ranked snippets.',
    ),
  );

  server.registerTool(
    'lynsok.search',
    description: 'Search the LynSok archive and return ranked snippets as JSON',
    inputSchema: JsonSchema.object(
      properties: {
        'query': JsonSchema.string(description: 'Search query'),
        'max_results': JsonSchema.integer(
          minimum: 1,
          maximum: 200,
          defaultValue: 10,
          description: 'Maximum number of results to return',
        ),
        'context_window': JsonSchema.integer(
          minimum: 128,
          maximum: 32768,
          defaultValue: 1200,
          description:
              'How much context (in bytes) to return around each match',
        ),
      },
      required: const ['query'],
    ),
    callback: (args, extra) async {
      final query = (args['query'] ?? '').toString().trim();
      if (query.isEmpty) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(text: jsonEncode({'error': 'query is required'})),
          ],
        );
      }

      final maxResults = _asInt(args['max_results'], 10);
      final contextBytes = _asInt(args['context_window'], 1200);

      final results = await searcher.indexedSearch(
        query,
        maxResults: maxResults,
        contextWindowBytes: contextBytes,
      );

      final payload = {
        'results': results
            .map(
              (r) => {'path': r.path, 'score': r.score, 'snippet': r.snippet},
            )
            .toList(),
      };

      // Portable result: a single text content block containing JSON.
      return CallToolResult.fromContent([
        TextContent(text: jsonEncode(payload)),
      ]);
    },
  );

  // Start stdio transport (handshake + framing handled by SDK).
  await server.connect(StdioServerTransport());
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index != -1 && index + 1 < args.length) {
    return args[index + 1];
  }
  return null;
}

int _asInt(Object? v, int fallback) {
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}
