import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoSave = true;
  bool _showPreview = true;
  String _sortOrder = 'date';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSave = prefs.getBool('autoSave') ?? true;
      _showPreview = prefs.getBool('showPreview') ?? true;
      _sortOrder = prefs.getString('sortOrder') ?? 'date';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSave', _autoSave);
    await prefs.setBool('showPreview', _showPreview);
    await prefs.setString('sortOrder', _sortOrder);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('自动保存'),
            subtitle: const Text('编辑时自动保存笔记'),
            value: _autoSave,
            onChanged: (value) {
              setState(() => _autoSave = value);
              _saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('显示预览'),
            subtitle: const Text('在列表中显示笔记内容预览'),
            value: _showPreview,
            onChanged: (value) {
              setState(() => _showPreview = value);
              _saveSettings();
            },
          ),
          ListTile(
            title: const Text('排序方式'),
            subtitle: Text(_sortOrder == 'date' ? '按日期' : '按名称'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('排序方式'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('按日期'),
                        leading: Radio<String>(
                          value: 'date',
                          groupValue: _sortOrder,
                          onChanged: (value) {
                            setState(() => _sortOrder = value!);
                            _saveSettings();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      ListTile(
                        title: const Text('按名称'),
                        leading: Radio<String>(
                          value: 'name',
                          groupValue: _sortOrder,
                          onChanged: (value) {
                            setState(() => _sortOrder = value!);
                            _saveSettings();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('关于 Yeah'),
            subtitle: const Text('版本 6.0.2'),
            leading: const Icon(Icons.info_outline),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Yeah',
                applicationVersion: '6.0.2',
                applicationIcon: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_note, color: Colors.white),
                ),
                children: [
                  const Text('新一代笔记应用，极简设计，丰富交互'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class TagsPage extends StatelessWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
      ),
      body: const Center(
        child: Text('标签管理页面'),
      ),
    );
  }
}

class CategoryPage extends StatelessWidget {
  const CategoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
      ),
      body: const Center(
        child: Text('分类管理页面'),
      ),
    );
  }
}

class NoteSearchDelegate extends SearchDelegate<dynamic> {
  final List<dynamic> notes;
  final Function(dynamic) onNoteSelected;

  NoteSearchDelegate(this.notes, this.onNoteSelected);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    final results = notes.where((note) {
      final title = note.title.toLowerCase();
      final content = note.content.toLowerCase();
      final searchQuery = query.toLowerCase();
      return title.contains(searchQuery) || content.contains(searchQuery);
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final note = results[index];
        return ListTile(
          title: Text(note.title.isNotEmpty ? note.title : '无标题'),
          subtitle: Text(
            note.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            onNoteSelected(note);
            close(context, note);
          },
        );
      },
    );
  }
}
