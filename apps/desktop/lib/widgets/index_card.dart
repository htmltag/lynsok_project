import 'package:flutter/material.dart';
import 'package:desktop/models/index_model.dart';

class IndexCard extends StatelessWidget {
  final IndexModel indexModel;
  final VoidCallback onTap;

  const IndexCard({super.key, required this.indexModel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon and status
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          indexModel.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          indexModel.formattedSize,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusIndicator(context),
                ],
              ),

              const SizedBox(height: 16),

              // Stats
              Row(
                children: [
                  _buildStat(
                    context,
                    Icons.description,
                    indexModel.fileCount.toString(),
                    'files',
                  ),
                  const SizedBox(width: 16),
                  _buildStat(
                    context,
                    Icons.access_time,
                    indexModel.formattedLastModified,
                    'updated',
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Path
              Text(
                indexModel.sourcePath,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const Spacer(),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      // TODO: Start/stop server
                    },
                    icon: Icon(
                      indexModel.isServerRunning
                          ? Icons.stop
                          : Icons.play_arrow,
                      size: 16,
                    ),
                    label: Text(
                      indexModel.isServerRunning ? 'Stop' : 'Start',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      // TODO: Open menu with more actions
                    },
                    icon: const Icon(Icons.more_vert, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    Color color;
    IconData icon;
    String tooltip;

    if (indexModel.isServerRunning) {
      color = Colors.green;
      icon = Icons.circle;
      tooltip = 'Server running';
    } else if (indexModel.hasErrors) {
      color = Theme.of(context).colorScheme.error;
      icon = Icons.error;
      tooltip = 'Has errors';
    } else {
      color = Theme.of(context).colorScheme.outline;
      icon = Icons.circle_outlined;
      tooltip = 'Inactive';
    }

    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 12, color: color),
    );
  }

  Widget _buildStat(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
