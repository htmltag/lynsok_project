import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop/models/index_model.dart';
import 'package:desktop/providers/lynsok_provider.dart';
import 'package:desktop/providers/server_process_provider.dart';
import 'package:desktop/providers/index_provider.dart';
import 'package:clipboard/clipboard.dart';
import 'package:lynsok_core/lynsok_runner.dart';

class IndexDetailScreen extends ConsumerStatefulWidget {
  final IndexModel index;

  const IndexDetailScreen({super.key, required this.index});

  @override
  ConsumerState<IndexDetailScreen> createState() => _IndexDetailScreenState();
}

class _IndexDetailScreenState extends ConsumerState<IndexDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  String _selectedLlm = 'ollama';
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _promptController.text =
        'You are a helpful assistant with access to local documents.';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.index.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Search & RAG'),
            Tab(text: 'Connectivity'),
            Tab(text: 'Maintenance'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
          _buildConnectivityTab(),
          _buildMaintenanceTab(),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Enter search query...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _performSearch,
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),
          const SizedBox(height: 16),

          // Results list
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('No results yet'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      return ListTile(
                        title: Text(result['title'] ?? 'Document'),
                        subtitle: Text(
                          result['snippet'] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          // Open document viewer with the result
                          _openDocumentViewer(
                            result['path'] ?? '',
                            result['title'] ?? 'Document',
                            result['snippet'] ?? '',
                          );
                        },
                      );
                    },
                  ),
          ),

          // RAG Panel
          const Divider(),
          const Text(
            'RAG Configuration',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // LLM Dropdown
          DropdownButtonFormField<String>(
            initialValue: _selectedLlm,
            decoration: const InputDecoration(labelText: 'LLM Provider'),
            items: const [
              DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
              DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
            ],
            onChanged: (value) {
              setState(() {
                _selectedLlm = value!;
              });
            },
          ),

          const SizedBox(height: 8),

          // System Prompt Editor
          TextField(
            controller: _promptController,
            decoration: const InputDecoration(
              labelText: 'System Prompt',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 16),

          // Ask AI Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _askAI,
              icon: const Icon(Icons.smart_toy),
              label: const Text('Ask AI'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectivityTab() {
    final config = ref.watch(configProvider);

    // Watch server state for this index
    final serverState = ref.watch(
      indexServersProviderWithConfig((
        id: widget.index.id?.toString() ?? 'unknown',
        lynPath: widget.index.lynPath,
        indexPath: widget.index.indexPath,
        port: config?.restPort ?? 8181,
      )),
    );

    final serverNotifier = ref.read(
      indexServersProviderWithConfig((
        id: widget.index.id?.toString() ?? 'unknown',
        lynPath: widget.index.lynPath,
        indexPath: widget.index.indexPath,
        port: config?.restPort ?? 8181,
      )).notifier,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HTTP Server
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'HTTP Server',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Switch(
                        value: serverState.httpServerRunning,
                        onChanged: serverState.isLoading
                            ? null
                            : (_) => serverNotifier.toggleHttpServer(),
                      ),
                    ],
                  ),
                  if (serverState.httpServerRunning) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Running on port ${serverState.httpServerPort ?? '-'}',
                    ),
                    Text(
                      'Endpoint: http://localhost:${serverState.httpServerPort ?? '-'}${serverState.httpServerPort != null ? '/search' : ''}',
                    ),
                    if (serverState.httpServerPort != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Example test URL: http://localhost:${serverState.httpServerPort}/search?q=test&max_results=3&context_window=300',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              tooltip: 'Copy example URL',
                              onPressed: () {
                                final exampleUrl =
                                    'http://localhost:${serverState.httpServerPort}/search?q=test&max_results=3&context_window=300';
                                FlutterClipboard.copy(exampleUrl);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Example URL copied'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (serverState.httpServerPid != null)
                      Text('PID: ${serverState.httpServerPid}'),
                  ],
                  if (serverState.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      serverState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // MCP Server
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'MCP Server',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Switch(
                        value: serverState.mcpServerRunning,
                        onChanged: serverState.isLoading
                            ? null
                            : (_) => serverNotifier.toggleMcpServer(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Model Context Protocol (JSON-RPC 2.0 over HTTP/SSE)',
                  ),
                  if (serverState.mcpServerRunning &&
                      serverState.mcpServerPid != null) ...[
                    const SizedBox(height: 8),
                    Text('Running on port ${serverState.mcpServerPort ?? '-'}'),
                    Text(
                      'JSON-RPC: http://localhost:${serverState.mcpServerPort ?? '-'}${serverState.mcpServerPort != null ? '/mcp' : ''}',
                    ),
                    Text(
                      'SSE Stream: http://localhost:${serverState.mcpServerPort ?? '-'}${serverState.mcpServerPort != null ? '/mcp/sse' : ''}',
                    ),
                    Text('PID: ${serverState.mcpServerPid}'),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _testMcpServer,
                        icon: const Icon(Icons.bug_report_outlined),
                        label: const Text('Test MCP'),
                      ),
                    ),
                  ],
                  if (serverState.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      serverState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Config Helper
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LLM Configuration',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Copy this configuration for Claude/Cursor:'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(_generateConfigJson()),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        FlutterClipboard.copy(_generateConfigJson());
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Configuration copied to clipboard',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy to Clipboard'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Index Statistics',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Source Path: ${widget.index.sourcePath}'),
                  Text('File Count: ${widget.index.fileCount}'),
                  Text('Total Size: ${widget.index.totalSize}'),
                  Text('Created: ${widget.index.createdAt}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Actions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _reindex,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-index'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _deleteIndex,
                      icon: const Icon(Icons.delete, color: Colors.white),
                      label: const Text('Delete Index'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _performSearch() async {
    if (_searchController.text.isEmpty) return;

    try {
      final archiveFile = File(
        widget.index.indexPath.replaceAll(RegExp(r'\.idx$'), '.lyn'),
      );
      final searcher = LynSokSearcher(
        archiveFile: archiveFile,
        indexPath: widget.index.indexPath,
      );
      if (File(widget.index.indexPath).existsSync()) {
        await searcher.loadIndex();
      }
      final results = await searcher.indexedSearch(
        _searchController.text,
        maxResults: 10,
        contextWindowBytes: 200,
      );

      setState(() {
        _searchResults = results.map((result) {
          return {
            'title': result.path.split('/').last,
            'snippet': result.snippet,
            'path': result.path,
            'score': result.score,
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  void _askAI() async {
    if (_searchResults.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please perform a search first')),
        );
      }
      return;
    }

    final llmConfig = ref.read(configProvider);
    if (llmConfig == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('LLM configuration not found')),
        );
      }
      return;
    }

    try {
      final client = LlmClient.fromConfig(llmConfig.llm);

      // Build context from top 3 results
      final contextText = _searchResults
          .take(3)
          .map((result) {
            return '${result['title']}: ${result['snippet']}';
          })
          .join('\n\n');

      final userPrompt =
          'Context:\n$contextText\n\nQuestion: ${_searchController.text}';

      final response = await client.generate(
        systemPrompt: _promptController.text,
        userPrompt: userPrompt,
        maxTokens: 1000,
      );

      // Show response in dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('AI Response'),
            content: SingleChildScrollView(child: Text(response)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('AI request failed: $e')));
      }
    }
  }

  String _generateConfigJson() {
    final config = ref.read(configProvider);
    final serverState = ref.read(
      indexServersProviderWithConfig((
        id: widget.index.id?.toString() ?? 'unknown',
        lynPath: widget.index.lynPath,
        indexPath: widget.index.indexPath,
        port: config?.restPort ?? 8181,
      )),
    );
    final mcpPort = serverState.mcpServerPort;

    return '''
{
  "mcpServers": {
    "lynsok": {
      "type": "http",
      "url": "http://localhost:${mcpPort ?? 0}/mcp"
    }
  }
}
''';
  }

  Future<void> _testMcpServer() async {
    final config = ref.read(configProvider);
    final serverState = ref.read(
      indexServersProviderWithConfig((
        id: widget.index.id?.toString() ?? 'unknown',
        lynPath: widget.index.lynPath,
        indexPath: widget.index.indexPath,
        port: config?.restPort ?? 8181,
      )),
    );

    final port = serverState.mcpServerPort;
    if (port == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start MCP server first.')),
        );
      }
      return;
    }

    final query = _searchController.text.trim().isEmpty
        ? 'test'
        : _searchController.text.trim();

    final client = HttpClient();
    try {
      final endpoint = Uri.parse('http://localhost:$port/mcp');

      final initResult = await _postJsonRpc(client, endpoint, {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2024-11-05',
          'capabilities': {},
          'clientInfo': {'name': 'lynsok-desktop', 'version': '0.1.0'},
        },
      });

      await _postJsonRpc(client, endpoint, {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': {},
      });

      final toolsResult = await _postJsonRpc(client, endpoint, {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': {},
      });

      final callResult = await _postJsonRpc(client, endpoint, {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'lynsok.search',
          'arguments': {
            'query': query,
            'max_results': 3,
            'context_window': 500,
          },
        },
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('MCP Test Result'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert({
                  'initialize': initResult,
                  'tools/list': toolsResult,
                  'tools/call': callResult,
                }),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('MCP test failed: $e')));
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJsonRpc(
    HttpClient client,
    Uri endpoint,
    Map<String, dynamic> payload,
  ) async {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (body.trim().isEmpty) {
      return {'statusCode': response.statusCode};
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'raw': decoded};
  }

  void _reindex() {
    final indexingNotifier = ref.read(indexingProvider.notifier);

    // Start the re-indexing immediately
    indexingNotifier.startIndexing(
      widget.index.sourcePath,
      widget.index.lynPath,
      excludePatterns: widget.index.excludePatterns,
    );

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Re-indexing'),
        content: Consumer(
          builder: (context, refInDialog, _) {
            final indexingState = refInDialog.watch(indexingProvider);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (indexingState.isIndexing) ...[
                  LinearProgressIndicator(
                    value: indexingState.progress > 0
                        ? indexingState.progress
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Indexing: ${(indexingState.progress * 100).toStringAsFixed(1)}%',
                  ),
                  if (indexingState.currentFile.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'File: ${indexingState.currentFile}',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ] else if (indexingState.error != null) ...[
                  Text(
                    'Error: ${indexingState.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ] else ...[
                  const Text('Re-indexing complete!'),
                ],
              ],
            );
          },
        ),
        actions: [
          Consumer(
            builder: (context, refInDialog, _) {
              final indexingState = refInDialog.watch(indexingProvider);
              if (!indexingState.isIndexing) {
                return TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Refresh the index list
                    ref.read(indexProvider.notifier).refreshIndexes();
                  },
                  child: const Text('Close'),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  void _deleteIndex() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Index'),
          content: const Text(
            'Are you sure you want to delete this index? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final config = ref.read(configProvider);
                  final serverNotifier = ref.read(
                    indexServersProviderWithConfig((
                      id: widget.index.id?.toString() ?? 'unknown',
                      lynPath: widget.index.lynPath,
                      indexPath: widget.index.indexPath,
                      port: config?.restPort ?? 8181,
                    )).notifier,
                  );

                  await serverNotifier.stopHttpServer();
                  await serverNotifier.stopMcpServer();

                  // Delete .lyn and .idx files
                  final lynFile = File(widget.index.lynPath);
                  final idxFile = File(widget.index.indexPath);

                  if (await lynFile.exists()) {
                    await lynFile.delete();
                  }
                  if (await idxFile.exists()) {
                    await idxFile.delete();
                  }

                  // Remove from database
                  if (widget.index.id != null) {
                    await ref
                        .read(indexProvider.notifier)
                        .removeIndex(widget.index.id!);
                  }

                  if (mounted) {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pop(); // Back to dashboard
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Index deleted')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete: $e')),
                    );
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }

  void _openDocumentViewer(String path, String title, String snippet) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Source: $path',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(snippet, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
