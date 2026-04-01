import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:lynsok_core/lynsok_runner.dart';

class ServerRuntimeInfo {
  final bool isRunning;
  final int? runtimeId;
  final int? port;

  const ServerRuntimeInfo({
    required this.isRunning,
    required this.runtimeId,
    required this.port,
  });
}

class _IsolateServerHandle {
  final String serverId;
  final String serverType;
  final ReceivePort receivePort;
  final Isolate isolate;
  final Completer<void> readyCompleter = Completer<void>();

  StreamSubscription? subscription;
  SendPort? commandPort;
  int? runtimeId;
  int? port;
  bool isRunning = false;

  _IsolateServerHandle({
    required this.serverId,
    required this.serverType,
    required this.receivePort,
    required this.isolate,
  });

  Future<void> waitUntilReady() => readyCompleter.future;
}

class ServerService {
  final Map<String, _IsolateServerHandle> _httpServers = {};
  final Map<String, _IsolateServerHandle> _mcpServers = {};

  Future<void> startHttpServer({
    required String serverId,
    required String lynPath,
    required String indexPath,
    int port = 0,
  }) async {
    if (_httpServers[serverId]?.isRunning == true) {
      throw StateError('HTTP server already running for $serverId');
    }

    await _startServer(
      target: _httpServers,
      serverType: 'http',
      serverId: serverId,
      lynPath: lynPath,
      indexPath: indexPath,
      port: port,
    );
  }

  Future<void> stopHttpServer(String serverId) async {
    await _stopServer(_httpServers, serverId);
  }

  bool isHttpServerRunning(String serverId) {
    return _httpServers[serverId]?.isRunning ?? false;
  }

  int? getHttpServerPid(String serverId) {
    return _httpServers[serverId]?.runtimeId;
  }

  int? getHttpServerPort(String serverId) {
    return _httpServers[serverId]?.port;
  }

  Future<void> startMcpServer({
    required String serverId,
    required String lynPath,
    required String indexPath,
    int port = 0,
  }) async {
    if (_mcpServers[serverId]?.isRunning == true) {
      throw StateError('MCP server already running for $serverId');
    }

    await _startServer(
      target: _mcpServers,
      serverType: 'mcp',
      serverId: serverId,
      lynPath: lynPath,
      indexPath: indexPath,
      port: port,
    );
  }

  Future<void> stopMcpServer(String serverId) async {
    await _stopServer(_mcpServers, serverId);
  }

  bool isMcpServerRunning(String serverId) {
    return _mcpServers[serverId]?.isRunning ?? false;
  }

  int? getMcpServerPid(String serverId) {
    return _mcpServers[serverId]?.runtimeId;
  }

  int? getMcpServerPort(String serverId) {
    return _mcpServers[serverId]?.port;
  }

  Future<void> stopAll() async {
    final httpIds = _httpServers.keys.toList(growable: false);
    for (final id in httpIds) {
      await stopHttpServer(id);
    }

    final mcpIds = _mcpServers.keys.toList(growable: false);
    for (final id in mcpIds) {
      await stopMcpServer(id);
    }
  }

  Future<void> _startServer({
    required Map<String, _IsolateServerHandle> target,
    required String serverType,
    required String serverId,
    required String lynPath,
    required String indexPath,
    required int port,
  }) async {
    final receivePort = ReceivePort();
    late final _IsolateServerHandle handle;

    try {
      final isolate = await Isolate.spawn(_serverWorkerMain, {
        'serverType': serverType,
        'serverId': serverId,
        'lynPath': lynPath,
        'indexPath': indexPath,
        'port': port,
        'sendPort': receivePort.sendPort,
      });

      handle = _IsolateServerHandle(
        serverId: serverId,
        serverType: serverType,
        receivePort: receivePort,
        isolate: isolate,
      );
      target[serverId] = handle;

      handle.subscription = receivePort.listen((message) {
        if (message is! Map) {
          return;
        }

        final type = message['type'];
        if (type == 'ready') {
          handle.commandPort = message['commandPort'] as SendPort?;
          handle.runtimeId = message['runtimeId'] as int?;
          handle.port = message['port'] as int?;
          handle.isRunning = true;
          if (!handle.readyCompleter.isCompleted) {
            handle.readyCompleter.complete();
          }
        } else if (type == 'stopped') {
          handle.isRunning = false;
        } else if (type == 'error') {
          final err = message['error'];
          if (!handle.readyCompleter.isCompleted) {
            handle.readyCompleter.completeError(
              StateError('Failed to start $serverType server: $err'),
            );
          }
        }
      });

      await handle.waitUntilReady().timeout(const Duration(seconds: 8));
    } catch (e) {
      await _stopServer(target, serverId);
      throw StateError('Failed to start $serverType server: $e');
    }
  }

