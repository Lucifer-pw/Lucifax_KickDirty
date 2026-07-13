import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImageService {
  static final ImagePicker _picker = ImagePicker();

  // Pick image from camera and convert to compressed Base64 string
  static Future<String?> pickImageFromCamera({
    BuildContext? context,
    double maxWidth = 800,
    double maxHeight = 800,
    int imageQuality = 70,
  }) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final sizeInBytes = bytes.length;
        if (sizeInBytes > 800 * 1024) {
          if (context != null && context.mounted) {
            _showSizeWarningDialog(context, sizeInBytes);
          }
          return null;
        }
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
  static Future<String?> pickImageFromGallery({
    BuildContext? context,
    double maxWidth = 800,
    double maxHeight = 800,
    int imageQuality = 70,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final sizeInBytes = bytes.length;
        if (sizeInBytes > 800 * 1024) {
          if (context != null && context.mounted) {
            _showSizeWarningDialog(context, sizeInBytes);
          }
          return null;
        }
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

  static void _showSizeWarningDialog(BuildContext context, int sizeInBytes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Ukuran Foto Terlalu Besar'),
            ],
          ),
          content: Text(
            'Ukuran foto setelah dikompres adalah ${(sizeInBytes / 1024).toStringAsFixed(1)} KB.\n\n'
            'Batas maksimal per foto adalah 800 KB agar dapat disimpan di database. '
            'Silakan pilih foto lain atau ambil foto dengan resolusi kamera yang lebih rendah.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
