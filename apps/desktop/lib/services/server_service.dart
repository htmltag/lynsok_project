import 'dart:io';
import 'dart:async';

/// Manages server processes (HTTP and MCP) for a specific index.
///
/// Spawns servers as subprocesses using `dart run` and tracks their lifecycle.
class ServerProcess {
  final String serverId; // index ID
  final String serverType; // 'http' or 'mcp'
  Process? _process;
  Completer<void>? _exitCompleter;

  ServerProcess({required this.serverId, required this.serverType});

  /// PID of the running process, or null if not running.
  int? get pid => _process?.pid;

  /// Whether this server is currently running.
  bool get isRunning => _process != null;

  /// Starts the server process.
  ///
  /// For HTTP: spawns `dart run apps/lynsok_cli/bin/server.dart --lyn <lynPath> --index <indexPath> --port <port>`
  /// For MCP: spawns `dart run apps/lynsok_cli/bin/mcp.dart --lyn <lynPath> --index <indexPath>`
  Future<void> start({
    required String lynPath,
    required String indexPath,
    int port = 8181,
  }) async {
    if (_process != null) {
      throw StateError('Server already running for $serverId ($serverType)');
    }

    try {
      final args = _buildArgs(lynPath, indexPath, port);
      _process = await Process.start(
        'dart',
        args,
        mode: ProcessStartMode.detachedWithStdio,
      );

      _exitCompleter = Completer<void>();

      // Listen for process exit
      _process!.exitCode
          .then((code) {
            if (!_exitCompleter!.isCompleted) {
              _exitCompleter!.complete();
            }
            _process = null;
          })
          .catchError((e) {
            if (!_exitCompleter!.isCompleted) {
              _exitCompleter!.completeError(e);
            }
            _process = null;
          });
    } catch (e) {
      _process = null;
      _exitCompleter = null;
      rethrow;
    }
  }

  /// Stops the running server process.
  Future<void> stop() async {
    if (_process == null) {
      return;
    }

    try {
      // Send SIGTERM on Unix, TerminateProcess on Windows
      final killed = _process!.kill();
      if (killed) {
        // Give it a moment to exit gracefully
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // If still running, force kill
      if (_process != null) {
        _process!.kill(ProcessSignal.sigkill);
      }
    } catch (e) {
      stderr.writeln('Error stopping $serverType server: $e');
    } finally {
      _process = null;
      if (_exitCompleter != null && !_exitCompleter!.isCompleted) {
        _exitCompleter!.complete();
      }
      _exitCompleter = null;
    }
  }

  /// Waits for the process to exit.
  Future<void> waitForExit() async {
    if (_exitCompleter == null) return;
    await _exitCompleter!.future;
  }

  List<String> _buildArgs(String lynPath, String indexPath, int port) {
    if (serverType == 'http') {
      return [
        'run',
        'apps/lynsok_cli/bin/server.dart',
        '--lyn',
        lynPath,
        '--index',
        indexPath,
      ];
    } else if (serverType == 'mcp') {
      return [
        'run',
        'apps/lynsok_cli/bin/mcp.dart',
        '--lyn',
        lynPath,
        '--index',
        indexPath,
      ];
    } else {
      throw ArgumentError('Unknown serverType: $serverType');
    }
  }
}

/// Service that manages the lifecycle of server processes.
class ServerService {
  final Map<String, ServerProcess> _httpServers = {};
  final Map<String, ServerProcess> _mcpServers = {};

  /// Starts the HTTP server for an index.
  Future<void> startHttpServer({
    required String serverId,
    required String lynPath,
    required String indexPath,
    int port = 8181,
  }) async {
    final server = ServerProcess(serverId: serverId, serverType: 'http');

    try {
      await server.start(lynPath: lynPath, indexPath: indexPath, port: port);
      _httpServers[serverId] = server;
    } catch (e) {
      throw StateError('Failed to start HTTP server: $e');
    }
  }

  /// Stops the HTTP server for an index.
  Future<void> stopHttpServer(String serverId) async {
    final server = _httpServers.remove(serverId);
    if (server != null) {
      await server.stop();
    }
  }

  /// Checks if HTTP server is running for an index.
  bool isHttpServerRunning(String serverId) {
    return _httpServers[serverId]?.isRunning ?? false;
  }

  /// Gets PID of HTTP server, if running.
  int? getHttpServerPid(String serverId) {
    return _httpServers[serverId]?.pid;
  }

  /// Starts the MCP server for an index.
  Future<void> startMcpServer({
    required String serverId,
    required String lynPath,
    required String indexPath,
  }) async {
    final server = ServerProcess(serverId: serverId, serverType: 'mcp');

    try {
      await server.start(lynPath: lynPath, indexPath: indexPath);
      _mcpServers[serverId] = server;
    } catch (e) {
      throw StateError('Failed to start MCP server: $e');
    }
  }

  /// Stops the MCP server for an index.
  Future<void> stopMcpServer(String serverId) async {
    final server = _mcpServers.remove(serverId);
    if (server != null) {
      await server.stop();
    }
  }

  /// Checks if MCP server is running for an index.
  bool isMcpServerRunning(String serverId) {
    return _mcpServers[serverId]?.isRunning ?? false;
  }

  /// Gets PID of MCP server, if running.
  int? getMcpServerPid(String serverId) {
    return _mcpServers[serverId]?.pid;
  }

  /// Stops all servers.
  Future<void> stopAll() async {
    for (final server in _httpServers.values) {
      await server.stop();
    }
    for (final server in _mcpServers.values) {
      await server.stop();
    }
    _httpServers.clear();
    _mcpServers.clear();
  }
}
