import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ImageService {
  static final ImagePicker _picker = ImagePicker();

  // Pick image from camera and convert to compressed Base64 string
  static Future<String?> pickImageFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 600, // Keep image size reasonable
        maxHeight: 600,
        imageQuality: 70, // Compress to keep under Firestore 1MB limits
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final base64Str = base64Encode(bytes);
        return "data:image/jpeg;base64,$base64Str";
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error picking image: $e");
      }
    }
    return null;
  }

  // Pick image from gallery and convert to compressed Base64 string
  static Future<String?> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 70,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Str = base64Encode(bytes);
        return "data:image/jpeg;base64,$base64Str";
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error picking image: $e");
      }
    }
    return null;
  }
}
