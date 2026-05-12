import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class YeahApp extends StatelessWidget {
  const YeahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'yeah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: ThemeMode.system,
      home: const NoteHomePage(),
    );
  }
}

class NoteHomePage extends StatefulWidget {
  const NoteHomePage({super.key});

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
  
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _fabAnimationController;
  late AnimationController _refreshAnimationController;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _refreshAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadNotes();
    _refreshAnimationController.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _loadNotes() async {
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
    } catch (e) {
      _addDemoNotes();
      setState(() => _isLoading = false);
    }
  }

  void _addDemoNotes() {
    final demoNotes = [
      Note(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '🎨 设计灵感',
        content: '好的设计是尽可能少的设计。让功能自然而然地呈现，而不是堆砌。',
        color: 0xFFFFF5E6,
        tags: ['设计', '灵感'],
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isFavorite: true,
        mood: '✨',
      ),
      Note(
        id: (DateTime.now().millisecondsSinceEpoch - 1000).toString(),
        title: '💡 产品思考',
        content: '用户需要的是简单易用的产品，而不是功能复杂的技术展示。',
        color: 0xFFE6F7FF,
        tags: ['产品', '思考'],
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        mood: '💡',
      ),
      Note(
        id: (DateTime.now().millisecondsSinceEpoch - 2000).toString(),
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
      final prefs = await SharedPreferences.getInstance();
      final notesJson = json.encode(_notes.map((n) => n.toJson()).toList());
      await prefs.setString('notes', notesJson);
    } catch (e) {
      debugPrint('保存笔记失败: $e');
    }
  }

  void _applyFilters() {
    _filteredNotes = _notes.where((note) {
      final searchLower = _searchQuery.toLowerCase();
      final matchesSearch = _searchQuery.isEmpty ||
          note.title.toLowerCase().contains(searchLower) ||
          note.content.toLowerCase().contains(searchLower) ||
          note.tags.any((tag) => tag.toLowerCase().contains(searchLower));
      
      final matchesTags = _selectedTags.isEmpty ||
          note.tags.any((tag) => _selectedTags.contains(tag));
      
      return matchesSearch && matchesTags;
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
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const NoteEditorPage(),
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
        _saveNotes();
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
        _saveNotes();
        _showSnackBar('📝 笔记已更新', Icons.edit, Colors.blue);
      }
    });
  }

  void _deleteNote(Note note, int index) {
    final deletedNote = note;
    setState(() {
      _notes.removeWhere((n) => n.id == note.id);
      _applyFilters();
    });
    _saveNotes();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.delete_outline, color: Colors.white),
              const SizedBox(width: 8),
              const Text('笔记已删除'),
            ],
          ),
          action: SnackBarAction(
            label: '撤销',
            textColor: Colors.white,
            onPressed: () {
              if (mounted) {
                setState(() {
                  _notes.insert(index.clamp(0, _notes.length), deletedNote);
                  _applyFilters();
                });
                _saveNotes();
              }
            },
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.grey[800],
        ),
      );
    }
  }

  void _toggleFavorite(Note note) {
    setState(() {
      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index != -1) {
        _notes[index] = note.copyWith(isFavorite: !note.isFavorite);
        _applyFilters();
      }
    });
    _saveNotes();
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
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = _stats;

    return Scaffold(
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(seconds: 1),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: const Icon(
                          Icons.edit_note,
                          size: 64,
                          color: Color(0xFF6366F1),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'yeah',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            )
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

  Widget _buildHeader(bool isDark, Map<String, dynamic> stats) {
    return SliverAppBar(
      expandedHeight: 180,
      floating: false,
      pinned: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
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
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.edit_note, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'yeah',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          Text(
                            _getGreeting(),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _StatCard(
                        icon: Icons.note_outlined,
                        value: '${stats['total']}',
                        label: '笔记',
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.star_outline,
                        value: '${stats['favorite']}',
                        label: '收藏',
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.label_outline,
                        value: '${stats['tags']}',
                        label: '标签',
                        color: const Color(0xFF10B981),
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
              prefixIcon: Icon(
                Icons.search,
                color: const Color(0xFF6366F1),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _QuickStat(
              emoji: '📝',
              value: '${stats['today']}',
              label: '今日',
            ),
            Container(width: 1, height: 40, color: isDark ? Colors.white24 : Colors.grey[300]),
            _QuickStat(
              emoji: '📊',
              value: '${stats['total']}',
              label: '总计',
            ),
            Container(width: 1, height: 40, color: isDark ? Colors.white24 : Colors.grey[300]),
            _QuickStat(
              emoji: '🔥',
              value: '${stats['favorite']}',
              label: '收藏',
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
                        ),
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
                      ),
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
                      size: 64,
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty ? '没有找到相关笔记' : '还没有笔记',
                style: TextStyle(
                  fontSize: 18,
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
      child: FloatingActionButton(
        onPressed: _addNote,
        elevation: 8,
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '早上好 ☀️';
    if (hour < 18) return '下午好 🌤️';
    return '晚上好 🌙';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fabAnimationController.dispose();
    _refreshAnimationController.dispose();
    super.dispose();
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey[600],
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

  const _QuickStat({
    required this.emoji,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6366F1),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
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
  double _dragOffset = 0;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
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
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset += details.delta.dx;
          _dragOffset = _dragOffset.clamp(-80.0, 80.0);
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset.abs() > 60) {
          if (_dragOffset > 0) {
            widget.onFavorite();
          } else {
            widget.onDelete();
          }
        }
        setState(() => _dragOffset = 0);
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              transform: Matrix4.translationValues(_dragOffset, 0, 0),
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
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.note.mood,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (widget.note.isFavorite)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.star, color: Colors.amber, size: 16),
                                ),
                              Expanded(
                                child: Text(
                                  widget.note.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Text(
                              widget.note.content,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                                height: 1.4,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: widget.note.tags.take(2).map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            )).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: _dragOffset < 0 ? null : 0,
              right: _dragOffset > 0 ? null : 0,
              top: 0,
              bottom: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 100),
                opacity: _dragOffset.abs() / 80,
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    color: _dragOffset > 0 ? Colors.amber : Colors.red,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(_dragOffset > 0 ? 0 : 16),
                      right: Radius.circular(_dragOffset < 0 ? 0 : 16),
                    ),
                  ),
                  child: Icon(
                    _dragOffset > 0 ? Icons.star : Icons.delete,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteListItem extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
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
    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onFavorite();
        } else {
          onDelete();
        }
        return false;
      },
      background: Container(
        decoration: BoxDecoration(
          color: Colors.amber,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.star, color: Colors.white),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(note.color),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                if (note.mood.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(note.mood, style: const TextStyle(fontSize: 24)),
                  ),
                Container(
                  width: 4,
                  height: 50,
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
                      const SizedBox(height: 4),
                      Text(
                        note.content,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(note.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
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
  final VoidCallback onDelete;
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
    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onFavorite();
        } else {
          onDelete();
        }
        return false;
      },
      background: Container(
        color: Colors.amber,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.star, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Color(note.color),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (note.mood.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(note.mood, style: const TextStyle(fontSize: 18)),
                  ),
                if (note.isFavorite)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.star, color: Colors.amber, size: 14),
                  ),
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatTime(note.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
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

class NoteEditorPage extends StatefulWidget {
  final Note? note;

  const NoteEditorPage({super.key, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> with SingleTickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  int _selectedColor = 0xFFFFF5E6;
  final List<String> _tags = [];
  String _selectedMood = '';
  
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
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _colorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _colorAnimationController,
      curve: Curves.easeIn,
    );
    
    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _contentController.text = widget.note!.content;
      _selectedColor = widget.note!.color;
      _tags.addAll(widget.note!.tags);
      _selectedMood = widget.note!.mood;
    }
    _colorAnimationController.forward();
  }

  void _saveNote() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    
    if (title.isEmpty && content.isEmpty) {
      Navigator.pop(context);
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
    );

    Navigator.pop(context, note);
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('标签 "$tag" 已存在'), duration: const Duration(seconds: 1)),
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
        SnackBar(content: Text('已添加标签: $tag'), duration: const Duration(seconds: 1)),
      );
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除标签: $tag'), duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Color(_selectedColor),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.grey[700]),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _saveNote,
            icon: Icon(Icons.check, color: isDark ? Colors.white70 : const Color(0xFF6366F1)),
            label: Text(widget.note != null ? '更新' : '保存', style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF6366F1))),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _contentController,
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
                    const SizedBox(height: 20),
                    Text(
                      '🎭 选择心情',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF6366F1) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF6366F1) : Colors.grey[300]!,
                              ),
                              boxShadow: isSelected
                                  ? [BoxShadow(
                                      color: const Color(0xFF6366F1).withOpacity(0.3),
                                      blurRadius: 8,
                                    )]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(mood['emoji']!, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 4),
                                Text(
                                  mood['label']!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.white : Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tags.map((tag) {
                            return Chip(
                              label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                              deleteIcon: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.close, size: 14, color: Colors.black54),
                              ),
                              onDeleted: () => _removeTag(tag),
                              backgroundColor: Colors.grey[100],
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
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
            Row(
              children: [
                Icon(Icons.label_outline, size: 20, color: isDark ? Colors.white54 : Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      hintText: '添加标签...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[400]),
                    ),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, color: isDark ? Colors.white54 : const Color(0xFF6366F1)),
                  onPressed: _addTag,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _colors.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedColor == _colors[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedColor = _colors[index]);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(_colors[index]),
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(color: const Color(0xFF6366F1), width: 3)
                            : Border.all(color: Colors.grey[300]!, width: 1),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.3),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Color(0xFF6366F1), size: 20)
                          : null,
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

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _colorAnimationController.dispose();
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

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.color,
    required this.tags,
    required this.createdAt,
    this.isFavorite = false,
    this.mood = '',
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
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        color: json['color'] as int? ?? 0xFFFFF5E6,
        tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) ?? DateTime.now() : DateTime.now(),
        isFavorite: json['isFavorite'] as bool? ?? false,
        mood: json['mood'] as String? ?? '',
      );
}

enum ViewMode { grid, list, compact }