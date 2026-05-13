import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EditorToolbar extends StatelessWidget {
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onList;
  final VoidCallback onQuote;
  final VoidCallback onCode;
  final VoidCallback onImage;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onSave;
  final bool canUndo;
  final bool canRedo;

  const EditorToolbar({
    super.key,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onList,
    required this.onQuote,
    required this.onCode,
    required this.onImage,
    required this.onUndo,
    required this.onRedo,
    this.onSave,
    this.canUndo = true,
    this.canRedo = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ToolbarButton(
                  icon: Icons.format_bold,
                  onTap: onBold,
                  tooltip: '加粗',
                ),
                _ToolbarButton(
                  icon: Icons.format_italic,
                  onTap: onItalic,
                  tooltip: '斜体',
                ),
                _ToolbarButton(
                  icon: Icons.format_underline,
                  onTap: onUnderline,
                  tooltip: '下划线',
                ),
                _VerticalDivider(),
                _ToolbarButton(
                  icon: Icons.format_list_bulleted,
                  onTap: onList,
                  tooltip: '列表',
                ),
                _ToolbarButton(
                  icon: Icons.format_quote,
                  onTap: onQuote,
                  tooltip: '引用',
                ),
                _ToolbarButton(
                  icon: Icons.code,
                  onTap: onCode,
                  tooltip: '代码',
                ),
                _VerticalDivider(),
                _ToolbarButton(
                  icon: Icons.image_outlined,
                  onTap: onImage,
                  tooltip: '图片',
                ),
                const Spacer(),
                _ToolbarButton(
                  icon: Icons.undo_rounded,
                  onTap: canUndo ? onUndo : null,
                  tooltip: '撤销',
                ),
                _ToolbarButton(
                  icon: Icons.redo_rounded,
                  onTap: canRedo ? onRedo : null,
                  tooltip: '重做',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  const _ToolbarButton({
    required this.icon,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = onTap != null;
    
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 22,
              color: isEnabled
                  ? (isDark ? Colors.white70 : AppColors.textSecondary)
                  : (isDark ? Colors.white.withOpacity(0.2) : AppColors.textTertiary),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isDark ? AppColors.borderDark : AppColors.borderLight,
    );
  }
}

class EditorHeader extends StatelessWidget {
  final String saveStatus;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback? onSave;

  const EditorHeader({
    super.key,
    required this.saveStatus,
    required this.onBack,
    required this.onShare,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              size: 20,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
            onPressed: onBack,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: Container(
                key: ValueKey(saveStatus),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: saveStatus == '已保存'
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  saveStatus,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: saveStatus == '已保存'
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.share_outlined,
              size: 22,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
            onPressed: onShare,
          ),
          Container(
            margin: const EdgeInsets.only(left: 4),
            child: ElevatedButton(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '保存',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FormatButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isDark;

  const FormatButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive
          ? AppColors.primary.withOpacity(0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: isActive
                    ? AppColors.primary
                    : (isDark ? Colors.white70 : AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive
                      ? AppColors.primary
                      : (isDark ? Colors.white54 : AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ColorPickerBar extends StatelessWidget {
  final int selectedColor;
  final Function(int) onColorSelected;

  const ColorPickerBar({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      0xFFFFFFFF,
      0xFFFFF5E6,
      0xFFE8F5E9,
      0xFFE3F2FD,
      0xFFF3E5F5,
      0xFFFFEBEE,
      0xFFFFF8E1,
      0xFFE0F7FA,
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final color = Color(colors[index]);
          final isSelected = selectedColor == colors[index];
          
          return GestureDetector(
            onTap: () => onColorSelected(colors[index]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (Theme.of(context).brightness == Brightness.dark
                          ? AppColors.borderDark
                          : AppColors.borderLight),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class MoodSelector extends StatelessWidget {
  final String? selectedMood;
  final Function(String) onMoodSelected;

  const MoodSelector({
    super.key,
    this.selectedMood,
    required this.onMoodSelected,
  });

  @override
  Widget build(BuildContext context) {
    final moods = ['😊', '😢', '😠', '😴', '🤔', '😍', '😎', '🥳'];

    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: moods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mood = moods[index];
          final isSelected = selectedMood == mood;
          
          return GestureDetector(
            onTap: () => onMoodSelected(mood),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : Colors.transparent,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                mood,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ImageGallery extends StatelessWidget {
  final List<String> images;
  final Function(int) onImageTap;
  final Function(int) onImageDelete;

  const ImageGallery({
    super.key,
    required this.images,
    required this.onImageTap,
    required this.onImageDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return _ImageItem(
          imagePath: images[index],
          onTap: () => onImageTap(index),
          onDelete: () => onImageDelete(index),
        );
      },
    );
  }
}

class _ImageItem extends StatelessWidget {
  final String imagePath;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ImageItem({
    required this.imagePath,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.accentLight,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, size: 32),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
