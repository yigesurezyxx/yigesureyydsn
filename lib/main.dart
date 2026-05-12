import 'dart:math';
import 'package:flutter/material.dart';
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
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF111111),
          surface: Color(0xFFFAFAFA),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        fontFamily: 'Inter',
      ),
      home: const NotesHome(),
    );
  }
}

class Note {
  final String id;
  final String content;
  final int colorIndex;
  final DateTime createdAt;
  final List<String> relatedNoteIds;

  Note({
    required this.id,
    required this.content,
    this.colorIndex = 0,
    required this.createdAt,
    this.relatedNoteIds = const [],
  });

  Note copyWith({
    String? content,
    int? colorIndex,
    List<String>? relatedNoteIds,
  }) {
    return Note(
      id: id,
      content: content ?? this.content,
      colorIndex: colorIndex ?? this.colorIndex,
      createdAt: createdAt,
      relatedNoteIds: relatedNoteIds ?? this.relatedNoteIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'colorIndex': colorIndex,
      'createdAt': createdAt.toIso8601String(),
      'relatedNoteIds': relatedNoteIds.join('|'),
    };
  }

  static Note fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      content: json['content'],
      colorIndex: (json['colorIndex'] ?? 0) is int
          ? json['colorIndex']
          : int.tryParse(json['colorIndex'].toString()) ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
      relatedNoteIds:
          json['relatedNoteIds']?.toString().isNotEmpty == true
              ? (json['relatedNoteIds'] as String).split('|')
              : [],
    );
  }
}

const List<Color> noteColors = [
  Color(0xFFFAFAFA),
  Color(0xFFFDF4EB),
  Color(0xFFF2F7FE),
  Color(0xFFF3F4F6),
  Color(0xFFF4F2FF),
];

