import 'package:desktop/models/index_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop/providers/index_provider.dart';
import 'package:desktop/providers/server_process_provider.dart';

class IndexCard extends ConsumerWidget {
  final IndexModel indexModel;
  final VoidCallback onTap;

  const IndexCard({super.key, required this.indexModel, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final metricsStyle = theme.textTheme.labelMedium?.copyWith(
      color: muted,
      fontWeight: FontWeight.w500,
    );
    final fileTypeStats = ref.watch(
      indexFileTypeStatsProvider(indexModel.indexPath),
    );
    final serverState = ref.watch(
      indexServersProviderWithConfig((
        id: indexModel.id?.toString() ?? 'unknown',
        lynPath: indexModel.lynPath,
        indexPath: indexModel.indexPath,
        httpPort: indexModel.httpPort,
        mcpPort: indexModel.mcpPort,
      )),
    );

    final idxCount = fileTypeStats.asData?.value.totalDocuments ?? 0;
    final effectiveFileCount = indexModel.fileCount > 0
        ? indexModel.fileCount
        : idxCount;
    final fileCountText = '${_formatFileCount(effectiveFileCount)} files';

    return _CardHoverLift(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  indexModel.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(fileCountText, style: metricsStyle),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 13, color: muted),
                    const SizedBox(width: 7),
                    Text(
                      'Created: ${_formatRelativeTime(indexModel.createdAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildServerLights(context, serverState),
                const SizedBox(height: 12),
                _buildFileTypeBreakdown(context, fileTypeStats),
                const SizedBox(height: 14),
                Text(
                  'Source',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  indexModel.sourcePath,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontFamily: 'monospace',
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  'Index',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  indexModel.indexPath,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontFamily: 'monospace',
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerLights(BuildContext context, IndexServersState state) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        _buildServerLight(
          context,
          label: 'HTTP',
          isRunning: state.httpServerRunning,
        ),
        _buildServerLight(
          context,
          label: 'MCP',
          isRunning: state.mcpServerRunning,
        ),
      ],
    );
  }

  Widget _buildServerLight(
    BuildContext context, {
    required String label,
    required bool isRunning,
  }) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = isRunning ? Colors.green : Colors.red;
    final statusText = isRunning ? 'Running' : 'Stopped';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.2),
        ),
        const SizedBox(width: 4),
        Text(
          statusText,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.15,
          ),
        ),
      ],
    );
  }

  String _formatFileCount(int count) {
    if (count < 1000) {
      return count.toString();
    }
    if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    }
    return 'Just now';
  }

  Widget _buildFileTypeBreakdown(
    BuildContext context,
    AsyncValue<IndexFileTypeStats> stats,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return stats.when(
      loading: () => Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading file type stats...',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: muted),
          ),
        ],
      ),
      error: (_, _) => Text(
        'File type stats unavailable',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: muted),
      ),
      data: (data) {
        if (data.totalDocuments == 0 || data.rows.isEmpty) {
          return Text(
            'No file type data yet',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: muted),
          );
        }

        final rows = data.rows.take(4);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top file types',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Text(
                        row.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${row.count} (${((row.count / data.totalDocuments) * 100).toStringAsFixed(0)}%)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CardHoverLift extends StatefulWidget {
  final Widget child;

  const _CardHoverLift({required this.child});

  @override
  State<_CardHoverLift> createState() => _CardHoverLiftState();
}

class _CardHoverLiftState extends State<_CardHoverLift> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: _isHovered ? 1.012 : 1,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          offset: _isHovered ? const Offset(0, -0.012) : Offset.zero,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.shadow.withValues(alpha: 0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
