import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),
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
  Set<String> _selectedTags = {};
  
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

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = prefs.getString('notes');
    if (notesJson != null) {
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
  }

  void _addDemoNotes() {
    final demoNotes = [
      Note(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '创新设计理念',
        content: '好的设计是尽可能少的设计。让功能自然而然地呈现，而不是堆砌。',
        color: 0xFFFFF5E6,
        tags: ['设计', '理念'],
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isFavorite: true,
      ),
      Note(
        id: (DateTime.now().millisecondsSinceEpoch - 1).toString(),
        title: '用户反馈',
        content: '用户需要的是简单易用的产品，而不是功能复杂的技术展示。',
        color: 0xFFE6F7FF,
        tags: ['反馈', '产品'],
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      Note(
        id: (DateTime.now().millisecondsSinceEpoch - 2).toString(),
        title: '本周计划',
        content: '1. 完成核心功能开发\n2. 优化用户体验\n3. 收集用户反馈',
        color: 0xFFF6FFED,
        tags: ['计划'],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
    _notes.addAll(demoNotes);
    _applyFilters();
    _saveNotes();
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = json.encode(_notes.map((n) => n.toJson()).toList());
    await prefs.setString('notes', notesJson);
  }

  void _applyFilters() {
    _filteredNotes = _notes.where((note) {
      final matchesSearch = _searchQuery.isEmpty ||
          note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          note.content.toLowerCase().contains(_searchQuery.toLowerCase());
      
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
        _showSnackBar('笔记已创建', Icons.check_circle, Colors.green);
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
        _showSnackBar('笔记已更新', Icons.edit, Colors.blue);
      }
    });
  }

  void _deleteNote(Note note, int index) {
    setState(() {
      _notes.removeWhere((n) => n.id == note.id);
      _applyFilters();
    });
    _saveNotes();
    _showSnackBar('笔记已删除', Icons.delete, Colors.red);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('笔记已删除'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            setState(() {
              _notes.insert(index.clamp(0, _notes.length), note);
              _applyFilters();
            });
            _saveNotes();
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );
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
      note.isFavorite ? '已取消收藏' : '已收藏',
      note.isFavorite ? Icons.star_border : Icons.star,
      note.isFavorite ? Colors.grey : Colors.amber,
    );
  }

  void _showSnackBar(String message, IconData icon, Color color) {
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildAppBar(),
                _buildSearchAndFilter(),
                _buildTagFilter(),
                _buildNotesList(),
              ],
            ),
      floatingActionButton: _buildAnimatedFab(),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Row(
          children: [
            const Text(
              'yeah',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_notes.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          tooltip: '排序',
          onSelected: (value) {
            setState(() {
              _sortBy = value;
              _applyFilters();
            });
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'date', child: Text('按时间')),
            const PopupMenuItem(value: 'name', child: Text('按名称')),
            const PopupMenuItem(value: 'favorite', child: Text('收藏优先')),
          ],
        ),
        PopupMenuButton<ViewMode>(
          icon: const Icon(Icons.view_module),
          tooltip: '视图模式',
          onSelected: (mode) {
            setState(() => _viewMode = mode);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: ViewMode.grid, child: Text('网格视图')),
            const PopupMenuItem(value: ViewMode.list, child: Text('列表视图')),
            const PopupMenuItem(value: ViewMode.compact, child: Text('紧凑视图')),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
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
              hintText: '搜索笔记...',
              prefixIcon: AnimatedBuilder(
                animation: _refreshAnimationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _searchQuery.isEmpty ? 0 : _refreshAnimationController.value * 2 * pi,
                    child: Icon(
                      _searchQuery.isEmpty ? Icons.search : Icons.sync,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
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
          ),
        ),
      ),
    );
  }

  Widget _buildTagFilter() {
    final tags = _allTags;
    if (tags.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Container(
        height: 50,
        margin: const EdgeInsets.only(top: 12),
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
                  onSelected: (selected) {
                    setState(() {
                      _selectedTags.clear();
                      _applyFilters();
                    });
                  },
                ),
              );
            }
            final tag = tags.elementAt(index - 1);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(tag),
                selected: _selectedTags.contains(tag),
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
    );
  }

  Widget _buildNotesList() {
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
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty ? '没有找到相关笔记' : '还没有笔记',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty ? '试试其他关键词' : '点击下方按钮开始记录',
                style: TextStyle(
                  color: Colors.grey[400],
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
          ? _buildGridView()
          : _viewMode == ViewMode.list
              ? _buildListView()
              : _buildCompactListView(),
    );
  }

  Widget _buildGridView() {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildAnimatedCard(index),
        childCount: _filteredNotes.length,
      ),
    );
  }

  Widget _buildListView() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildAnimatedListItem(index),
        ),
        childCount: _filteredNotes.length,
      ),
    );
  }

  Widget _buildCompactListView() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildCompactItem(index),
        ),
        childCount: _filteredNotes.length,
      ),
    );
  }

  Widget _buildAnimatedCard(int index) {
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
      ),
    );
  }

  Widget _buildAnimatedListItem(int index) {
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
      ),
    );
  }

  Widget _buildCompactItem(int index) {
    return _NoteCompactItem(
      note: _filteredNotes[index],
      onTap: () => _editNote(_filteredNotes[index]),
      onDelete: () => _deleteNote(_filteredNotes[index], index),
      onFavorite: () => _toggleFavorite(_filteredNotes[index]),
    );
  }

  Widget _buildAnimatedFab() {
    return AnimatedBuilder(
      animation: _fabAnimationController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_fabAnimationController.value * 0.1),
          child: FloatingActionButton(
            onPressed: _addNote,
            elevation: 8,
            child: AnimatedIcon(
              icon: AnimatedIcons.add_event,
              progress: _fabAnimationController,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fabAnimationController.dispose();
    _refreshAnimationController.dispose();
    super.dispose();
  }
}

class _NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
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
              padding: const EdgeInsets.all(16),
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
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      widget.note.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ...widget.note.tags.take(2).map((tag) => Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      )),
                      const Spacer(),
                      Text(
                        _formatTime(widget.note.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
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

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.month}/${date.day}';
  }
}