  Future<void> _stopServer(
    Map<String, _IsolateServerHandle> target,
    String serverId,
  ) async {
    final handle = target.remove(serverId);
    if (handle == null) {
      return;
    }

    try {
      handle.commandPort?.send({'cmd': 'stop'});
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}

    try {
      handle.isolate.kill(priority: Isolate.immediate);
    } catch (_) {}

    await handle.subscription?.cancel();
    handle.receivePort.close();
    handle.isRunning = false;
  }
}

Future<void> _serverWorkerMain(Map<String, dynamic> init) async {
  final sendPort = init['sendPort'] as SendPort;
  final serverType = (init['serverType'] as String?) ?? 'http';
  final lynPath = (init['lynPath'] as String?) ?? '';
  final indexPath = (init['indexPath'] as String?) ?? '';
  final requestedPort = (init['port'] as int?) ?? 0;

  HttpServer? server;
  final commandPort = ReceivePort();
  final sseClients = <HttpResponse>{};

  try {
    final archiveFile = File(lynPath);
    final searcher = LynSokSearcher(
      archiveFile: archiveFile,
      indexPath: indexPath,
    );

    if (File(indexPath).existsSync()) {
      await searcher.loadIndex();
    }

    server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      requestedPort == 0 ? 0 : requestedPort,
      shared: false,
    );

    sendPort.send({
      'type': 'ready',
      'commandPort': commandPort.sendPort,
      'runtimeId': Isolate.current.hashCode,
      'port': server.port,
    });

    commandPort.listen((message) async {
      if (message is Map && message['cmd'] == 'stop') {
        try {
          for (final client in sseClients) {
            try {
              await client.close();
            } catch (_) {}
          }
          await server?.close(force: true);
        } finally {
          sendPort.send({'type': 'stopped'});
          commandPort.close();
          Isolate.exit();
        }
      }
    });

    await for (final request in server) {
      await _handleRequest(
        serverType,
        request,
        searcher,
        indexPath,
        sseClients,
      );
    }
  } catch (e) {
    sendPort.send({'type': 'error', 'error': e.toString()});
    try {
      await server?.close(force: true);
    } catch (_) {}
    Isolate.exit();
  }
}

Future<void> _handleRequest(
  String serverType,
  HttpRequest request,
  LynSokSearcher searcher,
  String indexPath,
  Set<HttpResponse> sseClients,
) async {
  try {
    if (request.method == 'GET' && request.uri.path == '/health') {
      _writeJson(request.response, HttpStatus.ok, {'status': 'ok'});
      return;
    }

    if (serverType == 'http') {
      await _handleHttpSearch(request, searcher, indexPath);
      return;
    }

    await _handleMcpOverHttp(request, searcher, indexPath, sseClients);
  } catch (e) {
    _writeJson(request.response, HttpStatus.internalServerError, {
      'error': e.toString(),
    });
  }
}

Future<void> _handleHttpSearch(
  HttpRequest request,
  LynSokSearcher searcher,
  String indexPath,
) async {
  if (request.method != 'GET' || request.uri.path != '/search') {
    _writeJson(request.response, HttpStatus.notFound, {'error': 'Not found'});
    return;
  }

  final query =
      request.uri.queryParameters['q'] ??
      request.uri.queryParameters['query'] ??
      '';
  if (query.trim().isEmpty) {
    _writeJson(request.response, HttpStatus.badRequest, {
      'error': 'Missing query parameter (q or query)',
    });
    return;
  }

  final maxResults =
      int.tryParse(request.uri.queryParameters['max_results'] ?? '') ?? 10;
  final contextWindow =
      int.tryParse(request.uri.queryParameters['context_window'] ?? '') ?? 1200;

  final results = await _search(
    searcher,
    indexPath,
    query,
    maxResults,
    contextWindow,
  );
  _writeJson(request.response, HttpStatus.ok, {
    'query': query,
    'results': results,
  });
}

