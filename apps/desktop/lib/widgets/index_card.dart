import 'package:desktop/models/index_model.dart';
import 'package:flutter/material.dart';

class IndexCard extends StatelessWidget {
  final IndexModel indexModel;
  final VoidCallback onTap;

  const IndexCard({super.key, required this.indexModel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return _CardHoverLift(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (indexModel.isServerRunning) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${indexModel.formattedFileCount} Files - ${indexModel.formattedSize}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      splashRadius: 18,
                      tooltip: 'Open index',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: muted),
                    const SizedBox(width: 6),
                    Text(
                      'Last indexed: ${indexModel.formattedLastModified}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildActivityStrip(context),
                const SizedBox(height: 14),
                _buildFileTypeBreakdown(context),
                const SizedBox(height: 12),
                Text(
                  indexModel.sourcePath,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          // TODO: Connect to real process toggles.
                        },
                        icon: Icon(
                          indexModel.isServerRunning
                              ? Icons.stop
                              : Icons.play_arrow,
                          size: 14,
                        ),
                        label: Text(
                          indexModel.isServerRunning ? 'Running' : 'Start',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Trigger sync/index refresh.
                        },
                        icon: const Icon(Icons.sync, size: 14),
                        label: const Text('Sync'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityStrip(BuildContext context) {
    final values = [14, 20, 18, 24, 21, 30, 26, 34, 31, 39];
    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values
            .map(
              (v) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: v.toDouble(),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildFileTypeBreakdown(BuildContext context) {
    final rows = [
      ('TXT', 55, const Color(0xFF3B82F6)),
      ('MD', 25, const Color(0xFF60A5FA)),
      ('PDF', 15, const Color(0xFF93C5FD)),
      ('Other', 5, const Color(0xFFDBEAFE)),
    ];

    return Column(
      children: [
        for (final (name, value, color) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '$value%',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
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
