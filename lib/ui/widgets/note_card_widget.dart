import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NoteCard extends StatelessWidget {
  final String title;
  final String content;
  final String? category;
  final List<String>? tags;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final List<String>? images;

  const NoteCard({
    super.key,
    required this.title,
    required this.content,
    this.category,
    this.tags,
    required this.updatedAt,
    this.isPinned = false,
    this.isFavorite = false,
    required this.onTap,
    this.onFavoriteToggle,
    this.onDelete,
    this.onShare,
    this.images,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoryColor = _getCategoryColor(category);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Material(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: categoryColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context, isDark),
                          const SizedBox(height: 8),
                          if (title.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (content.isNotEmpty)
                            Text(
                              content,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white60 : AppColors.textSecondary,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 12),
                          _buildFooter(context, isDark),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Row(
      children: [
        if (isPinned)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.push_pin,
              size: 16,
              color: AppColors.warning,
            ),
          ),
        Expanded(
          child: Text(
            _formatDate(updatedAt),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : AppColors.textTertiary,
            ),
          ),
        ),
        _CardMenu(
          isFavorite: isFavorite,
          onFavoriteToggle: onFavoriteToggle,
          onDelete: onDelete,
          onShare: onShare,
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return Row(
      children: [
        if (tags != null && tags!.isNotEmpty) ...[
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tags!.take(3).map((tag) => _MiniTag(label: tag)).toList(),
            ),
          ),
        ],
        if (images != null && images!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 14,
                  color: isDark ? Colors.white38 : AppColors.textTertiary,
                ),
                const SizedBox(width: 2),
                Text(
                  '${images!.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _getCategoryColor(String? category) {
    if (category == null) return AppColors.primary;
    return AppColors.categoryColors[category] ?? AppColors.primary;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}

class _CardMenu extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;

  const _CardMenu({
    required this.isFavorite,
    this.onFavoriteToggle,
    this.onDelete,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz,
        size: 20,
        color: Theme.of(context).brightness == Brightness.dark 
            ? Colors.white38 
            : AppColors.textTertiary,
      ),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                size: 20,
                color: isFavorite ? AppColors.danger : null,
              ),
              const SizedBox(width: 12),
              Text(isFavorite ? '取消收藏' : '收藏'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              const Icon(Icons.share_outlined, size: 20),
              const SizedBox(width: 12),
              const Text('分享'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
              const SizedBox(width: 12),
              Text('删除', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'favorite':
            onFavoriteToggle?.call();
            break;
          case 'share':
            onShare?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;

  const _MiniTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.accentDark : AppColors.accentLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white70 : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class NoteGridCard extends StatelessWidget {
  final String title;
  final String? preview;
  final String? category;
  final DateTime updatedAt;
  final bool isPinned;
  final VoidCallback onTap;

  const NoteGridCard({
    super.key,
    required this.title,
    this.preview,
    this.category,
    required this.updatedAt,
    this.isPinned = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoryColor = _getCategoryColor(category);

    return Material(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: categoryColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isPinned)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.push_pin,
                                size: 14,
                                color: AppColors.warning,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (preview != null && preview!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            preview!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : AppColors.textTertiary,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String? category) {
    if (category == null) return AppColors.primary;
    return AppColors.categoryColors[category] ?? AppColors.primary;
  }
}
