import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'services/share_service.dart';
import 'pages/share_import_page.dart';
import 'pages/settings_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/note_card_widget.dart';
import 'ui/widgets/home_page_widgets.dart';
import 'ui/widgets/navigation_widgets.dart';
import 'ui/widgets/editor_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const YeahApp());
}

class YeahApp extends StatefulWidget {
  const YeahApp({super.key});

  @override
  State<YeahApp> createState() => _YeahAppState();
}

class _YeahAppState extends State<YeahApp> {
  AppThemeConfig _currentTheme = ThemeService.appThemes[0];
  ShareData? _pendingShareData;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initShareListener();
  }

  void _initShareListener() {
    ShareService().initializeShareListener((shareData) {
      setState(() {
        _pendingShareData = shareData;
      });
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      ShareData? data = ShareService().getPendingShareData();
      if (data != null && mounted) {
        _navigateToShareImport(data);
      }
    });
  }

  void _navigateToShareImport(ShareData data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ShareImportPage(shareData: data)),
    );
    if (result == true) {
      setState(() {
        _pendingShareData = null;
      });
    }
  }

  Future<void> _loadTheme() async {
    final theme = await ThemeService.loadSavedTheme();
    if (mounted) {
      setState(() {
        _currentTheme = theme;
      });
    }
  }

  void _changeTheme(AppThemeConfig theme) async {
    await ThemeService.saveTheme(theme.id);
    setState(() {
      _currentTheme = theme;
    });
  }

  @override
  void dispose() {
    ShareService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'yeah',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: NoteHomePage(
        onThemeChanged: _changeTheme,
        currentTheme: _currentTheme,
      ),
    );
  }
}

class NoteHomePage extends StatefulWidget {
  final Function(AppThemeConfig) onThemeChanged;
  final AppThemeConfig currentTheme;

  const NoteHomePage({
    super.key,
    required this.onThemeChanged,
    required this.currentTheme,
  });

  @override
  State<NoteHomePage> createState() => _NoteHomePageState();
}