class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  List<Note> notes = [];
  bool isLoading = true;
  final ScrollController scrollController = ScrollController();
  String? focusedNoteId;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = prefs.getStringList('notes') ?? [];
    setState(() {
      notes = notesJson.map((json) => Note.fromJson(Map.fromIterable(
            json.split('|||'),
            key: (e) => e.split('==')[0],
            value: (e) => e.split('==')[1],
          ))).toList();
      if (notes.isEmpty) {
        notes = [
          Note(
            id: '1',
            content: '欢迎使用 yeah\n\n在这里，你的想法会自然地关联在一起。写了新东西后，系统会提示你相关的旧笔记。',
            colorIndex: 1,
            createdAt: DateTime.now(),
          ),
          Note(
            id: '2',
            content: '试试长按笔记卡片，你会看到一些有趣的功能。',
            colorIndex: 2,
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
            relatedNoteIds: ['1'],
          ),
        ];
      }
      isLoading = false;
    });
  }

  Future<void> _saveNotes(List<Note> notesToSave) async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = notesToSave.map((note) {
      return [
        'id==${note.id}',
        'content==${note.content}',
        'colorIndex==${note.colorIndex}',
        'createdAt==${note.createdAt.toIso8601String()}',
        'relatedNoteIds==${note.relatedNoteIds.join('|')}',
      ].join('|||');
    }).toList();
    await prefs.setStringList('notes', notesJson);
  }

  List<Note> _findRelatedNotes(Note currentNote) {
    final keywords = _extractKeywords(currentNote.content);
    final related = notes.where((note) {
      if (note.id == currentNote.id) return false;
      final noteKeywords = _extractKeywords(note.content);
      return keywords.any((k) => noteKeywords.contains(k));
    }).toList();
    related.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return related.take(3).toList();
  }

  List<String> _extractKeywords(String content) {
    final words = content
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    final wordCount = <String, int>{};
    for (final word in words) {
      wordCount[word] = (wordCount[word] ?? 0) + 1;
    }
    return wordCount.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .take(5)
        .toList();
  }

  void _addNote() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => NoteEditor(
          onRelatedNotes: _findRelatedNotes,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    ).then((newNote) {
      if (newNote != null && newNote is Note) {
        setState(() {
          notes.insert(0, newNote);
          _saveNotes(notes);
        });
        _scrollToTop();
      }
    });
  }

  void _scrollToTop() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _deleteNote(String id) {
    setState(() {
      notes.removeWhere((n) => n.id == id);
      _saveNotes(notes);
    });
  }

  void _toggleFocus(Note note) {
    setState(() {
      focusedNoteId = focusedNoteId == note.id ? null : note.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF111111)))
                  : _buildNotesList(),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Text(
            'yeah',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.grey[900],
              letterSpacing: -2,
            ),
          ),
          const Spacer(),
          Text(
            '${notes.length} notes',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesList() {
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 48,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '开始写点什么',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      reverse: true,
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final isFocused = focusedNoteId == note.id;
        final relatedNotes = isFocused ? _findRelatedNotes(note) : <Note>[];
        
        return Column(
          children: [
            NoteCard(
              note: note,
              onTap: () => _openNote(note),
              onDelete: () => _deleteNote(note.id),
              onFocus: () => _toggleFocus(note),
              isFocused: isFocused,
            ),
            if (isFocused && relatedNotes.isNotEmpty)
              _buildRelatedNotes(note, relatedNotes),
          ],
        );
      },
    );
  }

  Widget _buildRelatedNotes(Note currentNote, List<Note> relatedNotes) {
    return Container(
      margin: const EdgeInsets.only(left: 40, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFFD4D4D4),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '相关发现',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[300],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...relatedNotes.map((related) {
            return GestureDetector(
              onTap: () => _openNote(related),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  related.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.85),
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  void _openNote(Note note) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => NoteEditor(
          note: note,
          onRelatedNotes: _findRelatedNotes,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    ).then((updatedNote) {
      if (updatedNote != null && updatedNote is Note) {
        setState(() {
          final idx = notes.indexWhere((n) => n.id == updatedNote.id);
          if (idx != -1) {
            notes[idx] = updatedNote;
            _saveNotes(notes);
          }
        });
      }
    });
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _addNote,
      backgroundColor: const Color(0xFF111111),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: const Icon(Icons.add, size: 24),
    );
  }
}

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onFocus;
  final bool isFocused;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onFocus,
    required this.isFocused,
  });

  @override
  Widget build(BuildContext context) {
    final color = noteColors[note.colorIndex % noteColors.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => _showOptions(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFocused
                  ? const Color(0xFF111111)
                  : Colors.black.withOpacity(0.05),
              width: isFocused ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                note.content,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[900],
                  height: 1.6,
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    _formatTime(note.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onFocus,
                    child: Icon(
                      isFocused ? Icons.push_pin : Icons.connect_without_contact,
                      size: 16,
                      color: isFocused ? const Color(0xFF111111) : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.connect_without_contact, color: Color(0xFF111111)),
                title: const Text('探索关联'),
                onTap: () {
                  Navigator.pop(context);
                  onFocus();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                title: const Text(
                  '删除',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${date.month}月${date.day}日 ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class NoteEditor extends StatefulWidget {
  final Note? note;
  final List<Note> Function(Note) onRelatedNotes;

  const NoteEditor({
    super.key,
    this.note,
    required this.onRelatedNotes,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _controller;
  int _selectedColorIndex = 0;
  bool _isSaving = false;
  List<Note> _relatedNotes = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note?.content ?? '');
    _selectedColorIndex = widget.note?.colorIndex ?? 0;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_controller.text.length > 20 && widget.note == null) {
      final tempNote = Note(
        id: 'temp',
        content: _controller.text,
        createdAt: DateTime.now(),
      );
      final related = widget.onRelatedNotes(tempNote);
      if (mounted && related.isNotEmpty) {
        setState(() {
          _relatedNotes = related;
          _showSuggestions = true;
        });
      }
    }
  }

  void _saveNote() {
    if (_controller.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);

    Future.delayed(const Duration(milliseconds: 200), () {
      final note = Note(
        id: widget.note?.id ?? DateTime.now().toIso8601String(),
        content: _controller.text.trim(),
        colorIndex: _selectedColorIndex,
        createdAt: widget.note?.createdAt ?? DateTime.now(),
        relatedNoteIds: _relatedNotes.map((n) => n.id).toList(),
      );
      Navigator.pop(context, note);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = noteColors[_selectedColorIndex % noteColors.length];
    
    return Scaffold(
      backgroundColor: color,
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(),
            if (_showSuggestions && _relatedNotes.isNotEmpty)
              _buildSuggestions(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: TextField(
                  controller: _controller,
                  autofocus: widget.note == null,
                  decoration: const InputDecoration(
                    hintText: '开始写...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      fontSize: 18,
                      color: Color(0xFF9CA3AF),
                      height: 1.6,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[900],
                    height: 1.6,
                  ),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
            _buildColorPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back, color: Color(0xFF4B5563), size: 22),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _saveNote,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome,
            color: Color(0xFFD4D4D4),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现了 ${_relatedNotes.length} 条相关笔记',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[300],
                  ),
                ),
                const SizedBox(height: 6),
                ..._relatedNotes.take(2).map((note) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      note.content,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: List.generate(noteColors.length, (index) {
          final color = noteColors[index];
          return GestureDetector(
            onTap: () => setState(() => _selectedColorIndex = index),
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedColorIndex == index
                        ? const Color(0xFF111111)
                        : Colors.black.withOpacity(0.1),
                    width: _selectedColorIndex == index ? 2 : 1,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}