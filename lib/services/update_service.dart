import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String releaseUrl;
  final bool isForceUpdate;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseUrl,
    required this.isForceUpdate,
    required this.hasUpdate,
  });
}

class UpdateService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Compare version strings and build numbers
  bool _isNewerVersion(
      String currentVer, String currentBuild, String latestVer, String latestBuild) {
    try {
      // 1. Compare version parts (major.minor.patch)
      List<String> currentParts = currentVer.split('.');
      List<String> latestParts = latestVer.split('.');

      int maxLen = currentParts.length > latestParts.length
          ? currentParts.length
          : latestParts.length;

      for (int i = 0; i < maxLen; i++) {
        int currentPart = i < currentParts.length ? (int.tryParse(currentParts[i]) ?? 0) : 0;
        int latestPart = i < latestParts.length ? (int.tryParse(latestParts[i]) ?? 0) : 0;

        if (latestPart > currentPart) return true;
        if (latestPart < currentPart) return false;
      }

      // 2. If version parts are equal, compare build numbers
      int currentBuildNum = int.tryParse(currentBuild) ?? 0;
      int latestBuildNum = int.tryParse(latestBuild) ?? 0;
      return latestBuildNum > currentBuildNum;
    } catch (e) {
      if (kDebugMode) print("Error parsing versions: $e");
    }
    return false;
  }

  // Fetch latest release via GitHub API
  Future<Map<String, dynamic>?> _getLatestReleaseFromApi() async {
    final client = HttpClient();
    try {
      // Set connection timeout to 5 seconds
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
          Uri.parse('https://api.github.com/repos/Lucifer-pw/Lucifax_KickDirty/releases/latest'));
      request.headers.set('User-Agent', 'lucifax-kickdirty-app');
      final response = await request.close();

      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching latest release via API: $e");
    } finally {
      client.close();
    }
    return null;
  }

  // Fetch latest release tag via GitHub webpage redirect (not rate-limited)
  Future<String?> _getLatestTagNameFromRedirect() async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
          Uri.parse('https://github.com/Lucifer-pw/Lucifax_KickDirty/releases/latest'));
      request.followRedirects = false; // Do not follow redirects automatically
      final response = await request.close();

      final location = response.headers.value('location');
      if (location != null && location.contains('/releases/tag/')) {
        final parts = location.split('/releases/tag/');
        if (parts.length > 1) {
          return Uri.decodeComponent(parts[1]);
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching latest tag via redirect: $e");
    } finally {
      client.close();
    }
    return null;
  }

  // Check for updates
  Future<UpdateInfo> checkForUpdate() async {
    try {
      // Get current local version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      String currentBuild = packageInfo.buildNumber;

      if (kDebugMode) {
        print("Current version: $currentVersion, Build: $currentBuild");
      }

      String latestVersion = currentVersion;
      String latestBuild = currentBuild;
      String downloadUrl = '';
      String releaseUrl = 'https://github.com/Lucifer-pw/Lucifax_KickDirty/releases/latest';

      // 1. Try GitHub API
      final apiRelease = await _getLatestReleaseFromApi();
      if (apiRelease != null) {
        if (kDebugMode) print("Found latest release from GitHub API");
        String tag = apiRelease['tag_name'] ?? '';
        if (tag.startsWith('v')) {
          tag = tag.substring(1);
        }
        List<String> tagParts = tag.split('+');
        latestVersion = tagParts[0];
        latestBuild = tagParts.length > 1 ? tagParts[1] : '0';

        // Find APK download URL
        if (apiRelease['assets'] != null && apiRelease['assets'] is List) {
          for (var asset in apiRelease['assets']) {
            String assetName = asset['name'] ?? '';
            if (assetName.endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] ?? '';
              break;
            }
          }
        }
        if (downloadUrl.isEmpty) {
          downloadUrl = apiRelease['html_url'] ?? '';
        }
        releaseUrl = apiRelease['html_url'] ?? 'https://github.com/Lucifer-pw/Lucifax_KickDirty/releases/latest';
      } else {
        // 2. Try GitHub Redirect (as API fallback)
        if (kDebugMode) print("GitHub API failed or rate-limited. Trying Redirect method...");
        final tag = await _getLatestTagNameFromRedirect();
        if (tag != null) {
          if (kDebugMode) print("Found latest release tag from Redirect: $tag");
          String cleanTag = tag;
          if (cleanTag.startsWith('v')) {
            cleanTag = cleanTag.substring(1);
          }
          List<String> tagParts = cleanTag.split('+');
          latestVersion = tagParts[0];
          latestBuild = tagParts.length > 1 ? tagParts[1] : '0';

          // Encode tag for URL compatibility (replace '+' with '%2B')
          String encodedTag = tag.replaceAll('+', '%2B');
          downloadUrl =
              'https://github.com/Lucifer-pw/Lucifax_KickDirty/releases/download/$encodedTag/lucifax-kickdirty-v$latestVersion.apk';
          releaseUrl = 'https://github.com/Lucifer-pw/Lucifax_KickDirty/releases/tag/$encodedTag';
        } else {
          // 3. Fallback to Firestore
          if (kDebugMode) print("GitHub methods failed. Trying Firestore fallback...");
          DocumentSnapshot doc =
              await _db.collection('app_config').doc('version_info').get();

          if (doc.exists) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            String firestoreLatest = data['latestVersion'] ?? currentVersion;
            downloadUrl = data['downloadUrl'] ?? '';
            releaseUrl = data['releaseUrl'] ?? 'https://github.com/Lucifer-pw/Lucifax_KickDirty/releases/latest';

            // Split version and build from Firestore if in X.Y.Z+B format
            List<String> firestoreParts = firestoreLatest.split('+');
            latestVersion = firestoreParts[0];
            latestBuild = firestoreParts.length > 1 ? firestoreParts[1] : '0';
          }
        }
      }

      bool hasUpdate = _isNewerVersion(currentVersion, currentBuild, latestVersion, latestBuild);

      if (kDebugMode) {
        print("Latest version: $latestVersion, Build: $latestBuild");
        print("Has update: $hasUpdate, Download URL: $downloadUrl, Release URL: $releaseUrl");
      }

      return UpdateInfo(
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseUrl: releaseUrl,
        isForceUpdate: false,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      if (kDebugMode) print("Failed to check for updates: $e");
    }

    // Default return if error
    return UpdateInfo(
      latestVersion: '1.0.0',
      downloadUrl: '',
      releaseUrl: 'https://github.com/Lucifer-pw/Lucifax_KickDirty/releases/latest',
      isForceUpdate: false,
      hasUpdate: false,
    );
  }
}
