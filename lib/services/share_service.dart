import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

enum ShareType {
  text,
  link,
  image,
  file,
  mixed,
}

class ShareData {
  final String text;
  final ShareType type;
  final List<String> imagePaths;
  final List<String> filePaths;

  ShareData({
    required this.text,
    required this.type,
    this.imagePaths = const [],
    this.filePaths = const [],
  });
}

class LinkInfo {
  final String url;
  final String title;
  final String description;
  final String? imageUrl;

  LinkInfo({
    required this.url,
    required this.title,
    required this.description,
    this.imageUrl,
  });
}

class ShareService {
  static final ShareService _instance = ShareService._internal();
  factory ShareService() => _instance;
  ShareService._internal();

  StreamSubscription? _intentDataStreamSubscription;
  ShareData? _pendingShareData;
  bool _isProcessing = false;

  void initializeShareListener(void Function(ShareData) onShareReceived) {
    _intentDataStreamSubscription?.cancel();
    
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> mediaList) {
      if (mediaList.isNotEmpty && !_isProcessing) {
        _processMediaFiles(mediaList);
      }
    }, onError: (err) {
      debugPrint('Error receiving media: $err');
    });

    _getInitialMedia();
  }

  Future<void> _getInitialMedia() async {
    try {
      final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty && !_isProcessing) {
        _processMediaFiles(initialMedia);
      }
    } catch (e) {
      debugPrint('Error getting initial media: $e');
    }
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
    ReceiveSharingIntent.instance.reset();
  }

  Future<void> _processMediaFiles(List<SharedMediaFile> mediaList) async {
    _isProcessing = true;
    try {
      List<String> imagePaths = [];
      List<String> filePaths = [];

      for (var media in mediaList) {
        if (media.type == SharedMediaType.image) {
          String savedPath = await _saveImageToLocal(media.path);
          if (savedPath.isNotEmpty) {
            imagePaths.add(savedPath);
          }
        } else {
          filePaths.add(media.path);
        }
      }

      ShareType type = imagePaths.isNotEmpty ? ShareType.image : ShareType.file;
      
      _pendingShareData = ShareData(
        text: mediaList.length > 1 ? '${mediaList.length} 个文件' : '',
        type: type,
        imagePaths: imagePaths,
        filePaths: filePaths,
      );
    } catch (e) {
      debugPrint('Error processing media files: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _processShareData(ShareData data) {
    _isProcessing = true;
    _pendingShareData = data;
    _isProcessing = false;
  }

  ShareData? getPendingShareData() {
    ShareData? data = _pendingShareData;
    _pendingShareData = null;
    return data;
  }

  Future<String> _saveImageToLocal(String sourcePath) async {
    try {
      File imageFile = File(sourcePath);
      if (!await imageFile.exists()) return '';

      Directory appDir = await getApplicationDocumentsDirectory();
      String fileName = 'share_${DateTime.now().millisecondsSinceEpoch}${path.extension(sourcePath)}';
      String destinationPath = path.join(appDir.path, 'images', fileName);

      await Directory(path.dirname(destinationPath)).create(recursive: true);
      await imageFile.copy(destinationPath);

      await _generateThumbnail(destinationPath);

      return destinationPath;
    } catch (e) {
      debugPrint('Error saving image: $e');
      return '';
    }
  }

  Future<void> _generateThumbnail(String imagePath) async {
    try {
      File imageFile = File(imagePath);
      Uint8List bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage != null) {
        int maxDimension = 300;
        img.Image thumbnail = img.copyResize(
          originalImage,
          width: originalImage.width > originalImage.height ? maxDimension : null,
          height: originalImage.height >= originalImage.width ? maxDimension : null,
        );

        String thumbnailPath = imagePath.replaceAll('.', '_thumb.');
        File(thumbnailPath).writeAsBytesSync(img.encodeJpg(thumbnail, quality: 80));
      }
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
    }
  }

  Future<LinkInfo?> extractLinkInfo(String url) async {
    try {
      if (!url.startsWith('http')) return null;

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        String? title = document.querySelector('title')?.text;
        String? description = document.querySelector('meta[name="description"]')?.attributes['content'];
        String? imageUrl = document.querySelector('meta[property="og:image"]')?.attributes['content'];

        return LinkInfo(
          url: url,
          title: title ?? url,
          description: description ?? '',
          imageUrl: imageUrl,
        );
      }
    } catch (e) {
      debugPrint('Error extracting link info: $e');
    }
    return null;
  }

  Future<void> shareNote(String title, String content, [List<String>? imagePaths]) async {
    String shareText = '$title\n\n$content';
    
    if (imagePaths != null && imagePaths.isNotEmpty) {
      await Share.shareXFiles(
        imagePaths.map((p) => XFile(p)).toList(),
        text: shareText,
      );
    } else {
      await Share.share(shareText);
    }
  }
}
