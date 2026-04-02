import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:desktop/models/index_model.dart';
import 'package:desktop/providers/lynsok_provider.dart';
import 'package:desktop/providers/server_process_provider.dart';
import 'package:desktop/providers/index_provider.dart';
import 'package:clipboard/clipboard.dart';
import 'package:path/path.dart' as p;

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
  final ScrollController _previewScrollController = ScrollController();
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final ScrollController _connectivityScrollController = ScrollController();
  final ScrollController _maintenanceScrollController = ScrollController();
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _queryTerms = [];
  int _maxResults = 10;
  int _contextWindow = 500;
  int? _lastSearchDurationMs;
  Map<String, dynamic>? _selectedResult;
  String? _previewText;
  String? _previewError;
  bool _previewLoading = false;
  double? _pendingPreviewJumpFraction;
  String? _pendingPdfSearchQuery;
  late final PdfTextSearcher _pdfTextSearcher;
  bool _isSearcherWarming = false;
  Future<void>? _searcherWarmup;
  String? _searcherWarmError;
  bool _showConnectivityTopFade = false;
  bool _showConnectivityBottomFade = false;
  bool _showMaintenanceTopFade = false;
  bool _showMaintenanceBottomFade = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pdfTextSearcher = PdfTextSearcher(_pdfViewerController);
    _pdfTextSearcher.addListener(_onPdfSearchStateChanged);
    _searcherWarmup = _warmSearcher();
    _connectivityScrollController.addListener(_updateConnectivityFades);
    _maintenanceScrollController.addListener(_updateMaintenanceFades);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateConnectivityFades();
      _updateMaintenanceFades();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _previewScrollController.dispose();
    _connectivityScrollController.removeListener(_updateConnectivityFades);
    _maintenanceScrollController.removeListener(_updateMaintenanceFades);
    _connectivityScrollController.dispose();
    _maintenanceScrollController.dispose();
    _pdfTextSearcher.removeListener(_onPdfSearchStateChanged);
    _pdfTextSearcher.dispose();
    super.dispose();
  }

  void _onPdfSearchStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _updateConnectivityFades() {
    if (!_connectivityScrollController.hasClients || !mounted) {
      return;
    }

    final position = _connectivityScrollController.position;
    final showTop = position.pixels > 4;
    final showBottom = position.pixels < position.maxScrollExtent - 4;

    if (showTop != _showConnectivityTopFade ||
        showBottom != _showConnectivityBottomFade) {
      setState(() {
        _showConnectivityTopFade = showTop;
        _showConnectivityBottomFade = showBottom;
      });
    }
  }

  void _updateMaintenanceFades() {
    if (!_maintenanceScrollController.hasClients || !mounted) {
      return;
    }

    final position = _maintenanceScrollController.position;
    final showTop = position.pixels > 4;
    final showBottom = position.pixels < position.maxScrollExtent - 4;

    if (showTop != _showMaintenanceTopFade ||
        showBottom != _showMaintenanceBottomFade) {
      setState(() {
        _showMaintenanceTopFade = showTop;
        _showMaintenanceBottomFade = showBottom;
      });
    }
  }

  Widget _buildScrollFade({required BuildContext context, required bool top}) {
    final baseColor = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [
              baseColor.withValues(alpha: 0.92),
              baseColor.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.index.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Search'),
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Enter search query...',
                    suffixIcon: _isSearcherWarming
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: _performSearch,
                          ),
                  ),
                  onSubmitted: _isSearcherWarming
                      ? null
                      : (_) => _performSearch(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  initialValue: _maxResults,
                  decoration: const InputDecoration(labelText: 'Max results'),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5')),
                    DropdownMenuItem(value: 10, child: Text('10')),
                    DropdownMenuItem(value: 20, child: Text('20')),
                    DropdownMenuItem(value: 50, child: Text('50')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _maxResults = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Context window: $_contextWindow',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Slider(
                      value: _contextWindow.toDouble(),
                      min: 300,
                      max: 2000,
                      divisions: 17,
                      label: _contextWindow.toString(),
                      onChanged: (value) {
                        setState(() => _contextWindow = value.round());
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isSearcherWarming) ...[
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Preparing search index...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (_searcherWarmError != null) ...[
            Text(
              'Warm-up failed: $_searcherWarmError',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_lastSearchDurationMs != null) ...[
            Text(
              'Last search: ${_searchResults.length} result(s) in $_lastSearchDurationMs ms',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 980;

                final resultsPane = Card(
                  child: _searchResults.isEmpty
                      ? const Center(child: Text('No results yet'))
                      : ListView.separated(
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            final selected = identical(_selectedResult, result);
                            return ListTile(
                              selected: selected,
                              title: _buildHighlightedResultText(
                                result['title']?.toString() ?? 'Document',
                                baseStyle: Theme.of(
                                  context,
                                ).textTheme.titleMedium,
                                maxLines: 1,
                              ),
                              subtitle: _buildHighlightedResultText(
                                _stripHighlightMarkers(
                                  result['snippet']?.toString() ?? '',
                                ),
                                baseStyle: Theme.of(
                                  context,
                                ).textTheme.bodyMedium,
                                maxLines: 3,
                              ),
                              onTap: () => _onResultSelected(result),
                            );
                          },
                        ),
                );

                final previewPane = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildPreviewPane(),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      Expanded(child: resultsPane),
                      const SizedBox(height: 12),
                      Expanded(child: previewPane),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 5, child: resultsPane),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: previewPane),
                  ],
                );
              },
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

    return Stack(
      children: [
        ListView(
          controller: _connectivityScrollController,
          padding: const EdgeInsets.all(16),
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
                      Text(
                        'Running on port ${serverState.mcpServerPort ?? '-'}',
                      ),
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
        if (_showConnectivityTopFade)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _buildScrollFade(context: context, top: true),
          ),
        if (_showConnectivityBottomFade)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildScrollFade(context: context, top: false),
          ),
      ],
    );
  }

  Widget _buildMaintenanceTab() {
    final fileTypeStats = ref.watch(
      indexFileTypeStatsProvider(widget.index.indexPath),
    );
    final fallbackFileCount = fileTypeStats.asData?.value.totalDocuments ?? 0;
    final effectiveFileCount = widget.index.fileCount > 0
        ? widget.index.fileCount
        : fallbackFileCount;

    return Stack(
      children: [
        ListView(
          controller: _maintenanceScrollController,
          padding: const EdgeInsets.all(16),
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
                    Text(
                      effectiveFileCount > 0
                          ? 'File Count: $effectiveFileCount'
                          : fileTypeStats.isLoading
                          ? 'File Count: Calculating...'
                          : 'File Count: 0',
                    ),
                    Text('Index Path: ${widget.index.indexPath}'),
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
        if (_showMaintenanceTopFade)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _buildScrollFade(context: context, top: true),
          ),
        if (_showMaintenanceBottomFade)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildScrollFade(context: context, top: false),
          ),
      ],
    );
  }

  Future<void> _warmSearcher() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isSearcherWarming = true;
      _searcherWarmError = null;
    });

    try {
      await ref.read(
        cachedSearcherProvider((
          lynPath: widget.index.lynPath,
          indexPath: widget.index.indexPath,
        )).future,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searcherWarmError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearcherWarming = false;
        });
      }
    }
  }

  void _performSearch() async {
    if (_searchController.text.isEmpty) return;

    if (_searcherWarmup != null) {
      await _searcherWarmup;
    }

    try {
      final stopwatch = Stopwatch()..start();
      final searcher = await ref.read(
        cachedSearcherProvider((
          lynPath: widget.index.lynPath,
          indexPath: widget.index.indexPath,
        )).future,
      );
      final hasIndex = File(widget.index.indexPath).existsSync();
      final results = hasIndex
          ? await searcher.indexedSearch(
              _searchController.text,
              maxResults: _maxResults,
              contextWindowBytes: _contextWindow,
            )
          : await searcher.rawSearch(
              _searchController.text,
              maxResults: _maxResults,
              contextWindowBytes: _contextWindow,
            );
      stopwatch.stop();

      final queryTerms = _extractQueryTerms(_searchController.text);

      setState(() {
        _queryTerms = queryTerms;
        _lastSearchDurationMs = stopwatch.elapsedMilliseconds;
        _searchResults = results.map((result) {
          return {
            'title': result.path.split('/').last,
            'snippet': result.snippet,
            'path': result.path,
            'score': result.score,
            'matchOffset': result.matchOffset,
          };
        }).toList();
        _selectedResult = null;
        _previewText = null;
        _previewError = null;
        _previewLoading = false;
        _pendingPreviewJumpFraction = null;
        _pendingPdfSearchQuery = null;
        _pdfTextSearcher.resetTextSearch();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  Future<void> _onResultSelected(Map<String, dynamic> result) async {
    setState(() {
      _selectedResult = result;
      _previewText = null;
      _previewError = null;
      _previewLoading = false;
      _pendingPreviewJumpFraction = null;
    });

    final path = (result['path'] as String?) ?? '';
    final extension = p.extension(path).toLowerCase();

    if (extension == '.txt' || extension == '.md') {
      setState(() {
        _previewLoading = true;
        _pendingPdfSearchQuery = null;
      });

      try {
        final file = File(path);
        if (!await file.exists()) {
          throw StateError('File not found: $path');
        }

        final content = await file.readAsString();
        if (!mounted) {
          return;
        }

        setState(() {
          _previewText = content;
          _previewLoading = false;
        });

        _queuePreviewJump(result, content);
      } catch (e) {
        if (!mounted) {
          return;
        }
        setState(() {
          _previewError = e.toString();
          _previewLoading = false;
        });
      }
      return;
    }

    if (extension == '.pdf') {
      setState(() {
        _pendingPdfSearchQuery = _searchController.text.trim();
      });
      _tryRunPdfSearch();
      return;
    }

    _pdfTextSearcher.resetTextSearch();
  }

  void _queuePreviewJump(Map<String, dynamic> result, String content) {
    if (content.isEmpty) {
      return;
    }

    final rawOffset = result['matchOffset'];
    final offset = rawOffset is int ? rawOffset : 0;
    final boundedOffset = offset.clamp(0, content.length);
    _pendingPreviewJumpFraction = boundedOffset / content.length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingPreviewJump();
    });
  }

  void _applyPendingPreviewJump() {
    if (!mounted) {
      return;
    }

    final fraction = _pendingPreviewJumpFraction;
    if (fraction == null) {
      return;
    }

    if (!_previewScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyPendingPreviewJump();
      });
      return;
    }

    final maxScrollExtent = _previewScrollController.position.maxScrollExtent;
    final target = (maxScrollExtent * fraction).clamp(0.0, maxScrollExtent);
    _previewScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    _pendingPreviewJumpFraction = null;
  }

  void _tryRunPdfSearch() {
    if (!_pdfViewerController.isReady) {
      return;
    }

    final query = (_pendingPdfSearchQuery ?? '').trim();
    if (query.isEmpty) {
      _pdfTextSearcher.resetTextSearch();
      return;
    }

    _pdfTextSearcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
    );
  }

  Widget _buildHighlightedResultText(
    String text, {
    required TextStyle? baseStyle,
    required int maxLines,
  }) {
    return Text.rich(
      _buildHighlightedSpan(text, baseStyle),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextSpan _buildHighlightedSpan(String text, TextStyle? baseStyle) {
    if (text.isEmpty || _queryTerms.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final lowerText = text.toLowerCase();
    final ranges = <(int, int)>[];
    for (final term in _queryTerms) {
      var start = 0;
      while (true) {
        final index = lowerText.indexOf(term, start);
        if (index < 0) {
          break;
        }
        ranges.add((index, index + term.length));
        start = index + 1;
      }
    }

    if (ranges.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in ranges) {
      if (merged.isEmpty || range.$1 > merged.last.$2) {
        merged.add(range);
        continue;
      }
      merged[merged.length - 1] = (
        merged.last.$1,
        range.$2 > merged.last.$2 ? range.$2 : merged.last.$2,
      );
    }

    final highlightStyle = (baseStyle ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in merged) {
      if (cursor < range.$1) {
        spans.add(
          TextSpan(text: text.substring(cursor, range.$1), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(range.$1, range.$2),
          style: highlightStyle,
        ),
      );
      cursor = range.$2;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  String _stripHighlightMarkers(String text) {
    return text.replaceAll('**', '');
  }

  List<String> _extractQueryTerms(String query) {
    final matches = RegExp(r'\S+').allMatches(query.toLowerCase());
    final terms = <String>{};
    for (final match in matches) {
      final token = query
          .substring(match.start, match.end)
          .toLowerCase()
          .trim();
      if (token.isNotEmpty) {
        terms.add(token);
      }
    }
    return terms.toList();
  }

  Widget _buildPreviewPane() {
    if (_selectedResult == null) {
      return const Center(
        child: Text('Select a search result to preview the document.'),
      );
    }

    final path = (_selectedResult!['path'] as String?) ?? '';
    final extension = p.extension(path).toLowerCase();

    if (_previewLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_previewError != null) {
      return Center(child: Text('Preview error: $_previewError'));
    }

    if (extension == '.pdf') {
      if (_pendingPdfSearchQuery != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryRunPdfSearch();
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview: ${_selectedResult!['title'] ?? p.basename(path)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: PdfViewer.file(
              path,
              controller: _pdfViewerController,
              params: PdfViewerParams(
                pagePaintCallbacks: [
                  _pdfTextSearcher.pageTextMatchPaintCallback,
                ],
                matchTextColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                activeMatchTextColor: Theme.of(
                  context,
                ).colorScheme.primaryContainer,
                onViewerReady: (document, controller) {
                  _tryRunPdfSearch();
                },
              ),
            ),
          ),
        ],
      );
    }

    if (extension == '.txt' || extension == '.md') {
      final content = _previewText ?? '';
      if (_pendingPreviewJumpFraction != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _applyPendingPreviewJump();
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview: ${_selectedResult!['title'] ?? p.basename(path)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              controller: _previewScrollController,
              child: extension == '.md'
                  ? MarkdownBody(data: content)
                  : SelectableText(
                      content,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
            ),
          ),
        ],
      );
    }

    if (extension == '.docx' || extension == '.doc') {
      return Center(
        child: Text(
          'DOCX preview is not available in phase 1.\nPath: $path',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Center(
      child: Text(
        'Preview not supported for ${extension.isEmpty ? 'this file type' : extension}.\nPath: $path',
        textAlign: TextAlign.center,
      ),
    );
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
                    ref.invalidate(
                      indexFileTypeStatsProvider(widget.index.indexPath),
                    );
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
                final dialogNavigator = Navigator.of(context);
                final pageNavigator = Navigator.of(this.context);
                final messenger = ScaffoldMessenger.of(this.context);

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

                  if (!mounted) return;

                  dialogNavigator.pop(); // Close dialog
                  pageNavigator.pop(); // Back to dashboard
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Index deleted')),
                  );
                } catch (e) {
                  if (!mounted) return;

                  dialogNavigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }
}
