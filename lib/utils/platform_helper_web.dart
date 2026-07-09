import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';

String getDeviceDetails() {
  final userAgent = html.window.navigator.userAgent;
  final platform = html.window.navigator.platform ?? '';
  return 'Web ($platform) - $userAgent';
}

Future<String?> getDeviceGpsLocation() async {
  try {
    final position = await html.window.navigator.geolocation.getCurrentPosition();
    final lat = position.coords?.latitude;
    final lng = position.coords?.longitude;
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
  } catch (e) {
    // Geolocation error or permission denied
  }
  return null;
}

void saveBackupFile(String content, String fileName) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = fileName;
  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);
  html.Url.revokeObjectUrl(url);
}
