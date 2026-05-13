import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../main.dart';
import '../services/share_service.dart';

class ShareImportPage extends StatefulWidget {
  final ShareData shareData;

  const ShareImportPage({super.key, required this.shareData});

  @override
  State<ShareImportPage> createState() => _ShareImportPageState();
}

class _ShareImportPageState extends State<ShareImportPage> {
  String _title = '';
  String _content = '';
  LinkInfo? _linkInfo;
  bool _isLoading = false;
  
  late TextEditingController _titleController;
  late TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _title);
    _contentController = TextEditingController(text: _content);
    _processShareData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _processShareData() async {
    setState(() => _isLoading = true);
    
    try {
      if (widget.shareData.type == ShareType.text) {
        _detectContentType(widget.shareData.text);
      } else if (widget.shareData.type == ShareType.image) {
        _title = '分享的图片';
        _content = widget.shareData.imagePaths.isNotEmpty 
            ? '![图片](${widget.shareData.imagePaths.first})' 
            : '';
      }

      if (_isUrl(widget.shareData.text)) {
        _linkInfo = await _extractLinkInfo(widget.shareData.text);
        if (_linkInfo != null) {
          _title = _linkInfo!.title;
          _content = '${_linkInfo!.description}\n\n${_linkInfo!.url}';
        }
      }
      
      _titleController.text = _title;
      _contentController.text = _content;
    } catch (e) {
      debugPrint('Error processing share data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<LinkInfo?> _extractLinkInfo(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final title = document.querySelector('title')?.text ?? url;
        final description = document.querySelector('meta[name="description"]')?.attributes['content'] ?? '';
        final image = document.querySelector('meta[property="og:image"]')?.attributes['content'];
        
        return LinkInfo(
          url: url,
          title: title,
          description: description,
          imageUrl: image,
        );
      }
    } catch (e) {
      debugPrint('Error extracting link info: $e');
    }
    return null;
  }

  void _detectContentType(String text) {
    if (_isUrl(text)) {
      _title = '网页链接';
      _content = text;
    } else if (text.length < 50) {
      _title = text;
      _content = '';
    } else {
      _title = '分享的内容';
      _content = text;
    }
  }

  bool _isUrl(String text) {
    return text.startsWith('http://') || text.startsWith('https://');
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入内容')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final note = Note(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title.isNotEmpty ? title : '无标题',
        content: content,
        color: 0xFFFFF5E6,
        tags: ['分享'],
        createdAt: DateTime.now(),
        images: widget.shareData.imagePaths,
      );

      await DatabaseService.insertNote(note);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记保存成功')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入分享内容'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveNote,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildContentTypeBadge(),
                  const SizedBox(height: 16),
                  _buildPreviewCard(),
                  if (widget.shareData.imagePaths.isNotEmpty)
                    _buildImagePreview(),
                  const SizedBox(height: 16),
                  _buildEditSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildContentTypeBadge() {
    String typeText = '混合';
    Color typeColor = Colors.grey;

    switch (widget.shareData.type) {
      case ShareType.text:
        typeText = '文本';
        typeColor = Colors.blue;
        break;
      case ShareType.link:
        typeText = '链接';
        typeColor = Colors.green;
        break;
      case ShareType.image:
        typeText = '图片';
        typeColor = Colors.purple;
        break;
      case ShareType.file:
        typeText = '文件';
        typeColor = Colors.orange;
        break;
      case ShareType.mixed:
        typeText = '混合';
        typeColor = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '检测到: $typeText',
        style: TextStyle(color: typeColor, fontSize: 12),
      ),
    );
  }

  Widget _buildPreviewCard() {
    if (_linkInfo != null) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_linkInfo!.imageUrl != null)
                Image.network(
                  _linkInfo!.imageUrl!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(),
                ),
              const SizedBox(height: 12),
              Text(
                _linkInfo!.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _linkInfo!.description,
                style: TextStyle(color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                _linkInfo!.url,
                style: TextStyle(color: Colors.blue[600], fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container();
  }

  Widget _buildImagePreview() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: widget.shareData.imagePaths.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            Image.file(
              File(widget.shareData.imagePaths[index]),
              fit: BoxFit.cover,
              width: double.infinity,
              height: 100,
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditSection() {
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
          controller: _titleController,
          maxLines: 1,
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: '内容',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          controller: _contentController,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
        ),
      ],
    );
  }
}
