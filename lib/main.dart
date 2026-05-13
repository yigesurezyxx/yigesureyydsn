      images: _images,
    );

    debugPrint('=== [DEBUG] _saveNote: 创建的 Note 对象 ===');
    debugPrint('  - id: ${note.id}');
    debugPrint('  - title: ${note.title}');
    
    try {
      if (widget.note == null || widget.isFromTemplate) {
        debugPrint('  - 调用 insertNote (新笔记或从模板创建)');
        await DatabaseService.insertNote(note);
      } else {
        debugPrint('  - 调用 updateNote (编辑现有笔记)');
        await DatabaseService.updateNote(note);
      }
    } catch (e) {
      debugPrint('数据库保存失败: $e');
    }

    setState(() => _isSaved = true);
    
    Navigator.pop(context, note);
  }