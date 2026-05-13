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
  AppTheme _currentTheme = ThemeService.appThemes[0];

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final theme = await ThemeService.loadSavedTheme();
    if (mounted) {
      setState(() {
        _currentTheme = theme;
      });
    }
  }

  void _changeTheme(AppTheme theme) async {
    await ThemeService.saveTheme(theme.id);
    setState(() {
      _currentTheme = theme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'yeah',
      debugShowCheckedModeBanner: false,
      theme: _currentTheme.toThemeData(),
      themeMode: ThemeMode.system,
      home: NoteHomePage(
        onThemeChanged: _changeTheme,
        currentTheme: _currentTheme,
      ),
    );
  }
}

class NoteHomePage extends StatefulWidget {
  final Function(AppTheme) onThemeChanged;
  final AppTheme currentTheme;

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
  late AnimationController _fabAnimationController;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
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
    try {
      final notes = await DatabaseService.getAllNotes();
      if (notes.isEmpty) {
        _addDemoNotes();
        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _notes.clear();
          _notes.addAll(notes);
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载笔记失败: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final notesJson = prefs.getString('notes');
        if (notesJson != null && notesJson.isNotEmpty) {
          final List<dynamic> notesList = json.decode(notesJson);
          setState(() {
            _notes.addAll(notesList.map((json) => Note.fromJson(json)));
            _applyFilters();
            _isLoading = false;
          });
        } else {
          _addDemoNotes();
          setState(() => _isLoading = false);
        }
      } catch (e2) {
        _addDemoNotes();
        setState(() => _isLoading = false);
      }
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
      try {
        final prefs = await SharedPreferences.getInstance();
        final notesJson = json.encode(_notes.map((n) => n.toJson()).toList());
        await prefs.setString('notes', notesJson);
      } catch (e2) {
        debugPrint('备用保存失败: $e2');
      }
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
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
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
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
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
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = json.encode(_notes.map((n) => n.toJson()).toList());
      await prefs.setString('notes', notesJson);
    } catch (e) {
      debugPrint('备用保存失败: $e');
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
    final stats = _stats;

    return Scaffold(
      body: _isLoading
          ? _buildLoadingScreen(isDark)
          : CustomScrollView(
              slivers: [
                _buildHeader(isDark, stats),
                _buildSearchBar(isDark),
                _buildQuickStats(isDark, stats),
                _buildTagFilter(isDark),
                _buildNotesList(isDark),
              ],
            ),
      floatingActionButton: _buildAnimatedFab(),
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

  Widget _buildHeader(bool isDark, Map<String, dynamic> stats) {
    return SliverAppBar(
      expandedHeight: 200,
      floating: false,
      pinned: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: const Text('yeah', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                  ? [const Color(0xFF1E1E1E), const Color(0xFF2D2D2D)]
                  : [Colors.white, const Color(0xFFF8F9FA)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getGreeting(),
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatCard(
                        icon: Icons.note_outlined,
                        value: '${stats['total']}',
                        label: '笔记',
                        color: const Color(0xFF6366F1),
                        isDark: isDark,
                      ),
                      _StatCard(
                        icon: Icons.star_outline,
                        value: '${stats['favorite']}',
                        label: '收藏',
                        color: Colors.amber,
                        isDark: isDark,
                      ),
                      _StatCard(
                        icon: Icons.label_outline,
                        value: '${stats['tags']}',
                        label: '标签',
                        color: const Color(0xFF10B981),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.sort, color: isDark ? Colors.white70 : Colors.grey[700]),
          tooltip: '排序',
          onSelected: (value) {
            setState(() {
              _sortBy = value;
              _applyFilters();
            });
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'date', child: Text('📅 按时间')),
            const PopupMenuItem(value: 'name', child: Text('🔤 按名称')),
            const PopupMenuItem(value: 'favorite', child: Text('⭐ 收藏优先')),
          ],
        ),
        PopupMenuButton<ViewMode>(
          icon: Icon(Icons.view_module, color: isDark ? Colors.white70 : Colors.grey[700]),
          tooltip: '视图模式',
          onSelected: (mode) {
            setState(() => _viewMode = mode);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: ViewMode.grid, child: Text('📱 网格视图')),
            const PopupMenuItem(value: ViewMode.list, child: Text('📋 列表视图')),
            const PopupMenuItem(value: ViewMode.compact, child: Text('⚡ 紧凑视图')),
          ],
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : Colors.grey[700]),
          tooltip: '更多操作',
          onSelected: (value) async {
            if (value == 'export') {
              await _exportNotes();
            } else if (value == 'import') {
              await _importNotes();
            } else if (value == 'theme') {
              _showThemeSelector();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.upload, color: Colors.green),
                  SizedBox(width: 8),
                  Text('📤 导出笔记'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'import',
              child: Row(
                children: [
                  Icon(Icons.download, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('📥 导入笔记'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'theme',
              child: Row(
                children: [
                  Icon(Icons.palette, color: widget.currentTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text('🎨 ${widget.currentTheme.icon} 主题'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _applyFilters();
              });
            },
            decoration: InputDecoration(
              hintText: '🔍 搜索笔记、标签...',
              hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey[400]),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF6366F1),
                size: 24,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: isDark ? Colors.white54 : Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _applyFilters();
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStats(bool isDark, Map<String, dynamic> stats) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 20, right: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6366F1).withOpacity(0.1),
              const Color(0xFF8B5CF6).withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6366F1).withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _QuickStat(
              emoji: '📝',
              value: '${stats['today']}',
              label: '今日',
              isDark: isDark,
            ),
            Container(width: 1, height: 40, color: isDark ? Colors.white24 : Colors.grey[300]),
            _QuickStat(
              emoji: '📊',
              value: '${stats['total']}',
              label: '总数',
              isDark: isDark,
            ),
            Container(width: 1, height: 40, color: isDark ? Colors.white24 : Colors.grey[300]),
            _QuickStat(
              emoji: '🔥',
              value: '${stats['favorite']}',
              label: '收藏',
              isDark: isDark,
            ),
          ],
        ),
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 300)),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: _NoteCard(
        note: _filteredNotes[index],
        onTap: () => _editNote(_filteredNotes[index]),
        onDelete: () => _deleteNote(_filteredNotes[index], index),
        onFavorite: () => _toggleFavorite(_filteredNotes[index]),
        isDark: isDark,
      ),
    );
  }

  Widget _buildAnimatedListItem(int index, bool isDark) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 30).clamp(0, 200)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(-50 * (1 - value), 0),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: _NoteListItem(
        note: _filteredNotes[index],
        onTap: () => _editNote(_filteredNotes[index]),
        onDelete: () => _deleteNote(_filteredNotes[index], index),
        onFavorite: () => _toggleFavorite(_filteredNotes[index]),
        isDark: isDark,
      ),
    );
  }

  Widget _buildCompactItem(int index, bool isDark) {
    return _NoteCompactItem(
      note: _filteredNotes[index],
      onTap: () => _editNote(_filteredNotes[index]),
      onDelete: () => _deleteNote(_filteredNotes[index], index),
      onFavorite: () => _toggleFavorite(_filteredNotes[index]),
      isDark: isDark,
    );
  }

  Widget _buildAnimatedFab() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: FloatingActionButton.extended(
        onPressed: _addNote,
        elevation: 6,
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add, color: Colors.white, size: 24),
        label: const Text('新建', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
      ),
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
    _fabAnimationController.dispose();
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final bool isDark;

  const _QuickStat({
    required this.emoji,
    required this.value,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  final VoidCallback onFavorite;
  final bool isDark;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
    required this.isDark,
  });

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _controller.forward();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Color(widget.note.color),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _isPressed 
                    ? Colors.black.withOpacity(0.15)
                    : Colors.black.withOpacity(0.08),
                blurRadius: _isPressed ? 12 : 8,
                offset: Offset(0, _isPressed ? 6 : 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.note.mood.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.note.mood,
                        style: const TextStyle(fontSize: 28),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              widget.note.isFavorite ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 20,
                            ),
                            onPressed: widget.onFavorite,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: widget.onDelete,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
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
                          if (widget.note.isFavorite && widget.note.mood.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.star, color: Colors.amber, size: 16),
                            ),
                          Expanded(
                            child: Text(
                              widget.note.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.note.mood.isEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    widget.note.isFavorite ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 20,
                                  ),
                                  onPressed: widget.onFavorite,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: widget.onDelete,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          widget.note.content,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.note.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: widget.note.tags.take(2).map((tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )).toList(),
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
}