class _NoteHomePageState extends State<NoteHomePage> with TickerProviderStateMixin {
  final List<Note> _notes = [];
  List<Note> _filteredNotes = [];
  String _searchQuery = '';
  bool _isLoading = true;
  ViewMode _viewMode = ViewMode.grid;
  String _sortBy = 'date';
  final Set<String> _selectedTags = {};
  DateTime? _lastBackupDate;
  List<String> _searchHistory = [];
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String? _filterMood;
  bool _showAdvancedFilters = false;
  
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _checkBackupReminder();
  }

  Future<void> _checkBackupReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackup = prefs.getString('lastBackupDate');
    if (lastBackup != null) {
      _lastBackupDate = DateTime.tryParse(lastBackup);
    }
    
    if (_lastBackupDate == null || 
        DateTime.now().difference(_lastBackupDate!).inDays >= 7) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showBackupReminder();
      });
    }
  }

  void _showBackupReminder() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.backup, color: Colors.orange),
            SizedBox(width: 8),
            Text('备份提醒'),
          ],
        ),
        content: const Text('您已经超过7天没有备份笔记了，建议定期备份以防止数据丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportNotes();
            },
            child: const Text('立即备份'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotes() async {
    debugPrint('=== [DEBUG] _loadNotes: 开始加载笔记 ===');
    try {
      final notes = await DatabaseService.getAllNotes();
      debugPrint('=== [DEBUG] _loadNotes: 从数据库加载了 ${notes.length} 条笔记 ===');
      setState(() {
        _notes.clear();
        _notes.addAll(notes);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载笔记失败: $e');
      setState(() {
        _notes.clear();
        _applyFilters();
        _isLoading = false;
      });
    }
    await _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('searchHistory');
      if (history != null) {
        setState(() {
          _searchHistory = history;
        });
      }
    } catch (e) {
      debugPrint('加载搜索历史失败: $e');
    }
  }

  Future<void> _saveSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('searchHistory', _searchHistory);
    } catch (e) {
      debugPrint('保存搜索历史失败: $e');
    }
  }

  void _addToSearchHistory(String query) {
    if (query.isEmpty) return;
    if (_searchHistory.contains(query)) {
      _searchHistory.remove(query);
    }
    _searchHistory.insert(0, query);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    _saveSearchHistory();
  }

  void _clearSearchHistory() {
    setState(() {
      _searchHistory.clear();
    });
    _saveSearchHistory();
    _showSnackBar('🗑️ 搜索历史已清除', Icons.delete_sweep, Colors.grey);
  }

  bool _demoNotesAdded = false;

  void _addDemoNotes() {
    if (_demoNotesAdded) return;
    _demoNotesAdded = true;
    
    final demoNotes = [
      Note(
        id: 'demo_${DateTime.now().millisecondsSinceEpoch}_1',
        title: '🎨 设计灵感',
        content: '好的设计是尽可能少的设计。让功能自然而然地呈现，而不是堆砌。',
        color: 0xFFFFF5E6,
        tags: ['设计', '灵感'],
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isFavorite: true,
        mood: '✨',
      ),
      Note(
        id: 'demo_${DateTime.now().millisecondsSinceEpoch}_2',
        title: '💡 产品思考',
        content: '用户需要的是简单易用的产品，而不是功能复杂的技术展示。',
        color: 0xFFE6F7FF,
        tags: ['产品', '思考'],
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        mood: '💡',
      ),
      Note(
        id: 'demo_${DateTime.now().millisecondsSinceEpoch}_3',
        title: '📋 本周任务',
        content: '1. 完成核心功能开发\n2. 优化用户体验\n3. 收集用户反馈',
        color: 0xFFF6FFED,
        tags: ['任务'],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        mood: '🎯',
      ),
    ];
    _notes.addAll(demoNotes);
    _applyFilters();
    _saveNotes();
  }

  Future<void> _saveNotes() async {
    try {
      for (final note in _notes) {
        await DatabaseService.insertNote(note);
      }
    } catch (e) {
      debugPrint('保存笔记失败: $e');
    }
  }

  void _applyFilters() {
    _filteredNotes = _notes.where((note) {
      final searchLower = _searchQuery.toLowerCase().trim();
      bool matchesSearch = true;
      
      if (searchLower.isNotEmpty) {
        final searchTerms = searchLower.split(' ');
        matchesSearch = searchTerms.every((term) {
          if (term.isEmpty) return true;
          return note.title.toLowerCase().contains(term) ||
                 note.content.toLowerCase().contains(term) ||
                 note.tags.any((tag) => tag.toLowerCase().contains(term));
        });
      }
      
      final matchesTags = _selectedTags.isEmpty ||
          _selectedTags.every((tag) => note.tags.contains(tag));
      
      bool matchesDate = true;
      if (_filterStartDate != null) {
        matchesDate = matchesDate && 
          (note.createdAt.isAfter(_filterStartDate!) || 
           note.createdAt.isAtSameMomentAs(_filterStartDate!));
      }
      if (_filterEndDate != null) {
        matchesDate = matchesDate && 
          note.createdAt.isBefore(_filterEndDate!.add(const Duration(days: 1)));
      }
      
      bool matchesMood = true;
      if (_filterMood != null && _filterMood!.isNotEmpty) {
        matchesMood = note.mood == _filterMood;
      }
      
      return matchesSearch && matchesTags && matchesDate && matchesMood;
    }).toList();

    switch (_sortBy) {
      case 'date':
        _filteredNotes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'name':
        _filteredNotes.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'favorite':
        _filteredNotes.sort((a, b) {
          if (a.isFavorite && !b.isFavorite) return -1;
          if (!a.isFavorite && b.isFavorite) return 1;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _applyFilters();
    });
  }

  void _onSearchSubmitted(String value) {
    if (value.isNotEmpty) {
      _addToSearchHistory(value);
    }
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _selectedTags.clear();
      _filterStartDate = null;
      _filterEndDate = null;
      _filterMood = null;
      _applyFilters();
    });
    _showSnackBar('🔄 筛选条件已清除', Icons.filter_alt_off, Colors.blue);
  }

  Set<String> get _allTags {
    final tags = <String>{};
    for (final note in _notes) {
      tags.addAll(note.tags);
    }
    return tags;
  }

  Map<String, dynamic> get _stats {
    final totalNotes = _notes.length;
    final favoriteNotes = _notes.where((n) => n.isFavorite).length;
    final allTags = _allTags.length;
    final now = DateTime.now();
    final todayNotes = _notes.where((n) => 
      n.createdAt.year == now.year &&
      n.createdAt.month == now.month &&
      n.createdAt.day == now.day
    ).length;
    return {
      'total': totalNotes,
      'favorite': favoriteNotes,
      'tags': allTags,
      'today': todayNotes,
    };
  }

  void _addNote() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TemplateSelectorSheet(
        onSelectTemplate: (template) {
          Navigator.pop(context);
          _navigateToEditor(template.createNote());
        },
        onSkip: () {
          Navigator.pop(context);
          _navigateToEditor(null);
        },
      ),
    );
  }

  void _navigateToEditor(Note? note) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => NoteEditorPage(
          note: note,
          isFromTemplate: note != null,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutQuart,
            reverseCurve: Curves.easeInQuart,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ).then((newNote) {
      if (newNote != null && newNote is Note) {
        setState(() {
          _notes.insert(0, newNote);
          _applyFilters();
        });
        _showSnackBar('✨ 笔记已创建', Icons.check_circle, Colors.green);
      }
    });
  }

  void _editNote(Note note) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => NoteEditorPage(note: note),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
    ).then((updatedNote) {
      if (updatedNote != null && updatedNote is Note) {
        setState(() {
          final index = _notes.indexWhere((n) => n.id == updatedNote.id);
          if (index != -1) {
            _notes[index] = updatedNote;
            _applyFilters();
          }
        });
        _showSnackBar('📝 笔记已更新', Icons.edit, Colors.blue);
      }
    });
  }

  Future<void> _deleteNote(Note note, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记？'),
        content: Text('确定要删除笔记「${note.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final deletedNote = note;
    final originalIndex = _notes.indexWhere((n) => n.id == note.id);
    
    setState(() {
      _notes.removeWhere((n) => n.id == note.id);
      _applyFilters();
    });
    
    try {
      await DatabaseService.deleteNote(note.id);
    } catch (e) {
      debugPrint('数据库删除失败: $e');
    }
    
    try {
      for (final imagePath in note.images) {
        await DatabaseService.deleteImage(imagePath);
      }
    } catch (e) {
      debugPrint('删除图片失败: $e');
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Icon(Icons.delete_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              const Text('笔记已删除'),
            ],
          ),
          action: SnackBarAction(
            label: '撤销',
            textColor: Colors.white,
            onPressed: () async {
              if (mounted) {
                setState(() {
                  _notes.insert(originalIndex.clamp(0, _notes.length), deletedNote);
                  _applyFilters();
                });
                await _saveNotes();
                _showSnackBar('笔记已恢复', Icons.restore, Colors.green);
              }
            },
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.grey[800],
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _toggleFavorite(Note note) async {
    final updatedNote = note.copyWith(isFavorite: !note.isFavorite);
    
    setState(() {
      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index != -1) {
        _notes[index] = updatedNote;
        _applyFilters();
      }
    });
    
    try {
      await DatabaseService.updateNote(updatedNote);
    } catch (e) {
      debugPrint('数据库更新失败: $e');
    }
    
    await _saveNotes();
    _showSnackBar(
      note.isFavorite ? '⭐ 取消收藏' : '⭐ 已收藏',
      note.isFavorite ? Icons.star_border : Icons.star,
      note.isFavorite ? Colors.grey : Colors.amber,
    );
  }

  void _showSnackBar(String message, IconData icon, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ThemeSelectorSheet(
        currentTheme: widget.currentTheme,
        onSelectTheme: (theme) {
          Navigator.pop(context);
          widget.onThemeChanged(theme);
          _showSnackBar('✨ 已切换到${theme.icon} ${theme.name}', Icons.check_circle, theme.primaryColor);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingScreen(isDark)
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildNewHeader()),
                  SliverToBoxAdapter(child: const SizedBox(height: 16)),
                  _buildQuickActions(),
                  SliverToBoxAdapter(child: const SizedBox(height: 16)),
                  _buildTagSection(),
                  SliverToBoxAdapter(child: const SizedBox(height: 8)),
                  _buildNotesList(isDark),
                ],
              ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _buildNewFab(),
      bottomNavigationBar: CustomBottomNavigation(
        currentIndex: 0,
        onTap: (index) => _handleNavigation(index),
      ),
    );
  }

  Widget _buildLoadingScreen(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(seconds: 1),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.edit_note,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'yeah',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagFilter(bool isDark) {
    final tags = _allTags.toList();
    if (tags.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '🏷️ 标签筛选',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tags.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('全部'),
                        selected: _selectedTags.isEmpty,
                        selectedColor: const Color(0xFF6366F1),
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _selectedTags.isEmpty ? Colors.white : (isDark ? Colors.white70 : Colors.grey[700]),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        onSelected: (selected) {
                          setState(() {
                            _selectedTags.clear();
                            _applyFilters();
                          });
                        },
                      ),
                    );
                  }
                  final tag = tags[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(tag),
                      selected: _selectedTags.contains(tag),
                      selectedColor: const Color(0xFF6366F1),
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _selectedTags.contains(tag) ? Colors.white : (isDark ? Colors.white70 : Colors.grey[700]),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedTags.add(tag);
                          } else {
                            _selectedTags.remove(tag);
                          }
                          _applyFilters();
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesList(bool isDark) {
    if (_filteredNotes.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Icon(
                      Icons.lightbulb_outline,
                      size: 80,
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                _searchQuery.isNotEmpty ? '没有找到相关笔记' : '还没有笔记',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty ? '试试其他关键词' : '点击下方按钮开始记录',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: _viewMode == ViewMode.grid
          ? _buildGridView(isDark)
          : _viewMode == ViewMode.list
              ? _buildListView(isDark)
              : _buildCompactListView(isDark),
    );
  }

  Widget _buildGridView(bool isDark) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildAnimatedCard(index, isDark),
        childCount: _filteredNotes.length,
      ),
    );
  }

  Widget _buildListView(bool isDark) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildAnimatedListItem(index, isDark),
        ),
        childCount: _filteredNotes.length,
      ),
    );
  }

  Widget _buildCompactListView(bool isDark) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildCompactItem(index, isDark),
        ),
        childCount: _filteredNotes.length,
      ),
    );
  }

  Widget _buildAnimatedCard(int index, bool isDark) {
    final note = _filteredNotes[index];
    return AnimatedListItem(
      index: index,
      child: NoteGridCard(
        title: note.title.isNotEmpty ? note.title : '无标题',
        preview: note.content.isNotEmpty ? note.content : null,
        category: note.category,
        updatedAt: note.createdAt is DateTime 
            ? note.createdAt 
            : DateTime.tryParse(note.createdAt.toString()) ?? DateTime.now(),
        isPinned: note.isPinned,
        onTap: () => _editNote(note),
      ),
    );
  }

  Widget _buildAnimatedListItem(int index, bool isDark) {
    final note = _filteredNotes[index];
    return AnimatedListItem(
      index: index,
      child: NoteCard(
        title: note.title.isNotEmpty ? note.title : '无标题',
        content: note.content,
        category: note.category,
        tags: note.tags,
        updatedAt: note.createdAt is DateTime 
            ? note.createdAt 
            : DateTime.tryParse(note.createdAt.toString()) ?? DateTime.now(),
        isPinned: note.isPinned,
        isFavorite: note.isFavorite,
        images: note.images,
        onTap: () => _editNote(note),
        onFavoriteToggle: () => _toggleFavorite(note),
        onDelete: () => _deleteNote(note, index),
        onShare: () => _shareNote(note),
      ),
    );
  }

  Widget _buildCompactItem(int index, bool isDark) {
    final note = _filteredNotes[index];
    return NoteCard(
      title: note.title.isNotEmpty ? note.title : '无标题',
      content: note.content,
      category: note.category,
      tags: note.tags,
      updatedAt: note.createdAt is DateTime 
          ? note.createdAt 
          : DateTime.tryParse(note.createdAt.toString()) ?? DateTime.now(),
      isPinned: note.isPinned,
      isFavorite: note.isFavorite,
      images: note.images,
      onTap: () => _editNote(note),
      onFavoriteToggle: () => _toggleFavorite(note),
      onDelete: () => _deleteNote(note, index),
      onShare: () => _shareNote(note),
    );
  }

  Widget _buildNewHeader() {
    return HomeHeader(
      onSearchTap: _showSearch,
      onSettingsTap: _showSettings,
      userName: '用户',
    );
  }

  Widget _buildQuickActions() {
    return SliverToBoxAdapter(
      child: QuickActionsRow(
        onActionTap: (index) {
          switch (index) {
            case 0:
              _addNote();
              break;
            case 1:
              _filterByFavorite();
              break;
            case 2:
              _showTagsPage();
              break;
            case 3:
              _showCategoriesPage();
              break;
          }
        },
      ),
    );
  }

  Widget _buildTagSection() {
    final allTags = _allTags;
    return SliverToBoxAdapter(
      child: Column(
        children: [
          SectionHeader(
            title: '标签',
            icon: Icons.label_outline_rounded,
          ),
          TagsRow(
            tags: allTags.take(10).toList(),
            onTagTap: (tag) {
              setState(() {
                if (_selectedTags.contains(tag)) {
                  _selectedTags.remove(tag);
                } else {
                  _selectedTags.add(tag);
                }
                _applyFilters();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNewFab() {
    return ScaleTapEffect(
      onTap: _addNote,
      child: CustomFAB(
        onPressed: _addNote,
        label: '新建笔记',
        icon: Icons.add_rounded,
      ),
    );
  }

  void _handleNavigation(int index) {
    switch (index) {
      case 0:
        // 首页
        break;
      case 1:
        // 笔记列表
        break;
      case 2:
        _filterByFavorite();
        break;
      case 3:
        _showTagsPage();
        break;
      case 4:
        _showSettings();
        break;
    }
  }

  void _showSearch() {
    showSearch(context: context, delegate: NoteSearchDelegate(_notes, (note) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NoteEditorPage(note: note)),
      );
    }));
  }

  void _showSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  void _showTagsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TagsPage()),
    );
  }

  void _showCategoriesPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CategoryPage()),
    );
  }

  void _filterByFavorite() {
    setState(() {
      _filteredNotes = _notes.where((note) => note.isFavorite).toList();
    });
  }

  void _shareNote(Note note) {
    ShareService().shareNote(
      note.title.isNotEmpty ? note.title : '无标题',
      note.content,
      note.images,
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了，早点休息 🌙';
    if (hour < 12) return '早上好，新的一天 ☀️';
    if (hour < 14) return '中午好，休息一下 ☀️';
    if (hour < 18) return '下午好，工作顺利 🌤️';
    if (hour < 22) return '晚上好，放松一下 🌙';
    return '夜深了，早点休息 🌙';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportNotes() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'yeah_backup_$timestamp.json';
      final file = File('${directory.path}/$fileName');
      
      final exportData = {
        'version': '5.0.4',
        'exportDate': DateTime.now().toIso8601String(),
        'notesCount': _notes.length,
        'notes': _notes.map((n) => n.toJson()).toList(),
      };
      
      await file.writeAsString(json.encode(exportData));
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastBackupDate', DateTime.now().toIso8601String());
      _lastBackupDate = DateTime.now();
      
      if (mounted) {
        _showSnackBar('✅ 导出成功！文件已保存', Icons.check_circle, Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('❌ 导出失败：${e.toString()}', Icons.error, Colors.red);
      }
    }
  }

  Future<void> _importNotes() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final data = json.decode(content);

      if (!data.containsKey('notes') || data['notes'] == null) {
        if (mounted) {
          _showSnackBar('❌ 文件格式错误', Icons.error, Colors.red);
        }
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入笔记'),
          content: Text('将导入 ${(data['notes'] as List).length} 条笔记。\n\n是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final importedNotes = (data['notes'] as List).map((json) {
        final oldNote = Note.fromJson(json);
        final newId = '${DateTime.now().millisecondsSinceEpoch}_${oldNote.id}';
        return Note(
          id: newId,
          title: oldNote.title,
          content: oldNote.content,
          color: oldNote.color,
          tags: oldNote.tags,
          createdAt: oldNote.createdAt,
          isFavorite: false,
          mood: oldNote.mood,
          images: oldNote.images,
        );
      }).toList();

      for (final note in importedNotes) {
        await DatabaseService.insertNote(note);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastBackupDate', DateTime.now().toIso8601String());
      _lastBackupDate = DateTime.now();

      setState(() {
        _notes.addAll(importedNotes);
        _applyFilters();
      });

      if (mounted) {
        _showSnackBar('✅ 成功导入 ${importedNotes.length} 条笔记', Icons.check_circle, Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('❌ 导入失败：${e.toString()}', Icons.error, Colors.red);
      }
    }
  }
}

