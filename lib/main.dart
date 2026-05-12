import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
      theme: ThemeData(
        primaryColor: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const NoteHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class NoteHomePage extends StatefulWidget {
  const NoteHomePage({super.key});

  @override
  State<NoteHomePage> createState() => _NoteHomePageState();
}

class _NoteHomePageState extends State<NoteHomePage> {
  final List<Note> _notes = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String _deviceModel = '';
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final double _scaleFactor = 1.0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _getDeviceInfo();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = prefs.getString('notes');
    if (notesJson != null) {
      final List<dynamic> notesList = json.decode(notesJson);
      setState(() {
        _notes.addAll(notesList.map((json) => Note.fromJson(json)));
        _isLoading = false;
      });
    } else {
      _addDemoNotes();
      setState(() => _isLoading = false);
    }
  }

  void _addDemoNotes() {
    _notes.addAll([
      Note(id: '1', content: '今天的想法：创新是改变世界的力量', color: 0xFFFFF5E6, createdAt: DateTime.now().subtract(const Duration(hours: 1))),
      Note(id: '2', content: '设计原则：少即是多', color: 0xFFE6F7FF, createdAt: DateTime.now().subtract(const Duration(hours: 3))),
      Note(id: '3', content: '用户体验比功能更重要', color: 0xFFF6FFED, createdAt: DateTime.now().subtract(const Duration(days: 1))),
    ]);
    _saveNotes();
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = json.encode(_notes.map((n) => n.toJson()).toList());
    await prefs.setString('notes', notesJson);
  }

  Future<void> _getDeviceInfo() async {
    try {
      const platform = MethodChannel('com.example.yeah/native');
      final result = await platform.invokeMethod('getDeviceInfo');
      setState(() {
        _deviceModel = result['model'] ?? '';
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to get device info: ${e.message}");
    }
  }

  void _addNote() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const NoteEditorPage(),
        transitionsBuilder: (_, animation, __, child) {
          return ScaleTransition(
            scale: animation.drive(Tween(begin: 0.9, end: 1.0)),
            child: child,
          );
        },
      ),
    ).then((newNote) {
      if (newNote != null && newNote is Note) {
        setState(() {
          _notes.insert(0, newNote);
        });
        _saveNotes();
      }
    });
  }

  void _editNote(Note note) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => NoteEditorPage(note: note),
        transitionsBuilder: (_, animation, __, child) {
          return ScaleTransition(
            scale: animation.drive(Tween(begin: 0.9, end: 1.0)),
            child: child,
          );
        },
      ),
    ).then((updatedNote) {
      if (updatedNote != null && updatedNote is Note) {
        setState(() {
          final index = _notes.indexWhere((n) => n.id == updatedNote.id);
          if (index != -1) {
            _notes[index] = updatedNote;
          }
        });
        _saveNotes();
      }
    });
  }

  void _deleteNote(String id) {
    setState(() {
      _notes.removeWhere((n) => n.id == id);
    });
    _saveNotes();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('笔记已删除')),
    );
  }

  List<Note> _filteredNotes() {
    if (_searchQuery.isEmpty) return _notes;
    return _notes.where((note) =>
      note.content.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = _filteredNotes();
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFFAFAFA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                _buildSearchBar(),
                _buildQuickActions(),
                Expanded(child: _buildNoteGrid(filteredNotes)),
              ],
            ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'yeah',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                '${_notes.length} 条',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '记录每一个灵感',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey[100]!,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          onChanged: (value) => setState(() => _searchQuery = value),
          decoration: const InputDecoration(
            hintText: '搜索笔记...',
            prefixIcon: Icon(Icons.search, color: Color(0xFFCCCCCC)),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, left: 20, right: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ActionChip(label: '全部', active: _searchQuery.isEmpty),
            _ActionChip(label: '今天', active: _searchQuery == '今天'),
            _ActionChip(label: '本周', active: _searchQuery == '本周'),
            _ActionChip(label: '本月', active: _searchQuery == '本月'),
            _ActionChip(label: '想法', active: _searchQuery == '想法'),
            _ActionChip(label: '待办', active: _searchQuery == '待办'),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteGrid(List<Note> notes) {
    if (notes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lightbulb_outline, size: 48, color: Color(0xFFDDDDDD)),
            SizedBox(height: 16),
            Text(
              '还没有笔记',
              style: TextStyle(color: Color(0xFF999999)),
            ),
            Text(
              '点击下方按钮开始记录',
              style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        return _NoteCard(
          note: notes[index],
          onTap: () => _editNote(notes[index]),
          onLongPress: () => _showDeleteDialog(notes[index]),
        );
      },
    );
  }

  void _showDeleteDialog(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: const Text('确定要删除这条笔记吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteNote(note.id);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFab() {
    return GestureDetector(
      onTap: _addNote,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final bool active;

  const _ActionChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6366F1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: active ? null : [
            BoxShadow(
              color: Colors.grey[100]!,
              blurRadius: 2,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: active ? Colors.white : const Color(0xFF666666),
            fontWeight: active ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onScaleUpdate: (details) {
        setState(() {
          _scale = details.scale.clamp(0.85, 1.15);
        });
      },
      onScaleEnd: (_) {
        setState(() => _scale = 1.0);
      },
      child: Transform.scale(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Color(widget.note.color),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey[200]!,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    widget.note.content,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF333333),
                      height: 1.5,
                    ),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatTime(widget.note.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
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
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }
}

class NoteEditorPage extends StatefulWidget {
  final Note? note;

  const NoteEditorPage({super.key, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final TextEditingController _contentController = TextEditingController();
  int _selectedColor = 0xFFFFF5E6;
  final List<int> _colors = [
    0xFFFFF5E6, 0xFFE6F7FF, 0xFFF6FFED, 0xFFFFF0E6, 0xFFF0E6FF,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      _contentController.text = widget.note!.content;
      _selectedColor = widget.note!.color;
    }
  }

  void _saveNote() {
    if (_contentController.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }

    final note = Note(
      id: widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      content: _contentController.text.trim(),
      color: _selectedColor,
      createdAt: widget.note?.createdAt ?? DateTime.now(),
    );

    Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(_selectedColor),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF666666)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saveNote,
            child: const Text(
              '保存',
              style: TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: '开始写...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
              ),
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF333333),
                height: 1.6,
              ),
              maxLines: null,
              autofocus: true,
              keyboardType: TextInputType.multiline,
            ),
          ),
          _buildColorSelector(),
        ],
      ),
    );
  }

  Widget _buildColorSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: _colors.map((color) {
          final isSelected = _selectedColor == color;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(color),
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: const Color(0xFF6366F1), width: 2)
                    : null,
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
                  ? const Icon(Icons.check, color: Color(0xFF6366F1), size: 18)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }
}

class Note {
  final String id;
  final String content;
  final int color;
  final DateTime createdAt;

  Note({
    required this.id,
    required this.content,
    required this.color,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'color': color,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'],
        content: json['content'],
        color: json['color'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}