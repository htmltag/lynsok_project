import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop/services/server_service.dart';

// Singleton instance of ServerService
final serverServiceProvider = Provider<ServerService>((ref) {
  return ServerService();
});

/// State for a single index's server processes
class IndexServersState {
  static const Object _sentinel = Object();

  final bool httpServerRunning;
  final bool mcpServerRunning;
  final int? httpServerPid;
  final int? mcpServerPid;
  final int? httpServerPort;
  final int? mcpServerPort;
  final String? error;
  final bool isLoading;

  const IndexServersState({
    this.httpServerRunning = false,
    this.mcpServerRunning = false,
    this.httpServerPid,
    this.mcpServerPid,
    this.httpServerPort,
    this.mcpServerPort,
    this.error,
    this.isLoading = false,
  });

  IndexServersState copyWith({
    bool? httpServerRunning,
    bool? mcpServerRunning,
    Object? httpServerPid = _sentinel,
    Object? mcpServerPid = _sentinel,
    Object? httpServerPort = _sentinel,
    Object? mcpServerPort = _sentinel,
    Object? error = _sentinel,
    bool? isLoading,
  }) {
    return IndexServersState(
      httpServerRunning: httpServerRunning ?? this.httpServerRunning,
      mcpServerRunning: mcpServerRunning ?? this.mcpServerRunning,
      httpServerPid: identical(httpServerPid, _sentinel)
          ? this.httpServerPid
          : httpServerPid as int?,
      mcpServerPid: identical(mcpServerPid, _sentinel)
          ? this.mcpServerPid
          : mcpServerPid as int?,
      httpServerPort: identical(httpServerPort, _sentinel)
          ? this.httpServerPort
          : httpServerPort as int?,
      mcpServerPort: identical(mcpServerPort, _sentinel)
          ? this.mcpServerPort
          : mcpServerPort as int?,
      error: identical(error, _sentinel) ? this.error : error as String?,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Notifier for managing server processes for a specific index
class IndexServersNotifier extends StateNotifier<IndexServersState> {
  final ServerService _serverService;
  final String _indexId;
  final String _lynPath;
  final String _indexPath;

  IndexServersNotifier({
    required ServerService serverService,
    required String indexId,
    required String lynPath,
    required String indexPath,
    int port = 8181,
  }) : _serverService = serverService,
       _indexId = indexId,
       _lynPath = lynPath,
       _indexPath = indexPath,
       super(const IndexServersState());

  /// Toggles the HTTP server on/off
  Future<void> toggleHttpServer() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      if (state.httpServerRunning) {
        await _serverService.stopHttpServer(_indexId);
        state = state.copyWith(
          httpServerRunning: false,
          httpServerPid: null,
          httpServerPort: null,
          isLoading: false,
        );
      } else {
        await _serverService.startHttpServer(
          serverId: _indexId,
          lynPath: _lynPath,
          indexPath: _indexPath,
          port: 0,
        );
        final pid = _serverService.getHttpServerPid(_indexId);
        final assignedPort = _serverService.getHttpServerPort(_indexId);
        state = state.copyWith(
          httpServerRunning: true,
          httpServerPid: pid,
          httpServerPort: assignedPort,
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to toggle HTTP server: $e',
        isLoading: false,
      );
    }
  }

  /// Toggles the MCP server on/off
  Future<void> toggleMcpServer() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      if (state.mcpServerRunning) {
        await _serverService.stopMcpServer(_indexId);
        state = state.copyWith(
          mcpServerRunning: false,
          mcpServerPid: null,
          mcpServerPort: null,
          isLoading: false,
        );
      } else {
        await _serverService.startMcpServer(
          serverId: _indexId,
          lynPath: _lynPath,
          indexPath: _indexPath,
          port: 0,
        );
        final pid = _serverService.getMcpServerPid(_indexId);
        final assignedPort = _serverService.getMcpServerPort(_indexId);
        state = state.copyWith(
          mcpServerRunning: true,
          mcpServerPid: pid,
          mcpServerPort: assignedPort,
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to toggle MCP server: $e',
        isLoading: false,
      );
    }
  }

  /// Manually start HTTP server
  Future<void> startHttpServer() async {
    if (state.httpServerRunning) return;
    await toggleHttpServer();
  }

  /// Manually stop HTTP server
  Future<void> stopHttpServer() async {
    if (!state.httpServerRunning) return;
    await toggleHttpServer();
  }

  /// Manually start MCP server
  Future<void> startMcpServer() async {
    if (state.mcpServerRunning) return;
    await toggleMcpServer();
  }

  /// Manually stop MCP server
  Future<void> stopMcpServer() async {
    if (!state.mcpServerRunning) return;
    await toggleMcpServer();
  }

  /// Check server health (stub for future use)
  Future<bool> checkHttpServerHealth() async {
    if (!state.httpServerRunning) return false;
    // TODO: Implement health check endpoint polling
    return true;
  }
}

/// Family provider for managing servers per index
/// Usage: ref.watch(indexServersProvider(indexId))
final indexServersProvider =
    StateNotifierProvider.family<
      IndexServersNotifier,
      IndexServersState,
      String
    >((ref, indexId) {
      // This would need index data passed in; for now return placeholder
      // In practice, you'd look up the index in a list and get its paths
      throw UnimplementedError(
        'Use indexServersProvider.call(indexId, lynPath, indexPath) instead',
      );
    });

/// Extended provider that takes index parameters
final indexServersProviderWithConfig =
    StateNotifierProvider.family<
      IndexServersNotifier,
      IndexServersState,
      ({String id, String lynPath, String indexPath, int port})
    >((ref, config) {
      final serverService = ref.watch(serverServiceProvider);
      return IndexServersNotifier(
        serverService: serverService,
        indexId: config.id,
        lynPath: config.lynPath,
        indexPath: config.indexPath,
        port: config.port,
      );
    });