Future<void> _handleMcpOverHttp(
  HttpRequest request,
  LynSokSearcher searcher,
  String indexPath,
  Set<HttpResponse> sseClients,
) async {
  final isSsePath =
      request.uri.path == '/mcp/sse' ||
      (request.uri.path == '/mcp' &&
          request.headers.value('accept')?.contains('text/event-stream') ==
              true);

  if (request.method == 'GET' && isSsePath) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.headers.set('cache-control', 'no-cache');
    request.response.headers.set('connection', 'keep-alive');
    request.response.headers.set('x-accel-buffering', 'no');
    request.response.write('event: endpoint\n');
    request.response.write('data: /mcp\n\n');
    request.response.write(': connected\n\n');
    await request.response.flush();
    sseClients.add(request.response);

    request.response.done
        .catchError((_) {})
        .whenComplete(() => sseClients.remove(request.response));
    return;
  }

  if (request.method == 'GET' && request.uri.path == '/mcp/tools') {
    _writeJson(request.response, HttpStatus.ok, {
      'tools': [_mcpToolDefinition()],
    });
    return;
  }

  if (request.method == 'POST' &&
      (request.uri.path == '/mcp' || request.uri.path == '/mcp/call')) {
    final body = await utf8.decoder.bind(request).join();
    final decodedRaw = body.trim().isEmpty ? null : jsonDecode(body);
    if (decodedRaw is! Map<String, dynamic>) {
      _writeJsonRpcError(request.response, null, -32600, 'Invalid Request');
      return;
    }

    final isJsonRpc = decodedRaw['jsonrpc'] == '2.0';
    if (!isJsonRpc) {
      final tool = (decodedRaw['tool'] as String?) ?? '';
      final args =
          (decodedRaw['arguments'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      if (tool != 'lynsok.search') {
        _writeJson(request.response, HttpStatus.badRequest, {
          'isError': true,
          'error': 'Unknown tool: $tool',
        });
        return;
      }

      final callResult = await _runSearchTool(searcher, indexPath, args);
      _writeJson(request.response, HttpStatus.ok, callResult);
      return;
    }

    final id = decodedRaw['id'];
    final method = decodedRaw['method'];
    final params =
        (decodedRaw['params'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    if (method is! String || method.isEmpty) {
      _writeJsonRpcError(request.response, id, -32600, 'Invalid Request');
      return;
    }

    if (method == 'initialize') {
      _writeJsonRpcResult(request.response, id, {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'lynsok', 'version': '0.1.0'},
        'instructions': 'Search a LynSok archive and return ranked snippets.',
      });
      return;
    }

    if (method == 'notifications/initialized') {
      // JSON-RPC notification: no response.
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }

    if (method == 'ping') {
      _writeJsonRpcResult(request.response, id, <String, dynamic>{});
      return;
    }

    if (method == 'tools/list') {
      _writeJsonRpcResult(request.response, id, {
        'tools': [_mcpToolDefinition()],
      });
      return;
    }

    if (method == 'tools/call') {
      final toolName = (params['name'] as String?) ?? '';
      if (toolName != 'lynsok.search') {
        _writeJsonRpcError(
          request.response,
          id,
          -32602,
          'Unknown tool: $toolName',
        );
        return;
      }

      final args =
          (params['arguments'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final callResult = await _runSearchTool(searcher, indexPath, args);
      _writeJsonRpcResult(request.response, id, callResult);
      return;
    }

    _writeJsonRpcError(request.response, id, -32601, 'Method not found');
    return;
  }

  _writeJson(request.response, HttpStatus.notFound, {'error': 'Not found'});
}

Map<String, dynamic> _mcpToolDefinition() {
  return {
    'name': 'lynsok.search',
    'description':
        'Search the LynSok archive and return ranked snippets as JSON',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
        'max_results': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 200,
          'default': 10,
        },
        'context_window': {
          'type': 'integer',
          'minimum': 128,
          'maximum': 32768,
          'default': 1200,
        },
      },
      'required': ['query'],
    },
  };
}

Future<Map<String, dynamic>> _runSearchTool(
  LynSokSearcher searcher,
  String indexPath,
  Map<String, dynamic> args,
) async {
  final query = (args['query'] as String?)?.trim() ?? '';
  if (query.isEmpty) {
    return {
      'isError': true,
      'content': [
        {
          'type': 'text',
          'text': jsonEncode({'error': 'query is required'}),
        },
      ],
    };
  }

  final maxResults = (args['max_results'] as num?)?.toInt() ?? 10;
  final contextWindow = (args['context_window'] as num?)?.toInt() ?? 1200;
  final results = await _search(
    searcher,
    indexPath,
    query,
    maxResults,
    contextWindow,
  );

  return {
    'isError': false,
    'content': [
      {
        'type': 'text',
        'text': jsonEncode({'results': results}),
      },
    ],
  };
}

Future<List<Map<String, dynamic>>> _search(
  LynSokSearcher searcher,
  String indexPath,
  String query,
  int maxResults,
  int contextWindow,
) async {
  final hasIndex = File(indexPath).existsSync();

  final results = hasIndex
      ? await searcher.indexedSearch(
          query,
          maxResults: maxResults,
          contextWindowBytes: contextWindow,
        )
      : await searcher.rawSearch(
          query,
          maxResults: maxResults,
          contextWindowBytes: contextWindow,
        );

  return results
      .map((r) => {'path': r.path, 'score': r.score, 'snippet': r.snippet})
      .toList(growable: false);
}

void _writeJson(HttpResponse response, int status, Map<String, dynamic> body) {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  response.close();
}

void _writeJsonRpcResult(HttpResponse response, Object? id, Object? result) {
  _writeJson(response, HttpStatus.ok, {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  });
}

void _writeJsonRpcError(
  HttpResponse response,
  Object? id,
  int code,
  String message,
) {
  _writeJson(response, HttpStatus.ok, {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });
}