class _NoteListItem extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  final VoidCallback onFavorite;
  final bool isDark;

  const _NoteListItem({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(note.color),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.mood.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(note.mood, style: const TextStyle(fontSize: 28)),
                ),
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (note.isFavorite)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.star, color: Colors.amber, size: 16),
                          ),
                        Expanded(
                          child: Text(
                            note.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      note.content,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (note.tags.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: note.tags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        )).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      note.isFavorite ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 20,
                    ),
                    onPressed: onFavorite,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: onDelete,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(note.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟';
    if (diff.inHours < 24) return '${diff.inHours}小时';
    if (diff.inDays < 7) return '${diff.inDays}天';
    return '${date.month}/${date.day}';
  }
}

class _NoteCompactItem extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  final VoidCallback onFavorite;
  final bool isDark;

  const _NoteCompactItem({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Color(note.color),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (note.mood.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(note.mood, style: const TextStyle(fontSize: 20)),
                ),
              if (note.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.star, color: Colors.amber, size: 14),
                ),
              Expanded(
                child: Text(
                  note.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  note.isFavorite ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 18,
                ),
                onPressed: onFavorite,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                onPressed: onDelete,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Text(
                _formatTime(note.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟';
    if (diff.inHours < 24) return '${diff.inHours}小时';
    if (diff.inDays < 7) return '${diff.inDays}天';
    return '${date.month}/${date.day}';
  }
}

class _ThemeSelectorSheet extends StatelessWidget {
  final AppTheme currentTheme;
  final Function(AppTheme) onSelectTheme;

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
  final AppTheme theme;
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

    try {
      if (widget.note == null) {
        await DatabaseService.insertNote(note);
      } else {
        await DatabaseService.updateNote(note);
      }
    } catch (e) {
      debugPrint('数据库保存失败: $e');
    }

    setState(() => _isSaved = true);
    
    if (silent) {
      Navigator.of(context).pop(note);
    } else {
      Navigator.pop(context, note);
    }
  }

  Future<bool> _onWillPop() async {
    if (_isSaved) return true;
    
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    
    if (title.isEmpty && content.isEmpty) return true;
    
    return await showDialog<bool>(
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
              _saveNote();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ) ?? false;
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

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Color(_selectedColor),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: isDark ? Colors.white70 : Colors.grey[700], size: 28),
              onPressed: () async {
                if (await _onWillPop()) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _isSaved ? '已保存' : '编辑中...',
              key: ValueKey(_isSaved),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _isSaved ? Colors.green : Colors.orange,
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _saveNote,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check, color: Colors.white, size: 22),
                label: Text(widget.note != null ? '更新' : '保存', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              ),
            ),
          ],
        ),
      body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: '📝 给笔记起个标题...',
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
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contentController,
                      focusNode: _contentFocusNode,
                      decoration: InputDecoration(
                        hintText: '开始记录你的想法...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey[400]),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF333333),
                        height: 1.6,
                      ),
                      maxLines: null,
                      minLines: 10,
                      keyboardType: TextInputType.multiline,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '🎭 选择心情',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _moods.map((mood) {
                        final isSelected = _selectedMood == mood['emoji'];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedMood = isSelected ? '' : mood['emoji']!;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF6366F1) : (isDark ? const Color(0xFF2D2D2D) : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF6366F1) : (isDark ? Colors.white24 : Colors.grey[300]!),
                              ),
                              boxShadow: isSelected
                                  ? [BoxShadow(
                                      color: const Color(0xFF6366F1).withOpacity(0.3),
                                      blurRadius: 12,
                                    )]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(mood['emoji']!, style: const TextStyle(fontSize: 24)),
                                const SizedBox(width: 8),
                                Text(
                                  mood['label']!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey[700]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🏷️ 已添加标签',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _tags.map((tag) {
                                return Chip(
                                  label: Text('#$tag', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                  deleteIcon: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.close, size: 14, color: Colors.black54),
                                  ),
                                  onDeleted: () => _removeTag(tag),
                                  backgroundColor: Colors.grey[100],
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _buildBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showFormattingBar) ...[
              _buildFormattingToolbar(isDark),
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: isDark ? Colors.white12 : Colors.grey[200],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Icon(Icons.label_outline, size: 22, color: isDark ? Colors.white54 : Colors.grey[600]),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      hintText: '添加标签...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[400]),
                    ),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.image_outlined, size: 26, color: isDark ? Colors.white54 : Colors.grey[600]),
                  onPressed: _addImage,
                  tooltip: '添加图片',
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, size: 28, color: isDark ? Colors.white54 : const Color(0xFF6366F1)),
                  onPressed: _addTag,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _colors.asMap().entries.map((entry) {
                final index = entry.key;
                final color = entry.value;
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedColor = color);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: index < _colors.length - 1 ? 12 : 0),
                    width: isSelected ? 52 : 40,
                    height: isSelected ? 52 : 40,
                    decoration: BoxDecoration(
                      color: Color(color),
                      borderRadius: BorderRadius.circular(isSelected ? 16 : 12),
                      border: isSelected
                          ? Border.all(color: const Color(0xFF6366F1), width: 3)
                          : Border.all(color: isDark ? Colors.white24 : Colors.grey[300]!, width: 1),
                      boxShadow: isSelected
                          ? [BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.3),
                              blurRadius: 12,
                            )]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF6366F1), size: 22)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattingToolbar(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FormatButton(
            icon: Icons.format_bold,
            label: '加粗',
            onTap: () => _applyFormatting('**', '**'),
            isDark: isDark,
          ),
          _FormatButton(
            icon: Icons.format_italic,
            label: '斜体',
            onTap: () => _applyFormatting('*', '*'),
            isDark: isDark,
          ),
          _FormatButton(
            icon: Icons.format_underline,
            label: '下划线',
            onTap: () => _applyFormatting('__', '__'),
            isDark: isDark,
          ),
          Container(
            width: 1,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: isDark ? Colors.white12 : Colors.grey[300],
          ),
          _FormatButton(
            icon: Icons.format_list_bulleted,
            label: '列表',
            onTap: _insertBulletPoint,
            isDark: isDark,
          ),
          _FormatButton(
            icon: Icons.code,
            label: '代码',
            onTap: () => _applyFormatting('`', '`'),
            isDark: isDark,
          ),
          _FormatButton(
            icon: Icons.format_quote,
            label: '引用',
            onTap: () => _applyFormatting('> ', ''),
            isDark: isDark,
          ),
          Container(
            width: 1,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: isDark ? Colors.white12 : Colors.grey[300],
          ),
          _FormatButton(
            icon: Icons.link,
            label: '链接',
            onTap: () => _applyFormatting('[', '](url)'),
            isDark: isDark,
          ),
        ],
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

