import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../models/category_model.dart';

class LocalCacheService {
  LocalCacheService._privateConstructor();
  static final LocalCacheService instance = LocalCacheService._privateConstructor();

  Directory? _cacheDir;

  /// Get or initialize the cache directory at /storage/emulated/0/Android/data/com.Lucifax.KickDirty/cache/
  Future<Directory?> get _cacheDirectory async {
    if (kIsWeb) return null;
    if (_cacheDir != null) return _cacheDir;
    try {
      if (Platform.isAndroid) {
        final extDirs = await getExternalCacheDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          final dir = extDirs.first;
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          _cacheDir = dir;
          return _cacheDir;
        }
      }
      final appDocDir = await getApplicationDocumentsDirectory();
      final cachePath = '${appDocDir.path}/cache';
      final dir = Directory(cachePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return _cacheDir;
    } catch (e) {
      if (kDebugMode) print('Error getting cache dir: $e');
      return null;
    }
  }

  /// Save history page orders to local persistent cache
  Future<void> saveHistoryPageCache({
    required int page,
    required int itemsPerPage,
    required String statusFilter,
    required List<OrderModel> orders,
    required int totalCount,
  }) async {
    try {
      final key = 'history_p${page}_${itemsPerPage}_$statusFilter';
      final payload = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'totalCount': totalCount,
        'orders': orders.map((o) => o.toMap()).toList(),
      };
      final jsonString = jsonEncode(payload);

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cache_$key', jsonString);
      } else {
        final dir = await _cacheDirectory;
        if (dir != null) {
          final file = File('${dir.path}/$key.json');
          await file.writeAsString(jsonString, flush: true);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error saving history cache: $e');
    }
  }

  /// Read history page orders from local persistent cache (0ms instant return)
  Future<Map<String, dynamic>?> getHistoryPageCache({
    required int page,
    required int itemsPerPage,
    required String statusFilter,
  }) async {
    try {
      final key = 'history_p${page}_${itemsPerPage}_$statusFilter';
      String? jsonString;

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonString = prefs.getString('cache_$key');
      } else {
        final dir = await _cacheDirectory;
        if (dir != null) {
          final file = File('${dir.path}/$key.json');
          if (await file.exists()) {
            jsonString = await file.readAsString();
          }
        }
      }

      if (jsonString != null && jsonString.isNotEmpty) {
        final Map<String, dynamic> map = jsonDecode(jsonString);
        final int totalCount = map['totalCount'] as int? ?? 0;
        final List rawList = map['orders'] as List? ?? [];
        final orders = rawList
            .map((item) => OrderModel.fromMap(item as Map<String, dynamic>, item['id'] ?? ''))
            .toList();

        return {
          'totalCount': totalCount,
          'orders': orders,
        };
      }
    } catch (e) {
      if (kDebugMode) print('Error reading history cache: $e');
    }
    return null;
  }

  /// Save any JSON serializable generic cache
  Future<void> saveGenericCache(String key, dynamic data) async {
    try {
      final jsonString = jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      });

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cache_$key', jsonString);
      } else {
        final dir = await _cacheDirectory;
        if (dir != null) {
          final file = File('${dir.path}/$key.json');
          await file.writeAsString(jsonString, flush: true);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error saving generic cache $key: $e');
    }
  }

  /// Read any JSON serializable generic cache
  Future<dynamic> getGenericCache(String key) async {
    try {
      String? jsonString;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonString = prefs.getString('cache_$key');
      } else {
        final dir = await _cacheDirectory;
        if (dir != null) {
          final file = File('${dir.path}/$key.json');
          if (await file.exists()) {
            jsonString = await file.readAsString();
          }
        }
      }

      if (jsonString != null && jsonString.isNotEmpty) {
        final map = jsonDecode(jsonString);
        return map['data'];
      }
    } catch (e) {
      if (kDebugMode) print('Error reading generic cache $key: $e');
    }
    return null;
  }

  /// Complete wipe of all cache files in Android/data/com.Lucifax.KickDirty/cache/
  /// Triggered automatically on Logout
  Future<void> clearAllCache() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys().where((k) => k.startsWith('cache_')).toList();
        for (var k in keys) {
          await prefs.remove(k);
        }
      } else {
        final dir = await _cacheDirectory;
        if (dir != null && await dir.exists()) {
          final List<FileSystemEntity> entities = await dir.list().toList();
          for (var entity in entities) {
            if (entity is File) {
              await entity.delete();
            }
          }
        }
      }
      if (kDebugMode) print('All local cache wiped successfully on logout.');
    } catch (e) {
      if (kDebugMode) print('Error clearing cache on logout: $e');
    }
  }
}
