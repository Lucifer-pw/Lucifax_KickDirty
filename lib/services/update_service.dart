import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final bool isForceUpdate;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.isForceUpdate,
    required this.hasUpdate,
  });
}

class UpdateService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Compare version strings (e.g., "1.0.0" and "1.0.1")
  bool _isNewerVersion(String current, String latest) {
    try {
      List<String> currentParts = current.split('+')[0].split('.');
      List<String> latestParts = latest.split('+')[0].split('.');

      for (int i = 0; i < latestParts.length; i++) {
        int latestPart = int.parse(latestParts[i]);
        int currentPart = i < currentParts.length ? int.parse(currentParts[i]) : 0;

        if (latestPart > currentPart) return true;
        if (latestPart < currentPart) return false;
      }
    } catch (e) {
      if (kDebugMode) print("Error parsing versions: $e");
    }
    return false;
  }

  // Check for updates
  Future<UpdateInfo> checkForUpdate() async {
    try {
      // Get current local version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      // Get remote version from Firestore
      DocumentSnapshot doc = await _db.collection('app_config').doc('version_info').get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String latestVersion = data['latestVersion'] ?? currentVersion;
        String downloadUrl = data['downloadUrl'] ?? '';
        bool isForceUpdate = data['isForceUpdate'] ?? false;

        bool hasUpdate = _isNewerVersion(currentVersion, latestVersion);

        return UpdateInfo(
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          isForceUpdate: isForceUpdate,
          hasUpdate: hasUpdate,
        );
      }
    } catch (e) {
      if (kDebugMode) print("Failed to check for updates: $e");
    }

    // Default return if document not found or error
    return UpdateInfo(
      latestVersion: '1.0.0',
      downloadUrl: '',
      isForceUpdate: false,
      hasUpdate: false,
    );
  }
}