class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _FormatButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: isDark ? Colors.white70 : Colors.grey[700]),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

class AppTheme {
  final String id;
  final String name;
  final String icon;
  final Color primaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Brightness brightness;

  const AppTheme({
    required this.id,
    required this.name,
    required this.icon,
    required this.primaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.brightness,
  });

  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
        surface: surfaceColor,
      ),
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

class ThemeService {
  static const List<AppTheme> appThemes = [
    AppTheme(
      id: 'default',
      name: '默认紫',
      icon: '💜',
      primaryColor: Color(0xFF6366F1),
      backgroundColor: Color(0xFFF8F9FA),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppTheme(
      id: 'blue',
      name: '清新蓝',
      icon: '💙',
      primaryColor: Color(0xFF3B82F6),
      backgroundColor: Color(0xFFF0F9FF),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppTheme(
      id: 'green',
      name: '自然绿',
      icon: '💚',
      primaryColor: Color(0xFF10B981),
      backgroundColor: Color(0xFFF0FDF4),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppTheme(
      id: 'pink',
      name: '可爱粉',
      icon: '💗',
      primaryColor: Color(0xFFEC4899),
      backgroundColor: Color(0xFFFDF2F8),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppTheme(
      id: 'orange',
      name: '活力橙',
      icon: '🧡',
      primaryColor: Color(0xFFF59E0B),
      backgroundColor: Color(0xFFFFFBEB),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppTheme(
      id: 'red',
      name: '热情红',
      icon: '❤️',
      primaryColor: Color(0xFFEF4444),
      backgroundColor: Color(0xFFFEF2F2),
      surfaceColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    AppTheme(
      id: 'dark',
      name: '深邃黑',
      icon: '🌙',
      primaryColor: Color(0xFF6366F1),
      backgroundColor: Color(0xFF121212),
      surfaceColor: Color(0xFF1E1E1E),
      brightness: Brightness.dark,
    ),
    AppTheme(
      id: 'dark_blue',
      name: '星空蓝',
      icon: '🌌',
      primaryColor: Color(0xFF3B82F6),
      backgroundColor: Color(0xFF0F172A),
      surfaceColor: Color(0xFF1E293B),
      brightness: Brightness.dark,
    ),
  ];

  static AppTheme getThemeById(String id) {
    return appThemes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => appThemes[0],
    );
  }

  static Future<AppTheme> loadSavedTheme() async {
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
      version: 1,
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
            updatedAt TEXT
          )
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
    );
  }
  
  static Future<void> insertNote(Note note) async {
    final db = await database;
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