class _ThemeSelectorSheet extends StatelessWidget {
  final AppThemeConfig currentTheme;
  final Function(AppThemeConfig) onSelectTheme;

  const _ThemeSelectorSheet({
    required this.currentTheme,
    required this.onSelectTheme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themes = ThemeService.appThemes;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎨 选择主题',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '个性化你的应用外观',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: themes.length,
              itemBuilder: (context, index) {
                final theme = themes[index];
                final isSelected = theme.id == currentTheme.id;
                return _ThemeCard(
                  theme: theme,
                  isSelected: isSelected,
                  isDark: isDark,
                  onTap: () => onSelectTheme(theme),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppThemeConfig theme;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.theme,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: theme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? theme.primaryColor : (isDark ? Colors.white12 : Colors.grey[200]!),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: theme.primaryColor.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                theme.icon,
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(height: 8),
              Text(
                theme.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 4),
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: theme.primaryColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateSelectorSheet extends StatelessWidget {
  final Function(NoteTemplate) onSelectTemplate;
  final VoidCallback onSkip;

  const _TemplateSelectorSheet({
    required this.onSelectTemplate,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final templates = NoteTemplateService.getTemplates();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '✨ 选择模板',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    TextButton(
                      onPressed: onSkip,
                      child: Text(
                        '跳过',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '选择一个模板快速开始',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                return _TemplateCard(
                  template: template,
                  onTap: () => onSelectTemplate(template),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final NoteTemplate template;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Color(template.color).withOpacity(isDark ? 0.3 : 1.0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey[200]!,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    template.icon,
                    style: const TextStyle(fontSize: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      template.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  template.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: template.defaultTags.take(3).map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteEditorPage extends StatefulWidget {
  final Note? note;
  final bool isFromTemplate;

  const NoteEditorPage({
    super.key,
    this.note,
    this.isFromTemplate = false,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> with SingleTickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  int _selectedColor = 0xFFFFF5E6;
  final List<String> _tags = [];
  String _selectedMood = '';
  bool _isSaved = true;
  Timer? _autoSaveTimer;
  bool _showFormattingBar = false;
  final List<String> _images = [];
  
  final List<int> _colors = [
    0xFFFFF5E6, 0xFFE6F7FF, 0xFFF6FFED, 0xFFFFF0E6, 0xFFF0E6FF,
    0xFFFFE6E6, 0xFFE6FFE6, 0xFFE6FFFF,
  ];

  final List<Map<String, String>> _moods = [
    {'emoji': '✨', 'label': '灵感'},
    {'emoji': '💡', 'label': '想法'},
    {'emoji': '🎯', 'label': '目标'},
    {'emoji': '📝', 'label': '记录'},
    {'emoji': '💭', 'label': '思考'},
    {'emoji': '🔥', 'label': '热血'},
    {'emoji': '🎨', 'label': '创意'},
    {'emoji': '📚', 'label': '学习'},
  ];
  
  late AnimationController _colorAnimationController;

  @override
  void initState() {
    super.initState();
    _colorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _colorAnimationController.forward();
    
    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _contentController.text = widget.note!.content;
      _selectedColor = widget.note!.color;
      _tags.addAll(widget.note!.tags);
      _selectedMood = widget.note!.mood;
      _images.addAll(widget.note!.images);
    }
    
    _titleController.addListener(_onContentChanged);
    _contentController.addListener(_onContentChanged);
    _contentFocusNode.addListener(_onFocusChanged);
    
    _colorAnimationController.forward();
  }

  void _onFocusChanged() {
    setState(() {
      _showFormattingBar = _contentFocusNode.hasFocus;
    });
  }

  void _onContentChanged() {
    if (_isSaved) {
      setState(() => _isSaved = false);
    }
    _startAutoSaveTimer();
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.note != null) {
        _saveNote(silent: true);
      }
    });
  }

  void _applyFormatting(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    if (selection.start == selection.end) {
      final newText = text.substring(0, selection.start) + 
                     prefix + suffix + 
                     text.substring(selection.start);
      _contentController.text = newText;
      _contentController.selection = TextSelection.collapsed(
        offset: selection.start + prefix.length,
      );
    } else {
      final selectedText = text.substring(selection.start, selection.end);
      final newText = text.substring(0, selection.start) + 
                     prefix + selectedText + suffix + 
                     text.substring(selection.end);
      _contentController.text = newText;
      _contentController.selection = TextSelection(
        baseOffset: selection.start + prefix.length,
        extentOffset: selection.start + prefix.length + selectedText.length,
      );
    }
    _onContentChanged();
  }

  void _insertBulletPoint() {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final cursorPos = selection.start;
    
    int lineStart = cursorPos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    
    final newText = text.substring(0, lineStart) + '• ' + text.substring(lineStart);
    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(
      offset: cursorPos + 2,
    );
    _onContentChanged();
  }

  Future<void> _addImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedPath = path.join(directory.path, 'images', fileName);
        
        final imageDir = Directory(path.join(directory.path, 'images'));
        if (!await imageDir.exists()) {
          await imageDir.create(recursive: true);
        }
        
        await File(image.path).copy(savedPath);
        
        setState(() {
          _images.add(savedPath);
        });
        
        final text = _contentController.text;
        final selection = _contentController.selection;
        final newText = text.substring(0, selection.start) + 
                       '[图片]\n' + 
                       text.substring(selection.start);
        _contentController.text = newText;
        _onContentChanged();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✅ 图片已添加'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 添加图片失败: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _removeImage(int index) async {
    if (index < 0 || index >= _images.length) return;
    
    final imagePath = _images[index];
    setState(() {
      _images.removeAt(index);
    });
    
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除图片文件失败: $e');
    }
    
    final content = _contentController.text;
    final imageMarker = '[图片]';
    int markerCount = 0;
    int removeStart = -1;
    int removeEnd = -1;
    
    for (int i = 0; i < content.length; i++) {
      if (content.substring(i).startsWith(imageMarker)) {
        markerCount++;
        if (markerCount == index + 1) {
          removeStart = i;
          removeEnd = i + imageMarker.length;
          while (removeEnd < content.length && content[removeEnd] == '\n') {
            removeEnd++;
          }
          break;
        }
      }
    }
    
    if (removeStart != -1) {
      _contentController.text = content.substring(0, removeStart) + content.substring(removeEnd);
    }
  }

  Future<void> _saveNote({bool silent = false}) async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    
    if (title.isEmpty && content.isEmpty) {
      if (!silent) Navigator.pop(context);
      return;
    }

    final note = Note(
      id: widget.note?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.isEmpty ? '💭 无标题笔记' : title,
      content: content,
      color: _selectedColor,
      tags: _tags,
      createdAt: widget.note?.createdAt ?? DateTime.now(),
      isFavorite: widget.note?.isFavorite ?? false,
      mood: _selectedMood,
      images: _images,
    );

    debugPrint('=== [DEBUG] _saveNote: 创建的 Note 对象 ===');
    debugPrint('  - id: ${note.id}');
    debugPrint('  - title: ${note.title}');
    
    try {
      if (widget.note == null || widget.isFromTemplate) {
        debugPrint('  - 调用 insertNote');
        await DatabaseService.insertNote(note);
      } else {
        debugPrint('  - 调用 updateNote');
        await DatabaseService.updateNote(note);
      }
    } catch (e) {
      debugPrint('数据库保存失败: $e');
    }

    setState(() => _isSaved = true);
    
    Navigator.pop(context, note);
  }

  Future<void> _shareNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    await ShareService().shareNote(
      title.isEmpty ? '无标题笔记' : title,
      content,
      _images,
    );
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('标签 "$tag" 已存在'),
              ],
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 12),
              Text('已添加标签: $tag'),
            ],
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              const SizedBox(width: 12),
              Text('已删除标签: $tag'),
            ],
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _isSaved || (_titleController.text.trim().isEmpty && _contentController.text.trim().isEmpty),
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        final shouldSave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('是否保存笔记？'),
            content: const Text('你有未保存的更改，是否保存？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('不保存'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
        
        if (shouldSave == true) {
          _saveNote();
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Color(_selectedColor),
        body: SafeArea(
          child: Column(
            children: [
              EditorHeader(
                saveStatus: _isSaved ? '已保存' : '编辑中...',
                onBack: () {
                  Navigator.pop(context, _isSaved ? widget.note : null);
                },
                onShare: _shareNote,
                onSave: _saveNote,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: '给笔记起个标题...',
                          border: InputBorder.none,
                          hintStyle: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[400],
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                        autofocus: widget.note == null,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _contentController,
                        focusNode: _contentFocusNode,
                        decoration: InputDecoration(
                          hintText: '开始记录...',
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Colors.grey[400]),
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: Color(0xFF333333),
                        ),
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                      ),
                      const SizedBox(height: 16),
                      if (_images.isNotEmpty) ...[
                        ImageGallery(
                          images: _images,
                          onImageTap: (index) {},
                          onImageDelete: (index) => _removeImage(index),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              EditorToolbar(
                onBold: () => _applyFormatting('**', '**'),
                onItalic: () => _applyFormatting('*', '*'),
                onUnderline: () => _applyFormatting('__', '__'),
                onList: () => _applyFormatting('- ', ''),
                onQuote: () => _applyFormatting('> ', ''),
                onCode: () => _applyFormatting('`', '`'),
                onImage: _addImage,
                onUndo: () {},
                onRedo: () {},
                onSave: _saveNote,
                canUndo: true,
                canRedo: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.removeListener(_onContentChanged);
    _contentController.removeListener(_onContentChanged);
    _contentFocusNode.removeListener(_onFocusChanged);
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _contentFocusNode.dispose();
    _colorAnimationController.dispose();
    _autoSaveTimer?.cancel();
    super.dispose();
  }
}

class Note {
  final String id;
  final String title;
  final String content;
  final int color;
  final List<String> tags;
  final DateTime createdAt;
  final bool isFavorite;
  final String mood;
  final List<String> images;
  final String category;
  final bool isPinned;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.color,
    required this.tags,
    required this.createdAt,
    this.isFavorite = false,
    this.mood = '',
    this.images = const [],
    this.category = '',
    this.isPinned = false,
  });

  Note copyWith({
    String? id,
    String? title,
    String? content,
    int? color,
    List<String>? tags,
    DateTime? createdAt,
    bool? isFavorite,
    String? mood,
    List<String>? images,
    String? category,
    bool? isPinned,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      color: color ?? this.color,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      mood: mood ?? this.mood,
      images: images ?? this.images,
      category: category ?? this.category,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'color': color,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'isFavorite': isFavorite,
        'mood': mood,
        'images': images,
        'category': category,
        'isPinned': isPinned,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    List<String> tagsList = [];
    if (json['tags'] is String) {
      try {
        tagsList = List<String>.from(jsonDecode(json['tags']));
      } catch (e) {
        tagsList = [];
      }
    } else if (json['tags'] is List) {
      tagsList = List<String>.from(json['tags']);
    }
    
    List<String> imagesList = [];
    if (json['images'] is String) {
      try {
        imagesList = List<String>.from(jsonDecode(json['images']));
      } catch (e) {
        imagesList = [];
      }
    } else if (json['images'] is List) {
      imagesList = List<String>.from(json['images']);
    }
    
    return Note(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      color: json['color'] as int? ?? 0xFFFFF5E6,
      tags: tagsList,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) ?? DateTime.now() : DateTime.now(),
      isFavorite: json['isFavorite'] == 1 || json['isFavorite'] == true,
      mood: json['mood'] as String? ?? '',
      images: imagesList,
      category: json['category'] as String? ?? '',
      isPinned: json['isPinned'] == 1 || json['isPinned'] == true,
    );
  }
}

class NoteTemplate {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int color;
  final String title;
  final String content;
  final List<String> defaultTags;
  final String mood;

  const NoteTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.title,
    required this.content,
    required this.defaultTags,
    required this.mood,
  });

  Note createNote() {
    return Note(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      color: color,
      tags: List<String>.from(defaultTags),
      createdAt: DateTime.now(),
      mood: mood,
    );
  }
}

class NoteTemplateService {
  static List<NoteTemplate> getTemplates() {
    return defaultTemplates;
  }

  static const List<NoteTemplate> defaultTemplates = [
    NoteTemplate(
      id: 'diary',
      name: '日记',
      description: '记录一天的心情和事件',
      icon: '📔',
      color: 0xFFFFF5E6,
      title: '', // 将在运行时动态生成
      content: '📅 今日日期：\n🌤️ 今日心情：\n📝 今日收获：\n✨ 明日计划：',
      defaultTags: ['日记'],
      mood: '✨',
    ),
    NoteTemplate(
      id: 'todo',
      name: '待办事项',
      description: '记录需要完成的任务',
      icon: '📋',
      color: 0xFFF6FFED,
      title: '待办事项',
      content: '🔴 紧急：\n1. \n2. \n🟡 重要：\n1. \n2. \n🟢 一般：\n1. \n2.',
      defaultTags: ['任务'],
      mood: '🎯',
    ),
    NoteTemplate(
      id: 'meeting',
      name: '会议记录',
      description: '记录会议要点和结论',
      icon: '📊',
      color: 0xFFE6F7FF,
      title: '会议记录',
      content: '📅 时间：\n📍 地点：\n👥 参会：\n📋 主题：\n🔍 讨论：\n✅ 结论：',
      defaultTags: ['会议'],
      mood: '💡',
    ),
    NoteTemplate(
      id: 'study',
      name: '学习笔记',
      description: '记录学习内容和心得',
      icon: '📚',
      color: 0xFFF0E6FF,
      title: '学习笔记',
      content: '📖 主题：\n📅 日期：\n📝 知识点：\n1. \n2. \n💡 感悟：\n❓ 疑问：',
      defaultTags: ['学习'],
      mood: '📚',
    ),
    NoteTemplate(
      id: 'idea',
      name: '灵感记录',
      description: '快速记录突然的想法',
      icon: '💡',
      color: 0xFFFFE6E6,
      title: '💡 灵感记录',
      content: '💡 描述：\n🎯 应用：\n👥 用户：\n⭐ 价值：\n🔧 方案：',
      defaultTags: ['灵感', '创意'],
      mood: '💡',
    ),
    NoteTemplate(
      id: 'reading',
      name: '读书笔记',
      description: '记录阅读心得和摘要',
      icon: '📖',
      color: 0xFFE6FFFF,
      title: '读书笔记',
      content: '📚 书名：\n✍️ 作者：\n📅 日期：\n💬 金句：\n📝 感悟：',
      defaultTags: ['读书'],
      mood: '📚',
    ),
    NoteTemplate(
      id: 'work',
      name: '工作日志',
      description: '记录每日工作内容',
      icon: '💼',
      color: 0xFFE6FFE6,
      title: '工作日志',
      content: '📅 日期：\n📌 完成：\n1. \n2. \n🔄 进行中：\n📋 明日计划：',
      defaultTags: ['工作'],
      mood: '💼',
    ),
    NoteTemplate(
      id: 'health',
      name: '健康追踪',
      description: '记录健康状况和生活习惯',
      icon: '🏃',
      color: 0xFFF6FFED,
      title: '健康日志',
      content: '📅 日期：\n😴 睡眠：\n🏃 运动：\n🍎 饮食：\n😊 心情：',
      defaultTags: ['健康'],
      mood: '🏃',
    ),
  ];
}

enum ViewMode { grid, list, compact }

class AppThemeConfig {
  final String id;
  final String name;
  final String icon;
  final Color primaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Brightness brightness;

  const AppThemeConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.primaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.brightness,
  });
}

class ThemeService {
  static const List<AppThemeConfig> appThemes = [
    AppThemeConfig(
      id: 'default',
      name: '默认紫',
      icon: '💜',
      primaryColor: Color(0xFF6366F1),
      backgroundColor: Color(0xFFF8F9FA),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppThemeConfig(
      id: 'blue',
      name: '清新蓝',
      icon: '💙',
      primaryColor: Color(0xFF3B82F6),
      backgroundColor: Color(0xFFF0F9FF),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppThemeConfig(
      id: 'green',
      name: '自然绿',
      icon: '💚',
      primaryColor: Color(0xFF10B981),
      backgroundColor: Color(0xFFF0FDF4),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppThemeConfig(
      id: 'pink',
      name: '可爱粉',
      icon: '💗',
      primaryColor: Color(0xFFEC4899),
      backgroundColor: Color(0xFFFDF2F8),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppThemeConfig(
      id: 'orange',
      name: '活力橙',
      icon: '🧡',
      primaryColor: Color(0xFFF59E0B),
      backgroundColor: Color(0xFFFFFBEB),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppThemeConfig(
      id: 'red',
      name: '热情红',
      icon: '❤️',
      primaryColor: Color(0xFFEF4444),
      backgroundColor: Color(0xFFFEF2F2),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppThemeConfig(
      id: 'dark',
      name: '深邃黑',
      icon: '🌙',
      primaryColor: Color(0xFF6366F1),
      backgroundColor: Color(0xFF121212),
      surfaceColor: Color(0xFF1E1E1E),
      brightness: Brightness.dark,
    ),
    AppThemeConfig(
      id: 'dark_blue',
      name: '星空蓝',
      icon: '🌌',
      primaryColor: Color(0xFF3B82F6),
      backgroundColor: Color(0xFF0F172A),
      surfaceColor: Color(0xFF1E293B),
      brightness: Brightness.dark,
    ),
  ];

  static AppThemeConfig getThemeById(String id) {
    return appThemes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => appThemes[0],
    );
  }

  static Future<AppThemeConfig> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeId = prefs.getString('appThemeId') ?? 'default';
      return getThemeById(themeId);
    } catch (e) {
      return appThemes[0];
    }
  }

  static Future<void> saveTheme(String themeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('appThemeId', themeId);
    } catch (e) {
      debugPrint('保存主题失败: $e');
    }
  }
}

class DatabaseService {
  static Database? _database;
  
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/yeah_notes.db';
    
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            title TEXT,
            content TEXT,
            color INTEGER,
            tags TEXT,
            createdAt TEXT,
            isFavorite INTEGER,
            mood TEXT,
            images TEXT,
            updatedAt TEXT,
            category TEXT,
            isPinned INTEGER
          )
        ''');
        
        await db.execute('''
          CREATE INDEX idx_notes_createdAt ON notes(createdAt DESC)
        ''');
        
        await db.execute('''
          CREATE INDEX idx_notes_isFavorite ON notes(isFavorite)
        ''');
        
        await db.execute('''
          CREATE TABLE note_versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            noteId TEXT,
            title TEXT,
            content TEXT,
            color INTEGER,
            tags TEXT,
            mood TEXT,
            versionNumber INTEGER,
            createdAt TEXT,
            FOREIGN KEY (noteId) REFERENCES notes(id)
          )
        ''');
        
        await db.execute('''
          CREATE TABLE images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            noteId TEXT,
            imagePath TEXT,
            createdAt TEXT,
            FOREIGN KEY (noteId) REFERENCES notes(id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE notes ADD COLUMN category TEXT');
          await db.execute('ALTER TABLE notes ADD COLUMN isPinned INTEGER DEFAULT 0');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_createdAt ON notes(createdAt DESC)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_isFavorite ON notes(isFavorite)');
        }
      },
    );
  }
  
  static Future<void> insertNote(Note note) async {
    final db = await database;
    debugPrint('=== [DEBUG] insertNote: 开始保存笔记 ===');
    debugPrint('  - id: ${note.id}');
    debugPrint('  - title: ${note.title}');
    debugPrint('  - content: ${note.content.substring(0, note.content.length > 50 ? 50 : note.content.length)}...');
    await db.insert(
      'notes',
      {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'color': note.color,
        'tags': json.encode(note.tags),
        'createdAt': note.createdAt.toIso8601String(),
        'isFavorite': note.isFavorite ? 1 : 0,
        'mood': note.mood,
        'images': json.encode(note.images),
        'updatedAt': DateTime.now().toIso8601String(),
        'category': note.category,
        'isPinned': note.isPinned ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('  - insertNote: 保存完成!');
  }
  
  static Future<void> updateNote(Note note) async {
    final db = await database;
    final versions = await getNoteVersions(note.id);
    final versionNumber = versions.length + 1;
    
    await db.insert('note_versions', {
      'noteId': note.id,
      'title': note.title,
      'content': note.content,
      'color': note.color,
      'tags': json.encode(note.tags),
      'mood': note.mood,
      'versionNumber': versionNumber,
      'createdAt': DateTime.now().toIso8601String(),
    });
    
    await db.update(
      'notes',
      {
        'title': note.title,
        'content': note.content,
        'color': note.color,
        'tags': json.encode(note.tags),
        'mood': note.mood,
        'images': json.encode(note.images),
        'isFavorite': note.isFavorite ? 1 : 0,
        'updatedAt': DateTime.now().toIso8601String(),
        'category': note.category,
        'isPinned': note.isPinned ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }
  
  static Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    await db.delete('note_versions', where: 'noteId = ?', whereArgs: [id]);
    await db.delete('images', where: 'noteId = ?', whereArgs: [id]);
  }
  
  static Future<List<Note>> getAllNotes() async {
    final db = await database;
    final maps = await db.query('notes', orderBy: 'createdAt DESC');
    debugPrint('=== [DEBUG] getAllNotes: 找到 ${maps.length} 条笔记 ===');
    for (final m in maps) {
      debugPrint('  - id: ${m['id']}, title: ${m['title']}');
    }
    return maps.map((map) => Note.fromJson(map)).toList();
  }
  
  static Future<List<Map<String, dynamic>>> getNoteVersions(String noteId) async {
    final db = await database;
    return await db.query(
      'note_versions',
      where: 'noteId = ?',
      whereArgs: [noteId],
      orderBy: 'versionNumber DESC',
    );
  }
  
  static Future<void> insertImage(String noteId, String imagePath) async {
    final db = await database;
    await db.insert('images', {
      'noteId': noteId,
      'imagePath': imagePath,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }
  
  static Future<List<String>> getNoteImages(String noteId) async {
    final db = await database;
    final maps = await db.query(
      'images',
      where: 'noteId = ?',
      whereArgs: [noteId],
    );
    return maps.map((map) => map['imagePath'] as String).toList();
  }
  
  static Future<void> deleteImage(String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
