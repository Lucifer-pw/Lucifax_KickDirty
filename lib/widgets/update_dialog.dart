import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/update_service.dart';
import '../theme.dart';

// ==========================================
// IN-APP UPDATE DIALOG WITH DOWNLOAD + INSTALL
// Shared widget used by both Admin and Customer screens
// ==========================================
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final bool isForceUpdate;

  const UpdateDialog({
    Key? key,
    required this.updateInfo,
    required this.isForceUpdate,
  }) : super(key: key);

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();

  /// Helper method to check for updates and show dialog
  static Future<void> checkAndShow(BuildContext context) async {
    final updateService = UpdateService();
    try {
      final updateInfo = await updateService.checkForUpdate();
      if (updateInfo.hasUpdate && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: !updateInfo.isForceUpdate,
          builder: (context) {
            return UpdateDialog(
              updateInfo: updateInfo,
              isForceUpdate: updateInfo.isForceUpdate,
            );
          },
        );
      }
    } catch (_) {
      // Fail silently
    }
  }
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusText = '';
  bool _downloadFailed = false;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusText = 'Memulai unduhan...';
      _downloadFailed = false;
    });

    try {
      final url = widget.updateInfo.downloadUrl;
      if (url.isEmpty) throw Exception('URL unduhan kosong');

      // Get temp directory for saving the APK
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/kickdirty-update.apk';
      final file = File(filePath);

      // Delete old file if exists
      if (await file.exists()) {
        await file.delete();
      }

      // Download file using HttpClient (follows redirects by default)
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 15);
      
      final request = await httpClient.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'lucifax-kickdirty-app');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      int receivedBytes = 0;
      final sink = file.openWrite();

      await for (var chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0) {
          setState(() {
            _downloadProgress = receivedBytes / contentLength;
            final mb = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (contentLength / 1024 / 1024).toStringAsFixed(1);
            _statusText = 'Mengunduh... $mb MB / $totalMb MB';
          });
        } else {
          setState(() {
            final mb = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
            _statusText = 'Mengunduh... $mb MB';
          });
        }
      }

      await sink.flush();
      await sink.close();
      httpClient.close();

      setState(() {
        _statusText = 'Unduhan selesai! Membuka installer...';
      });

      // Open the APK for installation
      final result = await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
      
      if (result.type != ResultType.done) {
        setState(() {
          _statusText = 'Gagal membuka installer: ${result.message}';
          _downloadFailed = true;
          _isDownloading = false;
        });
      } else {
        // Close the dialog after successfully opening installer
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() {
        _statusText = 'Gagal mengunduh: $e';
        _downloadFailed = true;
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update Aplikasi Tersedia!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isDownloading && !_downloadFailed)
            Text(
              'Versi baru (${widget.updateInfo.latestVersion}) telah dirilis.\nSilakan perbarui untuk melanjutkan.',
              textAlign: TextAlign.center,
            ),
          if (_isDownloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              backgroundColor: AppTheme.lightGray,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
            ),
            const SizedBox(height: 12),
            Text(
              _statusText,
              style: const TextStyle(fontSize: 12, color: AppTheme.textGray),
              textAlign: TextAlign.center,
            ),
          ],
          if (_downloadFailed) ...[
            const SizedBox(height: 8),
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(
              _statusText,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading) ...[
          if (!widget.isForceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Nanti', style: TextStyle(color: AppTheme.textGray)),
            ),
          ElevatedButton.icon(
            onPressed: _downloadAndInstall,
            icon: Icon(_downloadFailed ? Icons.refresh : Icons.system_update),
            label: Text(_downloadFailed ? 'Coba Lagi' : 'Update Sekarang'),
          ),
        ],
      ],
    );
  }
}
