import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ImageService {
  static final ImagePicker _picker = ImagePicker();
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload raw bytes directly to Firebase Storage and return the public download URL
  static Future<String?> uploadBytes({
    required Uint8List bytes,
    required String storagePath,
    String contentType = 'image/jpeg',
  }) async {
    try {
      final ref = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(
        contentType: contentType,
        cacheControl: 'public, max-age=31536000', // 1 year browser cache
      );
      final uploadTask = await ref.putData(bytes, metadata);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        print("ImageService.uploadBytes error: $e");
      }
      return null;
    }
  }

  /// Convert legacy Base64 string to bytes and upload to Firebase Storage
  static Future<String?> uploadBase64({
    required String base64Str,
    required String storagePath,
  }) async {
    try {
      String cleanBase64 = base64Str.trim();
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',')[1];
      }
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
      final bytes = base64Decode(cleanBase64);
      return await uploadBytes(bytes: bytes, storagePath: storagePath);
    } catch (e) {
      if (kDebugMode) {
        print("ImageService.uploadBase64 error: $e");
      }
      return null;
    }
  }

  /// Pick image from camera, compress, and automatically upload to Firebase Storage
  static Future<String?> pickAndUploadImage({
    required ImageSource source,
    required String folder,
    String? customFileName,
    BuildContext? context,
    double maxWidth = 800,
    double maxHeight = 800,
    int imageQuality = 70,
  }) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final fileName = customFileName ?? 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final storagePath = '$folder/$fileName';
        
        // Upload to Firebase Storage
        final downloadUrl = await uploadBytes(
          bytes: bytes,
          storagePath: storagePath,
          contentType: 'image/jpeg',
        );

        if (downloadUrl != null) {
          return downloadUrl;
        }

        // Fallback to local Base64 only if offline/error
        final base64Str = base64Encode(bytes);
        return "data:image/jpeg;base64,$base64Str";
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error picking/uploading image: $e");
      }
    }
    return null;
  }

  /// Pick image from camera (with optional direct storage upload)
  static Future<String?> pickImageFromCamera({
    BuildContext? context,
    String? uploadFolder,
    double maxWidth = 800,
    double maxHeight = 800,
    int imageQuality = 70,
  }) async {
    if (uploadFolder != null && uploadFolder.isNotEmpty) {
      return pickAndUploadImage(
        source: ImageSource.camera,
        folder: uploadFolder,
        context: context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final base64Str = base64Encode(bytes);
        return "data:image/jpeg;base64,$base64Str";
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error picking image from camera: $e");
      }
    }
    return null;
  }

  /// Pick image from gallery (with optional direct storage upload)
  static Future<String?> pickImageFromGallery({
    BuildContext? context,
    String? uploadFolder,
    double maxWidth = 800,
    double maxHeight = 800,
    int imageQuality = 70,
  }) async {
    if (uploadFolder != null && uploadFolder.isNotEmpty) {
      return pickAndUploadImage(
        source: ImageSource.gallery,
        folder: uploadFolder,
        context: context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Str = base64Encode(bytes);
        return "data:image/jpeg;base64,$base64Str";
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error picking image from gallery: $e");
      }
    }
    return null;
  }
}