class _NoteListItem extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;

  const _NoteListItem({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onFavorite();
          return false;
        } else {
          onDelete();
          return false;
        }
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
                Container(
                  width: 4,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ...note.tags.take(1).map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(tag, style: const TextStyle(fontSize: 10)),
                    )),
                    const SizedBox(height: 4),
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
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.month}/${date.day}';
  }
}

class _NoteCompactItem extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;

  const _NoteCompactItem({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
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
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
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
  List<String> _tags = [];
  bool _isEditing = false;
  
  final List<int> _colors = [
    0xFFFFF5E6, 0xFFE6F7FF, 0xFFF6FFED, 0xFFFFF0E6, 0xFFF0E6FF,
    0xFFFFE6E6, 0xFFE6FFE6, 0xFFE6FFFF,
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
      _tags = List.from(widget.note!.tags);
      _isEditing = true;
    }
    _colorAnimationController.forward();
  }

  void _saveNote() {
    if (_titleController.text.trim().isEmpty && _contentController.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }

    final note = Note(
      id: widget.note?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      color: _selectedColor,
      tags: _tags,
      createdAt: widget.note?.createdAt ?? DateTime.now(),
      isFavorite: widget.note?.isFavorite ?? false,
    );

    Navigator.pop(context, note);
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(_selectedColor),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _saveNote,
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? '更新' : '保存'),
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
                      decoration: const InputDecoration(
                        hintText: '标题',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFBBBBBB),
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                      autofocus: !_isEditing,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contentController,
                      decoration: const InputDecoration(
                        hintText: '开始记录...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
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
                    const SizedBox(height: 16),
                    if (_tags.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _tags.map((tag) {
                          return Chip(
                            label: Text(tag),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() => _tags.remove(tag));
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                const Icon(Icons.label_outline, size: 20, color: Color(0xFF999999)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
                      hintText: '添加标签...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
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
                            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
                            : Border.all(color: Colors.grey[300]!, width: 1),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            )
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

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.color,
    required this.tags,
    required this.createdAt,
    this.isFavorite = false,
  });

  Note copyWith({
    String? id,
    String? title,
    String? content,
    int? color,
    List<String>? tags,
    DateTime? createdAt,
    bool? isFavorite,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      color: color ?? this.color,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
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
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'],
        title: json['title'],
        content: json['content'],
        color: json['color'],
        tags: List<String>.from(json['tags'] ?? []),
        createdAt: DateTime.parse(json['createdAt']),
        isFavorite: json['isFavorite'] ?? false,
      );
}

enum ViewMode { grid, list, compact }