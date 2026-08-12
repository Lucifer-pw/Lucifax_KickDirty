import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class AutoBackupService {
  static final AutoBackupService instance = AutoBackupService._();
  AutoBackupService._();

  Timer? _timer;
  bool _isPerformingBackup = false;

  final List<String> _collections = [
    'users',
    'orders',
    'customers',
    'services',
    'categories',
    'vouchers',
    'expenses',
    'app_config',
    'logistics_methods',
    'developer_billing',
    'developer_billing_invoices'
  ];

  /// Start scheduled background check for automatic backup
  void startChecking(String role) {
    // Client-side auto-backup is completely deprecated in favor of Google Apps Script
    // to guarantee 100% Rp 0 and zero internet egress cost.
    stopChecking();
    print("AutoBackup: Client-side auto-backup disabled (Handled by Cloud Google Apps Script).");
  }

  /// Stop the background check timer
  void stopChecking() {
    _timer?.cancel();
    _timer = null;
  }

  /// Perform the checks and run backup if due
  Future<void> checkAndRunBackup() async {
    if (_isPerformingBackup) return;

    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('developer_config')
          .get();

      if (!configDoc.exists) return;

      final data = configDoc.data();
      if (data == null) return;

      final bool enableAutoBackup = data['enableAutoBackup'] == true;
      if (!enableAutoBackup) return;

      final String? gdriveUrl = data['gdriveUrl'] as String?;
      if (gdriveUrl == null || gdriveUrl.trim().isEmpty) {
        print("AutoBackup: Skipped. Google Drive Web App URL is empty.");
        return;
      }

      final int autoBackupHour = data['autoBackupHour'] as int? ?? 2; // Default to 2 AM (Dini Hari)
      final Timestamp? lastAutoBackupTime = data['lastAutoBackupTime'] as Timestamp?;

      final DateTime now = DateTime.now();
      bool isDue = false;

      // Hitung waktu target untuk hari ini (misal hari ini jam 02:00)
      final DateTime todayTargetTime = DateTime(now.year, now.month, now.day, autoBackupHour);

      if (now.isAfter(todayTargetTime)) {
        if (lastAutoBackupTime == null) {
          isDue = true;
        } else {
          final lastBackupDateTime = lastAutoBackupTime.toDate();
          if (lastBackupDateTime.isBefore(todayTargetTime)) {
            isDue = true;
          }
        }
      } else {
        // Jika belum melewati jam target hari ini, periksa apakah backup kemarin sudah selesai
        final DateTime yesterdayTargetTime = todayTargetTime.subtract(const Duration(days: 1));
        if (lastAutoBackupTime == null) {
          isDue = true;
        } else {
          final lastBackupDateTime = lastAutoBackupTime.toDate();
          if (lastBackupDateTime.isBefore(yesterdayTargetTime)) {
            isDue = true;
          }
        }
      }

      if (isDue) {
        print("AutoBackup: Backup is due. Initiating background upload...");
        _isPerformingBackup = true;

        // 1. Distributed Lock: Update the Firestore timestamp FIRST to prevent concurrent runs by other active devices
        await FirebaseFirestore.instance
            .collection('app_config')
            .doc('developer_config')
            .update({
          'lastAutoBackupTime': Timestamp.fromDate(now),
        });

        // 2. Fetch all data
        final backupData = await generateBackupData();

        // 3. Upload to Google Drive Web App
        final payload = {
          'token': 'LucifaxKickDirtyBackupToken2026',
          'backupData': backupData,
        };

        final response = await http.post(
          Uri.parse(gdriveUrl),
          headers: {'Content-Type': 'text/plain'}, // Avoids CORS preflight OPTIONS block
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final resData = jsonDecode(response.body);
          if (resData['status'] == 'success') {
            print("AutoBackup: Success! Saved as: ${resData['fileName']}");
          } else {
            print("AutoBackup: Server rejected upload: ${resData['message']}");
          }
        } else {
          print("AutoBackup: Server responded with status code: ${response.statusCode}");
        }
      }
    } catch (e) {
      print("AutoBackup: Error during background auto-backup: $e");
    } finally {
      _isPerformingBackup = false;
    }
  }

  /// Exports all collections and serializes timestamps
  Future<Map<String, dynamic>> generateBackupData() async {
    final Map<String, dynamic> backup = {};
    final firestore = FirebaseFirestore.instance;

    for (final col in _collections) {
      try {
        final snap = await firestore.collection(col).get();
        final List<Map<String, dynamic>> docs = [];
        for (final doc in snap.docs) {
          final serializedData = _serializeTimestamps(doc.data());
          docs.add({
            'id': doc.id,
            'data': serializedData,
          });
        }
        backup[col] = docs;
      } catch (e) {
        print("AutoBackup: Failed to fetch collection $col: $e");
        throw Exception("Akses Ditolak (Bagian: $col)");
      }
    }
    return backup;
  }

  Map<String, dynamic> _serializeTimestamps(Map<dynamic, dynamic> data) {
    final Map<String, dynamic> result = {};
    data.forEach((key, value) {
      final String keyStr = key.toString();
      if (value is Timestamp) {
        result[keyStr] = {
          '_type': 'Timestamp',
          'seconds': value.seconds,
          'nanoseconds': value.nanoseconds,
        };
      } else if (value is Map) {
        result[keyStr] = _serializeTimestamps(value);
      } else if (value is List) {
        result[keyStr] = value.map((item) {
          if (item is Map) {
            return _serializeTimestamps(item);
          }
          return item;
        }).toList();
      } else {
        result[keyStr] = value;
      }
    });
    return result;
  }
}
